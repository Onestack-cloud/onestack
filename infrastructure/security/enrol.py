#!/usr/bin/env python3
"""Add the shared security contract to a clean repository without installing dependencies."""
import argparse
import json
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
PINS = {
    'checkout': '3d3c42e5aac5ba805825da76410c181273ba90b1',
    'node': '949feb2413d6458794dcd2491c4babbbce0c15c1',
    'bun': '0c5077e51419868618aeaa5fe8019c62421857d6',
    'artifact': 'cf430e030ddbb5b0abf93d22962f4752f3646cd9',
}


def enrol(root, owner, platform, package_roots, review=True):
    directory = root / '.security'
    targets = [directory, root/'renovate.json']
    if platform == 'github':targets.append(root/'.github/workflows/security.yml')
    if any(path.exists() for path in targets):
        raise ValueError('Existing security configuration must be merged manually before enrolment')
    if platform == 'gitlab' and '\ninclude:' in '\n' + (root/'.gitlab-ci.yml').read_text():
        raise ValueError('Existing GitLab includes must be merged manually before enrolment')
    directory.mkdir()
    for name in ['check-runtime.ts', 'runtime-selfcheck.ts', 'ci.ts', 'report.ts', 'runtime-pins.py']:
        shutil.copyfile(HERE / 'templates' / name, directory / name)
    (directory / 'package.json').write_text('{"private":true,"type":"module"}\n')
    policy = {'schemaVersion': 1, 'owner': owner, 'nodeMajor': 24,
              'minimumNode': {'22': '22.23.4', '24': '24.22.1', '26': '26.12.1'},
              'packageRoots': package_roots,
              'release': {'requiresReview': review, 'automaticPatchReleaseQualified': False,
                          'qualification': None}}
    (directory / 'policy.json').write_text(json.dumps(policy, indent=2) + '\n')
    renovate = {
        '$schema': 'https://docs.renovatebot.com/renovate-schema.json',
        'extends': ['config:recommended'], 'dependencyDashboard': False,
        'timezone': 'Australia/Sydney', 'schedule': ['at any time'],
        'prConcurrentLimit': 3, 'prHourlyLimit': 2, 'automerge': False,
        'rangeStrategy': 'bump', 'minimumReleaseAge': '7 days',
        'vulnerabilityAlerts': {'enabled': True, 'schedule': ['at any time'], 'minimumReleaseAge': '0 days', 'automerge': False},
        'lockFileMaintenance': {'enabled': True, 'schedule': ['before 7am on monday']},
        'packageRules': [
            {'matchPackageNames': ['*'], 'minimumReleaseAge': '7 days'},
            {'matchDatasources': ['node-version'], 'allowedVersions': '>=24 <25', 'groupName': 'Node 24 runtime',
             'minimumReleaseAge': '0 days', 'schedule': ['at any time']},
            {'matchPackageNames': ['node'], 'matchDatasources': ['docker'], 'allowedVersions': '/^24([.-]|$)/', 'minimumReleaseAge': '7 days'},
            {'matchManagers': ['github-actions'], 'matchPackageNames': ['node', 'actions/node-versions'],
             'allowedVersions': '>=24.22.1 <25', 'groupName': 'Node 24 runtime'},
            {'matchUpdateTypes': ['major'], 'dependencyDashboardApproval': False, 'automerge': False, 'minimumReleaseAge': '7 days'},
        ],
        'customManagers': [{
            'customType': 'regex',
            'managerFilePatterns': ['/\\.(?:ya?ml|toml|[cm]?[jt]s)$/'],
            'matchStrings': ['(?:NODE_VERSION|nodeVersion|node-version)[\\"\\\']?\\s*[:=]\\s*[\\"\\\']?(?<currentValue>\\d+\\.\\d+\\.\\d+)'],
            'depNameTemplate': 'node', 'datasourceTemplate': 'node-version', 'versioningTemplate': 'node',
        }],
    }
    path = root / 'renovate.json'
    if path.exists():
        raise ValueError('Existing Renovate policy must be merged manually')
    path.write_text(json.dumps(renovate, indent=2) + '\n')
    document = '''# Security maintenance

This repository participates in the security inventory owned by Onestack infrastructure.
The contract is `.security/policy.json`, the dependency lockfiles, `renovate.json`
and the security CI job. Keep application and CI runtimes on the declared Node
major and commit exact versions with their lockfiles and download checksums.

Run locally with a supported Node and Bun 1.4.3 or later:

```
node --test .security/runtime-selfcheck.ts
node .security/check-runtime.ts
```

The second command reads lockfiles without installing or running package scripts.
It contacts the official Node release feeds and the package registry advisory API.
Exit 1 means affected software; exit 2 means coverage is incomplete. Both require
attention. A failed request or unsupported lockfile must never count as a clean scan.
The report covers known advisories, not absence of compromise.

CI runs `.security/ci.ts` and retains `security-report.json`. It blocks an unsafe
Node runtime, incomplete coverage or high/critical advisories introduced relative
to the PR base. Existing advisories stay explicitly listed as affected software;
they are not waived or reported clean. Scheduled inventory reports all findings.
Job success means the regression gate passed, not that every finding was fixed.

Renovate proposes upgrades through PRs/MRs. Existing tests, review and release
approvals remain mandatory. Automatic patch release is disabled until the
repository policy links a passing update, deployment, live verification and a
qualified recovery procedure. Major upgrades, migrations and sensitive financial
or reporting changes retain review. Never bypass a gate to clear a security finding.
Do not turn a bot's green source scan into a claim that production was patched.

Before merging a runtime update, update every version/checksum pair and check the
actual produced executable. After deployment verify the active release, runtime,
health and anonymous access controls. Retain the previous release until checks pass.
Database and other state changes require their own recovery plan.

When adding a package, workspace or build stage, add every independently locked
package root to `.security/policy.json`. Register a new deployed service in
`infrastructure/security/estate.json` in the Onestack repository, including its
runtime probes, release owner and verification/recovery commands. Add the same
policy and job with `python3 infrastructure/security/enrol.py --help` there.
Keep credentials in the established secret store. Store production scans and
software inventories remotely; share only sanitised findings and version metadata.
'''
    (directory / 'README.md').write_text(document)
    readme = root/'README.md'
    text = readme.read_text() if readme.exists() else ''
    readme.write_text(text + '\nSecurity maintenance and new-service requirements: [.security/README.md](.security/README.md).\n')
    ignore = root/'.gitignore'
    text = ignore.read_text() if ignore.exists() else ''
    ignore.write_text(text + '\n/security-report.json\n')
    if platform == 'github':
        workflow = f'''name: security
on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: '17 18 * * *'
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: security-${{{{ github.ref }}}}
  cancel-in-progress: ${{{{ github.ref != 'refs/heads/main' }}}}
jobs:
  audit:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@{PINS['checkout']} # v7
        with:
          persist-credentials: false
          fetch-depth: 0
      - uses: actions/setup-node@{PINS['node']} # v7
        with:
          node-version: 24.22.1
      - uses: oven-sh/setup-bun@{PINS['bun']} # v2
        with:
          bun-version: 1.4.3
      - run: python3 .security/runtime-pins.py
      - run: node --test .security/runtime-selfcheck.ts
      - name: Check runtime and locked dependencies
        run: node .security/ci.ts
        env:
          SECURITY_BASE_SHA: ${{{{ github.event.pull_request.base.sha || github.event.before || '' }}}}
      - name: Retain the complete security report in job logs and summary
        if: always()
        run: node .security/report.ts
'''
        path = root / '.github/workflows/security.yml'
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            raise ValueError('Existing security workflow must be merged manually')
        path.write_text(workflow)
    else:
        # Isolated from the application's custom runner images and deploy credentials.
        (directory / 'gitlab-ci.yml').write_text('''security-audit:
  stage: .pre
  timeout: 10 minutes
  before_script: []
  variables:
    GIT_SUBMODULE_STRATEGY: none
    GIT_DEPTH: '0'
  script:
    - python3 .security/runtime-pins.py
    - node --test .security/runtime-selfcheck.ts
    - |
      if [ -n "$CI_MERGE_REQUEST_DIFF_BASE_SHA" ]; then
        export SECURITY_BASE_SHA="$CI_MERGE_REQUEST_DIFF_BASE_SHA"
      elif [ -n "$CI_COMMIT_BRANCH" ] && [ "$CI_COMMIT_BRANCH" != "$CI_DEFAULT_BRANCH" ]; then
        export SECURITY_BASE_SHA="$(git merge-base HEAD "origin/$CI_DEFAULT_BRANCH")"
        test -n "$SECURITY_BASE_SHA"
      else
        export SECURITY_BASE_SHA="$CI_COMMIT_BEFORE_SHA"
      fi
    - if [ "$SECURITY_BASE_SHA" = "0000000000000000000000000000000000000000" ]; then unset SECURITY_BASE_SHA; fi
    - node .security/ci.ts
  artifacts:
    when: always
    expire_in: 14 days
    paths: [security-report.json]
''')
        # npm-only GitLab roots do not need a Bun installation for their audit.
        path = root / '.gitlab-ci.yml'
        text = path.read_text()
        include = "include:\n  - local: '.security/gitlab-ci.yml'\n\n"
        if '\ninclude:' in '\n' + text:
            raise ValueError('Existing includes must be merged manually')
        path.write_text(include + text)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('--owner', required=True)
    parser.add_argument('--platform', choices=['github', 'gitlab'], required=True)
    parser.add_argument('--package-root', action='append', default=[])
    args = parser.parse_args()
    enrol(args.root.resolve(), args.owner, args.platform, args.package_root)
