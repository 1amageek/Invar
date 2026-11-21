#!/usr/bin/env python3
"""Use unmodified Explorer SDK/service in an owned temporary workspace."""
import argparse
import hashlib
import json
import os
import select
from pathlib import Path
import shutil
import signal
import sqlite3
import socket
import sys
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--binary", default=str(ROOT / ".build/debug/inver"))
parser.add_argument("--host", default=str(ROOT / "Tests/Fixtures/ExplorerHost/.build/debug/InvarExplorerHost"))
parser.add_argument("--toolchain", help="Explicit existing pinned Formal toolchain; enables real TLC/Lean worker and read checks")
parser.add_argument("--native-recovery", action="store_true", help="Kill actual daemon during a journaled native harness and verify physical recovery")
parser.add_argument("--native", action="store_true", help="Verify actual native modules/oracles/sandbox/fuzz under host authority")
parser.add_argument("--compiler", type=Path)
parser.add_argument("--sdk", type=Path)
parser.add_argument("--tools-directory", type=Path)
parser.add_argument("--actions", action="store_true", help="Verify confirmed Provider Action admission, original SDK receipt and published view")
parser.add_argument("--watch", action="store_true", help="Verify daemon-owned watch after client exit, source edit, crash/restart and explicit stop")
parser.add_argument("--frontends", action="store_true", help="Verify actual CLI and local Swift SDK MCP relay against the same daemon")
args = parser.parse_args()
if args.native_recovery:
    args.native = True
binary, host = Path(args.binary).resolve(), Path(args.host).resolve()
checks = []
demands = {}


