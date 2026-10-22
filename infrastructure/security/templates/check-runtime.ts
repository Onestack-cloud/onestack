import { readFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const sources = {
  releases: 'https://nodejs.org/dist/index.json',
  schedule: 'https://raw.githubusercontent.com/nodejs/Release/main/schedule.json',
};

export function version(value: string): number[] {
  const match = /^v?(\d+)\.(\d+)\.(\d+)$/.exec(value);
  if (!match) throw new Error(`Invalid exact Node version: ${value}`);
  return match.slice(1).map(Number);
}

export function compare(a: string, b: string): number {
  const left = version(a), right = version(b);
  for (let i = 0; i < 3; i++) {
    if (left[i] !== right[i]) return left[i] - right[i];
  }
  return 0;
}

export function securityFloors(baseline: Record<string, string>, releases: Array<{version: string; security: boolean}>) {
  if (!Array.isArray(releases) || releases.length < 1) throw new Error('Invalid Node release feed');
  const floors = { ...baseline };
  for (const item of releases) {
    const major = String(version(item.version)[0]);
    if (typeof item.security !== 'boolean') throw new Error('Node release feed has no security status');
    if (item.security && (!floors[major] || compare(item.version, floors[major]) > 0)) floors[major] = item.version.replace(/^v/, '');
  }
  return floors;
}

export function assessRuntime(value: string, floors: Record<string, string>, schedule: Record<string, {start: string; end: string}>, today: string): string | null {
  const major = String(version(value)[0]), dates = schedule[`v${major}`];
  if (!dates || !dates.end || !dates.start || !floors[major]) return 'untracked Node release line';
  if (today < dates.start || today >= dates.end) return 'Node release line is unsupported';
  if (compare(value, floors[major]) < 0) return `requires Node ${floors[major]} or later in this major`;
  return null;
}

async function fetchJSON(url: string) {
  const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error(`Advisory source HTTP ${response.status}`);
  return response.json();
}

export function auditCount(report: unknown): number {
  if (!report || typeof report !== 'object' || Array.isArray(report)) throw new Error('Invalid audit document');
  const value = report as Record<string, unknown>;
  if (value.error || value.errors || value.skipped) throw new Error('Incomplete dependency audit');
  if (value.metadata && typeof value.metadata === 'object') {
    const counts = (value.metadata as {vulnerabilities?: Record<string, number>}).vulnerabilities;
    if (!counts || !Number.isFinite(counts.high) || !Number.isFinite(counts.critical)) throw new Error('Missing npm audit counts');
    return counts.high + counts.critical;
  }
  const entries = Object.values(value).flat();
  for (const entry of entries) {
    if (!entry || typeof entry !== 'object' || !('severity' in entry) || !['low', 'moderate', 'high', 'critical'].includes(String(entry.severity))) throw new Error('Incomplete Bun advisory');
  }
  return entries.filter(entry => ['high', 'critical'].includes(String((entry as {severity: string}).severity))).length;
}

export function discoverRoots(root: string): string[] {
  const result = spawnSync('git', ['ls-files', '-z'], {cwd: root, encoding: 'utf8'});
  if (result.status !== 0) throw new Error('Cannot discover tracked package roots');
  const roots = new Set<string>();
  for (const relative of result.stdout.split('\0').filter(Boolean)) {
    const file = resolve(root, relative);
    if (!existsSync(file)) continue;
    if (/(^|\/)(bun\.lockb?|package-lock\.json)$/.test(relative)) roots.add(dirname(relative));
    if (/(^|\/)package\.json$/.test(relative)) {
      const manifest = JSON.parse(readFileSync(file, 'utf8'));
      if (Object.keys(manifest.dependencies || {}).length || Object.keys(manifest.devDependencies || {}).length) roots.add(dirname(relative));
    }
  }
  return [...roots].sort();
}

export async function check(root = process.cwd()) {
  const policy = JSON.parse(readFileSync(resolve(root, '.security/policy.json'), 'utf8'));
  if (policy.schemaVersion !== 1 || !Array.isArray(policy.packageRoots)) throw new Error('Invalid security policy');
  for (const relative of policy.packageRoots) {
    if (typeof relative !== 'string' || relative.startsWith('/') || relative.split('/').includes('..')) throw new Error('Invalid registered package root');
  }
  if (existsSync(resolve(root, '.git'))) {
    const registered = new Set([...policy.packageRoots, ...Object.keys(policy.excludedPackageRoots || {})]);
    const missing = discoverRoots(root).filter(relative => !registered.has(relative));
    if (missing.length) throw new Error('A dependency root is not registered in the security policy');
  }
  const [releases, schedule] = await Promise.all([fetchJSON(sources.releases), fetchJSON(sources.schedule)]);
  const floors = securityFloors(policy.minimumNode, releases);
  const now = new Date().toISOString();
  const findings: Array<{target: string; detail: string}> = [];
  const failure = assessRuntime(process.versions.node, floors, schedule, now.slice(0, 10));
  if (failure) findings.push({target: 'CI Node', detail: failure});
  if (Number(process.versions.node.split('.')[0]) !== policy.nodeMajor) findings.push({target: 'CI Node', detail: `expected major ${policy.nodeMajor}`});
  const audits: Array<{root: string; state: string; findings?: unknown}> = [];
  for (const relative of policy.packageRoots) {
    const cwd = resolve(root, relative);
    if (cwd !== resolve(root) && !cwd.startsWith(resolve(root) + '/')) throw new Error('Package root escapes repository');
    let command: string, args: string[];
    if (existsSync(resolve(cwd, 'bun.lock')) || existsSync(resolve(cwd, 'bun.lockb'))) {
      command = process.env.SECURITY_BUN || 'bun';
      args = ['audit', '--json', '--audit-level=high'];
    } else if (existsSync(resolve(cwd, 'package-lock.json'))) {
      command = 'npm';
      args = ['audit', '--json', '--audit-level=high', '--ignore-scripts'];
    } else throw new Error(`No supported lockfile at ${relative}`);
    const run = spawnSync(command, args, {cwd, encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024});
    if (run.error || run.signal || run.status === null || run.status > 1) throw new Error(`Dependency audit unavailable at ${relative}`);
    let report;
    try { report = JSON.parse(run.stdout); } catch { throw new Error(`Dependency audit returned invalid JSON at ${relative}`); }
    const affected = auditCount(report);
    if (run.status === 1 && !affected) throw new Error(`Audit failed without actionable findings at ${relative}`);
    audits.push({root: relative, state: affected ? 'affected' : 'checked', findings: affected ? report : undefined});
    if (affected) findings.push({target: relative, detail: `${affected} high/critical dependency findings`});
  }
  return {schemaVersion: 1, checkedAt: now, state: findings.length ? 'affected' : 'checked', node: process.versions.node, floors, findings, audits};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  check().then(result => {
    console.log(JSON.stringify(result, null, 2));
    process.exitCode = result.findings.length ? 1 : 0;
  }).catch(() => {
    console.error(JSON.stringify({state: 'unknown', error: 'Security coverage incomplete. Check policy, lockfiles, audit tool and advisory source availability.'}));
    process.exitCode = 2;
  });
}
