#!/usr/bin/env python3
"""Aggregate exact, reviewed two-phase receipts over a complete acceptance inventory."""
import argparse
import hashlib
import json
from pathlib import Path
import re

PHASES = ('specification', 'implementation', 'correspondence')
STAGES = ('requirements', *PHASES, 'integration')
ACTIVITIES = {'specificationCheck': ('modelCheck', 'proof'), 'implementationCheck': ('modelCheck', 'proof'),
              'correspondenceCheck': ('translationValidation',), 'modelGeneration': ('generation',), 'regression': ('test',)}
PHASE_ACTIVITY = dict(zip(PHASES, ('specificationCheck', 'implementationCheck', 'correspondenceCheck')))
OUTCOMES = {'passed', 'failed', 'notVerified', 'unsupported', 'unknown'}
DOMAINS = {
    'specification': ('specification.',),
    'implementation': ('generatedModel.', 'source.'),
    'correspondence': ('translation.',),
}


def read(root, reference):
    path = Path(reference['path'])
    if path.is_absolute() or '..' in path.parts:
        raise ValueError('Evidence paths must be repository-relative')
    file = (root / path).resolve(strict=True)
    if not file.is_relative_to(root):
        raise ValueError('Evidence path escapes the repository')
    data = file.read_bytes()
    if len(data) > 16 * 1024 * 1024:
        raise ValueError('Evidence file exceeds 16 MiB')
    if hashlib.sha256(data).hexdigest() != reference['sha256']:
        raise ValueError('Changed evidence input: ' + str(path))
    return data


def key(reference):
    return reference['path'], reference['sha256']


def reference_set(root, values):
    if not isinstance(values, list) or len(values) > 4096:
        raise ValueError('Invalid bounded evidence reference list')
    keys = set()
    for value in values:
        if not isinstance(value, dict) or set(value) != {'path', 'sha256'} or key(value) in keys:
            raise ValueError('Duplicate or malformed evidence reference')
        read(root, value)
        keys.add(key(value))
    return keys


def checked_claim(root, claim, receipt, production):
    activity = receipt['activity']
    if claim.get('method') not in ACTIVITIES[activity]:
        raise ValueError('Claim method differs from its checker activity')
    if claim['outcome'] != 'passed':
        return
    if receipt['exitCode'] != 0 or receipt.get('executed') is not True or not receipt['inputs'] or not receipt['outputs']:
        raise ValueError('An unsuccessful or unexecuted process cannot supply a passed claim')
    if activity in {'modelGeneration', 'regression'}:
        return
    if activity == 'implementationCheck' and 'translate' in receipt['command']:
        raise ValueError('A translation command cannot establish an implementation property')
    inputs = {key(value) for value in receipt['inputs']}
    artifacts = inputs | {key(value) for value in receipt['outputs']}
    obligations = claim.get('obligations')
    if not isinstance(obligations, list) or not obligations or len(obligations) > 64:
        raise ValueError('Passed formal claim lacks its named obligations')
    for obligation in obligations:
        if set(obligation) != {'path', 'sha256', 'selector'} or not isinstance(obligation['selector'], str) or not obligation['selector'].strip():
            raise ValueError('Invalid named obligation')
        if key(obligation) not in inputs:
            raise ValueError('Named obligation was not an exact checker input')
    if activity in {'implementationCheck', 'correspondenceCheck'}:
        sources = reference_set(root, claim.get('sourceInputs'))
        models = reference_set(root, claim.get('modelInputs'))
        if not sources or not models or not sources <= production or not sources <= inputs or not models <= artifacts or sources & models:
            raise ValueError('Passed claim lacks exact production-source/model bindings')


