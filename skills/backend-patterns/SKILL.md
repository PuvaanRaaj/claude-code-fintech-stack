---
name: backend-patterns
description: Backend architecture patterns for payment services — thin controller/service/repository layers in PHP/Laravel and Go, event sourcing for transaction history, saga pattern for distributed payment flows, and idempotent job design.
origin: fintech-stack
---

# Backend Patterns

Payment logic that lives in a controller is logic that cannot be unit tested without an HTTP stack. Payment logic that calls the database directly from a service is logic that cannot be stubbed for host integration tests. The layered architecture exists because payment code has multiple failure modes that must be testable independently.

## When to Activate

- Designing or reviewing a new service class, handler, or repository
- Developer asks "how should I structure this?", "where does this logic go?", or "what pattern should I use?"
- Code review finds business logic in a controller or database calls in a service

---

## Laravel: Thin Controller → Service → Repository → Model

**Controller** — HTTP in/out only. No business logic.
```php
class PaymentController extends Controller
{
    public function __construct(private readonly PaymentService $payments) {}

    public function store(ProcessPaymentRequest $request): JsonResponse
    {
        $result = $this->payments->process($request->toDto());
        return new PaymentResource($result)
            ->response()
            ->setStatusCode(201);
    }
}
```

**Service** — Orchestrates business logic. No direct database calls.
```php
class PaymentService
{
    public function __construct(
        private readonly TransactionRepository $transactions,
        private readonly PaymentHostClient $host,
        private readonly IdempotencyService $idempotency,
    ) {}

    public function process(PaymentDto $dto): Transaction
    {
        return $this->idempotency->wrap($dto->idempotencyKey, function () use ($dto) {
            $response = $this->host->authorise($dto);
            return $this->transactions->createFromHostResponse($dto, $response);
        });
    }
}
```

**Repository** — Database access only. Returns domain models or DTOs.
```php
class TransactionRepository
{
    public function createFromHostResponse(PaymentDto $dto, HostResponse $resp): Transaction
    {
        return Transaction::create([
            'merchant_id'   => $dto->merchantId,
            'amount'        => $dto->amount,
            'currency'      => $dto->currency,
            'status'        => $resp->isApproved() ? 'approved' : 'declined',
            'auth_code'     => $resp->authCode,
            'response_code' => $resp->responseCode,
        ]);
    }
}
```

---

## Go: Handler → Service → Repository → Domain

```go
// handler/payment.go — HTTP layer only
func (h *PaymentHandler) Create(w http.ResponseWriter, r *http.Request) {
    var req CreatePaymentRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondError(w, http.StatusBadRequest, "INVALID_BODY", err.Error())
        return
    }
    result, err := h.svc.Process(r.Context(), req.toDomain())
    if err != nil {
        respondServiceError(w, err)
        return
    }
    respondJSON(w, http.StatusCreated, toPaymentResponse(result))
}

// service/payment.go — business logic
func (s *PaymentService) Process(ctx context.Context, p payment.Payment) (*payment.Transaction, error) {
    resp, err := s.host.Authorise(ctx, p)
    if err != nil {
        return nil, fmt.Errorf("host authorise: %w", err)
    }
    return s.repo.Create(ctx, p, resp)
}

// repository/transaction.go — database only
func (r *TransactionRepo) Create(ctx context.Context, p payment.Payment, resp host.Response) (*payment.Transaction, error) {
    // INSERT INTO transactions ...
}
```

---

## Event Sourcing for Transaction History

```php
// TransactionEvent is append-only — no updates, no deletes
class TransactionEvent extends Model
{
    protected $guarded = [];
    const UPDATED_AT = null; // immutable — events do not change
}

// Emit an event at every state change
TransactionEvent::create([
    'transaction_id' => $transaction->id,
    'event_type'     => 'payment.authorised',
    'payload'        => ['auth_code' => $authCode, 'response_code' => '00'],
    'created_at'     => now(),
]);
```

This gives you a full audit trail for disputes and reconciliation without relying on `updated_at` timestamps on the transaction row itself.

---

## Saga Pattern for Distributed Payment Flows

For multi-step flows (debit → notify issuer → settle → notify merchant):

```
Step 1: Debit customer account
  Success → emit PaymentDebited event → proceed to step 2
  Failure → saga ends; no compensations needed

Step 2: Notify issuer
  Success → emit IssuerNotified event → proceed to step 3
  Failure → compensate: reverse debit → emit DebitReversed

Step 3: Initiate settlement
  Success → emit SettlementInitiated → proceed to step 4
  Failure → compensate: reverse debit, mark IssuerNotified as reversed
```

Each step is an idempotent job. Store saga state in a `payment_sagas` table so any step can be replayed after a crash.

---

## Idempotent Job (Laravel)

```php
class ProcessPaymentJob implements ShouldQueue, ShouldBeUnique
{
    public int $tries  = 3;
    public int $backoff = 30;
    public string $uniqueId;

    public function __construct(private readonly PaymentDto $dto)
    {
        $this->uniqueId = $dto->idempotencyKey; // one job per idempotency key
    }

    public function handle(PaymentService $service): void
    {
        $service->process($this->dto);
    }

    public function failed(\Throwable $e): void
    {
        Log::error('Payment job failed', [
            'idempotency_key' => $this->dto->idempotencyKey,
            'error'           => $e->getMessage(),
        ]);
    }
}
```

---

## Best Practices

- **Controller = HTTP adapter only** — validation, authentication, serialization; nothing else
- **Service = one use-case per method** — `process()`, `reverse()`, `refund()`; not `handlePaymentOrRefundOrReversal()`
- **Repository = one database per class** — never call a second repository from inside a repository
- **Event sourcing for financial records** — a `transactions` row with an `updated_at` column cannot prove what the status was at 14:23:01; event rows can
- **Saga compensations are idempotent too** — a compensation job may run twice; it must be safe to reverse a reversal that already succeeded
