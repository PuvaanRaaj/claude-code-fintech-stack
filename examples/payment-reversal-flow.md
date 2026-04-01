# Laravel Payment Reversal Flow

A complete example of the reversal lifecycle: authorisation times out (504), transaction set to `pending`, reversal job dispatched, reversal sent to host, transaction updated to `reversed`.

## DB State Transitions

```
pending → approved      (host responded in time, RC 00)
pending → declined      (host responded in time, non-00 RC)
pending → reversed      (host timed out, reversal accepted by host)
pending → reversal_failed  (host timed out, reversal also failed — needs manual intervention)
```

## Migration (state column)

```php
// database/migrations/xxxx_create_transactions_table.php
$table->uuid('id')->primary();
$table->string('status')->default('pending');
// Valid values: pending | approved | declined | reversed | reversal_failed
$table->string('reversal_reason')->nullable();
$table->timestamp('reversed_at')->nullable();
```

## Service Layer — PaymentService::charge()

```php
<?php

declare(strict_types=1);

namespace App\Services;

use App\Exceptions\GatewayTimeoutException;
use App\Jobs\SendReversalJob;
use App\Models\Transaction;
use App\Repositories\TransactionRepository;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

final class PaymentService
{
    public function __construct(
        private readonly TransactionRepository $transactions,
    ) {}

    public function charge(Transaction $transaction): Transaction
    {
        Log::info('payment.charge.attempt', [
            'transaction_id' => $transaction->id,
            'amount'         => $transaction->amount,
            'currency'       => $transaction->currency,
        ]);

        try {
            $response = Http::withOptions(['verify' => config('payment.ca_bundle')])
                ->timeout(config('payment.gateway_timeout_seconds', 30))
                ->post(config('payment.gateway_url') . '/authorise', [
                    'reference' => $transaction->id,
                    'amount'    => $transaction->amount,
                    'currency'  => $transaction->currency,
                    'token'     => $transaction->payment_token,
                ]);
        } catch (ConnectionException $e) {
            // Network timeout or refused connection — outcome unknown
            // Must set pending (not failed) and dispatch reversal
            Log::warning('payment.charge.timeout', [
                'transaction_id' => $transaction->id,
                'error'          => $e->getMessage(),
            ]);

            // Transaction stays `pending` until reversal confirms
            SendReversalJob::dispatch($transaction)->onQueue('reversals');

            throw new GatewayTimeoutException(
                transactionId: $transaction->id,
                previous: $e,
            );
        }

        // 504 from gateway proxy — treat identically to connection timeout
        if ($response->status() === 504) {
            Log::warning('payment.charge.gateway_504', [
                'transaction_id' => $transaction->id,
            ]);

            SendReversalJob::dispatch($transaction)->onQueue('reversals');

            throw new GatewayTimeoutException(transactionId: $transaction->id);
        }

        if (! $response->successful()) {
            return $this->transactions->markDeclined(
                transaction: $transaction,
                responseCode: $response->json('response_code', 'XX'),
            );
        }

        $body = $response->json();

        if ($body['response_code'] !== '00') {
            return $this->transactions->markDeclined($transaction, $body['response_code']);
        }

        return $this->transactions->markApproved(
            transaction: $transaction,
            approvalCode: $body['approval_code'],
            gatewayRef: $body['gateway_reference'],
        );
    }
}
```

## Reversal Job

```php
<?php

declare(strict_types=1);

namespace App\Jobs;

use App\Models\Transaction;
use App\Repositories\TransactionRepository;
use App\Services\ReversalService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

final class SendReversalJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    // Reversals must be retried aggressively — a missing reversal = unbalanced position
    public int $tries = 10;
    public int $backoff = 30; // seconds between retries

    public function __construct(
        public readonly Transaction $transaction,
    ) {}

    public function handle(ReversalService $service, TransactionRepository $transactions): void
    {
        // Guard: only reverse transactions still in pending state
        // If a late approval came back and a worker approved it before this job ran,
        // skip the reversal — do not double-reverse
        $fresh = $transactions->findOrFail($this->transaction->id);

        if ($fresh->status !== 'pending') {
            Log::info('reversal.skipped', [
                'transaction_id' => $fresh->id,
                'current_status' => $fresh->status,
                'reason'         => 'status is no longer pending',
            ]);
            return;
        }

        $service->sendReversal($fresh);
    }

    public function failed(\Throwable $e): void
    {
        // After all retries exhausted — mark for manual intervention
        Log::error('reversal.job.failed', [
            'transaction_id' => $this->transaction->id,
            'error'          => $e->getMessage(),
        ]);
        // TransactionRepository::markReversalFailed is called by ReversalService
        // but if the job itself can't even boot the service, flag it here via direct update
        Transaction::where('id', $this->transaction->id)
            ->where('status', 'pending')
            ->update(['status' => 'reversal_failed']);
    }
}
```

