---
name: code-review
description: Code review workflow using git diff — PHP/Laravel, Go, and JS/TS checks plus payment-specific verification for idempotency, decimal amounts, response code handling, and PCI data exposure.
origin: fintech-stack
---

# Code Review

A code review in a payment system is a compliance checkpoint, not just a quality check. A `dd()` left in a payment controller is a PCI violation. An unhandled timeout creates pending transactions that may never resolve. This skill encodes the layer-by-layer review checklist for PHP, Go, and JS/TS with payment-specific additions.

## When to Activate

- Developer asks for a code review, "check my changes", or "review before commit"
- `git diff --staged` shows changes ready for review
- Part of the verification loop before opening a PR

---

## Gathering the Diff

```bash
# Staged changes (pre-commit)
git diff --staged

# All uncommitted changes
git diff

# Branch diff against main
git diff main...HEAD
```

---

## PHP / Laravel Checks

- `declare(strict_types=1)` present at top of every `.php` file
- Return types declared on every method (including `void`)
- No `dd()`, `var_dump()`, `dump()`, `print_r()` left in
- No hardcoded secrets, API keys, or credentials
- `Http::fake()` used in tests — no real HTTP calls in test suite
- `authorize()` implemented in FormRequest classes
- Eloquent `$hidden` array covers sensitive fields (`pan`, `cvv`, `track_data`)
- No raw SQL unless absolutely necessary
- `readonly` or `private readonly` for injected dependencies
- PHPStan level 8 would pass (no type errors, no unhandled nulls)
- Pint formatting applied

---

## Go Checks

- All errors handled — no `_ = err`
- Errors wrapped with `fmt.Errorf("context: %w", err)`
- Context passed as first parameter to all I/O functions
- No `context.Background()` in non-test code (use passed-in context)
- Goroutines have a clear termination path
- `defer wg.Done()` immediately after `wg.Add(1)` in goroutines
- `gofmt` applied — zero formatting differences
- No `panic()` in production code (except init)
- Exported types and functions have doc comments

---

## JS / TS Checks

- No `any` types — use explicit types or `unknown`
- No `console.log` statements left in
- `useEffect` returns a cleanup function where subscriptions are created
- React keys are stable (not array index unless list is static)
- No raw card data stored in state or context
- Error boundaries in place for payment components
- `async/await` with `try/catch` (not unhandled promise rejections)

---

## Payment-Specific Checks

- Idempotency key required and validated for all state-mutating endpoints
- Amount is integer (minor units) — never `float` for money
- Currency code validated against an allowlist
- Response codes from payment host checked explicitly (not just truthy)
- Full PAN not logged, displayed, or stored beyond tokenisation point
- CVV not stored after authorisation
- Timeout handled and transaction marked `pending` (not `failed`)
- Reversal logic exists for timeout scenarios

---

## Quick Security Scan

```bash
# Check for debug output in staged changes
git diff --staged | grep -E '\+.*dd\(|var_dump|console\.log'

# Check for disabled TLS
git diff --staged | grep -E 'InsecureSkipVerify|CURLOPT_SSL_VERIFYPEER.*false|verify.*=.*False'

# Check for PAN patterns in diff
git diff --staged | grep -E '\b4[0-9]{12,15}\b|\b5[1-5][0-9]{14}\b'

# Check for hardcoded secrets
git diff --staged | grep -Ei '(secret|password|token|key)\s*=\s*["\x27][^"\x27]{8,}'
```

---

## Review Output Format

```
CODE REVIEW — staged changes
────────────────────────────────────────────────────────────────────
Severity  File:Line                           Issue                         Fix
────────────────────────────────────────────────────────────────────
BLOCK     app/Services/PayService.php:55      dd() left in production code  Remove
BLOCK     internal/host/client.go:33          Error discarded (_ = err)     Handle or wrap
HIGH      app/Models/Transaction.php:22       Missing $hidden for 'pan'     Add to $hidden
HIGH      src/components/PayForm.tsx:88       Card number in useState       Clear on blur/unmount
MEDIUM    app/Rules/CardRule.php:15           Missing return type on handle() Add: bool
LOW       internal/payment/service.go:40      Exported func missing godoc   Add comment
────────────────────────────────────────────────────────────────────
Security scan: PASS — no PAN patterns, no debug code, no disabled TLS
────────────────────────────────────────────────────────────────────
VERDICT: BLOCKED — 2 BLOCK-level issues must be resolved before commit
```

---

## Best Practices

- **BLOCK = do not commit** — any `dd()`, discarded error, or disabled TLS is a hard block
- **HIGH = fix before merge** — data exposure and missing auth checks must be resolved before the PR merges, not after
- **Run the security scan on every review** — PAN patterns in a diff are a PCI incident waiting to happen
- **Automate what can be automated** — Pint and gofmt findings should not appear in a human review; enforce in CI
- **Flag payment-specific issues separately** — team members without payment context may not recognise a missing idempotency key as a bug
