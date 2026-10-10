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
  # A target-side ignore file suppresses findings; a clean count then is not "nothing to find".
  [ -f "$SRC/.gitleaksignore" ] && gl_note="$gl_note (.gitleaksignore present: some findings suppressed)"
  if gitleaks git "$SRC" --log-opts="--all" --redact --no-banner --exit-code 0 \
      --report-format json --report-path "$OUT/gitleaks.json" >"$OUT/gitleaks.log" 2>&1; then
    record gitleaks ok "$(count_json "$OUT/gitleaks.json" length)" gitleaks.json "$gl_note"
  else
    record gitleaks error null gitleaks.log "see gitleaks.log"
  fi
elif [ -f "$SRC/.git" ]; then
  # A linked worktree (or submodule) has a .git file pointing at git data outside the mount, so
  # its history cannot be read here. Say so instead of looking like a plain non-repository.
  record gitleaks skipped null "" "linked worktree or submodule: git data is outside the mount; scan a mirror clone (git clone --mirror)"
else
  record gitleaks skipped null "" "not a git repository"
fi

# 1b. Optional: also scan the working tree, not just history. Catches secrets in uncommitted or
# gitignored files (e.g. .env.local) that `gitleaks git` never sees. Off by default because
# scanning a checkout is noisy; build output and vendored deps are excluded so it stays usable.
if [ "${SCAN_WORKTREE:-0}" = "1" ] && [ -d "$SRC" ]; then
  wt_cfg="$OUT/.gitleaks-worktree.toml"
  cat > "$wt_cfg" <<'TOML'
title = "worktree"
[extend]
useDefault = true
[[allowlists]]
description = "build output and vendored dependencies"
paths = [
  '''(^|/)node_modules/''',
  '''(^|/)\.next/''',
  '''(^|/)dist/''',
  '''(^|/)build/''',
  '''(^|/)\.git/''',
]
TOML
  if gitleaks dir "$SRC" --config "$wt_cfg" --redact --no-banner --exit-code 0 \
      --report-format json --report-path "$OUT/gitleaks-worktree.json" >"$OUT/gitleaks-worktree.log" 2>&1; then
    record gitleaks-worktree ok "$(count_json "$OUT/gitleaks-worktree.json" length)" gitleaks-worktree.json "secrets in the working tree (build output and vendored deps excluded)"
  else
    record gitleaks-worktree error null gitleaks-worktree.log "see gitleaks-worktree.log"
  fi
fi

# 2. Dependencies: known vulnerabilities and known-malicious packages (MAL-*) from OSV.
osv_note="vulnerability entries (incl. MAL-*)"
if find "$SRC" -name osv-scanner.toml -not -path '*/node_modules/*' -print -quit 2>/dev/null | grep -q .; then
  osv_note="$osv_note (osv-scanner.toml present: some vulns may be ignored)"
