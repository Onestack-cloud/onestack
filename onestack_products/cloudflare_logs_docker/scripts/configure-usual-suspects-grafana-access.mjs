#!/usr/bin/env node

import crypto from "node:crypto";
import { realpathSync } from "node:fs";
import { pathToFileURL } from "node:url";

const baseUrl = process.env.GRAFANA_URL || "http://grafana:3000";
const adminUser = process.env.GRAFANA_ADMIN_USER;
const adminPassword = process.env.GRAFANA_ADMIN_PASSWORD;
const filteredApiToken = process.env.USUAL_SUSPECTS_LOGS_API_TOKEN;
const usualSuspectsApiUrl = process.env.USUAL_SUSPECTS_API_URL || "http://usual-suspects-api:8081/usual-suspects-logs";

const orgName = "Usual Suspects Logs";
const orgSlug = "usual-suspects-logs";
const userLogin = "usual-suspects-logs";
const userEmail = "usual-suspects-logs@onestack.local";
const userName = "Usual Suspects Logs";
const serviceAccountName = "usual-suspects-logs-api";
const datasourceUid = "usual-suspects-loki";
const folderUid = "usual-suspects-logs";
const dashboardUid = "usual-suspects-worker-logs";
const selectorLabels = "__USUAL_SUSPECTS_LABELS__";
const selector = `{${selectorLabels},kind=~"$kind",responseStatus=~"$status"} |~ "$search"`;
// Grafana's default org, whose provisioned "Loki" datasource reads every tenant.
const adminOrgId = 1;
const adminDatasourceUid = "Loki";
const usualSuspectsScripts = ["usual-suspects", "usual-suspects-production"];
// Asks for every script name. The proxy pins the Loki tenant, so only Usual
// Suspects scripts may come back; anything else means isolation is broken.
export const serviceTokenProbeQuery = `sum by (scriptName) (count_over_time({${selectorLabels}}[1h])) or sum by (scriptName) (count_over_time({scriptName=~".+"}[1h]))`;

const adminAuth = `Basic ${Buffer.from(`${adminUser}:${adminPassword}`).toString("base64")}`;

function authHeaders(auth, orgId) {
  return {
    authorization: auth,
    "content-type": "application/json",
    ...(orgId ? { "x-grafana-org-id": String(orgId) } : {}),
  };
}

async function request(method, path, body, { auth = adminAuth, orgId } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: authHeaders(auth, orgId),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = text;
  }
  return { ok: response.ok, status: response.status, json, text };
}

async function must(method, path, body, options) {
  const response = await request(method, path, body, options);
  if (!response.ok) {
    throw new Error(`${method} ${path} failed: ${response.status} ${response.text}`);
  }
  return response.json;
}

async function findOrCreateOrg() {
  const existing = await request("GET", `/api/orgs/name/${encodeURIComponent(orgName)}`);
  if (existing.ok) {
    return existing.json.id;
  }
  if (existing.status !== 404) {
    throw new Error(`org lookup failed: ${existing.status} ${existing.text}`);
  }
  const created = await must("POST", "/api/orgs", { name: orgName });
  return created.orgId;
}

async function findOrCreateUser(password, orgId) {
  const existing = await request("GET", `/api/users/lookup?loginOrEmail=${encodeURIComponent(userLogin)}`);
  if (existing.ok) {
    await must("PUT", `/api/admin/users/${existing.json.id}/password`, { password });
    return { id: existing.json.id, created: false };
  }
  if (existing.status !== 404) {
    throw new Error(`user lookup failed: ${existing.status} ${existing.text}`);
  }
  const created = await must("POST", "/api/admin/users", {
    name: userName,
    email: userEmail,
    login: userLogin,
    password,
    OrgId: orgId,
  });
  return { id: created.id, created: true };
}

