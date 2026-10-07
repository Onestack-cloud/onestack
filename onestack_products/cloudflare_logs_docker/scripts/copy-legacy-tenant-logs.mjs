#!/usr/bin/env node

// Copies Usual Suspects logs that live ingest wrote to Loki's legacy "fake"
// tenant before tenancy was enabled (ADR-0002) into the usual-suspects tenant,
// so the client sees that history again. Every line is re-redacted with the
// current rules and written under the backfill source label, which the proxy
// already serves. Entries the target already holds (same timestamp and labels,
// whatever the source label) are skipped, so a run can be repeated safely.

import { createRequire } from "node:module";

const { redact, normalizeMessage } = createRequire(import.meta.url)("../ingest/redaction.js");

const HOUR = 3600 * 1000;
// Loki rejects entries older than reject_old_samples_max_age (168h by default).
const MAX_AGE = 167 * HOUR;
const TENANT_ID = /^(?!\.{1,2}$)[A-Za-z0-9_.-]{1,150}$/;
// Labels Loki derives on ingest; it adds them again on the copy.
const DERIVED_LABELS = new Set(["service_name", "detected_level"]);
// Keeps the copy well under Loki's default 4 MB/s ingestion rate (6 MB burst),
// which live Logpush shares.
const PUSH_BYTES = 1024 * 1024;
const PAUSE_MS = Number(process.env.COPY_PAUSE_MS ?? 400);
const RETRY_DELAY_MS = Number(process.env.COPY_RETRY_DELAY_MS ?? 5000);
const MAX_ATTEMPTS = 6;

