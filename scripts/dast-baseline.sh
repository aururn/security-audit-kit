#!/usr/bin/env bash
# Passive OWASP ZAP baseline scan against a LOCAL or staging URL.
# Usage: scripts/dast-baseline.sh <url> [report-dir]
# Refuses non-local hosts unless DAST_I_OWN_THIS_TARGET=1 is set: scanning production or
# someone else's site sends many requests and can trigger paid upstream calls.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <url> [report-dir]" >&2
  exit 1
fi

URL=$1
REPORTS=${2:-./reports}
mkdir -p "$REPORTS"
# Docker needs host paths. Git Bash's /c/... form would be resolved inside Docker's VM.
if command -v cygpath >/dev/null 2>&1; then REPORTS=$(cygpath -m "$(cd "$REPORTS" && pwd)"); else REPORTS=$(cd "$REPORTS" && pwd); fi
ZAP_IMAGE=ghcr.io/zaproxy/zaproxy:2.17.0@sha256:781a2bdaea47324e7bab583e2263f21d257b0aee61ed51521a5be45f5f5081ef

HOST=$(printf '%s' "$URL" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')
case "$HOST" in
  localhost|127.0.0.1|host.docker.internal) ;;
  *)
    if [ "${DAST_I_OWN_THIS_TARGET:-}" != "1" ]; then
      echo "Refusing to scan non-local host '$HOST'. Set DAST_I_OWN_THIS_TARGET=1 for a staging host you own." >&2
      exit 2
    fi
    ;;
esac

# Inside the container, the host machine is host.docker.internal.
TARGET_URL=$(printf '%s' "$URL" | sed -E 's#://(localhost|127\.0\.0\.1)#://host.docker.internal#')

# The ZAP image runs as uid 1000; on Linux it cannot write reports into a bind mount owned by
# another uid, so run as the caller and give ZAP a writable HOME (same reasoning as
# docs/decisions/0001). Docker Desktop (Windows/macOS) maps bind mounts writable for any uid.
# No -t: there is no TTY under CI.
RUN_ARGS=(--rm --add-host=host.docker.internal:host-gateway -v "$REPORTS:/zap/wrk")
if [ "$(uname -s)" = "Linux" ]; then
  RUN_ARGS+=(--user "$(id -u):$(id -g)" -e HOME=/tmp)
fi

# zap-baseline.py exits 0 (no alert over threshold), 1 (FAIL-level alert) or 2 (WARN-level alert)
# when the scan ran, and only other codes when it could not run. Findings are not a script error:
# report them and point at the output, so a completed scan is never mistaken for a tool failure.
rc=0
MSYS_NO_PATHCONV=1 docker run "${RUN_ARGS[@]}" \
  "$ZAP_IMAGE" zap-baseline.py -t "$TARGET_URL" -J zap-baseline.json -r zap-baseline.html -I || rc=$?
case $rc in
  0) echo "ZAP baseline completed: no alert above the threshold." ;;
  1) echo "ZAP baseline completed: FAIL-level alerts reported — triage the report." ;;
  2) echo "ZAP baseline completed: WARN-level alerts reported — triage the report." ;;
  *) echo "ZAP baseline did not complete (docker/zap exit $rc)." >&2; exit 2 ;;
esac
echo "Reports: $REPORTS/zap-baseline.json and zap-baseline.html"
