---
name: docs
description: Update documentation after code changes — Swagger annotations, README, CHANGELOG, inline comments
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /docs

## Goal
Keep documentation in sync with code changes. Covers Swagger/OpenAPI annotations on controllers, README updates, CHANGELOG entries, and inline comments on complex logic.

## Steps
1. Run `git diff --staged` (or `git diff main...HEAD`) to see what changed
2. For each changed controller/endpoint:
   - Check `@OA\` annotations are present and accurate
   - Update request/response schema if parameters changed
   - Run `php artisan l5-swagger:generate` (or equivalent) to regenerate docs
3. For each changed service or utility:
   - Check inline comments explain non-obvious logic
   - Update or add PHPDoc / GoDoc blocks
4. If new features added, add CHANGELOG entry under `[Unreleased]`:
   ```markdown
   ## [Unreleased]
   ### Added
   - `POST /api/v1/payments/{id}/refund` — initiate partial or full refund
   ### Changed
   - Transaction status `timeout` renamed to `pending`
   ### Fixed
   - Idempotency key not validated on refund endpoint
   ```
5. If README references outdated commands or setup steps, update them
6. Confirm Swagger UI renders correctly:
   ```bash
   php artisan l5-swagger:generate && open http://localhost/api/documentation
   ```

## Output
```
DOCS UPDATE
────────────────────────────────────────────────
Changes detected:
  app/Http/Controllers/RefundController.php — new endpoint POST /refund

Actions taken:
  [UPDATED] @OA\Post annotation on RefundController::store()
  [UPDATED] CHANGELOG.md — added refund endpoint under [Unreleased]
  [ADDED]   Inline comment on RefundService::calculate() explaining proration

Swagger generated: PASS
CHANGELOG: Updated
────────────────────────────────────────────────
DONE
```
