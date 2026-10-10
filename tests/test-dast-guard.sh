#!/usr/bin/env bash
# Tests for scripts/dast-baseline.sh without Docker or ZAP: a fake `docker` on PATH records the
# arguments it was given and plays ZAP's exit codes.
#   - the host guard refuses URLs that do not point at this machine (or that only look like they do)
#   - the target URL handed to ZAP is rewritten to host.docker.internal
#   - ZAP's exit codes 0/1/2 are reported as a finished scan, and WARN alerts are not called clean
# Usage: tests/test-dast-guard.sh
set -euo pipefail

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dast-guard.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/reports"

# Fake docker: log the args, write a report into the /zap/wrk mount when FAKE_ZAP_REPORT=1, and
# exit with FAKE_ZAP_RC (default 0).
cat > "$WORK/bin/docker" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_DOCKER_LOG"
if [ "${FAKE_ZAP_REPORT:-0}" = "1" ]; then
  prev=""
  for a in "$@"; do
    if [ "$prev" = "-v" ]; then case "$a" in *:/zap/wrk) echo '{}' > "${a%:/zap/wrk}/zap-baseline.json" ;; esac; fi
    prev=$a
  done
fi
exit "${FAKE_ZAP_RC:-0}"
SH
chmod +x "$WORK/bin/docker"
export PATH="$WORK/bin:$PATH" FAKE_DOCKER_LOG="$WORK/docker.log"

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; failed=1; }

# run <url> : runs the script, sets OUT (stdout+stderr) and RC.
run() {
  rm -f "$FAKE_DOCKER_LOG"
  RC=0
  OUT=$(bash "$KIT_DIR/scripts/dast-baseline.sh" "$1" "$WORK/reports" 2>&1) || RC=$?
}

expect_refused() {
  run "$1"
  if [ "$RC" -eq 2 ] && [[ $OUT == *Refusing* ]] && [ ! -f "$FAKE_DOCKER_LOG" ]; then
    pass "refuses $1"
  else
    fail "should refuse $1 (rc=$RC, docker called: $([ -f "$FAKE_DOCKER_LOG" ] && echo yes || echo no))"
  fi
}

# expect_target <url> <target handed to ZAP>
expect_target() {
  FAKE_ZAP_REPORT=1 run "$1"
  if [ -f "$FAKE_DOCKER_LOG" ] && grep -qxF -- "$2" "$FAKE_DOCKER_LOG"; then
    pass "scans $1 as $2"
  else
    fail "should scan $1 as $2 (rc=$RC): $OUT"
  fi
}

expect_refused 'http://localhost:1@evil.example/'
expect_refused 'http://127.0.0.1:80@evil.example'
# Userinfo is refused even for an owned target. Without the userinfo check these would be scanned,
# so they fail if that check goes away (the cases above are also caught by the port check).
DAST_I_OWN_THIS_TARGET=1 expect_refused 'http://localhost@evil.example/'
DAST_I_OWN_THIS_TARGET=1 expect_refused 'https://user@staging.example.com/'
# The refusal must not echo credentials from the URL.
expect_refused 'http://user:s3cr3t-value@localhost:3000/'
if [[ $OUT == *s3cr3t-value* ]]; then fail "refusal message leaks the password"; else pass "refusal message hides the password"; fi
expect_refused 'https://example.com/'
expect_refused 'ftp://localhost/'
expect_refused 'localhost:3000'
expect_refused 'http://localhost.evil.example/'
expect_refused 'http://localhost:3000x/'

expect_target 'http://localhost:3000/a?b=1' 'http://host.docker.internal:3000/a?b=1'
expect_target 'http://LOCALHOST:3000' 'http://host.docker.internal:3000'
expect_target 'http://127.0.0.1/' 'http://host.docker.internal/'
expect_target 'http://[::1]:8080/' 'http://host.docker.internal:8080/'
expect_target 'HTTP://host.docker.internal:3000/' 'http://host.docker.internal:3000/'

DAST_I_OWN_THIS_TARGET=1 expect_target 'https://staging.example.com/' 'https://staging.example.com/'

# -I would turn WARN-level alerts into exit 0 and make a scan with findings look clean.
FAKE_ZAP_REPORT=1 run 'http://localhost:3000'
if grep -qxF -- '-I' "$FAKE_DOCKER_LOG"; then fail "zap-baseline.py must not get -I"; else pass "no -I"; fi

FAKE_ZAP_REPORT=1 FAKE_ZAP_RC=2 run 'http://localhost:3000'
if [ "$RC" -eq 0 ] && [[ $OUT == *WARN-level\ alerts\ reported* ]]; then pass "exit 2 is reported as WARN alerts"; else fail "exit 2 (rc=$RC): $OUT"; fi

FAKE_ZAP_REPORT=1 FAKE_ZAP_RC=0 run 'http://localhost:3000'
if [ "$RC" -eq 0 ] && [[ $OUT == *"no WARN or FAIL alerts"* ]]; then pass "exit 0 is reported as no WARN or FAIL alerts"; else fail "exit 0 (rc=$RC): $OUT"; fi

FAKE_ZAP_REPORT=0 FAKE_ZAP_RC=1 run 'http://localhost:3000'
if [ "$RC" -eq 2 ] && [[ $OUT == *"did not run"* ]]; then pass "no report means the scan did not run"; else fail "no report (rc=$RC): $OUT"; fi

if [ "$failed" -ne 0 ]; then echo "dast guard test: FAIL" >&2; exit 1; fi
echo "dast guard test: PASS"
