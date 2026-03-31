# Laravel PCI-Compliant Payment Endpoint

A complete example of a PCI-compliant payment processing endpoint in Laravel 11+, from route definition through response, with annotations on what the `pci-review` skill passes and flags.

## Route Definition

```php
// routes/api.php
Route::prefix('v1')->name('v1.')->middleware(['auth:sanctum', 'throttle:payments'])->group(function () {
    Route::post('payments', ProcessPaymentController::class)->name('payments.store');
});

// Rate limiter definition in AppServiceProvider::boot()
RateLimiter::for('payments', function (Request $request) {
    return Limit::perMinute(10)->by($request->user()->id);
});
```

## FormRequest

```php
<?php

declare(strict_types=1);

namespace App\Http\Requests\Payment;

use App\Enums\Currency;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

final class ProcessPaymentRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Authorization: merchant must own the terminal making the request
        return $this->user()->can('create', Payment::class);
    }

    public function rules(): array
    {
        return [
            // Amount in minor units (cents/sen) — never accept decimal amount strings
            'amount'      => ['required', 'integer', 'min:1', 'max:99999999'],
            'currency'    => ['required', 'string', 'size:3', Rule::in(Currency::codes())],
            'order_id'    => ['required', 'string', 'max:64', 'unique:transactions,order_id'],
            'description' => ['nullable', 'string', 'max:255'],

            // Token from client-side tokenization — NEVER accept raw card numbers
            'payment_token' => ['required', 'string', 'max:255'],

            // Metadata for reporting — must not contain card data
            'metadata'    => ['nullable', 'array', 'max:10'],
            'metadata.*'  => ['string', 'max:255'],
        ];
    }

    public function messages(): array
    {
        return [
            'amount.min'   => 'Amount must be at least 1 minor unit.',
            'order_id.unique' => 'This order ID has already been processed.',
        ];
    }

    protected function prepareForValidation(): void
    {
        // Normalize order_id to lowercase for deduplication consistency
        if ($this->has('order_id')) {
            $this->merge(['order_id' => strtolower($this->string('order_id'))]);
        }
    }
}
```

## Controller

```php
<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Payment\ProcessPaymentRequest;
use App\Http\Resources\TransactionResource;
use App\Services\PaymentService;
use Illuminate\Http\JsonResponse;

final class ProcessPaymentController
{
    public function __construct(
        private readonly PaymentService $payments,
    ) {}

    public function __invoke(ProcessPaymentRequest $request): JsonResponse
    {
        // validated() gives us only the declared fields — no mass-assignment risk
        $transaction = $this->payments->process(
            merchant: $request->user(),
            data: $request->validated(),
        );

        return response()->json(
            TransactionResource::make($transaction),
            201,
        );
    }
}
```

## Service Layer

```php
<?php

declare(strict_types=1);

namespace App\Services;

use App\Contracts\PaymentGateway;
use App\Events\PaymentProcessed;
use App\Exceptions\PaymentDeclinedException;
use App\Models\Transaction;
use App\Models\User;
use App\Repositories\TransactionRepository;
use Illuminate\Support\Facades\Log;

final class PaymentService
{
    public function __construct(
        private readonly PaymentGateway $gateway,
        private readonly TransactionRepository $transactions,
    ) {}

    public function process(User $merchant, array $data): Transaction
    {
        // Create transaction record BEFORE gateway call
        // This gives us an ID to reference in audit logs even if the gateway call fails
        $transaction = $this->transactions->create([
            'merchant_id'   => $merchant->id,
            'order_id'      => $data['order_id'],
            'amount'        => $data['amount'],
            'currency'      => $data['currency'],
            'payment_token' => $data['payment_token'],
            'status'        => 'pending',
            'metadata'      => $data['metadata'] ?? [],
        ]);

        // Structured log — no card data, no raw token values in log message
        Log::info('payment.attempt', [
            'transaction_id' => $transaction->id,
            'merchant_id'    => $merchant->id,
            'amount'         => $data['amount'],
            'currency'       => $data['currency'],
            'order_id'       => $data['order_id'],
        ]);

        try {
            $response = $this->gateway->charge(
                token: $data['payment_token'],
                amount: $data['amount'],
                currency: $data['currency'],
                reference: $transaction->id,
            );
        } catch (\Throwable $e) {
            $this->transactions->markFailed($transaction, $e->getMessage());

            Log::error('payment.gateway_error', [
                'transaction_id' => $transaction->id,
                'error'          => $e->getMessage(),
                // Do NOT log $data or $e->getTrace() — may contain token
            ]);

            throw $e;
        }

        if (! $response->isApproved()) {
            $this->transactions->markDeclined($transaction, $response->responseCode());

            Log::info('payment.declined', [
                'transaction_id' => $transaction->id,
                'response_code'  => $response->responseCode(),
            ]);

            throw new PaymentDeclinedException(
                code: $response->responseCode(),
                message: $response->declineMessage(),
            );
        }

        $approved = $this->transactions->markApproved(
            transaction: $transaction,
            approvalCode: $response->approvalCode(),
            gatewayReference: $response->reference(),
        );

        Log::info('payment.approved', [
            'transaction_id'   => $approved->id,
            'approval_code'    => $response->approvalCode(),
            'gateway_ref'      => $response->reference(),
        ]);

        event(new PaymentProcessed($approved));

        return $approved;
    }
}
```

## Response Resource

```php
<?php

declare(strict_types=1);

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

final class TransactionResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'               => $this->id,
            'order_id'         => $this->order_id,
            'status'           => $this->status,
            'amount'           => $this->amount,
            'currency'         => $this->currency,
            'approval_code'    => $this->when(
                $this->status === 'approved',
                $this->approval_code,
            ),
            'gateway_reference' => $this->when(
                $this->status === 'approved',
                $this->gateway_reference,
            ),
            'created_at'       => $this->created_at->toIso8601String(),
            // NEVER include: payment_token, raw card data, merchant secret keys
        ];
    }
}
```

## PCI Review Findings

### What the pci-review skill PASSES

- No raw PAN, CVV, track data, or PIN in any class
- `payment_token` replaces card data — client-side tokenization pattern
- Amount in minor integer units — no decimal string parsing risk
- Structured logging with explicit field allowlist
- FormRequest blocks `$request->all()` pattern
- Response resource uses `$this->when()` to conditionally expose approval code
- No `dd()`, `dump()`, `var_dump()` in any code path
- `unique:transactions,order_id` prevents duplicate processing

### What the pci-review skill FLAGS (and how to resolve)

**FLAG**: `payment_token` logged nowhere — confirm this is intentional
**Resolve**: Correct — token must not appear in logs. Keep as-is.

**FLAG**: Exception `$e->getMessage()` logged in gateway error — verify gateway exceptions don't include card data in message
**Resolve**: Add a `GatewayException` that sanitizes its message: `throw new GatewayException("Gateway error: {$responseCode}")` without propagating raw HTTP body.

**FLAG**: `metadata.*` max:255 validation but no content scanning — user-provided metadata could include PAN
**Resolve**: Add a custom validation rule `NoPANRule` that applies the PAN regex pattern to all metadata values.

**FLAG**: `transaction_id` in logs is an auto-increment integer — consider using UUID to avoid enumeration
**Resolve**: Use `$table->uuid('id')->primary()` in migration, `HasUuids` trait on model.
