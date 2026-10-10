# Scanner image for security-audit-kit (linux/amd64 and linux/arm64).
# Every binary is pinned to a version and verified against the checksum published with its
# release; Python tools are installed from a hash-locked requirements file; the base image is
# pinned by digest. Scanners are supply-chain targets too (Trivy's release and GitHub Action
# tags were tampered with in March 2026). Update pins with scripts/update-tools.sh.
# The base image comes from Google's Docker Hub mirror: the same image (same digest), without
# Docker Hub's unauthenticated pull limit, which shared CI runners hit (docs/decisions/0006).
FROM mirror.gcr.io/library/python:3.13-slim@sha256:7c61056e61ac89e852de05f3dc6fa51a6dd2181797bceed46aa725dd7cb2cd3b

ARG TARGETARCH
ARG GITLEAKS_VERSION=8.30.1
ARG GITLEAKS_SHA256_AMD64=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
ARG GITLEAKS_SHA256_ARM64=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080
ARG OSV_SCANNER_VERSION=2.6.0
ARG OSV_SCANNER_SHA256_AMD64=ca69b3d3cd08f889a49dc0a383122f71cc528b83803671df5fd874d97485b108
ARG OSV_SCANNER_SHA256_ARM64=2c71403eb443d05891c4f268c3ad771cf4f16e5443463fd7851ef8f454d3c7e4
ARG ACTIONLINT_VERSION=1.7.12
ARG ACTIONLINT_SHA256_AMD64=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
ARG ACTIONLINT_SHA256_ARM64=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6
# Semgrep registry rulesets baked in at build time so a given image always scans with the
# same rules and needs no network. p/nextjs is excluded: the registry serves it empty.
ARG SEMGREP_RULESETS="default owasp-top-ten typescript react nodejsscan"

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git jq shellcheck \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  case "${TARGETARCH:-amd64}" in \
    amd64) gl_arch=x64;   arch=amd64; gl_sum=$GITLEAKS_SHA256_AMD64; osv_sum=$OSV_SCANNER_SHA256_AMD64; al_sum=$ACTIONLINT_SHA256_AMD64 ;; \
    arm64) gl_arch=arm64; arch=arm64; gl_sum=$GITLEAKS_SHA256_ARM64; osv_sum=$OSV_SCANNER_SHA256_ARM64; al_sum=$ACTIONLINT_SHA256_ARM64 ;; \
    *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
  esac; \
  cd /tmp; \
  curl -fsSLo gitleaks.tar.gz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz"; \
  echo "${gl_sum}  gitleaks.tar.gz" | sha256sum -c -; \
  tar -xzf gitleaks.tar.gz gitleaks; install -m 0755 gitleaks /usr/local/bin/gitleaks; \
  curl -fsSLo osv-scanner "https://github.com/google/osv-scanner/releases/download/v${OSV_SCANNER_VERSION}/osv-scanner_linux_${arch}"; \
  echo "${osv_sum}  osv-scanner" | sha256sum -c -; \
  install -m 0755 osv-scanner /usr/local/bin/osv-scanner; \
  curl -fsSLo actionlint.tar.gz "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${arch}.tar.gz"; \
  echo "${al_sum}  actionlint.tar.gz" | sha256sum -c -; \
  tar -xzf actionlint.tar.gz actionlint; install -m 0755 actionlint /usr/local/bin/actionlint; \
  rm -rf /tmp/*

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --require-hashes -r /tmp/requirements.txt && rm /tmp/requirements.txt

# Fail the build if a ruleset comes back empty, instead of silently scanning with nothing.
# The registry sometimes answers with an error or an empty body for a moment (seen on CI runners),
# so each ruleset gets a few attempts before the build fails; the failure says what came back.
RUN set -eu; \
  mkdir -p /opt/semgrep-rules; \
  for rs in $SEMGREP_RULESETS; do \
    f="/opt/semgrep-rules/${rs}.yml"; n=0; code=none; \
    for attempt in 1 2 3 4; do \
      code=$(curl -sSL --retry 2 --retry-all-errors -o "$f" -w '%{http_code}' "https://semgrep.dev/c/p/${rs}" || echo "curl-failed"); \
      n=$(grep -c '^- id:' "$f" 2>/dev/null || true); \
      if [ "$code" = 200 ] && [ "${n:-0}" -gt 0 ]; then break; fi; \
      echo "p/${rs}: attempt ${attempt}: HTTP ${code}, ${n:-0} rules" >&2; \
      if [ "$attempt" -lt 4 ]; then sleep $((attempt * 10)); fi; \
    done; \
    [ "$code" = 200 ] && [ "${n:-0}" -gt 0 ] || { echo "semgrep ruleset p/${rs} is empty or unavailable (HTTP ${code})" >&2; exit 1; }; \
    echo "p/${rs}: ${n} rules, sha256 $(sha256sum "$f" | cut -c1-16)"; \
  done; \
  date -u +%Y-%m-%dT%H:%M:%SZ > /opt/semgrep-rules/FETCHED_AT

# The target is mounted read-only and owned by another user; let git read it.
RUN git config --system --add safe.directory '*'

COPY scan.sh /usr/local/bin/scan
RUN chmod 0755 /usr/local/bin/scan
# Runs as root by default because Docker Desktop bind mounts on Windows/macOS are not writable
# by other uids; on Linux, run-scan.sh passes the caller's uid. Either way the target is
# read-only, all capabilities are dropped and privilege escalation is disabled
# (docs/decisions/0001-container-user.md).
WORKDIR /src

# nosemgrep: dockerfile.security.missing-user-entrypoint.missing-user-entrypoint
ENTRYPOINT ["scan"]
