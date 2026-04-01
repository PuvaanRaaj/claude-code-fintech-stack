---
name: deployment-patterns
description: CI/CD and deployment patterns for payment microservices — multi-arch Docker builds, GitLab pipeline structure, environment promotion (staging → UAT → production), blue-green deployment, secrets management, and health checks.
origin: fintech-stack
---

# Deployment Patterns

A payment service deployment that goes wrong at 2am is not an engineering inconvenience — it's transactions being declined and merchants going offline. Zero-downtime deployment, environment promotion gates, and automated rollback are not optional extras for payment infrastructure.

## When to Activate

- Designing or reviewing a CI/CD pipeline for a payment service
- Setting up deployment for a new service or environment
- Developer asks about blue-green, zero-downtime, or environment promotion strategy

---

## Docker Multi-Arch Build

```yaml
# GitLab CI: build for amd64 + arm64
build:
  stage: build
  script:
    - docker buildx create --use
    - docker buildx build
        --platform linux/amd64,linux/arm64
        --tag registry.example.com/payment-service:${CI_COMMIT_SHA}
        --push
        .
```

---

## GitLab CI Pipeline Structure

```yaml
stages:
  - lint
  - test
  - build
  - scan
  - deploy-staging
  - deploy-uat
  - deploy-production

variables:
  DOCKER_DRIVER: overlay2

lint:php:
  stage: lint
  script:
    - composer install --no-interaction
    - ./vendor/bin/pint --test
    - ./vendor/bin/phpstan analyse --memory-limit=512M

lint:go:
  stage: lint
  script:
    - gofmt -l . | tee /tmp/gofmt.out
    - test ! -s /tmp/gofmt.out  # fail if any files unformatted
    - go vet ./...
    - golangci-lint run ./...

test:php:
  stage: test
  services:
    - mysql:8.0
  variables:
    DB_HOST: mysql
    DB_DATABASE: payments_test
  script:
    - composer install --no-interaction
    - php artisan migrate --force
    - ./vendor/bin/phpunit --coverage-text

test:go:
  stage: test
  script:
    - go test -race -timeout 120s ./...

build:image:
  stage: build
  script:
    - docker buildx build --platform linux/amd64,linux/arm64
        --tag ${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}
        --push .
  only:
    - main
    - /^release\/.*/

scan:trivy:
  stage: scan
  script:
    - trivy image --exit-code 1 --severity HIGH,CRITICAL
        ${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}

deploy:staging:
  stage: deploy-staging
  script:
    - ./deploy.sh staging ${CI_COMMIT_SHA}
  environment:
    name: staging

deploy:uat:
  stage: deploy-uat
  script:
    - ./deploy.sh uat ${CI_COMMIT_SHA}
  when: manual
  environment:
    name: uat

deploy:production:
  stage: deploy-production
  script:
    - ./deploy.sh production ${CI_COMMIT_SHA}
  when: manual
  only:
    - main
  environment:
    name: production
```

---

## Environment Promotion

```
local → staging (auto on merge to main) → UAT (manual gate) → production (manual gate)
```

- **Staging**: auto-deploy on every merge; no approval
- **UAT**: manual trigger; QA sign-off required
- **Production**: manual trigger; change ticket and approver required

---

## Blue-Green Deployment

For payment services — zero-downtime by switching traffic between two live environments:

```bash
# deploy.sh — simplified blue-green
deploy_to_green() {
    kubectl set image deployment/payment-service-green \
        payment-service=${IMAGE}:${TAG}
    kubectl rollout status deployment/payment-service-green
}

smoke_test() {
    curl -sf https://payment-service-green.internal/health || exit 1
}

switch_traffic() {
    aws elbv2 modify-listener \
        --listener-arn ${LISTENER_ARN} \
        --default-actions "[{\"Type\":\"forward\",\"TargetGroupArn\":\"${GREEN_TG_ARN}\"}]"
}

deploy_to_green && smoke_test && switch_traffic
```

---

## Secrets Management

- **Never** store secrets as plain text in CI variables or source code
- Use AWS SSM Parameter Store or HashiCorp Vault; retrieve at container startup

```bash
# entrypoint.sh
export DB_PASSWORD=$(aws ssm get-parameter \
    --name "/payment-service/production/DB_PASSWORD" \
    --with-decryption --query "Parameter.Value" --output text)
exec "$@"
```

- Rotate secrets without redeployment using dynamic secrets (Vault) or SSM references
- Mask secrets in CI output via `CI_MASKED_VARIABLES`; never log them

---

## Health Checks and Readiness Probes

```yaml
# Kubernetes deployment spec
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

```json
GET /health/ready
{
  "status": "ok",
  "checks": {
    "database": "ok",
    "payment_host": "ok",
    "queue": "ok"
  }
}
```

Return `200` when all checks pass; `503` when any critical dependency is down. Kubernetes stops routing traffic to a pod returning `503` on readiness.

---

## Best Practices

- **Tag images with commit SHA, not `latest`** — `latest` is not a version; `${CI_COMMIT_SHA}` is auditable and rollback-safe
- **Run `trivy` in CI on every image build** — vulnerability scanning before deployment, not after an incident
- **Manual gate before production** — even with full test coverage, a human should confirm a payment service deployment
- **Smoke test before switching traffic** — blue-green only works if the green environment is actually healthy before you cut over
- **Secrets must never touch the filesystem** — retrieve from SSM or Vault at startup; environment variables only, never files
