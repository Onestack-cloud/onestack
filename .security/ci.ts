import { check } from './check-runtime.ts';
import { readFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

export function advisoryKeys(audits: Array<{root: string; findings?: unknown}>): string[] {
  const keys = new Set<string>();
  for (const audit of audits) {
    if (!audit.findings || typeof audit.findings !== 'object') continue;
    const report = audit.findings as Record<string, unknown>;
    if (report.vulnerabilities && typeof report.vulnerabilities === 'object') {
      for (const [name, raw] of Object.entries(report.vulnerabilities)) {
        const item = raw as {severity: string; via: Array<string | {source?: number; url?: string}>};
        if (!['high', 'critical', 'unknown'].includes(item.severity)) continue;
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
      const roots: string[] = [];
      const hexLockfiles: string[] = [];
      for (const file of policy.hexLockfiles || []) {
        const result = spawnSync('git', ['show', `${base}:${file}`]);
        if (result.status === 0) {
          const path = resolve(directory, file);
          if (!path.startsWith(directory + '/')) throw new Error('Hex comparison path escapes directory');
          mkdirSync(dirname(path), {recursive:true});
          writeFileSync(path, result.stdout);
          hexLockfiles.push(file);
        }
      }
      for (const root of policy.packageRoots) {
        let found = false;
        for (const file of ['package.json', 'package-lock.json', 'bun.lock', 'bun.lockb']) {
          const relative = root === '.' ? file : `${root}/${file}`;
          const result = spawnSync('git', ['show', `${base}:${relative}`], {maxBuffer: 32 * 1024 * 1024});
          if (result.status === 0) {
            const path = resolve(directory, relative);
            if (!path.startsWith(directory + '/')) throw new Error('Comparison path escapes temporary directory');
            mkdirSync(dirname(path), {recursive: true});
            writeFileSync(path, result.stdout);
            if (file.endsWith('lock') || file.endsWith('lockb') || file === 'package-lock.json') found = true;
          }
        }
        if (found) roots.push(root);
      }
      mkdirSync(join(directory, '.security'));
      writeFileSync(join(directory, '.security/policy.json'), JSON.stringify({...policy, packageRoots: roots, hexLockfiles}));
      previousKeys = advisoryKeys((await check(directory)).audits);
      comparison = base;
    } finally {
      rmSync(directory, {recursive: true, force: true});
    }
  }
  const previous = new Set(previousKeys);
  const introduced = base ? currentKeys.filter(key => !previous.has(key)) : [];
  const policy = JSON.parse(readFileSync('.security/policy.json', 'utf8'));
  const mitigated = [];
  for (const item of policy.verifiedBackports || []) {
    if (!currentKeys.includes(item.advisoryKey)) continue;
    if (!Number.isFinite(Date.parse(item.reviewBefore)) || new Date().toISOString() >= item.reviewBefore) throw new Error('Security backport review is overdue or invalid');
    const path = resolve(item.patch);
    if (!path.startsWith(process.cwd() + '/')) throw new Error('Backport path escapes repository');
    const hash = createHash('sha256').update(readFileSync(path)).digest('hex');
    if (hash !== item.sha256) throw new Error('Security backport has changed');
    const verification = resolve(item.verification);
    if (!verification.startsWith(process.cwd() + '/')) throw new Error('Backport verification escapes repository');
    const result = spawnSync(process.execPath, [verification], {encoding:'utf8', timeout:30000});
    if (result.status !== 0) throw new Error('Security backport verification failed');
    mitigated.push({advisoryKey:item.advisoryKey, patch:item.patch, sha256:hash, state:'verified local backport'});
  }
  const mitigatedKeys = new Set(mitigated.map(item => item.advisoryKey));
  const unmitigated = introduced.filter(key => !mitigatedKeys.has(key));
  const runtimeFailures = current.findings.filter(item => item.target === 'CI Node');
  const report = {...current, comparison, introducedAdvisories: introduced,
                  verifiedMitigations: mitigated,
                  existingAdvisories: currentKeys.filter(key => !introduced.includes(key)),
                  gate: runtimeFailures.length || unmitigated.length ? 'failed' : 'passed'};
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
