#!/usr/bin/env python3
"""Check the installed CLI's workspace selection and shared MCP lifecycle."""
import argparse
import base64
import hashlib
from concurrent.futures import ThreadPoolExecutor
import http.cookiejar
import json
import os
from pathlib import Path
import posixpath
import re
import select
import shutil
import signal
import subprocess
import tempfile
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit, urlunsplit
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


def verify_skills(request):
    source = Path(__file__).resolve().parents[1] / 'Sources/InvarSkills/skills'
    entrypoints = {f'skill://invar/{file.relative_to(source).as_posix()}' for file in source.glob('*/SKILL.md')}
    assert len(entrypoints) == 8
    listed = request('skills/list')['skills']
    assert {skill['uri'] for skill in listed} == entrypoints
    assert {item['uri'] for item in request('resources/list')['resources']} == entrypoints
    contents = {}
    for skill in listed:
        uri = skill['uri']
        assert skill['frontmatter']['name'] == uri.split('/')[-2]
        assert request('skills/get', uri=uri)['skill'] == skill
        directory_uri = uri.rsplit('/', 1)[0]
        children = request('resources/directory/read', uri=directory_uri)['resources']
        assert uri in {child['uri'] for child in children}
        for resource in skill['resources']:
            file_uri = resource['uri']
            content, = request('resources/read', uri=file_uri)['contents']
            assert content['uri'] == file_uri
            data = content['text'].encode() if 'text' in content else base64.b64decode(content['blob'])
            assert len(data) == resource['size']
            assert resource['digest'] == 'sha256:' + hashlib.sha256(data).hexdigest()
            assert data == (source / file_uri.removeprefix('skill://invar/')).read_bytes()
            contents[file_uri] = data

    expected = {f'skill://invar/{file.relative_to(source).as_posix()}'
                for file in source.rglob('*') if file.is_file()}
    assert set(contents) == expected
    for uri, data in contents.items():
        if not uri.endswith('.md'):
            continue
        origin = urlsplit(uri)
        for link in re.findall(r'\]\(([^)]+)\)', data.decode()):
            target = urlsplit(link)
            if target.scheme or not target.path:
                continue
            path = posixpath.normpath(posixpath.join(posixpath.dirname(origin.path), target.path))
            assert urlunsplit((origin.scheme, origin.netloc, path, '', '')) in contents, (uri, link)

    with tempfile.TemporaryDirectory(prefix='invar-skill-helper-') as temporary:
        helper = Path(temporary) / 'project_report.py'
        helper.write_bytes(contents['skill://invar/verify-project/scripts/project_report.py'])
        result = subprocess.run(['/usr/bin/python3', helper, '--help'], capture_output=True, timeout=8, check=True)
        assert b'--manifest' in result.stdout, result.stdout
    assert request('skills/get', expect_error=True, uri='skill://invar/unknown/SKILL.md')['code'] == -32602
    request('resources/read', expect_error=True, uri='skill://invar/workspace-only/SKILL.md')


def mcp_status(argv, cwd, protocol='2025-11-25', *, check_skills=False):
    process = subprocess.Popen(argv, cwd=cwd, env=environment, text=True,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    identity = 0
    modern = protocol == '2026-07-28'
    client_info = {'name': 'startup regression', 'version': '1'}
    try:
        def request(method, *, notification=False, expect_error=False, **params):
            nonlocal identity
            message = {'jsonrpc': '2.0', 'method': method}
            if modern:
                params['_meta'] = {'io.modelcontextprotocol/protocolVersion': protocol,
                                   'io.modelcontextprotocol/clientCapabilities': {},
                                   'io.modelcontextprotocol/clientInfo': client_info}
            if not notification:
                identity += 1
                message.update(id=identity, params=params)
            process.stdin.write(json.dumps(message) + '\n')
            process.stdin.flush()
            if notification:
                return None
            assert select.select([process.stdout], [], [], 15)[0], method
            line = process.stdout.readline()
            assert line, method
            response = json.loads(line)
            assert response['id'] == identity, response
            if expect_error:
                return response['error']
            assert 'result' in response, response
            return response['result']

        if modern:
            initialized = request('server/discover')
            assert protocol in initialized['supportedVersions'], initialized
        else:
            initialized = request('initialize', protocolVersion=protocol, capabilities={}, clientInfo=client_info)
            request('notifications/initialized', notification=True)
            assert initialized['serverInfo']['name'] == 'Invar', initialized
        capability = initialized['capabilities']
        assert 'resources' in capability
        assert capability['extensions']['io.modelcontextprotocol/skills'] == {'directoryRead': True}
        assert {'invar_plan', 'invar_run', 'invar_report'} <= {tool['name'] for tool in request('tools/list')['tools']}
        if check_skills:
            verify_skills(request)
        result = request('tools/call', name='invar_status', arguments={})
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
    workspace_skill = workspace / 'skills/workspace-only/SKILL.md'
    workspace_skill.parent.mkdir(parents=True)
    workspace_skill.write_text('---\nname: workspace-only\ndescription: Must stay in this workspace.\n---\n')
    state = ['--state', str(root / 'state')]
    mcp = [binary, 'mcp', *state]
    assert invoke([binary, 'status', *state], root, 2)['code'] == 'WORKSPACE_REQUIRED'
    assert invoke([binary, 'daemon', 'approve', *state], nested, 2)['code'] == 'INVALID_ARGUMENT'
    assert invoke([*mcp, '--client-profile', 'legacy'], nested, 2)['code'] == 'INVALID_ARGUMENT'
    incomplete_install = root / 'invar-without-bundle'
    shutil.copy2(binary, incomplete_install)
    assert invoke([incomplete_install, '--no-open', *state], nested, 3)['code'] == 'EXPLORER_UNAVAILABLE'
    assert invoke([incomplete_install, 'mcp', *state], nested, 3)['code'] == 'SKILLS_UNAVAILABLE'
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
        cold = mcp_status(mcp, nested, check_skills=True)
        assert cold['workspaceID'] == identity['workspaceID'] and cold['protocolVersion'] == 3
        modern = mcp_status(mcp, nested, protocol='2026-07-28', check_skills=True)
        assert modern['workspaceID'] == cold['workspaceID'] and modern['epoch'] == cold['epoch']
        browser_epoch = verify_browser(nested, state, identity['workspaceID'])
        deadline = time.monotonic() + 8
        while invoke([binary, 'status', *state], nested)['state'] != 'ready':
            assert time.monotonic() < deadline, 'The bundled Provider did not register'
            time.sleep(0.05)
        assert legacy_resume.read_bytes() != legacy_record
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
print('Bundled Explorer, workspace selection, MCP lifecycle, and Skills discovery and file integrity on both protocol revisions verified.')
