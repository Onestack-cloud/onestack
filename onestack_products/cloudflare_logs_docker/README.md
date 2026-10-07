# Cloudflare Worker logs

Self-hosted Cloudflare Workers log viewer for `usual-suspects`.

## Architecture

Cloudflare Workers Logpush sends `workers_trace_events` to:

```text
https://logs.onestack.cloud/cloudflare-logpush
```

Traefik routes that path to the ingest adapter. The adapter validates the
`Authorization: Bearer ...` header, filters allowed Worker script names, redacts
secrets and writes to Loki. Grafana is exposed on the same host.

Redaction lives in `ingest/redaction.js`, which the backfill script shares. It
replaces the values of sensitive keys (authorisation, cookies, passwords,
secrets, tokens, API keys, JWTs, sessions, private keys, credentials and
signatures) anywhere in a record, including inside `console.log` arguments,
header lists and strings that are entirely JSON. Flags and counters with such
names (`passwordResetSent`, `tokenCount`) stay visible; other numbers, such as a
numeric OTP or PIN, do not. In any `scheme://` URL inside a string it redacts
userinfo and sensitive query or fragment parameters (the same names plus OAuth
and one-time `code`s and API `key`s), leaving the rest of the URL as logged. In
free text it redacts `Bearer` and `Basic` credentials and `name=value` or
`name: value` pairs with a sensitive name. Secrets in URL paths (such as webhook
URLs), in JSON with a prefix or in prose without a name are stored as logged, so
Workers must not log them. Malformed payloads are rejected without quoting them
back.

The backfill command mounts only `ingest/` and `scripts/`, so the stack's
`.env` stays out of the container.

## Tenant isolation

Loki runs with `auth_enabled: true`, so every read and write names a tenant in
the `X-Scope-OrgID` header:

- The ingest adapter and the backfill script route each Worker by exact script
  name using `LOKI_TENANT_BY_SCRIPT` (`script=tenant,...`). `usual-suspects` and
  `usual-suspects-production` go to the `usual-suspects` tenant. Every other
  script goes to `LOKI_DEFAULT_TENANT` (`cloudflare-workers`), which may not be
  a routed tenant, so an unknown or look-alike script never lands in
  `usual-suspects`.
- The `usual-suspects-api` proxy always sends `X-Scope-OrgID: usual-suspects`
  (`LOKI_TENANT`) and never forwards the caller's headers. The tenant is the
  security boundary, not the LogQL text: any query sent through the proxy can
  only read the `usual-suspects` tenant.
- The admin Grafana datasource reads every tenant with
  `usual-suspects|cloudflare-workers|fake` (`multi_tenant_queries_enabled`).

### Cutover from the single-tenant setup

Logs written before tenancy was enabled stay in Loki's `fake` tenant. Admins
still see them through the multi-tenant datasource until retention (14 days)
removes them. The Usual Suspects proxy does not read `fake`, so its history
starts at the cutover unless you re-run the backfill below for the window
Cloudflare still retains.

Deploy Loki, ingest, the proxy and Grafana together. An ingest push without a
tenant is rejected once Loki has `auth_enabled: true`, and Logpush retries it.
Loki and Grafana only read their config at startup, so recreate them (see
Deploy). The proxy checks that Loki rejects a read without a tenant before
every query and answers 503 until it does, so a Loki still running the old
config fails closed rather than exposing every tenant.

## Tests

```bash
npm test                    # unit tests, no dependencies
npm run test:integration    # also runs the bypass queries against the pinned Loki image (needs Docker)
```

## Deploy

Create `.env` from `.env.example`, then run:

```bash
docker compose config
docker compose up -d --build --force-recreate
```

`--force-recreate` matters: without it Compose keeps a container whose only
change is a bind-mounted config file, so Loki and Grafana would not pick up
`loki/config.yml` or the datasource provisioning. Recreating everything in one
step also stops the new ingest from writing into the old single-tenant Loki. Then check that
`/usual-suspects-logs/health` reports `"tenancyEnforced": true`.

## Cloudflare Logpush destination

Use an HTTP destination with the bearer token as a request header:

```text
https://logs.onestack.cloud/cloudflare-logpush?header_Authorization=Bearer%20<token>
```

Use the `workers_trace_events` dataset and filter `ScriptName` to the allowed
Worker script names.

## Usual Suspects Grafana access

`scripts/configure-usual-suspects-grafana-access.mjs` creates the "Usual
Suspects Logs" org, its datasource (pointing at the proxy), dashboard, UI user
and service account. The UI user belongs only to that org as a Viewer: it is
removed from every other org, including Grafana's admin org whose `Loki`
datasource reads every tenant, and is never a Grafana server admin. The service
account is kept at Viewer.

Before printing credentials the script checks that the UI user has no other
org and gets 403 from the admin datasource (which the admin can query), and
that the service account token only sees Usual Suspects script names even for
a query that asks for all of them. If any check fails it exits non-zero, prints
no credentials and deletes the token it just created. `--dashboard-only` runs
the datasource check too. `verification.conclusive` is `false` when no other
script has logs in the last 24 hours, because the check cannot then prove
isolation.

Run it by path from a container on the stack's networks, for example:

```bash
docker run --rm --network container:cloudflare-logs-grafana \
  -v /root/cloudflare_logs_docker/scripts:/scripts:ro \
  -e GRAFANA_URL=http://localhost:3000 \
  -e GRAFANA_ADMIN_USER -e GRAFANA_ADMIN_PASSWORD -e USUAL_SUSPECTS_LOGS_API_TOKEN \
  cloudflare_logs_docker-ingest \
  node /scripts/configure-usual-suspects-grafana-access.mjs
```

## Manual backfill

Historical Workers Logs can be backfilled from Cloudflare Workers Observability
while Cloudflare still retains them. Run the helper on the VPS from a container
that shares the ingest service network:

```bash
docker run --rm --network container:cloudflare-logs-ingest \
  -v /root/cloudflare_logs_docker/ingest:/stack/ingest:ro \
  -v /root/cloudflare_logs_docker/scripts:/stack/scripts:ro \
  -e CF_API_EMAIL -e CF_API_KEY -e CF_ACCOUNT_ID \
  cloudflare_logs_docker-ingest \
  node /stack/scripts/backfill-workers-observability.mjs \
    --source-label cloudflare-workers-backfill-full \
    --from "2026-06-02T00:00:00.000Z" \
    --to "2026-06-09T04:18:00.000Z" \
    --limit 2000
```

The backfill routes entries to Loki tenants with the same
`LOKI_TENANT_BY_SCRIPT` and `LOKI_DEFAULT_TENANT` rules as the ingest adapter.
Its defaults match `docker-compose.yml`, so pass them with `-e` only if you
change the routes there.

Use short windows, such as one hour, to avoid Cloudflare adaptive sampling. The
Grafana dashboard includes `cloudflare-workers` and
`cloudflare-workers-backfill-full` by default.
