#!/usr/bin/env bash
# Canary test: every scanner in the kit must flag a small, deliberately unsafe repository.
# "Scanning the kit finds 0 issues" also passes when a scanner silently stops working;
# this test fails in that case.
#
# Usage: tests/run-canary.sh [report-dir]
#   report-dir  where the scan reports go (default: a new temporary directory, kept and printed)
# Env:
#   CANARY_SKIP  space-separated fixture names to leave out (package-lock, workflow, server,
#                secret). Only for checking that the test fails when a scanner has nothing to find.
set -euo pipefail

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
FIXTURES_DIR="$KIT_DIR/tests/canary"
TOOLS=(gitleaks osv-scanner semgrep zizmor actionlint)

if [ $# -ge 1 ]; then
  REPORTS=$1
  mkdir -p "$REPORTS"
else
  REPORTS=$(mktemp -d "${TMPDIR:-/tmp}/canary-reports.XXXXXX")
fi
REPORTS=$(cd "$REPORTS" && pwd)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/canary-repo.XXXXXX")
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

skipped() { case " ${CANARY_SKIP:-} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# place <name> <template> <path-in-repo>
place() {
  if skipped "$1"; then
    echo "canary: leaving out $1 (CANARY_SKIP)"
    return 0
  fi
  mkdir -p "$(dirname "$WORK/$3")"
  cp "$FIXTURES_DIR/$2" "$WORK/$3"
}

place package-lock package-lock.json.fixture package-lock.json
place workflow workflow.yml.fixture .github/workflows/canary.yml
place server server.js.fixture app/server.js

# A fake GitHub token, generated now so that no token-shaped string is ever committed to the kit.
if ! skipped secret; then
  token=""
  while [ ${#token} -lt 36 ]; do
    token+=$(head -c 256 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')
  done
  mkdir -p "$WORK/config"
  printf 'GITHUB_TOKEN=ghp_%s\n' "${token:0:36}" > "$WORK/config/.env.production"
  unset token
else
  echo "canary: leaving out secret (CANARY_SKIP)"
fi
echo "canary: placeholder" > "$WORK/README.md"

# Commit everything so gitleaks' history scan sees it. Identity and signing are local to this
# throwaway repository only.
git -C "$WORK" init -q
git -C "$WORK" config user.name "canary"
git -C "$WORK" config user.email "canary@example.invalid"
git -C "$WORK" config commit.gpgsign false
git -C "$WORK" config core.autocrlf false
git -C "$WORK" add -A
git -C "$WORK" commit -q -m "canary fixtures"

scan_status=0
bash "$KIT_DIR/scripts/run-scan.sh" "$WORK" "$REPORTS" || scan_status=$?
echo "canary: run-scan.sh exited with $scan_status"

SUMMARY="$REPORTS/summary.json"
if [ ! -s "$SUMMARY" ]; then
  echo "canary: FAIL - $SUMMARY was not written" >&2
  exit 1
fi

# json <jq-filter> <node-expression> < file : evaluates against the JSON on stdin (variable d in
# node). Uses jq when present (CI), otherwise node (Windows hosts without jq).
if command -v jq >/dev/null 2>&1; then
  json() { jq -r "$1"; }
elif command -v node >/dev/null 2>&1; then
  json() {
    node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{const d=JSON.parse(s);const v=eval(process.argv[1]);console.log(v===undefined||v===null?"null":v);});' "$2"
  }
else
  echo "canary: FAIL - need jq or node to read summary.json" >&2
  exit 1
fi

# rules <tool> : distinct rule ids that fired, for the log (never the matched values).
rules() {
  local file
  file=$(json ".\"$1\".report // \"\"" "d[\"$1\"]?.report||\"\"" < "$SUMMARY")
  if [ -z "$file" ] || [ ! -s "$REPORTS/$file" ]; then echo "-"; return 0; fi
  case $1 in
    gitleaks) json '[.[].RuleID] | unique | join(",")' '[...new Set(d.map(x=>x.RuleID))].sort().join(",")' ;;
    osv-scanner) json '[.results[]?.packages[]?.vulnerabilities[]?.id] | unique | join(",")' \
      '[...new Set((d.results||[]).flatMap(r=>(r.packages||[]).flatMap(p=>(p.vulnerabilities||[]).map(v=>v.id))))].sort().join(",")' ;;
    semgrep) json '[.results[].check_id | split(".") | last] | unique | join(",")' \
      '[...new Set(d.results.map(x=>x.check_id.split(".").pop()))].sort().join(",")' ;;
    zizmor) json '[.[].ident] | unique | join(",")' '[...new Set(d.map(x=>x.ident))].sort().join(",")' ;;
    actionlint) json '[.[].kind] | unique | join(",")' '[...new Set(d.map(x=>x.kind))].sort().join(",")' ;;
  esac < "$REPORTS/$file"
}

