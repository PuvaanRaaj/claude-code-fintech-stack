---
name: observability
description: Structured logging, Prometheus metrics, and OpenTelemetry tracing for payment systems — with PCI-safe field rules and alerting thresholds for transaction, latency, and error-rate signals.
origin: fintech-stack
---

# Observability

A transaction that fails silently is indistinguishable from a fraud attempt, a host outage, or a misconfigured field. Payment observability has two hard constraints: you must capture enough to reconstruct any transaction from logs alone, and you must never capture cardholder data. This skill covers structured logging, Prometheus metrics, and distributed tracing under both constraints.

## When to Activate

- Adding logging to a payment service, webhook handler, or background job
- Setting up Prometheus metrics or OpenTelemetry tracing for a new service
- Auditing existing logs for PCI violations (PAN, CVV, or card object in log output)
- Defining alerting thresholds for a payment service

---

## Structured Logging

### PCI-Safe Log Context

Always build a safe context before logging. **Never pass the raw request payload.**

```php
<?php declare(strict_types=1);

namespace App\Services\Payment;

final class PaymentLogger
{
    /** Build safe log context — never include PAN, CVV, expiry, or track data */
    public static function context(array $payload, ?string $transactionId = null): array
    {
        return [
            'transaction_id' => $transactionId,
            'merchant_id'    => $payload['merchant_id'] ?? null,
            'amount'         => $payload['amount'] ?? null,      // minor units only
            'currency'       => $payload['currency'] ?? null,
            'pan_last4'      => isset($payload['pan'])
                                    ? substr($payload['pan'], -4)
                                    : ($payload['pan_last4'] ?? null),
            'card_brand'     => $payload['card_brand'] ?? null,
            'order_ref'      => $payload['order_ref'] ?? null,
        ];
    }
}

// Usage
Log::info('payment.authorise.start', PaymentLogger::context($payload, $transaction->id));

Log::info('payment.authorise.approved', [
    ...PaymentLogger::context($payload, $transaction->id),
    'auth_code' => $response['auth_code'],
    'rc'        => '00',
    'host_ms'   => $elapsedMs,
]);

Log::warning('payment.authorise.declined', [
    ...PaymentLogger::context($payload, $transaction->id),
    'rc'  => $response['response_code'],
    'msg' => $response['response_message'] ?? null,
]);

Log::error('payment.authorise.host_error', [
    ...PaymentLogger::context($payload, $transaction->id),
    'error'  => $exception->getMessage(),
    'status' => $httpStatus,
]);
```

### Go — slog with Safe Attributes

```go
func safeAttrs(p Payment, txID string) []slog.Attr {
    pan4 := ""
    if len(p.PAN) >= 4 {
        pan4 = p.PAN[len(p.PAN)-4:]
    }
    return []slog.Attr{
        slog.String("transaction_id", txID),
        slog.String("merchant_id",    p.MerchantID),
        slog.Int64("amount",          p.Amount),
        slog.String("currency",       p.Currency),
        slog.String("pan_last4",      pan4),
        slog.String("card_brand",     p.Brand),
    }
}

func (s *Service) Process(ctx context.Context, p Payment) (*Transaction, error) {
    start := time.Now()
    txID  := generateID()

    s.logger.LogAttrs(ctx, slog.LevelInfo, "payment.authorise.start", safeAttrs(p, txID)...)

    resp, err := s.host.Authorise(ctx, p)
    elapsed := time.Since(start).Milliseconds()

    if err != nil {
        s.logger.LogAttrs(ctx, slog.LevelError, "payment.authorise.error",
            append(safeAttrs(p, txID),
                slog.String("error",  err.Error()),
                slog.Int64("host_ms", elapsed),
            )...,
        )
        return nil, err
    }

    level := slog.LevelInfo
    if resp.ResponseCode != "00" {
        level = slog.LevelWarn
    }
    s.logger.LogAttrs(ctx, level, "payment.authorise.result",
        append(safeAttrs(p, txID),
            slog.String("rc",        resp.ResponseCode),
            slog.String("auth_code", resp.AuthCode),
            slog.Int64("host_ms",    elapsed),
        )...,
    )
    return s.repo.Create(ctx, p, resp)
}
```

---

## Prometheus Metrics

### Metric Definitions

```
# Counters
payment_transactions_total{status, currency}         — every transaction attempt
payment_host_errors_total{type}                      — timeout | connection | server_error
payment_reversals_total{reason}                      — timeout | duplicate

# Histograms
payment_host_duration_seconds{outcome}               — approved | declined | error
# Buckets: 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0

# Gauges (from Horizon / queue)
payment_queue_depth{queue}                           — webhooks | reversals | default
payment_queue_failed_total{queue}
```

