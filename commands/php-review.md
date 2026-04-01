---
name: php-review
description: Review PHP/Laravel code — strict_types, return types, PCI rules, Pint compliance, test coverage
allowed_tools: ["Bash", "Read", "Grep"]
---

# /php-review

## Goal
Review PHP/Laravel code against the fintech stack's PHP standards and PCI-DSS rules. Covers code style, type safety, security, and test coverage.

## Steps
1. Run automated checks:
   ```bash
   ./vendor/bin/pint --test 2>&1           # formatting
   ./vendor/bin/phpstan analyse 2>&1       # static analysis
   ```
2. Review `git diff --staged` (or specified file) for:
   - `declare(strict_types=1)` on every `.php` file
   - Return types on every method (including `void`)
   - `readonly` or `private readonly` for injected dependencies
   - `authorize()` implemented in all FormRequest classes
   - `$hidden` covers `pan`, `cvv`, `track_data`, `pin` on models
   - No `dd()`, `var_dump()`, `dump()`, `print_r()`
   - No raw SQL (`DB::statement`, `whereRaw` with user input)
   - No hardcoded credentials
3. PCI checks:
   - Full PAN not logged (check Log:: calls near card fields)
   - CVV not persisted after authorisation
   - TLS not disabled (`CURLOPT_SSL_VERIFYPEER`)
4. Test coverage check for changed service/feature files:
   ```bash
   ./vendor/bin/phpunit --coverage-text --filter RelatedTestName
   ```
5. Output findings table

## Output
```
PHP REVIEW
────────────────────────────────────────────────────────
Severity  File:Line                          Issue                        Fix
────────────────────────────────────────────────────────
BLOCK     app/Services/PayService.php:55     dd() in production code     Remove
HIGH      app/Models/Transaction.php:22      Missing 'pan' in $hidden    Add to $hidden
MEDIUM    app/Http/Requests/PayRequest.php:8 Missing authorize() check   Implement method
LOW       app/Services/PayService.php:10     Missing return type         Add: Transaction
────────────────────────────────────────────────────────
Pint:     PASS
PHPStan:  PASS (level 8)
Coverage: 84% for changed files
────────────────────────────────────────────────────────
VERDICT: BLOCKED — remove dd() before commit
```
