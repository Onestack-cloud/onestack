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

describe("redaction follow-up from the security scan", () => {
  test("numeric secrets are hidden while counters and flags stay visible", () => {
    const output = redact({ otp: 123456, pin: 4321, apiKey: 998877, tokenCount: 3, sessionTtl: 900, passwordResetSent: true });
    assertHidden(output, "123456");
    assertHidden(output, "998877");
    assert.equal(output.tokenCount, 3);
    assert.equal(output.sessionTtl, 900);
    assert.equal(output.passwordResetSent, true);
  });

  test("a credential name followed by its value in console arguments", () => {
    assertHidden(normalizeMessage(["authorization", "Bearer ARG1"]), "ARG1");
    assertHidden(normalizeMessage(["x-api-key", "ARG2"]), "ARG2");
  });

  test("Bearer and Basic credentials and key=value secrets in free text", () => {
    const output = redact(
      "auth header was Bearer FREE1abcdefgh then Basic FREE2abcdefgh== and password=FREE3, token: FREE4; user=sam",
    );
    for (const secret of ["FREE1", "FREE2", "FREE3", "FREE4"]) {
      assertHidden(output, secret);
    }
    assert.match(output, /user=sam/);
    assert.equal(redact("Error: token expired on the Basic plan"), "Error: token expired on the Basic plan");
  });

  test("free text rules stay linear", () => {
    const started = process.hrtime.bigint();
    redact(`${"a".repeat(200000)} ${"Bearer ".repeat(20000)} ${"x=".repeat(50000)}`);
    assert.ok(Number(process.hrtime.bigint() - started) / 1e6 < 500);
  });
});

describe("redaction gaps from the second review", () => {
  test("a credential name anywhere in console arguments hides the next argument", () => {
    assertHidden(normalizeMessage(["password:", "ARGS1"]), "ARGS1");
    assertHidden(normalizeMessage(["user", "sam", "token", "ARGS2", "extra"]), "ARGS2");
    assert.equal(normalizeMessage(["Session expired for user", "u-123"]), "Session expired for user u-123");
  });

  test("counter exceptions only apply to counter-like names", () => {
    const output = redact({ accountPassword: 482913, accountToken: 12345678, settlementSecret: 777, tokenCount: 2, tokenExpiresAt: 1700000000 });
    for (const secret of ["482913", "12345678", "777"]) {
      assertHidden(output, secret);
    }
    assert.equal(output.tokenCount, 2);
    assert.equal(output.tokenExpiresAt, 1700000000);
  });

  test("one-time codes and PINs under longer names", () => {
    const output = redact({ otpCode: "OTPC1", verificationCode: "VC1", mfaCode: "MFA1", userPin: "PIN1", errorCode: "E_TIMEOUT" });
    for (const secret of ["OTPC1", "VC1", "MFA1", "PIN1"]) {
      assertHidden(output, secret);
    }
    assert.equal(output.errorCode, "E_TIMEOUT");
    assertHidden(redact("sent otp_code=OTPC2 to user"), "OTPC2");
  });

  test("quoted names and values in free text", () => {
    for (const [input, secret] of [
      ['body: {"password":"QUOTE1","user":"sam"} truncated', "QUOTE1"],
      ['"token": "QUOTE2"', "QUOTE2"],
      ["password: 'QUOTE3 with spaces'", "QUOTE3"],
      ['secret="QUOTE4 more words"', "QUOTE4"],
      ["password => QUOTE5", "QUOTE5"],
    ]) {
      assertHidden(redact(input), secret);
    }
    assert.match(redact('body: {"password":"x","user":"sam"} truncated'), /"user":"sam"/);
  });
});

describe("redaction parser differentials from the push security scan", () => {
  test("a URL percent-encoded inside a parameter value", () => {
    const output = redact(
      "https://x.example/login?redirect=https%3A%2F%2Fy.example%2Fcb%3Ftoken%3DENC1%26state%3Dok&lang=en",
    );
    assertHidden(output, "ENC1");
    assert.match(output, /state%3Dok/);
    assert.match(output, /&lang=en$/);
  });

  test("JSON-escaped URLs inside a larger string", () => {
    assertHidden(redact('payload {"url":"https:\\/\\/api.example\\/v1?token=ESC1&x=1"} truncated'), "ESC1");
  });

  test("HTML-escaped ampersands", () => {
    assertHidden(redact("<a href=\"https://x.example/p?a=1&amp;token=AMP1\">"), "AMP1");
  });
});

describe("encoded URL edge cases from review", () => {
  test("a stray malformed escape does not switch redaction off", () => {
    assertHidden(redact("https://x.example/?redirect=https%3A%2F%2Fy%2Fcb%3Ftoken%3DSTRAY1%26x%3D%ZZ"), "STRAY1");
  });

  test("double-encoded nested URLs", () => {
    assertHidden(redact("https://x.example/?r=https%253A%252F%252Fy%252Fcb%253Ftoken%253DDOUBLE1"), "DOUBLE1");
  });

  test("a partly encoded scheme separator", () => {
    assertHidden(redact("https://x.example/?r=https:%2F%2Fy%2Fcb%3Ftoken%3DPARTIAL1"), "PARTIAL1");
  });
});
