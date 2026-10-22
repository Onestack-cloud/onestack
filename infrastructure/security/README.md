# Security maintenance

This directory owns the shared security contract and native detection jobs for
the eight active repositories in `estate.json`. It distinguishes advisory
findings, a tested source change, an image candidate and a verified live release.
The initial estate includes existing findings. A passing regression gate does
not mean those findings were fixed or that a system was never compromised.

## What runs

| Surface | Detection and cadence | Update policy |
| --- | --- | --- |
| Eight repositories | PR/MR, main and daily Node/EOL and locked npm/Bun audits | Renovate opens reviewed updates. Existing application CI and release owners remain mandatory |
| Onestack Elixir | Exact Hex package versions and Git commits in `mix.lock`, queried against OSV | Review required; unscored advisories stay visible and block new regressions |
| VPS root and four registered guests | Actual Node/Undici probes hourly, OS package and running-image scans nightly | Private image candidates only; no automatic application replacement |
| Public services and JobLink | HTTP/TLS and expected nameserver checks hourly | Report changes. DNS restoration requires its own owner approval |
| Mac | Installed vendor/developer Node executables and loaded executable mappings hourly while awake | Vendor apps use supported updaters. Never modify signed bundles |
| Provider settings | Azure packaged/running executable, Cloudflare build pins and runner release checks while Mac is awake | Drift or unavailable authentication requires attention |
| Maintenance tool itself | Official Node security release feed and tooling audit before credentials | Qualified Node 24 security updates only, with staging, compatibility checks and guarded rollback |

The VPS timers do not depend on the Mac or Codex. Their health unit fails when
reports are missing, stale, unknown or affected. The existing off-host host
heartbeat observes failed units. A supplemental hourly Codex heartbeat reviews
meaningful changes and required actions without repeating unchanged findings.
Mac and provider checks remain unavailable while the Mac is asleep; their
timestamps must be checked before relying on them.

## Install and verify

Use a reviewed checkout and the existing `onestack-admin` route:

```
python3 infrastructure/security/deploy.py
python3 infrastructure/security/deploy.py --guest onestack-ci-runner
python3 infrastructure/security/deploy.py --guest onestack-codex
python3 infrastructure/security/deploy.py --guest onestack-sandbox
python3 infrastructure/security/deploy.py --guest nomad-vps-worker
```

The installer writes detector source, policy and owned systemd units. It never
stops application units, restarts containers or copies provider credentials.
Scanners are installed from the official pinned archives in `tools.json`.
Their advisory database must be valid and current. Cold imports can take
several minutes; imports share a lock and bounded resource budgets. A timeout
is unknown coverage, never a clean result. Do not cancel active CI work to make
a security scan finish sooner.

Private VPS state is `/var/lib/onestack-security`. `runtime.json`, `images.json`,
`os.json`, `availability.json`, `candidates.json` and `health.json` are the
operational receipts. Images and inventories stay remote. OS inventory copies
only `/var/lib/dpkg/status` and `/etc/os-release`; it does not enumerate databases,
home directories, application volumes or backups. Image scans read image layers,
without mounting production volumes.

The Mac installer takes explicit patched tool paths:

```
python3 infrastructure/security/install-mac.py --node /absolute/path/to/node --bun /absolute/path/to/bun
```

It installs two hourly launchd agents, a locked Renovate dependency tree without
lifecycle scripts and a checksum-verified official RE2 binary. It proves a
controlled post-activation runtime failure restores the prior configuration.
Runtime release receipts live under `~/.local/state/security-maintenance/bot`.
Only the maintenance runtime has this automatic release qualification. Every
application's `automaticPatchReleaseQualified` remains false.

The update bot uses the existing local `gh`, WCS `GH_CONFIG_DIR` and `glab`
profiles in memory. Autodiscovery, lifecycle scripts, plugins, arbitrary commands
and internal network access are disabled. No token is saved in configuration or
transferred to the VPS. It audits itself before retrieving platform credentials.
The unfixed upstream braces advisory has a narrow, tested local depth-guard
backport recorded in `bot/backport.json`. Its raw advisory remains visible.
The patch hash, regression checks and review deadline must pass on every run;
an overdue review or another high/critical advisory blocks the bot.

## Bespoke downloads and candidates

`.security/node-downloads.json` registers the Azure and custom CI Node downloads.
`runtime-pins.py` validates each version and SHA-256 against the official Node
manifest in CI. The local trusted preparation job updates both together and
opens a reviewed PR/MR. Renovate excludes those files so it cannot update just
the version. No repository-provided post-update command runs with bot credentials.

`prepare-images.py` checks the explicitly registered VPS containers and CI image
aliases. It derives a candidate from the actual immutable base image, verifies
the selected official Node image and checks the resulting executable. It also
replaces legacy npm Undici copies below the registered incident floors using
registry integrity checks. Candidates use no application data or production
volumes, and do not change a running service. Receipt `baseImage` must still
match live production before any release. A new advisory without an implemented
safe transformation remains a finding for review.

Preserve existing patched-image overrides, Watchtower exclusions, persistent
runner externals reconciliation and disabled runner self-updates. Runner
application updates remain a Nomad CI-controller operation: inspect the
repository's offered runner version and enforcement deadline, wait for idle
capacity, stage all PATH/glibc/musl bundled executables and use the existing
controller. Never revive a retired Compose or systemd owner.

## Add a repository or service

1. Register its canonical repository, owner and package roots in `estate.json`.
   Add the existing local credential profile only if already authorised.
2. Run `python3 infrastructure/security/enrol.py /path/to/repo --owner owner/repo
   --platform github --package-root .` from this repository. Use `gitlab` for a
   GitLab repository. Existing security files/includes require a deliberate merge.
3. Add every independently locked root to `.security/policy.json`. A newly tracked
   npm/Bun dependency root fails CI until it is registered. Additional ecosystems,
   bundled executables and bespoke downloads require explicit adapters; do not
   claim coverage from an unrelated clean JavaScript scan.
4. Register runtime paths, stable container names/image identities, guests,
   public controls and report freshness requirements in `vps-policy.json`.
   Add provider checks where builds happen outside repository CI.
5. Link the normal tests, deployment owner, live version/health/access checks and
   retained recovery release. Keep automated application release disabled until
   an update, deployment, live verification and recovery drill have passed.

Major upgrades, schema changes, financial/reporting behaviour and material outage
risk retain human review. Database rollback requires a service-specific recovery
method. A previous container image alone cannot undo a migration.

## Validate changes

```
node --test .security/runtime-selfcheck.ts
python3 -m unittest discover -s infrastructure/security -p 'test_*.py'
node infrastructure/security/bot/verify-braces.mjs
SECURITY_BASE_SHA=<trusted-base-commit> node .security/ci.ts
```

Use the declared supported Node and Bun versions. Job logs and summaries retain
source reports even when GitHub artifact storage is unavailable. Keep retained
existing findings, scan failures and vendor limitations in the operational
register. Never remove a gate or suppress a report to make the rollout green.
