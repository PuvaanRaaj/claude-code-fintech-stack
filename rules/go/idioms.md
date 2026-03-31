# Go 1.22+ Idiomatic Patterns

## Accept Interfaces, Return Structs

Functions and methods accept the narrowest interface that satisfies the use case, and return concrete structs.

```go
// Correct — accept narrow interface, return concrete struct
func NewPaymentProcessor(gateway PaymentGateway, logger *slog.Logger) *PaymentProcessor {
    return &PaymentProcessor{gateway: gateway, logger: logger}
}

// Correct — io.Reader is narrower than *os.File
func ParseISO8583(r io.Reader) (*Message, error) { ... }

// Incorrect — accepting *os.File when io.Reader suffices
func ParseISO8583(f *os.File) (*Message, error) { ... }
```

Define interfaces at the consumer site, not the producer site. An interface with one method is often enough.

## context.Context as First Parameter

Every function that performs I/O, calls an external service, or may need cancellation must accept `context.Context` as its first parameter named `ctx`:

```go
// Correct
func (s *PaymentService) Process(ctx context.Context, req ProcessRequest) (*Transaction, error)
func (r *TransactionRepository) FindByID(ctx context.Context, id string) (*Transaction, error)
func (c *GatewayClient) Charge(ctx context.Context, amount int64, currency string) (*ChargeResponse, error)

// Incorrect — context buried or missing
func (s *PaymentService) Process(req ProcessRequest, ctx context.Context) (*Transaction, error)
func (s *PaymentService) Process(req ProcessRequest) (*Transaction, error)
```

Never store `context.Context` in a struct. Pass it through call chains.
Use `context.WithTimeout` at the entry point (HTTP handler, job runner), not deep in the stack.

## Table-Driven Tests

All unit tests must use table-driven format with `t.Run` for subtests:

```go
func TestMaskPAN(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected string
    }{
        {"visa 16-digit",  "4111111111111111", "411111****1111"},
        {"amex 15-digit",  "378282246310005",  "378282****0005"},
        {"short pan",      "1234",             "****"},
        {"empty string",   "",                 ""},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := MaskPAN(tt.input)
            if got != tt.expected {
                t.Errorf("MaskPAN(%q) = %q, want %q", tt.input, got, tt.expected)
            }
        })
    }
}
```

Never write repetitive `TestFuncCase1`, `TestFuncCase2` functions. Always use subtests.

## Package Naming

- Package names: lowercase, single word, no underscores, no mixedCase
- Package name should describe what it provides, not what it contains
  - `payment` not `payments`, `iso8583` not `isoParser`
- Avoid `util`, `helper`, `common`, `misc` — put code in the package it belongs to
- Test files: same package for white-box (`package payment`), `_test` suffix for black-box (`package payment_test`)
- `internal/` packages for code that must not be imported outside the module

```
pkg/
  payment/     — payment processing domain
  iso8583/     — ISO 8583 encode/decode
  gateway/     — gateway client implementations
  hsm/         — HSM client interface + implementations
internal/
  testutil/    — test helpers not for external use
```

## defer Patterns

Use `defer` for cleanup — always defer immediately after acquiring a resource:

```go
// Correct — defer immediately after open/acquire
conn, err := net.DialTimeout("tcp", addr, 10*time.Second)
if err != nil {
    return nil, fmt.Errorf("dial gateway: %w", err)
}
defer conn.Close()

// Correct — defer for mutex unlock
mu.Lock()
defer mu.Unlock()

// Correct — named return to capture defer error
func (r *Repo) Insert(ctx context.Context, tx *Transaction) (err error) {
    dbtx, err := r.db.BeginTx(ctx, nil)
    if err != nil {
        return fmt.Errorf("begin tx: %w", err)
    }
    defer func() {
        if err != nil {
            _ = dbtx.Rollback()
        }
    }()
    // ...
    return dbtx.Commit()
}
```

Do not defer in tight loops — the deferred calls accumulate until the function returns.

## Short Variable Scope

Declare variables as close to use as possible. Use short `if` init statements:

```go
// Correct — scoped to the if block
if resp, err := client.Post(ctx, url, body); err != nil {
    return fmt.Errorf("gateway post: %w", err)
} else {
    return parseResponse(resp)
}

// Also correct — scoped for loop variable (Go 1.22 loop variable fix)
for _, item := range items {
    go process(item)  // item is correctly scoped per iteration in Go 1.22+
}
```

Avoid package-level `var` blocks for mutable state — it creates hidden dependencies.

## Avoid Global State

- No `init()` functions that set package-level mutable state
- No `sync.Once` at package level for lazy initialization of dependencies — inject at construction
- Singletons: pass via dependency injection, not package-level globals
- Test globals are allowed for read-only lookup tables (e.g., MTI name map)

```go
// Incorrect — global mutable state
var defaultGateway PaymentGateway

func SetGateway(g PaymentGateway) { defaultGateway = g }

// Correct — injected dependency
type PaymentService struct {
    gateway PaymentGateway
}
func NewPaymentService(gateway PaymentGateway) *PaymentService {
    return &PaymentService{gateway: gateway}
}
```

## Error Wrapping with %w

Always wrap errors with contextual information using `fmt.Errorf` and `%w`:

```go
// Correct
if err := db.QueryRowContext(ctx, query, id).Scan(&tx); err != nil {
    return nil, fmt.Errorf("transaction.FindByID %s: %w", id, err)
}

// Incorrect — naked return loses context
if err := db.QueryRowContext(ctx, query, id).Scan(&tx); err != nil {
    return nil, err
}

// Incorrect — string concatenation loses error chain
return nil, errors.New("failed: " + err.Error())
```

The wrapped error message should read as a call stack when unwrapped: `"payment.Process: gateway.Charge: dial tcp: timeout"`.

## Goroutine Hygiene

- Never start a goroutine without a way to wait for it or stop it
- Use `sync.WaitGroup` or `errgroup.Group` for fan-out patterns
- Always pass context to goroutines for cancellation
- Goroutines must not outlive their parent context
- Use buffered channels sized to the maximum number of concurrent senders to avoid goroutine leaks

```go
// Correct — errgroup with context propagation
g, ctx := errgroup.WithContext(ctx)

for _, item := range items {
    item := item // pre-1.22: capture loop variable
    g.Go(func() error {
        return processItem(ctx, item)
    })
}

if err := g.Wait(); err != nil {
    return fmt.Errorf("batch process: %w", err)
}
```
