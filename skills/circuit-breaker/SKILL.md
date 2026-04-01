---
name: circuit-breaker
description: Circuit breaker patterns for payment host connections — closed/open/half-open state machine, failure threshold configuration, Go implementation with atomic state, PHP/Laravel circuit breaker service, and fallback responses for open circuits.
origin: fintech-stack
---

# Circuit Breaker Patterns

A circuit breaker prevents a cascade failure when a downstream payment host (acquirer, issuer, 3DS server) becomes slow or unreachable. Without one, a hung host causes your application threads to pile up waiting for a timeout, exhausting connection pools and bringing down the entire payment service. The circuit breaker fails fast — returning a known error immediately — giving the downstream system time to recover.

## When to Activate

- Implementing or reviewing a connection to an acquiring host, ISO 8583 switch, or 3DS server
- Diagnosing cascading timeouts or thread-pool exhaustion on a downstream failure
- Building fallback behaviour (queue for retry, return pending status) when the circuit is open
- Configuring failure thresholds and recovery probe intervals for a specific host SLA
- Exposing circuit state to Prometheus or a health-check endpoint

---

## Three-State Machine

```
         failures < threshold                   probe succeeds
  ┌──────────────────────────────┐    ┌──────────────────────────────┐
  │                              ▼    │                              ▼
CLOSED ──── failures ≥ threshold ──▶ OPEN ──── after cooldown ──▶ HALF-OPEN
  ▲                                                                   │
  └──────────────── probe fails ◀─────────────────────────────────────┘
                    (re-open)
```

| State | Behaviour |
|-------|-----------|
| Closed | All requests pass through. Failure counter increments on error. |
| Open | All requests fail immediately (no network call). Fallback is returned. |
| Half-Open | One probe request is allowed through. Success → Closed. Failure → Open (reset timer). |

---

## Go — Atomic Circuit Breaker

```go
package circuitbreaker

import (
    "context"
    "errors"
    "sync"
    "sync/atomic"
    "time"
)

const (
    StateClosed   int32 = 0
    StateOpen     int32 = 1
    StateHalfOpen int32 = 2
)

var ErrCircuitOpen = errors.New("circuit breaker open")

type CircuitBreaker struct {
    state            atomic.Int32
    failures         atomic.Int32
    lastFailure      atomic.Int64  // Unix nano
    threshold        int32
    cooldown         time.Duration
    halfOpenMu       sync.Mutex    // Only one probe at a time in half-open
}

func New(threshold int32, cooldown time.Duration) *CircuitBreaker {
    return &CircuitBreaker{
        threshold: threshold,
        cooldown:  cooldown,
    }
}

// Call executes fn if the circuit is closed or half-open.
// Returns ErrCircuitOpen immediately when the circuit is open.
func (cb *CircuitBreaker) Call(ctx context.Context, fn func(context.Context) error) error {
    switch cb.state.Load() {
    case StateOpen:
        if time.Since(time.Unix(0, cb.lastFailure.Load())) >= cb.cooldown {
            // Cooldown elapsed — attempt to move to half-open
            if cb.state.CompareAndSwap(StateOpen, StateHalfOpen) {
                return cb.probeCall(ctx, fn)
            }
        }
        return ErrCircuitOpen

    case StateHalfOpen:
        return cb.probeCall(ctx, fn)

    default: // StateClosed
        return cb.closedCall(ctx, fn)
    }
}

func (cb *CircuitBreaker) closedCall(ctx context.Context, fn func(context.Context) error) error {
    err := fn(ctx)
    if err != nil {
        failures := cb.failures.Add(1)
        cb.lastFailure.Store(time.Now().UnixNano())
        if failures >= cb.threshold {
            cb.state.Store(StateOpen)
            cb.failures.Store(0)
        }
        return err
    }
    cb.failures.Store(0) // Success — reset counter
    return nil
}

func (cb *CircuitBreaker) probeCall(ctx context.Context, fn func(context.Context) error) error {
    cb.halfOpenMu.Lock()
    defer cb.halfOpenMu.Unlock()

    // Re-check state after acquiring lock — another goroutine may have already probed
    if cb.state.Load() != StateHalfOpen {
        return ErrCircuitOpen
    }

    err := fn(ctx)
    if err != nil {
        // Probe failed — re-open
        cb.lastFailure.Store(time.Now().UnixNano())
        cb.state.Store(StateOpen)
        return err
    }

    // Probe succeeded — close circuit
    cb.state.Store(StateClosed)
    return nil
}

func (cb *CircuitBreaker) State() string {
    switch cb.state.Load() {
    case StateOpen:
        return "open"
    case StateHalfOpen:
        return "half_open"
    default:
        return "closed"
    }
}
```

Usage in an ISO 8583 host client:

```go
cb := circuitbreaker.New(5, 60*time.Second) // Open after 5 failures; probe after 60s

func (c *HostClient) Authorise(ctx context.Context, req *AuthRequest) (*AuthResponse, error) {
    var resp *AuthResponse
    err := cb.Call(ctx, func(ctx context.Context) error {
        var e error
        resp, e = c.sendISO8583(ctx, req)
        return e
    })
    if errors.Is(err, circuitbreaker.ErrCircuitOpen) {
        return &AuthResponse{Status: "pending", RetryAfter: 60}, nil // Fallback
    }
    return resp, err
}
```

---

## PHP/Laravel — Redis-Backed Circuit Breaker

