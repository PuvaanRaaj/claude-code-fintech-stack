# Go Error Handling Rules

## Always Wrap with Context

Every error returned from a function must be wrapped with `fmt.Errorf("context: %w", err)` before propagation. The context string describes the operation that failed.

```go
// Correct — each layer adds context
func (s *PaymentService) Process(ctx context.Context, req ProcessRequest) (*Transaction, error) {
    tx, err := s.repo.Create(ctx, req)
    if err != nil {
        return nil, fmt.Errorf("payment.Process create: %w", err)
    }
    resp, err := s.gateway.Charge(ctx, tx)
    if err != nil {
        return nil, fmt.Errorf("payment.Process gateway charge %s: %w", tx.ID, err)
    }
    return tx, nil
}

// Incorrect — context lost
func (s *PaymentService) Process(ctx context.Context, req ProcessRequest) (*Transaction, error) {
    tx, err := s.repo.Create(ctx, req)
    if err != nil {
        return nil, err  // no context: who failed? which operation?
    }
    return tx, nil
}
```

The error message chain should read like a call stack: `"payment.Process gateway charge txn_abc123: dial tcp 10.0.1.1:9100: connection refused"`.

## Never Discard with _

Never discard errors with `_` except for cases where the error is genuinely non-actionable and that is documented:

```go
// FORBIDDEN
result, _ := gateway.Charge(ctx, req)
_, _ = conn.Write(data)

// Correct — explicit discard with reason comment
_ = conn.Close() // best-effort close; error not actionable after I/O failure
```

For deferred cleanup where the error is non-actionable, document why:
```go
defer func() {
    _ = resp.Body.Close() // body close error not actionable; connection already completed
}()
```

## Sentinel Errors at Package Level

Define sentinel errors as exported package-level variables using `errors.New`:

```go
// payment/errors.go
package payment

import "errors"

var (
    ErrNotFound          = errors.New("transaction not found")
    ErrAlreadyProcessed  = errors.New("transaction already processed")
    ErrInsufficientFunds = errors.New("insufficient funds")
    ErrExpiredCard       = errors.New("card expired")
    ErrDeclined          = errors.New("transaction declined")
    ErrGatewayTimeout    = errors.New("gateway timeout")
)
```

Callers use `errors.Is` to check for sentinel errors:
```go
if errors.Is(err, payment.ErrAlreadyProcessed) {
    return idempotentResponse(tx), nil
}
```

Never compare errors with `==` on wrapped errors — that only works for sentinel errors at the top level.

## Custom Error Types for Domain Errors

When the caller needs structured data from the error, define a custom error type:

```go
// GatewayError carries the response code for error classification
type GatewayError struct {
    ResponseCode string
    Message      string
    Retryable    bool
}

func (e *GatewayError) Error() string {
    return fmt.Sprintf("gateway error %s: %s", e.ResponseCode, e.Message)
}

// Usage
func classifyResponse(code string) error {
    switch code {
    case "00":
        return nil
    case "05", "57":
        return &GatewayError{ResponseCode: code, Message: "do not honor", Retryable: false}
    case "91", "96":
        return &GatewayError{ResponseCode: code, Message: "issuer unavailable", Retryable: true}
    default:
        return &GatewayError{ResponseCode: code, Message: "declined", Retryable: false}
    }
}
```

## errors.Is and errors.As Usage

Use `errors.Is` for sentinel comparison (supports wrapped error chains):
```go
if errors.Is(err, payment.ErrNotFound) {
    http.NotFound(w, r)
    return
}
```

Use `errors.As` to extract typed error information:
```go
var gwErr *payment.GatewayError
if errors.As(err, &gwErr) {
    if gwErr.Retryable {
        return s.retry(ctx, req)
    }
    return nil, fmt.Errorf("terminal decline %s: %w", gwErr.ResponseCode, err)
}
```

Never use type assertions on errors directly — they break with wrapped errors:
```go
// INCORRECT — breaks wrapping
if e, ok := err.(*GatewayError); ok { ... }

// Correct — respects wrapping
var e *GatewayError
if errors.As(err, &e) { ... }
```

## Socket / I/O Error Recovery Patterns

Classify network errors into transient vs permanent before deciding to retry:

```go
func isTransient(err error) bool {
    if err == nil {
        return false
    }

    // Context cancellation / deadline — not transient, do not retry
    if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
        return false
    }

    // Network-level transient errors
    var netErr net.Error
    if errors.As(err, &netErr) {
        return netErr.Timeout() || netErr.Temporary() //nolint:staticcheck
    }

    // Specific syscall errors
    var opErr *net.OpError
    if errors.As(err, &opErr) {
        // Connection refused — remote not up yet — transient
        if opErr.Op == "dial" {
            return true
        }
    }

    return false
}
```

After socket write in a payment host connection: treat any write error as a potential duplicate — trigger reversal flow before retrying.

## Retry Patterns with Backoff

Use exponential backoff with jitter for transient failures. Never retry non-transient errors.

```go
func withRetry(ctx context.Context, maxAttempts int, fn func() error) error {
    var err error
    backoff := 500 * time.Millisecond

    for attempt := 1; attempt <= maxAttempts; attempt++ {
        err = fn()
        if err == nil {
            return nil
        }

        if !isTransient(err) {
            return fmt.Errorf("non-retryable error on attempt %d: %w", attempt, err)
        }

        if attempt == maxAttempts {
            break
        }

        // Jitter: sleep backoff ± 20%
        jitter := time.Duration(rand.Int63n(int64(backoff / 5)))
        sleep := backoff + jitter - (backoff / 10)

        select {
        case <-ctx.Done():
            return fmt.Errorf("retry aborted: %w", ctx.Err())
        case <-time.After(sleep):
        }

        backoff = min(backoff*2, 30*time.Second)
    }

    return fmt.Errorf("all %d attempts failed: %w", maxAttempts, err)
}
```

For payment host I/O specifically:
- Write failure: do not retry the same message — initiate reversal
- Read timeout: send reversal, then optionally retry on a new connection
- Connection refused: retry connection up to 3 times, 5s apart, before alerting

## Error Logging Conventions

Log errors at the boundary where the context is richest (entry point), not at every layer:

```go
// Correct — log once at handler level with full context
func (h *PaymentHandler) HandleCharge(w http.ResponseWriter, r *http.Request) {
    result, err := h.service.Process(r.Context(), req)
    if err != nil {
        h.logger.ErrorContext(r.Context(), "charge failed",
            slog.String("order_id", req.OrderID),
            slog.String("merchant_id", req.MerchantID),
            slog.String("error", err.Error()),
        )
        writeErrorResponse(w, err)
        return
    }
    // ...
}

// Incorrect — logging at every layer creates duplicate log noise
func (s *PaymentService) Process(...) {
    if err := s.repo.Create(...); err != nil {
        log.Printf("repo error: %v", err)  // log noise — caller will also log
        return nil, err
    }
}
```
