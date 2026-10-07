# ADR-0003: Grafana org membership, not roles, isolates Usual Suspects users

- Status: Accepted
- Date: 2026-10-07
- Authors: George Vlachos

## Context

The Usual Suspects client reaches its logs through a dedicated Grafana org ("Usual Suspects Logs") whose only datasource goes through the tenant-pinned proxy described in ADR-0002. Grafana's admin org (id 1) has a provisioned `Loki` datasource that reads every tenant. `scripts/configure-usual-suspects-grafana-access.mjs` used to create the Usual Suspects UI user in the admin org and then set its role there to `None`. Against Grafana 12.4.10 that role already blocked queries to the admin datasource, but isolation rested on a single role setting in an org that can read every tenant, and the script's own token check sent a query the proxy ignored, so it verified nothing.

## Decision

Org membership is the isolation boundary for Usual Suspects Grafana users. The configure script creates the UI user directly in the Usual Suspects org as a Viewer, removes it from every other org and clears the Grafana server admin flag on each run, which also cleans up existing deployments. The service account is kept at Viewer. Before it prints any credentials the script verifies isolation, and if any check fails it exits non-zero and deletes the token it just created:

- The Usual Suspects org contains only the proxy datasource, the admin, the UI user and Viewer service accounts, since any other datasource could bypass the proxy.
- The UI user is a Viewer in the Usual Suspects org, belongs to no other org and is not a server admin.
- The UI user gets 403 from the admin org's `Loki` datasource, which the admin can query.
- Asked through the Usual Suspects datasource for every script name, only Usual Suspects scripts come back. `--dashboard-only` runs this check and the org audit too.

## Consequences

A mistaken role change in the admin org can no longer expose every tenant to the client, and a broken proxy or datasource is caught when the script runs rather than by the client. Re-running the script is safe because org removal is idempotent. Anyone who wants the Usual Suspects user to see something in another org now has to change this script and its checks deliberately. The datasource check can only prove isolation when Loki holds logs from other scripts in the queried window, so it reports `conclusive: false` rather than a pass when there are none. Verification waits about six seconds for Grafana's datasource cache. The checks run only when the script runs, not continuously.

## Alternatives considered

- **Keep the user in the admin org with role `None`.** It worked on Grafana 12.4.10 but leaves isolation one role edit away from exposing every tenant, and Grafana's role and RBAC defaults can change between versions.
