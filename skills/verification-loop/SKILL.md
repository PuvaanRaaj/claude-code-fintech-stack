---
name: verification-loop
description: Full pre-PR verification loop — build, lint, static analysis, tests, security scan, and diff review across PHP/Laravel, Go, and JS/TS stacks.
origin: fintech-stack
---

# Verification Loop

Before opening a pull request, every change should pass the same checks that CI will run — without waiting for CI feedback. This skill runs the full stack check locally and produces a go/no-go verdict.

## When to Activate

- Developer says "verify", "ready for PR", "run all checks", or "verification loop"
- Before creating a pull or merge request
- After a large refactor or feature implementation

---

## Detect the Stack

Inspect the project root for `composer.json`, `go.mod`, `package.json`, or `bun.lockb` to determine which phases apply.

---

## PHP / Laravel Phases

```bash
# Phase 1: Install / ensure deps
composer install --no-interaction --prefer-dist

# Phase 2: Lint (Pint)
./vendor/bin/pint --test

# Phase 3: Static analysis (PHPStan)
./vendor/bin/phpstan analyse --memory-limit=512M

# Phase 4: Unit + Feature tests
./vendor/bin/phpunit --stop-on-failure

# Phase 5: Security audit
composer audit
```

---

## Go Phases

```bash
# Phase 1: Build
go build ./...

# Phase 2: Format check (fail if any files are unformatted)
gofmt -l .

# Phase 3: Vet
go vet ./...

# Phase 4: Tests with race detector
go test -race -timeout 120s ./...

# Phase 5: Lint
golangci-lint run ./...
```

---

## JS / TS Phases

```bash
# Phase 1: Build
bun run build

# Phase 2: Type check
bun x tsc --noEmit

# Phase 3: Lint (zero warnings)
bun x eslint . --max-warnings 0

# Phase 4: Tests
bun test
```

---

## Diff Review

```bash
git diff main...HEAD --stat
git diff main...HEAD
```

Scan for:
- `dd()`, `var_dump()`, `console.log` left in
- Hardcoded secrets or credentials
- TODOs that must be resolved before merge
- Missing test coverage for changed files

---

## Verification Report

```
VERIFICATION REPORT
────────────────────────────────────────────────
Phase               Status   Details
────────────────────────────────────────────────
[PHP] Install       PASS
[PHP] Pint lint     PASS
[PHP] PHPStan       PASS     Level 8, 0 errors
[PHP] PHPUnit       PASS     142 tests, 0 failures
[PHP] Audit         PASS     0 vulnerabilities
────────────────────────────────────────────────
[Go] Build          PASS
[Go] gofmt          PASS
[Go] go vet         PASS
[Go] Tests (race)   PASS     38 tests
[Go] golangci-lint  PASS
────────────────────────────────────────────────
[JS] Build          PASS
[JS] TypeScript     PASS
[JS] ESLint         PASS
[JS] Tests          PASS     56 tests
────────────────────────────────────────────────
Diff review         PASS     No debug code, no secrets
────────────────────────────────────────────────
OVERALL: READY FOR PR
```

If any phase fails:
```
OVERALL: NOT READY — fix [PHP] PHPStan before proceeding
```

---

## Best Practices

- **Run the verification loop before every PR** — catching issues locally is faster than waiting for CI
- **Stop on first failure per phase** — use `--stop-on-failure` for PHPUnit; fix before moving to the next phase
- **Race detector is non-optional for Go** — goroutine data races in payment code cause silent corruption
- **Zero lint warnings** — a warning budget leads to hundreds of suppressed warnings; start at zero and hold the line
- **Automate this** — wire the verification loop to a pre-push hook so it runs before `git push` without manual invocation