def wait_for(test, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = test()
        if value:
            return value
        time.sleep(0.5)
    raise AssertionError("Private integration condition timed out")


def axes(run):
    return {item["jobID"]: {key: item.get(key) for key in ["execution", "outcome", "diagnosticCode", "detail", "resources"]} for item in run["attempts"]}


with tempfile.TemporaryDirectory(prefix="invar-real-explorer-") as directory:
    root = Path(directory).resolve()
    workspace = root / "workspace"
    workspace.mkdir()
    (workspace / "Demo.swift").write_text("public func compute(_ value: Int64) -> Int64 { return value + 1 }\n")
    contracts = {"schemaVersion": 1, "architecture": [{"id": "cycle", "kind": "cycle", "approved": True}]}
    entries = []
    if args.toolchain:
        oracle = json.dumps({"schemaVersion": 1, "fuel": 64, "cases": [{"name": "positive", "entry": "compute", "arguments": ["2"], "expected": {"status": "returned", "value": "4"}}]}, separators=(",", ":")).encode()
        (workspace / "oracle.json").write_bytes(oracle)
        entries = [{"path": "oracle.json", "digest": hashlib.sha256(oracle).hexdigest(), "byteCount": len(oracle)}]
        contracts["formal"] = [{"id": "model", "source": "Demo.swift", "mode": "finite", "specification": "oracle.json", "toolchain": str(Path(args.toolchain).resolve()), "approved": True, "required": True, "acceptUnvalidatedModel": True, "memoryMiB": 4096}]
    listener = None
    if args.native:
        assert not (args.toolchain or args.watch or args.actions or args.frontends), "Native acceptance owns an independent bounded run"
        assert args.compiler and args.sdk and args.tools_directory, "Explicit existing native compiler/SDK/linker roots are required"
        from native_fixture import create_native_fixture
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        listener.settimeout(0.1)
        contracts, entries = create_native_fixture(workspace, root, listener, args.compiler, args.sdk, args.tools_directory)
        if args.native_recovery:
            native = next(item for item in contracts["native"] if item["id"] == "native")
            harness = b'import Darwin\n@main struct Wait { static func main() { sleep(3600) } }\n'
            (workspace / "Harness.swift").write_bytes(harness)
            contracts = {"schemaVersion": 1, "native": [native]}
            entries = [{"path": "Harness.swift", "digest": hashlib.sha256(harness).hexdigest(), "byteCount": len(harness)}]
        contracts["architecture"] = [{"id": "cycle", "kind": "cycle", "approved": True}]
    (workspace / "contracts.json").write_text(json.dumps(contracts))
    base = ["--workspace", str(workspace), "--state", str(root / "invar-state")]
    mcp_processes = []
    explorer = None
    invar_pid = None
    identity = None
    active_credential = "agent"
    source_identity = None
    log = (root / "explorer.log").open("w")

    def run(argv, expected=0):
        result = subprocess.run([str(value) for value in argv], capture_output=True, text=True, timeout=20)
        try:
            value = json.loads(result.stdout)
        except json.JSONDecodeError:
            raise AssertionError((argv[:2], result.returncode, result.stderr[:1024], result.stdout[:1024]))
        assert result.returncode == expected, (argv[:2], result.returncode, value)
        return value

    def daemon(action, *options, expected=0):
        return run([binary, "daemon", action, *base, *options], expected=expected)

    def rpc(method, params=None):
        return run([host, "rpc", workspace, method, json.dumps(params or {}, separators=(",", ":"))])

    def client(command, payload, credential=None, key="query", expected=0):
        credential = credential or active_credential
        return run([host, command, workspace, root / "invar-state", root / (credential + ".secret"), key, json.dumps(payload, separators=(",", ":"))], expected=expected)

    def operation(request, key):
        receipt = client("request", request, key=key)
        demands[key] = receipt["operationID"]
        result = wait_for(lambda: terminal(receipt["operationID"]), seconds=600 if args.native else 60)
        assert result["state"] == "completed", result
        return result["resultID"]

    def terminal(demand_id):
        value = client("query", {"demand": {"id": demand_id}})
        return value if value["state"] not in ("queued", "running", "cancelling") else None

    def published():
        value = client("query", {"publication": {"demandID": demands["run"]}})
        if value is not None:
            assert value["state"] not in ("blocked", "superseded"), value
            return value if value["state"] == "committed" else None
        return None

    def index():
        job = rpc("workspace.index")["jobID"]
        def indexed():
            value = rpc("workspace.index.result", {"jobID": job})
            assert value["state"] != "failed", value
            return value if value["state"] == "completed" else None
        wait_for(indexed)
        # Settle the source owner's independent file event after explicit index.
        time.sleep(0.3)
        return rpc("workspace.status")["snapshotID"]

    try:
        source_identity = run([host, "identity", workspace])
        explorer = subprocess.Popen([str(host), "serve", str(workspace)], stdout=log, stderr=log, start_new_session=True)
        socket_path = Path("/tmp") / ("ae-" + str(os.getuid()) + "-" + source_identity["workspaceID"][-24:]) / "rpc.sock"
        wait_for(socket_path.exists)
        index()
        identity = daemon("identity")
        configuration_digest = run([host, "configuration", workspace, "contracts.json"])["digest"]
        policy = {"workspaceID": identity["workspaceID"], "engineIdentity": identity["engineIdentity"], "revision": 1,
                  "peers": [{"binaryDigest": source_identity["binaryDigest"], "capabilities": ["read", "sourceValues", "changes", "planning", "verification", "watching"]}, {"binaryDigest": identity["clientBinaryDigest"], "capabilities": ["read", "sourceValues", "changes", "planning", "verification", "watching"]}],
                  "approvals": [{"configurationDigest": configuration_digest, "entries": entries}],
                  "sessionSeconds": 60, "principalSeconds": 900 if args.native else 120, "maximumSessions": 128,
                  "maximumConnections": 4, "maximumEnvelopeSeconds": 600 if args.native else 60}
        policy_path = root / "policy.json"
        policy_path.write_text(json.dumps(policy))
        daemon("start", "--policy", policy_path, "--contracts", "contracts.json")
        runtime = Path("/tmp") / ("invar-" + str(os.getuid()) + "-" + identity["workspaceID"][-24:])
        invar_pid = json.loads((runtime / "host-control.json").read_text())["processID"]
        pending = wait_for(lambda: next((value for value in rpc("extensions.pending") if value["manifest"]["extensionID"] == "invar"), None))
        assert pending["peer"]["processID"] == invar_pid
        rpc("extensions.approve", {"id": pending["id"], "permissions": pending["manifest"]["requestedPermissions"]})
        wait_for(lambda: daemon("status")["state"] == "ready")
        checks.append("real pinned Explorer host approves the actual independently running Invar Provider")
        claim = {"intent": "Update computation", "paths": ["Demo.swift"], "entityIDs": [], "expectedFiles": []}
        change_id = operation({"openChange": {"claim": claim, "configurationPath": "contracts.json"}}, "baseline")
        baseline = client("query", {"change": {"id": change_id}})
        assert baseline["state"] == "open" and baseline["baseline"]["dependencyStatus"] == "unknown"
        (workspace / "Demo.swift").write_text("public func compute(_ value: Int64) -> Int64 { return value + 2 }\n")
        index()
        revision_id = operation({"sealChange": {"changeID": change_id}}, "seal")
        revision = client("query", {"changeRevision": {"id": revision_id}})
        assert revision["before"] == baseline["baseline"]
        assert [value["path"] for value in revision["delta"]["files"]] == ["Demo.swift"]
        checks.append("separate SDK client captures and seals exact original bytes through one authenticated source lease")
        budget = {"maximumWorkers": 2, "memoryMiB": 4096, "timeoutSeconds": 50, "runTimeoutSeconds": 60,
                  "maximumOutputBytes": 8388608, "maximumProcesses": 8, "maximumCPUSeconds": 30, "maximumWorkspaceBytes": 536870912}
        if args.native:
            budget.update(timeoutSeconds=180, runTimeoutSeconds=480, maximumCPUSeconds=150)
        plan_id = operation({"preparePlan": {"configurationPath": "contracts.json", "changeRevisionID": revision_id, "budget": budget}}, "plan")
        plan = client("query", {"plan": {"id": plan_id}})
        assert plan["input"] == revision["after"] and plan["configurationDigest"] == configuration_digest
        if args.actions:
            source_manifest = rpc("inputs.manifest", {"snapshotID": plan["input"]["snapshotID"]})
            binding = {"workspaceID": identity["workspaceID"], "snapshotID": plan["input"]["snapshotID"], "inputManifestDigest": source_manifest["inputManifestDigest"], "entityIDs": [], "factIDs": []}
            action_generations = 1
            def confirm_verify_action():
                prepared = rpc("actions.prepare", {"registrationID": pending["id"], "actionID": "verify", "binding": binding, "arguments": {"planID": plan_id, "changeRevisionID": revision_id}})["intent"]
                rpc("actions.confirm", {"token": prepared["authorizationToken"], "requestFingerprint": prepared["requestFingerprint"]})
                return prepared

            def summary_for(request_id):
                return client("query", {"providerAction": {"id": request_id}})

            def running_action(request_id):
                value = summary_for(request_id)
                assert value is None or value.get("operationState") not in ("failed", "cancelled", "completed"), value
                return value if value is not None and value.get("operationState") == "running" else None

            if args.toolchain:
                cancelled_intent = confirm_verify_action()
                cancelled_running = wait_for(lambda: running_action(cancelled_intent["requestID"]))
                parent_source = wait_for(lambda: next((item for item in rpc("extensions.view")["actions"] if item["requestID"] == cancelled_intent["requestID"] and item.get("runID")), None))
                cancellation = rpc("actions.prepare", {"registrationID": pending["id"], "actionID": "cancel", "binding": binding, "arguments": {"requestID": cancelled_intent["requestID"], "jobID": cancelled_running["jobID"], "runID": parent_source["runID"]}})["intent"]
                rpc("actions.confirm", {"token": cancellation["authorizationToken"], "requestFingerprint": cancellation["requestFingerprint"]})
                wait_for(lambda: value if (value := summary_for(cancelled_intent["requestID"])) and value.get("operationState") == "cancelled" else None)
                cancelled_by = wait_for(lambda: value if (value := summary_for(cancellation["requestID"])) and value.get("operationState") == "completed" else None)
                assert cancelled_by["resultID"] == cancelled_running["jobID"]
                checks.append("confirmed cancellation resumes only the original Provider principal and waits for the owned real tool worker to stop")

                interrupted_intent = confirm_verify_action()
                interrupted_running = wait_for(lambda: running_action(interrupted_intent["requestID"]))
                def live_owned_worker():
                    for marker in (root / "invar-state").rglob("worker-identity.json"):
                        value = json.loads(marker.read_text())
                        if value["parentPID"] != invar_pid:
                            continue
                        try:
                            os.kill(value["pid"], 0)
                            return value
                        except ProcessLookupError:
                            pass
                    return None
                worker = wait_for(live_owned_worker)
                prior_epoch = daemon("status")["epoch"]
                os.kill(invar_pid, signal.SIGKILL)
                time.sleep(0.3)
                daemon("start", "--policy", policy_path, "--contracts", "contracts.json")
                invar_pid = json.loads((runtime / "host-control.json").read_text())["processID"]
                wait_for(lambda: daemon("status")["state"] == "ready")
                assert daemon("status")["epoch"] != prior_epoch
                interrupted = wait_for(lambda: value if (value := summary_for(interrupted_intent["requestID"])) and value.get("operationState") in ("interrupted", "notStarted") else None)
                assert interrupted["jobID"] == interrupted_running["jobID"] and interrupted.get("resultID") is None
                wait_for(lambda: next((item for item in rpc("extensions.view")["actions"] if item["requestID"] == interrupted_intent["requestID"] and item["state"] == "failed"), None))
                time.sleep(1)
                assert len(rpc("extensions.view")["attempts"]) == 2
                assert live_owned_worker() is None
                checks.append("SIGKILL during the actual tool worker preserves the original accepted SDK job, reports interrupted, and creates no replacement execution or generation")
                action_generations = 3
            prepared_action = rpc("actions.prepare", {"registrationID": pending["id"], "actionID": "verify", "binding": binding, "arguments": {"planID": plan_id, "changeRevisionID": revision_id}})
            intent = prepared_action["intent"]
            confirmation = {"token": intent["authorizationToken"], "requestFingerprint": intent["requestFingerprint"]}
            original_dispatch = rpc("actions.confirm", confirmation)
            assert rpc("actions.confirm", confirmation)["intent"]["requestID"] == intent["requestID"]

            def action_summary(terminal_only=True):
                value = client("query", {"providerAction": {"id": intent["requestID"]}})
                if value is None:
                    return None
                assert value["state"] != "outcomeUnknown", value
                if terminal_only and value.get("operationState") in (None, "queued", "running", "cancelling"):
                    return None
                return value

            completed_action = wait_for(action_summary, seconds=60)
            assert completed_action["operationState"] == "completed", completed_action
            action_job = completed_action["jobID"]
            assert action_job and action_job != intent["requestID"]
            action_result = client("query", {"runRecord": {"id": completed_action["resultID"]}})
            print(json.dumps({"phase": "provider-action", "axes": axes(action_result)}),file=sys.stderr,flush=True)
            assert all(item["execution"] == "completed" for item in action_result["attempts"]), axes(action_result)
            def action_published():
                value = client("query", {"publication": {"demandID": action_job}})
                assert value is None or value["state"] not in ("blocked", "superseded"), value
                return value if value is not None and value["state"] == "committed" else None
            action_publication = wait_for(action_published)
            assert action_publication["generation"] == action_generations, action_publication
            assert action_publication["view"] == completed_action["view"]
            wait_for(lambda: next((item for item in rpc("extensions.view")["actions"] if item["requestID"] == intent["requestID"] and item["state"] == "completed"), None))
            completed_action = wait_for(lambda: value if (value := action_summary()) and value["state"] == "terminal" else None)
            repeated = rpc("actions.confirm", confirmation)
            assert repeated["receipt"]["jobID"] == action_job
            time.sleep(1)
            assert client("query", {"providerAction": {"id": intent["requestID"]}}) == completed_action
            assert len(rpc("extensions.view")["attempts"]) == action_generations
            checks.append("confirmed real Explorer Action uses concrete SDK job receipt, executes original sealed plan, and adopts exactly one publication generation")
            checks.append("repeated confirmation preserves the original job/result/view without another admission or generation")
        if args.native:
            refusal = client("request", {"verify": {"planID": plan_id, "changeRevisionID": revision_id}}, key="native-denied", expected=8)
            assert refusal["code"] == "POLICY_DENIED", refusal
            policy["revision"] = 2
            for peer in policy["peers"]:
                peer["capabilities"].append("nativeExecution")
            policy_path.write_text(json.dumps(policy))
            daemon("approve", "--policy", policy_path)
            active_credential = "native-authorized-agent"
            checks.append("configuration approval alone cannot execute native code; an actual host native grant and new scoped principal are required")
        if args.native_recovery:
            accepted = client("request", {"verify": {"planID": plan_id, "changeRevisionID": revision_id}}, key="native-interrupted")
            def native_harness():
                for marker in (root / "invar-state/runs").rglob("native-processes/*.json"):
                    value = json.loads(marker.read_text())
                    if value["terminal"] or not value.get("pid") or "-o" in value["arguments"] or not value["arguments"] or not str(value["arguments"][-1]).endswith("/harness"):
                        continue
                    try:
                        os.kill(value["pid"], 0)
                        return value
                    except ProcessLookupError:
                        pass
                return None
            launched = wait_for(native_harness, seconds=180)
            victim = launched["pid"]
            prior_epoch = daemon("status")["epoch"]
            os.kill(invar_pid, signal.SIGKILL)
            time.sleep(0.3)
            daemon("start", "--policy", policy_path, "--contracts", "contracts.json")
            invar_pid = json.loads((runtime / "host-control.json").read_text())["processID"]
            wait_for(lambda: daemon("status")["state"] == "ready")
            interrupted = wait_for(lambda: terminal(accepted["operationID"]))
            assert interrupted["state"] == "interrupted" and interrupted.get("resultID") is None, interrupted
            assert daemon("status")["epoch"] != prior_epoch
            def victim_gone():
                try:
                    os.kill(victim, 0)
                    return False
                except ProcessLookupError:
                    return True
            wait_for(victim_gone)
            db = sqlite3.connect("file:" + str(root / "invar-state/verification.sqlite") + "?mode=ro", uri=True)
            assert db.execute("select count(*) from heads where kind='reservation'").fetchone()[0] == 0
            assert db.execute("select count(*) from records where namespace='run'").fetchone()[0] == 0
            db.close()
            checks.append("SIGKILL during the actual isolated native harness is recovered through its real launch journal; original demand is interrupted without fabricated run")
            checks.append("native session is physically reaped and every owned scratch reservation is drained before ready admission")
            print(json.dumps({"checks": checks}, indent=2))
            raise SystemExit(0)
        run_id = operation({"verify": {"planID": plan_id, "changeRevisionID": revision_id}}, "run")
        result = client("query", {"runRecord": {"id": run_id}})
        if args.native:
            attempts = {item["jobID"]: item for item in result["attempts"]}
            for name in ["native", "isolation", "expected_trap"]:
                assert attempts[name]["execution"] == "completed" and attempts[name]["outcome"] == "holdsWithinScope", attempts[name]
                assert attempts[name]["resources"]["cpuSeconds"] > 0, attempts[name]
            assert attempts["unexpected_crash"]["outcome"] == "violatedWithinScope", attempts["unexpected_crash"]
            assert attempts["empty_oracle"]["execution"] == "toolError" and attempts["empty_oracle"]["diagnosticCode"] == "INVALID_NATIVE_ORACLE", attempts["empty_oracle"]
            fuzz = attempts["fuzz"]
            artifact = next(item for item in fuzz["artifacts"] if item["profile"] == "native-fuzz/1")
            blob = (root / "invar-state/artifacts" / artifact["id"] / "blob").read_bytes()
            assert len(blob) == artifact["byteCount"] and hashlib.sha256(blob).hexdigest() == artifact["sha256"]
            witness = json.loads(blob)
            assert witness["originalInput"] == "100" and witness["reducedInput"] == "7", witness
            assert not result["accepted"]
            try:
                unexpected, _ = listener.accept()
                unexpected.close()
                raise AssertionError("Sandbox reached the external listener")
            except TimeoutError:
                pass
            replay_id = operation({"verify": {"planID": plan_id, "changeRevisionID": revision_id, "replayOfRunID": run_id}}, "native-replay")
            replay = client("query", {"runRecord": {"id": replay_id}})
            assert replay["id"] != run_id and replay["planID"] == plan_id
            comparison = {item["jobID"]: {"original": [attempts[item["jobID"]]["execution"], attempts[item["jobID"]]["outcome"]], "replay": [item["execution"], item["outcome"]], "diagnostic": item.get("diagnosticCode"), "resources": item["resources"]} for item in replay["attempts"]}
            assert all(item["original"] == item["replay"] for item in comparison.values()), comparison
            checks.append("actual authenticated daemon executes captured two-module native DAG, expected trap, invalid/empty oracle and seeded fuzz with original100/reduced7 witness")
            checks.append("actual sandbox denies outside file, network, fork, setpgid and setsid; replay independently reproduces the sealed native/fuzz outcomes")
            print(json.dumps({"checks": checks}, indent=2))
            raise SystemExit(0)
        print(json.dumps({"phase": "ordinary-run", "axes": axes(result)}),file=sys.stderr,flush=True)
        assert all(value["execution"] == "completed" for value in result["attempts"]), axes(result)
        assert {value["domain"] for value in result["attempts"]} == ({"architecture", "generatedModel"} if args.toolchain else {"architecture"})
        assert plan["input"]["dependencyStatus"] == "unknown"
        publication = wait_for(lambda: published())
        first = client("query", {"currentView": {}})
        second = client("query", {"currentView": {}}, credential="second-agent")
        assert first == second and first is not None
        view = client("query", {"view": {"id": first["id"]}})
        assert view["input"]["workspaceID"] == identity["workspaceID"]
        checks.append("actual isolated static worker commits immutable evidence and two real clients read the same view reference")
        checks.append("upstream dependency unknown is preserved rather than upgraded by byte equality")
        external = rpc("extensions.view")
        visible = next(value for value in external["publications"] if value["providerID"] == "invar")
        contribution = next(value for value in visible["contributions"] if value["id"] == "invar:verification")
        assert publication["view"] == first
        assert contribution["data"]["metadata"]["viewDigest"] == first["sha256"]
        assert contribution["data"]["metadata"]["upstreamDependencyStatus"] == "unknown"
        assert visible["generation"] == publication["generation"]
        assert visible["applicability"] == "unknown"
        assert all(node["attributes"]["execution"] == "completed" for node in contribution["data"]["nodes"])
        checks.append("actual Provider generation/atomic graph publication matches both SDK clients' exact committed view digest")
        checks.append(run(["python3", ROOT / "Tools/check-schemas.py", "--store", root / "invar-state/verification.sqlite"]))
        if args.watch:
            assert not args.toolchain, "Run watch lifetime separately from the expensive tool fixture"
            watch_id = operation({"watch": {"configurationPath": "contracts.json", "budget": budget}}, "watch")

            def watch_ready(previous_view=None):
                record = client("query", {"watch": {"id": watch_id}})
                assert record["state"] == "active", record
                assert record.get("failure") is None, record
                return record if record["cycle"]["phase"] == "idle" and record.get("lastView") is not None and record["lastView"] != previous_view else None

            watched = wait_for(watch_ready)
            time.sleep(3.5)
            quiet = client("query", {"watch": {"id": watch_id}})
            assert quiet == watched, (watched, quiet)
            checks.append("daemon watch continues after submitting SDK process exits; quiet probes append no watch revisions")
            (workspace / "Demo.swift").write_text("public func compute(_ value: Int64) -> Int64 { return value + 3 }\n")
            index()
            changed = wait_for(lambda: watch_ready(watched["lastView"]))
            assert changed["lastPlanID"] != watched["lastPlanID"] and changed["lastRunID"] != watched["lastRunID"], changed
            checks.append("source event automatically prepares and verifies exact changed input under original fixed watch authority")
            prior_epoch = daemon("status")["epoch"]
            os.kill(invar_pid, signal.SIGKILL)
            time.sleep(0.3)
            daemon("start", "--policy", policy_path, "--contracts", "contracts.json")
            invar_pid = json.loads((runtime / "host-control.json").read_text())["processID"]
            wait_for(lambda: daemon("status")["state"] == "ready")
            assert daemon("status")["epoch"] != prior_epoch
            resumed = wait_for(lambda: watch_ready(changed["lastView"]))
            assert resumed["lastRunID"] == changed["lastRunID"], (changed, resumed)
            checks.append("SIGKILL/restart retains registration and reassociates identical complete scope without a replacement verification run")
            assert operation({"stopWatch": {"watchID": watch_id}}, "watch-stop") == watch_id
            stopped = client("query", {"watch": {"id": watch_id}})
            assert stopped["state"] == "stopped" and stopped["cycle"]["phase"] == "idle", stopped
            assert daemon("status")["watchCount"] == 0
            (workspace / "Demo.swift").write_text("public func compute(_ value: Int64) -> Int64 { return value + 4 }\n")
            index()
            time.sleep(1)
            assert client("query", {"watch": {"id": watch_id}}) == stopped
            checks.append("explicit watch stop awaits cleanup and source changes cannot create a new cycle afterward")
        if args.frontends:
            full_caps = "read,sourceValues,changes,planning,verification,watching"
            frontend_options = [*base, "--client-state", root / "profiles", "--client-profile", "frontends", "--capabilities", full_caps,
                                "--run-timeout", "60", "--timeout", "50", "--cpu-seconds", "30"]

            def cli(command, *options):
                return run([binary, command, *frontend_options, *options])

            assert cli("status")["workspaceID"] == identity["workspaceID"]
            cli_plan = cli("plan", "--contracts", "contracts.json", "--key", "cli-plan", "--wait", "true")
            assert cli_plan["state"] == "completed", cli_plan
            cli_run = cli("run", "--plan", cli_plan["resultID"], "--key", "cli-run", "--wait", "true")
            assert cli_run["state"] == "completed", cli_run
            assert cli("report", "--run", cli_run["resultID"])["runID"] == cli_run["resultID"]
            duplicate = cli("run", "--plan", cli_plan["resultID"], "--key", "cli-run", "--wait", "true")
            assert duplicate == cli_run
            assert cli("source-status")["input"]["workspaceID"] == identity["workspaceID"]
            confirmed_cli_publication = wait_for(lambda: (lambda item: item if item and item["state"] == "committed" else None)(cli("publication","--operation-id",cli_run["id"])))
            checks.append("actual thin CLI prepares/verifies through daemon; separate processes resume one principal and repeated key retains one original demand")

            buffers = {}

            def send(process, value):
                process.stdin.write((json.dumps(value) + "\n").encode())
                process.stdin.flush()

            def receive(process, identifier, seconds=20):
                deadline = time.monotonic() + seconds
                while time.monotonic() < deadline:
                    buffer = buffers.setdefault(process.pid, bytearray())
                    if b"\n" in buffer:
                        line, _, rest = buffer.partition(b"\n")
                        buffers[process.pid] = bytearray(rest)
                        message = json.loads(line)
                        assert message["jsonrpc"] == "2.0", message
                        if message.get("id") == identifier:
                            assert "error" not in message, message
                            return message["result"]
                        continue
                    ready, _, _ = select.select([process.stdout], [], [], max(0, deadline-time.monotonic()))
                    if not ready:
                        continue
                    chunk = os.read(process.stdout.fileno(), 65536)
                    assert chunk, (process.poll(), process.stderr.read().decode() if process.poll() is not None else "MCP closed early")
                    buffer.extend(chunk)
                    assert len(buffer) <= 1048576, "MCP response exceeded fixture frame bound"
                raise AssertionError("MCP response timed out")

            def start_mcp(readonly=False):
                options = [*frontend_options]
                if readonly:
                    options[options.index("--client-profile")+1] = "read-only"
                    options[options.index("--capabilities")+1] = "read"
                process = subprocess.Popen([str(binary), "mcp", *map(str, options)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
                mcp_processes.append(process)
                send(process, {"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Invar process fixture","version":"2"}}})
                initialized = receive(process,0)
                assert initialized["protocolVersion"] == "2025-11-25", initialized
                send(process, {"jsonrpc":"2.0","method":"notifications/initialized"})
                return process

            def call_mcp(process, identifier, name, arguments=None, error=False):
                send(process, {"jsonrpc":"2.0","id":identifier,"method":"tools/call","params":{"name":name,"arguments":arguments or {}}})
                result = receive(process,identifier)
                assert bool(result.get("isError")) == error, result
                if error:
                    return json.loads(result["content"][0]["text"])
                envelope = result["structuredContent"]
                assert envelope["schemaVersion"] == 2
                assert json.loads(result["content"][0]["text"]) == envelope
                return envelope["value"]

            def close_mcp(process):
                process.stdin.close()
                process.wait(timeout=15)
                assert process.returncode == 0, process.stderr.read().decode()
                assert not process.stdout.read(), "MCP EOF polluted stdout"

            reader = start_mcp(readonly=True)
            send(reader,{"jsonrpc":"2.0","id":1,"method":"tools/list"})
            names = {item["name"] for item in receive(reader,1)["tools"]}
            assert "invar_current_view" in names and "invar_run" not in names and "invar_formal_query" not in names
            assert call_mcp(reader,2,"invar_run",{"key":"denied","planID":cli_plan["resultID"]},error=True)["code"] == "POLICY_DENIED"
            assert call_mcp(reader,3,"invar_current_view",{"workspace":"/another/root"},error=True)["code"] == "INVALID_ARGUMENT"
            close_mcp(reader)
            relay = start_mcp()
            assert call_mcp(relay,1,"invar_current_view") == cli("current")
            assert call_mcp(relay,2,"invar_run",{"key":"bad-authority","planID":cli_plan["resultID"],"nativeExecutionAllowed":True},error=True)["code"] == "INVALID_ARGUMENT"
            receipt = call_mcp(relay,3,"invar_run",{"key":"mcp-run","planID":cli_plan["resultID"]})
            close_mcp(relay)
            completed = wait_for(lambda: (lambda value: value if value["state"] not in ("queued","running","cancelling") else None)(cli("operation","--operation-id",receipt["operationID"])))
            assert completed["state"] == "completed", completed
            assert cli("receipt","--envelope-id",receipt["id"]) == receipt
            checks.append("actual local Swift MCP SDK negotiates stdio; scope/schema errors reject escalation and EOF leaves the accepted daemon operation running")
            relay = start_mcp()
            watch_receipt = call_mcp(relay,1,"invar_watch",{"key":"mcp-watch","configurationPath":"contracts.json"})
            close_mcp(relay)
            watched_operation = wait_for(lambda: (lambda value: value if value["state"] not in ("queued","running","cancelling") else None)(cli("operation","--operation-id",watch_receipt["operationID"])))
            assert watched_operation["state"] == "completed", watched_operation
            watch_id = watched_operation["resultID"]
            def cli_watch_ready():
                value = cli("watch-status","--watch-id",watch_id)
                assert value["state"] == "active" and value.get("failure") is None, {"state": value["state"], "failure": value.get("failure"), "cycle": value["cycle"]}
                if value["cycle"].get("pendingDemandID"):
                    pending_operation = cli("operation","--operation-id",value["cycle"]["pendingDemandID"])
                    assert pending_operation["state"] not in ("failed","cancelled","interrupted","notStarted"), pending_operation
                return value.get("lastView")
            wait_for(cli_watch_ready, seconds=60)
            assert cli("watch-status","--watch-id",watch_id)["state"] == "active"
            stopped_watch = cli("watch-stop","--watch-id",watch_id,"--key","cli-stop-mcp-watch","--wait","true")
            assert stopped_watch["state"] == "completed"
            assert cli("watch-status","--watch-id",watch_id)["state"] == "stopped"
            checks.append("MCP EOF retains its committed watch; a later independent CLI process stops the same principal's watch and awaits cleanup")
            if args.toolchain:
                formal_evidence = next(item for item in result["attempts"] if item["domain"] == "generatedModel")
                artifact = next(item for item in formal_evidence["artifacts"] if item["profile"] == "formal-evidence/1")
                reference = {key:artifact[key] for key in ("id","sha256","byteCount")}
                read_budget = {"maximumDatabaseBytes":536870912,"maximumRecordBytes":262144,"maximumPageBytes":262144,"maximumNodes":96,"maximumEdges":192,"maximumTraversalNodes":4096,"maximumCursors":4}
                opening = {"open":{"evidenceID":formal_evidence["id"],"reference":reference,"budget":read_budget}}
                for generation in range(2):
                    relay = start_mcp()
                    leases = []
                    for index in range(4):
                        opened = call_mcp(relay,10+index,"invar_formal_query",{"query":opening})
                        leases.append(opened["opened"]["_0"]["id"])
                    catalog = call_mcp(relay,30,"invar_formal_query",{"query":{"catalog":{"handle":leases[0]}}})["catalog"]["_0"]
                    descriptor = next(item for item in catalog["graphs"] if item["roots"])
                    query = {"graphID":descriptor["id"],"roots":descriptor["roots"][:1],"relations":[],"direction":"outgoing","depth":0}
                    graph = call_mcp(relay,31,"invar_formal_query",{"query":{"graph":{"handle":leases[0],"query":query}}})["graph"]["_0"]
                    assert graph["graphID"] == descriptor["id"] and graph["nodes"]
                    close_mcp(relay)
                checks.append("actual Formal bundles remain queryable through live MCP handles; EOF releases all four readers so a new relay immediately opens four more")
        if args.frontends:
            relay = start_mcp()
            old_epoch = call_mcp(relay,1,"invar_status")["epoch"]
            os.kill(invar_pid,signal.SIGKILL)
            time.sleep(0.3)
            daemon("start","--policy",policy_path,"--contracts","contracts.json")
            invar_pid = json.loads((runtime / "host-control.json").read_text())["processID"]
            wait_for(lambda: daemon("status")["state"] == "ready")
            assert call_mcp(relay,2,"invar_status",error=True)["code"] == "AUTHENTICATION_REQUIRED"
            refreshed = call_mcp(relay,3,"invar_reconnect")
            assert refreshed["principal"] == cli_run["principal"]
            assert call_mcp(relay,4,"invar_status")["epoch"] != old_epoch
            assert call_mcp(relay,5,"invar_receipt",{"envelopeID":receipt["id"]}) == receipt
            close_mcp(relay)
            checks.append("live MCP refreshes the same pinned principal after daemon SIGKILL/restart and reconciles its original receipt without resubmission")
        if args.toolchain:
            formal = next(value for value in result["attempts"] if value["domain"] == "generatedModel")
            assert formal["translation"] == "unvalidated" and formal["outcome"] == "holdsWithinScope", formal
            bundles = [value for value in formal["artifacts"] if value["profile"] == "formal-evidence/1"]
            inspected = {"graphs": [], "documents": []}
            for bundle in bundles:
                page = client("formal", {"evidenceID": formal["id"], "bundle": {key: bundle[key] for key in ("id", "sha256", "byteCount")}})
                inspected["graphs"].extend(page["graphs"])
                inspected["documents"].extend(page["documents"])
            kinds = {value["kind"] for value in inspected["graphs"]}
            assert {"tlaSpecification", "tlaStateSpace", "leanDeclarations", "leanProofTerm", "irControlFlow"}.issubset(kinds), kinds
            assert all(value["roots"] > 0 and value["nodes"] > 0 for value in inspected["graphs"])
            projected = [value for value in visible["contributions"] if value["id"].startswith("invar:formal-")]
            projected_kinds = {value["data"]["metadata"]["formalKind"] for value in projected}
            assert {"tlaSpecification", "tlaStateSpace", "leanDeclarations", "leanProofTerm", "irControlFlow"}.issubset(projected_kinds), projected_kinds
            assert all(value["data"]["metadata"]["viewDigest"] == first["sha256"] and value["data"]["metadata"]["stateValuesIncluded"] is False for value in projected)
            assert formal["resources"]["sampledPeakResidentBytes"] <= 4096 * 1024 * 1024
            checks.append("actual isolated TLC/Lean worker publishes original TLA/Lean/IR graph kinds and a separate authorized SDK client reads their rooted slices/documents")
            checks.append({"formalWorkerSampledPeakResidentBytes": formal["resources"]["sampledPeakResidentBytes"], "formalWorkerWallSeconds": formal["resources"]["wallSeconds"], "declaredMemoryMiB": 4096})
        assert (root / "explorer.log").stat().st_size <= 1048576
        daemon("stop", "--mode", "drain", "--deadline", "2")
        invar_pid = None
        rpc("daemon.stop")
        explorer.wait(timeout=8)
        assert explorer.returncode == 0
    finally:
        if listener is not None:
            listener.close()
        for process in reversed(mcp_processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        if invar_pid is not None:
            try:
                daemon("stop", "--mode", "cancel", "--deadline", "2")
            except Exception:
                command = subprocess.run(["/bin/ps", "-p", str(invar_pid), "-o", "command="], capture_output=True, text=True, timeout=5).stdout
                if str(workspace) in command:
                    os.kill(invar_pid, signal.SIGKILL)
        if explorer is not None and explorer.poll() is None:
            explorer.terminate()
            try:
                explorer.wait(timeout=5)
            except subprocess.TimeoutExpired:
                explorer.kill()
                explorer.wait(timeout=5)
        log.close()
        if source_identity is not None:
            source_runtime = Path("/tmp") / ("ae-" + str(os.getuid()) + "-" + source_identity["workspaceID"][-24:])
            shutil.rmtree(source_runtime, ignore_errors=True)
            shutil.rmtree(Path(source_identity["state"]), ignore_errors=True)
        if identity is not None:
            invar_runtime = Path("/tmp") / ("invar-" + str(os.getuid()) + "-" + identity["workspaceID"][-24:])
            shutil.rmtree(invar_runtime, ignore_errors=True)
print(json.dumps({"checks": checks}, indent=2))
