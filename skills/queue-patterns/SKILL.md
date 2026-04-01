---
name: queue-patterns
description: Async payment job patterns — Laravel Horizon queue configuration, idempotent jobs, priority queues, dispatch-after-commit, Go worker pools, and dead-letter handling for payment workloads.
origin: fintech-stack
---

# Queue Patterns

Payment jobs have different failure modes than typical background work. A webhook delivery job that runs twice is annoying; a reversal job that runs twice creates a double reversal. A job dispatched inside a database transaction that rolls back still fires. This skill covers the patterns that prevent these failure modes in both PHP/Laravel and Go.

## When to Activate

- Designing async workflows for webhook delivery, payment reversal, or settlement import
- Debugging stuck queues, failed jobs, or duplicate processing
- Configuring Laravel Horizon for a payment workload
- Implementing a Go worker pool with graceful shutdown
- Reviewing job dispatch code for the dispatch-inside-transaction footgun

---

## When to Queue vs When to Be Synchronous

| Operation | Approach | Reason |
|-----------|----------|--------|
| Payment authorisation | Synchronous | User waits for approved/declined response |
| 3DS challenge flow | Synchronous | Browser redirect requires immediate response |
| Webhook delivery to merchant | Queue | Don't block API response; retry on failure |
| Payment reversal (post-timeout) | Queue | Must not block the original API response |
| Settlement file import | Queue | Long-running; run offline |
| Email / SMS notification | Queue | Non-critical path |
| Reconciliation engine | Queue (scheduled) | Runs nightly, takes minutes |

---

## Laravel Horizon Configuration

```php
// config/horizon.php
return [
    'environments' => [
        'production' => [
            'supervisor-payments' => [
                'connection'   => 'redis',
                'queue'        => ['critical', 'payments', 'webhooks', 'default'],
                'balance'      => 'auto',
                'minProcesses' => 3,
                'maxProcesses' => 20,
                'tries'        => 3,
                'timeout'      => 60,
                'memory'       => 256,
            ],
            'supervisor-reconciliation' => [
                'connection'  => 'redis',
                'queue'       => ['reconciliation'],
                'balance'     => 'simple',
                'processes'   => 2,
                'timeout'     => 600,  // 10 minutes for settlement file processing
                'memory'      => 512,
            ],
        ],
    ],
];
```

**Queue priority order:** `critical` (reversals) → `payments` (webhooks) → `default` (notifications) → `reconciliation` (batch).

---

## Idempotent Payment Reversal Job

```php
<?php declare(strict_types=1);

namespace App\Jobs;

use App\Models\Transaction;
use App\Services\Payment\ReversalService;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Queue\Middleware\WithoutOverlapping;
use Illuminate\Support\Facades\Log;

final class SendPaymentReversal implements ShouldQueue
{
    use Queueable;

    public string $queue   = 'critical';
    public int    $tries   = 5;
    public int    $timeout = 30;
    public bool   $deleteWhenMissingModels = true;

    public function __construct(
        private readonly int $transactionId,
    ) {}

    /** Prevent concurrent reversal of the same transaction */
    public function middleware(): array
    {
        return [new WithoutOverlapping("reversal:{$this->transactionId}")->releaseAfter(60)];
    }

    public function backoff(): array
    {
        return [30, 120, 600, 1800, 3600]; // 30s, 2m, 10m, 30m, 1h
    }

    public function handle(ReversalService $service): void
    {
        $transaction = Transaction::findOrFail($this->transactionId);

        if ($transaction->status !== 'pending') {
            Log::info('reversal.skip', [
                'transaction_id' => $this->transactionId,
                'status'         => $transaction->status,
            ]);
            return; // Already resolved — idempotent early exit
        }

        $service->reverse($transaction);
        Log::info('reversal.complete', ['transaction_id' => $this->transactionId]);
    }

    public function failed(\Throwable $e): void
    {
        Log::critical('reversal.exhausted', [
            'transaction_id' => $this->transactionId,
            'error'          => $e->getMessage(),
        ]);
        // Page on-call — transaction stuck in pending state
    }
}
```

---

## Dispatch After Commit

Never dispatch a job inside a database transaction. If the transaction rolls back, the job has already been enqueued.

```php
// WRONG — job fires even if DB transaction rolls back
DB::transaction(function () use ($transaction) {
    $transaction->update(['status' => 'pending']);
    SendPaymentReversal::dispatch($transaction->id); // Already in Redis!
});

// CORRECT — job only fires after successful commit
DB::transaction(function () use ($transaction) {
    $transaction->update(['status' => 'pending']);
});
SendPaymentReversal::dispatch($transaction->id)->afterCommit();

// Or set globally in config/queue.php:
// 'after_commit' => true
```

---

## Unique Jobs (Prevent Duplicate Imports)

```php
use Illuminate\Contracts\Queue\ShouldBeUnique;

final class ImportSettlementFile implements ShouldQueue, ShouldBeUnique
{
    public function __construct(private readonly string $settlementDate) {}

    // Only one import per settlement date can be queued at a time
    public function uniqueId(): string
    {
        return $this->settlementDate;
    }

    public int $uniqueFor = 3600; // Hold the lock for up to 1 hour
}
```

---

## Go — Bounded Worker Pool

```go
package worker

import (
    "context"
    "log/slog"
    "sync"
)

type Job interface {
    Execute(ctx context.Context) error
    ID() string
}

type Pool struct {
    concurrency int
    jobs        chan Job
    wg          sync.WaitGroup
    logger      *slog.Logger
}

func NewPool(concurrency, bufferSize int, logger *slog.Logger) *Pool {
    return &Pool{
        concurrency: concurrency,
        jobs:        make(chan Job, bufferSize),
        logger:      logger,
    }
}

func (p *Pool) Start(ctx context.Context) {
    for i := 0; i < p.concurrency; i++ {
        p.wg.Add(1)
        go p.worker(ctx, i)
    }
}

func (p *Pool) Submit(job Job) { p.jobs <- job }

func (p *Pool) Stop() {
    close(p.jobs) // Signal workers — no more jobs
    p.wg.Wait()   // Wait for in-flight jobs to complete
}

func (p *Pool) worker(ctx context.Context, id int) {
    defer p.wg.Done()
    for {
        select {
        case job, ok := <-p.jobs:
            if !ok {
                return
            }
            if err := job.Execute(ctx); err != nil {
                p.logger.Error("job.failed", "worker", id, "job_id", job.ID(), "error", err)
            }
        case <-ctx.Done():
            return
        }
    }
}
```

### Graceful Shutdown

```go
func main() {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()

    pool := worker.NewPool(10, 100, logger)
    pool.Start(ctx)

    sigCh := make(chan os.Signal, 1)
    signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)

    <-sigCh
    logger.Info("shutdown — draining workers")
    cancel()     // Stop accepting new jobs
    pool.Stop()  // Wait for in-flight jobs to finish
}
```

---

## Best Practices

- **Payment authorisation is always synchronous** — the user must receive an approved/declined response; queue nothing in this path
- **Use `afterCommit()` for jobs dispatched inside DB transactions** — the footgun is real; default to `after_commit => true` in config
- **`WithoutOverlapping` on reversals** — running two reversals for the same transaction produces a double reversal
- **Idempotency inside every job** — check current state before acting; the same job may run twice after a worker restart
- **Dead-letter queue is mandatory** — failed jobs must be inspectable and re-runnable, not silently dropped
- **Separate queues by priority** — `critical` (reversals) must not be starved by `reconciliation` (batch) jobs
- **Alert on queue depth > 500 and failed jobs > 10/min** — sudden depth spike means workers are down or the job is crash-looping
