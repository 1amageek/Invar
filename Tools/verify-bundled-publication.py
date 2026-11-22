#!/usr/bin/env python3
"""Publish real verification evidence before and after replacing an Invar installation."""
import argparse
from contextlib import contextmanager
from http.cookiejar import CookieJar
import json
from pathlib import Path
import select
import subprocess
import tempfile
import time
from urllib.parse import urlencode, urlsplit
from urllib.request import build_opener, HTTPCookieProcessor, Request


def wait_for(read, accept, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = read()
        if accept(result):
            return result
        time.sleep(0.1)
    raise AssertionError(result)


@contextmanager
def installed(binary, workspace, state):
    options = ['--workspace', str(workspace), '--state', str(state)]
    host = binary.parent / 'Invar_invar.bundle/Contents/Resources/architecture-host'
    assert host.is_file(), host

    def invoke(*arguments):
        result = subprocess.run([binary, *arguments, *options], capture_output=True, text=True, timeout=25)
        assert result.returncode == 0, (arguments, result.stdout, result.stderr)
        return json.loads(result.stdout)

    with tempfile.TemporaryFile(mode='w+') as errors:
        frontend = subprocess.Popen([binary, '--no-open', *options], stdout=subprocess.PIPE, stderr=errors, text=True)
        try:
            assert select.select([frontend.stdout], [], [], 25)[0]
            line = frontend.stdout.readline()
            errors.seek(0)
            assert line, errors.read()
            launch = json.loads(line)
            assert 'url' in launch, launch
            address = urlsplit(launch['url'])
            assert address.hostname == '127.0.0.1'
            origin = f'{address.scheme}://{address.netloc}'
            opener = build_opener(HTTPCookieProcessor(CookieJar()))

            def post(path, value, token=None):
                headers = {'Origin': origin, 'Content-Type': 'application/json'}
                if token:
                    headers['Authorization'] = f'Bearer {token}'
                with opener.open(Request(origin + path, json.dumps(value).encode(), headers), timeout=6) as response:
                    return json.load(response)

            def read(method, params=None):
                query = urlencode({'method': method, 'params': json.dumps(params or {})})
                with opener.open(origin + '/api?' + query, timeout=6) as response:
                    return json.load(response)

            post('/session', {'token': address.fragment.split('=', 1)[1]})
            yield invoke, read, post
        finally:
            if frontend.poll() is None:
                frontend.terminate()
                frontend.wait(timeout=8)
            status = subprocess.run([binary, 'stop', '--deadline', '2', *options], capture_output=True, timeout=14)
            assert status.returncode == 0 or b'DAEMON_UNAVAILABLE' in status.stderr, status.stderr
            stop = subprocess.run([host, 'stop', '--workspace', str(workspace)], capture_output=True, timeout=10)
            assert stop.returncode == 0 or b'CONNECTION_FAILED' in stop.stderr, stop.stderr


def verify(invoke, read, label):
    plan = invoke('plan', '--contracts', 'contracts.json', '--key', f'{label}-plan', '--wait', 'true')
    assert plan['state'] == 'completed', plan
    run = invoke('run', '--plan', plan['resultID'], '--key', f'{label}-run', '--wait', 'true')
    assert run['state'] == 'completed', run
    result = invoke('report', '--run', run['resultID'])
    assert any(job['domain'] == 'architecture' and job['execution'] == 'completed' for job in result['attempts']), result
    publication = wait_for(lambda: invoke('publication', '--operation-id', run['id']),
                           lambda value: value and value['state'] == 'committed')
    snapshot = read('workspace.status')['snapshotID']
    visible = read('extensions.view', {'snapshotID': snapshot})['publications']
    match = next(item for item in visible if item['providerID'] == 'invar'
                 and item['generation'] == publication['generation'])
    assert match['binding']['snapshotID'] == snapshot
    contribution = next(item for item in match['contributions'] if item['id'] == 'invar:verification')
    assert contribution['data']['metadata']['viewDigest'] == publication['view']['sha256']
    return snapshot, match, run['resultID']


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--previous-binary', required=True, type=Path)
parser.add_argument('--binary', default=Path(__file__).resolve().parents[1] / '.build/debug/invar', type=Path)
args = parser.parse_args()
previous, replacement = args.previous_binary.resolve(), args.binary.resolve()
assert previous.read_bytes() != replacement.read_bytes(), 'The upgrade must replace the Invar executable'
with tempfile.TemporaryDirectory(prefix='invar-bundled-upgrade-') as temporary:
    workspace = Path(temporary).resolve() / 'project'
    workspace.mkdir()
    state = workspace.parent / 'state'
    source = workspace / 'Counter.swift'
    source.write_text('public func increment(_ value: Int) -> Int { value + 1 }\n')
    (workspace / 'contracts.json').write_text(json.dumps({'schemaVersion': 1, 'architecture': [{'id': 'cycle', 'kind': 'cycle'}]}))
    with installed(previous, workspace, state) as (invoke, read, post):
        pending = wait_for(lambda: read('extensions.pending'), bool)
        assert len(pending) == 1 and pending[0]['manifest']['extensionID'] == 'invar', pending
        provider = pending[0]
        post('/extensions', {'method': 'extensions.approve', 'params': {'id': provider['id'],
             'permissions': provider['manifest']['requestedPermissions']}}, read('host.context')['csrf'])
        wait_for(lambda: invoke('status'), lambda value: value['state'] == 'ready')
        snapshot_before, published_before, report_before = verify(invoke, read, 'before')
    source.write_text('public func increment(_ value: Int) -> Int { value + 2 }\n')
    with installed(replacement, workspace, state) as (invoke, read, _):
        wait_for(lambda: invoke('status'), lambda value: value['state'] == 'ready')
        assert not read('extensions.pending')
        wait_for(lambda: read('workspace.status'), lambda value: value['snapshotID'] != snapshot_before)
        history = read('extensions.view', {'snapshotID': snapshot_before})['publications']
        assert any(item['publicationID'] == published_before['publicationID']
                   and item['providerVersion'] == published_before['providerVersion'] for item in history)
        snapshot_after, published_after, _ = verify(invoke, read, 'after')
        attempts = read('extensions.view', {'snapshotID': snapshot_after})['attempts']
        assert any(item['runID'] == published_before['runID'] and item['completion'] == 'complete' for item in attempts)
        assert invoke('report', '--run', report_before)['runID'] == report_before
        assert snapshot_after != snapshot_before and published_after['publicationID'] != published_before['publicationID']
        assert published_after['providerVersion'] != published_before['providerVersion']
        print(f"Verified and published {published_before['providerVersion']} → {published_after['providerVersion']} without reapproval; prior publication retained.")
