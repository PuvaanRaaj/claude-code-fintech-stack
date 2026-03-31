# PHP 8.3+ Code Style Rules

## Strict Types

Every PHP file must declare strict types as the very first statement after the opening tag:

```php
<?php

declare(strict_types=1);
```

No exceptions. Files without `declare(strict_types=1)` will fail CI linting.

## Return Types

All public and protected methods must have explicit return types:

```php
// Correct
public function process(array $data): Transaction
public function findById(int $id): ?User
public function validate(): bool
public function handle(): void
protected function buildQuery(): Builder

// Incorrect — missing return type
public function process(array $data)
```

Private methods should also have return types unless the return type is genuinely mixed or complex to express without generics.

Use union types for legitimate multi-type returns: `string|int`, `Transaction|null`.
Avoid `mixed` — it signals a design problem. Use specific types or interfaces.

## Readonly Properties and Constructor Promotion

Use constructor promotion for all simple dependency injection:

```php
// Correct — constructor promotion with readonly
final class PaymentService
{
    public function __construct(
        private readonly PaymentGateway $gateway,
        private readonly TransactionRepository $transactions,
        private readonly LoggerInterface $logger,
    ) {}
}

// Incorrect — verbose manual assignment
class PaymentService
{
    private PaymentGateway $gateway;

    public function __construct(PaymentGateway $gateway)
    {
        $this->gateway = $gateway;
    }
}
```

Use `readonly` on properties that must not change after construction. DTOs and value objects should be fully readonly:

```php
final readonly class MoneyAmount
{
    public function __construct(
        public int $minor,
        public string $currency,
    ) {}
}
```

## Named Arguments

Use named arguments when calling functions or constructors with 4 or more parameters, or when argument order is ambiguous:

```php
// Correct — named arguments for clarity
$transaction = Transaction::create(
    amount: $request->integer('amount'),
    currency: $request->string('currency'),
    orderId: $request->string('order_id'),
    merchantId: $merchant->id,
);

// Also correct — named args clarify intent on built-in functions
$encrypted = openssl_encrypt(
    data: $plaintext,
    cipher_algo: 'aes-256-gcm',
    passphrase: $key,
    options: OPENSSL_RAW_DATA,
    iv: $iv,
    tag: $tag,
);
```

## match Over switch

Prefer `match` over `switch` for value-based dispatch:

```php
// Correct — match
$label = match($responseCode) {
    '00'    => 'Approved',
    '05'    => 'Do Not Honor',
    '51'    => 'Insufficient Funds',
    '54'    => 'Expired Card',
    '57'    => 'Transaction Not Permitted',
    default => "Unknown ({$responseCode})",
};

// Avoid — switch with fallthrough risk
switch ($responseCode) {
    case '00':
        $label = 'Approved';
        break;
    // ...
}
```

`match` is strict (===), throws `UnhandledMatchError` on unmatched value (no silent fallthrough), and returns a value.

## Short Closures

Use arrow functions (`fn =>`) for single-expression closures that capture from outer scope:

```php
// Correct — short closure
$amounts = array_map(fn(Transaction $t) => $t->amount, $transactions);
$active  = array_filter($merchants, fn(Merchant $m) => $m->is_active);

// Only use regular closure when multiple statements are needed
$processed = array_map(function (Transaction $t) use ($logger) {
    $logger->info('processing', ['id' => $t->id]);
    return $t->process();
}, $transactions);
```

## Import Ordering

Imports must follow this order, each group separated by a blank line:

1. PHP built-in / global namespace (none needed typically)
2. Framework classes (`Illuminate\*`, `Laravel\*`)
3. Third-party packages (`Stripe\*`, `Monolog\*`)
4. Application classes (`App\*`)

Within each group, alphabetical order. Use `pint` to enforce automatically.

```php
<?php

declare(strict_types=1);

namespace App\Services;

use Illuminate\Contracts\Cache\Repository as Cache;
use Illuminate\Support\Facades\Log;

use Psr\Log\LoggerInterface;

use App\Contracts\PaymentGateway;
use App\Models\Transaction;
use App\Repositories\TransactionRepository;
```

## Pint Configuration Alignment

Use Laravel Pint with the `laravel` preset plus these overrides in `pint.json`:

```json
{
    "preset": "laravel",
    "rules": {
        "declare_strict_types": true,
        "ordered_imports": {
            "sort_algorithm": "alpha",
            "imports_order": ["class", "function", "const"]
        },
        "no_unused_imports": true,
        "single_quote": true,
        "trailing_comma_in_multiline": {
            "elements": ["arguments", "arrays", "parameters"]
        },
        "php_unit_method_casing": {
            "case": "snake_case"
        },
        "final_class": false
    }
}
```

Run on CI: `./vendor/bin/pint --test` (exits non-zero if changes needed).
Run locally: `./vendor/bin/pint` (fixes in place).

## Additional Rules

- Use `final` on classes that must not be extended (most service/value classes)
- Enums over class constants for fixed value sets (PHP 8.1+)
- Intersection types for compound type constraints: `Countable&Traversable`
- Use `first-class callable syntax` for passing methods as callbacks: `$this->format(...)` instead of `fn($x) => $this->format($x)`
- Nullsafe operator `?->` for optional chaining — no null checks where avoidable
- Fibers for cooperative concurrency where applicable (PHP 8.1+)
