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
  if (adminPatched.ok) {
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
  // A server admin can add itself back to any org.
  await must("PUT", `/api/admin/users/${userId}/permissions`, { isGrafanaAdmin: false });

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
  const role = orgs.find((org) => org.orgId === orgId).role;
  if (role !== "Viewer") {
    throw new Error(`UI user must be a Viewer in org ${orgId}, not ${role}`);
  }
}

// Any other datasource in the org could bypass the tenant-pinned proxy.
export function assertOnlyExpectedDatasources(datasources) {
  const unexpected = datasources.filter((datasource) => datasource.uid !== datasourceUid);
  if (unexpected.length > 0) {
    throw new Error(
      `Usual Suspects org has unexpected datasources: ${unexpected.map((datasource) => `${datasource.name} (${datasource.uid})`).join(", ")}`,
    );
  }
}

// The admin who created the org stays a member (matched by id, since the
// configured admin name may be a login or an email); the UI user must be a
// Viewer.
export function assertOnlyExpectedMembers(members, adminUserId) {
  for (const member of members) {
    if (member.userId === adminUserId) {
      continue;
    }
    if (member.login !== userLogin) {
      throw new Error(`Usual Suspects org has an unexpected member: ${member.login} (${member.role})`);
    }
    if (member.role !== "Viewer") {
      throw new Error(`UI user must be a Viewer in the Usual Suspects org, not ${member.role}`);
    }
  }
}

// A service account above Viewer could add a datasource that bypasses the proxy.
export function assertServiceAccountsAreViewers(accounts) {
  const elevated = accounts.filter((account) => account.role !== "Viewer");
  if (elevated.length > 0) {
    throw new Error(
      `Usual Suspects org has service accounts above Viewer: ${elevated.map((account) => `${account.name} (${account.role})`).join(", ")}`,
    );
  }
}

