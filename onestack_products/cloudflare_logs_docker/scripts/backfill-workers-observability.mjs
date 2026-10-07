#!/usr/bin/env node

const API_BASE = "https://api.cloudflare.com/client/v4";
const DEFAULT_ACCOUNT_ID = "663b85e4f509df63c1735f6e77db4370";
const DEFAULT_SCRIPT_NAMES = ["usual-suspects", "usual-suspects-production"];
const DEFAULT_LOKI_URL = "http://loki:3100/loki/api/v1/push";
const MAX_LIMIT = 2000;

function parseArgs(argv) {
  const options = {
    accountId: process.env.CF_ACCOUNT_ID || process.env.CLOUDFLARE_ACCOUNT_ID || DEFAULT_ACCOUNT_ID,
    scriptNames: (process.env.ALLOWED_SCRIPT_NAMES || DEFAULT_SCRIPT_NAMES.join(","))
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
    lokiUrl: process.env.LOKI_URL || DEFAULT_LOKI_URL,
    from: Date.now() - 7 * 24 * 60 * 60 * 1000,
    to: Date.now(),
    limit: MAX_LIMIT,
    maxPages: Number.POSITIVE_INFINITY,
    dryRun: false,
    noScriptFilter: false,
    datasets: [],
    sourceLabel: process.env.BACKFILL_SOURCE_LABEL || "cloudflare-workers-backfill",
    pageSleepMs: 250,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const readValue = () => {
      const inline = arg.includes("=") ? arg.slice(arg.indexOf("=") + 1) : null;
      if (inline !== null) {
        return inline;
      }
      index += 1;
      return argv[index];
    };

    if (arg === "--dry-run") {
      options.dryRun = true;
    } else if (arg === "--no-script-filter") {
      options.noScriptFilter = true;
    } else if (arg.startsWith("--account-id")) {
      options.accountId = readValue();
    } else if (arg.startsWith("--scripts")) {
      options.scriptNames = readValue()
        .split(",")
        .map((value) => value.trim())
        .filter(Boolean);
    } else if (arg.startsWith("--dataset")) {
      options.datasets = readValue()
        .split(",")
        .map((value) => value.trim())
        .filter(Boolean);
    } else if (arg.startsWith("--source-label")) {
      options.sourceLabel = readValue();
    } else if (arg.startsWith("--from")) {
      options.from = parseTime(readValue(), "--from");
    } else if (arg.startsWith("--to")) {
      options.to = parseTime(readValue(), "--to");
    } else if (arg.startsWith("--limit")) {
      options.limit = Math.min(Number.parseInt(readValue(), 10), MAX_LIMIT);
    } else if (arg.startsWith("--max-pages")) {
      options.maxPages = Number.parseInt(readValue(), 10);
    } else if (arg.startsWith("--page-sleep-ms")) {
      options.pageSleepMs = Number.parseInt(readValue(), 10);
    } else if (arg.startsWith("--loki-url")) {
      options.lokiUrl = readValue();
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!options.accountId) {
    throw new Error("Missing Cloudflare account ID");
  }
  if (!options.noScriptFilter && options.scriptNames.length === 0) {
    throw new Error("At least one script name is required");
  }
  if (!Number.isFinite(options.from) || !Number.isFinite(options.to) || options.from >= options.to) {
    throw new Error("Invalid time range");
  }
  if (!Number.isFinite(options.limit) || options.limit <= 0) {
    throw new Error("Invalid page limit");
  }

  return options;
}

function parseTime(value, flag) {
  if (!value) {
    throw new Error(`${flag} requires a value`);
  }
  if (/^\d+$/.test(value)) {
    return Number.parseInt(value, 10);
  }
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) {
    throw new Error(`${flag} must be a Unix millisecond timestamp or ISO timestamp`);
  }
  return parsed;
}

function authHeaders() {
  const token = process.env.CLOUDFLARE_API_TOKEN || process.env.CF_API_TOKEN;
  if (token) {
    return { authorization: `Bearer ${token}` };
  }

  const email = process.env.CF_API_EMAIL || process.env.CLOUDFLARE_EMAIL;
  const key = process.env.CF_API_KEY || process.env.CLOUDFLARE_API_KEY;
  if (email && key) {
    return { "x-auth-email": email, "x-auth-key": key };
  }

  throw new Error("Missing Cloudflare auth. Set CLOUDFLARE_API_TOKEN or CF_API_EMAIL + CF_API_KEY.");
}

function redactUrl(value) {
  if (typeof value !== "string") {
    return value;
  }

  return value.replace(/https?:\/\/[^\s"'<>]+/g, (candidate) => {
    try {
      const url = new URL(candidate);
      for (const key of [...url.searchParams.keys()]) {
        if (/authorization|cookie|password|secret|token|api[-_]?key|code/i.test(key)) {
          url.searchParams.set(key, "[redacted]");
        }
      }
      return url.toString();
    } catch {
      return candidate;
    }
  });
}

