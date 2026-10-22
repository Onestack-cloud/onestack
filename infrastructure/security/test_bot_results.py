import importlib.util
import json
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('run_bot',Path(__file__).with_name('run-bot.py'))
bot=importlib.util.module_from_spec(spec);spec.loader.exec_module(bot)


class PerRepositoryBotResultsTests(unittest.TestCase):
    def test_config_rejection_or_missing_repository_cannot_be_a_successful_run(self):
        good={'msg':'Repository finished','repository':'owner/a','exitCode':0,'result':'done','enabled':True,'onboarded':True}
        self.assertEqual(bot.repository_results(json.dumps(good),['owner/a'])['state'],'checked')
        invalid={**good,'exitCode':5,'result':'config-validation'}
        self.assertEqual(bot.repository_results(json.dumps(invalid),['owner/a'])['state'],'unknown')
        for lines,expected in [([],['owner/a']),([good],['owner/a','owner/b']),([good,good],['owner/a']),
                               ([{**good,'enabled':False}],['owner/a'])]:
            self.assertEqual(bot.repository_results('\n'.join(map(json.dumps,lines)),expected)['state'],'unknown')


if __name__=='__main__':unittest.main()
