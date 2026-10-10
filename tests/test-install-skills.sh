#!/usr/bin/env bash
# Tests for scripts/install-skills.sh in a throwaway HOME (the real ~/.claude and ~/.codex are
# never touched):
#   - every skill lands in both ~/.claude/skills and ~/.codex/skills with its references/
#   - .kit-version records this checkout's commit (line 1) and its path (line 3), and line 3 finds
#     scripts/run-scan.sh, which is how an installed skill locates the scanner
#   - a second run skips existing skills; --force replaces them
#   - --check reports up to date, stale (older commit) and untracked (no .kit-version), and writes
#     nothing
# Usage: tests/test-install-skills.sh
set -euo pipefail

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INSTALL="$KIT_DIR/scripts/install-skills.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/install-skills.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; failed=1; }

SKILLS=()
for d in "$KIT_DIR"/skills/*/; do SKILLS+=("$(basename "$d")"); done
DESTS=("$HOME/.claude/skills" "$HOME/.codex/skills")
kit_sha=$(git -C "$KIT_DIR" rev-parse HEAD)

# Nothing installed yet.
OUT=$("$INSTALL" --check)
if [[ $OUT == *"No skills are installed"* ]] && [ ! -e "$HOME/.claude" ]; then
  pass "--check with nothing installed says so and writes nothing"
else
  fail "--check with nothing installed: $OUT"
fi

# Fresh install.
"$INSTALL" >/dev/null
for dest in "${DESTS[@]}"; do
  for s in "${SKILLS[@]}"; do
    d="$dest/$s"
    # The whole skill directory, references/ and helper scripts included, must be an exact copy;
    # .kit-version is the only file the installer adds.
    if [ -f "$d/SKILL.md" ] && diff -r --exclude=.kit-version "$KIT_DIR/skills/$s" "$d" >/dev/null; then
      pass "installed $d (exact copy, references included)"
    else
      fail "not installed or differs from skills/$s: $d"
    fi
    vf="$d/.kit-version"
    if [ -f "$vf" ] && [ "$(sed -n 1p "$vf")" = "$kit_sha" ] && [ -f "$(sed -n 3p "$vf")/scripts/run-scan.sh" ]; then
      pass "$s .kit-version: commit and kit path (finds run-scan.sh)"
    else
      fail "$s .kit-version wrong: $(tr '\n' ' ' < "$vf" 2>/dev/null || echo missing)"
    fi
  done
done
if [ -f "$HOME/.claude/skills/security-audit/references/principles.md" ] \
  && [ -f "$HOME/.claude/skills/security-audit/references/checklists/web-api.md" ]; then
  pass "skills carry their references/"
else
  fail "references/ missing from the installed security-audit skill"
fi

OUT=$("$INSTALL" --check)
n=$(grep -c '^up to date' <<<"$OUT" || true)
if [ "$n" -eq $(( ${#SKILLS[@]} * ${#DESTS[@]} )) ] && [[ $OUT != *stale* ]]; then
  pass "--check reports all $n installed skills up to date"
else
  fail "--check after install: $OUT"
fi

# A second run without --force keeps what is there.
marker="$HOME/.claude/skills/${SKILLS[0]}/local-note"
echo keep > "$marker"
OUT=$("$INSTALL")
if [ -f "$marker" ] && [[ $OUT == *"skip"* ]]; then
  pass "a second run skips existing skills"
else
  fail "a second run replaced an existing skill: $OUT"
fi

# Stale (installed from an older commit), checked on its own so that each kind must trigger the
# --force hint by itself.
snapshot() { (cd "$HOME" && find . -type f | sort | while IFS= read -r f; do cksum "$f"; done | cksum); }
stale_dir="$HOME/.claude/skills/${SKILLS[0]}"
sed -i.bak '1s/.*/0000000000000000000000000000000000000000/' "$stale_dir/.kit-version" && rm -f "$stale_dir/.kit-version.bak"
before=$(snapshot)
OUT=$("$INSTALL" --check)
after=$(snapshot)
if [[ $OUT == *"stale       $stale_dir"* ]] && [[ $OUT == *"--force"* ]] && [ "$before" = "$after" ]; then
  pass "--check reports a stale skill, suggests --force, writes nothing"
else
  fail "--check with a stale skill: $OUT"
fi
"$INSTALL" --force >/dev/null

# Untracked (installed before version tracking), on its own.
untracked_dir="$HOME/.codex/skills/${SKILLS[0]}"
rm -f "$untracked_dir/.kit-version"
OUT=$("$INSTALL" --check)
if [[ $OUT == *"untracked   $untracked_dir"* ]] && [[ $OUT == *"--force"* ]] && ! grep -q '^stale' <<<"$OUT"; then
  pass "--check reports an untracked skill and suggests --force"
else
  fail "--check with an untracked skill: $OUT"
fi
echo keep > "$marker"

# --force replaces them.
"$INSTALL" --force >/dev/null
OUT=$("$INSTALL" --check)
if [ ! -f "$marker" ] && [[ $OUT != *stale* ]] && [[ $OUT != *untracked* ]]; then
  pass "--force replaces existing skills and brings them up to date"
else
  fail "--force: $OUT"
fi

set +e
"$INSTALL" --bogus >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 2 ]; then pass "an unknown option exits 2"; else fail "unknown option exited $rc"; fi

if [ "$failed" -ne 0 ]; then echo "install-skills test: FAIL" >&2; exit 1; fi
echo "install-skills test: PASS"
