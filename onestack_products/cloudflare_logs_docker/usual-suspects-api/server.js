"use strict";

const http = require("node:http");
const { timingSafeEqual } = require("node:crypto");

const port = Number.parseInt(process.env.PORT || "8081", 10);
const apiToken = process.env.API_TOKEN || "";
const lokiBaseUrl = (process.env.LOKI_URL || "http://loki:3100").replace(/\/+$/, "");
const defaultLimit = Number.parseInt(process.env.DEFAULT_LIMIT || "100", 10);
const maxLimit = Number.parseInt(process.env.MAX_LIMIT || "5000", 10);
const baseSelector =
  process.env.LOGQL_SELECTOR ||
  '{source=~"cloudflare-workers|cloudflare-workers-backfill-full",scriptName=~"usual-suspects|usual-suspects-production"}';
const baseLabels = baseSelector.replace(/^\{|\}$/g, "");
// Loki tenant that holds only Usual Suspects logs. Isolation comes from this
// header, so it must name exactly one tenant ("|" would make it multi-tenant).
const lokiTenant = process.env.LOKI_TENANT ?? "usual-suspects";

if (!apiToken) {
  console.error("API_TOKEN is required");
  process.exit(1);
}

if (!/^(?!\.{1,2}$)[A-Za-z0-9_.-]{1,150}$/.test(lokiTenant)) {
  console.error("LOKI_TENANT must be a single Loki tenant ID (letters, digits, '_', '.', '-')");
  process.exit(1);
}

function safeEquals(left, right) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  return leftBuffer.length === rightBuffer.length && timingSafeEqual(leftBuffer, rightBuffer);
}

function isAuthorized(request) {
  return safeEquals(request.headers.authorization || "", `Bearer ${apiToken}`);
}

function sendJson(response, status, body) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(JSON.stringify(body));
}

function parseTimeNs(value, fallbackMs) {
  if (!value) {
    return String(BigInt(fallbackMs) * 1000000n);
  }

  if (/^\d+$/.test(value)) {
    return value.length > 16 ? value : String(BigInt(Number.parseInt(value, 10)) * 1000000n);
  }

  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) {
    throw new Error(`Invalid timestamp: ${value}`);
  }
  return String(BigInt(parsed) * 1000000n);
}

function appendLineFilters(query, searchParams) {
  const grep = searchParams.get("grep");
  if (!grep) {
    return query;
  }

  return `${query} |~ ${JSON.stringify(grep)}`;
}

function materializeDashboardQuery(searchParams) {
  const incomingQuery = searchParams.get("query");
  if (!incomingQuery) {
    return null;
  }

  if (!incomingQuery.includes("__USUAL_SUSPECTS_LABELS__") && !incomingQuery.includes("__USUAL_SUSPECTS_SELECTOR__")) {
    return null;
  }

  // No query text checks here: every request is pinned to lokiTenant, so a
  // query can only ever read the Usual Suspects tenant.
  return incomingQuery
    .replaceAll("__USUAL_SUSPECTS_SELECTOR__", baseSelector)
    .replaceAll("__USUAL_SUSPECTS_LABELS__", baseLabels);
}

function buildSelector(searchParams) {
  const exactLabels = {
    kind: searchParams.get("kind"),
    level: searchParams.get("level"),
    responseStatus: searchParams.get("status"),
  };

  const extra = Object.entries(exactLabels)
    .filter(([, value]) => value)
    .map(([key, value]) => `${key}=${JSON.stringify(value)}`);

  if (extra.length === 0) {
    return baseSelector;
  }

  return baseSelector.replace(/}$/, `,${extra.join(",")}}`);
}

function buildQuery(searchParams) {
  return materializeDashboardQuery(searchParams) || appendLineFilters(buildSelector(searchParams), searchParams);
}

// The tenant header only isolates anything while Loki runs with auth_enabled.
// Loki answers a read without X-Scope-OrgID with 401 "no org id" in that mode,
// so anything else (a stale container with the old config, an outage) fails
// closed. Returns null when enforced, otherwise the reason it is not.
async function tenancyProblem() {
  try {
    const nowNs = String(BigInt(Date.now()) * 1000000n);
    const probe = await fetch(`${lokiBaseUrl}/loki/api/v1/labels?start=${nowNs}&end=${nowNs}`, {
      signal: AbortSignal.timeout(2000),
    });
    const body = await probe.text();
    if (probe.status === 401 && /no org id/i.test(body)) {
      return null;
    }
    return probe.ok
      ? "Loki accepted a read without X-Scope-OrgID (auth_enabled is off)"
      : `Loki tenancy probe returned ${probe.status}`;
  } catch (error) {
    return `Loki tenancy probe failed: ${error.message}`;
  }
}

