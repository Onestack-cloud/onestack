"use strict";

const http = require("node:http");
const net = require("node:net");
const path = require("node:path");
const { spawn } = require("node:child_process");

const stackRoot = path.resolve(__dirname, "..");

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

// Records every request so tests can assert on what the services send to Loki.
async function startFakeLoki() {
  const requests = [];
  const server = http.createServer((request, response) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => {
      requests.push({
        method: request.method,
        url: new URL(request.url, "http://localhost"),
        headers: request.headers,
        body: Buffer.concat(chunks).toString("utf8"),
      });
      response.writeHead(request.method === "POST" ? 204 : 200, { "content-type": "application/json" });
      response.end(request.method === "POST" ? "" : JSON.stringify({ status: "success", data: { result: [] } }));
    });
  });
  const port = await freePort();
  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
  return {
    url: `http://127.0.0.1:${port}`,
    requests,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

// Starts a service script and resolves once it logs that it is listening.
async function startService(relativeScript, env) {
  const port = await freePort();
  const child = spawn(process.execPath, [path.join(stackRoot, relativeScript)], {
    env: { PATH: process.env.PATH, ...env, PORT: String(port) },
    stdio: ["ignore", "pipe", "pipe"],
  });

  let output = "";
  await new Promise((resolve, reject) => {
    const onData = (chunk) => {
      output += chunk.toString();
      if (/listening on/.test(output)) {
        resolve();
      }
    };
    child.stdout.on("data", onData);
    child.stderr.on("data", (chunk) => {
      output += chunk.toString();
    });
    child.on("exit", (code) => reject(new Error(`${relativeScript} exited with ${code}: ${output}`)));
  });

  return {
    url: `http://127.0.0.1:${port}`,
    stop: () =>
      new Promise((resolve) => {
        child.removeAllListeners("exit");
        child.on("exit", resolve);
        child.kill();
      }),
  };
}

// Runs a service script that is expected to refuse to start.
function runToExit(relativeScript, env) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [path.join(stackRoot, relativeScript)], {
      env: { PATH: process.env.PATH, ...env, PORT: "0" },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    child.stdout.on("data", (chunk) => {
      output += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      output += chunk.toString();
    });
    const timer = setTimeout(() => child.kill(), 3000);
    child.on("exit", (code, signal) => {
      clearTimeout(timer);
      resolve({ code, signal, output });
    });
  });
}

// LogQL that the old hand-rolled selector check let through, or that tries to
// read streams outside the Usual Suspects Worker logs. With tenant isolation
// none of these may reach data outside the Usual Suspects tenant.
const BASE_LABELS = "__USUAL_SUSPECTS_LABELS__";
const bypassQueries = {
  "backtick string desynchronises the quote tracker":
    `sum(count_over_time({${BASE_LABELS}} |= \`"\` [1h])) or sum by (scriptName) (count_over_time({scriptName=~".+"} |= \`"\` [1h]))`,
  "base labels smuggled into a backtick value of a wide selector":
    '{scriptName=~".+", note!=`source=~"cloudflare-workers|cloudflare-workers-backfill-full",scriptName=~"usual-suspects|usual-suspects-production"`}',
  "base selector widened with an extra regex matcher": `{${BASE_LABELS}, job=~".*"}`,
  "second selector hidden inside a string literal":
    `sum(count_over_time({${BASE_LABELS}} |= "{" [1h])) or sum by (scriptName) (count_over_time({scriptName=~".+"} |= \`}\` [1h]))`,
  "or across selectors": `sum(count_over_time({${BASE_LABELS}}[1h])) or sum by (scriptName) (count_over_time({scriptName=~".+"}[1h]))`,
  "binary operation across selectors": `sum(count_over_time({${BASE_LABELS}}[1h])) + on() group_left sum(count_over_time({scriptName!=""}[1h]))`,
  "unicode quotes around a wide matcher": `{${BASE_LABELS}} or {scriptName=~“.+”}`,
  "line content promoted into a label from a foreign stream":
    `sum by (msg) (count_over_time({${BASE_LABELS}} or {scriptName=~".+"} | json | label_format msg="{{.message}}" [1h]))`,
};

module.exports = { stackRoot, freePort, startFakeLoki, startService, runToExit, bypassQueries };
