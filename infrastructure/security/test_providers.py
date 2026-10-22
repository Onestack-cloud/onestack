import datetime as dt
import json
from pathlib import Path
import tempfile
import unittest
from providers import ACCOUNT, browser_build


class BrowserBuildCoverageTests(unittest.TestCase):
    def test_only_a_fresh_exact_dashboard_observation_counts_as_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'builds-browser.json'
            stamp=dt.datetime.now(dt.timezone.utc)
            record={'checkedAt':stamp.isoformat(),'source':'Cloudflare dashboard via Brave','account':ACCOUNT,
                    'targets':[{'worker':'r4r-next-js','node':'24.22.1',
                                'url':'https://dash.cloudflare.com/'+ACCOUNT+'/workers/services/view/r4r-next-js/production/settings'}]}
            path.write_text(json.dumps(record))
            self.assertEqual(browser_build(path,ACCOUNT,'r4r-next-js','RunBuddy')['node'],'24.22.1')
            for change in [{'checkedAt':(stamp-dt.timedelta(hours=3)).isoformat()},
                           {'checkedAt':(stamp+dt.timedelta(hours=1)).isoformat()},
                           {'account':'another-account'},{'targets':[]},
                           {'targets':[{**record['targets'][0],'url':'https://example.test'}]}]:
                path.write_text(json.dumps({**record,**change}))
                with self.assertRaises(ValueError):browser_build(path,ACCOUNT,'r4r-next-js','RunBuddy')


if __name__=='__main__':unittest.main()
