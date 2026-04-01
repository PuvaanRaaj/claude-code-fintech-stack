---
name: refactor-clean
description: Clean up code — reduce duplication, extract services, improve naming, remove dead code
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /refactor-clean

## Goal
Improve code quality without changing behaviour. Target: reduce duplication, extract misplaced logic, improve naming, and remove dead code. Run tests before and after to prove nothing broke.

## Steps
1. Run tests to establish baseline (must be green before starting):
   ```bash
   ./vendor/bin/phpunit   # or: go test ./...   or: bun test
   ```
2. Identify refactor targets:
   - Duplicated logic (copy-paste across files)
   - Controllers with business logic (extract to service)
   - Long methods (> 20 lines doing multiple things)
   - Magic numbers/strings (extract to constants or config)
   - Dead code (unreachable, unused methods, commented-out blocks)
3. Apply one change at a time — run tests after each
4. Naming improvements:
   - PHP: `processIt()` → `authorisePayment()`, `$data` → `$paymentDto`
   - Go: `doThing()` → `authorise()`, `res` → `hostResponse`
5. Extraction pattern:
   - Move logic from controller → service class
   - Move DB query from service → repository class
   - Move repeated validation → shared FormRequest or validator
6. Remove dead code — confirm with `git log` that it's not referenced elsewhere
7. Run full test suite after all changes to confirm no regression

## Output
```
REFACTOR CLEAN
────────────────────────────────────────────────
Baseline: 142 tests PASS

Changes:
  [EXTRACTED] PaymentController::process() → PaymentService::process()
  [RENAMED]   $data → $paymentDto in 3 files
  [REMOVED]   Dead method Transaction::legacyFormat() (unused since 2023-06)
  [EXTRACTED] Duplicate amount validation → AmountValidator trait

After refactor: 142 tests PASS (no regression)
────────────────────────────────────────────────
REFACTOR COMPLETE
```