failed=0
printf '\n%-12s %-8s %-6s %-6s %s\n' tool status count result rules
for tool in "${TOOLS[@]}"; do
  status=$(json ".\"$tool\".status // \"missing\"" "d[\"$tool\"]?.status??\"missing\"" < "$SUMMARY")
  count=$(json ".\"$tool\".count // \"null\"" "d[\"$tool\"]?.count" < "$SUMMARY")
  result=PASS
  if [ "$status" != ok ] || ! [[ $count =~ ^[0-9]+$ ]] || [ "$count" -lt 1 ]; then
    result=FAIL
    failed=1
  fi
  printf '%-12s %-8s %-6s %-6s %s\n' "$tool" "$status" "$count" "$result" "$(rules "$tool")"
done

# The fake token must be caught by the GitHub token rule specifically, not by some other hit.
if ! skipped secret; then
  pat_hits=0
  if [ -s "$REPORTS/gitleaks.json" ]; then
    pat_hits=$(json '[.[] | select(.RuleID == "github-pat")] | length' \
      'd.filter(x=>x.RuleID==="github-pat").length' < "$REPORTS/gitleaks.json")
  fi
  if [ "$pat_hits" -ge 1 ]; then
    echo "gitleaks github-pat rule matched the fake token: PASS"
  else
    echo "gitleaks github-pat rule did not match the fake token: FAIL"
    failed=1
  fi
fi

# semgrep also flags the workflow and the token file; require a hit in the JavaScript fixture so
# that the JavaScript rulesets are proven to be loaded as well.
if ! skipped server; then
  js_hits=0
  if [ -s "$REPORTS/semgrep.json" ]; then
    js_hits=$(json '[.results[]? | select(.path | endswith("app/server.js"))] | length'       '(d.results||[]).filter(x=>x.path.endsWith("app/server.js")).length' < "$REPORTS/semgrep.json")
  fi
  if [ "$js_hits" -ge 1 ]; then
    echo "semgrep flagged app/server.js ($js_hits findings): PASS"
  else
    echo "semgrep did not flag app/server.js: FAIL"
    failed=1
  fi
fi

# The workflow fixture has a script semgrep can only partly parse as Bash. That is parser noise,
# not unscanned code, so it must not show up as "scan errors" in the note.
if ! skipped workflow; then
  sg_note=$(json '.semgrep.note // ""' 'd.semgrep?.note??""' < "$SUMMARY")
  case "$sg_note" in
    *"scan errors"*)
      echo "semgrep note reports scan errors for the canary ($sg_note): FAIL"
      failed=1 ;;
    *) echo "semgrep note has no scan errors: PASS" ;;
  esac
fi

echo "Reports: $REPORTS"
if [ "$failed" -ne 0 ]; then
  echo "canary: FAIL - see the FAIL lines above" >&2
  exit 1
fi
echo "canary: PASS - every scanner flagged the canary repository"
