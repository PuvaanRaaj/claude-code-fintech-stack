---
name: reconciliation
description: Daily payment reconciliation workflows — settlement file import, transaction matching, discrepancy classification (missing, amount mismatch, float), and resolution playbook for PHP/Laravel and Go.
origin: fintech-stack
---

# Reconciliation

Reconciliation is the process of proving that what your system recorded matches what the bank actually settled. Discrepancies are not bugs to silently fix — they are potential fraud signals, host errors, or double charges that require documented resolution. This skill covers importing settlement files, matching them against internal records, and classifying what doesn't match.

## When to Activate

- Implementing an end-of-day or on-demand reconciliation command
- Importing a settlement file (CSV, fixed-width) from an acquirer or scheme
- Investigating a reported discrepancy between your records and a bank statement
- Designing the `settlement_records` and `reconciliation_discrepancies` tables

---

## Core Concepts

| Term | Meaning |
|------|---------|
| **Settlement file** | File sent by acquirer listing all settled transactions for a period |
| **Reconciliation** | Matching your internal approved transactions against the settlement file |
| **Float** | Same-day approval that settles the next business day — not a discrepancy yet |
| **Discrepancy** | Transaction present in one source but not the other, or amounts differ |
| **Chargeback** | Scheme-initiated reversal — appears in settlement, must match the original auth |

---

## Database Schema

```sql
CREATE TABLE settlement_records (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    acquirer_reference  VARCHAR(64)   NOT NULL UNIQUE,
    settlement_date     DATE          NOT NULL,
    merchant_id         VARCHAR(32)   NOT NULL,
    amount              BIGINT        NOT NULL,  -- always minor units
    currency            CHAR(3)       NOT NULL,
    transaction_type    VARCHAR(16)   NOT NULL,  -- SALE | REFUND | CHARGEBACK
    auth_code           VARCHAR(16),
    pan_last4           CHAR(4),
    raw_row             JSON,                    -- original row for audit
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_settlement_date (settlement_date),
    INDEX idx_merchant_id (merchant_id)
);

CREATE TABLE reconciliation_discrepancies (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    type                ENUM('missing_internal','missing_settlement','amount_mismatch') NOT NULL,
    acquirer_reference  VARCHAR(64),
    settlement_amount   BIGINT,
    internal_amount     BIGINT,
    currency            CHAR(3),
    resolved            TINYINT(1)    DEFAULT 0,
    resolved_at         TIMESTAMP     NULL,
    resolution_note     TEXT,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_type (type),
    INDEX idx_resolved (resolved)
);
```

---

## Settlement File Importer (PHP)

Idempotent — re-importing the same file is safe.

```php
<?php declare(strict_types=1);

namespace App\Services\Reconciliation;

use App\Models\SettlementRecord;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use League\Csv\Reader;

final class SettlementFileImporter
{
    public function import(string $filepath, string $settlementDate): ImportResult
    {
        $csv = Reader::createFromPath($filepath, 'r');
        $csv->setHeaderOffset(0);

        $imported = 0;
        $skipped  = 0;
        $errors   = [];

        DB::beginTransaction();
        try {
            foreach ($csv->getRecords() as $lineNo => $row) {
                try {
                    SettlementRecord::updateOrCreate(
                        ['acquirer_reference' => $row['ACQUIRER_REF']],
                        [
                            'settlement_date'  => $settlementDate,
                            'merchant_id'      => $row['MERCHANT_ID'],
                            'amount'           => (int) $row['AMOUNT'],  // minor units
                            'currency'         => $row['CURRENCY'],
                            'transaction_type' => $row['TXN_TYPE'],
                            'auth_code'        => $row['AUTH_CODE'] ?? null,
                            'pan_last4'        => $row['PAN_LAST4'] ?? null,
                            'raw_row'          => json_encode($row),
                        ]
                    );
                    $imported++;
                } catch (\Throwable $e) {
                    $errors[] = "Line {$lineNo}: " . $e->getMessage();
                    $skipped++;
                }
            }
            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        Log::info('reconciliation.import.complete', [
            'settlement_date' => $settlementDate,
            'imported'        => $imported,
            'skipped'         => $skipped,
        ]);

        return new ImportResult($imported, $skipped, $errors);
    }
}
```

---

## Reconciliation Engine (PHP)

