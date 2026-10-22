# Security maintenance

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

CI compares advisories with the base commit. Existing findings remain affected and visible; new high/critical advisories, unsafe runtimes and incomplete coverage fail the gate. A passing gate does not mean all findings are resolved. New dependency roots must be registered before CI passes.
