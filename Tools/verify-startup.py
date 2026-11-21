#!/usr/bin/env python3
"""Check the installed CLI's workspace selection and shared MCP lifecycle."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--binary', type=Path, default=Path(__file__).resolve().parents[1] / '.build/debug/invar')
parser.add_argument('--explorer', type=Path, required=True)
args = parser.parse_args()
binary = str(args.binary.resolve())
explorer = str(args.explorer.resolve())
environment = os.environ | {'INVAR_EXPLORER': explorer}


def invoke(argv, cwd, expected=0):
    result = subprocess.run(argv, cwd=cwd, env=environment, text=True, capture_output=True, timeout=18)
    assert result.returncode == expected, (argv, result.returncode, result.stdout, result.stderr)
    return json.loads(result.stdout or result.stderr)


def mcp_status(argv, cwd):
    process = subprocess.Popen(argv, cwd=cwd, env=environment, text=True,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        def request(method, identity=None, **params):
            message = {'jsonrpc': '2.0', 'method': method}
            if identity is not None:
                message.update(id=identity, params=params)
            process.stdin.write(json.dumps(message) + '\n')
            process.stdin.flush()
            if identity is None:
                return None
            assert select.select([process.stdout], [], [], 15)[0], method
            response = process.stdout.readline()
            assert response, process.stderr.read()
            return json.loads(response)['result']

        initialized = request('initialize', 1, protocolVersion='2025-11-25', capabilities={},
                              clientInfo={'name': 'startup regression', 'version': '1'})
        assert initialized['serverInfo']['name'] == 'Invar'
        request('notifications/initialized')
        result = request('tools/call', 2, name='invar_status', arguments={})
        assert not result.get('isError'), result
        return result['structuredContent']['value']
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


with tempfile.TemporaryDirectory(prefix='invar-startup-') as temporary:
    root = Path(temporary).resolve()
    workspace = root / 'project'
    nested = workspace / 'Sources' / 'Core'
    nested.mkdir(parents=True)
    subprocess.run(['/usr/bin/git', 'init', '--quiet', str(workspace)], check=True, timeout=8)
    state = ['--state', str(root / 'state')]
    profiles = ['--client-state', str(root / 'clients'), '--capabilities', 'read']
    mcp = [binary, 'mcp', *state, *profiles]
    assert invoke([binary, 'status', *state], root, 2)['code'] == 'WORKSPACE_REQUIRED'
    identity = invoke([binary, 'daemon', 'identity', *state], nested)
    explicit = invoke([binary, 'daemon', 'identity', '--workspace', str(nested), *state], workspace)
    assert explicit['workspaceID'] != identity['workspaceID']
    subprocess.run(['/usr/bin/git', '-C', str(workspace), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test',
                    '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null',
                    'commit', '--quiet', '--allow-empty', '-m', 'Fixture'], check=True, timeout=8)
    worktree = root / 'linked worktree'
    subprocess.run(['/usr/bin/git', '-C', str(workspace), 'worktree', 'add', '--quiet', '--detach', str(worktree)],
                   check=True, timeout=8)
    (worktree / 'Sources').mkdir()
    linked = invoke([binary, 'daemon', 'identity', *state], worktree / 'Sources')
    assert linked['workspaceID'] == invoke([binary, 'daemon', 'identity', '--workspace', str(worktree), *state], root)['workspaceID']
    assert linked['workspaceID'] != identity['workspaceID']
    assert invoke(mcp, nested, 8)['code'] == 'APPROVAL_REQUIRED'
    assert not (root / 'state' / 'verification.sqlite').exists()
    policy = root / 'policy.json'
    policy.write_text(json.dumps({
        'workspaceID': identity['workspaceID'], 'engineIdentity': identity['engineIdentity'], 'revision': 1,
        'peers': [{'binaryDigest': identity['clientBinaryDigest'], 'capabilities': ['read']}], 'approvals': [],
        'sessionSeconds': 30, 'principalSeconds': 120, 'maximumSessions': 8, 'maximumConnections': 4,
        'maximumEnvelopeSeconds': 60,
    }))
    owned = False
    runtime = Path('/tmp') / f"invar-{os.getuid()}-{identity['workspaceID'][-24:]}"
    try:
        start = [binary, 'daemon', 'start', '--policy', str(policy), *state]
        with ThreadPoolExecutor(max_workers=2) as executor:
            statuses = [future.result() for future in [executor.submit(invoke, start, nested) for _ in range(2)]]
        owned = True
        first, second = statuses
        assert first['epoch'] == second['epoch']
        wrong_state = invoke([binary, 'daemon', 'start', '--state', str(root / 'other-state')], nested, 8)
        assert wrong_state['code'] == 'WORKSPACE_STATE_MISMATCH'
        assert mcp_status(mcp + ['--client-profile', 'running'], nested)['epoch'] == first['epoch']
        process_id = json.loads((runtime / 'host-control.json').read_text())['processID']
        os.kill(process_id, signal.SIGTERM)
        deadline = time.monotonic() + 8
        while (runtime / 'host-control.json').exists():
            assert time.monotonic() < deadline, 'The owned daemon did not shut down'
            time.sleep(0.05)
        recovered = mcp_status(mcp + ['--client-profile', 'automatic'], nested)
        assert recovered['epoch'] != first['epoch']
        assert recovered['workspaceID'] == identity['workspaceID']
        assert invoke([explorer, 'daemon', 'status', '--workspace', str(workspace)], nested)['workspaceID'] == recovered['workspaceID']
        assert invoke([binary, 'stop', '--deadline', '2', *state], nested)['stopped']
        owned = False
        assert invoke(mcp, nested, 6)['code'] == 'USER_STOPPED'
        assert invoke([binary, 'status', *state], nested, 6)['code'] == 'DAEMON_UNAVAILABLE'
    finally:
        if owned:
            invoke([binary, 'stop', '--deadline', '2', *state], nested)
        if subprocess.run([explorer, 'daemon', 'status', '--workspace', str(workspace)], capture_output=True, timeout=5).returncode == 0:
            invoke([explorer, 'daemon', 'stop', '--workspace', str(workspace)], nested)
print('Workspace selection, concurrent start, stdio handshake, headless recovery, and explicit stop verified.')
