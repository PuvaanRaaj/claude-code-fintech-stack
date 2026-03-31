---
name: db-migrate
description: Run Laravel database migrations safely — detects destructive changes, validates rollback path, warns on production environments
argument-hint: <up|rollback|status|create <name>>
---

Run Laravel migrations safely. Triggers on "run migration", "migrate database", "create migration".

## Trigger Phrases
"run migration", "migrate database", "rollback migration", "create migration", "artisan migrate"

## Steps

1. **Check environment** — read `APP_ENV` from `.env`:
   - `production` → STOP. Require explicit `--force` acknowledgment
   - `staging` / `uat` → WARN. Confirm before proceeding
   - `local` / `testing` → proceed

2. **For `status`**: `php artisan migrate:status` — show pending migrations

3. **For `create`**: `php artisan make:migration <name> --table=<table>` — remind to set `$table->timestamps()`

4. **Destructive change detection** — grep new migration file for:
   - `->dropColumn(` → WARN: data will be lost
   - `->dropTable(` / `Schema::drop(` → WARN: full table drop
   - `->change()` → INFO: column change, check rollback
   - `->truncate()` → BLOCK: never truncate in migration

5. **Payment table flag** — if migration touches `transactions`, `cards`, `settlements`, `payment_logs`:
   - Require PCI review confirmation before running
   - Suggest: add to PCI change log

6. **Run migration**: `php artisan migrate`
   - On failure: `php artisan migrate:rollback --step=1`
   - Capture output, report which migrations ran

7. **Verify**: `php artisan migrate:status` after run — confirm all show `Ran`

## Output Format
- ENV check result
- Destructive changes detected (if any)
- Migration output
- Final status table
