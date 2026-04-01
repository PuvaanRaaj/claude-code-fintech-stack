---
name: card-tokenisation
description: Card tokenisation patterns — token vault design, network tokenisation (Visa Token Service / Mastercard MDES), token lifecycle management, token requestor registration, and PAN-to-token mapping with PCI scope reduction.
origin: fintech-stack
---

# Card Tokenisation Patterns

Tokenisation replaces a cardholder's PAN with a surrogate value (the token) that is useless outside the context it was issued for. Done correctly, it removes the PAN from every system except the token vault, collapsing PCI DSS scope from SAQ D to SAQ A or SAQ A-EP for most merchant environments.

## When to Activate

- Designing or reviewing a token vault schema or API
- Implementing Visa Token Service (VTS) or Mastercard MDES network tokenisation
- Managing token lifecycle: provisioning, update via Account Updater, suspension, or deletion
- Ensuring PAN never touches application storage, logs, or transit outside the vault
- Registering as a Token Requestor with a card scheme
- Writing Go token resolution middleware or a PHP/Laravel token service

---

## Why Tokenisation Reduces PCI Scope

A token is a random value with no mathematical relationship to the PAN it replaces. A token scoped to a single merchant (a payment token) is worthless if stolen — it cannot be used at any other merchant, cannot be reversed into a PAN without the vault, and has a defined expiry.

```
Without tokenisation:
  Application DB ──stores──▶ PAN (16 digits, full PCI scope)

With tokenisation:
  Token Vault (PCI DSS CDE) ──holds──▶ PAN → Token mapping (encrypted)
  Application DB ──stores──▶ Token only (out of PCI scope)
```

Every system that only ever sees the token — queues, logs, data warehouses, analytics — is out of PCI scope. Only the vault and the authorisation path that resolves the token back to a PAN (or passes it directly to the acquirer) remain in scope.

---

## Token Vault Database Design

```sql
-- tokens table: the vault core
CREATE TABLE tokens (
    id              BIGSERIAL PRIMARY KEY,
    token           CHAR(16) NOT NULL UNIQUE,          -- Random 16-digit numeric string
    pan_ciphertext  BYTEA NOT NULL,                    -- PAN encrypted with AES-256-GCM
    pan_key_version INT NOT NULL,                      -- Key rotation reference
    last_four       CHAR(4) NOT NULL,                  -- Display only — never use for auth
    expiry_month    CHAR(2) NOT NULL,
    expiry_year     CHAR(4) NOT NULL,
    card_brand      VARCHAR(20) NOT NULL,              -- visa, mastercard, amex
    status          VARCHAR(20) NOT NULL DEFAULT 'active', -- active, suspended, deleted
    token_scope     VARCHAR(64) NOT NULL,              -- merchant_id or 'network'
    requestor_id    VARCHAR(64),                       -- VTS/MDES token requestor ID
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ
);

CREATE INDEX idx_tokens_scope ON tokens (token_scope, status);
```

Never store the PAN in plaintext. Use AES-256-GCM with a key stored in a KMS (AWS KMS, GCP Cloud KMS, HashiCorp Vault). `last_four` is safe to store in cleartext for display purposes — it cannot be used to reconstruct the PAN.

---

## PHP/Laravel — Token Service

```php
<?php

namespace App\Services\Vault;

use App\Models\Token;
use Illuminate\Support\Str;
use App\Encryption\PanEncryptor;

final class TokenService
{
    public function __construct(private readonly PanEncryptor $encryptor) {}

    /**
     * Provision a new token for the given PAN and merchant scope.
     * PAN is encrypted immediately; the caller receives only the token.
     */
    public function provision(string $pan, string $merchantId, string $expiry): string
    {
        // Validate Luhn before storing — reject garbage early
        if (! $this->passesLuhn($pan)) {
            throw new \InvalidArgumentException('Invalid PAN (Luhn check failed)');
        }

        [$ciphertext, $keyVersion] = $this->encryptor->encrypt($pan);

        $token = Token::create([
            'token'          => $this->generateToken(),
            'pan_ciphertext' => $ciphertext,
            'pan_key_version'=> $keyVersion,
            'last_four'      => substr($pan, -4),
            'expiry_month'   => substr($expiry, 0, 2),
            'expiry_year'    => substr($expiry, 2, 4),
            'card_brand'     => $this->detectBrand($pan),
            'token_scope'    => $merchantId,
            'status'         => 'active',
        ]);

        // Do not return or log the PAN beyond this point
        return $token->token;
    }

    public function resolve(string $token, string $merchantId): string
    {
        $record = Token::where('token', $token)
            ->where('token_scope', $merchantId)
            ->where('status', 'active')
            ->firstOrFail();

        return $this->encryptor->decrypt($record->pan_ciphertext, $record->pan_key_version);
    }

    public function suspend(string $token): void
    {
        Token::where('token', $token)->update(['status' => 'suspended']);
    }

    public function delete(string $token): void
    {
        // Soft delete with wipe of encrypted PAN — retain last_four for dispute history
        Token::where('token', $token)->update([
            'status'         => 'deleted',
            'pan_ciphertext' => null,
        ]);
    }

    private function generateToken(): string
    {
        // 16-digit random numeric token — passes Luhn for compatibility with legacy validators
        do {
            $token = str_pad((string) random_int(0, 9999999999999999), 16, '0', STR_PAD_LEFT);
        } while (Token::where('token', $token)->exists());

        return $token;
    }

    private function passesLuhn(string $pan): bool
    {
        $sum    = 0;
        $parity = strlen($pan) % 2;
        for ($i = 0; $i < strlen($pan); $i++) {
            $digit = (int) $pan[$i];
            if ($i % 2 === $parity) {
                $digit *= 2;
                if ($digit > 9) {
                    $digit -= 9;
                }
            }
            $sum += $digit;
        }
        return $sum % 10 === 0;
    }

    private function detectBrand(string $pan): string
    {
        return match(true) {
            str_starts_with($pan, '4')              => 'visa',
            preg_match('/^5[1-5]/', $pan) === 1     => 'mastercard',
            preg_match('/^3[47]/', $pan) === 1      => 'amex',
            default                                 => 'unknown',
        };
    }
}
```