async function setOrgRole(userId, orgId, role) {
  const patched = await request("PATCH", `/api/org/users/${userId}`, { role }, { orgId });
  if (patched.ok) {
    return;
  }

  const adminPatched = await request("PATCH", `/api/orgs/${orgId}/users/${userId}`, { role });
  if (adminPatched.ok || adminPatched.status === 404) {
    return;
  }

  throw new Error(`set role failed for org ${orgId}: ${patched.status} ${patched.text}; ${adminPatched.status} ${adminPatched.text}`);
}

async function addUserToOrg(userId, orgId) {
  const added = await request("POST", `/api/orgs/${orgId}/users`, {
    loginOrEmail: userLogin,
    role: "Viewer",
  });
  if (!added.ok && added.status !== 409) {
    throw new Error(`add user to org failed: ${added.status} ${added.text}`);
  }
  await setOrgRole(userId, orgId, "Viewer");
  await request("POST", `/api/users/${userId}/using/${orgId}`);

  // Older runs created the user in the admin org with role None. Membership
  // anywhere else is removed outright rather than relying on a role.
  const memberships = await must("GET", `/api/users/${userId}/orgs`);
  for (const membership of memberships) {
    if (membership.orgId !== orgId) {
      await must("DELETE", `/api/orgs/${membership.orgId}/users/${userId}`);
    }
  }
}

export function assertOnlyMemberOf(orgs, orgId) {
  if (!orgs.some((org) => org.orgId === orgId)) {
    throw new Error(`UI user is not a member of org ${orgId}`);
  }
  const others = orgs.filter((org) => org.orgId !== orgId);
  if (others.length > 0) {
    throw new Error(`UI user is still a member of other orgs: ${others.map((org) => `${org.name} (${org.orgId})`).join(", ")}`);
  }
}

export function scriptLabelsFrom(proxied) {
  const series = proxied?.data?.result || [];
  return [...new Set(series.map((item) => (item.stream || item.metric)?.scriptName).filter(Boolean))];
}

export function assertOnlyUsualSuspectsScripts(scriptLabels) {
  const foreign = scriptLabels.filter((name) => !usualSuspectsScripts.includes(name));
  if (foreign.length > 0) {
    throw new Error(`Usual Suspects datasource can read other scripts: ${foreign.join(", ")}`);
  }
}

async function upsertDatasource(orgId) {
  const payload = {
    name: "Usual Suspects Loki",
    uid: datasourceUid,
    type: "loki",
    access: "proxy",
    url: usualSuspectsApiUrl,
    isDefault: true,
    editable: false,
    jsonData: {
      httpHeaderName1: "Authorization",
      maxLines: 1000,
    },
    secureJsonData: {
      httpHeaderValue1: `Bearer ${filteredApiToken}`,
    },
  };

  const existing = await request("GET", `/api/datasources/uid/${datasourceUid}`, undefined, { orgId });
  if (existing.ok) {
    await must("PUT", `/api/datasources/uid/${datasourceUid}`, payload, { orgId });
  } else if (existing.status === 404) {
    await must("POST", "/api/datasources", payload, { orgId });
  } else {
    throw new Error(`datasource lookup failed: ${existing.status} ${existing.text}`);
  }
}

async function upsertFolder(orgId) {
  const existing = await request("GET", `/api/folders/${folderUid}`, undefined, { orgId });
  if (existing.ok) {
    return;
  }
  if (existing.status !== 404) {
    throw new Error(`folder lookup failed: ${existing.status} ${existing.text}`);
  }
  await must("POST", "/api/folders", { uid: folderUid, title: "Usual Suspects" }, { orgId });
}

function datasourceRef() {
  return { type: "loki", uid: datasourceUid };
}

function target(refId, expr, extra = {}) {
  return {
    refId,
    datasource: datasourceRef(),
    expr,
    queryType: "range",
    ...extra,
  };
}

