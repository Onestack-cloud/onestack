import datetime as dt
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from providers import ACCOUNT, browser_build, cloudflare_builds


class BuildsAPICredentialTests(unittest.TestCase):
    def test_dedicated_credential_covers_discovery_without_oauth_or_browser(self):
        reference={'projectId':'123e4567-e89b-12d3-a456-426614174000',
                   'environment':'prod','path':'/security-maintenance',
                   'secretName':'CLOUDFLARE_BUILDS_READ_TOKEN'}
        token='synthetic-builds-read-token-for-unit-tests'
        calls=[]
        def api(url,headers):
            calls.append((url,headers))
            self.assertEqual(headers,{'Authorization':'Bearer '+token})
            if url.endswith('/workers/scripts'):
                return {'success':True,'result':[{'id':'r4r-next-js','tag':'runbuddy-tag'},
                                                {'id':'usual-suspects','tag':'usual-tag'}]}
            if url.endswith('/triggers'):
                return {'success':True,'result':[{'trigger_uuid':'synthetic-production-trigger'}]}
            if url.endswith('/environment_variables'):
                return {'success':True,'result':{'NODE_VERSION':{'value':'24.22.1'},
                                                 'UNRELATED_SECRET':{'value':None,'is_secret':True}}}
            self.fail('Unexpected API request')
        with patch('providers.cloudflare_token',side_effect=AssertionError('OAuth must not be required')),\
             patch('providers.subprocess.run') as secret,patch('providers.request',side_effect=api),\
             patch('providers.browser_build',side_effect=AssertionError('Browser must not be required')):
            secret.return_value.returncode=0
            secret.return_value.stdout=token+'\n'
            rows=cloudflare_builds({ACCOUNT:reference})
        self.assertEqual(len(rows),2)
        self.assertTrue(all(row['state']=='checked' and row['node']=='24.22.1' for row in rows))
        self.assertTrue(all(row['verificationSource']=='Cloudflare Builds API' for row in rows))
        self.assertEqual(secret.call_count,1)
        self.assertEqual(len(calls),6)
        self.assertNotIn(token,json.dumps(rows))
        self.assertNotIn('UNRELATED_SECRET',json.dumps(rows))

    def test_invalid_credential_environment_fails_closed_before_secret_lookup(self):
        reference={'projectId':'123e4567-e89b-12d3-a456-426614174000',
                   'environment':'--unexpected','path':'/security-maintenance',
                   'secretName':'CLOUDFLARE_BUILDS_READ_TOKEN'}
        with patch('providers.cloudflare_token',side_effect=AssertionError('No fallback to broader credentials')),\
             patch('providers.subprocess.run') as secret,patch('providers.request') as api:
            rows=cloudflare_builds({ACCOUNT:reference})
        self.assertTrue(all(row['state']=='unknown' for row in rows))
        secret.assert_not_called()
        api.assert_not_called()


class BrowserBuildCoverageTests(unittest.TestCase):
    def test_only_a_fresh_exact_dashboard_observation_counts_as_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'builds-browser.json'
            stamp=dt.datetime.now(dt.timezone.utc)
            record={'checkedAt':stamp.isoformat(),'source':'Cloudflare dashboard via Brave','account':ACCOUNT,
                    'targets':[{'worker':'r4r-next-js','node':'24.22.1',
                                'url':'https://dash.cloudflare.com/'+ACCOUNT+'/workers/services/view/r4r-next-js/production/settings'}]}
            parse_timestamp=dt.datetime.fromisoformat
            def parse_with_legacy_iso_rules(value):
                if value.endswith('Z'):raise ValueError('Explicit UTC offset required')
                return parse_timestamp(value)
            with patch('providers.dt.datetime') as native_datetime:
                native_datetime.fromisoformat.side_effect=parse_with_legacy_iso_rules
                for timestamp in [stamp.isoformat(),stamp.isoformat().replace('+00:00','Z')]:
                    path.write_text(json.dumps({**record,'checkedAt':timestamp}))
                    self.assertEqual(browser_build(path,ACCOUNT,'r4r-next-js','RunBuddy')['node'],'24.22.1')
            for change in [{'checkedAt':(stamp-dt.timedelta(hours=3)).isoformat()},
                           {'checkedAt':(stamp+dt.timedelta(hours=1)).isoformat()},
                           {'account':'another-account'},{'targets':[]},
                           {'targets':[{**record['targets'][0],'url':'https://example.test'}]}]:
                path.write_text(json.dumps({**record,**change}))
                with self.assertRaises(ValueError):browser_build(path,ACCOUNT,'r4r-next-js','RunBuddy')


if __name__=='__main__':unittest.main()
