#!/usr/bin/env bash
# Runs inside the scanner image. Target: /src (read-only). Reports: /reports.
# Each tool's exit status is recorded instead of aborting, so one finding does not hide the rest.
set -uo pipefail

SRC=/src
OUT=/reports
mkdir -p "$OUT"
SUMMARY="$OUT/summary.txt"
: > "$SUMMARY"

record() { printf '%-14s %s  [t=%ss]\n' "$1" "$2" "$SECONDS" | tee -a "$SUMMARY"; }

echo "== security-audit-kit scan: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$SUMMARY"

# 1. Secrets in the full git history (values redacted).
if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
  gitleaks git "$SRC" --log-opts="--all" --redact --no-banner --exit-code 0 \
    --report-format json --report-path "$OUT/gitleaks-history.json" >/dev/null 2>&1
  record gitleaks "$(jq length "$OUT/gitleaks-history.json" 2>/dev/null || echo error) hit(s) in history -> gitleaks-history.json"
else
  record gitleaks "skipped (not a git repository)"
fi

# 2. Dependencies: known vulnerabilities and known-malicious packages (MAL-*) from OSV.
osv-scanner scan source -r "$SRC" --format json --output "$OUT/osv.json" >/dev/null 2>&1
case $? in
  0) record osv-scanner "no known vulnerabilities -> osv.json" ;;
  1) record osv-scanner "$(jq '[.results[]?.packages[]?.vulnerabilities[]?] | length' "$OUT/osv.json") vulnerability entries -> osv.json" ;;
  128) record osv-scanner "no lockfiles found" ;;
  *) record osv-scanner "error (see osv.json)" ;;
esac

# 3. SAST. Rules are fetched from the Semgrep registry; no code or metrics are sent.
semgrep scan --metrics=off --quiet --json --output "$OUT/semgrep.json" \
  --config p/default --config p/owasp-top-ten --config p/typescript \
  --config p/react --config p/nextjs --config p/nodejsscan \
  --exclude node_modules --exclude .next --exclude dist --exclude build \
  "$SRC" >/dev/null 2>&1
record semgrep "$(jq '.results | length' "$OUT/semgrep.json" 2>/dev/null || echo error) finding(s) -> semgrep.json"

# 4. GitHub Actions workflows.
if [ -d "$SRC/.github/workflows" ]; then
  zizmor --offline --format json "$SRC/.github/workflows" > "$OUT/zizmor.json" 2>/dev/null
  record zizmor "$(jq length "$OUT/zizmor.json" 2>/dev/null || echo error) finding(s) -> zizmor.json"
  (cd "$SRC" && actionlint -no-color) > "$OUT/actionlint.txt" 2>&1
  record actionlint "$(grep -c . "$OUT/actionlint.txt") line(s) -> actionlint.txt"
else
  record zizmor "skipped (no .github/workflows)"
  record actionlint "skipped (no .github/workflows)"
fi

echo "Reports written to $OUT. Every hit is a candidate: triage it before reporting." | tee -a "$SUMMARY"