function statPanel(id, title, expr, gridPos, options = {}) {
  return {
    id,
    title,
    type: "stat",
    datasource: datasourceRef(),
    gridPos,
    fieldConfig: {
      defaults: {
        unit: options.unit || "short",
        decimals: options.decimals ?? 0,
        color: { mode: "thresholds" },
        thresholds: {
          mode: "absolute",
          steps: [
            { color: options.baseColor || "green", value: null },
            ...(options.warningAt ? [{ color: "yellow", value: options.warningAt }] : []),
            ...(options.dangerAt ? [{ color: "red", value: options.dangerAt }] : []),
          ],
        },
      },
      overrides: [],
    },
    options: {
      colorMode: "value",
      graphMode: "area",
      justifyMode: "auto",
      orientation: "auto",
      reduceOptions: { calcs: ["lastNotNull"], fields: "", values: false },
      textMode: "auto",
      wideLayout: true,
    },
    targets: [target("A", expr)],
  };
}

function timeSeriesPanel(id, title, expr, gridPos) {
  return {
    id,
    title,
    type: "timeseries",
    datasource: datasourceRef(),
    gridPos,
    fieldConfig: {
      defaults: {
        color: { mode: "palette-classic" },
        custom: {
          drawStyle: "line",
          fillOpacity: 12,
          lineInterpolation: "smooth",
          lineWidth: 1,
          pointSize: 4,
          showPoints: "never",
          spanNulls: true,
        },
        unit: "short",
      },
      overrides: [],
    },
    options: {
      legend: { calcs: ["lastNotNull"], displayMode: "list", placement: "bottom", showLegend: true },
      tooltip: { mode: "multi", sort: "desc" },
    },
    targets: [target("A", expr)],
  };
}

function logsPanel(id, title, expr, gridPos, maxLines = 100) {
  return {
    id,
    title,
    type: "logs",
    datasource: datasourceRef(),
    gridPos,
    options: {
      showTime: true,
      showLabels: false,
      showCommonLabels: false,
      wrapLogMessage: true,
      prettifyLogMessage: true,
      enableLogDetails: true,
    },
    targets: [target("A", expr, { maxLines })],
  };
}

function dashboardVariables() {
  return {
    list: [
      {
        name: "kind",
        label: "Kind",
        type: "custom",
        query: "All : .*, Invocation : invocation, Console : console, Exception : exception, Event : event",
        current: { selected: true, text: "All", value: ".*" },
        options: [
          { selected: true, text: "All", value: ".*" },
          { selected: false, text: "Invocation", value: "invocation" },
          { selected: false, text: "Console", value: "console" },
          { selected: false, text: "Exception", value: "exception" },
          { selected: false, text: "Event", value: "event" },
        ],
      },
      {
        name: "status",
        label: "Status",
        type: "custom",
        query: "All : .*, 2xx : 2.., 3xx : 3.., 4xx : 4.., 5xx : 5.., Unknown : unknown",
        current: { selected: true, text: "All", value: ".*" },
        options: [
          { selected: true, text: "All", value: ".*" },
          { selected: false, text: "2xx", value: "2.." },
          { selected: false, text: "3xx", value: "3.." },
          { selected: false, text: "4xx", value: "4.." },
          { selected: false, text: "5xx", value: "5.." },
          { selected: false, text: "Unknown", value: "unknown" },
        ],
      },
      {
        name: "search",
        label: "Search regex",
        type: "textbox",
        query: ".*",
        current: { selected: false, text: ".*", value: ".*" },
      },
    ],
  };
}

