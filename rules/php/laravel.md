# Laravel 11+ Architecture Rules

## Controllers

- Controllers must be thin — no business logic, no Eloquent calls directly
- Prefer single-action controllers (`__invoke`) for non-RESTful actions
- Constructor injection only — never resolve from the container inside methods
- Controllers call one service method per action, then return a response
- Never use `$request->all()` — use validated data from FormRequest or explicit `$request->input()`
- Route model binding is preferred over manual `Model::find($id)` calls
- Always return typed responses: `JsonResponse`, `RedirectResponse`, `Response`
- Controllers must not catch exceptions — use `app/Exceptions/Handler.php` or render methods
- Max 50 lines per controller action method; extract to service if over

```php
// Correct: single-action, thin controller
final class ProcessPaymentController
{
    public function __construct(
        private readonly PaymentService $payments,
    ) {}

    public function __invoke(ProcessPaymentRequest $request): JsonResponse
    {
        $result = $this->payments->process($request->validated());
        return response()->json(PaymentResource::make($result), 201);
    }
}
```

## FormRequests

- Every mutation endpoint (POST, PUT, PATCH, DELETE) must have a FormRequest
- No validation logic in controllers — all in FormRequest::rules()
- Authorization logic goes in FormRequest::authorize(), not controllers
- Use `prepareForValidation()` to normalize input (e.g., strip spaces from PAN before masking)
- Custom messages in `messages()`, attribute names in `attributes()`
- Validation rules must be array syntax, not pipe syntax for complex rules
- FormRequest class names: `{Action}{Resource}Request` (e.g., `ProcessPaymentRequest`)

```php
final class ProcessPaymentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Payment::class);
    }

    public function rules(): array
    {
        return [
            'amount'      => ['required', 'integer', 'min:1', 'max:99999999'],
            'currency'    => ['required', 'string', 'size:3', Rule::in(Currency::codes())],
            'order_id'    => ['required', 'string', 'max:64', 'unique:transactions,order_id'],
            'description' => ['nullable', 'string', 'max:255'],
        ];
    }
}
```

## Service Layer

- Services contain all business logic — fat services, thin controllers
- One service per domain concept (e.g., `PaymentService`, `RefundService`, `ReconciliationService`)
- Services must be final classes with constructor injection
- Services never call other services directly — use domain events or orchestrator services
- All public methods must have explicit return types
- Services may throw domain exceptions; never return null to indicate failure
- Never inject `Request` into a service — pass plain data (arrays or DTOs)
- Complex orchestration: use a dedicated `{Workflow}Orchestrator` class

```php
final class PaymentService
{
    public function __construct(
        private readonly PaymentGateway $gateway,
        private readonly TransactionRepository $transactions,
        private readonly AuditLogger $audit,
    ) {}

    public function process(array $data): Transaction
    {
        $transaction = $this->transactions->create($data);
        $response = $this->gateway->charge($transaction);
        $this->audit->log('payment.processed', $transaction->id);
        return $transaction->refresh();
    }
}
```

## Eloquent Best Practices

- Always eager-load relationships — never allow N+1 queries
- Use `with()` at the query origin, not in resource/presenter layer
- Named scopes for all reusable query constraints: `scopeApproved()`, `scopeForMerchant()`
- Never use raw SQL unless absolutely necessary; use `DB::raw()` only with bound parameters
- Cast attributes in `$casts` array — never cast manually in application code
- Use `withCount()` instead of loading full relationship just to count
- `$fillable` must be explicit — never use `$guarded = []`
- Soft deletes on all tables with customer data
- Never store computed values — use accessors or dedicated read models
- Model event listeners only for lightweight side-effects; heavy work → jobs

```php
// Correct: eager loading, scope, explicit fillable
$transactions = Transaction::with(['merchant', 'card'])
    ->approved()
    ->forMerchant($merchantId)
    ->latest()
    ->paginate(50);
```

## Route Conventions

- API routes versioned: `/api/v1/`, `/api/v2/` — never break existing versions
- Route names: `{version}.{resource}.{action}` (e.g., `v1.payments.store`)
- Group related routes with `Route::prefix()->name()->middleware()`
- Middleware grouping: `auth:sanctum` + `verified` + `throttle:api` on all authenticated routes
- Rate limiting: define named rate limiters in `AppServiceProvider`, not inline
- No anonymous route closures in production routes — always use controller classes
- Route parameters must use snake_case: `{order_id}`, not `{orderId}`
- Webhook routes: separate middleware group without CSRF, with signature verification

```php
Route::prefix('v1')->name('v1.')->middleware(['auth:sanctum', 'throttle:api'])->group(function () {
    Route::apiResource('payments', PaymentController::class)->only(['index', 'store', 'show']);
    Route::post('payments/{payment}/refund', RefundController::class)->name('payments.refund');
});
```

## Queue Patterns

- Always specify queue name — never use default queue for payment jobs
- Queue names: `payments`, `notifications`, `reports`, `reconciliation`
- All jobs must implement `ShouldBeUnique` where double-processing is dangerous
- Retry configuration: `$tries`, `$backoff`, `$timeout` must be explicit on every job
- Jobs must be idempotent — safe to run twice without side effects
- Store job state in database, not in job payload for long-running jobs
- Never queue closures — always use named job classes
- `$maxExceptions` to limit retries on permanent failures (e.g., 3 for gateway calls)

```php
final class ProcessPaymentJob implements ShouldQueue, ShouldBeUnique
{
    public int $tries = 3;
    public array $backoff = [60, 300, 900];
    public int $timeout = 120;
    public int $maxExceptions = 3;

    public function uniqueId(): string
    {
        return $this->orderId;
    }
}
```

## Config Conventions

- Never call `env()` in application code — only in `config/*.php` files
- Every environment variable must have a corresponding config key
- Sensitive values (keys, secrets) always via config, never via env() inline
- Group related config: `config/payment.php` for gateway settings
- Boolean env values: use `(bool) env('FEATURE_FLAG', false)` in config, not string comparison
- Config keys: snake_case, namespaced by service (e.g., `payment.gateway.timeout`)

```php
// config/payment.php — correct
return [
    'gateway' => [
        'base_url' => env('PAYMENT_GATEWAY_URL', 'https://api.example.com'),
        'timeout'  => (int) env('PAYMENT_GATEWAY_TIMEOUT', 30),
        'verify_ssl' => (bool) env('PAYMENT_GATEWAY_VERIFY_SSL', true),
    ],
];

// Incorrect — never do this in app code
$key = env('PAYMENT_SECRET_KEY');
```

## Caching Rules

- Always tag caches by entity: `Cache::tags(['merchant', "merchant:{$id}"])`
- TTL is mandatory on every `Cache::put()` / `Cache::remember()` — never omit
- Flush by tag when entity updates: `Cache::tags("merchant:{$id}")->flush()`
- Never cache PANs, CVVs, track data, or any cardholder data under any circumstances
- Cache keys: namespaced with version prefix to enable easy invalidation (`v1:merchant:123:rates`)
- Use `Cache::lock()` for distributed locking on critical sections
- Read-heavy config (exchange rates, BIN tables): cache with long TTL (1 hour+), warm on deploy
- Never cache `Request` objects, Eloquent models with relationships, or closures