def workflow(root, manifest, rows, claims, receipts, production):
    ids = {row['id'] for row in rows}
    base = {key(manifest['inventory']['source'])} | {key(value) for value in manifest.get('governingDocuments', [])}
    reviews, occupied, requested = [], set(), []
    for reference in manifest.get('reviews', []):
        review = json.loads(read(root, reference))
        stage = review.get('stage')
        covered = review.get('requirements', [])
        decision = review.get('decision')
        if review.get('schemaVersion') != 1 or stage not in STAGES or not covered or len(covered) != len(set(covered)) or not set(covered) <= ids or decision not in {'passed', 'changesRequested', 'incomplete'} or not review.get('summary'):
            raise ValueError('Malformed stage review')
        for identity in covered:
            pair = stage, identity
            if pair in occupied:
                raise ValueError('Overlapping stage reviews are ambiguous')
            occupied.add(pair)
        basis = reference_set(root, review.get('inputs'))
        needed = set(base)
        if stage in {'implementation', 'correspondence', 'integration'}:
            needed |= production
        phases = PHASES if stage == 'integration' else ('implementation', 'correspondence') if stage == 'correspondence' else (stage,)
        for row in rows:
            if row['id'] in covered:
                for phase in phases:
                    if phase in PHASES:
                        needed |= {key(claims[identity]['receipt']) for identity in row[phase]['claims']}
        if stage == 'integration':
            needed |= {key(value) for value in receipts}
            needed |= {key(value) for value in manifest.get('reviews', []) if value != reference and json.loads(read(root, value)).get('stage') != 'integration'}
        findings = review.get('findings')
        if not isinstance(findings, list) or (decision == 'passed' and findings) or (decision == 'changesRequested' and not findings):
            raise ValueError('Review decision and findings disagree')
        for finding in findings:
            if finding.get('requirementID') not in covered or finding.get('returnTo') not in STAGES or STAGES.index(finding['returnTo']) > STAGES.index(stage) or not finding.get('reason'):
                raise ValueError('Review finding lacks its owning return stage')
            requested.append(finding['returnTo'])
        reviews.append({**review, 'reference': reference, 'bindingComplete': needed <= basis})
    coverage = set()
    for row in rows:
        for identity in row['implementation']['claims']:
            claim = claims[identity]
            if claim['outcome'] == 'passed':
                coverage |= {key(value) for value in claim.get('sourceInputs', [])}
    missing_sources = production - coverage
    outcomes = {phase: aggregate([row[phase]['outcome'] for row in rows]) for phase in PHASES}
    evidence = {'requirements': 'passed', **outcomes, 'integration': aggregate(list(outcomes.values()))}
    if not production or missing_sources:
        evidence['implementation'] = 'unknown' if evidence['implementation'] == 'passed' else evidence['implementation']
        evidence['integration'] = 'unknown' if evidence['integration'] == 'passed' else evidence['integration']
    stages, blocked = [], False
    returns = set(requested)
    for stage in STAGES:
        accepted = set()
        reasons = []
        for review in reviews:
            if review['stage'] == stage:
                if review['decision'] == 'passed' and review['bindingComplete']:
                    accepted.update(review['requirements'])
                else:
                    reasons.append(review['summary'] if review['bindingComplete'] else 'Review omits governing inputs or checker receipts.')
        missing = sorted(ids - accepted)
        if missing:
            reasons.append('Current passed review missing for ' + str(len(missing)) + ' requirements.')
        if evidence[stage] != 'passed':
            reasons.append('Required evidence is ' + evidence[stage] + '.')
        if stage == 'implementation' and (not production or missing_sources):
            reasons.append('Declared production inputs are empty or not completely covered by implementation checks.')
        if stage in requested:
            reasons.append('An affected review requests revision of this owning stage.')
        own = 'failed' if evidence[stage] == 'failed' else 'passed' if not reasons else 'incomplete'
        if own != 'passed':
            returns.add(stage)
        status = 'blocked' if blocked else own
        stages.append({'id': stage, 'status': status, 'evidence': evidence[stage], 'review': 'passed' if not missing else 'incomplete',
                       'missingReviews': missing, 'reasons': reasons})
        blocked |= own != 'passed'
    verdict = 'failed' if 'failed' in outcomes.values() else 'passed' if all(stage['status'] == 'passed' for stage in stages) else 'incomplete'
    return {'schemaVersion': 1, 'stages': stages, 'reviews': reviews, 'productionInputCount': len(production),
            'coveredProductionInputCount': len(production & coverage), 'outcome': verdict,
            'returnTo': min(returns, key=STAGES.index) if returns else None}


