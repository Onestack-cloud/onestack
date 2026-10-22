import datetime as dt
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
from monitor import assess, floors_for, health, atomic, availability_scan, cached_image


class SecurityMonitorTests(unittest.TestCase):
    def test_cached_image_requires_same_digest_scanner_and_valid_exact_database(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'image.json';db={'built':'2026-10-22T06:00:00Z','schemaVersion':'v6','from':'https://publisher.example/db?checksum=known','valid':True}
            raw={'descriptor':{'name':'grype','version':'1.0','db':{'status':db}},'source':{'type':'image','target':{'imageID':'sha256:approved'}},'matches':[]}
            path.write_text(json.dumps(raw))
            self.assertIsNotNone(cached_image(path,'sha256:approved',db,'1.0'))
            self.assertIsNone(cached_image(path,'sha256:changed',db,'1.0'))
            self.assertIsNone(cached_image(path,'sha256:approved',{**db,'built':'2026-10-23T06:00:00Z'},'1.0'))
            self.assertIsNone(cached_image(path,'sha256:approved',db,'2.0'))
            self.assertIsNone(cached_image(path,'sha256:approved',{**db,'from':'https://publisher.example/db?checksum=changed'},'1.0'))
    def test_expected_authentication_denial_is_a_passing_access_control(self):
        with patch('monitor.urllib.request.urlopen', side_effect=urllib.error.HTTPError('https://example.test',401,'Denied',{},None)):
            result=availability_scan({'publicChecks':[{'url':'https://example.test','expected':401}]})
            self.assertEqual(result['state'],'checked')
            self.assertTrue(result['checks'][0]['passed'])
    def test_advisory_feed_never_reduces_the_patched_floor(self):
        floors = floors_for([{'version': 'v24.22.0', 'security': True}, {'version': 'v24.23.1', 'security': True}])
        self.assertEqual(floors['24'], '24.23.1')
        self.assertEqual(floors['22'], '22.23.4')

    def test_missing_security_metadata_is_unknown(self):
        with self.assertRaises(ValueError):
            floors_for([{'version': 'v24.23.1'}])

    def test_old_and_unsupported_runtime_detection(self):
        schedule = {'v24': {'start': '2025-04-22', 'end': '2028-04-30'}}
        self.assertIsNotNone(assess('24.21.0', {'24': '24.22.1'}, schedule, '2026-10-22'))
        self.assertIsNone(assess('24.22.1', {'24': '24.22.1'}, schedule, '2026-10-22'))
        self.assertIsNotNone(assess('24.22.1', {'24': '24.22.1'}, schedule, '2028-04-30'))

    def test_missing_stale_unknown_and_affected_reports_raise_attention(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            requirements = {'runtime.json': 3600}
            self.assertEqual(health(output, requirements)['state'], 'attention')
            stamp = dt.datetime.now(dt.timezone.utc).timestamp()
            for state in ['affected', 'unknown']:
                atomic(output / 'runtime.json', {'checkedAt': dt.datetime.fromtimestamp(stamp, dt.timezone.utc).isoformat(), 'state': state})
                self.assertEqual(health(output, requirements, stamp)['state'], 'attention')
            atomic(output / 'runtime.json', {'checkedAt': dt.datetime.fromtimestamp(stamp, dt.timezone.utc).isoformat(), 'state': 'checked'})
            self.assertEqual(health(output, requirements, stamp)['state'], 'checked')
            self.assertEqual(health(output, requirements, stamp + 3601)['state'], 'attention')
            self.assertEqual(health(output, requirements, stamp - 301)['state'], 'attention')
            self.assertEqual(json.loads((output / 'runtime.json').read_text())['state'], 'checked')


if __name__ == '__main__':
    unittest.main()
