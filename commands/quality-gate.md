---
name: quality-gate
description: Run full quality gate — lint, test, security scan. Must pass before merge.
allowed_tools: ["Bash", "Read", "Grep"]
---

# /quality-gate

## Goal
Run the mandatory quality gate checks before any merge to main. All checks must pass — no exceptions. Equivalent to the CI pipeline running locally.

## Steps
1. Detect stack (PHP/Go/JS)
2. Run lint:
   - PHP: `./vendor/bin/pint --test && ./vendor/bin/phpstan analyse`
   - Go: `gofmt -l . && go vet ./...`
   - JS: `bun x eslint . --max-warnings 0 && bun x tsc --noEmit`
3. Run tests:
   - PHP: `./vendor/bin/phpunit`
   - Go: `go test -race ./...`
   - JS: `bun test`
4. Run security scan:
   - `composer audit` (PHP)
   - `govulncheck ./...` (Go)
   - `bun audit` (JS)
5. Check coverage threshold (80% for payment packages):
   - PHP: `./vendor/bin/phpunit --coverage-text | grep "Lines:"`
   - Go: `go test -coverprofile=c.out ./... && go tool cover -func=c.out`
6. Aggregate — ALL phases must pass for GATE: OPEN verdict

## Output
```
QUALITY GATE
──────────────────────────────────────────────────────
Check               Status   Details
──────────────────────────────────────────────────────
PHP Pint            PASS
PHP PHPStan         PASS     Level 8, 0 errors
PHP PHPUnit         PASS     142 tests, 0 failures
PHP Coverage        PASS     84% (threshold: 80%)
PHP Audit           PASS     0 vulnerabilities
Go gofmt            PASS
Go vet              PASS
Go Tests (race)     PASS     38 tests
Go Coverage         PASS     86%
Go govulncheck      PASS
JS ESLint           PASS
JS TypeScript       PASS
JS Tests            PASS     56 tests
JS Audit            PASS
──────────────────────────────────────────────────────
GATE: OPEN — safe to merge
```

If any check fails:
```
GATE: CLOSED — fix [PHP PHPUnit] before merge
```
