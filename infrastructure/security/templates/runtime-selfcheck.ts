import { test } from 'node:test';
import assert from 'node:assert/strict';
import { securityFloors, assessRuntime, compare, auditCount } from './check-runtime.ts';
import { advisoryKeys, comparisonPackages } from './ci.ts';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

const floors = {'22': '22.23.4', '24': '24.22.1', '26': '26.12.1'};
const schedule = {v20: {start:'2023-04-18', end:'2026-04-30'}, v22: {start:'2024-04-24', end:'2027-04-30'}, v24: {start:'2025-04-22', end:'2028-04-30'}, v26: {start:'2026-04-22', end:'2029-04-30'}};

test('detects each vulnerable embedded runtime from the incident', () => {
  for (const v of ['22.23.3', '24.19.0', '24.21.0', '26.12.0']) assert.ok(assessRuntime(v, floors, schedule, '2026-10-22'));
});
test('accepts fixed versions and newer patches in supported majors', () => {
  for (const v of ['22.23.4', '24.22.1', '26.12.2']) assert.equal(assessRuntime(v, floors, schedule, '2026-10-22'), null);
});
test('raises a floor on a newly published security release without lowering the baseline', () => {
  assert.deepEqual(securityFloors(floors, [{version:'v24.22.0', security:true}, {version:'v24.23.0', security:true}, {version:'v26.13.0', security:false}]), {...floors, '24':'24.23.0'});
});
test('refuses incomplete feeds and unknown or end-of-life release lines', () => {
  assert.throws(() => securityFloors(floors, []));
  assert.throws(() => securityFloors(floors, [{version:'v24.23.0', security:undefined as unknown as boolean}]));
  assert.ok(assessRuntime('20.99.0', {...floors, '20':'20.0.0'}, schedule, '2026-10-22'));
  assert.ok(assessRuntime('28.0.0', floors, schedule, '2026-10-22'));
});
test('reads Bun nested advisory lists and npm audit counts', () => {
  assert.equal(auditCount({vite:[{severity:'high'}, {severity:'moderate'}], sharp:[{severity:'critical'}]}), 2);
  assert.equal(auditCount({metadata:{vulnerabilities:{high:2, critical:1, moderate:9}}}), 3);
  assert.equal(auditCount({}), 0);
});
test('does not turn malformed or incomplete audits into a clean scan', () => {
  for (const report of [null, [], {error:'unavailable'}, {skipped:['private-package']}, {package:[{title:'no severity'}]}, {metadata:{}}]) assert.throws(() => auditCount(report));
});
test('uses numerical version comparison', () => {
  assert.ok(compare('24.22.1','24.9.9') > 0);
  assert.throws(() => compare('24','24.22.1'));
});
test('compares advisory identities across Bun and npm instead of hiding existing findings', () => {
  assert.deepEqual(advisoryKeys([{root:'.', findings:{vite:[{id:1, url:'https://example.test/advisory', severity:'high'}]}}]), ['.:vite:https://example.test/advisory']);
  assert.deepEqual(advisoryKeys([{root:'console', findings:{vulnerabilities:{vite:{severity:'high', via:[{url:'https://example.test/advisory'}, 'esbuild']}}}}]), ['console:vite:esbuild', 'console:vite:https://example.test/advisory']);
});
test('requires a readable baseline commit and every registered lockfile', () => {
  const directory = mkdtempSync(join(tmpdir(), 'security-comparison-test-'));
  const source = join(directory, 'source'), target = join(directory, 'target');
  mkdirSync(source); mkdirSync(target);
  const git = (...args: string[]) => execFileSync('git', args, {cwd: source, encoding: 'utf8'}).trim();
  try {
    git('init', '--quiet');
    writeFileSync(join(source, 'package.json'), '{}');
    writeFileSync(join(source, 'package-lock.json'), '{"lockfileVersion":3}');
    git('add', '.');
    git('-c', 'user.name=Synthetic security test', '-c', 'user.email=security@example.invalid', 'commit', '--quiet', '-m', 'Synthetic baseline');
    const sha = git('rev-parse', 'HEAD');
    assert.deepEqual(comparisonPackages(sha, target, ['.'], source), ['.']);
    assert.equal(readFileSync(join(target, 'package-lock.json'), 'utf8'), '{"lockfileVersion":3}');
    assert.throws(() => comparisonPackages('a'.repeat(40), target, ['.'], source), /commit is unavailable/);
    assert.throws(() => comparisonPackages(sha, target, ['.', 'missing-root'], source), /lockfile is unavailable/);
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
});
