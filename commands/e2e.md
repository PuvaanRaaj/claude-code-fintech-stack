---
name: e2e
description: Write or run E2E tests for a payment flow using Playwright — PCI-safe test cards only
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /e2e

## Goal
Write or run Playwright end-to-end tests for payment flows. Always uses scheme test cards — never real card numbers. Covers approved, declined, and 3DS flows.

## Steps
1. If writing tests:
   - Check `e2e/fixtures/test-cards.ts` exists — create if not
   - Write test in `e2e/{feature}/` directory
   - Cover: approved flow, declined flow, 3DS flow (if applicable)
   - PCI rule: no real PAN patterns — test cards only
2. If running tests:
   ```bash
   bun x playwright test 2>&1
   ```
   Or target a specific file:
   ```bash
   bun x playwright test e2e/payment/checkout.spec.ts 2>&1
   ```
3. Parse failures:
   - Timeout: increase `timeout` or use `waitForURL` / `waitForResponse`
   - Element not found: check selector, add `data-testid` attribute
   - Flaky test: mark with `test.slow()`, add retry, use stable assertions
4. For CI failures, check screenshots and traces in `test-results/`
5. After writing new tests, run in headed mode for local verification:
   ```bash
   bun x playwright test --headed e2e/payment/checkout.spec.ts
   ```

## Output
```
E2E TEST RUN
────────────────────────────────────────────────
Run: bun x playwright test
────────────────────────────────────────────────
PASS: checkout flow — approved Visa payment (2.1s)
PASS: checkout flow — declined card shows error (1.8s)
FAIL: checkout flow — 3DS challenge flow (timeout)
────────────────────────────────────────────────
Failure: 3DS challenge — waitForURL timed out after 5000ms
Root cause: 3DS redirect URL pattern doesn't match /acs|challenge/
Fix: updated pattern to /3ds-challenge/ in waitForURL assertion

Re-run: 3DS test → PASS
Full suite: 3 passed, 0 failed
────────────────────────────────────────────────
ALL E2E TESTS PASS
```
