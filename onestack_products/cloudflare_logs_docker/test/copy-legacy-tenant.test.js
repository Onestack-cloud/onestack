"use strict";

const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { stackRoot, freePort } = require("./helpers");

const script = path.join(stackRoot, "scripts/copy-legacy-tenant-logs.mjs");
const HOUR = 3600 * 1000;
// Three days ago on the hour, well inside Loki's seven-day acceptance window.
const base = Math.floor((Date.now() - 3 * 24 * HOUR) / HOUR) * HOUR;
const ns = (ms) => String(BigInt(ms) * 1000000n);

function liveLabels(extra = {}) {
  return {
    source: "cloudflare-workers",
    scriptName: "usual-suspects",
    outcome: "ok",
    eventType: "fetch",
    entrypoint: "unknown",
    kind: "console",
    level: "log",
    responseStatus: "200",
    service_name: "unknown_service",
    detected_level: "info",
    ...extra,
  };
}

// Honours the two matcher shapes the script uses: source="x" and scriptName=~"a|b".
function matchesSelector(labels, query) {
  const source = query.match(/source="([^"]*)"/);
  if (source && labels.source !== source[1]) {
    return false;
  }
  const scripts = query.match(/scriptName=~"([^"]*)"/);
  return !scripts || new RegExp(`^(?:${scripts[1]})$`).test(labels.scriptName);
}

// A Loki stand-in that stores entries per tenant, answers query_range for a
// time range with a result limit and records every push. pushResponse may
// answer a push itself with { status, body }.
async function startTenantLoki(seed, { pushResponse, maxQueryEntries } = {}) {
  const store = new Map(Object.entries(seed).map(([tenant, entries]) => [tenant, [...entries]]));
  const pushes = [];
  const server = http.createServer((request, response) => {
    const tenant = request.headers["x-scope-orgid"];
    const url = new URL(request.url, "http://localhost");
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => {
      if (request.method === "POST") {
        const raw = Buffer.concat(chunks);
        const body = JSON.parse(raw.toString("utf8"));
        const custom = pushResponse ? pushResponse(pushes.length) : null;
        pushes.push({ tenant, streams: body.streams, bytes: raw.length, status: custom?.status ?? 204 });
        if (custom) {
          response.writeHead(custom.status, { "content-type": "text/plain" });
          response.end(custom.body);
          return;
        }
        const entries = store.get(tenant) || [];
        for (const stream of body.streams) {
          for (const [ts, line] of stream.values) {
            entries.push({ labels: stream.stream, ts, line });
          }
        }
        store.set(tenant, entries);
        response.writeHead(204);
        response.end();
        return;
      }
      const start = BigInt(url.searchParams.get("start"));
      const end = BigInt(url.searchParams.get("end"));
      const limit = Number(url.searchParams.get("limit"));
      const inRange = (store.get(tenant) || [])
        .filter((entry) => BigInt(entry.ts) >= start && BigInt(entry.ts) < end)
        .filter((entry) => matchesSelector(entry.labels, url.searchParams.get("query")));
      // Like Loki's 4 MB gRPC message cap: a response that would be too big fails.
      if (maxQueryEntries !== undefined && Math.min(inRange.length, limit) > maxQueryEntries) {
        response.writeHead(500, { "content-type": "text/plain" });
        response.end("rpc error: code = ResourceExhausted desc = grpc: received message larger than max");
        return;
      }
      const matching = inRange
        .sort((a, b) => (BigInt(a.ts) < BigInt(b.ts) ? -1 : 1))
        .slice(0, limit);
      const streams = new Map();
      for (const entry of matching) {
        const key = JSON.stringify(entry.labels);
        if (!streams.has(key)) {
          streams.set(key, { stream: entry.labels, values: [] });
        }
        streams.get(key).values.push([entry.ts, entry.line]);
      }
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ status: "success", data: { resultType: "streams", result: [...streams.values()] } }));
    });
  });
  const port = await freePort();
  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
  return { url: `http://127.0.0.1:${port}`, store, pushes, close: () => new Promise((resolve) => server.close(resolve)) };
}

function run(args, env) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [script, ...args], { env: { PATH: process.env.PATH, ...env } });
    let output = "";
    child.stdout.on("data", (chunk) => (output += chunk));
    child.stderr.on("data", (chunk) => (output += chunk));
    child.on("exit", (code) => resolve({ code, output }));
  });
}

const window = ["--from", new Date(base).toISOString(), "--to", new Date(base + 3 * HOUR).toISOString()];

function copied(loki) {
  return (loki.store.get("usual-suspects") || []).filter((entry) => entry.labels.source === "cloudflare-workers-backfill-full");
}

