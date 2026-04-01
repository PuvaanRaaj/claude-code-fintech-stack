---
name: database-migrations
description: Safe database migration patterns for financial systems — pre-migration checklist, zero-downtime column changes, rollback plans, and audit log table conventions for payment-critical tables.
origin: fintech-stack
---

# Database Migrations

In financial systems, a bad migration is not just a bug — it can take a merchant offline, corrupt a settlement record, or lock the `transactions` table during peak processing. Every migration affecting a payment-critical table requires a pre-flight checklist, a working `down()` method, and a documented rollback plan before it touches staging.

## When to Activate

- Writing or reviewing any database migration
- Schema changes touching `transactions`, `cards`, `settlements`, or `audit_logs`
- Developer asks "how do I safely migrate?" or "zero-downtime schema change"

---

## Pre-Migration Checklist

Before writing any migration:
- [ ] Confirm target environment (`APP_ENV`)
- [ ] Take a database backup before running in staging/production
- [ ] Check `php artisan migrate:status` — no pending broken migrations
- [ ] Is this change destructive? (column drop, table drop, type change)

```bash
php artisan migrate:status
```

---

## Payment Table Caution

Extra review required for migrations on these tables:

- `transactions` — core payment record; any change affects reporting and reconciliation
- `cards` / `card_tokens` — tokenised card data; encryption requirements apply
- `settlements` — financial ledger; wrong schema breaks settlement reconciliation
- `audit_logs` — append-only by design; never add UPDATE/DELETE capability
- `merchant_config` — live payment routing; a bad migration takes a merchant offline

For these tables: always pair the migration with a DB backup step and a documented rollback plan.

---

## Migration Structure

Every migration MUST have a working `down()` method:

```php
<?php declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table): void {
            $table->string('acquirer_ref', 24)->nullable()->after('auth_code');
        });
    }

    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table): void {
            $table->dropColumn('acquirer_ref');
        });
    }
};
```

---

## Zero-Downtime Patterns

**Adding a column** — safe, add as nullable first, backfill, then add NOT NULL in a later migration:

```php
// Migration 1: add nullable
$table->string('new_field')->nullable()->after('existing_field');

// After deploy + backfill complete:
// Migration 2: enforce NOT NULL
$table->string('new_field')->nullable(false)->change();
```

**Renaming a column** — three-deploy process:
1. Add new column, keep old; dual-write in app code
2. Backfill old → new; switch reads to new column
3. Drop old column

**Removing a column** — never in the same deploy as code removal:
1. Deploy code that ignores the column
2. Deploy migration to drop it

**Adding an index on a large table:**
```php
$table->index(['merchant_id', 'created_at'], 'idx_transactions_merchant_date');
// For very large tables (avoid lock):
DB::statement('ALTER TABLE transactions ADD INDEX idx_transactions_merchant_date (merchant_id, created_at) ALGORITHM=INPLACE, LOCK=NONE');
```

**Changing a column type** — always test on a copy of production data. Type narrowing (e.g., BIGINT → INT) is dangerous.

---

## Artisan Migration Commands

```bash
# Always check status before running
php artisan migrate:status

# Preview SQL without executing (use in production pre-check)
php artisan migrate --pretend

# Run migrations
php artisan migrate

# Rollback last batch
php artisan migrate:rollback

# Rollback specific number of steps
php artisan migrate:rollback --step=2

# NEVER in production — dev only
php artisan migrate:refresh --seed
```

---

## Audit Log Table Pattern

```php
// audit_logs must be append-only — no updated_at, no soft deletes
Schema::create('audit_logs', function (Blueprint $table): void {
    $table->id();
    $table->string('event_type', 64)->index();
    $table->morphs('subject');             // polymorphic: transaction, card, etc.
    $table->unsignedBigInteger('actor_id')->nullable();
    $table->json('payload');
    $table->string('ip_address', 45)->nullable();
    $table->timestamp('created_at');      // no updated_at — immutable by design
});
// Do NOT call $table->timestamps() — that adds updated_at
```

---

## Rollback Plan Template

Include in every PR description for migrations on payment tables:

```
Migration: add_acquirer_ref_to_transactions
Rollback:  php artisan migrate:rollback (removes column, no data loss)
Data risk: None — new nullable column, no backfill required
Tested on: local MySQL 8.0 with 10k row sample
```

---

## Best Practices

- **Every migration must have a working `down()` method** — "we'll never roll back" is how rollbacks become crises
- **Add nullable first, enforce NOT NULL later** — zero-downtime column additions without locking the table
- **Never drop a column in the same deploy as the code that removes references to it** — deploy code first, then the migration
- **`--pretend` before prod** — review the generated SQL before it runs on production data
- **Migrations on `transactions` require a backup confirmation** — make it a checklist item in the PR template, not tribal knowledge
