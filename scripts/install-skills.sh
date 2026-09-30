#!/usr/bin/env bash
# Install this kit's skills for Claude Code (~/.claude/skills) and Codex (~/.codex/skills).
# Existing skills with the same name are left untouched unless --force is given.
set -euo pipefail

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

for dest in "$HOME/.claude/skills" "$HOME/.codex/skills"; do
  mkdir -p "$dest"
  for skill in "$KIT_DIR"/skills/*/; do
    name=$(basename "$skill")
    if [ -e "$dest/$name" ] && [ "$FORCE" -ne 1 ]; then
      echo "skip   $dest/$name (exists; use --force to replace)"
      continue
    fi
    rm -rf "${dest:?}/$name"
    cp -R "$skill" "$dest/$name"
    echo "install $dest/$name"
  done
done
