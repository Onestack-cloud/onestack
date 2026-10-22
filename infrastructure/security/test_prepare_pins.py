import base64
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('prepare_pins', Path(__file__).with_name('prepare-pins.py'))
preparation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preparation)


class PairedRuntimeUpdateTests(unittest.TestCase):
    def test_official_checksum_and_related_pins_are_one_commit_on_the_exact_base(self):
        manifest = {'downloads': [{'file': 'download.ts', 'versionPattern': r"VERSION='(\d+\.\d+\.\d+)'",
                                  'checksumPattern': r"SHA='([a-f0-9]{64})'", 'major': 24,
                                  'artifact': 'linux-x64.tar.xz'}],
                    'versionFiles': [{'file': 'mise.toml', 'versionPattern': r'node="(\d+\.\d+\.\d+)"', 'major': 24}]}
        source = {'.security/node-downloads.json': json.dumps(manifest),
                  'download.ts': "VERSION='24.22.1'\nSHA='" + 'a'*64 + "'\n",
                  'mise.toml': 'node="24.22.1"\n'}
        calls = []

        def api(platform, endpoint, env, data=None, optional=False):
            calls.append((endpoint, data))
            if endpoint.endswith('/git/ref/heads/main'): return {'object': {'sha': 'base-commit'}}
            if '/contents/' in endpoint:
                path = endpoint.split('/contents/')[1].split('?')[0]
                self.assertTrue(endpoint.endswith('?ref=base-commit'))
                return {'encoding': 'base64', 'content': base64.b64encode(source[path].encode()).decode()}
            if '/git/ref/heads/security' in endpoint: return None
            if endpoint.endswith('/git/commits/base-commit'): return {'tree': {'sha': 'whole-repository-tree'}}
            if endpoint.endswith('/git/trees'): return {'sha': 'updated-tree'}
            if endpoint.endswith('/git/commits'): return {'sha': 'updated-commit'}
            if endpoint.endswith('/git/refs'): return {}
            if '/pulls?' in endpoint: return []
            if endpoint.endswith('/pulls'): return {'html_url': 'https://example.test/review/1'}
            raise AssertionError(endpoint)

        def feed(path):
            if path == '/dist/index.json': return json.dumps([{'version': 'v24.23.1', 'security': True}])
            version = path.split('/')[2].lstrip('v')
            return ('a' if version == '24.22.1' else 'b')*64 + '  node-v' + version + '-linux-x64.tar.xz\n'

        with patch.object(preparation, 'api', side_effect=api), patch.object(preparation.pins, 'get', side_effect=feed):
            result = preparation.prepare({'nodeDownloadPins': True, 'repository': 'owner/repo', 'platform': 'github'}, 'github', {})
        self.assertEqual(result['state'], 'review required')
        tree = next(data for endpoint, data in calls if endpoint.endswith('/git/trees'))
        self.assertEqual(tree['base_tree'], 'whole-repository-tree')
        self.assertEqual({x['path'] for x in tree['tree']}, {'download.ts', 'mise.toml'})
        self.assertTrue(all('24.23.1' in x['content'] for x in tree['tree']))
        self.assertIn('b'*64, next(x['content'] for x in tree['tree'] if x['path'] == 'download.ts'))
        commit = next(data for endpoint, data in calls if endpoint.endswith('/git/commits'))
        self.assertEqual(commit['parents'], ['base-commit'])
        self.assertFalse(any('force' in (data or {}) for endpoint, data in calls))


if __name__ == '__main__': unittest.main()
