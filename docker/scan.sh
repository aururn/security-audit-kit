#!/usr/bin/env bash
# Runs inside the scanner image. Target: /src (read-only). Reports: /reports.
# Each tool's result is recorded instead of aborting, so one failure does not hide the rest.
# summary.json: { "<tool>": { "status": "ok"|"skipped"|"error", "count": <int|null>, "report": "<file>", "note": "<text>" } }
set -uo pipefail

SRC=${SCAN_SRC:-/src}
OUT=${SCAN_OUT:-/reports}
RULES_DIR=${SEMGREP_RULES_DIR:-/opt/semgrep-rules}
mkdir -p "$OUT"
SUMMARY_TXT="$OUT/summary.txt"
SUMMARY_JSON="$OUT/summary.json"
echo '{}' > "$SUMMARY_JSON"
: > "$SUMMARY_TXT"

# record <tool> <status> <count|null> <report-file> <note>
record() {
  local tmp
  tmp=$(mktemp)
  jq --arg t "$1" --arg s "$2" --argjson c "$3" --arg r "$4" --arg n "$5" \
    '.[$t] = {status: $s, count: $c, report: $r, note: $n}' "$SUMMARY_JSON" > "$tmp" && mv "$tmp" "$SUMMARY_JSON"
  printf '%-12s %-8s %-6s %s  [t=%ss]\n' "$1" "$2" "$3" "$5" "$SECONDS" | tee -a "$SUMMARY_TXT"
}

# count_json <file> <jq-filter> : prints a number, or null if the file is not valid JSON.
count_json() { jq "$2" "$1" 2>/dev/null || echo null; }

echo "== security-audit-kit scan $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$SUMMARY_TXT"
printf '%-12s %-8s %-6s %s\n' tool status count note | tee -a "$SUMMARY_TXT"

# 1. Secrets in the full git history (values redacted).
if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
  # A shallow clone has only the tip commits, so --all cannot reach older history: a clean
  # result then means "nothing in what was fetched", not "nothing ever committed". Say so.
  gl_note="secrets in git history"
  if [ "$(git -C "$SRC" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    gl_note="secrets in git history (SHALLOW clone: older commits not scanned)"
  fi
  if gitleaks git "$SRC" --log-opts="--all" --redact --no-banner --exit-code 0 \
      --report-format json --report-path "$OUT/gitleaks.json" >"$OUT/gitleaks.log" 2>&1; then
    record gitleaks ok "$(count_json "$OUT/gitleaks.json" length)" gitleaks.json "$gl_note"
  else
    record gitleaks error null gitleaks.log "see gitleaks.log"
  fi
else
  record gitleaks skipped null "" "not a git repository"
fi

# 2. Dependencies: known vulnerabilities and known-malicious packages (MAL-*) from OSV.
osv-scanner scan source -r "$SRC" --format json --output "$OUT/osv.json" >"$OUT/osv.log" 2>&1
case $? in
  0|1) record osv-scanner ok "$(count_json "$OUT/osv.json" '[.results[]?.packages[]?.vulnerabilities[]?] | length')" osv.json "vulnerability entries (incl. MAL-*)" ;;
  128) record osv-scanner skipped null "" "no lockfiles found" ;;
  *) record osv-scanner error null osv.log "see osv.log" ;;
esac

# 3. SAST with the rules baked into the image at build time (reproducible, no network).
semgrep scan --metrics=off --disable-version-check --quiet --json --output "$OUT/semgrep.json" \
  --config "$RULES_DIR" \
  --exclude node_modules --exclude .next --exclude dist --exclude build \
  "$SRC" >"$OUT/semgrep.log" 2>&1
if jq -e '.results | type == "array"' "$OUT/semgrep.json" >/dev/null 2>&1; then
  record semgrep ok "$(count_json "$OUT/semgrep.json" '.results | length')" semgrep.json "SAST findings"
else
  record semgrep error null semgrep.log "see semgrep.log"
fi

# 4. GitHub Actions workflows.
if [ -d "$SRC/.github/workflows" ]; then
  zizmor --offline --format json "$SRC/.github/workflows" >"$OUT/zizmor.json" 2>"$OUT/zizmor.log"
  if [ $? -le 14 ] && jq -e 'type == "array"' "$OUT/zizmor.json" >/dev/null 2>&1; then
    record zizmor ok "$(count_json "$OUT/zizmor.json" length)" zizmor.json "workflow findings"
  else
    record zizmor error null zizmor.log "see zizmor.log"
  fi
  (cd "$SRC" && actionlint -format '{{json .}}') >"$OUT/actionlint.json" 2>"$OUT/actionlint.log"
  if [ $? -le 1 ] && jq -e 'type == "array"' "$OUT/actionlint.json" >/dev/null 2>&1; then
    record actionlint ok "$(count_json "$OUT/actionlint.json" length)" actionlint.json "workflow errors"
  else
    record actionlint error null actionlint.log "see actionlint.log"
  fi
else
  record zizmor skipped null "" "no .github/workflows"
  record actionlint skipped null "" "no .github/workflows"
fi

echo "Reports: $OUT (summary.json, summary.txt). Every hit is a candidate: triage it before reporting." | tee -a "$SUMMARY_TXT"
if jq -e 'any(.[]; .status == "error")' "$SUMMARY_JSON" >/dev/null; then exit 2; fi
