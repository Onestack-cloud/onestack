"use strict";

const http = require("node:http");
const zlib = require("node:zlib");
const { timingSafeEqual } = require("node:crypto");

const port = Number.parseInt(process.env.PORT || "8080", 10);
const authToken = process.env.AUTH_TOKEN || "";
const lokiUrl = process.env.LOKI_URL || "http://loki:3100/loki/api/v1/push";
const maxBodyBytes = Number.parseInt(process.env.MAX_BODY_BYTES || "25000000", 10);
const allowedScriptNames = new Set(
  (process.env.ALLOWED_SCRIPT_NAMES || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean),
);

if (!authToken) {
  console.error("AUTH_TOKEN is required");
  process.exit(1);
}

const tenantIdPattern = /^[A-Za-z0-9_.-]{1,150}$/;

// Maps exact Worker script names to the Loki tenant (X-Scope-OrgID) their logs
// are written to, e.g. "usual-suspects=usual-suspects". Scripts without a
// route go to the default tenant, which may not be a routed tenant, so an
// unknown or look-alike script can never land in a restricted tenant.
function parseTenantRouting(routesValue, defaultTenant) {
  const routes = new Map();
  for (const route of routesValue.split(",").map((value) => value.trim()).filter(Boolean)) {
    const [scriptName, tenant, ...rest] = route.split("=").map((value) => value.trim());
    if (!scriptName || !tenantIdPattern.test(tenant || "") || rest.length > 0) {
      throw new Error(`LOKI_TENANT_BY_SCRIPT has an invalid route: ${route}`);
    }
    routes.set(scriptName, tenant);
  }
  if (!tenantIdPattern.test(defaultTenant) || [...routes.values()].includes(defaultTenant)) {
    throw new Error("LOKI_DEFAULT_TENANT must be a single Loki tenant ID that no script is routed to");
  }
  return { routes, defaultTenant };
}

let tenantRouting;
try {
  tenantRouting = parseTenantRouting(
    process.env.LOKI_TENANT_BY_SCRIPT || "",
    process.env.LOKI_DEFAULT_TENANT ?? "cloudflare-workers",
  );
} catch (error) {
  console.error(error.message);
  process.exit(1);
}

function tenantForScript(scriptName) {
  return tenantRouting.routes.get(scriptName) ?? tenantRouting.defaultTenant;
}

function safeEquals(left, right) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  return leftBuffer.length === rightBuffer.length && timingSafeEqual(leftBuffer, rightBuffer);
}

function isAuthorized(request) {
  const expected = `Bearer ${authToken}`;
  const actual = request.headers.authorization || "";
  return safeEquals(actual, expected);
}

function collectRequestBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;

    request.on("data", (chunk) => {
      size += chunk.length;
      if (size > maxBodyBytes) {
        request.destroy();
        reject(new Error("request body too large"));
        return;
      }
      chunks.push(chunk);
    });

    request.on("end", () => resolve(Buffer.concat(chunks)));
    request.on("error", reject);
  });
}

function looksGzipped(buffer) {
  return buffer.length >= 2 && buffer[0] === 0x1f && buffer[1] === 0x8b;
}

function decodePayload(buffer, request) {
  const contentEncoding = String(request.headers["content-encoding"] || "").toLowerCase();
  if (contentEncoding.includes("gzip") || looksGzipped(buffer)) {
    return zlib.gunzipSync(buffer).toString("utf8");
  }
  return buffer.toString("utf8");
}

