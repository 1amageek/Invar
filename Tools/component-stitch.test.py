#!/usr/bin/env python3
"""Exercise the component runner's evidence decisions."""
import importlib.util
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

sys.dont_write_bytecode = True
runner = Path(__file__).resolve().parents[1] / 'Sources/InvarSkills/skills/verify-project/scripts/component_stitch.py'
spec = importlib.util.spec_from_file_location('component_stitch', runner)
component_stitch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(component_stitch)


class ComponentStitchTests(unittest.TestCase):
    def setUp(self):
        self.arguments = SimpleNamespace(seconds=3, endpoint=['reset'])
        self.stats = {'workers': 1, 'elapsed_secs': 3, 'execs': 24, 'crashes_saved': 0, 'crashing_execs': 0,
                      'endpoints': [{'name': 'reset', 'ok': 9}]}

    def observe(self, **stats):
        return component_stitch.observe({'stats': self.stats | stats}, self.arguments)

    def test_completed_campaign_with_required_endpoint_yields_bounded_observation(self):
        self.assertEqual(self.observe(), ('noViolationObservedWithinBudget', 0))

    def test_observed_failure_is_retained_even_when_required_endpoint_did_not_finish(self):
        self.assertEqual(self.observe(crashing_execs=1, endpoints=[]), ('findingObserved', 5))

    def test_missing_successful_invocation_is_incomplete(self):
        with self.assertRaisesRegex(ValueError, 'Required Endpoint'):
            self.observe(endpoints=[{'name': 'reset', 'ok': 0}])

    def test_unstarted_or_interrupted_worker_is_incomplete(self):
        for updates in ({'execs': 0}, {'elapsed_secs': 2}, {'elapsed_secs': float('nan')}):
            with self.subTest(stats=updates), self.assertRaisesRegex(ValueError, 'execution budget'):
                self.observe(**updates)
        with self.assertRaisesRegex(ValueError, 'statistics'):
            self.observe(workers=0)


if __name__ == '__main__':
    unittest.main()
