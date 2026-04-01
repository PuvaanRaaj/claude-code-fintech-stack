---
name: code-review
description: Review staged changes — applies code-reviewer checklist, outputs severity table and verdict
allowed_tools: ["Bash", "Read", "Grep"]
---

# /code-review

## Goal
Review all staged changes before committing. Applies PHP, Go, JS/TS, and payment-specific checklists. Outputs a findings table and a clear APPROVED or BLOCKED verdict.

## Steps
1. Run `git diff --staged` to get all staged changes
2. If no staged changes, run `git diff` (unstaged) and note this
3. For each changed file, apply the relevant checklist:
   - `.php` files: strict_types, return types, no dd(), Pint style, PCI rules
   - `.go` files: error handling, gofmt, context propagation, no goroutine leaks
   - `.ts`/`.tsx`/`.vue` files: no any, no console.log, stable keys, PCI-safe form patterns
4. Run security quick-scan:
   ```bash
   git diff --staged | grep -E '\+.*dd\(|var_dump|console\.log'
   git diff --staged | grep -E 'InsecureSkipVerify|CURLOPT_SSL_VERIFYPEER.*false'
   git diff --staged | grep -E '\b4[0-9]{12,15}\b|\b5[1-5][0-9]{14}\b'
   ```
5. Check payment-specific issues: idempotency keys, amount as integer, currency validation, response code handling
6. Aggregate findings into severity table
7. Issue verdict:
   - APPROVED: no BLOCK or HIGH findings
   - NEEDS CHANGES: HIGH findings present
   - BLOCKED: any BLOCK finding

## Output
```
CODE REVIEW — git diff --staged
────────────────────────────────────────────────────────
Severity  File:Line                     Issue                     Fix
────────────────────────────────────────────────────────
HIGH      app/Services/PayService.php:42  Missing return type    Add: Transaction
LOW       tests/Feature/PayTest.php:88    Missing timeout test   Add test case
────────────────────────────────────────────────────────
Security: PASS
Payment checks: PASS
────────────────────────────────────────────────────────
VERDICT: NEEDS CHANGES — resolve HIGH findings before commit
```
