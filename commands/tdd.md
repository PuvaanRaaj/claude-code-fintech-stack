---
name: tdd
description: Start a TDD cycle — write failing test, implement, verify green, refactor
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /tdd

## Goal
Run a complete Red→Green→Refactor TDD cycle. Works for PHPUnit (Laravel), Go test, Vitest, and Bun test. Always writes the test before the implementation.

## Steps
1. Ask (or infer from context): what behaviour needs to be tested?
2. Identify test file location:
   - PHP: `tests/Unit/` or `tests/Feature/`
   - Go: `{package}_test.go` alongside the package
   - JS: `{component}.test.ts` alongside the component
3. Write the failing test — include happy path AND failure paths (decline, timeout, invalid input)
4. Run to confirm RED:
   - PHP: `./vendor/bin/phpunit --filter TestClassName`
   - Go: `go test -run TestName ./...`
   - JS: `bun test --filter TestName`
5. Write minimum implementation to make test pass
6. Run again to confirm GREEN
7. Run full suite to ensure no regressions:
   - PHP: `./vendor/bin/phpunit`
   - Go: `go test -race ./...`
   - JS: `bun test`
8. Refactor if needed, then re-run step 6
9. Check coverage — must be 80%+ for payment packages:
   - PHP: `./vendor/bin/phpunit --coverage-text`
   - Go: `go test -coverprofile=coverage.out ./...`

## Output
```
TDD CYCLE
─────────────────────────────────────────
Test written: tests/Feature/Payment/ProcessPaymentTest.php
─────────────────────────────────────────
RED   ✗  Test fails (expected — no implementation yet)
─────────────────────────────────────────
[Implementation written]
─────────────────────────────────────────
GREEN ✓  Test passes
SUITE ✓  Full suite passes (142 tests, 0 failures)
─────────────────────────────────────────
Coverage: 84% (threshold: 80%) ✓
─────────────────────────────────────────
CYCLE COMPLETE
```
