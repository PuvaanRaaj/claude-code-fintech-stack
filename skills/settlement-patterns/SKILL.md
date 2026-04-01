---
name: settlement-patterns
description: Payment settlement patterns — T+1 batch processing, ISO 8583 TC (0500/0510) messages, net vs gross settlement, settlement file validation, cutoff time handling, and recon against acquirer reports.
origin: fintech-stack
---

# Settlement Patterns

Settlement is the process by which authorised transactions are converted into actual fund movements between the acquirer, card scheme, and issuer. A missed cutoff, a mismatched batch total, or a silent file rejection means funds don't move — and the merchant calls your support line at 9 AM wondering where their money is.

## When to Activate

- Building or debugging a settlement batch job that runs at end-of-day
- Constructing ISO 8583 TC (Transaction Capture) messages: MTI 0500, 0510, 0520
- Validating a settlement file against internal transaction records
- Handling net vs gross settlement calculations for payout reconciliation
- Diagnosing cutoff time drift, timezone bugs, or missing records in a recon report
- Implementing recon against an acquirer-provided CSV or fixed-width settlement file

---

## Settlement Flow Overview

```
23:59 MYT — Cutoff
     │
     ▼
Collect all authorised, non-reversed transactions since last cutoff
     │
     ▼
Build ISO 8583 batch: MTI 0500 per transaction + 0520 batch totals
     │
     ▼
Send batch to acquirer host (or deposit settlement file via SFTP)
     │
     ▼
Receive 0510 response per transaction + 0520 batch response
     │
     ▼
T+1 morning: acquirer delivers settlement report (CSV or fixed-width)
     │
     ▼
Recon report: match internal DB against acquirer file line by line
```

Settlement windows typically close at 23:59 MYT (UTC+8). Any authorisation not captured before cutoff rolls into the next business day. Transactions captured after 23:59 MYT are held until the following cutoff.

---

## ISO 8583 TC Batch Messages

| MTI  | Name | Direction | Purpose |
|------|------|-----------|---------|
| 0500 | Capture Request | Merchant → Acquirer | Present one captured transaction for settlement |
| 0510 | Capture Response | Acquirer → Merchant | Confirm individual capture accepted or rejected |
| 0520 | Batch Upload Request | Merchant → Acquirer | Signal end-of-batch with transaction count and totals |
| 0530 | Batch Upload Response | Acquirer → Merchant | Confirm batch accepted or flag discrepancy |

Key fields in a 0500:

| Field | Name | Value |
|-------|------|-------|
| F3 | Processing Code | `000000` (purchase) |
| F4 | Transaction Amount | Minor units, 12 digits, zero-padded |
| F11 | STAN | Original STAN from the 0100 authorisation |
| F37 | Retrieval Reference Number | Echo from original 0110 response |
| F38 | Authorisation Code | Echo from original 0110 F38 |
| F49 | Currency Code | ISO 4217 numeric |
| F60 | Batch Number | Incremented per cutoff cycle |

---

## PHP/Laravel — Settlement Job at Cutoff

```php
<?php

namespace App\Jobs;

use App\Models\Transaction;
use App\Services\Settlement\BatchBuilder;
use App\Services\Settlement\AcquirerClient;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

final class RunSettlementBatch implements ShouldQueue
{
    use Queueable;

    public int $timeout = 300; // 5 min hard limit

    public function handle(BatchBuilder $builder, AcquirerClient $acquirer): void
    {
        $cutoff    = now()->timezone('Asia/Kuala_Lumpur')->startOfMinute(); // 23:59:00 MYT
        $batchNo   = $this->nextBatchNumber();
        $transactions = Transaction::query()
            ->where('status', 'authorised')
            ->where('settled', false)
            ->where('created_at', '<', $cutoff)
            ->lockForUpdate()
            ->get();

        if ($transactions->isEmpty()) {
            Log::info('settlement: no transactions to settle', ['batch' => $batchNo]);
            return;
        }

        DB::transaction(function () use ($transactions, $builder, $acquirer, $batchNo, $cutoff) {
            $batch = $builder->build($transactions, $batchNo);

            foreach ($batch->captures() as $capture) {
                $response = $acquirer->sendCapture($capture); // MTI 0500 → 0510
                if ($response->responseCode() !== '00') {
                    Log::error('settlement: capture rejected', [
                        'stan'    => $capture->stan(),
                        'rrn'     => $capture->rrn(),
                        'rc'      => $response->responseCode(),
                    ]);
                }
            }

            $batchResponse = $acquirer->closeBatch($batch->totals()); // MTI 0520 → 0530
            if (! $batchResponse->accepted()) {
                throw new \RuntimeException("Batch {$batchNo} rejected by acquirer: " . $batchResponse->errorDescription());
            }

            $transactions->each->update(['settled' => true, 'settlement_batch' => $batchNo, 'settled_at' => $cutoff]);
        });

        Log::info('settlement: batch complete', [
            'batch'       => $batchNo,
            'count'       => $transactions->count(),
            'gross_minor' => $transactions->sum('amount_minor'),
        ]);
    }

    private function nextBatchNumber(): int
    {
        return DB::table('settlement_batches')->max('batch_number') + 1;
    }
}
```

