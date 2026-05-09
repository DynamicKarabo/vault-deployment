# =============================================================================
# Multi-stage Vault Dockerfile — downloads signed release binary
# =============================================================================
# HashiCorp's official Dockerfile uses a single-stage download pattern.
# This version improves with: multi-stage build, checksum verification,
# non-root user, HEALTHCHECK, and OCI labels.
#
# Build: docker build -t vault:latest .
#        docker build --build-arg VAULT_VERSION=1.19.0 -t vault:1.19.0 .
# =============================================================================

# Stage 1: Download and verify
FROM alpine:3.23 AS downloader

ARG VAULT_VERSION=1.19.0
ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG VAULT_URL=https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_${TARGETOS}_${TARGETARCH}.zip
ARG VAULT_SHA_URL=https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS
ARG VAULT_SIG_URL=https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS.sig
ARG HASHICORP_PUB_KEY=https://www.hashicorp.com/.well-known/pgp-key.txt

RUN apk add --no-cache curl gnupg unzip ca-certificates && \
    gpg --batch --keyserver hkp://keyserver.ubuntu.com --recv-keys 72D7468F || \
    gpg --batch --keyserver hkp://p80.pool.sks-keyservers.net --recv-keys 72D7468F || \
    curl -sL "${HASHICORP_PUB_KEY}" | gpg --batch --import

RUN cd /tmp && \
    curl -sLO "${VAULT_URL}" && \
    curl -sLO "${VAULT_SHA_URL}" && \
    curl -sLO "${VAULT_SIG_URL}" && \
    grep "vault_${VAULT_VERSION}_${TARGETOS}_${TARGETARCH}.zip" vault_${VAULT_VERSION}_SHA256SUMS > vault.sha256 && \
    sha256sum -c vault.sha256 && \
    gpg --verify vault_${VAULT_VERSION}_SHA256SUMS.sig vault_${VAULT_VERSION}_SHA256SUMS && \
    unzip -d /output vault_${VAULT_VERSION}_${TARGETOS}_${TARGETARCH}.zip

# Stage 2: Runtime
FROM alpine:3.23

RUN apk add --no-cache ca-certificates tzdata su-exec dumb-init && \
    addgroup -g 10001 -S vault && \
    adduser -u 10001 -S -G vault vault

COPY --from=downloader /output/vault /usr/local/bin/vault

# Vault runtime directories
RUN mkdir -p /vault/logs /vault/file /vault/config && \
    chown -R vault:vault /vault

# Vault ports: 8200 (HTTP API), 8201 (cluster)
EXPOSE 8200 8201

USER vault
WORKDIR /vault

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD vault status -tls-skip-verify 2>/dev/null || curl -sf http://localhost:8200/v1/sys/health 2>/dev/null || exit 1

LABEL org.opencontainers.image.title="Vault" \
      org.opencontainers.image.description="HashiCorp Vault - Secrets Management" \
      org.opencontainers.image.version="${VAULT_VERSION}" \
      org.opencontainers.image.source="https://github.com/DynamicKarabo/vault-deployment"

ENTRYPOINT ["dumb-init", "vault"]
CMD ["server", "-config", "/vault/config"]
