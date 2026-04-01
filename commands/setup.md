---
name: setup
description: Set up local dev environment — composer install, npm/bun install, .env setup, migrations, seed
allowed_tools: ["Bash", "Read", "Write", "Glob"]
---

# /setup

## Goal
Bootstrap the local development environment from scratch. Installs dependencies, configures `.env`, runs migrations, seeds test data, and verifies the setup is working.

## Steps
1. Check prerequisites:
   ```bash
   php --version        # require 8.2+
   composer --version
   go version           # require 1.21+
   node --version       # require 18+
   bun --version
   docker --version
   ```
2. Install PHP dependencies:
   ```bash
   composer install
   ```
3. Set up `.env`:
   ```bash
   cp .env.example .env
   php artisan key:generate
   ```
   Check `.env` for required variables: DB_*, REDIS_*, PAYMENT_HOST_URL, PAYMENT_HOST_KEY
4. Start Docker services:
   ```bash
   docker compose up -d
   ```
   Wait for MySQL health check to pass.
5. Run migrations:
   ```bash
   php artisan migrate
   ```
6. Seed test data (if seeder exists):
   ```bash
   php artisan db:seed --class=DevSeeder
   ```
7. Install JS dependencies:
   ```bash
   bun install
   ```
8. Build frontend assets:
   ```bash
   bun run build
   ```
9. Go: download modules:
   ```bash
   go mod download
   go build ./...
   ```
10. Run tests to confirm working setup:
    ```bash
    ./vendor/bin/phpunit --stop-on-failure
    go test ./...
    bun test
    ```
11. Report any failures with instructions to fix

## Output
```
LOCAL SETUP
────────────────────────────────────────────────
PHP 8.3.2     ✓
Composer 2.7  ✓
Go 1.22.0     ✓
Bun 1.1.0     ✓
Docker 25.0   ✓
────────────────────────────────────────────────
composer install     PASS
.env configured      PASS
Docker services      PASS (mysql, redis, rabbitmq)
Migrations           PASS (12 migrations)
Seed                 PASS
bun install          PASS
bun run build        PASS
go mod download      PASS
────────────────────────────────────────────────
Tests:
  PHPUnit    PASS (142 tests)
  Go test    PASS (38 tests)
  Bun test   PASS (56 tests)
────────────────────────────────────────────────
SETUP COMPLETE — dev environment ready
```
