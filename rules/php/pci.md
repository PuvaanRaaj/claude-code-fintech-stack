# PCI-DSS Rules for PHP / Laravel

## Data That Must Never Be Stored

The following data must never be persisted to any storage (database, file, cache, log, session, queue payload):

- **Full PAN** after authorization is complete — store only masked or tokenized form
- **CVV2 / CVC2 / CAV2** — never store under any circumstances, not even temporarily
- **Track 1 / Track 2 equivalent data** — full magnetic stripe data must not persist post-auth
- **PIN blocks** — never store, log, or transmit outside an HSM context
- **Card expiry** — do not store alongside masked PAN unless required for recurring billing with explicit tokenization
- **Cardholder name** — treat as sensitive; do not store unless operationally required and access-controlled

If any of these appear in a migration, model `$fillable`, or repository method — stop and reject the change.

## Card Masking Formula

All display, logging, and API responses must use: **first 6 digits + `****` + last 4 digits**

```php
// Correct masking
function maskPan(string $pan): string
{
    $digits = preg_replace('/\D/', '', $pan);
    if (strlen($digits) < 13) {
        return str_repeat('*', strlen($digits));
    }
    return substr($digits, 0, 6) . '****' . substr($digits, -4);
}
// 4111111111111111 → 411111****1111
// 378282246310005  → 378282****0005
```

Never display more than 6+4 digits. Never log the full PAN even "temporarily for debugging".

## Log Masking Requirements

- Never log raw PAN, CVV, track data, or PIN block
- Mask before passing to any logger: `Log::info()`, `\Log::channel()->debug()`, Monolog handlers
- Transaction log entries must use: token reference, masked PAN, or transaction ID — not full card data
- HTTP request/response logging must strip `card_number`, `cvv`, `track_data`, `pin` fields
- Structured log fields for payment events:
  ```
  transaction_id, merchant_id, amount, currency, masked_pan, response_code, status
  ```
- Audit log retention: minimum 1 year online, 3 years archive per PCI DSS 10.7
- Log file permissions: `640` (owner rw, group r, world none)

## Forbidden Debugging Functions

The following must never appear in production code paths that handle payment data:

```php
// FORBIDDEN in any file that touches payment/card data:
dd($transaction);          // dumps and dies — may expose PAN
dump($request->all());     // may expose raw card input
var_dump($response);       // raw object dump
print_r($cardData);        // plaintext card data to output
var_export($payment);      // same risk as print_r
```

If any of these are found in a controller, service, or repository touching payment data, treat as a PCI violation and block the commit.

Use structured logging instead:
```php
Log::info('payment.attempt', [
    'transaction_id' => $transaction->id,
    'masked_pan'     => maskPan($pan),
    'amount'         => $transaction->amount,
]);
```

## TLS Requirements

- Minimum TLS 1.2 for all payment-related HTTP clients; TLS 1.3 preferred
- Never disable SSL verification in any environment:
  ```php
  // FORBIDDEN:
  Http::withOptions(['verify' => false])->post($url, $data);
  curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);

  // Correct:
  Http::withOptions(['verify' => '/path/to/ca-bundle.crt'])->post($url, $data);
  ```
- Pin certificates for payment gateway connections where the gateway provides a pinning bundle
- `APP_ENV=production` must enforce TLS; never allow HTTP endpoints for payment APIs
- Internal service-to-service calls within PCI scope must also use TLS

## HSM / Key Management Patterns

- Encryption keys must come from config only: `config('payment.encryption_key')`
- Never hardcode keys, IVs, or secrets in source code — not even in comments
- Key rotation: code must support key versioning (key ID stored alongside ciphertext)
- HSM operations (PIN translation, MAC generation): use dedicated HSM client library — never implement cryptographic primitives
- Key derivation: use PBKDF2 or bcrypt — never MD5 or SHA1 for key material
- Working keys must be double-length 3DES or AES-128 minimum; AES-256 preferred
- Key loading into HSM: out-of-band, never via application deployment pipeline

```php
// Correct: key from config
$key = config('payment.data_key');
$encrypted = openssl_encrypt($data, 'aes-256-gcm', $key, 0, $iv, $tag);

// FORBIDDEN: hardcoded key
$key = '0123456789ABCDEF0123456789ABCDEF';
```

## Payment Table Access Controls

- Payment tables (`transactions`, `cards`, `settlements`, `payment_logs`, `audit_logs`) must have row-level or application-level access control
- No wildcard `SELECT *` on payment tables — select only needed columns
- Service accounts used by the application must have minimum privilege:
  - Application DB user: SELECT, INSERT, UPDATE on required tables only
  - No DELETE privilege on audit tables
  - No DDL privilege in production
- Migrations touching payment tables require PCI change review before deployment
- Direct database access to production payment tables must be logged and require MFA

## Audit Logging Requirements

All of the following events must generate an immutable audit log entry:

- Payment attempt (approval and decline)
- Refund request and completion
- Void request
- Settlement batch open/close
- Card tokenization / detokenization
- Key rotation events
- User privilege changes on payment systems
- Failed authentication attempts on payment APIs
- Any administrative action on payment data

Audit log entry minimum fields:
```php
[
    'event'          => 'payment.approved',
    'actor_id'       => $user->id,         // who performed the action
    'actor_ip'       => $request->ip(),
    'resource_type'  => 'transaction',
    'resource_id'    => $transaction->id,
    'masked_pan'     => maskPan($pan),      // never raw PAN
    'amount'         => $amount,
    'currency'       => $currency,
    'occurred_at'    => now()->toIso8601String(),
]
```

Audit logs must be:
- Append-only (no UPDATE/DELETE on audit tables)
- Tamper-evident (hash chaining or immutable storage)
- Retained per PCI DSS 10.7 requirements
- Accessible to security team within 24 hours of a request
