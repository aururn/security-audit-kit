#!/usr/bin/env bash
# Update the pinned scanner versions and checksums in docker/Dockerfile and
# docker/requirements.txt.
#   scripts/update-tools.sh          rewrite the pins (review the diff, then rebuild and run the canary)
#   scripts/update-tools.sh --check  only report; exit 1 if an eligible newer version exists
# Only versions published at least COOLDOWN_DAYS (default 7) ago are eligible: a hijacked release
# is usually caught and pulled within days, so waiting avoids pulling it (matches the Dependabot
# cooldown for the base image and Actions). A newer version still inside the cooldown is reported
# but not adopted, and does not make --check fail.
# Checksums are taken from the checksum files published with each release, never computed from
# the downloaded binary alone. Requires: curl, python3 (or python); uv for the Python lock.
# Set GITHUB_TOKEN to avoid the unauthenticated GitHub API rate limit.
set -euo pipefail

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DOCKERFILE="$KIT_DIR/docker/Dockerfile"
REQ_IN="$KIT_DIR/docker/requirements.in"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1
COOLDOWN_DAYS=${COOLDOWN_DAYS:-7}

# Pick an interpreter that actually runs: on Windows, `python3` may be the Microsoft Store stub.
PY=
for cand in python3 python; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import json' >/dev/null 2>&1; then PY=$cand; break; fi
done
[ -n "$PY" ] || { echo "python3 is required" >&2; exit 1; }

gh_api() {
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL ${auth[@]+"${auth[@]}"} -H 'Accept: application/vnd.github+json' "https://api.github.com/$1"
}
current_arg() { sed -nE "s/^ARG $1=(.*)$/\1/p" "$DOCKERFILE"; }
set_arg() { sed -i.bak -E "s|^ARG $1=.*$|ARG $1=$2|" "$DOCKERFILE" && rm -f "$DOCKERFILE.bak"; }

OUTDATED=0
report() { printf '%-12s %-10s -> %-10s %s\n' "$1" "$2" "$3" "$4"; }

# Python selects the version; the JSON is piped in on stdin, COOLDOWN_DAYS is argv[1].
# (The program is passed with -c so stdin stays free for the piped data.)
GH_SELECT=$(cat <<'PY'
import json, sys, re, datetime
days = int(sys.argv[1])
rels = json.load(sys.stdin)
now = datetime.datetime.now(datetime.timezone.utc)
newest = elig = "-"
for r in rels:
    if r.get("draft") or r.get("prerelease"):
        continue
    tag = r.get("tag_name") or ""
    if not re.fullmatch(r"v?\d+(\.\d+)*", tag):
        continue
    pa = r.get("published_at")
    if not pa:
        continue
    dt = datetime.datetime.fromisoformat(pa.replace("Z", "+00:00"))
    if newest == "-":
        newest = tag
    if (now - dt).days >= days:
        elig = tag
        break
print(f"{elig}\t{newest}")
PY
)

PYPI_SELECT=$(cat <<'PY'
import json, sys, re, datetime
days = int(sys.argv[1])
d = json.load(sys.stdin)
now = datetime.datetime.now(datetime.timezone.utc)
cands = []
for ver, files in d.get("releases", {}).items():
    if not re.fullmatch(r"\d+(\.\d+)*", ver):
        continue
    times = [f.get("upload_time_iso_8601") or f.get("upload_time") for f in files]
    times = [t for t in times if t]
    if not times:
        continue
    t = min(datetime.datetime.fromisoformat(x.replace("Z", "+00:00")) for x in times)
    if t.tzinfo is None:
        t = t.replace(tzinfo=datetime.timezone.utc)
    cands.append((t, ver))
cands.sort()
newest = cands[-1][1] if cands else "-"
elig = "-"
for t, ver in reversed(cands):
    if (now - t).days >= days:
        elig = ver
        break
print(f"{elig}\t{newest}")
PY
)

# Prints "<eligible_tag>\t<newest_tag>" for a GitHub repo, stable releases only (tag like v1.2.3,
# not draft or prerelease). eligible = newest published >= COOLDOWN_DAYS ago; newest = regardless.
gh_eligible() { gh_api "repos/$1/releases?per_page=30" | "$PY" -c "$GH_SELECT" "$COOLDOWN_DAYS"; }

# Prints "<eligible_version>\t<newest_version>" for a PyPI package, stable versions only.
pypi_eligible() { curl -fsSL "https://pypi.org/pypi/$1/json" | "$PY" -c "$PYPI_SELECT" "$COOLDOWN_DAYS"; }

cooldown_note() {  # <eligible> <newest> : " (X in cooldown)" when a newer version is still too fresh
  if [ "$2" != "$1" ] && [ "$2" != "-" ]; then printf ' (%s in cooldown)' "${2#v}"; fi
}

