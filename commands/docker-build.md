---
name: docker-build
description: Build Docker image for this service — supports multi-arch (amd64+arm64)
allowed_tools: ["Bash", "Read", "Glob"]
---

# /docker-build

## Goal
Build a Docker image for the current service. Supports single-arch and multi-arch (amd64+arm64) builds. Validates Dockerfile before building and runs a security scan after.

## Steps
1. Check Dockerfile exists:
   ```bash
   ls Dockerfile Dockerfile.* 2>/dev/null
   ```
2. Lint the Dockerfile:
   ```bash
   docker run --rm -i hadolint/hadolint < Dockerfile 2>&1
   ```
3. Determine build mode:
   - Single arch (default): `docker build`
   - Multi-arch: `docker buildx build --platform linux/amd64,linux/arm64`
4. Build image:
   ```bash
   # Single arch
   docker build \
     --tag {service-name}:$(git rev-parse --short HEAD) \
     --tag {service-name}:latest \
     .

   # Multi-arch (requires buildx)
   docker buildx create --use 2>/dev/null || true
   docker buildx build \
     --platform linux/amd64,linux/arm64 \
     --tag registry.example.com/{service-name}:$(git rev-parse --short HEAD) \
     --push \
     .
   ```
5. Run Trivy security scan on built image:
   ```bash
   trivy image --exit-code 1 --severity HIGH,CRITICAL {service-name}:latest 2>&1
   ```
6. Report image size and any scan findings

## Output
```
DOCKER BUILD
────────────────────────────────────────────────
Dockerfile:    PASS (hadolint: 0 warnings)
Platform:      linux/amd64, linux/arm64
Tag:           payment-service:abc1234

Build:         SUCCESS
Image size:    42 MB (amd64)

Security scan (Trivy):
  HIGH:        0
  CRITICAL:    0
  PASS
────────────────────────────────────────────────
Image ready: payment-service:abc1234
```
