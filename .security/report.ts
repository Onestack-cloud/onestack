import { appendFileSync, readFileSync } from 'node:fs';

const raw = readFileSync('security-report.json', 'utf8');
const report = JSON.parse(raw);
console.log(raw);
if (process.env.GITHUB_STEP_SUMMARY) {
  const code = String.fromCharCode(96).repeat(3);
  const summary = `## Security inventory\n\nState: ${report.state}. Regression gate: ${report.gate}.\n\nA passing gate means no unmitigated introduced high/critical advisory and complete coverage for this repository check; existing findings remain visible below. The full report is also retained in this job's logs.\n\n${code}json\n${raw.slice(0, 850000)}\n${code}\n`;
  appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
}
