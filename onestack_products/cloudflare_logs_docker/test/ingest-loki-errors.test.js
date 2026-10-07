"use strict";

const { test, describe, after } = require("node:test");
const assert = require("node:assert/strict");
const zlib = require("node:zlib");
const { startFakeLoki, startService } = require("./helpers");

const authToken = "ingest-token";
const tenantRoutes = "usual-suspects=usual-suspects";

// The body production's Loki 3.7 returned for a late Logpush entry.
const tooFarBehind = [
  "entry with timestamp 2026-10-07 01:35:32.405 +0000 UTC ignored, reason: 'entry too far behind, entry timestamp is: 2026-10-07T01:35:32Z, oldest acceptable timestamp is: 2026-10-07T03:23:59Z',",
  "user 'usual-suspects', total ignored: 1 out of 1 for stream: {kind=\"invocation\", scriptName=\"usual-suspects\"}",
  "",
].join("\n");

function record(scriptName) {
  return JSON.stringify({ ScriptName: scriptName, Outcome: "ok", EventType: "fetch", EventTimestampMs: Date.now(), Logs: [] });
}

async function withIngest(pushResponse, env, run) {
  const loki = await startFakeLoki({ pushResponse });
  const ingest = await startService("ingest/server.js", {
    AUTH_TOKEN: authToken,
    LOKI_URL: `${loki.url}/loki/api/v1/push`,
    LOKI_TENANT_BY_SCRIPT: tenantRoutes,
    LOKI_DEFAULT_TENANT: "cloudflare-workers",
    ...env,
  });
  try {
    await run({ loki, ingest });
  } finally {
    await ingest.stop();
    await loki.close();
  }
}

async function logpush(ingest, body, headers = {}) {
  const response = await fetch(`${ingest.url}/cloudflare-logpush`, {
    method: "POST",
    headers: { authorization: `Bearer ${authToken}`, ...headers },
    body,
  });
  return { status: response.status, text: await response.text() };
}

describe("ingest handling of Loki rejections", () => {
  test("entries Loki will never accept do not make Logpush retry the batch", async () => {
    await withIngest(() => ({ status: 400, body: tooFarBehind }), {}, async ({ ingest }) => {
      const { status, text } = await logpush(ingest, record("usual-suspects"));
      assert.equal(status, 202, text);
      assert.match(ingest.output(), /too far behind/);
    });
  });

  test("out of order and too old entries are treated the same way", async () => {
    for (const reason of ["entry out of order", "entry for stream '{a=\"b\"}' has timestamp too old: 2026-01-01T00:00:00Z"]) {
      const body = `entry with timestamp x ignored, reason: '${reason}',\nuser 'usual-suspects', total ignored: 1 out of 3 for stream: {a="b"}\n`;
      await withIngest(() => ({ status: 400, body }), {}, async ({ ingest }) => {
        assert.equal((await logpush(ingest, record("usual-suspects"))).status, 202, reason);
      });
    }
  });

  test("other Loki errors still fail the batch so Logpush retries", async () => {
    for (const [status, body] of [
      [400, "error parsing labels {a=: parse error"],
      [400, `${tooFarBehind}\nerror at line 2: invalid stream labels\n`],
      [429, "Ingestion rate limit exceeded"],
      [500, "internal error"],
    ]) {
      await withIngest(() => ({ status, body }), {}, async ({ ingest }) => {
        assert.equal((await logpush(ingest, record("usual-suspects"))).status, 502, body);
      });
    }
  });

  test("a rejected late entry for one tenant does not stop pushes to the others", async () => {
    const pushResponse = (request) =>
      request.headers["x-scope-orgid"] === "usual-suspects" ? { status: 400, body: tooFarBehind } : null;
    await withIngest(pushResponse, { ALLOWED_SCRIPT_NAMES: "" }, async ({ loki, ingest }) => {
      const before = loki.requests.length;
      const { status } = await logpush(ingest, [record("usual-suspects"), record("other-worker")].join("\n"));
      assert.equal(status, 202);
      const tenants = loki.requests.slice(before).map((request) => request.headers["x-scope-orgid"]).sort();
      assert.deepEqual(tenants, ["cloudflare-workers", "usual-suspects"]);
    });
  });
});

describe("ingest decompression limit", () => {
  test("a gzip bomb is refused without exhausting memory", async () => {
    // About 10 KB compressed, 10 MB once decompressed.
    const bomb = zlib.gzipSync(Buffer.alloc(10 * 1024 * 1024, 0x20));
    await withIngest(null, { MAX_DECODED_BYTES: String(1024 * 1024) }, async ({ ingest }) => {
      const { status, text } = await logpush(ingest, bomb, { "content-encoding": "gzip" });
      assert.equal(status, 413, text);
      // Still serving afterwards.
      assert.equal((await logpush(ingest, record("usual-suspects"))).status, 202);
    });
  });

  test("normal gzip batches still decode", async () => {
    await withIngest(null, {}, async ({ ingest }) => {
      const { status, text } = await logpush(ingest, zlib.gzipSync(record("usual-suspects")), { "content-encoding": "gzip" });
      assert.equal(status, 202, text);
    });
  });
});
