---
name: verify
description: Full verification loop — build, lint, test, security scan, diff review. Reports READY/NOT READY.
allowed_tools: ["Bash", "Read", "Grep"]
---

# /verify

## Goal
Run the complete verification pipeline before creating a PR. Detects stack automatically (PHP/Go/JS) and runs all checks. Reports READY or NOT READY.

## Steps
1. Detect stack by checking for `composer.json`, `go.mod`, `package.json`/`bun.lockb`
2. Run PHP phases (if composer.json present):
   - `composer install --no-interaction`
   - `./vendor/bin/pint --test`
   - `./vendor/bin/phpstan analyse --memory-limit=512M`
   - `./vendor/bin/phpunit`
   - `composer audit`
3. Run Go phases (if go.mod present):
   - `go build ./...`
   - `gofmt -l .` (fail if output)
   - `go vet ./...`
   - `go test -race -timeout 120s ./...`
   - `golangci-lint run ./...` (if installed)
4. Run JS phases (if package.json/bun.lockb present):
   - `bun run build`
   - `bun x tsc --noEmit`
   - `bun x eslint . --max-warnings 0`
   - `bun test`
5. Run diff review:
   - `git diff main...HEAD`
   - Scan for debug code, secrets, TODOs
6. Aggregate results — if any phase fails, mark NOT READY with the blocking phase name

## Output
```
VERIFICATION REPORT
──────────────────────────────────────────────────────
Phase                  Status   Details
──────────────────────────────────────────────────────
[PHP] Install          PASS
[PHP] Pint             PASS
[PHP] PHPStan          PASS     Level 8, 0 errors
[PHP] PHPUnit          PASS     142 tests, 0 failures
[PHP] Audit            PASS     0 vulnerabilities
[Go]  Build            PASS
[Go]  gofmt            PASS
[Go]  go vet           PASS
[Go]  Tests (race)     PASS     38 tests
[JS]  Build            PASS
[JS]  TypeScript       PASS
[JS]  ESLint           PASS
[JS]  Tests            PASS     56 tests
Diff review            PASS     No debug code or secrets
──────────────────────────────────────────────────────
OVERALL: READY FOR PR
```