---

## Network Tokenisation: VTS and MDES

Network tokens are issued by the card scheme (Visa Token Service or Mastercard MDES) rather than your vault. They carry a cryptogram (TAVV/DSRP) that provides stronger fraud protection and benefit from Account Updater automatically.

```
Token Requestor (your system)
        │
        │  1. Token Provisioning Request (TPR) ──────────────────▶ VTS / MDES
        │                                                                │
        │                                              2. Token issued ◀┘
        │
        │  3. Store network token (not PAN) ──▶ Token Vault
        │
        │  [At transaction time]
        │
        │  4. Cryptogram Request (TAVV) ─────────────────────────▶ VTS / MDES
        │  5. TAVV returned ◀────────────────────────────────────── VTS / MDES
        │
        │  6. Authorisation with (token + TAVV + ECI) ───────────▶ Acquirer
```

To register as a Token Requestor with Visa, you need a Token Requestor ID (TRID) and a signed certificate from Visa Developer. Mastercard MDES follows an equivalent onboarding process via Mastercard Developers.

---

## Go — Token Resolution Middleware

```go
package middleware

import (
    "context"
    "net/http"

    "github.com/your-org/payments/vault"
)

type contextKey string

const resolvedPANKey contextKey = "resolved_pan"

// TokenResolution resolves a payment token to a PAN for downstream handlers
// that require direct PAN access (e.g. the authorisation path to the acquirer).
// All other handlers should use the token directly.
func TokenResolution(vaultClient *vault.Client) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            token      := r.Header.Get("X-Payment-Token")
            merchantID := r.Header.Get("X-Merchant-ID")

            if token == "" || merchantID == "" {
                http.Error(w, "missing token or merchant", http.StatusBadRequest)
                return
            }

            pan, err := vaultClient.Resolve(r.Context(), token, merchantID)
            if err != nil {
                http.Error(w, "token resolution failed", http.StatusUnauthorized)
                return
            }

            // Store PAN in context — never in headers, logs, or response body
            ctx := context.WithValue(r.Context(), resolvedPANKey, pan)
            next.ServeHTTP(w, r.WithContext(ctx))
        })
    }
}

func PANFromContext(ctx context.Context) (string, bool) {
    pan, ok := ctx.Value(resolvedPANKey).(string)
    return pan, ok
}
```

---

## Token Lifecycle Management

| Event | Trigger | Action |
|-------|---------|--------|
| Provisioning | New card saved, checkout, wallet add | Create token; encrypt PAN; return token to caller |
| Account Updater | Card reissued by issuer (new expiry or new PAN) | VTS/MDES pushes updated PAN or expiry via webhook; re-encrypt and update vault record |
| Suspension | Fraud flag, merchant request | Set `status = suspended`; token cannot be resolved until reinstated |
| Deletion | Cardholder request (GDPR/PDPA), card closure | Wipe `pan_ciphertext`; set `status = deleted`; retain `last_four` for dispute history |
| Expiry | Token `expires_at` reached | Treat as deleted; prompt cardholder to re-add card |

---

## Best Practices

- **Never store PAN anywhere outside the encrypted vault column** — not in application logs, not in queues, not in error messages, not in API responses
- **Scope tokens to a merchant or context** — a token issued for Merchant A must not be resolvable by Merchant B; enforce scope check in every resolution call
- **Prefer network tokens for recurring payments** — VTS and MDES tokens survive card reissue via Account Updater; your own vault tokens become stale when the issuer reissues the card
- **Rotate encryption keys without re-issuing tokens** — use `pan_key_version` to track which KEK was used; re-encrypt in background on key rotation rather than forcing cardholder to re-add their card
- **Use test card numbers in all development fixtures** — `4111111111111111` (Visa test) is safe to use; never commit real PANs even in test data
- **Log token and `last_four` only** — when debugging payment flows, `token=4242...1234 last_four=1234` is sufficient; the PAN must never appear in any log line