```php
<?php

namespace App\Services\CircuitBreaker;

use Illuminate\Support\Facades\Redis;

final class CircuitBreakerService
{
    private const STATE_CLOSED    = 'closed';
    private const STATE_OPEN      = 'open';
    private const STATE_HALF_OPEN = 'half_open';

    public function __construct(
        private readonly int $threshold   = 5,    // Failures before opening
        private readonly int $windowSecs  = 60,   // Failure window in seconds
        private readonly int $cooldownSecs = 60,  // Seconds before half-open probe
    ) {}

    public function call(string $key, callable $fn): mixed
    {
        $state = $this->getState($key);

        return match ($state) {
            self::STATE_OPEN      => $this->handleOpen($key),
            self::STATE_HALF_OPEN => $this->handleHalfOpen($key, $fn),
            default               => $this->handleClosed($key, $fn),
        };
    }

    private function getState(string $key): string
    {
        $state = Redis::get("cb:{$key}:state") ?? self::STATE_CLOSED;

        if ($state === self::STATE_OPEN) {
            $lastFailure = (int) Redis::get("cb:{$key}:last_failure");
            if (time() - $lastFailure >= $this->cooldownSecs) {
                Redis::set("cb:{$key}:state", self::STATE_HALF_OPEN);
                return self::STATE_HALF_OPEN;
            }
        }

        return $state;
    }

    private function handleClosed(string $key, callable $fn): mixed
    {
        try {
            $result = $fn();
            $this->recordSuccess($key);
            return $result;
        } catch (\Throwable $e) {
            $this->recordFailure($key);
            throw $e;
        }
    }

    private function handleHalfOpen(string $key, callable $fn): mixed
    {
        try {
            $result = $fn();
            $this->close($key);
            return $result;
        } catch (\Throwable $e) {
            $this->open($key);
            throw $e;
        }
    }

    private function handleOpen(string $key): never
    {
        throw new CircuitOpenException("Circuit breaker open for: {$key}");
    }

    private function recordFailure(string $key): void
    {
        $failures = Redis::incr("cb:{$key}:failures");
        Redis::expire("cb:{$key}:failures", $this->windowSecs);
        Redis::set("cb:{$key}:last_failure", time());

        if ($failures >= $this->threshold) {
            $this->open($key);
        }
    }

    private function recordSuccess(string $key): void
    {
        Redis::del("cb:{$key}:failures");
    }

    private function open(string $key): void
    {
        Redis::set("cb:{$key}:state", self::STATE_OPEN);
        Redis::set("cb:{$key}:last_failure", time());
    }

    private function close(string $key): void
    {
        Redis::set("cb:{$key}:state", self::STATE_CLOSED);
        Redis::del("cb:{$key}:failures");
    }
}
```

---

## Fallback Response for Open Circuits

When the circuit is open, returning a `pending` status (rather than an error) preserves the transaction for retry without alarming the cardholder:

```php
// In a payment service
try {
    $response = $this->circuitBreaker->call('acquirer-host', fn() => $this->hostClient->authorise($request));
} catch (CircuitOpenException) {
    // Queue the transaction for retry when the circuit closes
    RetryAuthorisationJob::dispatch($request)->delay(now()->addSeconds(60));

    return AuthorisationResponse::pending(
        retryAfter: 60,
        message:    'Host temporarily unavailable — transaction queued for retry',
    );
}
```

Never return a hard decline (`RC 91 — issuer unavailable`) automatically on circuit open — the transaction may succeed on retry. Return pending and let the cardholder know.

---

## Prometheus Metrics

```go
var (
    circuitStateGauge = promauto.NewGaugeVec(prometheus.GaugeOpts{
        Name: "payment_circuit_breaker_state",
        Help: "Circuit breaker state: 0=closed, 1=open, 2=half_open",
    }, []string{"host"})

    circuitOpenTotal = promauto.NewCounterVec(prometheus.CounterOpts{
        Name: "payment_circuit_breaker_open_total",
        Help: "Total number of times the circuit breaker opened",
    }, []string{"host"})
)

func (cb *CircuitBreaker) recordStateChange(host string, newState int32) {
    circuitStateGauge.WithLabelValues(host).Set(float64(newState))
    if newState == StateOpen {
        circuitOpenTotal.WithLabelValues(host).Inc()
    }
}
```

---

## Best Practices

- **Set the threshold based on host SLA, not guesswork** — if the acquiring host SLA is 99.5% uptime, 5 failures in 60 seconds is a reasonable threshold; for a host with a 2s timeout, 5 failures in 10 seconds is already a problem
- **Keep the cooldown longer than the host's recovery time** — if the acquirer typically recovers in 30 seconds, set cooldown to 60 seconds; opening too early wastes the probe and restarts the timer
- **Use per-host keys** — one circuit breaker per downstream dependency (acquirer-host, 3ds-server, fraud-engine); a failure in 3DS should not open the circuit to the acquirer
- **Emit state change events to Prometheus** — `circuit_breaker_open_total` and `circuit_breaker_state` are the two metrics that trigger on-call alerts; without them, the first signal of a problem is a support call
- **Never swallow `ErrCircuitOpen` silently** — log it at WARN level with the host name; an open circuit is an operational event, not a normal error path
- **Test the half-open probe** — write an integration test that simulates 5 failures, confirms the circuit opens, waits for cooldown, then sends a success probe and confirms the circuit closes