function dashboardDefinition() {
  const filteredLogs = `{${selectorLabels},kind=~"$kind",responseStatus=~"$status"} |~ "$search"`;
  const invocations = `{${selectorLabels},kind="invocation",responseStatus=~"$status"} |~ "$search"`;
  const non2xx = `{${selectorLabels},responseStatus!~"2.."} |~ "$search"`;
  const slowRequests = `{${selectorLabels},kind="invocation"} |~ "\\"wallTimeMs\\":[1-9][0-9]{3,}" |~ "$search"`;

  return {
    uid: dashboardUid,
    title: "Usual Suspects Worker Logs",
    schemaVersion: 41,
    version: 1,
    refresh: "30s",
    timezone: "browser",
    tags: ["cloudflare", "usual-suspects"],
    time: { from: "now-24h", to: "now" },
    templating: dashboardVariables(),
    panels: [
      statPanel(1, "Events", `sum(count_over_time(${filteredLogs} [$__range]))`, { h: 4, w: 6, x: 0, y: 0 }),
      statPanel(
        2,
        "Errors / 5xx",
        `(sum(count_over_time({${selectorLabels},kind="exception"} |~ "$search" [$__range])) or vector(0)) + (sum(count_over_time({${selectorLabels},responseStatus=~"5.."} |~ "$search" [$__range])) or vector(0))`,
        { h: 4, w: 6, x: 6, y: 0 },
        { baseColor: "green", warningAt: 1, dangerAt: 5 },
      ),
      statPanel(
        3,
        "4xx",
        `sum(count_over_time({${selectorLabels},responseStatus=~"4.."} |~ "$search" [$__range])) or vector(0)`,
        { h: 4, w: 6, x: 12, y: 0 },
        { baseColor: "green", warningAt: 1, dangerAt: 20 },
      ),
      statPanel(
        4,
        "Slow >1s",
        `sum(count_over_time(${slowRequests} [$__range])) or vector(0)`,
        { h: 4, w: 6, x: 18, y: 0 },
        { baseColor: "green", warningAt: 1, dangerAt: 10 },
      ),
      timeSeriesPanel(
        5,
        "Events by kind",
        `sum by (kind)(count_over_time(${filteredLogs} [$__interval]))`,
        { h: 7, w: 12, x: 0, y: 4 },
      ),
      timeSeriesPanel(
        6,
        "Responses by status",
        `sum by (responseStatus)(count_over_time(${filteredLogs} [$__interval]))`,
        { h: 7, w: 12, x: 12, y: 4 },
      ),
      logsPanel(7, "Errors and non-2xx", non2xx, { h: 8, w: 24, x: 0, y: 11 }, 100),
      logsPanel(8, "Recent invocations", invocations, { h: 8, w: 24, x: 0, y: 19 }, 100),
      logsPanel(9, "Raw logs", filteredLogs, { h: 12, w: 24, x: 0, y: 27 }, 200),
    ],
  };
}

async function upsertDashboard(orgId) {
  await must(
    "POST",
    "/api/dashboards/db",
    {
      dashboard: dashboardDefinition(),
      folderUid,
      overwrite: true,
      message: "Provision Usual Suspects restricted logs dashboard",
    },
    { orgId },
  );
}

async function findOrCreateServiceAccount(orgId) {
  const search = await must(
    "GET",
    `/api/serviceaccounts/search?query=${encodeURIComponent(serviceAccountName)}`,
    undefined,
    { orgId },
  );
  const existing = (search.serviceAccounts || []).find((account) => account.name === serviceAccountName);
  if (existing) {
    return existing.id;
  }

  const created = await must(
    "POST",
    "/api/serviceaccounts",
    { name: serviceAccountName, role: "Viewer" },
    { orgId },
  );
  return created.id;
}

async function createServiceAccountToken(orgId, serviceAccountId) {
  const created = await must(
    "POST",
    `/api/serviceaccounts/${serviceAccountId}/tokens`,
    { name: `usual-suspects-logs-${new Date().toISOString()}` },
    { orgId },
  );
  return created.key;
}