// Never forwards caller headers: the tenant is always lokiTenant.
async function proxyToLoki(path, params, response) {
  const lokiResponse = await fetch(`${lokiBaseUrl}${path}?${params.toString()}`, {
    headers: { "X-Scope-OrgID": lokiTenant },
  });
  const text = await lokiResponse.text();
  response.writeHead(lokiResponse.status, {
    "content-type": lokiResponse.headers.get("content-type") || "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(text);
}

async function proxyQueryRange(requestUrl, response) {
  const now = Date.now();
  const start = parseTimeNs(requestUrl.searchParams.get("start") || requestUrl.searchParams.get("from"), now - 24 * 60 * 60 * 1000);
  const end = parseTimeNs(requestUrl.searchParams.get("end") || requestUrl.searchParams.get("to"), now);
  const limit = Math.min(Math.max(Number.parseInt(requestUrl.searchParams.get("limit") || String(defaultLimit), 10), 1), maxLimit);
  const direction = requestUrl.searchParams.get("direction") === "forward" ? "forward" : "backward";
  const query = buildQuery(requestUrl.searchParams);

  const params = new URLSearchParams({
    query,
    start,
    end,
    limit: String(limit),
    direction,
  });
  const step = requestUrl.searchParams.get("step");
  if (step) {
    params.set("step", step);
  }

  await proxyToLoki("/loki/api/v1/query_range", params, response);
}

async function proxyQuery(requestUrl, response) {
  const query = buildQuery(requestUrl.searchParams);
  const limit = Math.min(Math.max(Number.parseInt(requestUrl.searchParams.get("limit") || String(defaultLimit), 10), 1), maxLimit);
  const direction = requestUrl.searchParams.get("direction") === "forward" ? "forward" : "backward";

  const params = new URLSearchParams({
    query,
    limit: String(limit),
    direction,
  });
  const time = requestUrl.searchParams.get("time");
  if (time) {
    params.set("time", time);
  }

  await proxyToLoki("/loki/api/v1/query", params, response);
}

const routes = {
  "/usual-suspects-logs/health": "health",
  "/usual-suspects-logs/api/v1/query_range": "query_range",
  "/usual-suspects-logs/loki/api/v1/query_range": "query_range",
  "/usual-suspects-logs/api/v1/query": "query",
  "/usual-suspects-logs/loki/api/v1/query": "query",
};

async function handle(request, response) {
  const requestUrl = new URL(request.url, "http://localhost");

  if (!requestUrl.pathname.startsWith("/usual-suspects-logs")) {
    sendJson(response, 404, { error: "not_found" });
    return;
  }

  if (!isAuthorized(request)) {
    sendJson(response, 401, { error: "unauthorized" });
    return;
  }

  if (request.method !== "GET") {
    sendJson(response, 405, { error: "method_not_allowed" });
    return;
  }

  const route = routes[requestUrl.pathname];
  if (!route) {
    sendJson(response, 404, { error: "not_found" });
    return;
  }

  const problem = await tenancyProblem();

  if (route === "health") {
    sendJson(response, problem ? 503 : 200, {
      ok: !problem,
      tenancyEnforced: !problem,
      ...(problem ? { problem } : {}),
      selector: baseSelector,
      tenant: lokiTenant,
      labelPlaceholder: "__USUAL_SUSPECTS_LABELS__",
      selectorPlaceholder: "__USUAL_SUSPECTS_SELECTOR__",
      defaultLimit,
      maxLimit,
    });
    return;
  }

  if (problem) {
    console.error(`Refusing to proxy: ${problem}`);
    sendJson(response, 503, { error: "loki_tenancy_not_enforced" });
    return;
  }

  if (route === "query_range") {
    await proxyQueryRange(requestUrl, response);
  } else {
    await proxyQuery(requestUrl, response);
  }
}

const server = http.createServer((request, response) => {
  handle(request, response).catch((error) => {
    console.error(error);
    sendJson(response, 400, { error: error.message || "bad_request" });
  });
});

server.listen(port, "0.0.0.0", () => {
  console.log(`usual-suspects logs API listening on ${port}`);
});
