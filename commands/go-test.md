---
name: go-test
description: Run Go tests with race detector, parse failures, and offer targeted fixes
allowed_tools: ["Bash", "Read", "Write", "Grep"]
---

# /go-test

## Goal
Run the Go test suite with the race detector, parse any failures, and offer to fix them. Focuses on payment packages first.

## Steps
1. Run tests with race detector:
   ```bash
   go test -race -timeout 120s -v ./... 2>&1
   ```
2. Parse output for failures:
   - `FAIL` lines indicate failing tests
   - `DATA RACE` indicates a race condition
   - `panic:` indicates unexpected panics
3. For each failure:
   - Read the test file and the implementation file it tests
   - Identify root cause: wrong assertion, missing mock, race condition, or implementation bug
   - Propose a targeted fix
4. After fixing, re-run only the failing test:
   ```bash
   go test -race -run TestSpecificName ./package/...
   ```
5. Then re-run full suite to confirm no regressions:
   ```bash
   go test -race ./...
   ```
6. Report coverage for changed packages:
   ```bash
   go test -coverprofile=coverage.out ./...
   go tool cover -func=coverage.out | grep -v "100.0%"
   ```

## Output
```
GO TEST
────────────────────────────────────────────────
Run: go test -race -timeout 120s ./...
────────────────────────────────────────────────
PASS: internal/payment (12 tests)
FAIL: internal/host (1 failure)
────────────────────────────────────────────────
Failure: TestHostClient_Authorise/host_timeout
  File: internal/host/client_test.go:88
  Error: expected status "pending", got "error"

Root cause: timeout handler returns error instead of pending status
Fix applied: internal/host/client.go:45 — return pending on 504

Re-run: TestHostClient_Authorise → PASS
Full suite: go test -race ./... → PASS (38 tests)
────────────────────────────────────────────────
Coverage: internal/host: 87%
```
