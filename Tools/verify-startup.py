#!/usr/bin/env python3
"""Check the installed CLI's workspace selection and shared MCP lifecycle."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import http.cookiejar
import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import tempfile
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPCookieProcessor, Request, build_opener

parser = argparse.ArgumentParser()
parser.add_argument('--binary', type=Path, default=Path(__file__).resolve().parents[1] / '.build/debug/invar')
args = parser.parse_args()
binary = str(args.binary.resolve())
resources = Path(binary).parent / 'Invar_invar.bundle'
explorer = next((root / 'architecture-host' for root in (resources / 'Contents/Resources', resources)
                 if (root / 'architecture-host').is_file()), None)
assert explorer, f'Explorer is not bundled beside {binary}'
for module in ('ArchitectureGraph', 'ArchitectureWeb', 'ArchitectureHTTPHost'):
    assert list(explorer.parent.glob(f'ArchitectureExplorer_{module}*.bundle')), module
environment = os.environ | {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
                            'INVAR_EXPLORER': '/no-external-explorer'}


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


def verify_browser(nested, state, workspace_id):
    process = subprocess.Popen([binary, '--no-open', *state], cwd=nested, env=environment, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        assert select.select([process.stdout], [], [], 35)[0], 'Bundled browser never became ready'
        line = process.stdout.readline()
        assert line, process.stderr.read()
        launch = json.loads(line)
        assert launch['workspaceID'] == workspace_id
        parts = urlsplit(launch['url'])
        assert parts.hostname == '127.0.0.1'
        origin = f'{parts.scheme}://{parts.netloc}'
        endpoint = origin + '/api?method=workspace.status'
        opener = build_opener(HTTPCookieProcessor(http.cookiejar.CookieJar()))
        with opener.open(origin + '/', timeout=5) as response:
            assert b'Architecture Explorer' in response.read()
        with opener.open(origin + '/assets/explorer.js', timeout=5) as response:
            assert len(response.read()) > 1000
        try:
            opener.open(endpoint, timeout=5).close()
            raise AssertionError('Unauthenticated access to the index succeeded')
        except HTTPError as error:
            assert error.code == 403
            error.close()
        authentication = Request(origin + '/session', json.dumps({'token': parts.fragment.split('=', 1)[1]}).encode(),
                                 headers={'Origin': origin, 'Content-Type': 'application/json'})
        with opener.open(authentication, timeout=5) as response:
            assert response.status == 200
        deadline = time.monotonic() + 8
        while True:
            with opener.open(endpoint, timeout=5) as response:
                status = json.load(response)
            if status.get('snapshotID') and status.get('entityCount', 0) > 0:
                break
            assert time.monotonic() < deadline, status
            time.sleep(0.05)
        invar_status = invoke([binary, 'status', *state], nested)
        assert invar_status['workspaceID'] == workspace_id
        assert invar_status['protocolVersion'] == 3 and 'policyRevision' not in invar_status
        return invar_status['epoch']
    finally:
        process.terminate()
        try:
            assert process.wait(timeout=8) == 130
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
            raise


with tempfile.TemporaryDirectory(prefix='invar-startup-') as temporary:
    root = Path(temporary).resolve()
    workspace = root / 'project'
    nested = workspace / 'Sources' / 'Core'
    nested.mkdir(parents=True)
    subprocess.run(['/usr/bin/git', 'init', '--quiet', str(workspace)], check=True, timeout=8)
    (nested / 'Fixture.swift').write_text('public func answer() -> Int { 42 }\n')
    state = ['--state', str(root / 'state')]
    mcp = [binary, 'mcp', *state]
    assert invoke([binary, 'status', *state], root, 2)['code'] == 'WORKSPACE_REQUIRED'
    assert invoke([binary, 'daemon', 'approve', *state], nested, 2)['code'] == 'INVALID_ARGUMENT'
    assert invoke([*mcp, '--client-profile', 'legacy'], nested, 2)['code'] == 'INVALID_ARGUMENT'
    incomplete_install = root / 'invar-without-bundle'
    shutil.copy2(binary, incomplete_install)
    assert invoke([incomplete_install, '--no-open', *state], nested, 3)['code'] == 'EXPLORER_UNAVAILABLE'
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
    owned = False
    index_socket = Path("/tmp") / f"ae-{os.getuid()}-{identity['workspaceID'][-24:]}" / "rpc.sock"
    runtime = Path('/tmp') / f"invar-{os.getuid()}-{identity['workspaceID'][-24:]}"
    try:
        assert not (root / 'state' / 'verification.sqlite').exists()
        legacy_resume = root / 'state' / 'explorer-resume.json'
        legacy_resume.parent.mkdir(mode=0o700, exist_ok=True)
        legacy_resume.write_text(json.dumps({'manifestDigest': 'a' * 64, 'credential': 'b' * 72}))
        legacy_resume.chmod(0o600)
        legacy_record = legacy_resume.read_bytes()
        cold = mcp_status(mcp, nested)
        assert cold['workspaceID'] == identity['workspaceID'] and cold['protocolVersion'] == 3
        assert legacy_resume.read_bytes() == legacy_record
        browser_epoch = verify_browser(nested, state, identity['workspaceID'])
        assert invoke([binary, 'status', *state], nested)['epoch'] == browser_epoch == cold['epoch']
        invoke([binary, 'stop', '--deadline', '2', *state], nested)
        subprocess.run([explorer, 'stop', '--workspace', str(workspace)], env=environment, check=True, timeout=8)
        deadline = time.monotonic() + 8
        while index_socket.exists():
            assert time.monotonic() < deadline, 'The bundled index did not release its socket'
            time.sleep(0.05)
        start = [binary, 'daemon', 'start', *state]
        with ThreadPoolExecutor(max_workers=2) as executor:
            statuses = [future.result() for future in [executor.submit(invoke, start, nested) for _ in range(2)]]
        owned = True
        first, second = statuses
        assert first['epoch'] == second['epoch']
        wrong_state = invoke([binary, 'daemon', 'start', '--state', str(root / 'other-state')], nested, 8)
        assert wrong_state['code'] == 'WORKSPACE_STATE_MISMATCH'
        assert mcp_status(mcp, nested)['epoch'] == first['epoch']
        process_id = json.loads((runtime / 'host-control.json').read_text())['processID']
        os.kill(process_id, signal.SIGTERM)
        deadline = time.monotonic() + 8
        while (runtime / 'host-control.json').exists():
            assert time.monotonic() < deadline, 'The owned daemon did not shut down'
            time.sleep(0.05)
        recovered = mcp_status(mcp, nested)
        assert index_socket.exists()
        assert recovered['epoch'] != first['epoch']
        assert recovered['workspaceID'] == identity['workspaceID']
        assert invoke([binary, 'stop', '--deadline', '2', *state], nested)['stopped']
        owned = False
        assert invoke(mcp, nested, 6)['code'] == 'USER_STOPPED'
        assert invoke([binary, 'status', *state], nested, 6)['code'] == 'DAEMON_UNAVAILABLE'
    finally:
        if owned or (runtime / 'host-control.json').exists():
            invoke([binary, 'stop', '--deadline', '2', *state], nested)
        result = subprocess.run([explorer, 'stop', '--workspace', str(workspace)], env=environment,
                                capture_output=True, text=True, timeout=8)
        assert result.returncode == 0 or 'CONNECTION_FAILED' in result.stderr, result.stderr
print('Bundled browser and assets, authenticated index, workspace selection, cold MCP start, concurrent start, MCP recovery, and explicit stop verified.')
