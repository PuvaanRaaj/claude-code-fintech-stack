---
name: db-migrate
description: Run Laravel migrations safely — env check, destructive detection, rollback on failure
allowed_tools: ["Bash", "Read", "Grep"]
---

# /db-migrate

## Goal
Run Laravel database migrations with safety checks. Detects destructive changes, checks the target environment, reminds about backups for payment tables, and rolls back automatically on failure.

## Steps
1. Check current environment:
   ```bash
   php artisan env
   ```
   Warn loudly if APP_ENV is `production`.

2. Check migration status:
   ```bash
   php artisan migrate:status
   ```
   List pending migrations and flag any that affect payment tables.

3. Scan pending migrations for destructive operations:
   ```bash
   grep -n "dropColumn\|dropTable\|drop(\|->change()" database/migrations/*.php
   ```
   If found: require explicit confirmation before proceeding.

4. If migration touches `transactions`, `cards`, `settlements`, or `audit_logs`:
   - Output: "HIGH CAUTION TABLE — ensure database backup taken before proceeding"
   - Do not auto-proceed in production environment

5. Run with pretend first to preview SQL:
   ```bash
   php artisan migrate --pretend
   ```

6. Run migration:
   ```bash
   php artisan migrate --force
   ```

7. If migration fails, rollback the last batch:
   ```bash
   php artisan migrate:rollback
   ```
   Report what was rolled back.

8. Confirm final state:
   ```bash
   php artisan migrate:status
   ```

## Output
```
DB MIGRATE
────────────────────────────────────────────────
Environment: local (safe to proceed)
Pending migrations: 1
  2024_01_15_103000_add_acquirer_ref_to_transactions.php
    Table: transactions ← HIGH CAUTION TABLE
    Change: ADD COLUMN acquirer_ref (nullable, no data risk)
────────────────────────────────────────────────
Pretend (SQL preview):
  ALTER TABLE `transactions` ADD `acquirer_ref` VARCHAR(24) NULL AFTER `auth_code`;
────────────────────────────────────────────────
Running migration... SUCCESS
────────────────────────────────────────────────
migrate:status: All migrations up to date
────────────────────────────────────────────────
DONE
```
