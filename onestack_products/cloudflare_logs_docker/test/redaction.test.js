"use strict";

const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const { redact, normalizeMessage } = require("../ingest/redaction.js");

function assertHidden(output, secret) {
  const text = typeof output === "string" ? output : JSON.stringify(output);
  assert.ok(!text.includes(secret), `${secret} survived: ${text}`);
}

describe("redaction of URLs inside strings", () => {
  test("sensitive query parameters, including OAuth codes and signed URL parts", () => {
    const output = redact(
      "GET https://x.example/cb?code=S1&state=keep&X-Amz-Signature=S2&X-Amz-Credential=S3&access_token=S4&sig=S5",
    );
    for (const secret of ["=S1", "=S2", "=S3", "=S4", "=S5"]) {
      assertHidden(output, secret);
    }
    assert.match(output, /state=keep/);
  });

  test("fragment parameters", () => {
    assertHidden(redact("redirect to https://app.example/#access_token=FRAG1&type=bearer"), "FRAG1");
  });

  test("passwords in userinfo, for any scheme", () => {
    for (const url of [
      "https://sam:USERINFO1@api.example/x",
      "postgres://app:USERINFO2@db.internal:5432/main",
      "redis://default:USERINFO3@cache:6379",
      "mongodb+srv://svc:USERINFO4@cluster.example/db",
    ]) {
      const output = redact(`connect failed for ${url}`);
      assertHidden(output, url.match(/USERINFO\d/)[0]);
    }
  });

  test("query parameters on non-http schemes", () => {
    assertHidden(redact("opening wss://rt.example/socket?token=WSS1"), "WSS1");
  });

  test("URLs that WHATWG URL parsing rejects", () => {
    assertHidden(redact("bad https://[bad/?token=BAD1"), "BAD1");
  });

  test("leaves unrelated parameters, encoding and punctuation alone", () => {
    const input =
      "see https://x.example/p?country_code=AU&status_code=500&postcode=3000&q=a%20b&token=T1). Done";
    const output = redact(input);
    assert.match(output, /country_code=AU&status_code=500&postcode=3000&q=a%20b&token=\[redacted\]\)\. Done$/);
  });
});

describe("redaction of structured values", () => {
  test("sensitive keys anywhere in an object", () => {
    const output = redact({
      a: { jwt: "K1", sessionId: "K2", pwd: "K3", private_key: "K4", "x-client-secret": "K5", apiKey: "K6" },
      keep: "visible",
    });
    for (const secret of ["K1", "K2", "K3", "K4", "K5", "K6"]) {
      assertHidden(output, secret);
    }
    assert.equal(output.keep, "visible");
  });

  test("header pair arrays", () => {
    assertHidden(redact([["authorization", "Bearer PAIR1"], ["accept", "text/html"]]), "PAIR1");
    assert.deepEqual(redact([["accept", "text/html"]]), [["accept", "text/html"]]);
  });

  test("JSON encoded inside a string", () => {
    const output = redact(JSON.stringify({ user: "sam", password: "JSON1" }));
    assertHidden(output, "JSON1");
    assert.equal(JSON.parse(output).user, "sam");
  });

  test("console arguments become a redacted message", () => {
    const message = normalizeMessage(["login", { user: "sam", password: "MSG1" }, "https://x.example/?token=MSG2"]);
    assertHidden(message, "MSG1");
    assertHidden(message, "MSG2");
    assert.match(message, /^login \{"user":"sam","password":"\[redacted\]"\}/);
  });
});
