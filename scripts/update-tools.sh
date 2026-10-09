#!/usr/bin/env bash
# Update the pinned scanner versions and checksums in docker/Dockerfile and
# docker/requirements.txt.
#   scripts/update-tools.sh          rewrite the pins (review the diff, then rebuild and run the canary)
#   scripts/update-tools.sh --check  only report; exit 1 if an eligible newer version exists
# Only versions published at least COOLDOWN_DAYS (default 7) ago are eligible: a hijacked or
# broken release is usually caught and pulled within days, so waiting avoids pulling it (matches
# the Dependabot cooldown for the base image and Actions). A newer version still inside the
# cooldown is reported but not adopted, and does not make --check fail. A pin is only ever moved
# forward: an eligible version that is not newer than the current pin is left alone.
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

# Both selectors read the registry JSON on stdin and take argv[1]=COOLDOWN_DAYS, argv[2]=current
# pin. They print "<eligible>\t<newest>\t<outdated>":
#   eligible  highest stable version published >= COOLDOWN_DAYS ago ("-" if none)
#   newest    highest stable version regardless of age ("-" if none)
#   outdated  1 iff eligible exists and is strictly newer than the current pin, else 0
# Stable means a version like 1.2.3 (no pre-release); versions are ranked numerically, not by
# upload time, so a late backport of an older branch never outranks a higher version.
# (The program is passed with -c so stdin stays free for the piped data.)
GH_SELECT=$(cat <<'PY'
import sys, datetime
days, cur = int(sys.argv[1]), sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc)
def key(v): return tuple(int(x) for x in v.lstrip("v").split("."))
def gt(a, b):
    ka, kb = key(a), key(b); n = max(len(ka), len(kb))
    return ka + (0,) * (n - len(ka)) > kb + (0,) * (n - len(kb))
cands = []
for line in sys.stdin:                      # "<tag>\t<published_at>" per stable release
    line = line.rstrip()
    if not line:
        continue
    tag, pa = line.split("\t", 1)
    dt = datetime.datetime.fromisoformat(pa.replace("Z", "+00:00"))
    cands.append((tag, dt))
newest = max((c[0] for c in cands), key=key, default="-")
elig_items = [c[0] for c in cands if (now - c[1]).days >= days]
elig = max(elig_items, key=key, default="-")
outdated = 1 if elig != "-" and gt(elig, cur) else 0
print(f"{elig}\t{newest}\t{outdated}")
PY
)

PYPI_SELECT=$(cat <<'PY'
import json, sys, re, datetime
days, cur = int(sys.argv[1]), sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc)
def key(v): return tuple(int(x) for x in v.split("."))
def gt(a, b):
    ka, kb = key(a), key(b); n = max(len(ka), len(kb))
    return ka + (0,) * (n - len(ka)) > kb + (0,) * (n - len(kb))
d = json.load(sys.stdin)
cands = []
for ver, files in d.get("releases", {}).items():
    if not re.fullmatch(r"\d+(\.\d+)*", ver):
        continue
    live = [f for f in files if not f.get("yanked")]   # a yanked (withdrawn) release is not a candidate
    times = [f.get("upload_time_iso_8601") or f.get("upload_time") for f in live]
    times = [t for t in times if t]
    if not times:
        continue
    t = min(datetime.datetime.fromisoformat(x.replace("Z", "+00:00")) for x in times)
    if t.tzinfo is None:
        t = t.replace(tzinfo=datetime.timezone.utc)
    cands.append((ver, t))
newest = max((c[0] for c in cands), key=key, default="-")
elig_items = [c[0] for c in cands if (now - c[1]).days >= days]
elig = max(elig_items, key=key, default="-")
outdated = 1 if elig != "-" and gt(elig, cur) else 0
print(f"{elig}\t{newest}\t{outdated}")
PY
)

# Print "<tag>\t<published_at>" for every stable release, following pages (the newest stable past
# the cooldown can sit behind a first page full of prereleases). Each page is reduced to these two
# fields immediately, so nothing large is kept. Stops at the last page or after 10 pages.
GH_PAGE=$(cat <<'PY'
import json, sys, re
rels = json.load(sys.stdin)
print(len(rels))
for r in rels:
    if r.get("draft") or r.get("prerelease"):
        continue
    tag = r.get("tag_name") or ""
    pa = r.get("published_at")
    if re.fullmatch(r"v?\d+(\.\d+)*", tag) and pa:
        print(f"{tag}\t{pa}")
PY
)
gh_stable_lines() {
  local repo=$1 page=1 out n lines
  while [ "$page" -le 10 ]; do
    # A failed fetch or unparseable page must not look like "no releases": fail loudly instead.
    if ! out=$(gh_api "repos/$repo/releases?per_page=100&page=$page" | "$PY" -c "$GH_PAGE"); then
      echo "error: could not fetch releases for $repo (page $page)" >&2
      return 1
    fi
    n=${out%%$'\n'*}; n=${n%$'\r'}        # python on Windows emits CRLF; drop the CR
    case "$out" in *$'\n'*) lines=${out#*$'\n'} ;; *) lines="" ;; esac
    [ -n "$lines" ] && printf '%s\n' "$lines"
    { [ -z "$n" ] || [ "$n" -lt 100 ]; } && break
    page=$((page + 1))
  done
}
gh_eligible() { gh_stable_lines "$1" | "$PY" -c "$GH_SELECT" "$COOLDOWN_DAYS" "$2"; }
pypi_eligible() { curl -fsSL "https://pypi.org/pypi/$1/json" | "$PY" -c "$PYPI_SELECT" "$COOLDOWN_DAYS" "$2"; }

cooldown_note() {  # <eligible> <newest> : " (X in cooldown)" when a higher version is still too fresh
  if [ "$2" != "$1" ] && [ "$2" != "-" ]; then printf ' (%s in cooldown)' "${2#v}"; fi
}

# update_binary <name> <repo> <VERSION_ARG> <SHA_ARG_PREFIX> <checksum-asset> <amd64-asset> <arm64-asset>
# Asset names may contain {v} for the version without the leading "v".
update_binary() {
  local name=$1 repo=$2 varg=$3 sprefix=$4 sums_tpl=$5 amd_tpl=$6 arm_tpl=$7
  local cur out elig newest od tag latest note
  cur=$(current_arg "$varg")
  out=$(gh_eligible "$repo" "$cur") || { echo "error: release lookup failed for $name ($repo)" >&2; exit 1; }
  IFS=$'\t' read -r elig newest od <<<"$out"
  if [ "$elig" = "-" ]; then report "$name" "$cur" "-" "no version past cooldown"; return; fi
  note=$(cooldown_note "$elig" "$newest")
  if [ "$od" != "1" ]; then report "$name" "$cur" "$cur" "up to date$note"; return; fi
  OUTDATED=1
  tag=$elig; latest=${elig#v}
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
  out=$(pypi_eligible "$pkg" "$cur") || { echo "error: PyPI lookup failed for $pkg" >&2; exit 1; }
  IFS=$'\t' read -r elig newest od <<<"$out"
  if [ "$elig" = "-" ]; then report "$pkg" "$cur" "-" "no version past cooldown"; continue; fi
  note=$(cooldown_note "$elig" "$newest")
  if [ "$od" != "1" ]; then report "$pkg" "$cur" "$cur" "up to date$note"; continue; fi
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
