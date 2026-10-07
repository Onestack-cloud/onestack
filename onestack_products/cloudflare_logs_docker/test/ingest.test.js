"use strict";

const { test, describe, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { startFakeLoki, startService, runToExit } = require("./helpers");

const authToken = "ingest-token";
const script = "ingest/server.js";
const tenantRoutes = "usual-suspects=usual-suspects,usual-suspects-production=usual-suspects";

function record(scriptName) {
  return { ScriptName: scriptName, Outcome: "ok", EventType: "fetch", EventTimestampMs: Date.now(), Logs: [] };
}

function pushedScriptNames(request) {
  return JSON.parse(request.body).streams.map((stream) => stream.stream.scriptName);
}

describe("ingest tenant routing", () => {
  let loki;
  let ingest;

  before(async () => {
    loki = await startFakeLoki();
    ingest = await startService(script, {
      AUTH_TOKEN: authToken,
      LOKI_URL: `${loki.url}/loki/api/v1/push`,
      ALLOWED_SCRIPT_NAMES: "",
      LOKI_TENANT_BY_SCRIPT: tenantRoutes,
      LOKI_DEFAULT_TENANT: "cloudflare-workers",
    });
  });

  after(async () => {
    await ingest.stop();
    await loki.close();
  });

  async function logpush(records) {
    const before = loki.requests.length;
    const response = await fetch(`${ingest.url}/cloudflare-logpush`, {
      method: "POST",
      headers: { authorization: `Bearer ${authToken}` },
      body: records.map((value) => JSON.stringify(value)).join("\n"),
    });
    assert.equal(response.status, 202, await response.text());
    return loki.requests.slice(before);
  }

  test("each push carries exactly one tenant and only that tenant's scripts", async () => {
    const pushes = await logpush([
      record("usual-suspects"),
      record("other-worker"),
      record("usual-suspects-production"),
      record("billing-worker"),
    ]);

    const byTenant = {};
    for (const push of pushes) {
      const tenant = push.headers["x-scope-orgid"];
      assert.ok(tenant, "push is missing X-Scope-OrgID");
      assert.ok(!tenant.includes("|"), "push must target a single tenant");
      byTenant[tenant] = [...(byTenant[tenant] || []), ...pushedScriptNames(push)];
    }

    assert.deepEqual(byTenant["usual-suspects"].sort(), ["usual-suspects", "usual-suspects-production"]);
    assert.deepEqual(byTenant["cloudflare-workers"].sort(), ["billing-worker", "other-worker"]);
  });

  test("a script that only looks like a Usual Suspects script is not routed there", async () => {
    const pushes = await logpush([record("usual-suspects-staging"), record("Usual-Suspects")]);
    assert.ok(pushes.length > 0);
    for (const push of pushes) {
      assert.equal(push.headers["x-scope-orgid"], "cloudflare-workers");
    }
  });
});

describe("ingest tenant configuration", () => {
  test("refuses to start with a multi-tenant route", async () => {
    const result = await runToExit(script, {
      AUTH_TOKEN: authToken,
      LOKI_TENANT_BY_SCRIPT: "usual-suspects=usual-suspects|cloudflare-workers",
    });
    assert.notEqual(result.code, 0);
    assert.match(result.output, /LOKI_TENANT_BY_SCRIPT/);
  });

  test("refuses to start with a malformed route", async () => {
    const result = await runToExit(script, { AUTH_TOKEN: authToken, LOKI_TENANT_BY_SCRIPT: "usual-suspects" });
    assert.notEqual(result.code, 0);
    assert.match(result.output, /LOKI_TENANT_BY_SCRIPT/);
  });

  test("refuses to start with an invalid default tenant", async () => {
    const result = await runToExit(script, { AUTH_TOKEN: authToken, LOKI_DEFAULT_TENANT: "a|b" });
    assert.notEqual(result.code, 0);
    assert.match(result.output, /LOKI_DEFAULT_TENANT/);
  });

  test("refuses to use the Usual Suspects tenant as the default", async () => {
    const result = await runToExit(script, {
      AUTH_TOKEN: authToken,
      LOKI_TENANT_BY_SCRIPT: tenantRoutes,
      LOKI_DEFAULT_TENANT: "usual-suspects",
    });
    assert.notEqual(result.code, 0);
    assert.match(result.output, /LOKI_DEFAULT_TENANT/);
  });
});
