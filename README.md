# Vault — Containerized Deployment

[![Docker Build & Push](https://github.com/DynamicKarabo/vault-deployment/actions/workflows/docker-build.yml/badge.svg)](https://github.com/DynamicKarabo/vault-deployment/actions/workflows/docker-build.yml)
[![GitHub Stars](https://img.shields.io/badge/dynamic/json?logo=github&label=stars&color=gold&query=stargazers_count&url=https%3A%2F%2Fapi.github.com%2Frepos%2Fhashicorp%2Fvault)](https://github.com/hashicorp/vault)

**Vault** — **36k⭐** on GitHub. HashiCorp's secrets management, encryption-as-a-service, and privileged access management tool.

## Why This Deployment

The upstream [hashicorp/vault](https://github.com/hashicorp/vault) ships a single-stage Dockerfile that downloads a prebuilt binary from releases.hashicorp.com. This repo replaces it with a hardened multi-stage build: GPG signature verification in the download stage, Alpine 3.21 runtime, non-root user, health check, and proper process management.

## Image Specs

| Property | Value |
|----------|-------|
| **Size** | **677MB** (all-in-one binary with UI + all backends) |
| **Base image** | `alpine:3.21` |
| **Vault version** | 1.19.0 |
| **User** | Non-root `vault` (UID 10001) |
| **HEALTHCHECK** | `vault status` via TLS-skip |
| **Entrypoint** | `dumb-init vault` (proper PID 1) |
| **Ports** | 8200 (HTTP API), 8201 (cluster) |

## Multi-Stage Build

1. **Downloader** — Downloads the official HashiCorp release zip + SHA256SUMS + GPG signature
2. **Runtime** — Alpine 3.21 with ca-certificates, tzdata, dumb-init, and the vault binary

Key security step: GPG verifies the SHA256SUMS file against HashiCorp's public key before extracting the binary.

```bash
docker build --build-arg VAULT_VERSION=1.19.0 -t vault:latest .
```

## Load Test

| Metric | Baseline (10 concurrent) | Stress (100 concurrent) |
|--------|-------------------------|------------------------|
| **Requests/sec** | 1,119 | **1,209** |
| **p99 latency** | 73ms | **270ms** |
| **Failed requests** | 0 | **0** |
| **Transfer rate** | 643 KB/s | 695 KB/s |

Vault scales well under load — throughput increases with concurrency and zero failures at both levels.

## Deployment

### k3s (Dev Mode)

```bash
kubectl apply -f k8s/deployment.yaml
# Access the API:
curl http://localhost:30820/v1/sys/health
# Root token: root
```

### Docker (Dev Mode)

```bash
docker run -d --cap-add=IPC_LOCK -p 8200:8200 ghcr.io/dynamickarabo/vault-deployment:latest \
  vault server -dev -dev-root-token-id=root -dev-listen-address=0.0.0.0:8200
```

## CI/CD

Every push to `main` triggers the [Docker Build & Push](.github/workflows/docker-build.yml) workflow. Supports manual version overrides via workflow_dispatch:
```bash
gh workflow run "Docker Build & Push" --repo DynamicKarabo/vault-deployment -f version=1.19.0
```

## Repo Structure

```
├── Dockerfile          # Multi-stage Vault build (download + verify + runtime)
├── .dockerignore       # Excludes source files (we download prebuilt binary)
├── k8s/
│   └── deployment.yaml # k3s manifests (dev mode)
├── .github/
│   └── workflows/
│       └── docker-build.yml
├── src/                # Git submodule → DynamicKarabo/vault-fork
└── .gitmodules
```
