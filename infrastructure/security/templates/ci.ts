import { check } from './check-runtime.ts';
import { readFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export function advisoryKeys(audits: Array<{root: string; findings?: unknown}>): string[] {
  const keys = new Set<string>();
  for (const audit of audits) {
    if (!audit.findings || typeof audit.findings !== 'object') continue;
    const report = audit.findings as Record<string, unknown>;
    if (report.vulnerabilities && typeof report.vulnerabilities === 'object') {
      for (const [name, raw] of Object.entries(report.vulnerabilities)) {
        const item = raw as {severity: string; via: Array<string | {source?: number; url?: string}>};
        if (!['high', 'critical'].includes(item.severity)) continue;
        for (const via of item.via) {
          keys.add(`${audit.root}:${name}:${typeof via === 'string' ? via : via.url || via.source}`);
        }
      }
    } else {
      for (const [name, raw] of Object.entries(report)) {
        for (const item of raw as Array<{id: number; url?: string; severity: string}>) {
          if (['high', 'critical'].includes(item.severity)) keys.add(`${audit.root}:${name}:${item.url || item.id}`);
        }
      }
    }
  }
  return [...keys].sort();
}

export function comparisonPackages(base: string, directory: string, roots: string[], source = process.cwd()): string[] {
  if (!/^[a-f0-9]{40}$/.test(base) || /^0+$/.test(base)) throw new Error('Invalid security comparison commit');
  const commit = spawnSync('git', ['cat-file', '-e', `${base}^{commit}`], {cwd: source});
  if (commit.status !== 0) throw new Error('Security comparison commit is unavailable');
  for (const root of roots) {
    let found = false;
    for (const file of ['package.json', 'package-lock.json', 'bun.lock', 'bun.lockb']) {
      const relative = root === '.' ? file : `${root}/${file}`;
      const result = spawnSync('git', ['show', `${base}:${relative}`], {cwd: source, maxBuffer: 32 * 1024 * 1024});
      if (result.status !== 0) continue;
      const path = resolve(directory, relative);
      if (!path.startsWith(directory + '/')) throw new Error('Comparison path escapes temporary directory');
      mkdirSync(dirname(path), {recursive: true});
      writeFileSync(path, result.stdout);
      if (file !== 'package.json') found = true;
    }
    if (!found) throw new Error(`Security comparison lockfile is unavailable at ${root}`);
  }
  return roots;
}

async function main() {
  const current = await check();
  const currentKeys = advisoryKeys(current.audits);
  const base = process.env.SECURITY_BASE_SHA;
  let previousKeys: string[] = [];
  let comparison = 'scheduled inventory';
  if (base) {
    if (!/^[a-f0-9]{40}$/.test(base) || /^0+$/.test(base)) throw new Error('Invalid security comparison commit');
    const directory = mkdtempSync(join(tmpdir(), 'security-base-'));
    try {
      const policy = JSON.parse(readFileSync('.security/policy.json', 'utf8'));
      const roots = comparisonPackages(base, directory, policy.packageRoots);
      mkdirSync(join(directory, '.security'));
      writeFileSync(join(directory, '.security/policy.json'), JSON.stringify({...policy, packageRoots: roots}));
      previousKeys = advisoryKeys((await check(directory)).audits);
      comparison = base;
    } finally {
      rmSync(directory, {recursive: true, force: true});
    }
  }
  const previous = new Set(previousKeys);
  const introduced = base ? currentKeys.filter(key => !previous.has(key)) : [];
  const runtimeFailures = current.findings.filter(item => item.target === 'CI Node');
  const report = {...current, comparison, introducedAdvisories: introduced,
                  existingAdvisories: currentKeys.filter(key => !introduced.includes(key)),
                  gate: runtimeFailures.length || introduced.length ? 'failed' : 'passed'};
  writeFileSync('security-report.json', JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({state: report.state, gate: report.gate,
                             existing: report.existingAdvisories.length, introduced: introduced.length}));
  process.exitCode = report.gate === 'passed' ? 0 : 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => {
    writeFileSync('security-report.json', JSON.stringify({state:'unknown', gate:'failed', error:'Incomplete security comparison or advisory coverage'}) + '\n');
    console.error('Security comparison or advisory coverage is incomplete');
    process.exitCode = 2;
  });
}