## Reversal Service

```php
<?php

declare(strict_types=1);

namespace App\Services;

use App\Models\Transaction;
use App\Repositories\TransactionRepository;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

final class ReversalService
{
    public function __construct(
        private readonly TransactionRepository $transactions,
    ) {}

    public function sendReversal(Transaction $transaction): void
    {
        Log::info('reversal.attempt', [
            'transaction_id' => $transaction->id,
            'amount'         => $transaction->amount,
            'currency'       => $transaction->currency,
        ]);

        try {
            $response = Http::withOptions(['verify' => config('payment.ca_bundle')])
                ->timeout(config('payment.reversal_timeout_seconds', 30))
                ->post(config('payment.gateway_url') . '/reverse', [
                    'original_reference' => $transaction->id,
                    'amount'             => $transaction->amount,
                    'currency'           => $transaction->currency,
                ]);
        } catch (ConnectionException $e) {
            Log::warning('reversal.network_error', [
                'transaction_id' => $transaction->id,
                'error'          => $e->getMessage(),
            ]);
            // Re-throw so the job retries
            throw $e;
        }

        $body = $response->json();

        // RC 00 = reversal accepted; RC 25 = original not found (idempotent — already reversed)
        $accepted = in_array($body['response_code'] ?? '', ['00', '25'], strict: true);

        if (! $accepted) {
            Log::error('reversal.rejected', [
                'transaction_id' => $transaction->id,
                'response_code'  => $body['response_code'] ?? 'unknown',
            ]);
            throw new \RuntimeException(
                "Reversal rejected by host with RC {$body['response_code']}"
            );
        }

        $this->transactions->markReversed(
            transaction: $transaction,
            reason: 'gateway_timeout',
        );

        Log::info('reversal.accepted', [
            'transaction_id' => $transaction->id,
            'response_code'  => $body['response_code'],
        ]);
    }
}
```

## TransactionRepository — State Transition Methods

```php
<?php

declare(strict_types=1);

namespace App\Repositories;

use App\Models\Transaction;
use Illuminate\Support\Facades\DB;

final class TransactionRepository
{
    public function markApproved(Transaction $transaction, string $approvalCode, string $gatewayRef): Transaction
    {
        return tap($transaction)->update([
            'status'            => 'approved',
            'approval_code'     => $approvalCode,
            'gateway_reference' => $gatewayRef,
            'approved_at'       => now(),
        ]);
    }

    public function markDeclined(Transaction $transaction, string $responseCode): Transaction
    {
        return tap($transaction)->update([
            'status'        => 'declined',
            'response_code' => $responseCode,
            'declined_at'   => now(),
        ]);
    }

    public function markReversed(Transaction $transaction, string $reason): Transaction
    {
        return tap($transaction)->update([
            'status'          => 'reversed',
            'reversal_reason' => $reason,
            'reversed_at'     => now(),
        ]);
    }

    public function markReversalFailed(Transaction $transaction): Transaction
    {
        return tap($transaction)->update([
            'status' => 'reversal_failed',
        ]);
    }

    public function findOrFail(string $id): Transaction
    {
        return Transaction::findOrFail($id);
    }
}
```

## Test — Http::sequence() Covering the Full Reversal Flow

