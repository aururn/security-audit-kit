#!/usr/bin/env bash
# Build the scanner image (if needed) and scan a local repository.
# Usage: scripts/run-scan.sh <target-dir> [report-dir]
# The target is mounted read-only; reports are written to <report-dir> (default ./reports).
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <target-dir> [report-dir]" >&2
  exit 1
fi

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
REPORTS=${2:-./reports}
mkdir -p "$REPORTS"

# Docker needs host paths. Git Bash's /c/... form would be resolved inside Docker's VM.
host_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$(cd "$1" && pwd)"; else (cd "$1" && pwd); fi
}
TARGET=$(host_path "$1")
REPORTS=$(host_path "$REPORTS")
IMAGE=security-audit-kit:local

docker build -q -t "$IMAGE" "$KIT_DIR/docker" >/dev/null

# With all capabilities dropped, root cannot write into a directory owned by someone else.
# On Linux, run as the calling user so the report directory is writable. Docker Desktop
# (Windows/macOS) maps bind mounts so that root inside the container can write.
USER_ARGS=()
if [ "$(uname -s)" = "Linux" ]; then
  USER_ARGS=(--user "$(id -u):$(id -g)" -e HOME=/tmp)
fi

# Git Bash on Windows rewrites /src-style arguments; keep them as container paths.
MSYS_NO_PATHCONV=1 docker run --rm \
  --cap-drop ALL --security-opt no-new-privileges \
  ${USER_ARGS[@]+"${USER_ARGS[@]}"} \
  -v "$TARGET:/src:ro" \
  -v "$REPORTS:/reports" \
  "$IMAGE"
