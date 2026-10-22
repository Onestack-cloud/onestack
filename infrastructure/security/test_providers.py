import datetime as dt
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from providers import ACCOUNT, azure, azure_native_ssh, browser_build, cloudflare_builds, cloudflare_token, refresh_cloudflare_oauth


class PagesOAuthCoverageTests(unittest.TestCase):
    def test_only_a_current_token_is_read_after_noninteractive_session_refresh(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);path=home/'.wrangler/config/default.toml';path.parent.mkdir(parents=True)
            path.write_text('oauth_token = "synthetic-old-token"\nexpiration_time = "2025-01-01T00:00:00Z"\n')
            def refreshed():
                expiry=(dt.datetime.now(dt.timezone.utc)+dt.timedelta(hours=1)).isoformat()
                path.write_text('oauth_token = "synthetic-refreshed-token"\nexpiration_time = "'+expiry+'"\n')
            with patch('providers.Path.home',return_value=home),patch('providers.refresh_cloudflare_oauth',side_effect=refreshed) as refresh:
                self.assertEqual(cloudflare_token(),'synthetic-refreshed-token')
                refresh.assert_called_once_with()

    def test_failed_refresh_or_still_expired_tokens_cannot_become_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);path=home/'.wrangler/config/default.toml';path.parent.mkdir(parents=True)
            path.write_text('oauth_token = "synthetic-expired-token"\nexpiration_time = "2025-01-01T00:00:00Z"\n')
            with patch('providers.Path.home',return_value=home):
                for error in [None,RuntimeError('Synthetic refresh failure')]:
                    with patch('providers.refresh_cloudflare_oauth',side_effect=error):
                        with self.assertRaises(RuntimeError):cloudflare_token()

    def test_refresh_uses_pinned_readonly_wrangler_without_interactive_or_api_token_auth(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);base=home/'.local/share/security-maintenance'
            wrangler=base/'bot/node_modules/wrangler/bin/wrangler.js';wrangler.parent.mkdir(parents=True);wrangler.write_text('')
            node=base/'synthetic-node';node.write_text('')
            (base/'bot-policy.json').write_text(json.dumps({'node':str(node)}))
            with patch('providers.Path.home',return_value=home),patch('providers.subprocess.run') as run,\
                 patch.dict('providers.os.environ',{'CLOUDFLARE_API_TOKEN':'synthetic-unrelated-token'}):
                run.return_value.returncode=0
                refresh_cloudflare_oauth()
            command=run.call_args.args[0]
            self.assertEqual(command,[str(node),str(wrangler),'whoami','--json','--account',ACCOUNT])
            environment=run.call_args.kwargs['env']
            self.assertEqual(environment['CI'],'true')
            self.assertEqual(environment['BROWSER'],'none')
            self.assertNotIn('CLOUDFLARE_API_TOKEN',environment)


class AzureRuntimeCoverageTests(unittest.TestCase):
    def test_ssh_loader_follows_the_installed_cli_launcher_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            launcher=root/'libexec/bin/az';launcher.parent.mkdir(parents=True);launcher.write_text('synthetic launcher')
            library=root/'libexec/lib/python3.14/site-packages'
            module=library/'azure/cli/__main__.py';module.parent.mkdir(parents=True);module.write_text('')
            link=root/'bin/az';link.parent.mkdir();link.symlink_to(launcher)
            def which(name):return {'az':str(link),'python3.14':'/synthetic/python3.14'}.get(name)
            with patch('providers.shutil.which',side_effect=which),patch('providers.subprocess.run') as run:
                run.return_value.returncode=0
                azure_native_ssh()
            self.assertEqual(run.call_args.args[0][0],'/synthetic/python3.14')
            self.assertEqual(run.call_args.kwargs['env']['PYTHONPATH'],str(library.resolve()))

    def probe(self, *, execute_available=True, fallback_error=None, stale=False, processes=True):
        def cli(args):
            if args[1:4]==['webapp','config','show']:
                return {'appCommandLine':'/home/site/wwwroot/.runtime/node --no-maglev-osr /home/site/wwwroot/server.js',
                        'linuxFxVersion':'NODE|24-lts'}
            if args[1:3]==['webapp','exec']:
                if not execute_available:raise RuntimeError('Synthetic unavailable API')
                return []
            if args[1:3]==['account','get-access-token']:
                return {'accessToken':'synthetic-provider-token'}
            self.fail('Unexpected CLI operation')
        timestamp=dt.datetime.now(dt.timezone.utc)-dt.timedelta(hours=1 if stale else 0)
        receipt={'checkedAt':timestamp.isoformat(),'packaged':'24.22.1','sourceCommit':'a'*40,
                 'processes':[{'pid':7,'node':'24.22.1'}] if processes else []}
        with patch('providers.cli',side_effect=cli),patch('providers.request',return_value=receipt),\
             patch('providers.azure_native_ssh',side_effect=fallback_error) as fallback,\
             patch('providers.time.sleep'):
            result=azure()
        return result,fallback

    def test_native_execute_success_does_not_require_ssh(self):
        result,fallback=self.probe()
        self.assertEqual(result['verificationSource'],'Azure execute API')
        self.assertEqual(result['processes'],[{'pid':7,'node':'24.22.1'}])
        fallback.assert_not_called()

    def test_unavailable_execute_api_uses_same_fresh_app_container_receipt(self):
        result,fallback=self.probe(execute_available=False)
        self.assertEqual(result['verificationSource'],'Azure CLI authenticated app SSH')
        self.assertEqual(result['state'],'checked')
        self.assertEqual(result['executeApiState'],'unavailable')
        self.assertNotIn('synthetic-provider-token',json.dumps(result))
        fallback.assert_called_once_with()

    def test_failed_ssh_cannot_become_checked_coverage(self):
        with self.assertRaises(RuntimeError):
            self.probe(execute_available=False,fallback_error=RuntimeError('Synthetic failed SSH'))

    def test_stale_or_empty_process_receipts_cannot_become_checked_coverage(self):
        for values in [{'stale':True},{'processes':False}]:
            with self.assertRaises(ValueError):self.probe(execute_available=False,**values)


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
