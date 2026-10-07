"use strict";

const { test, describe, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { startFakeLoki, startService, runToExit, bypassQueries } = require("./helpers");

const apiToken = "test-token";
const script = "usual-suspects-api/server.js";

describe("usual-suspects-api tenant isolation", () => {
  let loki;
  let api;

  before(async () => {
    loki = await startFakeLoki();
    api = await startService(script, { API_TOKEN: apiToken, LOKI_URL: loki.url });
  });

  after(async () => {
    await api.stop();
    await loki.close();
  });

  async function get(path, headers = {}) {
    const before = loki.requests.length;
    const response = await fetch(`${api.url}${path}`, {
      headers: { authorization: `Bearer ${apiToken}`, ...headers },
    });
    await response.text();
    return { response, lokiRequests: loki.requests.slice(before) };
  }

  for (const [name, query] of Object.entries(bypassQueries)) {
    for (const endpoint of ["query_range", "query"]) {
      test(`${endpoint}: ${name} is scoped to the usual-suspects tenant`, async () => {
        const { lokiRequests } = await get(
          `/usual-suspects-logs/loki/api/v1/${endpoint}?query=${encodeURIComponent(query)}`,
        );
        // Isolation must come from the tenant header, not from parsing the
        // query text, so every query is forwarded and Loki decides.
        assert.equal(lokiRequests.length, 1);
        assert.equal(lokiRequests[0].headers["x-scope-orgid"], "usual-suspects");
      });
    }
  }

  test("a caller-supplied X-Scope-OrgID never reaches Loki", async () => {
    const { response, lokiRequests } = await get("/usual-suspects-logs/loki/api/v1/query_range", {
      "x-scope-orgid": "cloudflare-workers|usual-suspects|fake",
    });
    assert.equal(response.status, 200);
    assert.equal(lokiRequests.length, 1);
    assert.equal(lokiRequests[0].headers["x-scope-orgid"], "usual-suspects");
  });

  test("the simple label API still builds the base selector", async () => {
    const { response, lokiRequests } = await get("/usual-suspects-logs/api/v1/query_range?kind=exception&status=500");
    assert.equal(response.status, 200);
    assert.equal(
      lokiRequests[0].url.searchParams.get("query"),
      '{source=~"cloudflare-workers|cloudflare-workers-backfill-full",scriptName=~"usual-suspects|usual-suspects-production",kind="exception",responseStatus="500"}',
    );
    assert.equal(lokiRequests[0].headers["x-scope-orgid"], "usual-suspects");
  });

  test("dashboard placeholders are still materialised", async () => {
    const query = 'sum(count_over_time({__USUAL_SUSPECTS_LABELS__,kind=~".+"} |~ "x" [5m]))';
    const { response, lokiRequests } = await get(
      `/usual-suspects-logs/loki/api/v1/query?query=${encodeURIComponent(query)}`,
    );
    assert.equal(response.status, 200);
    assert.equal(
      lokiRequests[0].url.searchParams.get("query"),
      'sum(count_over_time({source=~"cloudflare-workers|cloudflare-workers-backfill-full",scriptName=~"usual-suspects|usual-suspects-production",kind=~".+"} |~ "x" [5m]))',
    );
  });

  test("requests without the bearer token never reach Loki", async () => {
    const before = loki.requests.length;
    const response = await fetch(`${api.url}/usual-suspects-logs/loki/api/v1/query_range`);
    assert.equal(response.status, 401);
    assert.equal(loki.requests.length, before);
  });
});

describe("usual-suspects-api tenant configuration", () => {
  test("refuses to start with a multi-tenant LOKI_TENANT", async () => {
    const result = await runToExit(script, { API_TOKEN: apiToken, LOKI_TENANT: "usual-suspects|cloudflare-workers" });
    assert.notEqual(result.code, 0);
    assert.match(result.output, /LOKI_TENANT/);
  });

  test("refuses to start with an empty LOKI_TENANT", async () => {
    const result = await runToExit(script, { API_TOKEN: apiToken, LOKI_TENANT: "" });
    assert.notEqual(result.code, 0);
    assert.match(result.output, /LOKI_TENANT/);
  });
});
