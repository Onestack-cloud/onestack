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

if (!apiToken) {
  console.error("API_TOKEN is required");
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

function compactQuery(value) {
  return value.replace(/\s+/g, "");
}

function extractLogqlSelectors(query) {
  const selectors = [];
  let inString = false;
  let escaped = false;
  let selectorStart = -1;

  for (let index = 0; index < query.length; index += 1) {
    const character = query[index];

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === "\"") {
        inString = false;
      }
      continue;
    }

    if (character === "\"") {
      inString = true;
    } else if (character === "{" && selectorStart === -1) {
      selectorStart = index + 1;
    } else if (character === "}" && selectorStart !== -1) {
      selectors.push(query.slice(selectorStart, index));
      selectorStart = -1;
    }
  }

  return selectors;
}

function materializeDashboardQuery(searchParams) {
  const incomingQuery = searchParams.get("query");
  if (!incomingQuery) {
    return null;
  }

  if (!incomingQuery.includes("__USUAL_SUSPECTS_LABELS__") && !incomingQuery.includes("__USUAL_SUSPECTS_SELECTOR__")) {
    return null;
  }

  const query = incomingQuery
    .replaceAll("__USUAL_SUSPECTS_SELECTOR__", baseSelector)
    .replaceAll("__USUAL_SUSPECTS_LABELS__", baseLabels);

  const compactBaseLabels = compactQuery(baseLabels);
  const selectors = extractLogqlSelectors(query).map(compactQuery);
  if (selectors.length === 0 || selectors.some((selector) => !selector.includes(compactBaseLabels))) {
    throw new Error("query must use only the Usual Suspects log selector");
  }

  return query;
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

  const lokiResponse = await fetch(`${lokiBaseUrl}/loki/api/v1/query_range?${params.toString()}`);
  const text = await lokiResponse.text();
  response.writeHead(lokiResponse.status, {
    "content-type": lokiResponse.headers.get("content-type") || "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(text);
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

  const lokiResponse = await fetch(`${lokiBaseUrl}/loki/api/v1/query?${params.toString()}`);
  const text = await lokiResponse.text();
  response.writeHead(lokiResponse.status, {
    "content-type": lokiResponse.headers.get("content-type") || "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(text);
}

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

  if (requestUrl.pathname === "/usual-suspects-logs/health") {
    sendJson(response, 200, {
      ok: true,
      selector: baseSelector,
      labelPlaceholder: "__USUAL_SUSPECTS_LABELS__",
      selectorPlaceholder: "__USUAL_SUSPECTS_SELECTOR__",
      defaultLimit,
      maxLimit,
    });
    return;
  }

  if (
    requestUrl.pathname === "/usual-suspects-logs/api/v1/query_range" ||
    requestUrl.pathname === "/usual-suspects-logs/loki/api/v1/query_range"
  ) {
    await proxyQueryRange(requestUrl, response);
    return;
  }

  if (
    requestUrl.pathname === "/usual-suspects-logs/api/v1/query" ||
    requestUrl.pathname === "/usual-suspects-logs/loki/api/v1/query"
  ) {
    await proxyQuery(requestUrl, response);
    return;
  }

  sendJson(response, 404, { error: "not_found" });
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