### PHP — Prometheus Client

```php
final class PaymentMetrics
{
    private Counter   $transactionsTotal;
    private Histogram $hostDuration;
    private Counter   $hostErrors;

    public function __construct(CollectorRegistry $registry)
    {
        $this->transactionsTotal = $registry->getOrRegisterCounter(
            'payment', 'transactions_total', 'Total transactions', ['status', 'currency']
        );
        $this->hostDuration = $registry->getOrRegisterHistogram(
            'payment', 'host_duration_seconds', 'Host latency',
            ['outcome'], [0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
        );
        $this->hostErrors = $registry->getOrRegisterCounter(
            'payment', 'host_errors_total', 'Host errors by type', ['type']
        );
    }

    public function recordTransaction(string $status, string $currency): void
    {
        $this->transactionsTotal->inc(['status' => $status, 'currency' => $currency]);
    }

    public function recordHostLatency(float $seconds, string $outcome): void
    {
        $this->hostDuration->observe($seconds, ['outcome' => $outcome]);
    }
}
```

### Go — promauto

```go
var (
    TransactionsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
        Name: "payment_transactions_total",
        Help: "Total payment transactions",
    }, []string{"status", "currency"})

    HostDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
        Name:    "payment_host_duration_seconds",
        Help:    "Payment host round-trip latency",
        Buckets: []float64{0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0},
    }, []string{"outcome"})

    HostErrors = promauto.NewCounterVec(prometheus.CounterOpts{
        Name: "payment_host_errors_total",
        Help: "Payment host errors",
    }, []string{"type"})
)
```

---

## Distributed Tracing (OpenTelemetry)

### PHP Spans

```php
$tracer = Globals::tracerProvider()->getTracer('payment-service');
$span   = $tracer->spanBuilder('payment.authorise')->startSpan();

$span->setAttribute('merchant_id', $dto->merchantId);
$span->setAttribute('amount',      $dto->amount);
$span->setAttribute('currency',    $dto->currency);
$span->setAttribute('pan_last4',   substr($dto->pan, -4)); // last 4 only

try {
    $result = $this->client->authorise($dto->toArray(), $dto->idempotencyKey);
    $span->setAttribute('rc', $result['response_code']);
    return $result;
} catch (\Throwable $e) {
    $span->recordException($e);
    $span->setStatus(StatusCode::STATUS_ERROR, $e->getMessage());
    throw $e;
} finally {
    $span->end();
}
```

### Go Spans

```go
ctx, span := otel.Tracer("payment-service").Start(ctx, "payment.authorise")
defer span.End()

span.SetAttributes(
    attribute.String("merchant_id", p.MerchantID),
    attribute.Int64("amount",       p.Amount),
    attribute.String("currency",    p.Currency),
    attribute.String("pan_last4",   p.PAN[len(p.PAN)-4:]),
)

resp, err := s.host.Authorise(ctx, p)
if err != nil {
    span.RecordError(err)
    span.SetStatus(codes.Error, err.Error())
    return nil, err
}
span.SetAttributes(attribute.String("rc", resp.ResponseCode))
```

---

## Alerting Thresholds

| Signal | Warning | Critical | Action |
|--------|---------|----------|--------|
| Decline rate | > 10% | > 25% | Check host connectivity and BIN data |
| Host latency p99 | > 3s | > 8s | Check host status, network path |
| Host error rate | > 1% | > 5% | Page on-call |
| Queue depth (webhooks) | > 500 | > 2 000 | Scale workers |
| Failed jobs | > 10/min | > 50/min | Page on-call |
| Reversal failure rate | > 2% | > 10% | Manual review of pending transactions |

---

## Best Practices

- **Never log the raw payment payload** — it may contain PAN, CVV, or card objects; always use a safe context builder
- **Log at the right level** — `INFO` for normal flow, `WARNING` for soft declines, `ERROR` for host failures, `CRITICAL` for PCI events
- **Include `transaction_id` in every log line** — without it, you cannot reconstruct a disputed transaction
- **Use histograms for latency, not gauges** — histograms give you p50/p95/p99; gauges only show the last value
- **PAN last 4 is the maximum in any log** — not masked PAN (e.g., `****1234`), not full PAN, not expiry
- **Trace spans should cover inbound request → host call → DB write** — gaps in the trace are blind spots for incident response
