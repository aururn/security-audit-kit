#!/usr/bin/env bash
# Install this kit's skills for Claude Code (~/.claude/skills) and Codex (~/.codex/skills).
#   install-skills.sh            install skills (skip ones that already exist)
#   install-skills.sh --force    replace existing skills too
#   install-skills.sh --check    do not install; report which installed skills came from an older
#                                kit commit than this checkout, and how to update. --check only
#                                reports (it ignores --force and writes nothing).
# Each installed skill records the kit commit it came from in a .kit-version file, so --check can
# tell a stale copy from a current one. The file lives only in the installed copy, not in the repo.
set -euo pipefail

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
FORCE=0
CHECK=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --check) CHECK=1 ;;
    *) echo "unknown option: $arg (use --force and/or --check)" >&2; exit 2 ;;
  esac
done

kit_sha=$(git -C "$KIT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)
kit_date=$(git -C "$KIT_DIR" show -s --format=%cs HEAD 2>/dev/null || echo unknown)

DESTS=("$HOME/.claude/skills" "$HOME/.codex/skills")

if [ "$CHECK" -eq 1 ]; then
  found=0
  stale=0
  for dest in "${DESTS[@]}"; do
    for skill in "$KIT_DIR"/skills/*/; do
      name=$(basename "$skill")
      vf="$dest/$name/.kit-version"
      [ -f "$vf" ] || continue
      found=1
      installed=$(head -n1 "$vf" | tr -d '[:space:]')
      if [ "$installed" = "$kit_sha" ]; then
        echo "up to date  $dest/$name ($installed)"
      else
        echo "stale       $dest/$name (installed ${installed:0:12}, kit ${kit_sha:0:12})"
        stale=1
      fi
    done
  done
  if [ "$found" -eq 0 ]; then
    echo "No installed skills carry a .kit-version. Run scripts/install-skills.sh to (re)install."
  elif [ "$stale" -eq 1 ]; then
    echo "Update the stale skills with: scripts/install-skills.sh --force"
  fi
  exit 0
fi

for dest in "${DESTS[@]}"; do
  mkdir -p "$dest"
  for skill in "$KIT_DIR"/skills/*/; do
    name=$(basename "$skill")
    if [ -e "$dest/$name" ] && [ "$FORCE" -ne 1 ]; then
      echo "skip   $dest/$name (exists; use --force to replace)"
      continue
    fi
    rm -rf "${dest:?}/$name"
    cp -R "$skill" "$dest/$name"
    printf '%s\n%s\n' "$kit_sha" "$kit_date" > "$dest/$name/.kit-version"
    echo "install $dest/$name ($kit_sha)"
  done
done
