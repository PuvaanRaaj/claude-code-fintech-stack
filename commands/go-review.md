---
name: go-review
description: Review Go code — gofmt, go vet, error handling, goroutine hygiene, context propagation
allowed_tools: ["Bash", "Read", "Grep"]
---

# /go-review

## Goal
Review Go code against the fintech stack's Go standards. Catches the most common Go mistakes in payment services: discarded errors, missing context, goroutine leaks, and formatting issues.

## Steps
1. Run tooling checks:
   ```bash
   gofmt -l .                    # list unformatted files
   go vet ./...                  # static analysis
   go build ./...                # compilation check
   golangci-lint run ./...       # extended lint (if installed)
   ```
2. Review `git diff --staged` (or the specified file) for:
   - `_ = err` — discarded errors
   - `context.Background()` in non-test code — should use passed-in context
   - `go func()` without `defer wg.Done()` or channel receive — goroutine leak risk
   - `panic()` outside of `init()` or test code
   - Missing `fmt.Errorf("context: %w", err)` wrapping
   - Exported functions without doc comments
   - Interfaces defined where they are used, not where they are implemented
3. Payment-specific Go checks:
   - TCP connections have deadlines set before read/write
   - ISO 8583 field lengths validated before parsing
   - Connection pool has bounded size
   - Graceful shutdown handles in-flight payment requests
4. Output findings table with file:line, issue, and fix

## Output
```
GO REVIEW
────────────────────────────────────────────────────────────
Severity  File:Line                    Issue                          Fix
────────────────────────────────────────────────────────────
BLOCK     internal/host/client.go:33  Error discarded (_ = err)     Handle or wrap
HIGH      cmd/main.go:88              context.Background() in handler Use r.Context()
MEDIUM    internal/pool/pool.go:52    Goroutine without done signal   Add wg.Done()
LOW       internal/payment/service.go:10  Missing godoc on Process()  Add comment
────────────────────────────────────────────────────────────
gofmt:          PASS
go vet:         PASS
golangci-lint:  1 finding
────────────────────────────────────────────────────────────
VERDICT: BLOCKED — fix discarded error before commit
```
