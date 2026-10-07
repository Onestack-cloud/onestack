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

The whole procedure, including the old single-tenant state, the upgrade, the
configure script and the backfill, was rehearsed locally against the pinned
images on 2026-10-07 and passed. Expect about two minutes without log ingestion
while the containers are recreated; Logpush retries in the meantime.

## Decide before you start

Running the configure script (step 6) rotates the Usual Suspects UI password and
mints a new service account token. Plan when to send the client the new UI
password. Their existing service account token keeps working, so the new one
only needs to be sent if you want to rotate it. Skipping step 6 leaves the UI
user in the admin org with role None (safe today, but see ADR-0003).

## 0. Local pre-flight

From a clean checkout of `main` that includes merge `339afb8` or later:

```bash
cd onestack_products/cloudflare_logs_docker
npm test
npm run test:integration
```

Both must pass (the integration suite needs Docker). Then export exactly what
is committed, so unrelated local changes cannot ride along:

```bash
mkdir -p /tmp/cloudflare_logs_release /tmp/cloudflare_logs_baseline
git archive main onestack_products/cloudflare_logs_docker | tar -x -C /tmp/cloudflare_logs_release --strip-components=2
git archive 1471aed onestack_products/cloudflare_logs_docker | tar -x -C /tmp/cloudflare_logs_baseline --strip-components=2
```

Use fresh, empty directories (delete any from an earlier attempt first).

`1471aed` is the copy that was imported into git as "currently deployed".

## 1. Server pre-flight (read-only)

Connect to Tailscale first; `onestack-admin` is a Tailscale address.

Check that the server still runs what was imported. Any file listed here was
changed on the server after the import and must be reconciled before deploying:

```bash
rsync -rcn --delete --exclude .env --exclude credentials.txt --out-format='%n' \
  /tmp/cloudflare_logs_baseline/ onestack-admin:/root/cloudflare_logs_docker/
```

Then check the running state, the volume names and free space (this prints
`.env` key names only, never values):

```bash
ssh onestack-admin 'cd /root/cloudflare_logs_docker && cut -d= -f1 .env && docker compose ps && docker volume ls | grep -E "loki|grafana" && df -h /'
```

The `.env` must define `LOGS_HOST`, `GRAFANA_ADMIN_USER`,
`GRAFANA_ADMIN_PASSWORD`, `INGEST_BEARER_TOKEN`, `ALLOWED_SCRIPT_NAMES` and
`USUAL_SUSPECTS_LOGS_API_TOKEN`; no new variables are needed. Note the two volume
names (normally `cloudflare_logs_docker_grafana_data` and
`cloudflare_logs_docker_loki_data`).

## 2. Back up

Back up the stack directory, including `.env`, and both volumes. The volumes
must be read as root (`--user 0`), because the stack's images run as non-root
users. The ingest image is already on the server and has `tar`:

```bash
ssh onestack-admin 'bash -s' <<'EOF'
set -e
stamp=$(date +%Y%m%d-%H%M%S)
mkdir -p /root/backups/cloudflare_logs/$stamp
tar czf /root/backups/cloudflare_logs/$stamp/stack.tgz -C /root cloudflare_logs_docker
for v in grafana_data loki_data; do
  docker run --rm --user 0 -v cloudflare_logs_docker_$v:/data:ro \
    -v /root/backups/cloudflare_logs/$stamp:/backup \
    cloudflare_logs_docker-ingest tar czf /backup/$v.tgz -C /data .
done
ls -la /root/backups/cloudflare_logs/$stamp
EOF
```

Use the volume names from step 1 if they differ. Note the backup directory for
rollback.

## 3. Copy the release

The excludes protect the server's secrets. Run with `-n` first and read the
list of deletions:

```bash
rsync -avn --delete --exclude .env --exclude credentials.txt \
  /tmp/cloudflare_logs_release/ onestack-admin:/root/cloudflare_logs_docker/
rsync -av --delete --exclude .env --exclude credentials.txt \
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
shell history:

```bash
ssh onestack-admin 'bash -s' <<'EOF'
cd /root/cloudflare_logs_docker && set -a && . ./.env && set +a
echo "proxy health (expect 200 and \"tenancyEnforced\":true):"
curl -sS -w ' %{http_code}\n' -H "Authorization: Bearer $USUAL_SUSPECTS_LOGS_API_TOKEN" \
  "https://$LOGS_HOST/usual-suspects-logs/health"
