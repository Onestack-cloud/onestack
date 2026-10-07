"use strict";

const { test, describe, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { startFakeLoki, startService } = require("./helpers");

const authToken = "ingest-token";

// Values that must never reach Loki or the container logs.
const secrets = {
  oauthCode: "OAUTH_CODE_7f3a",
  queryToken: "QUERY_TOKEN_91bd",
  password: "PASSWORD_hunter2",
  messageToken: "MESSAGE_TOKEN_5c2e",
  apiKey: "API_KEY_d04f",
  nestedSecret: "NESTED_SECRET_88aa",
  signedUrl: "AMZ_SIGNATURE_3e1c",
};

function logpushRecord() {
  const now = Date.now();
  return {
    ScriptName: "usual-suspects",
    Outcome: "ok",
    EventType: "fetch",
    EventTimestampMs: now,
    Event: {
      Request: {
        Method: "GET",
        URL: `https://usual-suspects.example/auth/callback?code=${secrets.oauthCode}&state=keep-me&token=${secrets.queryToken}`,
      },
      Response: { Status: 302 },
    },
    Logs: [
      { Level: "log", Message: ["login attempt", { user: "sam", password: secrets.password }], TimestampMs: now },
      { Level: "log", Message: [`calling https://api.example/v1/items?access_token=${secrets.messageToken}`], TimestampMs: now },
      { Level: "log", Message: [{ request: { headers: { "x-client-secret": secrets.nestedSecret } } }], TimestampMs: now },
      {
        Level: "log",
        Message: [`uploading to https://bucket.example/obj?X-Amz-Credential=AKIA&X-Amz-Signature=${secrets.signedUrl}`],
        TimestampMs: now,
      },
    ],
    Exceptions: [
      { Name: "Error", Message: `fetch https://api.example/v1/x?api_key=${secrets.apiKey} failed`, TimestampMs: now },
    ],
  };
}

describe("ingest redaction", () => {
  let loki;
  let ingest;

  before(async () => {
    loki = await startFakeLoki();
    ingest = await startService("ingest/server.js", {
      AUTH_TOKEN: authToken,
      LOKI_URL: `${loki.url}/loki/api/v1/push`,
      LOKI_TENANT_BY_SCRIPT: "usual-suspects=usual-suspects",
      LOKI_DEFAULT_TENANT: "cloudflare-workers",
    });
  });

  after(async () => {
    await ingest.stop();
    await loki.close();
  });

  async function logpush(body) {
    const before = loki.requests.length;
    const response = await fetch(`${ingest.url}/cloudflare-logpush`, {
      method: "POST",
      headers: { authorization: `Bearer ${authToken}` },
      body,
    });
    return { response, text: await response.text(), pushes: loki.requests.slice(before) };
  }

  test("no secret from URLs, console arguments or exceptions reaches Loki", async () => {
    const { response, text, pushes } = await logpush(JSON.stringify(logpushRecord()));
    assert.equal(response.status, 202, text);
    const pushed = pushes.map((push) => push.body).join("\n");
    assert.ok(pushed.length > 0);
    const leaked = Object.entries(secrets)
      .filter(([, value]) => pushed.includes(value))
      .map(([name]) => name);
    assert.deepEqual(leaked, []);
  });

  test("non-sensitive context survives redaction", async () => {
    const { pushes } = await logpush(JSON.stringify(logpushRecord()));
    const pushed = pushes.map((push) => push.body).join("\n");
    assert.match(pushed, /state=keep-me/);
    assert.match(pushed, /login attempt/);
    assert.match(pushed, /\\"user\\":\\"sam\\"/);
    assert.match(pushed, /usual-suspects\.example\/auth\/callback/);
  });

  test("a malformed payload is not echoed into the response or the service logs", async () => {
    const marker = `PAYLOAD_SNIPPET_${secrets.password}`;
    // Node's JSON.parse quotes the input around an unexpected token.
    const { response, text } = await logpush(`{"ScriptName":"usual-suspects","note":${marker}}`);
    assert.equal(response.status, 400);
    // Node truncates the quoted input, so look for the start of the marker.
    assert.ok(!text.includes("PAYLOAD"), `response echoed the payload: ${text}`);
    assert.ok(!ingest.output().includes("PAYLOAD"), "service logs echoed the payload");
  });
});
