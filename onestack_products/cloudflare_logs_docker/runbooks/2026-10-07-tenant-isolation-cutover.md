# Runbook: Usual Suspects tenant isolation cutover

Deploys the changes behind ADR-0002, ADR-0003 and ADR-0004 to the Cloudflare
logs stack on `onestack-admin` (`/root/cloudflare_logs_docker`):

- Loki runs with `auth_enabled: true`, and the Usual Suspects proxy is pinned to
  the `usual-suspects` tenant. This closes the LogQL bypass, which is live in
  production until this cutover.
- Ingest and backfill route each Worker to a tenant and redact secrets with the
  shared `ingest/redaction.js`.
- The Grafana configure script takes the Usual Suspects UI user out of the admin
  org, audits the Usual Suspects org and checks isolation before it prints
  credentials.

The release is commit `339afb8`. On 2026-10-07 the whole procedure was
rehearsed locally against the pinned images, from the old single-tenant state
through the upgrade, the configure script and the backfill, and it passed.
Expect a few minutes without log ingestion during the backup and the container
recreation; Logpush retries in the meantime.

## Before you start

Tell the Usual Suspects client two things:

- Their dashboards start empty at the cutover. Earlier logs stay in a tenant
  they cannot read (ADR-0002) until they are re-backfilled in step 7.
- Their UI password changes in step 6. Their existing service account token
  keeps working.

Skipping step 6 leaves the UI user in the admin org with role None. That is
safe today but is what ADR-0003 replaces.

## Rollback triggers

Roll back (see the end of this runbook) if any of the following happens:

- Within five minutes of step 4, `/usual-suspects-logs/health` does not return
  200 with `"tenancyEnforced":true`.
- Ten minutes after step 4, with Logpush running, the `usual-suspects` tenant
  has received no new logs (step 5).
- Any other stack service fails to start.

A failed step 6 is not a rollback trigger: fix the reported problem and run it
again.

## 0. Local pre-flight

Test the exact release in a throwaway worktree:

```bash
cd "$(git rev-parse --show-toplevel)"
git worktree add /tmp/cloudflare_logs_check 339afb8
(cd /tmp/cloudflare_logs_check/onestack_products/cloudflare_logs_docker && npm test && npm run test:integration)
git worktree remove /tmp/cloudflare_logs_check
```

Both suites must pass (the integration suite needs Docker). Then export the
release and the baseline that was imported as "currently deployed" (`1471aed`).
The block stops on any failure and refuses to continue with an empty export:

```bash
cd "$(git rev-parse --show-toplevel)" && set -o pipefail
rm -rf /tmp/cloudflare_logs_release /tmp/cloudflare_logs_baseline
mkdir -p /tmp/cloudflare_logs_release /tmp/cloudflare_logs_baseline
git archive 339afb8 onestack_products/cloudflare_logs_docker | tar -x -C /tmp/cloudflare_logs_release --strip-components=2 &&
git archive 1471aed onestack_products/cloudflare_logs_docker | tar -x -C /tmp/cloudflare_logs_baseline --strip-components=2 &&
test -f /tmp/cloudflare_logs_release/ingest/redaction.js &&
test -f /tmp/cloudflare_logs_baseline/docker-compose.yml &&
echo "export ok"
```

Do not continue unless it prints `export ok`.

## 1. Server pre-flight (read-only)

Connect to Tailscale first; `onestack-admin` is a Tailscale address.

Check that the server still runs what was imported. Any file listed here was
changed on the server after the import and must be reconciled before deploying:

```bash
rsync -rcn --exclude .env --exclude credentials.txt --out-format='%n' \
  /tmp/cloudflare_logs_baseline/ onestack-admin:/root/cloudflare_logs_docker/
```

Then check the running state, the volumes and free space. This prints `.env`
key names only, never values:

```bash
ssh onestack-admin 'bash -s' <<'EOF'
cd /root/cloudflare_logs_docker
echo "== .env keys"; cut -d= -f1 .env
echo "== containers"; docker compose ps
for c in cloudflare-logs-grafana cloudflare-logs-loki; do
  for v in $(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' $c); do
    echo "== $c volume $v: $(docker run --rm -v $v:/data:ro --user 0 --entrypoint du "$(docker inspect -f '{{.Image}}' cloudflare-logs-ingest)" -sh /data | cut -f1)"
  done
done
echo "== free space"; df -h /
EOF
```

