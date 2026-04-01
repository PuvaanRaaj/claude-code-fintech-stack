---
name: docker-patterns
description: Docker patterns for fintech services — multi-stage builds for PHP/Laravel and Go, multi-arch (amd64/arm64) support, Alpine version pinning, NewRelic agent installation, Docker Compose for local dev, and health check patterns.
origin: fintech-stack
---

# Docker Patterns

Payment service containers have stricter requirements than typical web app containers: they run on both x86 and ARM infrastructure, they need APM agents installed correctly for each architecture, and they must have health checks that verify payment host connectivity — not just that the process started.

## When to Activate

- Writing or reviewing a Dockerfile for a PHP or Go service
- Setting up Docker Compose for local payment service development
- Adding a NewRelic or other APM agent to a multi-arch image
- Developer asks about multi-arch builds, Alpine pinning, or health checks

---

## Multi-Stage Dockerfile for PHP / Laravel

```dockerfile
# syntax=docker/dockerfile:1
ARG PHP_VERSION=8.3
ARG ALPINE_VERSION=3.19

# Stage 1: Composer dependencies
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-scripts \
    --prefer-dist \
    --optimize-autoloader

# Stage 2: Production image
FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION}

RUN apk add --no-cache \
    nginx \
    supervisor \
    libpng-dev \
    libzip-dev \
    && docker-php-ext-install pdo_mysql zip gd opcache \
    && rm -rf /var/cache/apk/*

WORKDIR /var/www/html

COPY --from=vendor /app/vendor ./vendor
COPY . .

RUN php artisan config:cache \
    && php artisan route:cache \
    && php artisan view:cache

EXPOSE 9000
CMD ["php-fpm"]
```

---

## Multi-Stage Dockerfile for Go

```dockerfile
# syntax=docker/dockerfile:1
ARG GO_VERSION=1.22
ARG ALPINE_VERSION=3.19

# Stage 1: Build
FROM golang:${GO_VERSION}-alpine AS builder
WORKDIR /app

# Cache module downloads separately from source
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-w -s -X main.version=$(git describe --tags --always)" \
    -o /payment-service \
    ./cmd/payment-service

# Stage 2: Minimal runtime image
FROM alpine:${ALPINE_VERSION}
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=builder /payment-service .
EXPOSE 8080
ENTRYPOINT ["./payment-service"]
```

---

## Multi-Arch Support

```dockerfile
ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN echo "Building on $BUILDPLATFORM for $TARGETPLATFORM"

# Platform-specific binary selection (e.g., for monitoring agents)
RUN case "${TARGETPLATFORM}" in \
        "linux/amd64")  ARCH="x86_64" ;; \
        "linux/arm64")  ARCH="aarch64" ;; \
        *) echo "Unsupported platform: ${TARGETPLATFORM}" && exit 1 ;; \
    esac \
    && wget -q "https://download.example.com/agent-${ARCH}.tar.gz" \
    && tar -xzf agent-${ARCH}.tar.gz
```

Build command:
```bash
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --tag registry.example.com/payment-service:latest \
    --push \
    .
```

---

## Alpine Version Pinning

Always pin to a specific minor version — unpinned `alpine:latest` changes under you:

```dockerfile
FROM alpine:3.19           # pin to minor version
FROM php:8.3-fpm-alpine3.19
FROM golang:1.22-alpine3.19
```

Use Dependabot or Renovate to get automated update PRs.

---

## NewRelic Multi-Arch Agent

```dockerfile
ARG TARGETPLATFORM
ARG NR_VERSION=10.x.x

RUN case "${TARGETPLATFORM}" in \
        "linux/amd64")  NR_ARCH="x86_64" ;; \
        "linux/arm64")  NR_ARCH="aarch64" ;; \
        *) echo "Unsupported: ${TARGETPLATFORM}" && exit 1 ;; \
    esac \
    && apk add --no-cache curl \
    && curl -L "https://download.newrelic.com/php_agent/archive/${NR_VERSION}/newrelic-php5-${NR_VERSION}-linux-musl-${NR_ARCH}.tar.gz" \
        | tar xz \
    && ./newrelic-install install \
    && rm -rf newrelic-*

ENV NEWRELIC_LICENSE_KEY=""
ENV NEWRELIC_APP_NAME="payment-service"
```

---

## Docker Compose for Local Dev

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    volumes:
      - .:/var/www/html
      - vendor:/var/www/html/vendor
    environment:
      APP_ENV: local
      DB_HOST: mysql
      REDIS_HOST: redis
    ports:
      - "8080:80"
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_started

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: secret
      MYSQL_DATABASE: payments
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  rabbitmq:
    image: rabbitmq:3.12-management-alpine
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
      RABBITMQ_DEFAULT_USER: guest
      RABBITMQ_DEFAULT_PASS: guest

volumes:
  mysql_data:
  vendor:
```

---

## Health Check Pattern

```dockerfile
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:8080/health/live || exit 1
```

The health endpoint should check real dependencies — not just that the process is running:

```json
GET /health/ready
{
  "status": "ok",
  "checks": {
    "database":    "ok",
    "payment_host": "ok",
    "queue":       "ok"
  }
}
```

Return `200` when all checks pass; `503` when any critical dependency is down.

---

## Best Practices

- **Build args at the top** — `PHP_VERSION`, `GO_VERSION`, `ALPINE_VERSION`; makes version bumps a one-line change
- **Named build stages** — `AS vendor`, `AS builder`; makes the Dockerfile readable and enables `--target` for CI caching
- **Pin Alpine, not `latest`** — `alpine:latest` is not reproducible; pin to `alpine:3.19` and use Renovate to update
- **Health check checks real dependencies** — a container that can't reach the database or payment host is not healthy, regardless of whether the process started
- **Multi-arch on every payment service** — ARM-based instances are cheaper; support them from day one rather than retrofitting later
