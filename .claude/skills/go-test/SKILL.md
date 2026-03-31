---
name: go-test
description: Run Go tests, parse failures, and offer targeted fixes. Mirrors PHPUnit skill for Go.
argument-hint: <package path or 'all'>
---

Run Go tests and fix failures. Triggers when working in `*.go` files and tests are mentioned or failing.

## Trigger Phrases
"run go tests", "go test failing", "fix go test", "test failing in go", "go test ./..."

## Steps

1. **Determine scope** — from $ARGUMENTS: specific package path, or `./...` for all packages

2. **Run tests with race detector**:
   ```bash
   go test -race -count=1 -v ./... 2>&1
   ```
   Or for specific package: `go test -race -count=1 -v ./pkg/payment/...`

3. **Parse output** — identify lines starting with `--- FAIL:` and `FAIL` summary lines
   - Extract: test name, file:line of failure, error message
   - Group by package

4. **For each failure**:
   - Read the failing test function
   - Read the source function being tested
   - Identify root cause in one sentence

5. **Present findings**:
   ```
   FAILED: TestPurchaseRequest/missing_amount (payment/iso8583_test.go:47)
   Root cause: Amount field not zero-padded to 12 digits
   ```

6. **Ask the developer**: "Fix all / fix one by one / show only / abort?"

7. **After fix**: verify with targeted run:
   ```bash
   go test -run TestPurchaseRequest ./pkg/payment/ -v
   ```
   Then full suite: `go test -race ./...`

8. **Coverage check** (if requested):
   ```bash
   go test -coverprofile=coverage.out ./... && go tool cover -func=coverage.out
   ```

## Output Format
- List of failures with root cause
- Fix proposal (diff-style)
- Verification result after fix
