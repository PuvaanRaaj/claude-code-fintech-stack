---
name: laravel-patterns
description: Laravel-specific patterns for payment applications — service provider wiring, Eloquent models with PCI-safe hidden fields, FormRequest authorization, API Resources, queued jobs with ShouldBeUnique, event/listener lifecycle, and Horizon supervisor configuration.
origin: fintech-stack
---

# Laravel Patterns

Laravel's container, event system, and queue infrastructure map naturally onto payment flows — but only if the wiring follows conventions that keep card data out of logs, enforce merchant scoping in authorization, and make jobs idempotent by default.

## When to Activate

- Wiring a new payment service into the Laravel container
- Writing Eloquent models for payment entities
- Implementing queued jobs, events, or multi-step form requests
- Reviewing Laravel-specific code structure

---

## Service Provider Registration

```php
// app/Providers/PaymentServiceProvider.php
<?php declare(strict_types=1);

namespace App\Providers;

use App\Services\PaymentHostClient;
use App\Services\PaymentService;
use App\Repositories\TransactionRepository;
use Illuminate\Support\ServiceProvider;

final class PaymentServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(PaymentHostClient::class, function ($app) {
            return new PaymentHostClient(
                baseUrl: config('payment.host_url'),
                timeout: config('payment.host_timeout', 30),
                tlsVerify: config('payment.host_tls_verify', true),
            );
        });

        $this->app->singleton(PaymentService::class, function ($app) {
            return new PaymentService(
                host: $app->make(PaymentHostClient::class),
                transactions: $app->make(TransactionRepository::class),
            );
        });
    }

    public function boot(): void
    {
        // Register payment-specific validation rules
        Validator::extend('luhn', \App\Rules\LuhnRule::class);
    }
}
```

Register in `bootstrap/providers.php` (Laravel 11+).

---

## Eloquent Model for Payment Entities

```php
// app/Models/Transaction.php
<?php declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Factories\HasFactory;

final class Transaction extends Model
{
    use HasFactory;
    // No SoftDeletes — transactions are never soft-deleted (audit requirement)

    protected $fillable = [
        'merchant_id', 'amount', 'currency', 'status',
        'auth_code', 'response_code', 'card_last4', 'card_brand',
        'idempotency_key', 'order_ref',
    ];

    protected $casts = [
        'amount'     => 'integer',  // always minor units
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
    ];

    // Prevent accidentally exposing full card data in serialisation
    protected $hidden = ['pan', 'cvv', 'track_data'];

    public function isApproved(): bool
    {
        return $this->status === 'approved';
    }

    public function merchant(): BelongsTo
    {
        return $this->belongsTo(Merchant::class);
    }

    public function events(): HasMany
    {
        return $this->hasMany(TransactionEvent::class)->orderBy('created_at');
    }
}
```

---

## FormRequest for Payment Validation and Authorization

```php
// app/Http/Requests/ProcessPaymentRequest.php
<?php declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use App\DTOs\PaymentDto;

final class ProcessPaymentRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Merchant may only submit payments for their own merchant ID
        return $this->user()->hasMerchant($this->input('merchant_id'));
    }

    public function rules(): array
    {
        return [
            'amount'      => ['required', 'integer', 'min:1', 'max:99999999'],
            'currency'    => ['required', 'string', 'in:MYR,SGD,USD'],
            'card_token'  => ['required', 'string', 'starts_with:tok_'],
            'merchant_id' => ['required', 'string', 'exists:merchants,merchant_id'],
            'order_ref'   => ['required', 'string', 'max:32'],
        ];
    }

    public function toDto(): PaymentDto
    {
        return new PaymentDto(
            amount:         $this->integer('amount'),
            currency:       $this->string('currency'),
            cardToken:      $this->string('card_token'),
            merchantId:     $this->string('merchant_id'),
            orderRef:       $this->string('order_ref'),
            idempotencyKey: $this->header('Idempotency-Key'),
        );
    }
}
```

---

## API Resource for Payment Responses

```php
// app/Http/Resources/PaymentResource.php
<?php declare(strict_types=1);

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

final class PaymentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'          => $this->resource->id,
            'status'      => $this->resource->status,
            'amount'      => $this->resource->amount,
            'currency'    => $this->resource->currency,
            'auth_code'   => $this->when($this->resource->isApproved(), $this->resource->auth_code),
            'card_last4'  => $this->resource->card_last4,
            'card_brand'  => $this->resource->card_brand,
            'merchant_id' => $this->resource->merchant_id,
            'order_ref'   => $this->resource->order_ref,
            'created_at'  => $this->resource->created_at->toIso8601String(),
        ];
    }
}
```

---

## Job with ShouldBeUnique

```php
// app/Jobs/ProcessPaymentJob.php
<?php declare(strict_types=1);

namespace App\Jobs;

use App\DTOs\PaymentDto;
use App\Services\PaymentService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldBeUnique;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

final class ProcessPaymentJob implements ShouldQueue, ShouldBeUnique
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;
    public int $maxExceptions = 2;
    public array $backoff = [30, 60, 120]; // seconds

    public string $uniqueId;

    public function __construct(private readonly PaymentDto $dto)
    {
        $this->uniqueId = $dto->idempotencyKey;
        $this->onQueue('payments');
    }

    public function handle(PaymentService $service): void
    {
        $service->process($this->dto);
    }

    public function failed(\Throwable $e): void
    {
        Log::error('ProcessPaymentJob failed', [
            'idempotency_key' => $this->dto->idempotencyKey,
            'merchant_id'     => $this->dto->merchantId,
            'error'           => $e->getMessage(),
        ]);
    }
}
```

---

## Event and Listener for Transaction Lifecycle

```php
// app/Events/PaymentAuthorised.php
final class PaymentAuthorised
{
    public function __construct(public readonly Transaction $transaction) {}
}

// app/Listeners/SendPaymentWebhook.php
final class SendPaymentWebhook implements ShouldQueue
{
    public function handle(PaymentAuthorised $event): void
    {
        $transaction = $event->transaction;
        dispatch(new SendWebhookJob($transaction->merchant->webhook_url, $transaction));
    }
}

// Register in EventServiceProvider:
// PaymentAuthorised::class => [SendPaymentWebhook::class, CreateSettlementRecord::class]
```

---

## Horizon Supervisor Configuration

```php
// config/horizon.php — queue supervisor for payment jobs
'environments' => [
    'production' => [
        'payment-supervisor' => [
            'connection'   => 'redis',
            'queue'        => ['payments', 'webhooks', 'default'],
            'balance'      => 'auto',
            'minProcesses' => 2,
            'maxProcesses' => 10,
            'tries'        => 3,
            'timeout'      => 60,
        ],
    ],
],
```

Monitor at `/horizon`. Alerts configured via `Horizon::routeSmsNotificationsTo()`.

---

## Best Practices

- **`$hidden = ['pan', 'cvv', 'track_data']` on every payment model** — prevents accidental serialisation of card data in API responses or logs
- **`authorize()` scopes by merchant** — `$this->user()->hasMerchant($merchantId)` is the first gate; never skip it
- **`ShouldBeUnique` keyed on idempotency key** — eliminates duplicate job dispatches without application-level locking
- **`toDto()` on FormRequest** — keeps the controller thin and the DTO clean; the controller never touches raw input arrays
- **Event + Listener for lifecycle side effects** — webhook dispatch, settlement records, and audit events are listeners, not service method calls
- **Horizon `balance: auto`** — auto-scales workers between queues based on depth; set `minProcesses ≥ 2` so payments queue never starves