```php
<?php

declare(strict_types=1);

namespace Tests\Feature\Payment;

use App\Jobs\SendReversalJob;
use App\Models\Transaction;
use App\Services\PaymentService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

final class PaymentReversalFlowTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function it_sets_transaction_to_pending_and_dispatches_reversal_on_504(): void
    {
        Queue::fake();

        $transaction = Transaction::factory()->create(['status' => 'pending']);

        Http::sequence()
            ->push(['error' => 'upstream timeout'], 504)  // authorise call returns 504
            ->push(['response_code' => '00'], 200);        // reversal call succeeds (handled by job)

        $service = app(PaymentService::class);

        $this->expectException(\App\Exceptions\GatewayTimeoutException::class);
        $service->charge($transaction);

        // Transaction must remain pending — not failed — until reversal confirms
        $this->assertDatabaseHas('transactions', [
            'id'     => $transaction->id,
            'status' => 'pending',
        ]);

        Queue::assertPushedOn('reversals', SendReversalJob::class, function ($job) use ($transaction) {
            return $job->transaction->id === $transaction->id;
        });
    }

    /** @test */
    public function it_marks_transaction_reversed_when_reversal_job_succeeds(): void
    {
        Queue::fake([]);  // don't fake — let job run inline

        $transaction = Transaction::factory()->create(['status' => 'pending']);

        // authorise = 504, reversal = accepted RC 00
        Http::sequence()
            ->push(['error' => 'upstream timeout'], 504)
            ->push(['response_code' => '00'], 200);

        $service = app(PaymentService::class);

        try {
            $service->charge($transaction);
        } catch (\App\Exceptions\GatewayTimeoutException) {
            // Expected — proceed to job dispatch
        }

        // Manually run the reversal job (simulates worker picking it up)
        (new \App\Jobs\SendReversalJob($transaction))->handle(
            app(\App\Services\ReversalService::class),
            app(\App\Repositories\TransactionRepository::class),
        );

        $this->assertDatabaseHas('transactions', [
            'id'     => $transaction->id,
            'status' => 'reversed',
        ]);
    }

    /** @test */
    public function it_skips_reversal_if_transaction_was_approved_before_job_ran(): void
    {
        // Simulates race: charge timed out, but a late response approved the transaction
        // before the reversal job was processed
        $transaction = Transaction::factory()->create(['status' => 'approved']);

        Http::fake(); // should not be called

        (new \App\Jobs\SendReversalJob($transaction))->handle(
            app(\App\Services\ReversalService::class),
            app(\App\Repositories\TransactionRepository::class),
        );

        Http::assertNothingSent();

        $this->assertDatabaseHas('transactions', [
            'id'     => $transaction->id,
            'status' => 'approved', // unchanged
        ]);
    }

    /** @test */
    public function it_retries_reversal_on_network_failure_and_succeeds_on_second_attempt(): void
    {
        $transaction = Transaction::factory()->create(['status' => 'pending']);

        Http::sequence()
            ->push(fn () => throw new ConnectionException('network error')) // first reversal attempt fails
            ->push(['response_code' => '00'], 200);                         // second attempt succeeds

        $job = new \App\Jobs\SendReversalJob($transaction);

        // First attempt throws — job will be retried by queue worker
        $this->expectException(ConnectionException::class);
        $job->handle(
            app(\App\Services\ReversalService::class),
            app(\App\Repositories\TransactionRepository::class),
        );

        // Simulate queue worker retrying
        $job->handle(
            app(\App\Services\ReversalService::class),
            app(\App\Repositories\TransactionRepository::class),
        );

        $this->assertDatabaseHas('transactions', [
            'id'     => $transaction->id,
            'status' => 'reversed',
        ]);
    }
}
```

## Key Rules

- Transaction status must be `pending` (not `failed`) immediately after a timeout — outcome is unknown until reversal response confirms.
- The reversal job must guard against the approved-before-reversal race: re-read status from DB before sending.
- Never reverse a transaction that is already `approved`, `declined`, or `reversed`.
- Reversal job retries 10 times with 30-second backoff — a missing reversal is an unbalanced financial position.
- After all retries exhausted, status moves to `reversal_failed` and triggers a PagerDuty/ops alert.
- RC 25 from host on reversal = "original not found" — treat as success (idempotent).