function parsePayload(text) {
  const trimmed = text.trim();
  if (!trimmed) {
    return [];
  }

  if (trimmed.startsWith("[")) {
    const parsed = JSON.parse(trimmed);
    return Array.isArray(parsed) ? parsed : [parsed];
  }

  if (trimmed.startsWith("{") && !trimmed.includes("\n")) {
    return [JSON.parse(trimmed)];
  }

  return trimmed
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function redact(value) {
  if (Array.isArray(value)) {
    return value.map(redact);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => {
        if (/authorization|cookie|password|secret|token|api[-_]?key/i.test(key)) {
          return [key, "[redacted]"];
        }
        return [key, redact(nested)];
      }),
    );
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

function normalizeMessage(message) {
  if (Array.isArray(message)) {
    return message.map((part) => (typeof part === "string" ? part : JSON.stringify(part))).join(" ");
  }
  if (typeof message === "string") {
    return message;
  }
  return JSON.stringify(message);
}

function extractRequestSummary(event) {
  const request = event?.request || event?.Request || {};
  const response = event?.response || event?.Response || {};
  return {
    requestMethod: request.method || request.Method || null,
    requestUrl: request.url || request.URL || null,
    responseStatus: response.status || response.Status || null,
  };
}

function addValue(streamsByTenant, tenant, labels, timestamp, line) {
  if (!streamsByTenant.has(tenant)) {
    streamsByTenant.set(tenant, new Map());
  }
  const streams = streamsByTenant.get(tenant);
  const key = JSON.stringify(labels);
  const existing = streams.get(key);
  if (existing) {
    existing.values.push([timestamp, line]);
    return;
  }
  streams.set(key, { stream: labels, values: [[timestamp, line]] });
}

function shouldAcceptScript(scriptName) {
  return allowedScriptNames.size === 0 || allowedScriptNames.has(scriptName);
}

function convertRecordToStreams(record, streamsByTenant) {
  const scriptName = record.ScriptName || record.scriptName || "unknown";
  if (!shouldAcceptScript(scriptName)) {
    return { accepted: 0, filtered: 1 };
  }

  const tenant = tenantForScript(scriptName);

  const baseLabels = {
    source: "cloudflare-workers",
    scriptName: labelValue(scriptName),
    outcome: labelValue(record.Outcome || record.outcome),
    eventType: labelValue(record.EventType || record.eventType),
    entrypoint: labelValue(record.Entrypoint || record.entrypoint),
  };
  const baseTimestamp = timestampNs(record.EventTimestampMs || record.eventTimestamp);
  const safeRecord = redact(record);
  const safeEvent = safeRecord.Event || safeRecord.event;
  const requestSummary = extractRequestSummary(safeEvent);
  const logs = Array.isArray(record.Logs) ? record.Logs : [];
  const exceptions = Array.isArray(record.Exceptions) ? record.Exceptions : [];
  let accepted = 0;

  const invocationLine = JSON.stringify({
    kind: "invocation",
    scriptName,
    outcome: record.Outcome || record.outcome,
    eventType: record.EventType || record.eventType,
    cpuTimeMs: record.CPUTimeMs,
    wallTimeMs: record.WallTimeMs,
    ...requestSummary,
    event: safeEvent,
    scriptVersion: safeRecord.ScriptVersion,
  });
  addValue(
    streamsByTenant,
    tenant,
    { ...baseLabels, kind: "invocation", responseStatus: labelValue(requestSummary.responseStatus) },
    baseTimestamp,
    invocationLine,
  );
  accepted += 1;

  for (const log of logs) {
    const level = log.level || log.Level || "log";
    const line = JSON.stringify({
      kind: "console",
      level,
      scriptName,
      message: normalizeMessage(log.message || log.Message || ""),
      ...requestSummary,
      log: redact(log),
      event: safeEvent,
    });
    addValue(
      streamsByTenant,
      tenant,
      {
        ...baseLabels,
        kind: "console",
        level: labelValue(level, "log"),
        responseStatus: labelValue(requestSummary.responseStatus),
      },
      timestampNs(log.timestamp || log.Timestamp || record.EventTimestampMs),
      line,
    );
    accepted += 1;
  }

  for (const exception of exceptions) {
    const line = JSON.stringify({
      kind: "exception",
      scriptName,
      ...requestSummary,
      exception: redact(exception),
      event: safeEvent,
    });
    addValue(
      streamsByTenant,
      tenant,
      { ...baseLabels, kind: "exception", level: "error", responseStatus: labelValue(requestSummary.responseStatus) },
      timestampNs(exception.timestamp || exception.Timestamp || record.EventTimestampMs),
      line,
    );
    accepted += 1;
  }

  return { accepted, filtered: 0 };
}

async function pushToLoki(streamsByTenant) {
  for (const [tenant, streams] of streamsByTenant) {
    const response = await fetch(lokiUrl, {
      method: "POST",
      headers: { "content-type": "application/json", "X-Scope-OrgID": tenant },
      body: JSON.stringify({ streams: [...streams.values()] }),
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`loki push failed for tenant ${tenant}: ${response.status} ${body}`);
    }
  }
}

async function handleLogpush(request, response) {
  if (!isAuthorized(request)) {
    response.writeHead(401, { "content-type": "text/plain" });
    response.end("unauthorized\n");
    return;
  }

  const body = await collectRequestBody(request);
  const text = decodePayload(body, request);
  const records = parsePayload(text);
  const streamsByTenant = new Map();
  let accepted = 0;
  let filtered = 0;

  for (const record of records) {
    if (record && record.content === "tests" && Object.keys(record).length === 1) {
      continue;
    }
    const result = convertRecordToStreams(record, streamsByTenant);
    accepted += result.accepted;
    filtered += result.filtered;
  }

  await pushToLoki(streamsByTenant);

  response.writeHead(202, { "content-type": "application/json" });
  response.end(JSON.stringify({ accepted, filtered, records: records.length }) + "\n");
}

const server = http.createServer((request, response) => {
  if (request.method === "GET" && request.url === "/healthz") {
    response.writeHead(200, { "content-type": "text/plain" });
    response.end("ok\n");
    return;
  }

  if (!request.url?.startsWith("/cloudflare-logpush")) {
    response.writeHead(404, { "content-type": "text/plain" });
    response.end("not found\n");
    return;
  }

  if (request.method !== "POST") {
    response.writeHead(405, { "content-type": "text/plain" });
    response.end("method not allowed\n");
    return;
  }

  handleLogpush(request, response).catch((error) => {
    console.error(error);
    const status = /too large|JSON/.test(error.message) ? 400 : 502;
    response.writeHead(status, { "content-type": "text/plain" });
    response.end(`${error.message}\n`);
  });
});

server.listen(port, "0.0.0.0", () => {
  console.log(`cloudflare log ingest listening on ${port}`);
});
