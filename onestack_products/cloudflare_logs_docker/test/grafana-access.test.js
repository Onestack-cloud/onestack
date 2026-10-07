"use strict";

const { test, describe, before } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { stackRoot } = require("./helpers");

const scriptUrl = pathToFileURL(path.join(stackRoot, "scripts/configure-usual-suspects-grafana-access.mjs")).href;

describe("Grafana access isolation checks", () => {
  let configure;

  before(async () => {
    configure = await import(scriptUrl);
  });

  test("a UI user that only belongs to the Usual Suspects org passes", () => {
    assert.doesNotThrow(() => configure.assertOnlyMemberOf([{ orgId: 7, name: "Usual Suspects Logs", role: "Viewer" }], 7));
  });

  test("a UI user still in the admin org fails, even with role None", () => {
    assert.throws(
      () =>
        configure.assertOnlyMemberOf(
          [
            { orgId: 1, name: "Main Org.", role: "None" },
            { orgId: 7, name: "Usual Suspects Logs", role: "Viewer" },
          ],
          7,
        ),
      /Main Org\./,
    );
  });

  test("a UI user with more than Viewer in the Usual Suspects org fails", () => {
    assert.throws(() => configure.assertOnlyMemberOf([{ orgId: 7, name: "Usual Suspects Logs", role: "Admin" }], 7), /Viewer/);
  });

  test("a UI user missing from the Usual Suspects org fails", () => {
    assert.throws(() => configure.assertOnlyMemberOf([], 7), /not a member/);
  });

  test("script labels are read from log streams and metric series", () => {
    const labels = configure.scriptLabelsFrom({
      data: {
        result: [
          { stream: { scriptName: "usual-suspects" }, values: [] },
          { metric: { scriptName: "usual-suspects-production" }, values: [] },
          { metric: {}, values: [] },
        ],
      },
    });
    assert.deepEqual(labels.sort(), ["usual-suspects", "usual-suspects-production"]);
  });

  test("only Usual Suspects script names pass the service token check", () => {
    assert.doesNotThrow(() => configure.assertOnlyUsualSuspectsScripts(["usual-suspects", "usual-suspects-production"]));
    assert.throws(() => configure.assertOnlyUsualSuspectsScripts(["usual-suspects", "other-worker"]), /other-worker/);
  });

  test("the service token check sends a query that would see other scripts if it could", () => {
    const query = configure.serviceTokenProbeQuery;
    assert.match(query, /__USUAL_SUSPECTS_LABELS__/, "the proxy ignores queries without the placeholder");
    assert.match(query, /scriptName=~"\.\+"/);
  });
});