The `.env` must define `LOGS_HOST`, `GRAFANA_ADMIN_USER`,
`GRAFANA_ADMIN_PASSWORD`, `INGEST_BEARER_TOKEN`, `ALLOWED_SCRIPT_NAMES` and
`USUAL_SUSPECTS_LOGS_API_TOKEN`; no new variables are needed. Free space on `/`
must be at least twice the two volumes combined (for the backup and the image
rebuild).

## 2. Back up

This backs up the stack directory, including `.env`, and both volumes. Grafana
and Loki are stopped for the copy so that Grafana's SQLite database and Loki's
WAL are consistent; ingest fails meanwhile and Logpush retries. Volumes are read
as root because the stack's images run as non-root users. Volume names are taken
from the running containers, so they are right whatever the compose project is
called:

```bash
ssh onestack-admin 'bash -s' <<'EOF'
set -e
cd /root/cloudflare_logs_docker
stamp=$(date +%Y%m%d-%H%M%S)
dir=/root/backups/cloudflare_logs/$stamp
mkdir -p "$dir"
img=$(docker inspect -f '{{.Image}}' cloudflare-logs-ingest)
grafana_volume=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' cloudflare-logs-grafana)
loki_volume=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' cloudflare-logs-loki)
test -n "$img"; test -n "$grafana_volume"; test -n "$loki_volume"
echo "$grafana_volume $loki_volume" > "$dir/volumes.txt"
tar czf "$dir/stack.tgz" -C /root cloudflare_logs_docker
trap 'docker start cloudflare-logs-loki cloudflare-logs-grafana' EXIT
docker stop cloudflare-logs-grafana cloudflare-logs-loki
for v in "$grafana_volume" "$loki_volume"; do
  docker run --rm --user 0 -v "$v":/data:ro -v "$dir":/backup "$img" tar czf "/backup/$v.tgz" -C /data .
done
ls -la "$dir"
EOF
```

Write down the backup directory it prints.

## 3. Copy the release

Do the dry run first and read the list of files. It should show only the
release's added and changed files. There is no `--delete`: the release only adds
and changes files, and any server-only file is left alone.

```bash
rsync -rlptvn --no-owner --no-group --exclude .env --exclude credentials.txt \
  /tmp/cloudflare_logs_release/ onestack-admin:/root/cloudflare_logs_docker/
```

Only then copy:

```bash
rsync -rlptv --no-owner --no-group --exclude .env --exclude credentials.txt \
  /tmp/cloudflare_logs_release/ onestack-admin:/root/cloudflare_logs_docker/
```

## 4. Deploy

```bash
ssh onestack-admin 'cd /root/cloudflare_logs_docker && docker compose config -q && docker compose up -d --build --force-recreate && docker compose ps'
```

`--force-recreate` is required. Without it, Loki and Grafana keep their old
config, and the proxy answers 503 by design.

## 5. Verify

The tokens are read from `.env` on the server, so they stay out of your local
shell history.

```bash
ssh onestack-admin 'bash -s' <<'EOF'
cd /root/cloudflare_logs_docker && set -a && . ./.env && set +a
echo "== proxy health (expect \"tenancyEnforced\":true and 200)"
curl -sS -w ' %{http_code}\n' -H "Authorization: Bearer $USUAL_SUSPECTS_LOGS_API_TOKEN" \
  "https://$LOGS_HOST/usual-suspects-logs/health"
echo "== tenantless Loki read (expect 401 no org id)"
docker exec cloudflare-logs-ingest node -e 'fetch("http://loki:3100/loki/api/v1/labels").then(async (r) => console.log(r.status, (await r.text()).trim()))'
EOF
```

