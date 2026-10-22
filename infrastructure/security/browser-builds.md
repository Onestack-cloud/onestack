# Cloudflare Builds browser verification

The existing hourly `security-maintenance` Codex heartbeat provides this fallback
while the native Cloudflare OAuth login cannot read the Builds API. It requires
the Mac and Codex app to be running and the signed-in Brave Work session.
VPS scans and repository CI do not depend on this browser session.

On each heartbeat, use the supported computer-use tools to confirm that the
selected browser is Brave and read these exact Cloudflare settings pages:

- https://dash.cloudflare.com/663b85e4f509df63c1735f6e77db4370/workers/services/view/r4r-next-js/production/settings
- https://dash.cloudflare.com/663b85e4f509df63c1735f6e77db4370/workers/services/view/usual-suspects/production/settings

Check the Digital Nachos account, worker name, Builds production section and
`NODE_VERSION` value. Read only those fields. Do not reveal runtime secrets,
other build variables, deploy hooks or credentials. Do not replay browser
requests, export cookies or create a new credential for this fallback.

After both values are visibly verified, atomically write mode 0600 JSON to
`~/.local/state/security-maintenance/bot/builds-browser.json` with:

```json
{
  "checkedAt": "<actual UTC observation time in ISO 8601>",
  "source": "Cloudflare dashboard via Brave",
  "account": "663b85e4f509df63c1735f6e77db4370",
  "targets": [
    {"worker": "r4r-next-js", "node": "<observed version>", "url": "<exact settings URL above>"},
    {"worker": "usual-suspects", "node": "<observed version>", "url": "<exact settings URL above>"}
  ]
}
```

Use each actually observed value, including an old version. The native provider
check compares it with current official Node security floors. Receipts older
than two hours, future-dated receipts and mismatched accounts, workers or URLs
do not count as coverage. An API failure remains visible in `apiCoverage` even
when a current browser observation covers the setting.

If either page cannot be verified, do not refresh the receipt timestamp. Report
unknown coverage and the actual blocker. Recheck the provider report after a
successful observation. A screenshot is not a substitute for reading the value.
Changes to build settings and application releases retain the existing release
review and qualification policy.

The optional long-term API route is a user-scoped Cloudflare token with the
read permission accepted by the Builds endpoints, restricted to Digital Nachos.
Store a reference in the private bot policy and the secret in Infisical.
Creation or expansion of credentials through browser control requires the
user's participation under the computer-use rules. Current API reference:
https://developers.cloudflare.com/api/resources/workers_builds/subresources/triggers/subresources/environment_variables/methods/list/
