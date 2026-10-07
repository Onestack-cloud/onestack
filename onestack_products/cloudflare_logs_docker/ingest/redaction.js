"use strict";

// Shared by the ingest adapter and scripts/backfill-workers-observability.mjs
// so live and backfilled logs are redacted the same way before they reach Loki.
// Every regex here is linear in the input: log content is attacker-influenced
// and a slow pattern would stall the ingest event loop.

const REDACTED = "[redacted]";
// Deeper values are replaced outright rather than risking a stack overflow
// that would either crash the batch or skip redaction.
const MAX_DEPTH = 64;

// Object keys and query parameter names whose values are credentials.
const sensitiveKeyPattern =
  /authori[sz]ation|^auth$|[-_]auth$|cookie|passw(or)?d|^pwd$|secret|token|api[-_]?key|jwt|session|private[-_]?key|credential|signature|^sig$|(^|[-_])(otp|pin)([-_]|$)|(auth|verification|reset|mfa|2fa|access|refresh|otp)[-_]?code/i;
// camelCase one-time codes and PINs (otpCode, userPin) without catching words
// such as "footprint" or "spin".
const camelSensitivePattern = /^(otp|pin)[A-Z]|[a-z](Otp|Pin)([A-Z]|$)/;
// Numbers under a sensitive key stay visible only when the key names a
// counter, size or duration (tokenCount, sessionTtl), not an OTP or PIN.
const counterKeyPattern = /(count|total|length|size|ttl|expir\w*|attempts)$/i;
// A bare credential name, as in console.log("authorization", value).
const namePattern = /^[A-Za-z0-9_.-]{1,64}$/;
// Query parameters only: OAuth and one-time codes (without catching
// country_code, status_code or postcode) and bare API "key" parameters.
const sensitiveParamPattern = /^(key|code|.*(auth|otp|verification|reset|access|refresh)[-_]?code)$/i;
// Any scheme://..., so postgres://, redis://, wss:// and friends are covered,
// including the JSON-escaped form scheme:\/\/... found in serialised payloads.
// The scheme length is bounded to keep matching linear.
const urlPattern = /\b[a-z][a-z0-9+.-]{0,31}:(?:\/\/|\\\/\\\/)[^\s"'<>]+/gi;
// A parameter value that is itself a percent-encoded URL (redirect_uri=https%3A%2F%2F...).
const encodedUrlPattern = /%3A(?:%2F|\/){2}/i;
const trailingPunctuation = new Set([")", ".", ",", ";", ":", "!", "?", "]"]);
// Free text: "Bearer <token>" and "password=..." or "token: ...". The
// lookbehind makes a name start only at a word boundary, keeping this linear.
// Credentials are at least eight characters, so "Basic plan" is left alone.
const schemeCredentialPattern = /\b([Bb]earer|[Bb]asic)\s+[A-Za-z0-9._~+/=-]{8,}/g;
// Names may be quoted ("token": "...") and quoted values are bounded so the
// pattern stays linear.
const textPairPattern =
  /(?<![A-Za-z0-9_.-])(["']?)([A-Za-z0-9_.-]{1,64})\1(\s*(?:=>|[:=])\s*)("[^"\n]{0,512}"|'[^'\n]{0,512}'|[^\s,;&"']+)/g;

function isSensitiveKey(key) {
  return sensitiveKeyPattern.test(key) || camelSensitivePattern.test(key);
}

// "password", "password:" or "token=" on its own, as a console.log argument.
function isBareSensitiveName(value) {
  if (typeof value !== "string") {
    return false;
  }
  const name = value.trim().replace(/\s*[:=]$/, "");
  return namePattern.test(name) && isSensitiveKey(name);
}

function isSensitiveParam(name) {
  let decoded = name;
  try {
    decoded = decodeURIComponent(name);
  } catch {
    // Keep the raw name.
  }
  return isSensitiveKey(decoded) || sensitiveParamPattern.test(decoded);
}

// Rewrites only the sensitive parts as text, leaving encoding, parameter order
// and trailing punctuation as logged. No URL parsing, so malformed URLs are
// redacted too. "?" also separates parameters so a URL nested in a parameter
// value has its own parameters checked.
function redactUrlText(candidate) {
  let end = candidate.length;
  while (end > 0 && trailingPunctuation.has(candidate[end - 1])) {
    end -= 1;
  }
  let core = candidate.slice(0, end);
  core = core.replace(/^([a-z][a-z0-9+.-]{0,31}:(?:\/\/|\\\/\\\/))([^/?#@\s]*)@/i, (match, scheme, userinfo) => {
    const colon = userinfo.indexOf(":");
    return colon === -1 ? `${scheme}${REDACTED}@` : `${scheme}${userinfo.slice(0, colon)}:${REDACTED}@`;
  });
  core = core.replace(/([?&#;])([^=&#;?]+)=([^&#;?]*)/g, (match, separator, name, value) => {
    if (isSensitiveParam(name)) {
      return `${separator}${name}=${REDACTED}`;
    }
    const nested = redactEncodedUrl(value);
    return nested === value ? match : `${separator}${name}=${nested}`;
  });
  return core + candidate.slice(end);
}

// Decodes a percent-encoded URL value, redacts it with the same rules and
// re-encodes it only if something changed. Each nested level is shorter than
// the last, so this terminates.
function redactEncodedUrl(value) {
  if (!encodedUrlPattern.test(value)) {
    return value;
  }
  let decoded;
  try {
    decoded = decodeURIComponent(value);
  } catch {
    return value;
  }
  const redacted = decoded.replace(urlPattern, redactUrlText);
  return redacted === decoded ? value : encodeURIComponent(redacted);
}

function redactString(value, depth) {
  const trimmed = value.trim();
  if ((trimmed.startsWith("{") && trimmed.endsWith("}")) || (trimmed.startsWith("[") && trimmed.endsWith("]"))) {
    let parsed;
    let isJson = true;
    try {
      parsed = JSON.parse(trimmed);
    } catch {
      isJson = false;
    }
    if (isJson) {
      try {
        const safe = JSON.stringify(redactValue(parsed, depth + 1));
        // Keep the original text (formatting, big integers) unless something changed.
        return safe === JSON.stringify(parsed) ? value : safe;
      } catch {
        return REDACTED;
      }
    }
  }
  return value
    .replace(urlPattern, redactUrlText)
    .replace(schemeCredentialPattern, `$1 ${REDACTED}`)
    .replace(textPairPattern, (match, quote, name, separator, secret) => {
      const quoted = secret[0] === '"' || secret[0] === "'";
      const inner = quoted ? secret.slice(1, -1) : secret;
      if (!isSensitiveKey(name) || inner.startsWith(REDACTED)) {
        return match;
      }
      const wrap = quoted ? secret[0] : "";
      return `${quote}${name}${quote}${separator}${wrap}${REDACTED}${wrap}`;
    });
}

function isPair(value) {
  return Array.isArray(value) && value.length === 2 && typeof value[0] === "string";
}

function redactValue(value, depth) {
  if (depth > MAX_DEPTH) {
    return REDACTED;
  }

  if (Array.isArray(value)) {
    // Header lists such as [["authorization", "Bearer ..."], ...]. Only bare
    // names count, so console.log("Session expired", id) is left alone.
    if (value.length > 0 && value.every(isPair)) {
      return value.map(([name, nested]) => [
        name,
        isSensitiveKey(name) ? REDACTED : redactValue(nested, depth + 2),
      ]);
    }
    // console.log("password:", value, ...): hide whatever follows a bare name.
    return value.map((nested, index) =>
      index > 0 && isBareSensitiveName(value[index - 1]) ? REDACTED : redactValue(nested, depth + 1),
    );
  }

  if (value && typeof value === "object") {
    // Header objects such as { name: "Authorization", value: "Bearer ..." }.
    const sensitiveNameValue = typeof value.name === "string" && "value" in value && isSensitiveKey(value.name);
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => {
        const hides = (sensitiveNameValue && key === "value") || isSensitiveKey(key);
        // Flags (passwordResetSent) and counters (tokenCount) stay visible.
        const visible =
          nested === null ||
          nested === undefined ||
          typeof nested === "boolean" ||
          (typeof nested === "number" && counterKeyPattern.test(key));
        if (hides && !visible) {
          return [key, REDACTED];
        }
        return [key, redactValue(nested, depth + 1)];
      }),
    );
  }

  if (typeof value === "string") {
    return redactString(value, depth);
  }

  return value;
}

function redact(value) {
  return redactValue(value, 0);
}

// Turns console.log arguments into one line, redacting before stringifying.
function normalizeMessage(message) {
  const safe = redact(message);
  if (Array.isArray(safe)) {
    return safe.map((part) => (typeof part === "string" ? part : JSON.stringify(part))).join(" ");
  }
  if (typeof safe === "string") {
    return safe;
  }
  if (safe === null || safe === undefined) {
    return "";
  }
  return JSON.stringify(safe);
}

module.exports = { redact, normalizeMessage };
