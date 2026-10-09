#!/usr/bin/env bash
# Bundle the shared files a skill references (principles, checklists, templates) into that
# skill's references/ directory, so an installed skill resolves them without the kit's clone.
# The repository root stays the single source of truth; references/ is generated from it.
#
#   scripts/build-skill-references.sh          copy the shared files into each skill's references/
#   scripts/build-skill-references.sh --check  only verify; exit 1 if any copy is missing or stale
#
# Add a new mapping line below when a skill starts referencing a shared file.
set -euo pipefail

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# <skill>|<source path under KIT_DIR, file or dir>|<destination under skills/<skill>/references/>
MAPPINGS=(
  "security-audit|AGENTS.md|principles.md"
  "security-audit|checklists|checklists"
  "cost-abuse-review|checklists/cost-and-abuse.md|checklists/cost-and-abuse.md"
  "security-fix-workflow|templates/issue-security.md|templates/issue-security.md"
  "security-fix-workflow|templates/pull_request.md|templates/pull_request.md"
)

stale=0

# list_files <path> : print every regular file under <path> (a single file prints itself),
# each as a path relative to <path> ("." for a lone file).
list_files() {
  if [ -d "$1" ]; then (cd "$1" && find . -type f | sed 's|^\./||' | sort); else echo "."; fi
}

check_one() {
  local src=$1 dst=$2 rel s d
  while IFS= read -r rel; do
    if [ "$rel" = "." ]; then s=$src; d=$dst; else s=$src/$rel; d=$dst/$rel; fi
    if [ ! -f "$d" ]; then echo "missing: ${d#"$KIT_DIR"/}"; stale=1
    elif ! cmp -s "$s" "$d"; then echo "stale:   ${d#"$KIT_DIR"/}"; stale=1
    fi
  done < <(list_files "$src")
}

copy_one() {
  local src=$1 dst=$2 rel s d
  while IFS= read -r rel; do
    if [ "$rel" = "." ]; then s=$src; d=$dst; else s=$src/$rel; d=$dst/$rel; fi
    mkdir -p "$(dirname "$d")"
    cp "$s" "$d"
  done < <(list_files "$src")
}

for m in "${MAPPINGS[@]}"; do
  IFS="|" read -r skill src dst <<<"$m"
  src="$KIT_DIR/$src"
  dst="$KIT_DIR/skills/$skill/references/$dst"
  [ -e "$src" ] || { echo "source not found: $src" >&2; exit 1; }
  if [ "$CHECK" -eq 1 ]; then check_one "$src" "$dst"; else copy_one "$src" "$dst"; fi
done

if [ "$CHECK" -eq 1 ]; then
  if [ "$stale" -ne 0 ]; then
    echo "skill references are out of date. Run scripts/build-skill-references.sh and commit." >&2
    exit 1
  fi
  echo "skill references are up to date."
else
  echo "skill references rebuilt under skills/*/references/."
fi
