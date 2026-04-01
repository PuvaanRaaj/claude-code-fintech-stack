---
name: error-handling
description: Payment error classification, retry strategies with idempotency, circuit breakers, and ambiguous-outcome (504/timeout) handling for PHP/Laravel and Go payment services.
origin: fintech-stack
---

# Error Handling

Not all payment errors are equal. A hard decline (RC 05) must never be retried. A host timeout leaves the outcome unknown and requires a reversal before any retry. Getting this wrong means double charges, ghost transactions, or failed refunds. This skill encodes the classification and handling patterns for each error category.

## When to Activate

- Implementing a payment host client, reversal flow, or queue worker
- Reviewing code where errors are swallowed, unconditionally retried, or panicked on
- Handling 504 / connection timeout responses from an acquiring host
- Adding a circuit breaker to protect an upstream host

---

## Error Classification

| Category | Examples | Retry? |
|----------|----------|--------|
| **Transient** | Network timeout, 503, connection refused | Yes — with backoff |
| **Ambiguous** | 504 gateway timeout (outcome unknown) | Send reversal first, then retry with same idempotency key |
| **Hard decline** | RC 05 (do not honour), RC 14 (invalid card) | No |
| **Soft decline** | RC 51 (insufficient funds), RC 61 (amount limit) | No — return to user |
| **Auth failure** | RC 41 (lost card), RC 43 (stolen card) | No |
| **System error** | RC 96 (system malfunction), RC 91 (issuer unavailable) | Yes — limited |
| **Config error** | RC 30 (format error), RC 12 (invalid transaction) | No — fix the request |

---

## Exception Hierarchy (PHP)

```php
<?php declare(strict_types=1);

namespace App\Exceptions\Payment;

abstract class PaymentException extends \RuntimeException {}

// Host is unreachable — safe to retry
final class HostTimeoutException    extends PaymentException {}
final class HostUnavailableException extends PaymentException {}

// Outcome unknown — MUST send reversal before any retry
final class AmbiguousOutcomeException extends PaymentException {}

// Hard decline — do not retry
final class CardDeclinedException extends PaymentException
{
    public function __construct(
        public readonly string $responseCode,
        public readonly string $responseMessage,
    ) {
        parent::__construct("Card declined: {$responseCode} — {$responseMessage}");
    }
}

// Configuration or format error — fix the code
final class InvalidRequestException extends PaymentException {}
```

---

## Host Client with Classification (PHP)

```php
final class PaymentHostClient
{
    private const RETRIABLE_RC     = ['91', '96'];
    private const NON_RETRIABLE_RC = ['05', '14', '41', '43', '51', '61'];

    public function authorise(array $payload, string $idempotencyKey): array
    {
        try {
            $response = Http::timeout(15)
                ->withHeaders(['Idempotency-Key' => $idempotencyKey])
                ->post(config('payment.host_url') . '/authorise', $payload);

            if ($response->status() === 504) {
                // Outcome unknown — leave transaction as pending, queue reversal
                throw new AmbiguousOutcomeException("Host returned 504");
            }

            if (! $response->successful()) {
                throw new HostUnavailableException("Host returned {$response->status()}");
            }

            $rc = $response->json('response_code');

            if (in_array($rc, self::NON_RETRIABLE_RC, true)) {
                throw new CardDeclinedException($rc, $response->json('response_message', ''));
            }

            return $response->json();

        } catch (\Illuminate\Http\Client\ConnectionException $e) {
            throw new HostTimeoutException("Connection timed out", 0, $e);
        }
    }
}
```

---

## Ambiguous Outcome Handling

A 504 / timeout means the host may or may not have processed the transaction. **Do not mark it failed.** Mark as pending, queue a reversal, and let the reversal determine the outcome.

