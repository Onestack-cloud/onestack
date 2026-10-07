"use strict";

const { test, describe, before, after } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { stackRoot, startFakeLoki } = require("./helpers");

const backfillUrl = pathToFileURL(path.join(stackRoot, "scripts/backfill-workers-observability.mjs")).href;

function entry(scriptName) {
  return {
    timestamp: String(BigInt(Date.now()) * 1000000n),
    labels: { source: "cloudflare-workers-backfill", scriptName, kind: "console" },
    line: JSON.stringify({ scriptName }),
    scriptName,
  };
}

describe("backfill tenant routing", () => {
  let loki;
  let backfill;

  before(async () => {
    loki = await startFakeLoki();
    backfill = await import(backfillUrl);
  });

  after(async () => {
    await loki.close();
  });

  test("pushes each script's entries to its own tenant", async () => {
    const options = {
      lokiUrl: `${loki.url}/loki/api/v1/push`,
      dryRun: false,
      tenantRouting: backfill.parseTenantRouting(
        "usual-suspects=usual-suspects,usual-suspects-production=usual-suspects",
        "cloudflare-workers",
      ),
    };

    await backfill.pushToLoki(options, [
      entry("usual-suspects"),
      entry("other-worker"),
      entry("usual-suspects-production"),
    ]);

    const byTenant = {};
    for (const push of loki.requests) {
      const tenant = push.headers["x-scope-orgid"];
      const names = JSON.parse(push.body).streams.map((stream) => stream.stream.scriptName);
      byTenant[tenant] = [...(byTenant[tenant] || []), ...names];
    }
    assert.deepEqual(byTenant["usual-suspects"].sort(), ["usual-suspects", "usual-suspects-production"]);
    assert.deepEqual(byTenant["cloudflare-workers"], ["other-worker"]);
    assert.deepEqual(Object.keys(byTenant).sort(), ["cloudflare-workers", "usual-suspects"]);
  });

  test("entries carry no secrets from messages, errors or URLs", () => {
    const event = {
      timestamp: Date.now(),
      source: ["calling", { password: "BF1" }],
      $metadata: {
        id: "evt-1",
        message: "GET https://x.example/cb?code=BF2&state=ok",
        error: "connect postgres://app:BF3@db/main failed",
        trigger: "GET https://x.example/hook?token=BF4",
      },
      $workers: { scriptName: "usual-suspects", event: { request: { url: "https://x.example/?api_key=BF5" } } },
    };
    const entry = backfill.eventToLokiEntry(event, { sourceLabel: "cloudflare-workers-backfill" });
    for (const secret of ["BF1", "BF2", "BF3", "BF4", "BF5"]) {
      assert.ok(!entry.line.includes(secret), `${secret} survived: ${entry.line}`);
    }
    assert.match(entry.line, /state=ok/);
  });

  test("rejects routes that would write to several tenants at once", () => {
    assert.throws(() => backfill.parseTenantRouting("usual-suspects=a|b", "cloudflare-workers"), /LOKI_TENANT_BY_SCRIPT/);
    assert.throws(() => backfill.parseTenantRouting("usual-suspects=usual-suspects", "x|y"), /LOKI_DEFAULT_TENANT/);
    assert.throws(
      () => backfill.parseTenantRouting("usual-suspects=usual-suspects", "usual-suspects"),
      /LOKI_DEFAULT_TENANT/,
    );
  });
});
