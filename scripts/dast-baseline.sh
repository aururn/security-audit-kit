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

MSYS_NO_PATHCONV=1 docker run --rm -t \
  --add-host=host.docker.internal:host-gateway \
  -v "$REPORTS:/zap/wrk" \
  "$ZAP_IMAGE" zap-baseline.py -t "$TARGET_URL" -J zap-baseline.json -r zap-baseline.html -I