function refuse(message) {
  console.error(`Refusing: ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const options = {
    lokiUrl: (process.env.LOKI_URL || "http://loki:3100").replace(/\/+$/, ""),
    fromTenant: "fake",
    toTenant: "usual-suspects",
    // Reads only what live ingest wrote, never earlier backfills.
    selector: '{source="cloudflare-workers", scriptName=~"usual-suspects|usual-suspects-production"}',
    // Everything already in the target, whatever its source, for dedupe.
    targetSelector: '{scriptName=~"usual-suspects|usual-suspects-production"}',
    scripts: ["usual-suspects", "usual-suspects-production"],
    sourceLabel: "cloudflare-workers-backfill-full",
    windowMinutes: 60,
    limit: 5000,
    dryRun: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const value = () => argv[++index];
    if (arg === "--dry-run") options.dryRun = true;
    else if (arg === "--from") options.from = Date.parse(value());
    else if (arg === "--to") options.to = Date.parse(value());
    else if (arg === "--from-tenant") options.fromTenant = value();
    else if (arg === "--to-tenant") options.toTenant = value();
    else if (arg === "--selector") options.selector = value();
    else if (arg === "--target-selector") options.targetSelector = value();
    else if (arg === "--scripts") options.scripts = value().split(",").map((name) => name.trim()).filter(Boolean);
    else if (arg === "--source-label") options.sourceLabel = value();
    else if (arg === "--window-minutes") options.windowMinutes = Number(value());
    else if (arg === "--limit") options.limit = Number(value());
    else refuse(`unknown argument ${arg}`);
  }

  if (!Number.isFinite(options.from) || !Number.isFinite(options.to) || options.from >= options.to) {
    refuse("--from and --to must be timestamps with --from before --to");
  }
  if (options.from < Date.now() - MAX_AGE) {
    refuse(`--from is older than Loki accepts; use ${new Date(Date.now() - MAX_AGE).toISOString()} or later`);
  }
  for (const [flag, tenant] of [["--from-tenant", options.fromTenant], ["--to-tenant", options.toTenant]]) {
    if (!TENANT_ID.test(tenant)) {
      refuse(`${flag} must be a single Loki tenant ID`);
    }
  }
  if (options.scripts.length === 0) {
    refuse("--scripts must name at least one Worker script");
  }
  if (options.fromTenant === options.toTenant) {
    refuse("--from-tenant and --to-tenant must differ");
  }
  if (!(options.windowMinutes > 0) || !(options.limit > 1)) {
    refuse("--window-minutes must be positive and --limit above 1");
  }
  return options;
}

const ns = (ms) => BigInt(Math.trunc(ms)) * 1000000n;

// Without source, Loki's derived labels and its internal __ labels (such as
// __stream_shard__), so live, legacy and copied entries compare equal.
function identityLabels(labels) {
  return Object.fromEntries(
    Object.entries(labels)
      .filter(([name]) => name !== "source" && !DERIVED_LABELS.has(name) && !name.startsWith("__"))
      .sort(([a], [b]) => (a < b ? -1 : 1)),
  );
}

// An entry's identity ignores the source label, so a live copy and a
// backfilled copy of the same event count as the same entry.
function entryKey(labels, ts) {
  return `${ts}|${JSON.stringify(identityLabels(labels))}`;
}

async function queryRange(options, tenant, startNs, endNs) {
  const params = new URLSearchParams({
    query: tenant === options.toTenant ? options.targetSelector : options.selector,
    start: String(startNs),
    end: String(endNs),
    limit: String(options.limit),
    direction: "forward",
  });
  const response = await fetch(`${options.lokiUrl}/loki/api/v1/query_range?${params}`, {
    headers: { "X-Scope-OrgID": tenant },
  });
  if (!response.ok) {
    throw new Error(`query for tenant ${tenant} failed: ${response.status} ${(await response.text()).slice(0, 500)}`);
  }
  const entries = [];
  for (const stream of (await response.json()).data?.result || []) {
    for (const [ts, line] of stream.values) {
      entries.push({ labels: stream.stream, ts, line });
    }
  }
  return entries;
}

// Reads [startNs, endNs) completely, halving the range whenever a query
// returns as many entries as the limit allows.
async function readAll(options, tenant, startNs, endNs) {
  const entries = await queryRange(options, tenant, startNs, endNs);
  if (entries.length < options.limit) {
    return entries;
  }
  if (endNs - startNs <= 1n) {
    throw new Error(`more than ${options.limit} entries share one nanosecond in tenant ${tenant}; raise --limit`);
  }
  const middle = startNs + (endNs - startNs) / 2n;
  return [...(await readAll(options, tenant, startNs, middle)), ...(await readAll(options, tenant, middle, endNs))];
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Before the cutover, ingest joined console arguments into "message" without
// redacting them, so rebuild it from the original arguments with today's rules
// before redacting the rest of the line.
function redactLine(line) {
  let parsed;
  try {
    parsed = JSON.parse(line);
  } catch {
    return redact(line);
  }
  if (parsed && typeof parsed === "object" && parsed.kind === "console" && parsed.log && typeof parsed.log === "object") {
    const original = parsed.log.message ?? parsed.log.Message;
    if (original !== undefined) {
      parsed.message = normalizeMessage(original);
    }
  }
  return JSON.stringify(redact(parsed));
}

// Any rejection stops the run: the target streams are new, so Loki refusing an
// entry means something is wrong. Rate limits and server errors are retried.
async function push(options, entries) {
  const streams = new Map();
  for (const entry of entries) {
    const key = JSON.stringify(entry.labels);
    if (!streams.has(key)) {
      streams.set(key, { stream: entry.labels, values: [] });
    }
    streams.get(key).values.push([entry.ts, entry.line]);
  }
  const body = JSON.stringify({ streams: [...streams.values()] });
  for (let attempt = 1; ; attempt += 1) {
    const response = await fetch(`${options.lokiUrl}/loki/api/v1/push`, {
      method: "POST",
      headers: { "content-type": "application/json", "X-Scope-OrgID": options.toTenant },
      body,
    });
    if (response.ok) {
      return;
    }
    const text = await response.text();
    const retryable = response.status === 429 || response.status >= 500;
    if (!retryable || attempt >= MAX_ATTEMPTS) {
      throw new Error(`push to tenant ${options.toTenant} failed: ${response.status} ${text.slice(0, 500)}`);
    }
    console.warn(`push got ${response.status}, retrying (attempt ${attempt} of ${MAX_ATTEMPTS})`);
    await sleep(RETRY_DELAY_MS * attempt);
  }
}

// Splits entries into pushes of roughly PUSH_BYTES.
function batches(entries) {
  const result = [];
  let current = [];
  let size = 0;
  for (const entry of entries) {
    const entrySize = entry.line.length + 64;
    if (current.length > 0 && size + entrySize > PUSH_BYTES) {
      result.push(current);
      current = [];
      size = 0;
    }
    current.push(entry);
    size += entrySize;
  }
  if (current.length > 0) {
    result.push(current);
  }
  return result;
}

async function copyWindow(options, startMs, endMs) {
  const [source, existing] = await Promise.all([
    readAll(options, options.fromTenant, ns(startMs), ns(endMs)),
    readAll(options, options.toTenant, ns(startMs), ns(endMs)),
  ]);

  // Counts, so two identical legacy entries against one existing copy still
  // copy one. Exact (redacted) lines are matched first, so a partial earlier
  // run is completed with the entries it actually missed.
  const presentExact = new Map();
  const presentKey = new Map();
  const increment = (map, key) => map.set(key, (map.get(key) || 0) + 1);
  for (const entry of existing) {
    const key = entryKey(entry.labels, entry.ts);
    increment(presentKey, key);
    increment(presentExact, `${key}|${entry.line}`);
  }

  const toCopy = [];
  const pending = [];
  let foreign = 0;
  for (const entry of source) {
    // The selector should already exclude other scripts; this guarantees no
    // other Worker's logs ever reach the target tenant, whatever --selector says.
    if (!options.scripts.includes(entry.labels.scriptName)) {
      foreign += 1;
      continue;
    }
    const key = entryKey(entry.labels, entry.ts);
    const line = redactLine(entry.line);
    const exactKey = `${key}|${line}`;
    if ((presentExact.get(exactKey) || 0) > 0) {
      presentExact.set(exactKey, presentExact.get(exactKey) - 1);
      presentKey.set(key, presentKey.get(key) - 1);
      continue;
    }
    pending.push({ key, entry: { labels: { ...identityLabels(entry.labels), source: options.sourceLabel }, ts: entry.ts, line } });
  }
  // Then fall back to timestamp and labels for copies whose line differs,
  // such as live entries written by today's ingest.
  for (const { key, entry } of pending) {
    if ((presentKey.get(key) || 0) > 0) {
      presentKey.set(key, presentKey.get(key) - 1);
      continue;
    }
    toCopy.push(entry);
  }
  toCopy.sort((a, b) => (BigInt(a.ts) < BigInt(b.ts) ? -1 : BigInt(a.ts) > BigInt(b.ts) ? 1 : 0));

  if (!options.dryRun) {
    for (const batch of batches(toCopy)) {
      await push(options, batch);
      await sleep(PAUSE_MS);
    }
  }
  return { read: source.length, skipped: source.length - toCopy.length - foreign, foreign, copied: toCopy.length };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const windowMs = options.windowMinutes * 60 * 1000;
  const totals = { read: 0, skipped: 0, foreign: 0, copied: 0 };
  for (let start = options.from; start < options.to; start += windowMs) {
    const end = Math.min(start + windowMs, options.to);
    const result = await copyWindow(options, start, end);
    for (const key of Object.keys(totals)) {
      totals[key] += result[key];
    }
    console.log(JSON.stringify({ window: new Date(start).toISOString(), ...result }));
  }
  console.log(
    JSON.stringify(
      options.dryRun
        ? { dryRun: true, read: totals.read, skipped: totals.skipped, foreign: totals.foreign, wouldCopy: totals.copied }
        : { done: true, ...totals },
    ),
  );
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