Once Logpush has delivered a batch (usually within a few minutes, and Cloudflare
shows the job's last successful push), check that new logs reach the
`usual-suspects` tenant (expect a non-zero count):

```bash
ssh onestack-admin 'bash -s' <<'EOF'
docker exec cloudflare-logs-ingest node -e '
const q = "sum(count_over_time({scriptName=~\".+\"}[10m]))";
fetch("http://loki:3100/loki/api/v1/query?query=" + encodeURIComponent(q), { headers: { "X-Scope-OrgID": "usual-suspects" } })
  .then(async (r) => console.log(r.status, JSON.stringify((await r.json()).data.result)))'
EOF
```

Then check the proxy's isolation. This query asks for every script name and
must return 200 with only Usual Suspects names. Before the cutover, a variant of
it also returned other scripts:

```bash
ssh onestack-admin 'bash -s' <<'EOF'
cd /root/cloudflare_logs_docker && set -a && . ./.env && set +a
curl -sS -G -w '\n%{http_code}\n' -H "Authorization: Bearer $USUAL_SUSPECTS_LOGS_API_TOKEN" \
  --data-urlencode 'query=sum by (scriptName) (count_over_time({__USUAL_SUSPECTS_LABELS__}[1h])) or sum by (scriptName) (count_over_time({scriptName=~".+"}[1h]))' \
  "https://$LOGS_HOST/usual-suspects-logs/loki/api/v1/query" | grep -o -E '"scriptName":"[^"]*"|^[0-9]{3}$' | sort -u
EOF
```

The output must include `200` and at least one of
`"scriptName":"usual-suspects"` or `"scriptName":"usual-suspects-production"`;
nothing else may appear. Finally, in Grafana:

- In the Usual Suspects org, the dashboard shows new invocations.
- In the admin org, the "Cloudflare Worker Logs" dashboard still shows logs from
  before the cutover (now in the `fake` tenant) as well as new ones.

## 6. Reconfigure Grafana access

This rotates the UI password. The output contains new credentials, so it is
written to a file only you can read:

```bash
(umask 077; ssh onestack-admin 'bash -s' > ~/usual-suspects-grafana-access.json <<'EOF'
cd /root/cloudflare_logs_docker && set -a && . ./.env && set +a
docker run --rm --network container:cloudflare-logs-grafana \
  -v /root/cloudflare_logs_docker/scripts:/scripts:ro \
  -e GRAFANA_URL=http://localhost:3000 \
  -e GRAFANA_ADMIN_USER -e GRAFANA_ADMIN_PASSWORD -e USUAL_SUSPECTS_LOGS_API_TOKEN \
  "$(docker inspect -f '{{.Image}}' cloudflare-logs-ingest)" \
  node /scripts/configure-usual-suspects-grafana-access.mjs
EOF
echo "exit $?")
```

It must exit 0, and the `verification` blocks must show:

- `ui.verification`: `queryStatus` 200 and `adminDatasourceStatus` 403.
- `serviceAccount.verification`: `scriptLabels` contains only Usual Suspects
  scripts. `conclusive: false` is expected while ingest accepts only Usual
  Suspects scripts, because there are no other scripts' logs to compare against.

If it exits non-zero, nothing was printed and no new token is left; read the
error on stderr and fix the org. The UI password has still been rotated, so the
client stays locked out until a run succeeds.

## 7. Afterwards

- Send the client the new UI password through the usual secure channel, then
  delete `~/usual-suspects-grafana-access.json`.
- Re-backfill straight away, before Cloudflare's retention runs out, using the
  README command (it now mounts `ingest/` and `scripts/` only). That restores
  the client's recent history in the `usual-suspects` tenant.
- From 14 days after the cutover, retention has emptied the `fake` tenant, and
  it can be dropped from `grafana/provisioning/datasources/loki.yml` in a later
  change.

## Rollback

Set `dir` to the backup directory from step 2, then restore the previous stack
files and, if needed, the Grafana volume:

```bash
ssh onestack-admin 'bash -s' <<'EOF'
set -e
dir=/root/backups/cloudflare_logs/REPLACE_WITH_STAMP
read -r grafana_volume loki_volume < "$dir/volumes.txt"
# Check everything before stopping or deleting anything.
test -n "$grafana_volume"
gzip -t "$dir/stack.tgz"
[ "${RESTORE_GRAFANA:-no}" != yes ] || gzip -t "$dir/$grafana_volume.tgz"
img=$(docker inspect -f '{{.Image}}' cloudflare-logs-ingest)
test -n "$img"
cd /root
docker compose -f cloudflare_logs_docker/docker-compose.yml stop
mv cloudflare_logs_docker "cloudflare_logs_docker.failed.$(date +%Y%m%d-%H%M%S)"
tar xzf "$dir/stack.tgz"
# Restore the Grafana database only if step 6 ran and must be undone (this
# also undoes the password rotation).
if [ "${RESTORE_GRAFANA:-no}" = yes ]; then
  docker run --rm --user 0 -v "$grafana_volume":/data -v "$dir":/backup "$img" \
    sh -c "find /data -mindepth 1 -delete && tar xzf /backup/$grafana_volume.tgz -C /data"
fi
cd cloudflare_logs_docker && docker compose up -d --build --force-recreate && docker compose ps
EOF
```

To restore Grafana too, put `export RESTORE_GRAFANA=yes` as the first line
inside the heredoc.

Logs ingested after the cutover stay on disk in their tenants, but the old
single-tenant Loki cannot see them; they reappear if the cutover is redone. Do
not restore the Loki volume unless the cutover itself corrupted it, because that
discards everything ingested since the backup. Rollback reopens the LogQL bypass.
