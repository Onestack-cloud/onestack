import {readFileSync} from 'node:fs';

export function parseHex(text: string) {
  const rows = text.split('\n').filter(line => /^\s*"/.test(line));
  if (!rows.length) throw new Error('Empty Hex inventory');
  return rows.map(line => {
    const match = /^\s*"[^"]+":\s*\{:hex,\s*:([a-zA-Z0-9_]+),\s*"([0-9][^"]*)"/.exec(line);
    if (match) return {name:match[1], version:match[2], query:{package:{ecosystem:'Hex', name:match[1]}, version:match[2]}};
    const git = /^\s*"([^"]+)":\s*\{:git,\s*"https:\/\/[^\"]+",\s*"([a-f0-9]{40})"/.exec(line);
    if (git) return {name:git[1], version:git[2], query:{commit:git[2]}};
    throw new Error('Unsupported mix.lock entry requires an adapter');
  });
}

async function json(url: string, data?: unknown): Promise<any> {
  const response = await fetch(url, {signal:AbortSignal.timeout(30000),
    ...(data ? {method:'POST', headers:{'content-type':'application/json'}, body:JSON.stringify(data)} : {})});
  if (!response.ok) throw new Error('Hex advisory coverage unavailable');
  return response.json();
}

export async function auditHex(path: string) {
  const queries = parseHex(readFileSync(path, 'utf8'));
  const batch = await json('https://api.osv.dev/v1/querybatch', {queries:queries.map(item => item.query)});
  if (!Array.isArray(batch.results) || batch.results.length !== queries.length) throw new Error('Incomplete Hex advisory batch');
  const vulnerabilities: Record<string, {severity:string; via:Array<{url:string}>; version:string}> = {};
  for (let i=0; i<queries.length; i++) {
    const result = batch.results[i];
    if (result.error || result.next_page_token) throw new Error('Incomplete paginated Hex result');
    for (const item of result.vulns || []) {
      if (typeof item.id !== 'string') throw new Error('Invalid Hex advisory identity');
      const detail = await json('https://api.osv.dev/v1/vulns/' + encodeURIComponent(item.id));
      if (detail.withdrawn) continue;
      let severity = String(detail.database_specific?.severity || 'unknown').toLowerCase();
      if (severity === 'medium') severity = 'moderate';
      if (!['low','moderate','high','critical'].includes(severity)) severity = 'unknown';
      if (['high','critical','unknown'].includes(severity)) {
        const key = queries[i].name + ':' + item.id;
        vulnerabilities[key] = {severity, version:queries[i].version, via:[{url:'https://osv.dev/vulnerability/' + item.id}]};
      }
    }
  }
  return {packages:queries.length, vulnerabilities};
}
