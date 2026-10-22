import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('source_monitor',Path(__file__).with_name('source-monitor.py'))
source=importlib.util.module_from_spec(spec);spec.loader.exec_module(source)


class SourceReportTests(unittest.TestCase):
    def test_affected_inventory_is_retained_when_the_regression_gate_passes(self):
        log='\n'.join('audit\tReport\t2026-10-22T10:00:00Z '+line for line in ['{','"audits":[],"gate":"passed","state":"affected"','}'])
        self.assertEqual(source.report_from_log(log)['state'],'affected')

    def test_missing_or_partial_job_logs_cannot_become_clean_coverage(self):
        for log in ['', '{"state":"checked"}', '{"audits":[],"gate":']:
            with self.assertRaises(ValueError):source.report_from_log(log)


if __name__=='__main__':unittest.main()