async function auditOrg(orgId) {
  assertOnlyExpectedDatasources(await must("GET", "/api/datasources", undefined, { orgId }));
  const admin = await must("GET", "/api/user");
  assertOnlyExpectedMembers(await must("GET", "/api/org/users", undefined, { orgId }), admin.id);
  const accounts = await must("GET", "/api/serviceaccounts/search?perpage=1000", undefined, { orgId });
  if ((accounts.serviceAccounts || []).length < (accounts.totalCount ?? 0)) {
    throw new Error(`Usual Suspects org has more service accounts (${accounts.totalCount}) than one page; audit them by hand`);
  }
  assertServiceAccountsAreViewers(accounts.serviceAccounts || []);

  const uiUser = await request("GET", `/api/users/lookup?loginOrEmail=${encodeURIComponent(userLogin)}`);
  if (uiUser.ok) {
    assertOnlyMemberOf(await must("GET", `/api/users/${uiUser.json.id}/orgs`), orgId);
    if (uiUser.json.isGrafanaAdmin) {
      throw new Error("UI user is a Grafana server admin");
    }
  } else if (uiUser.status !== 404) {
    throw new Error(`UI user lookup failed: ${uiUser.status}`);
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
    // A higher role could add a datasource that bypasses the proxy.
    if (existing.role !== "Viewer") {
      await must("PATCH", `/api/serviceaccounts/${existing.id}`, { role: "Viewer" }, { orgId });
    }
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
  return { id: created.id, key: created.key };
}

async function deleteServiceAccountToken(orgId, serviceAccountId, tokenId) {
  await must("DELETE", `/api/serviceaccounts/${serviceAccountId}/tokens/${tokenId}`, undefined, { orgId });
}

// Grafana caches datasources by UID for about five seconds, so a check run
// straight after updating the datasource can still go to the old URL.
function waitForDatasourceCache() {
  return new Promise((resolve) => setTimeout(resolve, 6000));
}

async function verifyUiUser(orgId, userId, password) {
  const userAuth = `Basic ${Buffer.from(`${userLogin}:${password}`).toString("base64")}`;
  const search = await must("GET", "/api/search?query=Usual", undefined, { auth: userAuth, orgId });
  assertOnlyMemberOf(await must("GET", "/api/user/orgs", undefined, { auth: userAuth }), orgId);
  if ((await must("GET", `/api/users/${userId}`)).isGrafanaAdmin) {
    throw new Error("UI user is a Grafana server admin");
  }

  // The admin must be able to run the query, so the UI user's 403 is a real
  // denial rather than a missing or renamed datasource.
  const adminDatasourceBody = {
    from: "now-1h",
    to: "now",
    queries: [{ refId: "A", datasource: { uid: adminDatasourceUid, type: "loki" }, expr: '{scriptName=~".+"}' }],
  };
  const asAdmin = await request("POST", "/api/ds/query", adminDatasourceBody, { orgId: adminOrgId });
  if (!asAdmin.ok) {
    throw new Error(`admin cannot query the "${adminDatasourceUid}" datasource in org ${adminOrgId}: ${asAdmin.status}`);
  }
  const adminDatasourceQuery = await request("POST", "/api/ds/query", adminDatasourceBody, {
    auth: userAuth,
    orgId: adminOrgId,
  });
  if (adminDatasourceQuery.status !== 403) {
    throw new Error(`UI user query to the admin Loki datasource returned ${adminDatasourceQuery.status}, expected 403`);
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
  if (!query.ok || query.json?.results?.A?.error) {
    throw new Error(`UI user cannot query the Usual Suspects datasource: ${query.status} ${query.json?.results?.A?.error || ""}`);
  }
  return { dashboardCount: search.length, queryStatus: query.status, adminDatasourceStatus: adminDatasourceQuery.status };
}

// Queries the Usual Suspects datasource as `auth` for every script name. The
// same query through the admin datasource shows whether other scripts have
// logs in the window at all; without any, the check cannot prove isolation
// and is reported as inconclusive rather than passed.
async function verifyDatasourceIsolation(orgId, auth) {
  const nowNs = BigInt(Date.now()) * 1000000n;
  const window = {
    start: String(nowNs - 24n * 3600n * 1000000000n),
    end: String(nowNs),
    step: "3600",
  };
  const everyScript = await must(
    "GET",
    `/api/datasources/proxy/uid/${adminDatasourceUid}/loki/api/v1/query_range?${new URLSearchParams({
      ...window,
      query: 'sum by (scriptName) (count_over_time({scriptName=~".+"}[1h]))',
    })}`,
    undefined,
    { orgId: adminOrgId },
  );
  const foreignScriptsInWindow = scriptLabelsFrom(everyScript).filter((name) => !usualSuspectsScripts.includes(name));

  const proxied = await must(
    "GET",
    `/api/datasources/proxy/uid/${datasourceUid}/loki/api/v1/query_range?${new URLSearchParams({
      ...window,
      query: serviceTokenProbeQuery,
    })}`,
    undefined,
    { auth, orgId },
  );
  const scriptLabels = scriptLabelsFrom(proxied);
  assertOnlyUsualSuspectsScripts(scriptLabels);
  return {
    series: proxied.data?.result?.length || 0,
    scriptLabels,
    foreignScriptsInWindow,
    conclusive: foreignScriptsInWindow.length > 0,
  };
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
    await auditOrg(orgId);
    await waitForDatasourceCache();
    // Grafana replaces the caller's Authorization with the datasource's own
    // header, so this checks the datasource exactly as the client uses it.
    const verification = await verifyDatasourceIsolation(orgId, adminAuth);
    console.log(
      JSON.stringify(
        {
          orgId,
          orgName,
          verification,
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
  // Audit before minting a token, so a bad org never has a new token at all.
  await auditOrg(orgId);
  const serviceAccountToken = await createServiceAccountToken(orgId, serviceAccountId);
  let uiVerification;
  let serviceVerification;
  try {
    await waitForDatasourceCache();
    uiVerification = await verifyUiUser(orgId, user.id, uiPassword);
    serviceVerification = await verifyDatasourceIsolation(orgId, `Bearer ${serviceAccountToken.key}`);
  } catch (error) {
    // Never leave a valid token behind that nobody was given. The rotated UI
    // password is not printed either, so the client stays locked out until
    // the problem is fixed and the script is run again.
    await deleteServiceAccountToken(orgId, serviceAccountId, serviceAccountToken.id).catch((deleteError) => {
      console.error(`Could not delete the unused service account token ${serviceAccountToken.id}: ${deleteError.message}`);
    });
    throw error;
  }

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
          token: serviceAccountToken.key,
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
  if (!process.argv[1] || process.argv[1] === "-") {
    console.error("Run this script by path, e.g. node scripts/configure-usual-suspects-grafana-access.mjs");
    process.exit(1);
  }
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
