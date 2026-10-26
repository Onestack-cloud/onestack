import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from monitor import now


spec = importlib.util.spec_from_file_location('source_monitor', Path(__file__).with_name('source-monitor.py'))
source_monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source_monitor)


class SourceCoverageTests(unittest.TestCase):
    repository = {'repository': 'example/service', 'platform': 'github', 'profile': 'github'}
    workflow = {'id': 123, 'status': 'completed', 'html_url': 'https://example.test/run/123', 'head_sha': 'a' * 40}

    def report(self):
        return {'checkedAt': now(), 'state': 'affected', 'audits': [], 'gate': 'passed',
                'existingAdvisories': ['root:package:GHSA-example'], 'findings': [{'detail': 'known finding'}]}

    def test_empty_listing_is_retried_before_reading_the_report(self):
        responses = [json.dumps({'workflow_runs': []}),
                     json.dumps({'workflow_runs': [self.workflow]}), json.dumps(self.report())]
        with tempfile.TemporaryDirectory() as directory, patch.object(source_monitor, 'run', side_effect=responses) as run:
            report = source_monitor.scan([self.repository], Path(directory))
        self.assertEqual(report['state'], 'affected')
        self.assertEqual(report['repositories'][0]['advisories'], ['root:package:GHSA-example'])
        self.assertEqual(run.call_count, 3)

    def test_exhausted_listing_stays_unknown_and_preserves_last_known_findings(self):
        previous = {'repository': 'example/service', 'state': 'affected', 'checkedAt': '2026-01-01T00:00:00+00:00',
                    'commit': 'b' * 40, 'advisories': ['root:package:GHSA-existing'],
                    'findings': [{'detail': 'unresolved finding'}]}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / 'sources.json').write_text(json.dumps({'repositories': [previous]}))
            with patch.object(source_monitor, 'run', return_value=json.dumps({'workflow_runs': []})) as run:
                report = source_monitor.scan([self.repository], output)
            row = report['repositories'][0]
            self.assertEqual(report['state'], 'unknown')
            self.assertEqual(row['state'], 'unknown')
            self.assertEqual(row['lastKnownReport'], previous)
            self.assertNotIn('checkedAt', row)
            self.assertEqual(run.call_count, 3)
            with patch.object(source_monitor, 'run', return_value=json.dumps({'workflow_runs': []})):
                again = source_monitor.scan([self.repository], output)
            self.assertEqual(again['repositories'][0]['lastKnownReport'], previous)

    def test_running_workflow_is_unknown_without_reusing_an_older_pass(self):
        response = json.dumps({'workflow_runs': [{**self.workflow, 'status': 'in_progress'}]})
        with tempfile.TemporaryDirectory() as directory, patch.object(source_monitor, 'run', return_value=response) as run:
            report = source_monitor.scan([self.repository], Path(directory))
        self.assertEqual(report['state'], 'unknown')
        self.assertNotIn('checkedAt', report['repositories'][0])
        self.assertEqual(run.call_count, 1)


if __name__ == '__main__':
    unittest.main()
