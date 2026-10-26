# Shared VPS GitLab queue

George authorised sharing VPS GitLab capacity on 26 October 2026. Runner
`57332354` now serves Usual Suspects and Stocktake as
`vps-shared-gitlab-general`. Its existing compatibility tags remain and
`vps-shared` is available for other trusted projects. It accepts untagged jobs.
Additional trusted projects can be explicitly assigned to this registration.

The existing Nomad `gitlab-runners` job remains the sole manager owner in the
`ci-vps` namespace on `onestack-ci-runner`. Its process and configuration path
`/etc/gitlab-runner-usual-suspects/config.toml` remain in place. There are four
global job/request slots. Excess eligible jobs wait in GitLab's queue. Preserve
the existing 7 GiB/3.5 CPU per-job ceiling, aggregate 15 GiB/12 CPU slice and zero
swap. Do not revive masked systemd or Compose owners.

The shared executor remains unprivileged with no host Docker socket or services.
Its existing image allowlist now also admits Stocktake's `node:24` image.
The pull policy stays `never`: the operator preloads and verifies an official
image before admitting it. The initial alias points to official Node 24.22.1,
digest `sha256:6449e19d8184d84062525b6a7524def03146c2cb04a7f08b076680d0e8e4240a`.
Refresh this alias through the normal reviewed CI runtime owner when the Node
security floor changes. Register it in the CI guest security policy's
`extraImages`; retain the 32-hour inventory freshness requirement.

Stocktake has GitLab-hosted instance runners disabled, so it no longer depends
on their compute quota. Its source, application deployment and secrets are
unchanged. Allbids retains its separate protected deployment executor and host
Docker access. Do not grant that access to general shared CI jobs.

Native rollback configuration is retained under
`/root/gitlab-shared-queue-2026-10-26/` on the CI guest. To recover, pause new
claims, let running jobs finish, restore the exact saved configuration and
project/runner assignment settings, then verify the existing Nomad owner and
security policy. Never print runner tokens or copy their private configuration
off the guest. Source changes and a healthy queue do not establish application
deployment or client acceptance.

Masked qualification evidence is in the WCS operator workspace's
`outputs/dependency-release-2026-10-26/` directory, including original failures.