echo "tenantless Loki read (expect 401 no org id):"
docker exec cloudflare-logs-ingest node -e 'fetch("http://loki:3100/loki/api/v1/labels").then(async (r) => console.log(r.status, (await r.text()).trim()))'
echo "ingest errors in the last 10 minutes (expect none):"
docker compose logs --since 10m ingest | grep -i -E 'error|fail' || echo none
EOF
```

Then, after the next Logpush batch has arrived (usually within a minute or two):

- In the Usual Suspects Grafana org, the dashboard shows new invocations. Logs
  from before the cutover do not appear there. That is expected (ADR-0002), so
  re-backfill if needed (see the README).
- In the admin org, the "Cloudflare Worker Logs" dashboard still shows logs from
  before the cutover (they now sit in the `fake` tenant) as well as new ones.
- Optional bypass check: a query through the proxy for every script name
  returns only Usual Suspects scripts:

```bash
ssh onestack-admin 'bash -s' <<'EOF'
cd /root/cloudflare_logs_docker && set -a && . ./.env && set +a
curl -sS -G -H "Authorization: Bearer $USUAL_SUSPECTS_LOGS_API_TOKEN" \
  --data-urlencode 'query=sum(count_over_time({__USUAL_SUSPECTS_LABELS__} |= `"` [1h])) or sum by (scriptName) (count_over_time({scriptName=~".+"} != `"` [1h]))' \
  "https://$LOGS_HOST/usual-suspects-logs/loki/api/v1/query" | grep -o '"scriptName":"[^"]*"' | sort -u
EOF
```

Only Usual Suspects script names may appear. Before the cutover, this same query
also returned other scripts.

## 6. Reconfigure Grafana access

This rotates the UI password (see "Decide before you start"). It prints new
credentials, so capture the output somewhere safe rather than in a shared
terminal log:

```bash
ssh onestack-admin 'bash -s' > ~/usual-suspects-grafana-access.json <<'EOF'
cd /root/cloudflare_logs_docker && set -a && . ./.env && set +a
docker run --rm --network container:cloudflare-logs-grafana \
  -v /root/cloudflare_logs_docker/scripts:/scripts:ro \
  -e GRAFANA_URL=http://localhost:3000 \
  -e GRAFANA_ADMIN_USER -e GRAFANA_ADMIN_PASSWORD -e USUAL_SUSPECTS_LOGS_API_TOKEN \
  cloudflare_logs_docker-ingest \
  node /scripts/configure-usual-suspects-grafana-access.mjs
EOF
echo "exit $?"; chmod 600 ~/usual-suspects-grafana-access.json
```

It must exit 0. The `verification` blocks should show the following:

- `ui.verification`: `queryStatus` 200 and `adminDatasourceStatus` 403.
- `serviceAccount.verification`: `scriptLabels` contains only Usual Suspects
  scripts. `conclusive: false` is expected while ingest accepts only Usual
  Suspects scripts, because no other script's logs exist to compare against.

If it exits non-zero, nothing was printed and no new token is left. Read the
error and fix the org. The UI password has still been rotated, so the client
stays locked out until a successful run.

## 7. Afterwards

- Send the client the new UI password through the usual secure channel.
- Optionally re-backfill the window Cloudflare still retains, with the README
  command (it now mounts `ingest/` and `scripts/` only).
- From 14 days after the cutover, retention has emptied the `fake` tenant, and
  it can be dropped from `grafana/provisioning/datasources/loki.yml` in a later
  change.

## Rollback

1. Restore the previous files:

   ```bash
   ssh onestack-admin 'cd /root && tar xzf /root/backups/cloudflare_logs/<stamp>/stack.tgz'
   ```

   This restores `cloudflare_logs_docker/` exactly as backed up, `.env`
   included.
2. Recreate the stack:

   ```bash
   ssh onestack-admin 'cd /root/cloudflare_logs_docker && docker compose up -d --build --force-recreate'
   ```

Logs ingested after the cutover stay on disk in their tenants, but the old
single-tenant Loki cannot see them; they reappear if the cutover is redone.
Rollback reopens the LogQL bypass. Only restore the Grafana volume backup if the
configure script left Grafana in a state you need to undo; that also undoes the
password rotation.
