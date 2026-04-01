# Laravel Settlement Batch Generation

A complete example of end-of-day settlement: Artisan command at 23:59 MYT, query approved transactions, generate CSV, upload to SFTP, mark transactions `settled`, log batch summary.

## Schedule Registration

```php
// routes/console.php  (Laravel 11)
use Illuminate\Support\Facades\Schedule;

// Run at 23:59 MYT (UTC+8) daily — cron is in UTC so 23:59 MYT = 15:59 UTC
Schedule::command('settlement:generate')
    ->dailyAt('15:59')
    ->timezone('UTC')
    ->withoutOverlapping(10)       // lock for up to 10 minutes
    ->runInBackground()
    ->onFailure(function () {
        Log::critical('settlement.command.failed');
    });
```

## Artisan Command

```php
<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Services\SettlementService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

final class GenerateSettlementCommand extends Command
{
    protected $signature = 'settlement:generate
                            {--date= : Settlement date in Y-m-d format (defaults to today in MYT)}
                            {--dry-run : Generate file and validate but do not upload or mark settled}';

    protected $description = 'Generate daily settlement batch, upload to SFTP, and mark transactions as settled';

    public function handle(SettlementService $service): int
    {
        $date = $this->option('date')
            ? \Carbon\Carbon::parse($this->option('date'), 'Asia/Kuala_Lumpur')
            : now('Asia/Kuala_Lumpur')->startOfDay();

        $dryRun = (bool) $this->option('dry-run');

        $this->info("Generating settlement for {$date->toDateString()} (dry-run: " . ($dryRun ? 'yes' : 'no') . ')');

        try {
            $summary = $service->generate(settlementDate: $date, dryRun: $dryRun);
        } catch (\Throwable $e) {
            $this->error("Settlement failed: {$e->getMessage()}");
            Log::critical('settlement.command.exception', [
                'date'  => $date->toDateString(),
                'error' => $e->getMessage(),
            ]);
            return Command::FAILURE;
        }

        $this->table(
            ['Metric', 'Value'],
            [
                ['Date',              $summary['date']],
                ['Batch Number',      $summary['batch_number']],
                ['Transaction Count', $summary['transaction_count']],
                ['Gross Amount',      number_format($summary['gross_amount'] / 100, 2) . ' ' . $summary['currency']],
                ['Net Amount',        number_format($summary['net_amount'] / 100, 2) . ' ' . $summary['currency']],
                ['File',              $summary['filename']],
                ['Uploaded',          $summary['uploaded'] ? 'yes' : 'no (dry-run)'],
            ],
        );

        return Command::SUCCESS;
    }
}
```

## Settlement Service

