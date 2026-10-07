"use strict";

// Shared by the ingest adapter and scripts/backfill-workers-observability.mjs
// so live and backfilled logs are redacted the same way before they reach Loki.

const REDACTED = "[redacted]";

// Object keys and query parameter names whose values are credentials.
const sensitiveKeyPattern =
  /authori[sz]ation|^auth$|[-_]auth$|cookie|passw(or)?d|^pwd$|secret|token|api[-_]?key|jwt|session|private[-_]?key|credential|signature|^sig$/i;
// OAuth and one-time codes, without catching country_code, status_code or postcode.
const sensitiveCodePattern = /^(code|.*(auth|otp|verification|reset|access|refresh)[-_]?code)$/i;
// Any scheme://..., so postgres://, redis://, wss:// and friends are covered.
const urlPattern = /\b[a-z][a-z0-9+.-]*:\/\/[^\s"'<>]+/gi;

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
  return isSensitiveKey(decoded) || sensitiveCodePattern.test(decoded);
}

// Rewrites only the sensitive parts as text, leaving encoding, parameter order
// and trailing punctuation as logged. No URL parsing, so malformed URLs are
// redacted too.
function redactUrlText(candidate) {
  const tail = candidate.match(/[).,;:!?\]]+$/)?.[0] || "";
  let core = candidate.slice(0, candidate.length - tail.length);
  core = core.replace(/^([a-z][a-z0-9+.-]*:\/\/)([^/?#@\s]*):([^/?#@\s]*)@/i, `$1$2:${REDACTED}@`);
  core = core.replace(/([?&#;])([^=&#;]+)=([^&#;]*)/g, (match, separator, name) =>
    isSensitiveParam(name) ? `${separator}${name}=${REDACTED}` : match,
  );
  return core + tail;
}

function redactString(value) {
  const trimmed = value.trim();
  if ((trimmed.startsWith("{") && trimmed.endsWith("}")) || (trimmed.startsWith("[") && trimmed.endsWith("]"))) {
    try {
      return JSON.stringify(redact(JSON.parse(trimmed)));
    } catch {
      // Not JSON; fall through to URL redaction.
    }
  }
  return value.replace(urlPattern, redactUrlText);
}

function redact(value) {
  if (Array.isArray(value)) {
    // Header lists such as [["authorization", "Bearer ..."], ...].
    if (value.length === 2 && typeof value[0] === "string" && isSensitiveKey(value[0])) {
      return [value[0], REDACTED];
    }
    return value.map(redact);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [key, isSensitiveKey(key) ? REDACTED : redact(nested)]),
    );
  }

  if (typeof value === "string") {
    return redactString(value);
  }

  return value;
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
