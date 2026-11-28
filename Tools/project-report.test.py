#!/usr/bin/env python3
"""Behavioral checks for complete-inventory and phase-specific evidence gates."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys

sys.dont_write_bytecode = True

source = Path(__file__).resolve().parents[1] / 'Sources/InvarSkills/skills/verify-project/scripts/project_report.py'
spec = importlib.util.spec_from_file_location('project_report', source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ProjectReportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.specification = self.write('SPEC.md', '## Acceptance\n| R01 | Valid result | The result meets the contract |\n| R02 | Boundary | The boundary is preserved |\n')
        self.architecture = self.write('ARCHITECTURE.dsl', 'workspace {\nmodel {\nsample = softwareSystem "Sample"\n}\n}\n')
        self.log = self.write('checker.log', 'actual controlled checker output')
        self.source = self.write('Code.swift', 'func value() -> Bool { true }')
        self.model = self.write('model.json', '{"model":"controlled test model"}')
        self.obligation = self.write('properties.json', '{"condition":"result is true"}')
        self.receipts = {}
        for phase, domain, activity, method in [('specification', 'specification.lean', 'specificationCheck', 'proof'),
                                               ('implementation', 'generatedModel.lean', 'implementationCheck', 'proof'),
                                               ('correspondence', 'translation.validated', 'correspondenceCheck', 'translationValidation')]:
            claims = [{'id': phase + identity, 'requirements': [identity], 'domain': domain, 'outcome': 'passed', 'scope': 'Declared test domain',
                       'method': method, 'obligations': [{**self.obligation, 'selector': identity}],
                       'sourceInputs': [self.source], 'modelInputs': [self.model]} for identity in ['R01', 'R02']]
            self.receipts[phase] = {'schemaVersion': 2, 'activity': activity, 'command': ['checker', 'input'], 'executed': True, 'exitCode': 0,
                                    'inputs': [self.specification, self.source, self.model, self.obligation], 'outputs': [self.log], 'claims': claims}
        self.receipt = self.receipts['specification']
        self.manifest = {'schemaVersion': 2, 'title': 'Whole project', 'inventory': {'source': self.specification,
                         'sections': [{'heading': '## Acceptance', 'kind': 'table'}]}, 'receipts': [], 'architectureInputs': [self.architecture], 'productionInputs': [self.source],
                         'requirements': [{'id': identity, **{phase: {'claims': [phase + identity]} for phase in module.PHASES}} for identity in ['R01', 'R02']]}
        self.manifest['receipts'] = [self.save_receipt(phase) for phase in module.PHASES]
        self.make_reviews()

    def write(self, path, data):
        (self.root / path).write_text(data)
        return {'path': path, 'sha256': hashlib.sha256(data.encode()).hexdigest()}

    def save_receipt(self, phase='specification'):
        return self.write(phase + '-receipt.json', json.dumps(self.receipts[phase]))

    def intent(self):
        return [{'requirementID': identity, 'basis': 'existingSpecification', 'decision': 'Preserve the condition',
                 'rationale': 'The governing requirement defines this result', 'source': 'SPEC.md#acceptance'}
                for identity in ['R01', 'R02']]

    def make_reviews(self):
        self.manifest['reviews'] = []
        for stage in module.STAGES:
            architecture = self.manifest.get('architectureInputs', []) if stage in {'requirements', 'integration'} else []
            review = {'schemaVersion': 1, 'stage': stage, 'requirements': ['R01', 'R02'], 'decision': 'passed', 'summary': 'Reviewed controlled fixture scope',
                      'findings': [], 'inputs': [self.specification, *architecture, *self.manifest['productionInputs'], *self.manifest['receipts'], *self.manifest['reviews']]}
            if stage == 'requirements':
                review['intent'] = self.intent()
            self.manifest['reviews'].append(self.write(stage + '-review.json', json.dumps(review)))

    def update_receipt(self, phase='specification'):
        self.manifest['receipts'][module.PHASES.index(phase)] = self.save_receipt(phase)

    def update_review(self, stage, change):
        index = module.STAGES.index(stage)
        review = json.loads((self.root / self.manifest['reviews'][index]['path']).read_text())
        change(review)
        self.manifest['reviews'][index] = self.write(stage + '-review.json', json.dumps(review))

    def build(self):
        return module.build(self.root, self.manifest)['metadata']['verificationReport']

    def test_complete_both_phases_and_correspondence(self):
        value = self.build()
        self.assertEqual(value['inventory'], ['R01', 'R02'])
        self.assertEqual(value['outcome'], 'passed')
        self.assertTrue(all(row[phase]['outcome'] == 'passed' for row in value['requirements'] for phase in module.PHASES))

    def test_unanswered_intent_blocks_even_successful_checker_evidence(self):
        def mark_pending(review):
            review['intent'][0]['basis'] = 'pending'
        self.update_review('requirements', mark_pending)
        self.manifest['reviews'] = self.manifest['reviews'][:1]
        workflow = self.build()['workflow']
        self.assertEqual(workflow['returnTo'], 'requirements')
        self.assertEqual(workflow['stages'][1]['status'], 'blocked')
        self.assertEqual(workflow['stages'][1]['evidence'], 'passed')

    def test_user_acceptance_is_independent_and_linked_to_current_reviews(self):
        self.assertEqual(self.build()['userAcceptance']['status'], 'notRecorded')
        record = {'schemaVersion': 1, 'decision': 'changesRequested', 'source': 'User review message',
                  'summary': 'Revise the presented behavior', 'integrationReviews': [self.manifest['reviews'][-1]]}
        self.manifest['userAcceptance'] = self.write('acceptance.json', json.dumps(record))
        document = module.build(self.root, self.manifest)
        report = document['metadata']['verificationReport']
        self.assertEqual((report['outcome'], report['userAcceptance']['status']), ('passed', 'changesRequested'))
        edges = {(edge['source'], edge['target']) for edge in document['edges']}
        nodes = {node['id']: node for node in document['nodes']}
        self.assertIn(('intent-R01', 'R01'), edges)
        self.assertTrue(any(source == 'R01' and nodes[target]['role'] == 'verification evidence'
                            and any(parent == target and nodes[file]['role'] == 'implementation source' for parent, file in edges)
                            for source, target in edges))
        self.update_review('integration', lambda review: review.update(summary='Revised integration review'))
        self.assertEqual(self.build()['userAcceptance']['status'], 'notRecorded')

    def test_deferred_implementation_resumes_with_unaffected_receipts(self):
        stable_source = self.write('Stable.swift', 'func stable() -> Bool { true }')
        stable_model = self.write('stable-model.json', '{"model":"stable"}')
        spec_receipt = self.receipts['specification']
        spec_receipt['inputs'] = [self.specification, self.obligation]
        spec_reference = self.save_receipt()
        review_references = [
            self.write(stage + '-review.json', json.dumps({
                'schemaVersion': 1, 'stage': stage, 'requirements': ['R01', 'R02'],
                'decision': 'passed', 'summary': 'Reviewed independent contracts',
                'inputs': [self.specification, reference], 'findings': [],
                **({'intent': self.intent()} if stage == 'requirements' else {}),
            }))
            for stage, reference in [('requirements', self.architecture), ('specification', spec_reference)]
        ]

        def record_component(identity, source, model):
            references = []
            row = next(row for row in self.manifest['requirements'] if row['id'] == identity)
            for phase in ('implementation', 'correspondence'):
                receipt = copy.deepcopy(self.receipts[phase])
                claim = next(claim for claim in receipt['claims'] if identity in claim['requirements'])
                claim.update(sourceInputs=[source], modelInputs=[model])
                receipt.update(claims=[claim], inputs=[self.specification, self.obligation, source, model])
                references.append(self.write(f'{phase}-{identity}.json', json.dumps(receipt)))
                row[phase] = {'claims': [claim['id']]}
            return references

        affected = record_component('R01', self.source, self.model)
        unchanged = record_component('R02', stable_source, stable_model)
        self.manifest.update(productionInputs=[self.source, stable_source], receipts=[spec_reference, *affected, *unchanged],
                             reviews=review_references.copy())
        for stage in ('implementation', 'correspondence', 'integration'):
            is_implementation = stage == 'implementation'
            self.manifest['reviews'].append(self.write(stage + '-review.json', json.dumps({
                'schemaVersion': 1, 'stage': stage, 'requirements': ['R01', 'R02'],
                'decision': 'changesRequested' if is_implementation else 'passed',
                'summary': 'Fix the affected source' if is_implementation else 'Reviewed available evidence',
                'inputs': [self.specification, self.architecture, *self.manifest['productionInputs'],
                           *self.manifest['receipts'], *self.manifest['reviews']],
                'findings': [{'requirementID': 'R01', 'returnTo': 'implementation', 'reason': 'Behavior review found a defect'}]
                            if is_implementation else [],
            })))
        self.assertEqual(self.build()['workflow']['returnTo'], 'implementation')

        revised_source = self.write('Code.swift', 'func value() -> Bool { 1 == 1 }')
        self.manifest['productionInputs'] = [revised_source, stable_source]
        with self.assertRaisesRegex(ValueError, 'Changed evidence input: Code.swift'):
            self.build()

        self.manifest.update(receipts=[spec_reference, *unchanged], reviews=review_references.copy())
        for phase in ('implementation', 'correspondence'):
            self.manifest['requirements'][0][phase] = {'claims': [], 'reason': 'Deferred until the component is ready'}
        deferred = self.build()['workflow']
        self.assertEqual(deferred['outcome'], 'incomplete')
        self.assertEqual(deferred['returnTo'], 'implementation')
        self.assertEqual(deferred['coveredProductionInputCount'], 1)
        self.assertEqual([stage['status'] for stage in deferred['stages']],
                         ['passed', 'passed', 'incomplete', 'blocked', 'blocked'])

        current_model = self.write('model.json', '{"model":"revised"}')
        self.manifest['receipts'].extend(record_component('R01', revised_source, current_model))
        for stage in ('implementation', 'correspondence', 'integration'):
            self.manifest['reviews'].append(self.write(stage + '-review.json', json.dumps({
                'schemaVersion': 1, 'stage': stage, 'requirements': ['R01', 'R02'],
                'decision': 'passed', 'summary': 'Reviewed fixed inputs and retained evidence',
                'inputs': [self.specification, self.architecture, *self.manifest['productionInputs'],
                           *self.manifest['receipts'], *self.manifest['reviews']], 'findings': [],
            })))
        current = self.build()['workflow']
        self.assertEqual(current['outcome'], 'passed')
        self.assertIsNone(current['returnTo'])
        self.assertEqual(current['coveredProductionInputCount'], 2)

    def test_missing_stage_reviews_cannot_pass(self):
        self.manifest['reviews'] = []
        result = self.build()
        self.assertEqual(result['outcome'], 'incomplete')
        self.assertEqual(result['workflow']['returnTo'], 'requirements')
        self.assertEqual([stage['status'] for stage in result['workflow']['stages']], ['incomplete', 'blocked', 'blocked', 'blocked', 'blocked'])

    def test_missing_architecture_blocks_requirements_even_with_complete_formal_evidence(self):
        self.manifest.pop('architectureInputs')
        self.make_reviews()
        (self.root / 'ARCHITECTURE.dsl').unlink()
        result = self.build()
        self.assertEqual(result['outcome'], 'incomplete')
        self.assertEqual(result['workflow']['returnTo'], 'requirements')
        self.assertIn('ARCHITECTURE.dsl', ' '.join(result['workflow']['stages'][0]['reasons']))

    def test_integration_review_must_bind_the_architecture_even_when_requirements_pass(self):
        self.update_review('integration', lambda review: review['inputs'].remove(self.architecture))
        result = self.build()
        self.assertEqual(result['workflow']['returnTo'], 'integration')
        self.assertEqual(result['workflow']['stages'][0]['status'], 'passed')
        self.assertEqual(result['outcome'], 'incomplete')

    def test_revised_contract_invalidates_the_old_review(self):
        self.manifest['architectureInputs'] = [self.write('ARCHITECTURE.dsl', 'workspace "Changed" {\nmodel {\n}\n}\n')]
        with self.assertRaisesRegex(ValueError, 'Changed evidence input: ARCHITECTURE.dsl'):
            self.build()

    def test_included_declarations_must_be_recorded_and_bound_in_reviews(self):
        contract = self.write('ARCHITECTURE.dsl', 'workspace {\nmodel {\n!include "subject.dsl"\n}\n}\n')
        fragment = self.write('subject.dsl', 'sample = softwareSystem "Sample"\n')
        self.manifest['architectureInputs'] = [contract]
        with self.assertRaisesRegex(ValueError, 'unbound architecture declaration: subject.dsl'):
            self.build()
        self.manifest['architectureInputs'].append(fragment)
        self.make_reviews()
        self.assertEqual(self.build()['outcome'], 'passed')

    def test_generation_command_cannot_supply_passed_formal_claims(self):
        self.receipts['implementation']['command'] = ['formal', 'translate', '--draft-unvalidated']
        self.update_receipt('implementation')
        try:
            value = self.build()
        except ValueError:
            return
        self.assertNotEqual(value['outcome'], 'passed')

    def test_grouping_retains_every_requirement_and_assessment(self):
        for row in self.manifest['requirements']:
            row['group'] = 'Execution contracts'
        document = module.build(self.root, self.manifest)
        group = next(node for node in document['nodes'] if node['role'] == 'requirement group')
        self.assertEqual(len(group['details']['requirements']), 2)
        self.assertEqual([node['id'] for node in document['nodes'] if node.get('parentID') == group['id']], ['R01', 'R02'])
        phases = [edge for edge in document['edges'] if edge.get('role') in module.PHASES]
        self.assertEqual(len(phases), 3)
        self.assertTrue(all(edge['source'] == group['id'] and edge['label'] == '2/2 verified' for edge in phases))

    def test_missing_or_duplicate_requirement_is_rejected(self):
        for change in [lambda rows: rows.pop(), lambda rows: rows.append(copy.deepcopy(rows[0]))]:
            original = copy.deepcopy(self.manifest)
            change(self.manifest['requirements'])
            with self.assertRaises(ValueError):
                self.build()
            self.manifest = original

    def test_changed_specification_or_checker_output_is_rejected(self):
        for name in ['SPEC.md', 'checker.log']:
            original = (self.root / name).read_bytes()
            (self.root / name).write_text('changed')
            with self.assertRaises(ValueError):
                self.build()
            (self.root / name).write_bytes(original)

    def test_wrong_phase_or_requirement_is_rejected(self):
        for claim in ['implementationR01', 'specificationR02']:
            self.manifest['requirements'][0]['specification']['claims'] = [claim]
            with self.assertRaises(ValueError):
                self.build()

    def test_incomplete_source_correspondence_survives_model_success(self):
        self.manifest['requirements'][0]['correspondence'] = {'claims': [], 'reason': 'No semantic certificate'}
        self.make_reviews()
        self.assertEqual(self.build()['requirements'][0]['correspondence']['outcome'], 'notVerified')
        self.assertEqual(self.build()['outcome'], 'incomplete')

    def test_failed_process_cannot_supply_a_passed_claim(self):
        self.receipt['exitCode'] = 1
        self.update_receipt()
        with self.assertRaises(ValueError):
            self.build()

    def test_unexecuted_process_cannot_supply_a_passed_claim(self):
        self.receipt['executed'] = False
        self.update_receipt()
        with self.assertRaises(ValueError):
            self.build()

    def test_regression_claim_cannot_replace_a_formal_claim(self):
        self.receipt['claims'][0]['domain'] = 'regression.unit'
        self.update_receipt()
        with self.assertRaises(ValueError):
            self.build()

    def test_unvalidated_translation_cannot_be_promoted(self):
        self.receipts['correspondence']['claims'][0]['domain'] = 'translation.unvalidated'
        self.update_receipt('correspondence')
        with self.assertRaises(ValueError):
            self.build()

    def test_unsupported_and_failed_claims_keep_original_outcomes(self):
        self.receipt['claims'][0]['outcome'] = 'unsupported'
        self.receipts['implementation']['claims'][0]['outcome'] = 'failed'
        self.update_receipt()
        self.update_receipt('implementation')
        self.make_reviews()
        row = self.build()['requirements'][0]
        self.assertEqual(row['specification']['outcome'], 'unsupported')
        self.assertEqual(row['implementation']['outcome'], 'failed')
        self.assertEqual(self.build()['outcome'], 'failed')

    def test_passed_claim_needs_a_named_checked_obligation(self):
        for field in ['obligations', 'sourceInputs', 'modelInputs']:
            with self.subTest(field=field):
                original = copy.deepcopy(self.receipts['implementation'])
                del self.receipts['implementation']['claims'][0][field]
                self.update_receipt('implementation')
                with self.assertRaises(ValueError):
                    self.build()
                self.receipts['implementation'] = original

    def test_uncovered_production_input_blocks_implementation_gate(self):
        self.manifest['productionInputs'].append(self.write('Other.swift', 'func other() {}'))
        self.make_reviews()
        result = self.build()
        self.assertEqual(result['outcome'], 'incomplete')
        self.assertEqual(result['workflow']['returnTo'], 'implementation')
        self.assertEqual(result['workflow']['stages'][2]['review'], 'passed')
        self.assertEqual(result['workflow']['coveredProductionInputCount'], 1)
        self.assertEqual(result['workflow']['productionInputCount'], 2)

    def test_generation_activity_cannot_be_relabelled_as_a_proof(self):
        self.receipts['implementation']['activity'] = 'modelGeneration'
        for claim in self.receipts['implementation']['claims']:
            claim['method'] = 'generation'
        self.update_receipt('implementation')
        with self.assertRaises(ValueError):
            self.build()

    def test_duplicate_requirement_binding_is_invalid(self):
        self.receipts['implementation']['claims'][0]['requirements'] = ['R01', 'R01']
        self.update_receipt('implementation')
        with self.assertRaises(ValueError):
            self.build()

    def test_revision_invalidates_owner_and_blocks_dependents(self):
        self.update_review('specification', lambda review: review.update(decision='changesRequested', findings=[{'requirementID':'R01','returnTo':'requirements','reason':'The original contract omits a failure case'}]))
        self.manifest['reviews'] = self.manifest['reviews'][:2]
        value = self.build()['workflow']
        self.assertEqual(value['returnTo'], 'requirements')
        self.assertEqual(value['stages'][0]['status'], 'incomplete')
        self.assertTrue(all(stage['status'] == 'blocked' for stage in value['stages'][1:]))

    def test_review_without_current_receipt_basis_is_incomplete(self):
        self.update_review('specification', lambda review: review.update(inputs=[self.specification]))
        self.manifest['reviews'] = self.manifest['reviews'][:2]
        result = self.build()
        self.assertEqual(result['outcome'], 'incomplete')
        self.assertEqual(result['workflow']['returnTo'], 'specification')

    def test_overlapping_reviews_are_not_silently_selected(self):
        self.manifest['reviews'].append(self.manifest['reviews'][0])
        with self.assertRaises(ValueError):
            self.build()

    def test_changed_review_cannot_be_reused(self):
        (self.root / 'requirements-review.json').write_text('{}')
        with self.assertRaises(ValueError):
            self.build()

    def test_path_outside_repository_is_rejected(self):
        self.manifest['inventory']['source']['path'] = '../SPEC.md'
        with self.assertRaises(ValueError):
            self.build()

    def test_cli_preserves_incomplete_report_and_rejects_changed_evidence(self):
        manifest_path = self.root / 'manifest.json'
        output = self.root / 'Report.json'
        command = [sys.executable, str(source), '--workspace', str(self.root), '--manifest', str(manifest_path), '--output', str(output)]
        manifest_path.write_text(json.dumps(self.manifest))
        complete = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual(complete.returncode, 0, complete.stderr)
        self.assertEqual(json.loads(complete.stdout)['outcome'], 'passed')
        self.manifest['requirements'][0]['correspondence'] = {'claims': [], 'reason': 'Unvalidated source'}
        manifest_path.write_text(json.dumps(self.manifest))
        incomplete = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual(incomplete.returncode, 6, incomplete.stderr)
        self.assertEqual(json.loads(output.read_text())['metadata']['verificationReport']['outcome'], 'incomplete')
        retained = output.read_bytes()
        (self.root / 'checker.log').write_text('changed evidence')
        rejected = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual(output.read_bytes(), retained)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--write-fixtures':
        destination = Path(sys.argv[2])
        destination.mkdir(parents=True, exist_ok=True)
        fixture = ProjectReportTests()
        fixture.setUp()
        try:
            (destination / 'passed.json').write_text(json.dumps(module.build(fixture.root, fixture.manifest)))
            fixture.manifest['reviews'] = []
            (destination / 'incomplete.json').write_text(json.dumps(module.build(fixture.root, fixture.manifest)))
            fixture.make_reviews()
            fixture.update_review('specification', lambda review: review.update(decision='changesRequested', findings=[{'requirementID':'R01','returnTo':'requirements','reason':'Missing boundary contract'}]))
            fixture.manifest['reviews'] = fixture.manifest['reviews'][:2]
            (destination / 'revision.json').write_text(json.dumps(module.build(fixture.root, fixture.manifest)))
        finally:
            fixture.doCleanups()
    else:
        unittest.main()
