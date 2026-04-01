---
name: update-docs
description: Sweep changed files and update all related documentation and Swagger annotations
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /update-docs

## Goal
After code changes, find every documentation artifact that needs updating and update it. Covers Swagger annotations, inline comments, README, and CHANGELOG. Leaves no stale docs behind.

## Steps
1. Get list of changed files:
   ```bash
   git diff --name-only main...HEAD
   ```
2. For each changed PHP controller:
   - Check `@OA\` annotations match current request/response structure
   - Update parameter types, required fields, and response schemas
   - Run `php artisan l5-swagger:generate` and verify no errors
3. For each changed service or utility:
   - Check PHPDoc / GoDoc blocks are accurate
   - Update `@param` and `@return` tags if signatures changed
   - Add inline comments to non-obvious logic introduced in this PR
4. For each changed API route:
   - Update `README.md` API section if it contains manual endpoint docs
   - Update Postman collection or API spec if stored in `docs/`
5. Check CHANGELOG.md:
   - If new features: add to `[Unreleased] Added`
   - If bug fixes: add to `[Unreleased] Fixed`
   - If breaking changes: add to `[Unreleased] Changed` with migration note
6. Check `CLAUDE.md` — if new patterns established, update the architecture section
7. Report every file updated

## Output
```
DOCS UPDATE
────────────────────────────────────────────────
Changed files: 6

Documentation updated:
  [SWAGGER]   app/Http/Controllers/RefundController.php
              Added @OA\Post for POST /api/v1/payments/{id}/refund
  [PHPDOC]    app/Services/RefundService.php
              Updated @param and @return on calculate()
  [COMMENT]   app/Services/RefundService.php:88
              Added inline comment explaining pro-rata calculation
  [CHANGELOG] CHANGELOG.md
              Added refund endpoint and bug fix entries
  [README]    README.md
              Updated API endpoints table

Swagger regenerated: PASS
────────────────────────────────────────────────
DOCS UP TO DATE
```