```php
final class ReconciliationEngine
{
    public function reconcile(string $settlementDate): ReconciliationResult
    {
        $settlement   = SettlementRecord::whereSettlementDate($settlementDate)
                            ->get()->keyBy('acquirer_reference');
        $transactions = Transaction::whereDate('created_at', $settlementDate)
                            ->whereStatus('approved')
                            ->get()->keyBy('acquirer_reference');

        $matched       = 0;
        $discrepancies = [];

        // 1. Walk settlement records — match against internal transactions
        foreach ($settlement as $ref => $record) {
            $tx = $transactions->get($ref);

            if (! $tx) {
                $this->flag('missing_internal', $ref, $record, null);
                $discrepancies[] = ['type' => 'missing_internal', 'ref' => $ref];
                continue;
            }

            if ($tx->amount !== $record->amount || $tx->currency !== $record->currency) {
                $this->flag('amount_mismatch', $ref, $record, $tx);
                $discrepancies[] = [
                    'type'       => 'amount_mismatch',
                    'ref'        => $ref,
                    'internal'   => $tx->amount,
                    'settlement' => $record->amount,
                ];
                continue;
            }

            $tx->update(['reconciled_at' => now(), 'settlement_date' => $settlementDate]);
            $matched++;
        }

        // 2. Find internal transactions absent from settlement file
        foreach ($transactions as $ref => $tx) {
            if (! $settlement->has($ref)) {
                if ($tx->created_at->isToday()) {
                    Log::info('reconciliation.float', ['ref' => $ref, 'tx_id' => $tx->id]);
                } else {
                    $this->flag('missing_settlement', $ref, null, $tx);
                    $discrepancies[] = ['type' => 'missing_settlement', 'ref' => $ref];
                }
            }
        }

        Log::info('reconciliation.complete', [
            'settlement_date' => $settlementDate,
            'matched'         => $matched,
            'discrepancies'   => count($discrepancies),
        ]);

        return new ReconciliationResult($matched, $discrepancies);
    }

    private function flag(string $type, string $ref, ?SettlementRecord $s, ?Transaction $tx): void
    {
        ReconciliationDiscrepancy::create([
            'type'               => $type,
            'acquirer_reference' => $ref,
            'settlement_amount'  => $s?->amount,
            'internal_amount'    => $tx?->amount,
            'currency'           => $s?->currency ?? $tx?->currency,
            'resolved'           => false,
        ]);
    }
}
```

---

## Artisan Command

```php
final class ReconcileSettlement extends Command
{
    protected $signature   = 'payments:reconcile {date?} {--file=}';
    protected $description = 'Import settlement file and reconcile transactions';

    public function handle(SettlementFileImporter $importer, ReconciliationEngine $engine): int
    {
        $date = $this->argument('date') ?? now()->subDay()->toDateString();
        $file = $this->option('file') ?? storage_path("settlement/{$date}.csv");

        if (! file_exists($file)) {
            $this->error("Settlement file not found: {$file}");
            return Command::FAILURE;
        }

        $import = $importer->import($file, $date);
        $this->info("Imported: {$import->imported} | Skipped: {$import->skipped}");

        $result = $engine->reconcile($date);
        $this->info("Matched: {$result->matched}");

        foreach ($result->discrepancies as $d) {
            $this->warn("  [{$d['type']}] {$d['ref']}");
        }

        return $result->discrepancies ? Command::FAILURE : Command::SUCCESS;
    }
}
```

---

## Go — CSV Settlement Parser

```go
type SettlementRecord struct {
    AcquirerRef     string
    MerchantID      string
    Amount          int64  // minor units
    Currency        string
    TransactionType string // SALE | REFUND | CHARGEBACK
    AuthCode        string
    PANL4           string
}

func ParseCSVSettlement(r io.Reader) ([]SettlementRecord, error) {
    reader := csv.NewReader(r)
    headers, err := reader.Read()
    if err != nil {
        return nil, fmt.Errorf("read headers: %w", err)
    }
    idx := headerIndex(headers)
    var records []SettlementRecord

    for {
        row, err := reader.Read()
        if err == io.EOF { break }
        if err != nil { return nil, fmt.Errorf("read row: %w", err) }

        amount, err := strconv.ParseInt(row[idx["AMOUNT"]], 10, 64)
        if err != nil {
            return nil, fmt.Errorf("parse amount %q: %w", row[idx["AMOUNT"]], err)
        }
        records = append(records, SettlementRecord{
            AcquirerRef:     row[idx["ACQUIRER_REF"]],
            MerchantID:      row[idx["MERCHANT_ID"]],
            Amount:          amount,
            Currency:        row[idx["CURRENCY"]],
            TransactionType: row[idx["TXN_TYPE"]],
            AuthCode:        row[idx["AUTH_CODE"]],
            PANL4:           row[idx["PAN_LAST4"]],
        })
    }
    return records, nil
}
```

---

## Discrepancy Resolution Playbook

| Type | Likely Cause | Resolution |
|------|-------------|------------|
| `missing_internal` | Transaction processed by host but not saved (timeout during DB write) | Check host logs; if approved, create transaction record |
| `missing_settlement` | Float — same-day approval, next-day settlement | Re-run next day; raise with acquirer if persists > 3 business days |
| `amount_mismatch` | DCC conversion, acquirer fee deduction, or rounding difference | Compare with scheme-level statement; may require adjustment entry |
| Chargeback ref mismatch | Chargeback reference differs from original auth reference | Match by auth code + amount + date; update `acquirer_reference` |

---

## Best Practices

- **Amount is always in minor units** — never floats; `10000` = MYR 100.00. Mismatch by one unit is a real discrepancy
- **Import is idempotent** — use `updateOrCreate` on `acquirer_reference`; re-running the same file must not create duplicates
- **Float is not a discrepancy on day 1** — same-day approvals that haven't settled yet are expected; mark as float and check the next day
- **Dispatch `payments:reconcile` as a scheduled job** — run it nightly after the settlement file drops, not manually
- **Alert on unresolved discrepancies > 3 days old** — stale discrepancies are escalation items, not backlog
- **Never auto-resolve discrepancies** — always require a human decision and `resolution_note` before marking resolved
