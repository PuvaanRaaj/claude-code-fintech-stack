---
name: performance-patterns
description: Performance optimization for payment systems — PHP eager loading, Redis caching, Go pprof profiling, bounded goroutine pools, composite database indexes, and Redis pipeline patterns for high-throughput transaction workloads.
origin: fintech-stack
---

# Performance Patterns

Payment systems have two performance failure modes: slow enough that users abandon checkout, and slow enough that the host connection times out and you don't know if the transaction succeeded. Both are costly. This skill covers the specific optimizations that matter for high-throughput payment workloads.

## When to Activate

- Investigating slow payment queries or API response times
- Designing a caching strategy or index plan for transaction tables
- Developer asks "how do I speed this up?" or "why is this query slow?"
- Code review finds N+1 queries, missing indexes, or blocking operations in the critical path

---

## PHP / Laravel

### Eliminate N+1 with Eager Loading

```php
// Bad — one extra query per transaction
$transactions = Transaction::all();
foreach ($transactions as $txn) {
    echo $txn->merchant->name; // N+1
}

// Good — one query for all related models
$transactions = Transaction::with(['merchant', 'events'])
    ->where('merchant_id', $merchantId)
    ->paginate(25);
```

### Redis Caching for Config and Lookup Data

```php
// Cache merchant config for 5 minutes — avoid a DB hit on every request
$config = Cache::remember("merchant:{$merchantId}:config", 300, function () use ($merchantId) {
    return Merchant::with('paymentConfig')->findOrFail($merchantId);
});
```

### Dispatch Non-Critical Work to Queues

```php
// Don't block the HTTP response waiting for webhook delivery
$transaction = $paymentService->process($dto);
dispatch(new SendWebhookJob($transaction))->onQueue('webhooks');
return new PaymentResource($transaction);
```

### DB Connection Pooling

Use PgBouncer or ProxySQL in front of MySQL/Postgres. In PHP this maps to `ATTR_PERSISTENT`:
```php
// config/database.php
'options' => [
    PDO::ATTR_PERSISTENT => true,
],
```

---

## Go

### pprof Profiling

```go
import _ "net/http/pprof"

go func() {
    log.Println(http.ListenAndServe(":6060", nil))
}()

// Profile in production (30 seconds):
// go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30
```

### Bounded Goroutine Pool

```go
func processInParallel(items []PaymentRequest, concurrency int) []Result {
    sem := make(chan struct{}, concurrency)
    results := make([]Result, len(items))
    var wg sync.WaitGroup

    for i, item := range items {
        wg.Add(1)
        go func(idx int, req PaymentRequest) {
            defer wg.Done()
            sem <- struct{}{}          // acquire slot
            defer func() { <-sem }()  // release slot
            results[idx] = process(req)
        }(i, item)
    }
    wg.Wait()
    return results
}
```

### HTTP Client with Connection Pooling (for Payment Host Calls)

```go
var hostClient = &http.Client{
    Transport: &http.Transport{
        MaxIdleConns:        10,
        MaxIdleConnsPerHost: 10,
        IdleConnTimeout:     90 * time.Second,
        TLSHandshakeTimeout: 5 * time.Second,
    },
    Timeout: 30 * time.Second,
}
```

Never use the default `http.Get` or `http.Post` for payment host calls — they do not pool connections.

---

## Database Indexes

### Composite Index for Transaction Queries

Most queries filter by `merchant_id` first, then by date:

```sql
SELECT * FROM transactions
WHERE merchant_id = 'MERCH001'
  AND created_at BETWEEN '2024-01-01' AND '2024-01-31'
ORDER BY created_at DESC;
```

```php
// Laravel migration
Schema::table('transactions', function (Blueprint $table): void {
    $table->index(['merchant_id', 'created_at'], 'idx_transactions_merchant_date');
});
```

### Partial Index for Pending Transactions

```sql
-- Only index pending rows — much smaller index, much faster scan
CREATE INDEX idx_transactions_pending
ON transactions (created_at)
WHERE status = 'pending';
```

### Verify Index Is Being Used

```sql
EXPLAIN SELECT * FROM transactions
WHERE merchant_id = 'MERCH001' AND created_at > '2024-01-01';
-- Look for: Using index, not Using filesort
```

---

## Redis: Pipeline and TTL Strategy

### Pipeline for Batch Writes

```php
// Bad — N round trips to Redis
foreach ($transactionIds as $id) {
    Cache::set("txn:{$id}:processed", true, 3600);
}

// Good — one round trip
Redis::pipeline(function ($pipe) use ($transactionIds) {
    foreach ($transactionIds as $id) {
        $pipe->set("txn:{$id}:processed", 1, 'EX', 3600);
    }
});
```

### TTL Strategy for Payment Data

| Key pattern | TTL | Reason |
|-------------|-----|--------|
| `idempotency:{key}` | 86400 (24h) | RFC-recommended idempotency window |
| `merchant:{id}:config` | 300 (5m) | Config changes rarely |
| `session:{token}` | 1800 (30m) | Payment session timeout |
| `rate_limit:{ip}` | 60 (1m) | Sliding window |
| `txn:{id}:status` | 30 (30s) | Short-lived polling cache |

---

## Async Boundaries

| Operation | Approach | Reason |
|-----------|----------|--------|
| Payment authorisation | Synchronous | User waits for result |
| Webhook delivery | Async (queue) | Non-blocking, retryable |
| Settlement import | Async (scheduled job) | Long-running, offline |
| Reporting / analytics | Read replica | Never hit primary DB |

---

## Best Practices

- **Eager load all relations before loops** — N+1 queries on the `transactions` table at 1,000 rows/page kill response time
- **Use composite indexes, not single-column** — `merchant_id + created_at` outperforms two separate indexes for the common transaction query
- **Profile before optimising** — use `EXPLAIN` in SQL and `pprof` in Go; never guess where the bottleneck is
- **Pool HTTP connections to payment hosts** — TLS handshakes are expensive; reuse connections across requests
- **Partial indexes for status columns** — `WHERE status = 'pending'` on a 10M row table needs a partial index, not a full scan
