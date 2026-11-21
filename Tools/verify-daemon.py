#!/usr/bin/env python3
"""Exercise owned CLI processes, replacement control, signals and crash restart."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("--binary", default=str(Path(__file__).resolve().parents[1] / ".build/debug/invar"))
args = parser.parse_args()
source = Path(args.binary).resolve()
checks = []


def wait_for(predicate, seconds=8):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.025)
    raise AssertionError("Owned daemon did not reach its expected state")


with tempfile.TemporaryDirectory(prefix="invar-daemon-runtime-") as directory:
    root = Path(directory).resolve()
    workspace = root / "workspace"
    workspace.mkdir()
    binary = root / "invar"
    shutil.copy2(source, binary)
    for bundle in source.parent.glob("*.bundle"):
        shutil.copytree(bundle, root / bundle.name)
    link_directory = root / "bin"
    link_directory.mkdir()
    (link_directory / binary.name).symlink_to(binary)
    environment = os.environ | {"PATH": str(link_directory) + os.pathsep + os.environ["PATH"]}
    base = ["--workspace", str(workspace), "--state", str(root / "state")]
    runtime = None
    owned_pid = None

    def call(action, *options, expected=0):
        result = subprocess.run(
            [binary.name, "daemon", action, *base, *options], cwd=workspace, env=environment,
            capture_output=True, text=True, timeout=20,
        )
        assert result.returncode == expected, (action, result.returncode, result.stdout, result.stderr)
        return json.loads(result.stdout)

    def record():
        return json.loads((runtime / "host-control.json").read_text())

    def lock_free():
        try:
            with (runtime / "owner.lock").open("rb") as handle:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return True
        except BlockingIOError:
            return False

    try:
        identity = call("identity")
        runtime = Path("/tmp") / ("invar-" + str(os.getuid()) + "-" + identity["workspaceID"][-24:])
        status = call("start")
        owned_pid = record()["processID"]
        assert status["epoch"] == record()["epoch"]
        assert call("status")["epoch"] == status["epoch"]
        checks.append("detached start retains ownership after bootstrap exits")
        original = record()
        os.kill(owned_pid, signal.SIGTERM)
        wait_for(lambda: lock_free() and not (runtime / "host-control.json").exists())
        owned_pid = None
        checks.append("SIGTERM reaches detached host and awaits socket/Store/lock cleanup")
        call("start")
        owned_pid = record()["processID"]
        epoch = record()["epoch"]
        os.kill(owned_pid, signal.SIGKILL)
        wait_for(lock_free)
        owned_pid = None
        assert (runtime / "host-control.json").exists()
        call("start")
        owned_pid = record()["processID"]
        assert record()["epoch"] != epoch
        checks.append("crash restart replaces only stale owned sockets/record with a new epoch")
        old_record = record()
        replacement = root / "replacement"
        shutil.copy2(binary, replacement)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--identifier", "dev.1amageek.invar-replacement-fixture", str(replacement)], check=True, capture_output=True, timeout=10)
        os.replace(replacement, binary)
        replaced = call("status")
        assert replaced["engineIdentity"] == old_record["endpoint"]["engineIdentity"]
        assert replaced["epoch"] == old_record["epoch"]
        denied = call("start", expected=4)
        assert denied["code"] == "EXECUTOR_MISMATCH"
        checks.append("binary replacement preserves private administration and refuses replacement-engine attachment")
        stopped = call("stop", "--mode", "cancel", "--deadline", "2")
        assert stopped["stopped"] and lock_free()
        assert not (runtime / "host-control.json").exists()
        assert (root / "state/user-stopped").exists()
        owned_pid = None
        checks.append("replacement binary can explicitly stop original audit/PID/start-bound host")
    finally:
        if owned_pid is not None:
            # The private record was produced by this test's child, and the
            # exact workspace is unique. Never stop an unrelated workspace.
            command = subprocess.run(["/bin/ps", "-p", str(owned_pid), "-o", "command="], capture_output=True, text=True, timeout=5).stdout
            if root.name + "/invar daemon serve" in command and str(workspace) in command:
                os.kill(owned_pid, signal.SIGKILL)
                wait_for(lock_free)
        if runtime is not None and runtime.exists() and lock_free():
            shutil.rmtree(runtime)
print(json.dumps({"checks": checks}, indent=2))
