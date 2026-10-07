"use strict";

// Runs the bypass queries through the real proxy and ingest services against
// the pinned Loki image with this stack's loki/config.yml. Opt in with
// LOKI_INTEGRATION=1 (needs Docker); it is skipped otherwise.

const { test, describe, before, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { randomUUID } = require("node:crypto");
const { stackRoot, startService, bypassQueries } = require("./helpers");

const enabled = process.env.LOKI_INTEGRATION === "1";
const apiToken = "integration-api-token";
const ingestToken = "integration-ingest-token";
const run = randomUUID().slice(0, 8);
const markers = {
  visible: `US_VISIBLE_${run}`,
  foreign: `FOREIGN_${run}`,
  impostor: `IMPOSTOR_${run}`,
  legacy: `LEGACY_${run}`,
};

function lokiImage() {
  const compose = fs.readFileSync(path.join(stackRoot, "docker-compose.yml"), "utf8");
  return compose.match(/image:\s*(grafana\/loki@sha256:[0-9a-f]+)/)[1];
}

async function waitForReady(url) {
  const deadline = Date.now() + 120000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${url}/ready`);
      if (response.ok) {
        return;
      }
    } catch {
      // Loki is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error("Loki did not become ready");
}

async function pushDirect(lokiUrl, tenant, labels, line) {
  const response = await fetch(`${lokiUrl}/loki/api/v1/push`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-scope-orgid": tenant },
    body: JSON.stringify({ streams: [{ stream: labels, values: [[String(BigInt(Date.now()) * 1000000n), line]] }] }),
  });
  assert.ok(response.ok, `push to ${tenant} failed: ${response.status} ${await response.text()}`);
}

describe("Loki tenant isolation (integration)", { skip: !enabled && "set LOKI_INTEGRATION=1 to run" }, () => {
  let containerId;
  let lokiUrl;
  let ingest;
  let api;

  before(async () => {
    containerId = execFileSync("docker", [
      "run", "-d", "--rm", "-p", "127.0.0.1::3100",
      "-v", `${path.join(stackRoot, "loki/config.yml")}:/etc/loki/config.yml:ro`,
      lokiImage(), "-config.file=/etc/loki/config.yml",
    ]).toString().trim();
    const hostPort = execFileSync("docker", ["port", containerId, "3100/tcp"]).toString().trim().split(":").pop();
    lokiUrl = `http://127.0.0.1:${hostPort}`;
    await waitForReady(lokiUrl);

    ingest = await startService("ingest/server.js", {
      AUTH_TOKEN: ingestToken,
      LOKI_URL: `${lokiUrl}/loki/api/v1/push`,
      ALLOWED_SCRIPT_NAMES: "",
      LOKI_TENANT_BY_SCRIPT: "usual-suspects=usual-suspects,usual-suspects-production=usual-suspects",
      LOKI_DEFAULT_TENANT: "cloudflare-workers",
    });
    api = await startService("usual-suspects-api/server.js", { API_TOKEN: apiToken, LOKI_URL: lokiUrl });

    const records = [
      { scriptName: "usual-suspects", message: markers.visible },
      { scriptName: "other-worker", message: markers.foreign },
    ].map(({ scriptName, message }) =>
      JSON.stringify({
        ScriptName: scriptName,
        Outcome: "ok",
        EventType: "fetch",
        EventTimestampMs: Date.now(),
        Logs: [{ level: "log", message: [message], timestamp: Date.now() }],
      }),
    );
    const pushed = await fetch(`${ingest.url}/cloudflare-logpush`, {
      method: "POST",
      headers: { authorization: `Bearer ${ingestToken}` },
      body: records.join("\n"),
    });
    assert.equal(pushed.status, 202, await pushed.text());

    // Another tenant's stream that copies the Usual Suspects labels exactly.
    await pushDirect(
      lokiUrl,
      "cloudflare-workers",
      { source: "cloudflare-workers", scriptName: "usual-suspects", kind: "console" },
      markers.impostor,
    );
    // Data written before tenancy was enabled lands in Loki's "fake" tenant.
    await pushDirect(lokiUrl, "fake", { source: "cloudflare-workers", scriptName: "legacy-worker" }, markers.legacy);
  });

  after(async () => {
    await api?.stop();
    await ingest?.stop();
    if (containerId) {
      execFileSync("docker", ["rm", "-f", containerId], { stdio: "ignore" });
    }
  });

  const foreignIndicators = [markers.foreign, markers.impostor, markers.legacy, "other-worker", "legacy-worker"];
  const baseLabels =
    'source=~"cloudflare-workers|cloudflare-workers-backfill-full",scriptName=~"usual-suspects|usual-suspects-production"';

  function timeParams(endpoint) {
    const nowNs = BigInt(Date.now()) * 1000000n;
    return endpoint === "query"
      ? { time: String(nowNs) }
      : { start: String(nowNs - 3600n * 1000000000n), end: String(nowNs), limit: "1000" };
  }

  async function viaProxy(endpoint, query) {
    const params = new URLSearchParams({ query, ...timeParams(endpoint) });
    const response = await fetch(`${api.url}/usual-suspects-logs/loki/api/v1/${endpoint}?${params}`, {
      headers: { authorization: `Bearer ${apiToken}` },
    });
    return { status: response.status, body: await response.text() };
  }

  // The same query sent straight to Loki across every tenant, to prove it
  // would have read foreign data without tenant isolation.
  async function asAdmin(endpoint, query) {
    const params = new URLSearchParams({ query: query.replaceAll("__USUAL_SUSPECTS_LABELS__", baseLabels), ...timeParams(endpoint) });
    const response = await fetch(`${lokiUrl}/loki/api/v1/${endpoint}?${params}`, {
      headers: { "x-scope-orgid": "usual-suspects|cloudflare-workers|fake" },
    });
    return { status: response.status, body: await response.text() };
  }

  function assertNoForeignData(body) {
    for (const marker of foreignIndicators) {
      assert.ok(!body.includes(marker), `response leaked ${marker}: ${body.slice(0, 500)}`);
    }
  }

  test("the base Usual Suspects query still returns Usual Suspects logs", async () => {
    const { status, body } = await viaProxy("query_range", "{__USUAL_SUSPECTS_LABELS__}");
    assert.equal(status, 200, body);
    assert.ok(body.includes(markers.visible), body.slice(0, 500));
    assertNoForeignData(body);
  });

  test("a match-everything metric query only counts the Usual Suspects tenant", async () => {
    const { status, body } = await viaProxy(
      "query",
      'sum by (scriptName) (count_over_time({__USUAL_SUSPECTS_LABELS__}[1h])) or sum by (scriptName) (count_over_time({scriptName=~".+"}[1h]))',
    );
    assert.equal(status, 200, body);
    assert.match(body, /"scriptName":"usual-suspects"/);
    assertNoForeignData(body);
  });

  test("Loki rejects a read without a tenant", async () => {
    const response = await fetch(`${lokiUrl}/loki/api/v1/labels`);
    assert.equal(response.status, 401);
    // The proxy's probe relies on this exact error.
    assert.match(await response.text(), /no org id/);
  });

  for (const [name, { type, parses, query }] of Object.entries(bypassQueries)) {
    for (const endpoint of type === "metric" ? ["query_range", "query"] : ["query_range"]) {
      test(`${endpoint}: ${name} cannot read other tenants`, async () => {
        const admin = await asAdmin(endpoint, query);
        const proxied = await viaProxy(endpoint, query);
        if (parses) {
          assert.equal(admin.status, 200, admin.body);
          assert.ok(
            foreignIndicators.some((marker) => admin.body.includes(marker)),
            `query does not reach foreign data even across tenants, so it proves nothing: ${admin.body.slice(0, 300)}`,
          );
          assert.equal(proxied.status, 200, proxied.body);
        } else {
          assert.equal(admin.status, 400, admin.body);
          assert.equal(proxied.status, 400, proxied.body);
        }
        assertNoForeignData(proxied.body);
      });
    }
  }

  test("a late Logpush entry Loki refuses does not make the batch fail", async () => {
    const send = (timestamp) =>
      fetch(`${ingest.url}/cloudflare-logpush`, {
        method: "POST",
        headers: { authorization: `Bearer ${ingestToken}` },
        body: JSON.stringify({ ScriptName: "usual-suspects", Outcome: "canceled", EventType: "fetch", EventTimestampMs: timestamp }),
      });
    assert.equal((await send(Date.now())).status, 202);
    // Four hours behind the stream's newest entry: Loki 3.7 rejects it as
    // "entry too far behind" and a retry can never succeed.
    const late = await send(Date.now() - 4 * 60 * 60 * 1000);
    assert.equal(late.status, 202, await late.text());
  });

  test("the admin multi-tenant header still sees every tenant", async () => {
    const params = new URLSearchParams({ query: '{source=~".+"}', limit: "1000" });
    const response = await fetch(`${lokiUrl}/loki/api/v1/query_range?${params}`, {
      headers: { "x-scope-orgid": "usual-suspects|cloudflare-workers|fake" },
    });
    const body = await response.text();
    assert.equal(response.status, 200, body);
    for (const marker of Object.values(markers)) {
      assert.ok(body.includes(marker), `admin query missing ${marker}`);
    }
  });
});
