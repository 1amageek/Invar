#!/usr/bin/env python3
"""Run a reviewed local component harness and record bounded execution evidence."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tomllib
from uuid import uuid4


VERSION = '0.2.0'


def invoke(argv, timeout, environment=None):
    with subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, env=environment, start_new_session=True) as process:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            raise
        if process.returncode:
            diagnostic = stderr.strip() or stdout.strip()
            raise ValueError(diagnostic[-2000:] or f'{Path(argv[0]).name} exited {process.returncode}')
        return stdout.strip()


def within(root, path):
    resolved = (root / path).resolve(strict=True)
    if not resolved.is_relative_to(root):
        raise ValueError(f'Input lies outside the disposable workspace: {path}')
    return resolved


def observe(campaign, arguments):
    stats = campaign.get('stats')
    if not isinstance(stats, dict) or stats.get('workers') != 1:
        raise ValueError('Campaign did not retain statistics for its worker')
    counters = [stats.get(key) for key in ('execs', 'crashes_saved', 'crashing_execs')]
    if any(type(value) is not int or value < 0 for value in counters):
        raise ValueError('Campaign counters are missing or invalid')
    executions, saved, failures = counters
    if saved or failures:
        return 'findingObserved', 5
    elapsed = stats.get('elapsed_secs')
    if not executions or type(elapsed) not in (int, float) or not math.isfinite(elapsed) or elapsed < arguments.seconds:
        raise ValueError('Campaign did not complete its execution budget')
    reached = {entry['name'] for entry in stats['endpoints'] if entry['ok'] > 0}
    if missing := set(arguments.endpoint) - reached:
        raise ValueError('Required Endpoint not successfully executed: ' + ', '.join(sorted(missing)))
    return 'noViolationObservedWithinBudget', 0


def run(arguments, evidence):
    root = arguments.workspace.resolve(strict=True)
    project = within(root, arguments.harness)
    config = within(root, project / 'stitch.toml')
    config_bytes = config.read_bytes()
    values = tomllib.loads(config_bytes.decode())
    source = values.get('source', {})
    if not source.get('path') or source.get('git'):
        raise ValueError('Declare a local source path in stitch.toml')
    within(root, project / source['path'])
    within(root, project / values.get('docker', {}).get('dockerfile', 'Dockerfile'))
    within(root, project / 'harness')
    if (project / '.stitch').exists() or (project / '.stitch').is_symlink():
        raise ValueError('Use a disposable copy without prior .stitch build or campaign data')
    if values.get('project', {}).get('stitch_version') != VERSION:
        raise ValueError(f'Pin stitch_version = "{VERSION}" in stitch.toml')

    stitch = shutil.which(str(arguments.stitch))
    docker = shutil.which('docker')
    if not stitch or not docker:
        raise ValueError('STITCH++ and Docker must be available locally')
    version = invoke([stitch, '--version'], 10)
    if version != f'stitch-fuzz {VERSION}':
        raise ValueError(f'STITCH++ {VERSION} required, found {version}')
    context = invoke([docker, 'context', 'show'], 10)
    environment = os.environ.copy()
    environment.pop('DOCKER_HOST', None)
    environment['DOCKER_CONTEXT'] = context
    address = invoke([docker, 'context', 'inspect', context, '--format', '{{.Endpoints.docker.Host}}'],
                     10, environment)
    if not address.startswith('unix://'):
        raise ValueError('Select a local Docker context with a Unix socket')
    engine = invoke([docker, 'version', '--format', '{{.Server.Os}}/{{.Server.Arch}} {{.Server.Version}}'],
                    10, environment)

    name = 'invar-' + uuid4().hex
    command = [stitch, '-C', str(project), '--json', 'fuzz', '--foreground',
               '--name', name, '--jobs', '1', '--secs', str(arguments.seconds)]
    evidence.update(tool=version, engine=engine, command=command, campaign=name,
                    configSHA256=hashlib.sha256(config_bytes).hexdigest(),
                    durationSeconds=arguments.seconds, wallTimeoutSeconds=arguments.timeout,
                    requiredEndpoints=arguments.endpoint)
    try:
        output = invoke(command, arguments.timeout, environment)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        if (project / '.stitch' / 'campaigns' / name / 'campaign.json').is_file():
            try:
                invoke([stitch, '-C', str(project), 'stop', name], 15, environment)
            except (subprocess.TimeoutExpired, OSError, ValueError) as failure:
                evidence['cleanupDiagnostic'] = str(failure)
        raise
    campaign = json.loads(output)
    if not isinstance(campaign, dict) or campaign.get('name') != name or campaign.get('secs') != arguments.seconds:
        raise ValueError('STITCH++ result does not match the requested campaign')
    evidence['result'] = campaign
    image = campaign.get('image')
    if not isinstance(image, str) or not image:
        raise ValueError('Campaign did not identify its image')
    evidence['imageID'] = invoke([docker, 'image', 'inspect', '--format', '{{.Id}}', '--', image], 10, environment)
    return observe(campaign, arguments)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', required=True, type=Path, help='disposable copy of reviewed inputs')
    parser.add_argument('--harness', required=True, type=Path, help='STITCH++ project directory inside the copy')
    parser.add_argument('--stitch', default='stitch', help='path to the pinned stitch executable')
    parser.add_argument('--seconds', required=True, type=int, help='campaign execution budget')
    parser.add_argument('--timeout', required=True, type=int, help='wall time budget for build and campaign')
    parser.add_argument('--endpoint', required=True, action='append', help='required assertion Endpoint, repeatable')
    arguments = parser.parse_args()
    if not 0 < arguments.seconds < arguments.timeout:
        parser.error('require 0 < seconds < timeout')
    evidence = {'schemaVersion': 1, 'kind': 'stitchComponentCheck'}
    try:
        outcome, code = run(arguments, evidence)
    except (ValueError, KeyError, TypeError, AttributeError, OSError,
            subprocess.TimeoutExpired, KeyboardInterrupt) as failure:
        outcome, code = 'incomplete', 6
        evidence['diagnostic'] = str(failure) or 'Campaign was interrupted'
    evidence['outcome'] = outcome
    print(json.dumps(evidence, indent=2))
    return code


if __name__ == '__main__':
    sys.exit(main())