def inventory(text, sections):
    lines = text.splitlines()
    entries = []
    for section in sections:
        start = lines.index(section['heading']) + 1
        end = next((i for i in range(start, len(lines)) if lines[i].startswith('## ')), len(lines))
        count = 0
        for number in range(start, end):
            line = lines[number]
            if section['kind'] == 'table':
                match = re.match(r'^\|\s*([A-Za-z]+[0-9]+)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*$', line)
                if match:
                    entries.append({'id': match[1], 'title': match[2], 'condition': match[3], 'line': number + 1})
            elif section['kind'] == 'bullets':
                if line.startswith('- '):
                    count += 1
                    entries.append({'id': section['prefix'] + str(count).zfill(2), 'title': line[2:], 'condition': line[2:], 'line': number + 1})
            else:
                raise ValueError('Unsupported acceptance inventory format')
    ids = [entry['id'] for entry in entries]
    if not ids or len(ids) != len(set(ids)):
        raise ValueError('Acceptance inventory must have unique nonempty identities')
    return entries


def aggregate(outcomes):
    for outcome in ('failed', 'unsupported', 'unknown', 'notVerified'):
        if outcome in outcomes:
            return outcome
    return 'passed' if outcomes else 'notVerified'


def build(root, manifest):
    root = Path(root).resolve(strict=True)
    if manifest.get('schemaVersion') != 2:
        raise ValueError('Unsupported project manifest version')
    specification = read(root, manifest['inventory']['source']).decode('utf-8')
    expected = inventory(specification, manifest['inventory']['sections'])
    requirements = manifest['requirements']
    ids = [entry['id'] for entry in requirements]
    if len(ids) != len(set(ids)) or set(ids) != {entry['id'] for entry in expected}:
        raise ValueError('Requirements differ from the complete acceptance inventory')
    for reference in manifest.get('governingDocuments', []):
        read(root, reference)
    production = reference_set(root, manifest.get('productionInputs'))

    claims = {}
    receipts = []
    for reference in manifest['receipts']:
        receipt = json.loads(read(root, reference))
        if receipt.get('schemaVersion') != 2 or not receipt.get('command') or receipt.get('activity') not in ACTIVITIES:
            raise ValueError('Receipt lacks its original command')
        reference_set(root, receipt['inputs'])
        reference_set(root, receipt['outputs'])
        for claim in receipt['claims']:
            if claim['id'] in claims or claim['outcome'] not in OUTCOMES or not claim.get('scope'):
                raise ValueError('Duplicate or malformed verification claim')
            covered = claim.get('requirements')
            if not isinstance(covered, list) or not covered or len(covered) != len(set(covered)) or not set(covered).issubset(set(ids)):
                raise ValueError('Receipt claims an unknown requirement')
            checked_claim(root, claim, receipt, production)
            claims[claim['id']] = {**claim, 'activity': receipt['activity'], 'receipt': reference}
        receipts.append(reference)

    nodes = []
    edges = []
    rows = []
    groups = {}
    source = manifest['inventory']['source']['path']
    by_id = {entry['id']: entry for entry in expected}
    for requirement in requirements:
        identity = requirement['id']
        row = {'id': identity, 'nodeID': identity, 'title': requirement.get('title', by_id[identity]['title'])}
        for phase in PHASES:
            assessment = requirement[phase]
            used = []
            references = assessment['claims']
            if len(references) != len(set(references)):
                raise ValueError('Duplicate claim in an assessment')
            for claim_id in references:
                claim = claims[claim_id]
                if identity not in claim['requirements'] or not claim['domain'].startswith(DOMAINS[phase]):
                    raise ValueError('Claim does not establish the requested requirement and phase')
                if claim['activity'] != PHASE_ACTIVITY[phase] and not (phase == 'implementation' and claim['activity'] == 'modelGeneration' and claim['outcome'] != 'passed'):
                    raise ValueError('Generation or regression cannot establish a checked formal phase')
                if phase == 'correspondence' and claim['outcome'] == 'passed' and claim['domain'] != 'translation.validated':
                    raise ValueError('A model proof cannot establish validated source correspondence')
                used.append(claim['outcome'])
            if not references and not assessment.get('reason'):
                raise ValueError('Uncovered requirements need an explicit reason')
            row[phase] = {'outcome': aggregate(used), 'claims': references, 'detail': assessment.get('reason', '')}
        if row['correspondence']['outcome'] == 'passed':
            for field in ('sourceInputs', 'modelInputs'):
                implementation = {key(value) for identity in row['implementation']['claims'] for value in claims[identity].get(field, [])}
                correspondence = {key(value) for identity in row['correspondence']['claims'] for value in claims[identity].get(field, [])}
                if not implementation or implementation != correspondence:
                    raise ValueError('Correspondence does not bind the checked implementation sources/models')
        outcome = aggregate([row[phase]['outcome'] for phase in PHASES])
        details = {'requirement': source + ':' + str(by_id[identity]['line']), 'condition': by_id[identity]['condition'],
                   **{phase: row[phase] for phase in PHASES}, 'overall': outcome}
        nodes.append({'id': identity, 'label': identity + ' · ' + row['title'], 'role': 'requirement', 'details': details})
        if requirement.get('group'):
            label = requirement['group']
            group_id = 'group-' + hashlib.sha256(label.encode()).hexdigest()[:16]
            nodes[-1]['parentID'] = group_id
            groups.setdefault(group_id, {'label': label, 'requirements': []})['requirements'].append(row)
        rows.append(row)
        if not requirement.get('group'):
            for phase in PHASES:
                edges.append({'id': identity + '-' + phase, 'source': identity, 'target': phase,
                              'label': row[phase]['outcome'], 'role': phase, 'directed': True})
    for phase in PHASES:
        passed = sum(row[phase]['outcome'] == 'passed' for row in rows)
        nodes.append({'id': phase, 'label': phase.title() + ' · ' + str(passed) + '/' + str(len(rows)),
                      'role': 'verification phase', 'details': {'outcomes': {row['id']: row[phase] for row in rows}}})
    for identity, group in groups.items():
        nodes.append({'id': identity, 'label': group['label'], 'role': 'requirement group', 'details': group})
        for phase in PHASES:
            passed = sum(row[phase]['outcome'] == 'passed' for row in group['requirements'])
            edges.append({'id': identity + '-' + phase, 'source': identity, 'target': phase, 'role': phase, 'directed': True,
                          'label': str(passed) + '/' + str(len(group['requirements'])) + ' verified'})
    gates = workflow(root, manifest, rows, claims, receipts, production)
    verdict = gates['outcome']
    for index, stage in enumerate(gates['stages']):
        identity = 'workflow-' + stage['id']
        stage['nodeID'] = identity
        nodes.append({'id': identity, 'label': stage['id'].title() + ' · ' + stage['status'].title(), 'role': 'workflow gate',
                      'details': {**stage, 'returnTo': gates['returnTo']}})
        if index:
            edges.append({'id': identity + '-prerequisite', 'source': 'workflow-' + STAGES[index-1], 'target': identity, 'label': 'reviewed prerequisite', 'directed': True})
    document = {'schemaVersion': '1', 'kind': 'proofDependencies', 'title': manifest['title'], 'nodes': nodes, 'edges': edges,
                'metadata': {'verificationReport': {'schemaVersion': 2, 'inventory': [entry['id'] for entry in expected],
                    'requirements': rows, 'evidence': list(claims.values()), 'receipts': receipts, 'outcome': verdict,
                    'workflow': gates, 'productionInputs': manifest['productionInputs'], 'mapBinding': manifest.get('mapBinding'), 'openQuestions': []}}}
    return document


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--workspace', required=True, type=Path)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    document = build(args.workspace, json.loads(args.manifest.read_text()))
    data = json.dumps(document, ensure_ascii=False, indent=2) + '\n'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_name(args.output.name + '.tmp')
    with temporary.open('x', encoding='utf-8') as file:
        file.write(data)
    temporary.replace(args.output)
    report = document['metadata']['verificationReport']
    print(json.dumps({'output': str(args.output), 'requirements': len(report['requirements']), 'outcome': report['outcome']}))
    raise SystemExit({'passed': 0, 'failed': 5, 'incomplete': 6}[report['outcome']])


if __name__ == '__main__':
    main()