function redact(value, parentKey = "") {
  if (Array.isArray(value)) {
    return value.map((nested) => redact(nested));
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => {
        if (/authorization|cookie|password|secret|token|api[-_]?key/i.test(key)) {
          return [key, "[redacted]"];
        }
        return [key, redact(nested, key)];
      }),
    );
  }

  if (typeof value === "string" && /url|uri|href|source|message|trigger/i.test(parentKey)) {
    return redactUrl(value);
  }

  return value;
}

function labelValue(value, fallback = "unknown") {
  const stringValue = String(value ?? fallback)
    .replace(/[^A-Za-z0-9_.:-]/g, "_")
    .slice(0, 120);
  return stringValue || fallback;
}

function timestampNs(timestampMs) {
  const numeric = Number(timestampMs);
  const millis = Number.isFinite(numeric) && numeric > 0 ? Math.trunc(numeric) : Date.now();
  return String(BigInt(millis) * 1000000n);
}

function normalizeMessage(source) {
  if (typeof source === "string") {
    return redactUrl(source);
  }
  if (source === null || source === undefined) {
    return "";
  }
  return JSON.stringify(redact(source));
}

function inferKind(event) {
  const type = event?.$metadata?.type || event?.$workers?.type;
  if (type === "cf-worker-event") {
    return "invocation";
  }
  if (type === "cf-worker-log") {
    return "console";
  }
  if (event?.$metadata?.error) {
    return "exception";
  }
  return "event";
}

function inferRequestSummary(event) {
  const workersEvent = event?.$workers?.event || {};
  const request = workersEvent.request || workersEvent.Request || {};
  const response = workersEvent.response || workersEvent.Response || {};
  const metadata = event?.$metadata || {};
  const trigger = metadata.trigger || "";
  const triggerMatch = typeof trigger === "string" ? trigger.match(/^([A-Z]+)\s+(https?:\/\/\S+)/) : null;

  return {
    requestMethod: request.method || request.Method || triggerMatch?.[1] || null,
    requestUrl: redactUrl(request.url || request.URL || metadata.url || triggerMatch?.[2] || null),
    responseStatus: response.status || response.Status || metadata.statusCode || null,
  };
}

function eventToLokiEntry(event, options) {
  const metadata = event.$metadata || {};
  const workers = event.$workers || {};
  const scriptName = workers.scriptName || metadata.service || "unknown";
  const kind = inferKind(event);
  const requestSummary = inferRequestSummary(event);
  const level = metadata.level || (kind === "exception" ? "error" : "log");
  const eventType = workers.eventType || metadata.origin || "unknown";
  const timestampMs = event.timestamp || metadata.startTime || metadata.endTime;

  const line = JSON.stringify({
    kind,
    backfill: true,
    cloudflareEventId: metadata.id,
    scriptName,
    level,
    message: metadata.message || normalizeMessage(event.source),
    outcome: workers.outcome,
    eventType,
    cpuTimeMs: workers.cpuTimeMs,
    wallTimeMs: workers.wallTimeMs,
    requestId: workers.requestId || metadata.requestId,
    ...requestSummary,
    source: redact(event.source, "source"),
    metadata: redact(metadata),
    workers: redact(workers),
  });

  return {
    timestamp: timestampNs(timestampMs),
    labels: {
      source: labelValue(options.sourceLabel),
      scriptName: labelValue(scriptName),
      outcome: labelValue(workers.outcome || metadata.outcome),
      eventType: labelValue(eventType),
      entrypoint: labelValue(workers.entrypoint || metadata.entrypoint),
      kind,
      level: labelValue(level, "log"),
      responseStatus: labelValue(requestSummary.responseStatus),
    },
    line,
    scriptName,
    timestampMs,
  };
}

function queryBody(options, offset) {
  const scriptFilters = options.scriptNames.flatMap((scriptName) => [
    { kind: "filter", key: "$metadata.service", operation: "eq", type: "string", value: scriptName },
    { kind: "filter", key: "$workers.scriptName", operation: "eq", type: "string", value: scriptName },
  ]);
  const filters =
    options.noScriptFilter || scriptFilters.length === 0
      ? []
      : [
          {
            kind: "group",
            filterCombination: "or",
            filters: scriptFilters,
          },
        ];

  return {
    queryId: "usual-suspects-manual-backfill",
    timeframe: { from: options.from, to: options.to },
    dry: true,
    limit: options.limit,
    view: "events",
    ...(offset ? { offset, offsetDirection: "next" } : {}),
    parameters: {
      ...(options.datasets.length > 0 ? { datasets: options.datasets } : {}),
      filterCombination: "and",
      filters,
      view: "events",
    },
  };
}