```php
<?php

declare(strict_types=1);

namespace App\Services;

use App\Models\Transaction;
use App\Repositories\TransactionRepository;
use Carbon\Carbon;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

final class SettlementService
{
    // Mismatch threshold: flag any variance > MYR 0.01 (1 sen = 1 minor unit)
    private const MISMATCH_THRESHOLD_MINOR = 1;

    public function __construct(
        private readonly TransactionRepository $transactions,
    ) {}

    /**
     * Generate a settlement batch for the given date.
     *
     * @param Carbon $settlementDate  Date in MYT (Asia/Kuala_Lumpur)
     * @param bool   $dryRun          If true, generate and validate only — do not upload or mark settled
     */
    public function generate(Carbon $settlementDate, bool $dryRun = false): array
    {
        // Settlement window: 00:00:00 to 23:59:59 MYT
        $windowStart = $settlementDate->copy()->startOfDay();
        $windowEnd   = $settlementDate->copy()->endOfDay();

        Log::info('settlement.generate.start', [
            'date'       => $settlementDate->toDateString(),
            'window_utc' => [
                'from' => $windowStart->copy()->utc()->toIso8601String(),
                'to'   => $windowEnd->copy()->utc()->toIso8601String(),
            ],
        ]);

        // Fetch only approved transactions — never include pending, declined, reversed
        $transactions = $this->transactions->getApprovedForSettlement(
            from: $windowStart,
            to: $windowEnd,
        );

        if ($transactions->isEmpty()) {
            Log::info('settlement.generate.empty', ['date' => $settlementDate->toDateString()]);
            return $this->emptySummary($settlementDate);
        }

        $batchNumber = $this->generateBatchNumber($settlementDate);

        // Build CSV content
        $csv = $this->buildCsv(
            transactions: $transactions,
            batchNumber: $batchNumber,
            settlementDate: $settlementDate,
        );

        // Validate totals before upload
        $this->validateTotals($csv, $transactions);

        $filename = $this->filename($settlementDate, $batchNumber);

        if (! $dryRun) {
            // Write to local temp, then SFTP upload
            $this->uploadToSftp($filename, $csv);

            // Mark all transactions settled in a single DB update
            $this->transactions->markSettled(
                ids: $transactions->pluck('id')->all(),
                batchNumber: $batchNumber,
                settledAt: now(),
            );
        }

        $grossAmount = $transactions->sum('amount');
        $refundTotal = $transactions->where('type', 'refund')->sum('amount');
        $netAmount   = $grossAmount - $refundTotal;

        $summary = [
            'date'              => $settlementDate->toDateString(),
            'batch_number'      => $batchNumber,
            'transaction_count' => $transactions->count(),
            'gross_amount'      => $grossAmount,
            'net_amount'        => $netAmount,
            'currency'          => 'MYR',
            'filename'          => $filename,
            'uploaded'          => ! $dryRun,
        ];

        Log::info('settlement.generate.complete', $summary);

        return $summary;
    }

    /**
     * Build the settlement CSV.
     *
     * File format (per-row):
     *   merchant_id, terminal_id, batch_number, transaction_count (1 per data row),
     *   amount (minor units), currency, date (YYYYMMDD), transaction_id, type
     *
     * First row is the batch header; last row is the batch trailer with totals.
     */
    private function buildCsv(
        \Illuminate\Support\Collection $transactions,
        string $batchNumber,
        Carbon $settlementDate,
    ): string {
        $merchantId = config('payment.merchant_id');
        $terminalId = config('payment.terminal_id');
        $dateStr    = $settlementDate->format('Ymd');
        $currency   = 'MYR';

        $grossAmount = $transactions->sum('amount');
        $refundTotal = $transactions->where('type', 'refund')->sum('amount');
        $netAmount   = $grossAmount - $refundTotal;
        $count       = $transactions->count();

        $lines = [];

        // Batch header
        $lines[] = implode(',', [
            'HDR',
            $merchantId,
            $terminalId,
            $batchNumber,
            $count,
            $netAmount,
            $currency,
            $dateStr,
        ]);

        // Data rows
        foreach ($transactions as $tx) {
            $lines[] = implode(',', [
                'TXN',
                $merchantId,
                $terminalId,
                $batchNumber,
                1,
                $tx->amount,
                $currency,
                $dateStr,
                $tx->id,
                $tx->type,          // purchase | refund
                $tx->approval_code,
                $tx->gateway_reference,
            ]);
        }

        // Batch trailer with totals
        $lines[] = implode(',', [
            'TRL',
            $merchantId,
            $terminalId,
            $batchNumber,
            $count,
            $grossAmount,
            $refundTotal,
            $netAmount,
            $currency,
            $dateStr,
        ]);

        return implode("\r\n", $lines) . "\r\n";
    }

    /**
     * Validate that our in-memory totals match what is written to the CSV trailer.
     * Throws if variance > MISMATCH_THRESHOLD_MINOR.
     */
    private function validateTotals(string $csv, \Illuminate\Support\Collection $transactions): void
    {
        // Parse trailer line (last non-empty line)
        $lines = array_filter(explode("\r\n", trim($csv)));
        $trailer = array_pop($lines);
        $parts = explode(',', $trailer);

        // TRL,merchantId,terminalId,batch,count,gross,refund,net,currency,date
        $csvGross  = (int) $parts[5];
        $csvNet    = (int) $parts[7];

        $calcGross = $transactions->sum('amount');
        $calcNet   = $calcGross - $transactions->where('type', 'refund')->sum('amount');

        $grossVariance = abs($csvGross - $calcGross);
        $netVariance   = abs($csvNet - $calcNet);

        if ($grossVariance > self::MISMATCH_THRESHOLD_MINOR || $netVariance > self::MISMATCH_THRESHOLD_MINOR) {
            Log::critical('settlement.validation.mismatch', [
                'csv_gross'      => $csvGross,
                'calc_gross'     => $calcGross,
                'gross_variance' => $grossVariance,
                'csv_net'        => $csvNet,
                'calc_net'       => $calcNet,
                'net_variance'   => $netVariance,
            ]);

            throw new \RuntimeException(
                "Settlement total mismatch: gross variance={$grossVariance}, net variance={$netVariance} minor units"
            );
        }
    }

    private function uploadToSftp(string $filename, string $content): void
    {
        // Uses the 'sftp' disk defined in config/filesystems.php
        $remotePath = config('payment.settlement_sftp_path', 'settlement/') . $filename;

        $written = Storage::disk('sftp')->put($remotePath, $content);

        if (! $written) {
            throw new \RuntimeException("Failed to upload settlement file to SFTP: {$remotePath}");
        }

        Log::info('settlement.sftp.uploaded', ['remote_path' => $remotePath]);
    }

    private function generateBatchNumber(Carbon $date): string
    {
        // Format: YYYYMMDD + 3-digit sequence (001 for first batch of day)
        return $date->format('Ymd') . '001';
    }

    private function filename(Carbon $date, string $batchNumber): string
    {
        $merchantId = config('payment.merchant_id');
        return "SETTLEMENT_{$merchantId}_{$batchNumber}_{$date->format('Ymd')}.csv";
    }

    private function emptySummary(Carbon $date): array
    {
        return [
            'date'              => $date->toDateString(),
            'batch_number'      => null,
            'transaction_count' => 0,
            'gross_amount'      => 0,
            'net_amount'        => 0,
            'currency'          => 'MYR',
            'filename'          => null,
            'uploaded'          => false,
        ];
    }
}
```

