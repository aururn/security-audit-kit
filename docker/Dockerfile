# Scanner image for security-audit-kit.
# Every tool is pinned to a version and verified against the checksum published with its
# release; the base image is pinned by digest. Scanners are supply-chain targets too
# (Trivy's release and GitHub Action tags were tampered with in March 2026).
FROM python:3.13-slim@sha256:7c61056e61ac89e852de05f3dc6fa51a6dd2181797bceed46aa725dd7cb2cd3b

ARG GITLEAKS_VERSION=8.30.1
ARG GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
ARG OSV_SCANNER_VERSION=2.6.0
ARG OSV_SCANNER_SHA256=ca69b3d3cd08f889a49dc0a383122f71cc528b83803671df5fd874d97485b108
ARG ACTIONLINT_VERSION=1.7.12
ARG ACTIONLINT_SHA256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
ARG SEMGREP_VERSION=1.178.0
ARG ZIZMOR_VERSION=1.30.1

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git jq shellcheck \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  cd /tmp; \
  curl -fsSLo gitleaks.tar.gz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"; \
  echo "${GITLEAKS_SHA256}  gitleaks.tar.gz" | sha256sum -c -; \
  tar -xzf gitleaks.tar.gz gitleaks; install -m 0755 gitleaks /usr/local/bin/gitleaks; \
  curl -fsSLo osv-scanner "https://github.com/google/osv-scanner/releases/download/v${OSV_SCANNER_VERSION}/osv-scanner_linux_amd64"; \
  echo "${OSV_SCANNER_SHA256}  osv-scanner" | sha256sum -c -; \
  install -m 0755 osv-scanner /usr/local/bin/osv-scanner; \
  curl -fsSLo actionlint.tar.gz "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"; \
  echo "${ACTIONLINT_SHA256}  actionlint.tar.gz" | sha256sum -c -; \
  tar -xzf actionlint.tar.gz actionlint; install -m 0755 actionlint /usr/local/bin/actionlint; \
  rm -rf /tmp/*

RUN pip install --no-cache-dir "semgrep==${SEMGREP_VERSION}" "zizmor==${ZIZMOR_VERSION}"

# The target is mounted read-only and owned by another user; let git read it.
RUN git config --system --add safe.directory '*'

COPY scan.sh /usr/local/bin/scan
RUN chmod 0755 /usr/local/bin/scan
# Runs as root because Docker Desktop bind mounts on Windows/macOS are not writable by other
# uids. run-scan.sh compensates: the target is mounted read-only, all capabilities are dropped
# and privilege escalation is disabled.
WORKDIR /src

ENTRYPOINT ["scan"]
