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

# Split the URL ourselves and refuse anything ambiguous: a URL whose authority carries userinfo
# (http://localhost:1@evil.example) names localhost but connects to evil.example.
# The message never repeats the URL: it may carry credentials.
refuse() { echo "Refusing to scan: $1" >&2; exit 2; }
case "$URL" in *://*) ;; *) refuse "not an absolute http(s) URL" ;; esac
SCHEME=$(printf '%s' "${URL%%://*}" | tr '[:upper:]' '[:lower:]')
case "$SCHEME" in http|https) ;; *) refuse "only http and https are supported" ;; esac
REST=${URL#*://}
AUTHORITY=${REST%%[/?#]*}
PATH_PART=${REST#"$AUTHORITY"}
case "$AUTHORITY" in *@*) refuse "credentials (user@host) in the URL are not allowed" ;; esac
case "$AUTHORITY" in
  \[*\]*) HOST=${AUTHORITY%%]*}]; PORT_PART=${AUTHORITY#"$HOST"} ;;   # [::1]:3000
  *) HOST=${AUTHORITY%%:*}; PORT_PART=${AUTHORITY#"$HOST"} ;;
esac
HOST_LC=$(printf '%s' "$HOST" | tr '[:upper:]' '[:lower:]')
[ -n "$HOST_LC" ] || refuse "no host"
case "$PORT_PART" in
  '') ;;
  :*[!0-9]*|:) refuse "invalid port" ;;
  :*) ;;
  *) refuse "invalid authority" ;;
esac

case "$HOST_LC" in
  localhost|127.0.0.1|'[::1]')
    # Inside the container, the host machine is host.docker.internal.
    TARGET_URL="$SCHEME://host.docker.internal$PORT_PART$PATH_PART" ;;
  host.docker.internal)
    TARGET_URL="$SCHEME://$HOST_LC$PORT_PART$PATH_PART" ;;
  *)
    if [ "${DAST_I_OWN_THIS_TARGET:-}" != "1" ]; then
      refuse "non-local host '$HOST_LC'. Set DAST_I_OWN_THIS_TARGET=1 for a staging host you own."
    fi
    TARGET_URL="$SCHEME://$HOST_LC$PORT_PART$PATH_PART" ;;
esac

# The ZAP image runs as uid 1000; on Linux it cannot write reports into a bind mount owned by
# another uid, so run as the caller (same reasoning as docs/decisions/0001). A caller uid that is
# absent from the image's passwd (e.g. GitHub Actions' 1001) has no home, so point both Python
# (HOME) and the ZAP JVM (user.home) at a writable dir, or ZAP tries to write /zap/?/.ZAP and
# fails before producing reports. Docker Desktop (Windows/macOS) maps bind mounts writable for
# any uid. No -t: there is no TTY under CI.
RUN_ARGS=(--rm --add-host=host.docker.internal:host-gateway -v "$REPORTS:/zap/wrk")
if [ "$(uname -s)" = "Linux" ]; then
  RUN_ARGS+=(--user "$(id -u):$(id -g)" -e HOME=/tmp -e JAVA_TOOL_OPTIONS=-Duser.home=/tmp)
fi

# zap-baseline.py exits 0 (no WARN or FAIL alert), 1 (FAIL-level alert) or 2 (WARN-level alert)
# when the scan ran, and only other codes when it could not run. Do not pass -I: it turns WARN into
# exit 0, and every rule is WARN by default, so a scan with findings would read as clean. But `docker run` itself can exit
# 1 without ever starting ZAP (daemon unreachable, image pull failure), so a non-zero code alone
# cannot be read as scan findings. Clear any old report first and require a fresh one: only then
# are findings (not a tool failure) reported, so a completed scan is never mistaken for an error
# and an error is never mistaken for a completed scan.
rm -f "$REPORTS/zap-baseline.json" "$REPORTS/zap-baseline.html"
rc=0
MSYS_NO_PATHCONV=1 docker run "${RUN_ARGS[@]}" \
  "$ZAP_IMAGE" zap-baseline.py -t "$TARGET_URL" -J zap-baseline.json -r zap-baseline.html || rc=$?
if [ ! -f "$REPORTS/zap-baseline.json" ]; then
  echo "ZAP baseline did not run: no report was produced (docker/zap exit $rc)." >&2
  exit 2
fi
# 0/1/2 mean the scan finished (clean / FAIL alerts / WARN alerts); any other code is a ZAP tool
# failure (e.g. 3), which a produced report does not make trustworthy — treat it as an error.
case $rc in
  0) echo "ZAP baseline completed: no WARN or FAIL alerts." ;;
  1) echo "ZAP baseline completed: FAIL-level alerts reported — triage the report." ;;
  2) echo "ZAP baseline completed: WARN-level alerts reported — triage the report." ;;
  *) echo "ZAP baseline failed (exit $rc); the scan did not complete, do not trust the report." >&2; exit 2 ;;
esac
echo "Reports: $REPORTS/zap-baseline.json and zap-baseline.html"