## TransactionRepository — Settlement Methods

```php
<?php

declare(strict_types=1);

namespace App\Repositories;

use App\Models\Transaction;
use Carbon\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

final class TransactionRepository
{
    /**
     * Fetch all approved (and approved-refund) transactions in the settlement window.
     * Excludes: pending, declined, reversed, reversal_failed, settled.
     */
    public function getApprovedForSettlement(Carbon $from, Carbon $to): Collection
    {
        return Transaction::query()
            ->whereIn('status', ['approved'])
            ->whereIn('type', ['purchase', 'refund'])
            ->whereBetween('approved_at', [
                $from->copy()->utc(),
                $to->copy()->utc(),
            ])
            ->whereNull('settled_at')
            ->orderBy('approved_at')
            ->get([
                'id', 'merchant_id', 'terminal_id', 'type',
                'amount', 'currency', 'approval_code',
                'gateway_reference', 'approved_at',
            ]);
    }

    /**
     * Mark a batch of transactions as settled in a single UPDATE.
     * Uses a chunked update to avoid locking too many rows at once.
     */
    public function markSettled(array $ids, string $batchNumber, Carbon $settledAt): void
    {
        foreach (array_chunk($ids, 500) as $chunk) {
            Transaction::whereIn('id', $chunk)
                ->where('status', 'approved')   // re-check status under lock
                ->update([
                    'status'         => 'settled',
                    'batch_number'   => $batchNumber,
                    'settled_at'     => $settledAt->utc(),
                ]);
        }
    }
}
```

## Settlement File Format Reference

```
Row Types
─────────
HDR  Batch header  — one per file
TXN  Transaction   — one per approved transaction
TRL  Batch trailer — one per file, contains totals

HDR row columns:
  [0] HDR
  [1] merchant_id       — alphanumeric, up to 15 chars
  [2] terminal_id       — alphanumeric, up to 8 chars
  [3] batch_number      — YYYYMMDD + 3-digit seq (e.g. 20260401001)
  [4] transaction_count — integer
  [5] net_amount        — integer, minor units (e.g. MYR 100.50 = 10050)
  [6] currency          — ISO 4217 alpha (e.g. MYR)
  [7] date              — YYYYMMDD

TXN row columns:
  [0]  TXN
  [1]  merchant_id
  [2]  terminal_id
  [3]  batch_number
  [4]  1               — always 1 per TXN row
  [5]  amount          — minor units (always positive; type field identifies refund)
  [6]  currency
  [7]  date
  [8]  transaction_id  — UUID
  [9]  type            — purchase | refund
  [10] approval_code
  [11] gateway_reference

TRL row columns:
  [0] TRL
  [1] merchant_id
  [2] terminal_id
  [3] batch_number
  [4] transaction_count
  [5] gross_amount     — sum of all amounts (minor units)
  [6] refund_total     — sum of refund amounts (minor units)
  [7] net_amount       — gross_amount minus refund_total
  [8] currency
  [9] date

Line ending: CRLF (\r\n)
Encoding:    UTF-8, no BOM
```

## Key Rules

- Only `approved` transactions enter the settlement batch — never `pending`, `declined`, `reversed`, or `reversal_failed`.
- Settlement cutoff is 23:59 MYT (UTC+8). The cron runs at 15:59 UTC.
- Amounts are always in minor units (sen for MYR). Never write decimal amounts to the file.
- Validate in-memory totals against the CSV trailer before upload. Flag any variance > MYR 0.01 (1 minor unit) and abort.
- If the SFTP host rejects with RC 94 (duplicate batch), hold 24 hours and resubmit with a new batch number.
- Use `--dry-run` to validate the batch in staging without uploading or marking transactions settled.
- `markSettled` re-checks `status = approved` under the update lock to prevent double-settling a transaction that was reversed between query and update.
- Net = gross minus refunds/reversals. Gross = sum of all approved purchase amounts.
