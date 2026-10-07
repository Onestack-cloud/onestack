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

describe("redaction edge cases from review", () => {
  function timed(fn) {
    const started = process.hrtime.bigint();
    fn();
    return Number(process.hrtime.bigint() - started) / 1e6;
  }

  test("dotted and punctuation-heavy strings redact in linear time", () => {
    assert.ok(timed(() => redact("a.".repeat(80000))) < 500, "dotted string was slow");
    assert.ok(timed(() => redact(`https://x.example/?token=T ${")".repeat(160000)}a`)) < 500, "punctuation was slow");
  });

  test("deeply nested JSON in a string never leaks", () => {
    const deep = `${'{"a":'.repeat(5000)}{"password":"DEEP1"}${"}".repeat(5000)}`;
    assertHidden(redact(deep), "DEEP1");
  });

  test("deeply nested objects do not crash redaction", () => {
    let value = { password: "DEEP2" };
    for (let index = 0; index < 20000; index += 1) {
      value = { a: value };
    }
    assertHidden(redact(value), "DEEP2");
  });

  test("two-item console arguments are not mistaken for a header", () => {
    assert.equal(normalizeMessage(["Session expired for user", "u-123"]), "Session expired for user u-123");
  });

  test("header lists as pairs or name/value objects", () => {
    assertHidden(redact([["accept", "text/html"], ["cookie", "HDR1"]]), "HDR1");
    assertHidden(redact([{ name: "Authorization", value: "Bearer HDR2" }]), "HDR2");
  });

  test("URLs nested in a parameter, API key params and token-only userinfo", () => {
    assertHidden(redact("https://x.example/login?redirect=https://y.example/?token=NEST1"), "NEST1");
    assertHidden(redact("https://maps.example/api?key=KEY1&q=x"), "KEY1");
    assertHidden(redact("git clone https://TOKENONLY1@github.com/org/repo.git"), "TOKENONLY1");
  });

  test("JSON strings with nothing sensitive are left exactly as logged", () => {
    const input = '{ "id": 12345678901234567890, "ok": true }';
    assert.equal(redact(input), input);
  });

  test("counters and flags named after secrets stay visible", () => {
    assert.deepEqual(redact({ tokenCount: 3, passwordResetSent: true }), { tokenCount: 3, passwordResetSent: true });
  });

  test("one-time and auth code keys", () => {
    const output = redact({ otp: "OTP1", authCode: "AC1", code: "ERR_TIMEOUT" });
    assertHidden(output, "OTP1");
    assertHidden(output, "AC1");
    assert.equal(output.code, "ERR_TIMEOUT");
  });
});
