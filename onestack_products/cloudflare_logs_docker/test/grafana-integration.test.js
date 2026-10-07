"use strict";

// Runs configure-usual-suspects-grafana-access.mjs against the pinned Grafana
// and Loki images with the real proxy. Opt in with LOKI_INTEGRATION=1 (needs
// Docker); it is skipped otherwise.

const { test, describe, before, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const { execFileSync, spawn } = require("node:child_process");
const { randomUUID } = require("node:crypto");
const { stackRoot, freePort, startService } = require("./helpers");

const enabled = process.env.LOKI_INTEGRATION === "1";
const run = randomUUID().slice(0, 8);
const apiToken = `integration-api-token-${run}`;
const adminUser = "admin";
const adminPassword = `admin-${run}`;
const uiLogin = "usual-suspects-logs";
const adminAuth = `Basic ${Buffer.from(`${adminUser}:${adminPassword}`).toString("base64")}`;

function composeImage(name) {
  const compose = fs.readFileSync(path.join(stackRoot, "docker-compose.yml"), "utf8");
  return compose.match(new RegExp(`image:\\s*(grafana/${name}@sha256:[0-9a-f]+)`))[1];
}

function docker(...args) {
  return execFileSync("docker", args).toString().trim();
}

function hostPort(containerId, containerPort) {
  return docker("port", containerId, `${containerPort}/tcp`).split("\n")[0].split(":").pop();
}

async function waitFor(check, label) {
  const deadline = Date.now() + 120000;
  while (Date.now() < deadline) {
    try {
      if (await check()) {
        return;
      }
    } catch {
      // Still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`${label} did not become ready`);
}

async function grafana(grafanaUrl, method, apiPath, body, { auth = adminAuth, orgId } = {}) {
  const response = await fetch(`${grafanaUrl}${apiPath}`, {
    method,
    headers: {
      authorization: auth,
      "content-type": "application/json",
      ...(orgId ? { "x-grafana-org-id": String(orgId) } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, json: text ? JSON.parse(text) : null };
}

async function pushLoki(lokiUrl, tenant, scriptName) {
  const response = await fetch(`${lokiUrl}/loki/api/v1/push`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-scope-orgid": tenant },
    body: JSON.stringify({
      streams: [
        {
          stream: { source: "cloudflare-workers", scriptName, kind: "invocation", responseStatus: "200" },
          values: [[String(BigInt(Date.now()) * 1000000n), JSON.stringify({ scriptName })]],
        },
      ],
    }),
  });
  assert.ok(response.ok, `push to ${tenant} failed: ${response.status}`);
}

function runConfigure(env) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [path.join(stackRoot, "scripts/configure-usual-suspects-grafana-access.mjs")], {
      env: { PATH: process.env.PATH, ...env },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("exit", (code) => resolve({ code, stdout, stderr }));
  });
}

// Stands in for a proxy that has lost its tenant pin: it reads every tenant.
async function startLeakyProxy(lokiUrl) {
  const baseLabels =
    'source=~"cloudflare-workers|cloudflare-workers-backfill-full",scriptName=~"usual-suspects|usual-suspects-production"';
  const server = http.createServer(async (request, response) => {
    const url = new URL(request.url, "http://localhost");
    const query = (url.searchParams.get("query") || "").replaceAll("__USUAL_SUSPECTS_LABELS__", baseLabels);
    url.searchParams.set("query", query);
    const upstream = await fetch(`${lokiUrl}${url.pathname.replace(/^\/usual-suspects-logs/, "")}?${url.searchParams}`, {
      headers: { "x-scope-orgid": "usual-suspects|cloudflare-workers" },
    });
    response.writeHead(upstream.status, { "content-type": "application/json" });
    response.end(await upstream.text());
  });
  const port = await freePort();
  await new Promise((resolve) => server.listen(port, "0.0.0.0", resolve));
  return { port, close: () => new Promise((resolve) => server.close(resolve)) };
}

describe("Grafana access configuration (integration)", { skip: !enabled && "set LOKI_INTEGRATION=1 to run" }, () => {
  const network = `cloudflare-logs-test-${run}`;
  let lokiId;
  let grafanaId;
  let lokiUrl;
  let grafanaUrl;
  let api;
  let apiPort;

  before(async () => {
    docker("network", "create", network);
    lokiId = docker(
      "run", "-d", "--rm", "--network", network, "--network-alias", "loki", "-p", "127.0.0.1::3100",
      "-v", `${path.join(stackRoot, "loki/config.yml")}:/etc/loki/config.yml:ro`,
      composeImage("loki"), "-config.file=/etc/loki/config.yml",
    );
    grafanaId = docker(
      "run", "-d", "--rm", "--network", network, "-p", "127.0.0.1::3000",
      "--add-host", "host.docker.internal:host-gateway",
      "-e", `GF_SECURITY_ADMIN_USER=${adminUser}`, "-e", `GF_SECURITY_ADMIN_PASSWORD=${adminPassword}`,
      "-v", `${path.join(stackRoot, "grafana/provisioning")}:/etc/grafana/provisioning:ro`,
      "-v", `${path.join(stackRoot, "grafana/dashboards")}:/var/lib/grafana/dashboards:ro`,
      composeImage("grafana"),
    );
    lokiUrl = `http://127.0.0.1:${hostPort(lokiId, 3100)}`;
    grafanaUrl = `http://127.0.0.1:${hostPort(grafanaId, 3000)}`;

    await waitFor(async () => (await fetch(`${lokiUrl}/ready`)).ok, "Loki");
    await waitFor(async () => (await grafana(grafanaUrl, "GET", "/api/org")).status === 200, "Grafana");

    await pushLoki(lokiUrl, "usual-suspects", "usual-suspects");
    await pushLoki(lokiUrl, "cloudflare-workers", "other-worker");

    api = await startService("usual-suspects-api/server.js", { API_TOKEN: apiToken, LOKI_URL: lokiUrl });
    apiPort = new URL(api.url).port;

    // An existing deployment: the UI user was created in the admin org.
    const created = await grafana(grafanaUrl, "POST", "/api/admin/users", {
      name: "Usual Suspects Logs",
      email: "usual-suspects-logs@onestack.local",
      login: uiLogin,
      password: `old-${run}-password`,
      OrgId: 1,
    });
    assert.equal(created.status, 200);
  });

  after(async () => {
    await api?.stop();
    for (const id of [grafanaId, lokiId]) {
      if (id) {
        execFileSync("docker", ["rm", "-f", id], { stdio: "ignore" });
      }
    }
    execFileSync("docker", ["network", "rm", network], { stdio: "ignore" });
  });

  function configureEnv(port) {
    return {
      GRAFANA_URL: grafanaUrl,
      GRAFANA_ADMIN_USER: adminUser,
      GRAFANA_ADMIN_PASSWORD: adminPassword,
      USUAL_SUSPECTS_LOGS_API_TOKEN: apiToken,
      USUAL_SUSPECTS_API_URL: `http://host.docker.internal:${port}/usual-suspects-logs`,
    };
  }

  test("configuring leaves the UI user only in the Usual Suspects org", async () => {
    const result = await runConfigure(configureEnv(apiPort));
    assert.equal(result.code, 0, result.stderr);
    const output = JSON.parse(result.stdout);

    const user = await grafana(grafanaUrl, "GET", `/api/users/lookup?loginOrEmail=${uiLogin}`);
    const orgs = await grafana(grafanaUrl, "GET", `/api/users/${user.json.id}/orgs`);
    assert.deepEqual(
      orgs.json.map((org) => org.orgId),
      [output.orgId],
    );

    const uiAuth = `Basic ${Buffer.from(`${uiLogin}:${output.ui.password}`).toString("base64")}`;
    const adminDatasource = await grafana(
      grafanaUrl,
      "POST",
      "/api/ds/query",
      { from: "now-1h", to: "now", queries: [{ refId: "A", datasource: { uid: "Loki", type: "loki" }, expr: '{scriptName=~".+"}' }] },
      { auth: uiAuth, orgId: 1 },
    );
    assert.ok(adminDatasource.status >= 400, `UI user could query the admin Loki datasource: ${adminDatasource.status}`);

    assert.deepEqual(output.serviceAccount.verification.scriptLabels, ["usual-suspects"]);
  });

  test("configuring fails when the Usual Suspects datasource can see other scripts", async () => {
    const leaky = await startLeakyProxy(lokiUrl);
    // Grafana caches datasources by UID for a few seconds, so let the URL
    // from the previous run expire before pointing the datasource elsewhere.
    await new Promise((resolve) => setTimeout(resolve, 6000));
    try {
      const result = await runConfigure(configureEnv(leaky.port));
      assert.notEqual(result.code, 0, result.stdout);
      assert.match(result.stderr, /other-worker/);
    } finally {
      await leaky.close();
    }
  });
});