fi
osv-scanner scan source -r "$SRC" --format json --output "$OUT/osv.json" >"$OUT/osv.log" 2>&1
osv_rc=$?
if [ "$osv_rc" -le 1 ]; then
  # Triage starts from what ships, so say how many entries are in dev-only dependencies. The count
  # itself stays the total: a dev tool can still run on a developer's machine or in CI.
  # - package-lock.json and npm-shrinkwrap.json: read npm's own flags. osv-scanner reports both a
  #   dev-only optional package (dev + optional) and a devOptional one (in the dev tree and in the
  #   production optional tree, so it can ship) as ["dev", "optional"]; only the lockfile tells them
  #   apart. A name@version is dev-only when every lockfile entry for it has "dev": true. The name
  #   is the real package name, as osv-scanner reports it, also for an alias (v2/v3: the entry's
  #   "name"; v1: a "npm:<name>@<version>" version). Lockfile v2/v3 lists entries under "packages";
  #   v1 only nests them under "dependencies".
  # - other lockfiles: osv-scanner's groups, exactly ["dev"]. pnpm-lock.yaml has none (see below).
  npm_lock='endswith("package-lock.json") or endswith("npm-shrinkwrap.json")'
  osv_dev=$(jq "[.results[]? | select((.source.path // \"\") | ($npm_lock) | not)
    | .packages[]? | select((.dependency_groups // []) == [\"dev\"]) | .vulnerabilities[]?] | length" "$OUT/osv.json" 2>/dev/null)
  case "$osv_dev" in ''|*[!0-9]*) osv_dev=0 ;; esac
  while IFS= read -r lock; do
    [ -f "$lock" ] || continue
    devset=$(jq -c '
      def v2: .packages | to_entries[] | select(.key != "")
        | {k: ((.value.name // (.key | sub("^.*node_modules/"; ""))) + "@" + (.value.version // "")),
           dev: (.value.dev == true)};
      def v1: [.. | objects | select(has("dependencies")) | .dependencies | objects | to_entries[]] | .[]
        | {k: (if (.value.version // "" | startswith("npm:")) then (.value.version | ltrimstr("npm:"))
               else .key + "@" + (.value.version // "") end),
           dev: (.value.dev == true)};
      [if has("packages") then v2 else v1 end] | group_by(.k) | map(select(all(.dev)) | .[0].k)' "$lock" 2>/dev/null) || continue
    n=$(jq --arg lock "$lock" --argjson devset "$devset" '[.results[]? | select(.source.path == $lock)
      | .packages[]? | select((.package.name + "@" + .package.version) as $k | $devset | index($k))
      | .vulnerabilities[]?] | length' "$OUT/osv.json" 2>/dev/null)
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    osv_dev=$((osv_dev + n))
  done < <(jq -r "[.results[]?.source.path // empty | select($npm_lock)] | unique | .[]" "$OUT/osv.json" 2>/dev/null)
  [ "$osv_dev" -gt 0 ] && osv_note="$osv_note ($osv_dev in dev-only dependencies)"
  if jq -e '[.results[]? | select((.source.path // "") | endswith("pnpm-lock.yaml")) | .packages[]?.vulnerabilities[]?] | length > 0' "$OUT/osv.json" >/dev/null 2>&1; then
    osv_note="$osv_note (pnpm-lock.yaml: dev and runtime dependencies not told apart)"
  fi
fi
case $osv_rc in
  0|1) record osv-scanner ok "$(count_json "$OUT/osv.json" '[.results[]?.packages[]?.vulnerabilities[]?] | length')" osv.json "$osv_note" ;;
  128) record osv-scanner skipped null "" "no lockfiles found" ;;
  *) record osv-scanner error null osv.log "see osv.log" ;;
esac

# 3. SAST with the rules baked into the image at build time (reproducible, no network).
semgrep scan --metrics=off --disable-version-check --quiet --json --output "$OUT/semgrep.json" \
  --config "$RULES_DIR" \
  --exclude node_modules --exclude .next --exclude dist --exclude build \
  "$SRC" >"$OUT/semgrep.log" 2>&1
if jq -e '.results | type == "array"' "$OUT/semgrep.json" >/dev/null 2>&1; then
  sg_note="SAST findings"
  # Files semgrep could not parse or that timed out are reported in .errors, not .results, so a
  # low finding count can hide unscanned code. Drop only the benign partial-parse warnings
  # (semgrep's shell/Dockerfile grammars are incomplete and always emit these); a full syntax
  # failure, timeout or any higher-level error is still counted, whatever the file type.
  # Drop only the verified parser noise: a warn-level PartialParsing on a shell script or
  # Dockerfile (semgrep's grammars for those are incomplete). Keep everything else, including a
  # PartialParsing on a .js/.ts file (part of application code went unanalyzed) and any Syntax
  # error, timeout or higher-level error on any file. .type is an array ["PartialParsing", …] for
  # partial parses but a plain string ("Syntax error", …) otherwise, so normalise it first.
  errs=$(jq '[ .errors[]?
    | (if (.type | type) == "array" then .type[0] else .type end) as $t
    | ((.path // "") | ascii_downcase) as $p
    | select( ( ($t == "PartialParsing") and (.level == "warn")
                and ( ($p|endswith(".sh")) or ($p|endswith(".bash")) or ($p|endswith("dockerfile")) )
              ) | not )
  ] | length' "$OUT/semgrep.json" 2>/dev/null); case "$errs" in ''|*[!0-9]*) errs=0 ;; esac
  [ "$errs" -gt 0 ] && sg_note="$sg_note ($errs scan errors: some files not analyzed)"
  [ -f "$SRC/.semgrepignore" ] && sg_note="$sg_note (.semgrepignore present: some paths skipped)"
  # The rules are baked in at image build time (docs/decisions/0004); flag a stale image so a
  # scan with months-old rules is not mistaken for an up-to-date one. Rebuild to refresh.
  max_age=${SEMGREP_RULES_MAX_AGE_DAYS:-30}
  if [ -f "$RULES_DIR/FETCHED_AT" ]; then
    fetched_epoch=$(date -d "$(cat "$RULES_DIR/FETCHED_AT")" +%s 2>/dev/null || echo "")
    if [ -n "$fetched_epoch" ]; then
      age_days=$(( ( $(date -u +%s) - fetched_epoch ) / 86400 ))
      [ "$age_days" -gt "$max_age" ] && sg_note="$sg_note (rules ${age_days}d old: rebuild image to refresh)"
    fi
  fi
  record semgrep ok "$(count_json "$OUT/semgrep.json" '.results | length')" semgrep.json "$sg_note"
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
