---
name: php-test
description: Run PHPUnit tests, parse failures, and offer fixes — supports feature and unit test suites
allowed_tools: ["Bash", "Read", "Write", "Grep"]
---

# /php-test

## Goal
Run the PHPUnit test suite, parse failures, diagnose root cause, and offer to fix them. Supports targeting specific test classes or running the full suite.

## Steps
1. Run the full test suite:
   ```bash
   ./vendor/bin/phpunit --stop-on-failure 2>&1
   ```
   Or target a specific class:
   ```bash
   ./vendor/bin/phpunit --filter ClassName 2>&1
   ```
2. Parse output for:
   - `FAILED` — assertion failure with expected vs actual values
   - `ERROR` — exception thrown during test (setup issue, missing mock)
   - `RISKY` — test has no assertions
3. For each failure:
   - Read the test file at the failing line
   - Read the class under test
   - Identify: wrong assertion, missing Http::fake(), DB state issue, or implementation bug
4. Propose a fix — always fix the implementation, not the test (unless the test is wrong)
5. Re-run the failing test to confirm green:
   ```bash
   ./vendor/bin/phpunit --filter FailingTestName
   ```
6. Run full suite to confirm no regressions:
   ```bash
   ./vendor/bin/phpunit
   ```
7. Report coverage for changed files:
   ```bash
   ./vendor/bin/phpunit --coverage-text
   ```

## Output
```
PHP TEST
────────────────────────────────────────────────
Run: ./vendor/bin/phpunit
────────────────────────────────────────────────
PASS: 140 tests
FAIL: 2 tests
────────────────────────────────────────────────
Failure 1: ProcessPaymentTest::test_timeout_returns_pending
  File: tests/Feature/Payment/ProcessPaymentTest.php:88
  Expected: status "pending"
  Actual:   status "error"
  Root cause: PaymentService returns error on 504 — should return pending
  Fix applied: app/Services/PaymentService.php:55

Failure 2: TransactionRepositoryTest::test_creates_with_correct_status
  File: tests/Unit/Repositories/TransactionRepositoryTest.php:42
  Error: SQLSTATE[42S02]: Table 'transactions' doesn't exist
  Root cause: Migration not run in test setup
  Fix: php artisan migrate --env=testing

────────────────────────────────────────────────
Re-run: 142 tests, 0 failures
Coverage: 84%
────────────────────────────────────────────────
ALL TESTS PASS
```
