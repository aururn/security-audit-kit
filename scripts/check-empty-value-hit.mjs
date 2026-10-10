// Triage for a gitleaks generic-api-key hit whose StartLine and EndLine differ, in a dotenv file:
// is StartLine an empty NAME= whose value the rule took from the next setting? Prints one of two
// fixed phrases and never the lines, because the next line may hold a real credential.
//   ask the user  StartLine is an empty NAME= and the next line starts a NAME_LIKE_THIS= setting
//   real          anything else
// The commit and the file name are read from the report, never typed into a command: a file name
// in an audited repository can contain shell syntax.
// Usage: node check-empty-value-hit.mjs <gitleaks report.json> <index of the hit, from 0> <scanned dir>
//   For gitleaks-worktree.json (no commit), the file is read from the scanned directory on disk.
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import process from 'node:process'

const [report, index, dir] = process.argv.slice(2)
if (!report || !/^\d+$/.test(index ?? '') || !dir) {
  console.error('usage: node check-empty-value-hit.mjs <gitleaks report.json> <index> <scanned dir>')
  process.exit(2)
}
const hit = JSON.parse(readFileSync(report, 'utf8'))[Number(index)]
if (!hit) {
  console.error(`no hit at index ${index}`)
  process.exit(2)
}
if (hit.RuleID !== 'generic-api-key' || hit.StartLine === hit.EndLine) {
  console.log('real')
  process.exit(0)
}

let text
try {
  text = hit.Commit
    ? execFileSync('git', ['-C', dir, 'show', `${hit.Commit}:${hit.File}`],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 256 * 1024 * 1024 })
    // The scanner saw the directory at /src.
    : readFileSync(join(dir, hit.File.replace(/^\/src\//, '')), 'utf8')
} catch {
  console.error('could not read the file the hit came from')
  process.exit(1)
}
const lines = text.split(/\r?\n/)
const emptyName = /^[A-Za-z_][A-Za-z0-9_]*=[ \t]*$/.test(lines[hit.StartLine - 1] ?? '')
const nextSetting = /^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+=/.test(lines[hit.StartLine] ?? '')
console.log(emptyName && nextSetting ? 'ask the user' : 'real')