describe("copy-legacy-tenant-logs", () => {
  test("copies the window into the target tenant, relabelled and re-redacted", async () => {
    const loki = await startTenantLoki({
      fake: [
        { labels: liveLabels(), ts: ns(base + 10), line: JSON.stringify({ kind: "console", message: "one" }) },
        {
          labels: liveLabels({ kind: "invocation" }),
          ts: ns(base + HOUR + 5),
          line: JSON.stringify({ kind: "invocation", requestUrl: "https://x.example/cb?code=LEGACYSECRET&state=ok" }),
        },
        // Outside the window and another script: never copied.
        { labels: liveLabels(), ts: ns(base + 5 * HOUR), line: '{"message":"later"}' },
        { labels: liveLabels({ scriptName: "other-worker" }), ts: ns(base + 20), line: '{"message":"foreign"}' },
      ],
    });
    try {
      const result = await run(window, { LOKI_URL: loki.url });
      assert.equal(result.code, 0, result.output);
      const entries = copied(loki);
      assert.deepEqual(entries.map((entry) => entry.ts), [ns(base + 10), ns(base + HOUR + 5)]);
      for (const entry of entries) {
        assert.equal(entry.labels.source, "cloudflare-workers-backfill-full");
        assert.equal(entry.labels.scriptName, "usual-suspects");
        assert.ok(!("service_name" in entry.labels) && !("detected_level" in entry.labels), JSON.stringify(entry.labels));
      }
      assert.ok(!entries[1].line.includes("LEGACYSECRET"), entries[1].line);
      assert.match(entries[1].line, /state=ok/);
    } finally {
      await loki.close();
    }
  });

  test("skips entries the target tenant already has, counting duplicates", async () => {
    const shared = { labels: liveLabels(), ts: ns(base + 100), line: '{"message":"dup"}' };
    const loki = await startTenantLoki({
      fake: [shared, { ...shared }, { labels: liveLabels(), ts: ns(base + 200), line: '{"message":"only legacy"}' }],
      // Live ingest delivered one copy of the duplicated entry after the cutover.
      "usual-suspects": [{ ...shared }],
    });
    try {
      const result = await run(window, { LOKI_URL: loki.url });
      assert.equal(result.code, 0, result.output);
      assert.deepEqual(copied(loki).map((entry) => entry.ts), [ns(base + 100), ns(base + 200)]);
    } finally {
      await loki.close();
    }
  });

  test("running it again copies nothing new", async () => {
    const loki = await startTenantLoki({
      fake: [1, 2, 3].map((n) => ({ labels: liveLabels(), ts: ns(base + n), line: `{"n":${n}}` })),
    });
    try {
      assert.equal((await run(window, { LOKI_URL: loki.url })).code, 0);
      const second = await run(window, { LOKI_URL: loki.url });
      assert.equal(second.code, 0, second.output);
      assert.equal(copied(loki).length, 3);
    } finally {
      await loki.close();
    }
  });

  test("splits a window that hits the query limit instead of losing entries", async () => {
    const loki = await startTenantLoki({
      fake: Array.from({ length: 9 }, (_, n) => ({ labels: liveLabels(), ts: ns(base + n * 60000), line: `{"n":${n}}` })),
    });
    try {
      const result = await run([...window, "--limit", "2"], { LOKI_URL: loki.url });
      assert.equal(result.code, 0, result.output);
      assert.equal(copied(loki).length, 9);
    } finally {
      await loki.close();
    }
  });

  test("a query Loki fails on is split into smaller ranges", async () => {
    const loki = await startTenantLoki(
      { fake: Array.from({ length: 40 }, (_, n) => ({ labels: liveLabels(), ts: ns(base + n * 60000), line: `{"n":${n}}` })) },
      { maxQueryEntries: 6 },
    );
    try {
      const result = await run(window, { LOKI_URL: loki.url, COPY_RETRY_DELAY_MS: "1" });
      assert.equal(result.code, 0, result.output);
      assert.equal(copied(loki).length, 40);
    } finally {
      await loki.close();
    }
  });

  test("pushes each stream oldest first", async () => {
    const loki = await startTenantLoki({
      fake: [5, 1, 4, 2, 3].map((n) => ({ labels: liveLabels(), ts: ns(base + n * HOUR / 3), line: `{"n":${n}}` })),
    });
    try {
      assert.equal((await run(window, { LOKI_URL: loki.url })).code, 0);
      const order = loki.pushes.flatMap((push) => push.streams.flatMap((stream) => stream.values.map(([ts]) => BigInt(ts))));
      assert.deepEqual(order, [...order].sort((a, b) => (a < b ? -1 : 1)));
    } finally {
      await loki.close();
    }
  });

  test("--dry-run reports what it would copy and writes nothing", async () => {
    const loki = await startTenantLoki({ fake: [{ labels: liveLabels(), ts: ns(base + 1), line: "{}" }] });
    try {
      const result = await run([...window, "--dry-run"], { LOKI_URL: loki.url });
      assert.equal(result.code, 0, result.output);
      assert.equal(loki.pushes.length, 0);
      assert.match(result.output, /"wouldCopy":1/);
    } finally {
      await loki.close();
    }
  });

  test("console messages are rebuilt from the original arguments and redacted", async () => {
    // Before the cutover, ingest joined console arguments into "message"
    // without redacting them.
    const line = JSON.stringify({
      kind: "console",
      message: "apiKey sk_live_LEGACY1 otp 123456",
      log: { level: "log", message: ["apiKey", "sk_live_LEGACY1", "otp", 123456] },
    });
    const loki = await startTenantLoki({ fake: [{ labels: liveLabels(), ts: ns(base + 1), line }] });
    try {
      assert.equal((await run(window, { LOKI_URL: loki.url })).code, 0);
      const [entry] = copied(loki);
      assert.ok(!entry.line.includes("sk_live_LEGACY1") && !entry.line.includes("123456"), entry.line);
      assert.match(JSON.parse(entry.line).message, /^apiKey \[redacted\] otp \[redacted\]$/);
    } finally {
      await loki.close();
    }
  });

  test("any rejected push stops the run", async () => {
    const tooFarBehind = "entry with timestamp x ignored, reason: 'entry too far behind',\nuser 'usual-suspects', total ignored: 1 out of 1 for stream: {a=\"b\"}\n";
    const loki = await startTenantLoki(
      { fake: [{ labels: liveLabels(), ts: ns(base + 1), line: "{}" }] },
      { pushResponse: () => ({ status: 400, body: tooFarBehind }) },
    );
    try {
      const result = await run(window, { LOKI_URL: loki.url });
      assert.notEqual(result.code, 0, result.output);
    } finally {
      await loki.close();
    }
  });

  test("rate-limited pushes are retried rather than aborting", async () => {
    const loki = await startTenantLoki(
      { fake: [{ labels: liveLabels(), ts: ns(base + 1), line: "{}" }] },
      { pushResponse: (index) => (index === 0 ? { status: 429, body: "Ingestion rate limit exceeded" } : null) },
    );
    try {
      const result = await run(window, { LOKI_URL: loki.url, COPY_RETRY_DELAY_MS: "10" });
      assert.equal(result.code, 0, result.output);
      assert.equal(copied(loki).length, 1);
    } finally {
      await loki.close();
    }
  });

  test("pushes stay around a megabyte so live ingestion keeps its rate", async () => {
    const big = "x".repeat(200 * 1024);
    const loki = await startTenantLoki({
      fake: Array.from({ length: 12 }, (_, n) => ({ labels: liveLabels(), ts: ns(base + n), line: JSON.stringify({ n, big }) })),
    });
    try {
      assert.equal((await run(window, { LOKI_URL: loki.url, COPY_PAUSE_MS: "0" })).code, 0);
      assert.equal(copied(loki).length, 12);
      assert.ok(loki.pushes.length >= 3, `only ${loki.pushes.length} pushes`);
      for (const push of loki.pushes) {
        assert.ok(push.bytes < 1.5 * 1024 * 1024, `push of ${push.bytes} bytes`);
      }
    } finally {
      await loki.close();
    }
  });

  test("dedupe prefers the exact line and ignores Loki's internal labels", async () => {
    const at = ns(base + 7);
    const loki = await startTenantLoki({
      fake: [
        { labels: liveLabels(), ts: at, line: '{"message":"first"}' },
        { labels: liveLabels(), ts: at, line: '{"message":"second"}' },
      ],
      // An earlier partial run copied only "second", and Loki sharded the stream.
      "usual-suspects": [
        { labels: { ...liveLabels(), source: "cloudflare-workers-backfill-full", __stream_shard__: "1" }, ts: at, line: '{"message":"second"}' },
      ],
    });
    try {
      assert.equal((await run(window, { LOKI_URL: loki.url })).code, 0);
      const lines = copied(loki).map((entry) => entry.line).sort();
      assert.deepEqual(lines, ['{"message":"first"}', '{"message":"second"}']);
    } finally {
      await loki.close();
    }
  });

  test("only live-sourced legacy entries are read", async () => {
    const loki = await startTenantLoki({
      fake: [
        { labels: liveLabels(), ts: ns(base + 1), line: '{"message":"live"}' },
        { labels: liveLabels({ source: "cloudflare-workers-backfill-full" }), ts: ns(base + 2), line: '{"message":"old backfill"}' },
      ],
    });
    try {
      assert.equal((await run(window, { LOKI_URL: loki.url })).code, 0);
      assert.deepEqual(copied(loki).map((entry) => entry.line), ['{"message":"live"}']);
    } finally {
      await loki.close();
    }
  });

  test("refuses a target that is not a single tenant or a window Loki would reject", async () => {
    for (const args of [
      [...window, "--to-tenant", "usual-suspects|cloudflare-workers"],
      [...window, "--to-tenant", "fake"],
      ["--from", new Date(Date.now() - 8 * 24 * HOUR).toISOString(), "--to", new Date().toISOString()],
      ["--from", new Date(base + HOUR).toISOString(), "--to", new Date(base).toISOString()],
    ]) {
      const result = await run(args, { LOKI_URL: "http://127.0.0.1:9" });
      assert.notEqual(result.code, 0, args.join(" "));
      assert.match(result.output, /^Refusing:/m, args.join(" "));
    }
  });
});
