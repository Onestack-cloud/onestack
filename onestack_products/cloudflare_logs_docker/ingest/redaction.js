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
  /authori[sz]ation|^auth$|[-_]auth$|cookie|passw(or)?d|^pwd$|secret|token|api[-_]?key|jwt|session|private[-_]?key|credential|signature|^sig$|^otp$|auth[-_]?code/i;
// Query parameters only: OAuth and one-time codes (without catching
// country_code, status_code or postcode) and bare API "key" parameters.
const sensitiveParamPattern = /^(key|code|.*(auth|otp|verification|reset|access|refresh)[-_]?code)$/i;
// Any scheme://..., so postgres://, redis://, wss:// and friends are covered.
// The scheme length is bounded to keep matching linear.
const urlPattern = /\b[a-z][a-z0-9+.-]{0,31}:\/\/[^\s"'<>]+/gi;
const trailingPunctuation = new Set([")", ".", ",", ";", ":", "!", "?", "]"]);

function isSensitiveKey(key) {
  return sensitiveKeyPattern.test(key);
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
  core = core.replace(/^([a-z][a-z0-9+.-]{0,31}:\/\/)([^/?#@\s]*)@/i, (match, scheme, userinfo) => {
    const colon = userinfo.indexOf(":");
    return colon === -1 ? `${scheme}${REDACTED}@` : `${scheme}${userinfo.slice(0, colon)}:${REDACTED}@`;
  });
  core = core.replace(/([?&#;])([^=&#;?]+)=([^&#;?]*)/g, (match, separator, name) =>
    isSensitiveParam(name) ? `${separator}${name}=${REDACTED}` : match,
  );
  return core + candidate.slice(end);
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
  return value.replace(urlPattern, redactUrlText);
}

function isPair(value) {
  return Array.isArray(value) && value.length === 2 && typeof value[0] === "string";
}

function redactValue(value, depth) {
  if (depth > MAX_DEPTH) {
    return REDACTED;
  }

  if (Array.isArray(value)) {
    // Header lists such as [["authorization", "Bearer ..."], ...]. Only lists
    // made entirely of pairs count, so console.log("Session expired", id) is
    // left alone.
    if (value.length > 0 && value.every(isPair)) {
      return value.map(([name, nested]) => [
        name,
        isSensitiveKey(name) ? REDACTED : redactValue(nested, depth + 2),
      ]);
    }
    return value.map((nested) => redactValue(nested, depth + 1));
  }

  if (value && typeof value === "object") {
    // Header objects such as { name: "Authorization", value: "Bearer ..." }.
    const sensitiveNameValue = typeof value.name === "string" && "value" in value && isSensitiveKey(value.name);
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => {
        const hides = (sensitiveNameValue && key === "value") || isSensitiveKey(key);
        // Numbers and flags such as tokenCount or passwordResetSent stay visible.
        if (hides && (typeof nested === "string" || (nested && typeof nested === "object"))) {
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