# update_binary <name> <repo> <VERSION_ARG> <SHA_ARG_PREFIX> <checksum-asset> <amd64-asset> <arm64-asset>
# Asset names may contain {v} for the version without the leading "v".
update_binary() {
  local name=$1 repo=$2 varg=$3 sprefix=$4 sums_tpl=$5 amd_tpl=$6 arm_tpl=$7
  local cur out elig newest tag latest note
  cur=$(current_arg "$varg")
  out=$(gh_eligible "$repo")
  elig=${out%%$'\t'*}; newest=${out##*$'\t'}
  if [ "$elig" = "-" ] || [ -z "$elig" ]; then
    report "$name" "$cur" "-" "no version past cooldown"; return
  fi
  tag=$elig; latest=${elig#v}
  note=$(cooldown_note "$elig" "$newest")
  if [ "$cur" = "$latest" ]; then report "$name" "$cur" "$latest" "up to date$note"; return; fi
  OUTDATED=1
  report "$name" "$cur" "$latest" "outdated$note"
  [ "$CHECK" -eq 1 ] && return
  local sums amd arm
  sums=$(curl -fsSL "https://github.com/$repo/releases/download/$tag/${sums_tpl//\{v\}/$latest}")
  amd=$(printf '%s\n' "$sums" | awk -v f="${amd_tpl//\{v\}/$latest}" '$2 == f || $2 == "*"f {print $1}')
  arm=$(printf '%s\n' "$sums" | awk -v f="${arm_tpl//\{v\}/$latest}" '$2 == f || $2 == "*"f {print $1}')
  if [ ${#amd} -ne 64 ] || [ ${#arm} -ne 64 ]; then
    echo "  could not find both checksums for $name $latest; asset names may have changed" >&2
    exit 1
  fi
  set_arg "$varg" "$latest"
  set_arg "${sprefix}_AMD64" "$amd"
  set_arg "${sprefix}_ARM64" "$arm"
}

update_binary gitleaks gitleaks/gitleaks GITLEAKS_VERSION GITLEAKS_SHA256 \
  'gitleaks_{v}_checksums.txt' 'gitleaks_{v}_linux_x64.tar.gz' 'gitleaks_{v}_linux_arm64.tar.gz'
update_binary osv-scanner google/osv-scanner OSV_SCANNER_VERSION OSV_SCANNER_SHA256 \
  'osv-scanner_SHA256SUMS' 'osv-scanner_linux_amd64' 'osv-scanner_linux_arm64'
update_binary actionlint rhysd/actionlint ACTIONLINT_VERSION ACTIONLINT_SHA256 \
  'actionlint_{v}_checksums.txt' 'actionlint_{v}_linux_amd64.tar.gz' 'actionlint_{v}_linux_arm64.tar.gz'

# Python tools: bump the direct pins, then re-lock every transitive dependency with hashes.
PY_CHANGED=0
for pkg in semgrep zizmor; do
  cur=$(sed -nE "s/^$pkg==(.*)$/\1/p" "$REQ_IN")
  out=$(pypi_eligible "$pkg")
  elig=${out%%$'\t'*}; newest=${out##*$'\t'}
  if [ "$elig" = "-" ] || [ -z "$elig" ]; then
    report "$pkg" "$cur" "-" "no version past cooldown"; continue
  fi
  note=$(cooldown_note "$elig" "$newest")
  if [ "$cur" = "$elig" ]; then report "$pkg" "$cur" "$elig" "up to date$note"; continue; fi
  OUTDATED=1
  report "$pkg" "$cur" "$elig" "outdated$note"
  [ "$CHECK" -eq 1 ] && continue
  sed -i.bak -E "s/^$pkg==.*$/$pkg==$elig/" "$REQ_IN" && rm -f "$REQ_IN.bak"
  PY_CHANGED=1
done
if [ "$PY_CHANGED" -eq 1 ]; then
  command -v uv >/dev/null || { echo "uv is required to re-lock docker/requirements.txt" >&2; exit 1; }
  (cd "$KIT_DIR/docker" && uv pip compile requirements.in --universal --python-version 3.13 \
    --generate-hashes --no-header -o requirements.txt --quiet)
fi

# The base image digest is updated by Dependabot (.github/dependabot.yml).

if [ "$CHECK" -eq 1 ]; then
  [ "$OUTDATED" -eq 0 ] && echo "All pins are current (newer versions still in cooldown are not counted)." && exit 0
  echo "An eligible newer version exists. Run scripts/update-tools.sh, rebuild, and run tests/run-canary.sh." >&2
  exit 1
fi
[ "$OUTDATED" -eq 1 ] && echo "Pins updated. Review 'git diff', then rebuild and run tests/run-canary.sh." || echo "All pins are current."
