#!/usr/bin/env bash
# Bundle the shared files a skill references (principles, checklists, templates) into that
# skill's references/ directory, so an installed skill resolves them without the kit's clone.
# The repository root stays the single source of truth; references/ is generated from it.
#
#   scripts/build-skill-references.sh          sync each skill's references/ with the root sources
#   scripts/build-skill-references.sh --check  only verify; exit 1 if any copy is missing, stale,
#                                              or left over from a source that no longer exists
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
  "security-audit|templates/scope.md|templates/scope.md"
  "cost-abuse-review|AGENTS.md|principles.md"
  "cost-abuse-review|checklists/cost-and-abuse.md|checklists/cost-and-abuse.md"
  "cost-abuse-review|templates/scope.md|templates/scope.md"
  "security-fix-workflow|templates/issue-security.md|templates/issue-security.md"
  "security-fix-workflow|templates/pull_request.md|templates/pull_request.md"
)

stale=0
EXPECTED=$'\n'   # newline-delimited list of every destination file a mapping produces

# list_files <path> : print every regular file under <path> (a single file prints "."),
# each as a path relative to <path>.
list_files() {
  if [ -d "$1" ]; then (cd "$1" && find . -type f | sed 's|^\./||' | sort); else echo "."; fi
}

sync_one() {
  local src=$1 dst=$2 rel s d
  while IFS= read -r rel; do
    if [ "$rel" = "." ]; then s=$src; d=$dst; else s=$src/$rel; d=$dst/$rel; fi
    EXPECTED+="$d"$'\n'
    if [ "$CHECK" -eq 1 ]; then
      if [ ! -f "$d" ]; then echo "missing: ${d#"$KIT_DIR"/}"; stale=1
      elif ! cmp -s "$s" "$d"; then echo "stale:   ${d#"$KIT_DIR"/}"; stale=1
      fi
    else
      mkdir -p "$(dirname "$d")"
      cp "$s" "$d"
    fi
  done < <(list_files "$src")
}

for m in "${MAPPINGS[@]}"; do
  IFS="|" read -r skill src dst <<<"$m"
  src="$KIT_DIR/$src"
  dst="$KIT_DIR/skills/$skill/references/$dst"
  [ -e "$src" ] || { echo "source not found: $src" >&2; exit 1; }
  sync_one "$src" "$dst"
done

# Every file under a skill's references/ must be produced by a mapping above. A left-over file
# (its root source was deleted or renamed) is drift too, so reject it in --check and prune it
# otherwise.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$EXPECTED" in
    *$'\n'"$f"$'\n'*) ;;
    *)
      if [ "$CHECK" -eq 1 ]; then echo "orphan:  ${f#"$KIT_DIR"/}"; stale=1
      else echo "pruning ${f#"$KIT_DIR"/}" >&2; rm -f "$f"; fi
      ;;
  esac
done < <(find "$KIT_DIR"/skills/*/references -type f 2>/dev/null | sort)

# Remove directories left empty after pruning (ignore errors; -p stops at the first non-empty).
[ "$CHECK" -eq 0 ] && find "$KIT_DIR"/skills/*/references -type d -empty -delete 2>/dev/null

if [ "$CHECK" -eq 1 ]; then
  if [ "$stale" -ne 0 ]; then
    echo "skill references are out of date. Run scripts/build-skill-references.sh and commit." >&2
    exit 1
  fi
  echo "skill references are up to date."
else
  echo "skill references rebuilt under skills/*/references/."
fi
