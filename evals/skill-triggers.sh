#!/usr/bin/env bash
# Which skill does Claude Code pick for a request? Loads this kit as a plugin for the session only
# (--plugin-dir; nothing is installed) and allows only the Skill tool, so each run stops right
# after the choice. Uses the caller's Claude Code login and costs a little usage per case, so it is
# not run in CI. Run it after changing a skill's description.
# Usage: evals/skill-triggers.sh <target-repo-dir>
set -uo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <target-repo-dir>" >&2
  exit 1
fi
KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
command -v cygpath >/dev/null 2>&1 && KIT_DIR=$(cygpath -m "$KIT_DIR")
TARGET=$1
OUT=$(mktemp -d "${TMPDIR:-/tmp}/skill-triggers.XXXXXX")

# expected skill | request. "none" means no skill of this kit should be picked.
cases=(
  "security-audit|このリポジトリの脆弱性を調べて"
  "pre-publish-secret-scan|公開する前に秘密情報がないか確認して"
  "security-fix-workflow|見つかった脆弱性を Issue と PR で直して"
  "cost-abuse-review|高額請求にならないか確認して"
  "security-audit|Is this app safe to launch? Check it for security problems."
  "pre-publish-secret-scan|このリポジトリを public にしたい。その前にやることをやって"
  "cost-abuse-review|Vercel の請求が急に増えた。原因になりそうなところを見て"
  "security-audit|AIで作ったアプリなんだけど、このまま公開して大丈夫か見て"
  "none|README の誤字を直して"
)

pass=0
i=0
for c in "${cases[@]}"; do
  i=$((i + 1))
  want=${c%%|*}
  prompt=${c#*|}
  (cd "$TARGET" && timeout 300 claude -p "$prompt" --plugin-dir "$KIT_DIR" --output-format stream-json --verbose \
    --allowedTools Skill \
    --disallowedTools "Bash,PowerShell,Read,Glob,Grep,Edit,Write,NotebookEdit,WebFetch,WebSearch,Agent" \
    >"$OUT/case$i.jsonl" 2>"$OUT/case$i.err")
  # The first Skill tool call, e.g. "security-audit-kit:security-audit"; "none" if there was none.
  got=$(node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean)
    for (const l of lines) {
      let j; try { j = JSON.parse(l) } catch { continue }
      for (const c of j.message?.content ?? []) {
        if (c.type === "tool_use" && c.name === "Skill") { console.log(c.input.skill ?? "?"); process.exit(0) }
      }
    }
    console.log("none")' "$OUT/case$i.jsonl")
  if [ "${got##*:}" = "$want" ]; then
    result=PASS
    pass=$((pass + 1))
  else
    result=FAIL
  fi
  printf '%-4s case%-2s want=%-24s got=%-40s %s\n' "$result" "$i" "$want" "$got" "$prompt"
done
echo "skill triggers: $pass/${#cases[@]} (logs: $OUT)"
[ "$pass" -eq "${#cases[@]}" ]