async function verifyUiUser(orgId, password) {
  const userAuth = `Basic ${Buffer.from(`${userLogin}:${password}`).toString("base64")}`;
  const search = await must("GET", "/api/search?query=Usual", undefined, { auth: userAuth, orgId });
  assertOnlyMemberOf(await must("GET", "/api/user/orgs", undefined, { auth: userAuth }), orgId);
  const adminDatasourceQuery = await request(
    "POST",
    "/api/ds/query",
    {
      from: "now-1h",
      to: "now",
      queries: [{ refId: "A", datasource: { uid: adminDatasourceUid, type: "loki" }, expr: '{scriptName=~".+"}' }],
    },
    { auth: userAuth, orgId: adminOrgId },
  );
  if (adminDatasourceQuery.ok) {
    throw new Error("UI user can query the admin Loki datasource");
  }
  const now = Date.now();
  const query = await request(
    "POST",
    "/api/ds/query",
    {
      from: String(now - 60 * 60 * 1000),
      to: String(now),
      queries: [
        {
          refId: "A",
          datasource: { uid: datasourceUid, type: "loki" },
          expr: selector,
          queryType: "range",
          maxLines: 5,
          intervalMs: 1000,
          maxDataPoints: 1000,
        },
      ],
    },
    { auth: userAuth, orgId },
  );
  return { dashboardCount: search.length, queryStatus: query.status, adminDatasourceStatus: adminDatasourceQuery.status };
}

async function verifyServiceToken(orgId, token) {
  const auth = `Bearer ${token}`;
  const params = new URLSearchParams({
    from: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
    to: new Date().toISOString(),
    step: "3600",
    query: serviceTokenProbeQuery,
  });
  const proxied = await must(
    "GET",
    `/api/datasources/proxy/uid/${datasourceUid}/loki/api/v1/query_range?${params.toString()}`,
    undefined,
    { auth, orgId },
  );
  const scriptLabels = scriptLabelsFrom(proxied);
  assertOnlyUsualSuspectsScripts(scriptLabels);
  return { series: proxied.data?.result?.length || 0, scriptLabels };
}

async function main() {
  if (!adminUser || !adminPassword || !filteredApiToken) {
    throw new Error("GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD and USUAL_SUSPECTS_LOGS_API_TOKEN are required");
  }

  const orgId = await findOrCreateOrg();
  if (process.argv.includes("--dashboard-only")) {
    await upsertDatasource(orgId);
    await upsertFolder(orgId);
    await upsertDashboard(orgId);
    console.log(
      JSON.stringify(
        {
          orgId,
          orgName,
          dashboardUrl: `https://logs.onestack.cloud/d/${dashboardUid}/usual-suspects-worker-logs?orgId=${orgId}`,
        },
        null,
        2,
      ),
    );
    return;
  }

  const uiPassword = crypto.randomBytes(18).toString("base64url");
  const user = await findOrCreateUser(uiPassword, orgId);
  await addUserToOrg(user.id, orgId);
  await upsertDatasource(orgId);
  await upsertFolder(orgId);
  await upsertDashboard(orgId);
  const serviceAccountId = await findOrCreateServiceAccount(orgId);
  const serviceAccountToken = await createServiceAccountToken(orgId, serviceAccountId);
  const uiVerification = await verifyUiUser(orgId, uiPassword);
  const serviceVerification = await verifyServiceToken(orgId, serviceAccountToken);

  console.log(
    JSON.stringify(
      {
        orgId,
        orgName,
        ui: {
          login: userLogin,
          email: userEmail,
          password: uiPassword,
          dashboardUrl: `https://logs.onestack.cloud/d/${dashboardUid}/usual-suspects-worker-logs?orgId=${orgId}`,
          verification: uiVerification,
        },
        serviceAccount: {
          name: serviceAccountName,
          token: serviceAccountToken,
          grafanaProxyQueryRangeUrl: `https://logs.onestack.cloud/api/datasources/proxy/uid/${datasourceUid}/loki/api/v1/query_range?orgId=${orgId}`,
          directFilteredQueryRangeUrl: "https://logs.onestack.cloud/usual-suspects-logs/api/v1/query_range",
          verification: serviceVerification,
        },
      },
      null,
      2,
    ),
  );
}

function isEntryPoint() {
  try {
    return Boolean(process.argv[1]) && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href;
  } catch {
    return false;
  }
}

if (isEntryPoint()) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