async function cloudflareRequest(options, body) {
  const response = await fetch(`${API_BASE}/accounts/${options.accountId}/workers/observability/telemetry/query`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...authHeaders(),
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`Cloudflare returned non-JSON response ${response.status}: ${text.slice(0, 300)}`);
  }

  if (!response.ok || json.success === false) {
    const messages = [
      ...(json.errors || []).map((error) => error.message || JSON.stringify(error)),
      ...(json.messages || []).map((message) => message.message || JSON.stringify(message)),
    ];
    throw new Error(`Cloudflare query failed ${response.status}: ${messages.join("; ") || text.slice(0, 300)}`);
  }

  return json;
}

function groupForLoki(entries) {
  const streams = new Map();
  for (const entry of entries) {
    const key = JSON.stringify(entry.labels);
    const existing = streams.get(key);
    if (existing) {
      existing.values.push([entry.timestamp, entry.line]);
    } else {
      streams.set(key, { stream: entry.labels, values: [[entry.timestamp, entry.line]] });
    }
  }

  for (const stream of streams.values()) {
    stream.values.sort((left, right) => {
      const leftTime = BigInt(left[0]);
      const rightTime = BigInt(right[0]);
      return leftTime < rightTime ? -1 : leftTime > rightTime ? 1 : left[1].localeCompare(right[1]);
    });
  }

  return [...streams.values()];
}

async function pushToLoki(options, entries) {
  if (entries.length === 0 || options.dryRun) {
    return;
  }

  const streams = groupForLoki(entries);
  const response = await fetch(options.lokiUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ streams }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Loki push failed ${response.status}: ${body.slice(0, 1000)}`);
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const entries = [];
  let offset = null;
  let page = 0;
  let matchedCount = null;
  const firstEventIds = new Set();

  console.log(
    JSON.stringify({
      action: options.dryRun ? "dry-run" : "backfill",
      accountId: options.accountId,
      scripts: options.scriptNames,
      sourceLabel: options.sourceLabel,
      from: new Date(options.from).toISOString(),
      to: new Date(options.to).toISOString(),
      pageLimit: options.limit,
    }),
  );

  while (page < options.maxPages) {
    page += 1;
    const json = await cloudflareRequest(options, queryBody(options, offset));
    const result = json.result?.events || {};
    const events = result.events || [];
    matchedCount = result.count ?? matchedCount;

    if (page === 1) {
      console.log(
        JSON.stringify({
          runStatus: json.result?.run?.status,
          resultKeys: Object.keys(json.result || {}),
          eventResultKeys: Object.keys(result || {}),
          statistics: json.result?.statistics || json.result?.run?.statistics || null,
        }),
      );
    }

    if (events.length === 0) {
      break;
    }

    const firstId = events.at(0)?.$metadata?.id;
    if (firstId && firstEventIds.has(firstId)) {
      console.warn(`Stopping because Cloudflare returned a repeated page at event ${firstId}`);
      break;
    }
    if (firstId) {
      firstEventIds.add(firstId);
    }

    const converted = events.map((event) => eventToLokiEntry(event, options));
    entries.push(...converted);
    offset = events.at(-1)?.$metadata?.id;

    console.log(
      JSON.stringify({
        page,
        returned: events.length,
        accumulated: entries.length,
        matchedCount,
        lastTimestamp: new Date(converted.at(-1)?.timestampMs || options.from).toISOString(),
      }),
    );

    if (!offset || events.length < options.limit) {
      break;
    }
    await sleep(options.pageSleepMs);
  }

  entries.sort((left, right) => {
    const leftTime = BigInt(left.timestamp);
    const rightTime = BigInt(right.timestamp);
    return leftTime < rightTime ? -1 : leftTime > rightTime ? 1 : left.line.localeCompare(right.line);
  });

  const sample = entries.at(0);
  const sampleLine = sample ? JSON.parse(sample.line) : null;
  console.log(
    JSON.stringify({
      matchedCount,
      fetched: entries.length,
      firstFetchedAt: sample ? new Date(sample.timestampMs).toISOString() : null,
      lastFetchedAt: entries.at(-1) ? new Date(entries.at(-1).timestampMs).toISOString() : null,
      sample: sample
        ? {
            scriptName: sample.scriptName,
            labels: sample.labels,
            kind: sampleLine.kind,
            level: sampleLine.level,
            message: sampleLine.message,
            requestMethod: sampleLine.requestMethod,
            requestUrl: sampleLine.requestUrl,
            responseStatus: sampleLine.responseStatus,
          }
        : null,
    }),
  );

  const chunkSize = 100;
  for (let index = 0; index < entries.length; index += chunkSize) {
    const chunk = entries.slice(index, index + chunkSize);
    await pushToLoki(options, chunk);
    if (!options.dryRun) {
      console.log(JSON.stringify({ pushed: chunk.length, totalPushed: Math.min(index + chunk.length, entries.length) }));
    }
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