Schedule this job to fire at 23:59 MYT:

```php
// routes/console.php
Schedule::job(RunSettlementBatch::class)->dailyAt('23:59')->timezone('Asia/Kuala_Lumpur');
```

---

## Settlement File Structure

Acquirers deliver settlement files as CSV or fixed-width. A typical fixed-width layout:

```
Position  Length  Field
1         1       Record Type (H=header, D=detail, T=trailer)
2         8       Settlement Date (YYYYMMDD)
10        6       Batch Number
16        12      Transaction Amount (minor units, right-justified, zero-padded)
28        12      Retrieval Reference Number
40        6       Authorisation Code
46        2       Response Code
48        3       Currency Code (ISO 4217 numeric)
51        15      Merchant ID
66        8       Terminal ID
74        1       Transaction Type (P=purchase, R=refund, C=chargeback)
```

---

## Net vs Gross Settlement Calculation

```php
final class SettlementCalculator
{
    public function gross(Collection $transactions): int
    {
        // Sum of all purchase amounts (minor units)
        return $transactions
            ->where('type', 'purchase')
            ->sum('amount_minor');
    }

    public function net(Collection $transactions, int $mdrBasisPoints): int
    {
        // Net = gross purchases - refunds - MDR fees
        $purchases = $transactions->where('type', 'purchase')->sum('amount_minor');
        $refunds   = $transactions->where('type', 'refund')->sum('amount_minor');
        $mdr        = (int) round($purchases * $mdrBasisPoints / 10000);

        return $purchases - $refunds - $mdr;
    }
}
```

MDR (Merchant Discount Rate) is typically expressed in basis points (e.g. 150 bps = 1.5%). Always calculate MDR on gross purchases, not net.

---

## Validating the Settlement File Against Internal Records

```php
final class SettlementRecon
{
    public function reconcile(array $acquirerRecords, Collection $internalTransactions): ReconReport
    {
        $report   = new ReconReport();
        $internal = $internalTransactions->keyBy('rrn'); // Index by RRN for O(1) lookup

        foreach ($acquirerRecords as $record) {
            $txn = $internal->get($record['rrn']);

            if ($txn === null) {
                $report->addMissing($record); // In acquirer file but not in our DB
                continue;
            }

            if ($txn->amount_minor !== (int) $record['amount']) {
                $report->addMismatch($txn, $record); // Amount differs
                continue;
            }

            $report->addMatched($txn);
        }

        // Transactions in our DB but absent from acquirer file
        $settledRrns = collect($acquirerRecords)->pluck('rrn');
        $internalTransactions
            ->whereNotIn('rrn', $settledRrns)
            ->each(fn ($txn) => $report->addUnreported($txn));

        return $report;
    }
}
```

---

## Handling Missing or Mismatched Records

| Scenario | Action |
|----------|--------|
| Transaction in our DB, absent from acquirer file | Flag as `unreported`; re-present in next batch or raise with acquirer |
| Transaction in acquirer file, absent from our DB | Flag as `ghost`; investigate before acknowledging — may be a replay or data loss event |
| Amount mismatch | Flag as `mismatch`; do not auto-correct; raise dispute with acquirer |
| Duplicate RRN in acquirer file | Flag both; escalate to acquirer — RRN must be unique per settlement cycle |
| Missing batch response (0530 not received) | Assume batch failed; do not mark transactions as settled; retry next window after confirmation |

---

## Best Practices

- **Use `lockForUpdate` when selecting transactions for settlement** — prevents double-settlement if the job fires twice due to scheduler overlap
- **Always store `rrn` (F37) from the 0110 response** — it is the primary join key between your DB and every acquirer report
- **Store amounts in minor units (integers)** — floating-point arithmetic on currency produces settlement mismatches; never store amounts as `float` or `decimal` in application memory
- **Cutoff is wall-clock MYT, not UTC** — record the timezone explicitly in the job schedule and in every log line; DST is not observed in Malaysia but your servers may be in UTC
- **Treat batch rejection as a hard failure** — if the acquirer rejects the 0520 batch, roll back the `settled` flag on all transactions in the batch and alert immediately; do not silently swallow the error
- **Recon before payout** — never trigger merchant payout until the recon report shows a clean match; a ghost record or amount mismatch must be resolved first