```php
final class PaymentOrchestrator
{
    public function process(PaymentDto $dto): Transaction
    {
        $transaction = Transaction::create([
            'idempotency_key' => $dto->idempotencyKey,
            'status'          => 'pending',
            'amount'          => $dto->amount,
            'currency'        => $dto->currency,
        ]);

        try {
            $response = $this->client->authorise($dto->toArray(), $dto->idempotencyKey);
            $transaction->update([
                'status'    => $response['response_code'] === '00' ? 'approved' : 'declined',
                'auth_code' => $response['auth_code'] ?? null,
                'rc'        => $response['response_code'],
            ]);

        } catch (AmbiguousOutcomeException $e) {
            // Leave as pending; schedule reversal
            Log::error('payment.ambiguous_outcome', [
                'transaction_id' => $transaction->id,
                'error'          => $e->getMessage(),
            ]);
            SendPaymentReversal::dispatch($transaction)->afterCommit()->delay(now()->addSeconds(30));
        }

        return $transaction->fresh();
    }
}
```

---

## Error Types and Retry (Go)

```go
package payment

import (
    "errors"
    "fmt"
)

var (
    ErrHostTimeout      = errors.New("host timeout")
    ErrHostUnavailable  = errors.New("host unavailable")
    ErrAmbiguousOutcome = errors.New("ambiguous outcome — reversal required")
)

type DeclineError struct {
    ResponseCode    string
    ResponseMessage string
}

func (e *DeclineError) Error() string {
    return fmt.Sprintf("card declined: %s — %s", e.ResponseCode, e.ResponseMessage)
}

func IsRetriable(err error) bool {
    return errors.Is(err, ErrHostTimeout) || errors.Is(err, ErrHostUnavailable)
}
```

### Retry with Exponential Backoff (Go)

```go
func WithRetry(ctx context.Context, maxAttempts int, baseDelay time.Duration, fn func() error) error {
    var lastErr error
    for attempt := 0; attempt < maxAttempts; attempt++ {
        err := fn()
        if err == nil {
            return nil
        }
        if !IsRetriable(err) {
            return err // hard decline, config error — stop immediately
        }
        lastErr = err

        delay := baseDelay * (1 << attempt)
        if delay > 10*time.Second {
            delay = 10 * time.Second
        }
        select {
        case <-ctx.Done():
            return ctx.Err()
        case <-time.After(delay):
        }
    }
    return fmt.Errorf("exhausted %d retries: %w", maxAttempts, lastErr)
}
```

---

## Circuit Breaker (Go)

Prevent hammering a host that is down. Open the circuit after repeated failures; allow one probe request after the reset timeout.

```go
type CircuitBreaker struct {
    mu           sync.Mutex
    state        circuitState // closed, open, half-open
    failures     int
    threshold    int
    openedAt     time.Time
    resetTimeout time.Duration
}

func (cb *CircuitBreaker) Allow() bool {
    cb.mu.Lock()
    defer cb.mu.Unlock()
    switch cb.state {
    case stateClosed:
        return true
    case stateOpen:
        if time.Since(cb.openedAt) > cb.resetTimeout {
            cb.state = stateHalfOpen
            return true
        }
        return false
    default: // half-open — allow one probe
        return true
    }
}

func (cb *CircuitBreaker) RecordSuccess() {
    cb.mu.Lock(); defer cb.mu.Unlock()
    cb.failures = 0; cb.state = stateClosed
}

func (cb *CircuitBreaker) RecordFailure() {
    cb.mu.Lock(); defer cb.mu.Unlock()
    cb.failures++
    if cb.state == stateHalfOpen || cb.failures >= cb.threshold {
        cb.state = stateOpen; cb.openedAt = time.Now()
    }
}
```

---

## Best Practices

- **Classify before retrying** — check `IsRetriable()` or inspect the exception type; never retry blindly
- **Idempotency key on every retry** — the same key tells the host to deduplicate, preventing double charges
- **504 = ambiguous, not failed** — leave the transaction pending, queue a reversal, let the reversal resolve it
- **Never swallow errors silently** — always log with `transaction_id`, `merchant_id`, and `rc`
- **Circuit-break after 5 consecutive host failures** — protects the host from being hammered during an outage
- **Alert on dead-letter queue growth** — a growing reversal failure queue means unresolved pending transactions
