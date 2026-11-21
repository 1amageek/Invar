#!/usr/bin/env python3
"""Exercise post-registration failure against an owned unmodified Explorer host."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--host", default=str(ROOT / "Tests/Fixtures/ExplorerHost/.build/debug/InvarExplorerHost"))
parser.add_argument("--provider", default=str(ROOT / "Tests/Fixtures/ExplorerHost/.build/debug/InvarConnectionFailure"))
args = parser.parse_args()
host = Path(args.host).resolve()
provider = Path(args.provider).resolve()
assert host.read_bytes() != provider.read_bytes(), "Provider must have distinct code identity from the privileged source host"


def wait_for(test, seconds=20):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = test()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError("Owned connection-cleanup fixture timed out")


with tempfile.TemporaryDirectory(prefix="invar-provider-cleanup-") as directory:
    root = Path(directory).resolve()
    workspace, state = root / "workspace", root / "connection"
    workspace.mkdir()
    state.mkdir(mode=0o700)
    (workspace / "Demo.swift").write_text("public struct Demo {}\n")
    processes = []
    with (root / "host.log").open("w") as log:
        def rpc(method):
            result = subprocess.run([host, "rpc", workspace, method, "{}"],capture_output=True,text=True,timeout=10)
            assert result.returncode == 0, (method,result.stderr,result.stdout)
            return json.loads(result.stdout)

        try:
            identity = subprocess.run([host,"identity",workspace],capture_output=True,text=True,check=True,timeout=10)
            workspace_id = json.loads(identity.stdout)["workspaceID"]
            source = subprocess.Popen([host,"serve",workspace],stdout=log,stderr=log,start_new_session=True)
            processes.append(source)
            socket = Path("/tmp") / ("ae-" + str(os.getuid()) + "-" + workspace_id[-24:]) / "rpc.sock"
            wait_for(socket.exists)
            connection = subprocess.Popen([provider,workspace,state],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
            processes.append(connection)
            pending = wait_for(lambda: next((item for item in rpc("extensions.pending") if item["manifest"]["extensionID"] == "invar-cleanup"),None))
            assert pending["peer"]["processID"] == connection.pid
            params = json.dumps({"id":pending["id"],"permissions":pending["manifest"]["requestedPermissions"]})
            approved = subprocess.run([host,"rpc",workspace,"extensions.approve",params],capture_output=True,text=True,timeout=10)
            assert approved.returncode == 0, (approved.stdout,approved.stderr)
            out, err = connection.communicate(timeout=20)
            assert connection.returncode == 0, (out,err)
            assert json.loads(out)["observedFailure"]
            registered = next(item for item in rpc("extensions.list") if item["providerID"] == "invar-cleanup")
            assert not registered["connected"], registered
            print(json.dumps({"checks":["actual registration approved for owned process","credential persistence failed after registration","failed initialization disconnected actual source session"]}))
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    os.killpg(process.pid,signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid,signal.SIGKILL)
                        process.wait(timeout=5)
