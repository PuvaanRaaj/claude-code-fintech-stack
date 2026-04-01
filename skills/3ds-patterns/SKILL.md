---
name: 3ds-patterns
description: 3DS2 authentication patterns for payment services — frictionless vs challenge flow, ACS/DS communication, authentication result codes, EMV 3DS data elements, and fallback to 3DS1.
origin: fintech-stack
---

# 3DS2 Patterns

3DS2 (EMV 3-D Secure) is the authentication layer that sits between the merchant and the card issuer, providing risk-based authentication that eliminates most friction while maintaining liability shift. Getting the message flow wrong produces silent authentication failures that surface only as RC 82 or a dispute loss months later.

## When to Activate

- Implementing or debugging a 3DS2 authentication flow in a payment service
- Handling AReq/ARes/CReq/CRes message construction or parsing
- Deciding between frictionless and challenge flow based on ARes risk score
- Processing authentication result codes (Y, N, A, U, C) and mapping them to authorisation decisions
- Adding EMV 3DS data elements (`cavv`, `eci`, `dsTransId`, `acsTransId`) to an ISO 8583 or API request
- Implementing fallback to 3DS1 when 3DS2 is unavailable

---

## AReq/ARes/CReq/CRes Message Flow

```
Cardholder Browser / SDK
        │
        │  1. AuthenticationRequest (AReq) ──────────────────────────────▶ DS (Directory Server)
        │                                                                       │
        │                                                             2. AReq forwarded ──▶ ACS
        │                                                                       │
        │  3. AuthenticationResponse (ARes) ◀────────────────────────────── DS
        │
        │  [If transStatus = C — challenge required]
        │
        │  4. ChallengeRequest (CReq) ─────────────────────────────────────▶ ACS
        │  5. ChallengeResponse (CRes) ◀──────────────────────────────────── ACS
        │
        │  6. Results Request (RReq) / Results Response (RRes) — 3DS Server to DS
```

The 3DS Server (your backend) sends AReq, receives ARes, then drives the challenge iframe/SDK if needed. The DS routes everything — your server never talks directly to the ACS except through the DS relay.

---

## Frictionless Flow vs Challenge Flow

| Condition | Flow | Description |
|-----------|------|-------------|
| ARes `transStatus` = `Y` or `A` | Frictionless | ACS authenticated without cardholder interaction |
| ARes `transStatus` = `C` | Challenge | ACS requires cardholder to complete a challenge |
| ARes `transStatus` = `N` | Not authenticated | Do not proceed to authorisation |
| ARes `transStatus` = `U` | Unavailable | ACS could not authenticate; retry or proceed at own risk |
| ARes `transStatus` = `R` | Rejected | ACS rejected the transaction; do not attempt authorisation |

Frictionless: collect `cavv`, `eci`, `dsTransId` from ARes and pass them into the authorisation request immediately.

Challenge: redirect the cardholder to the ACS challenge URL (from `acsURL` in ARes), wait for CRes callback, then collect `cavv` and `eci` from the final RReq.

---

## PHP/Laravel — Initiating 3DS2

```php
<?php

namespace App\Services\ThreeDS;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

final class ThreeDSService
{
    public function __construct(
        private readonly string $threeDsServerUrl,
        private readonly string $merchantId,
        private readonly string $acquirerBin,
    ) {}

    public function initiateAuthentication(array $transaction): AuthenticationResult
    {
        $aReq = [
            'threeDSRequestorID'       => $this->merchantId,
            'threeDSRequestorName'     => config('app.name'),
            'threeDSRequestorURL'      => config('app.url'),
            'acquirerBIN'              => $this->acquirerBin,
            'acquirerMerchantID'       => $this->merchantId,
            'cardExpiryDate'           => $transaction['card_expiry'],   // YYMM
            'acctNumber'               => $transaction['token'],         // Use token — never raw PAN
            'purchaseAmount'           => $transaction['amount_minor'],  // Minor units
            'purchaseCurrency'         => $transaction['currency_code'], // ISO 4217 numeric
            'purchaseDate'             => now()->format('YmdHis'),
            'transType'                => '01', // Goods/service purchase
            'messageCategory'          => '01', // Payment authentication
            'deviceChannel'            => '02', // Browser
            'browserInfo'              => $transaction['browser_info'],
            'threeDSServerTransID'     => Str::uuid()->toString(),
            'messageVersion'           => '2.2.0',
        ];

        $response = Http::timeout(10)
            ->post("{$this->threeDsServerUrl}/authentication", $aReq)
            ->throw()
            ->json();

        return AuthenticationResult::fromARes($response);
    }
}
```

---

## PHP/Laravel — Handling the Challenge Callback

```php
<?php

namespace App\Http\Controllers;

use App\Services\ThreeDS\ThreeDSService;
use Illuminate\Http\Request;

final class ThreeDSChallengeController extends Controller
{
    public function callback(Request $request, ThreeDSService $service): \Illuminate\Http\JsonResponse
    {
        // CRes arrives as a base64url-encoded JSON body posted by the ACS
        $cRes = json_decode(base64_decode(strtr($request->input('cres'), '-_', '+/')), true);

        if (! isset($cRes['threeDSServerTransID'], $cRes['transStatus'])) {
            return response()->json(['error' => 'invalid_cres'], 400);
        }

        $result = $service->processChallenge($cRes['threeDSServerTransID'], $cRes['transStatus']);

        if ($result->isAuthenticated()) {
            return response()->json([
                'status'    => 'authenticated',
                'cavv'      => $result->cavv,
                'eci'       => $result->eci,
                'dsTransId' => $result->dsTransId,
            ]);
        }

        return response()->json(['status' => 'not_authenticated', 'reason' => $result->transStatus], 422);
    }
}
```

---

## Go — 3DS2 Client with Context/Timeout

```go
package threeds

import (
    "bytes"
    "context"
    "encoding/json"
    "fmt"
    "net/http"
    "time"
)

type Client struct {
    baseURL    string
    httpClient *http.Client
}

func NewClient(baseURL string) *Client {
    return &Client{
        baseURL: baseURL,
        httpClient: &http.Client{
            Timeout: 10 * time.Second,
        },
    }
}

type AReq struct {
    ThreeDSServerTransID string `json:"threeDSServerTransID"`
    AcctNumber           string `json:"acctNumber"`   // Token — not PAN
    PurchaseAmount       string `json:"purchaseAmount"`
    PurchaseCurrency     string `json:"purchaseCurrency"`
    PurchaseDate         string `json:"purchaseDate"` // YYYYMMDDHHmmss
    MessageVersion       string `json:"messageVersion"`
    DeviceChannel        string `json:"deviceChannel"`
    MessageCategory      string `json:"messageCategory"`
}

type ARes struct {
    ThreeDSServerTransID string `json:"threeDSServerTransID"`
    ACSTransID           string `json:"acsTransID"`
    DSTransID            string `json:"dsTransID"`
    TransStatus          string `json:"transStatus"` // Y, N, A, U, C, R
    CAVV                 string `json:"authenticationValue"`
    ECI                  string `json:"eci"`
    ACSUrl               string `json:"acsURL"`
}

func (c *Client) Authenticate(ctx context.Context, req AReq) (*ARes, error) {
    body, err := json.Marshal(req)
    if err != nil {
        return nil, fmt.Errorf("marshal areq: %w", err)
    }

    httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/authentication", bytes.NewReader(body))
    if err != nil {
        return nil, fmt.Errorf("build request: %w", err)
    }
    httpReq.Header.Set("Content-Type", "application/json; charset=utf-8")

    resp, err := c.httpClient.Do(httpReq)
    if err != nil {
        return nil, fmt.Errorf("send areq: %w", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        return nil, fmt.Errorf("3ds server returned %d", resp.StatusCode)
    }

    var aRes ARes
    if err := json.NewDecoder(resp.Body).Decode(&aRes); err != nil {
        return nil, fmt.Errorf("decode ares: %w", err)
    }
    return &aRes, nil
}
```

---

## Authentication Result Codes

| Code | Meaning | Authorisation Decision |
|------|---------|----------------------|
| `Y`  | Fully authenticated — cryptographic proof | Proceed; liability shifts to issuer |
| `A`  | Attempted — ACS tried but cardholder not enrolled | Proceed with `eci=06`; partial liability shift |
| `N`  | Not authenticated | Do not authorise; return decline to merchant |
| `U`  | Unavailable — ACS or DS could not complete | Proceed at acquirer/merchant risk; `eci=07` |
| `C`  | Challenge required | Present challenge flow before proceeding |
| `R`  | Rejected by ACS | Do not attempt authorisation |

---

## EMV 3DS Data Elements

These values must be included in the authorisation request sent to the issuer:

| Field | Name | Notes |
|-------|------|-------|
| `cavv` | Cardholder Authentication Verification Value | Base64-encoded; from ARes (frictionless) or RReq (challenge) |
| `eci` | Electronic Commerce Indicator | `05` = fully authenticated; `06` = attempted; `07` = unavailable |
| `dsTransId` | Directory Server Transaction ID | UUID from DS; echoed to issuer for dispute resolution |
| `acsTransId` | ACS Transaction ID | UUID from ACS; included in dispute records |

```php
// Mapping 3DS result into an authorisation request
$authRequest = [
    'amount'        => $transaction->amountMinor(),
    'currency'      => $transaction->currencyCode(),
    'token'         => $transaction->token(),
    'cavv'          => $authResult->cavv,
    'eci'           => $authResult->eci,
    'ds_trans_id'   => $authResult->dsTransId,
    'acs_trans_id'  => $authResult->acsTransId,
    'three_ds_version' => '2.2.0',
];
```

---

## Fallback to 3DS1

Fall back to 3DS1 when the ACS or DS does not support 3DS2 (error code `305` from the DS, or `transStatusReason` = `20` in the ARes).

```php
public function authenticate(Transaction $txn): AuthenticationResult
{
    try {
        return $this->threeDS2->initiateAuthentication($txn->toArray());
    } catch (ThreeDSVersionNotSupportedException $e) {
        // DS returned 305 (Requested version not supported) — fall back to 3DS1 PAReq/PARes
        return $this->threeDS1->authenticate($txn);
    }
}
```

3DS1 uses a PAReq (Base64-encoded XML) posted via cardholder browser to the ACS URL. The ACS returns a PARes. The merchant decodes and verifies the PARes signature before proceeding to authorisation.

---

## Best Practices

- **Always use a token in `acctNumber`** — the AReq field accepts a token in place of PAN; never send raw PAN over a 3DS2 message
- **Set a hard timeout of 10 seconds on AReq** — DS and ACS SLAs are 8–10 seconds; beyond that, treat as `U` and proceed at acquirer risk
- **Log `dsTransId` and `acsTransId` for every transaction** — these are the primary keys for dispute resolution and chargeback defence
- **Check `transStatusReason`** — a `transStatus` of `U` with `transStatusReason` of `20` means 3DS2 is not supported; fall back to 3DS1 rather than retrying
- **ECI drives liability** — `eci=05` gives full liability shift; `eci=06` gives partial shift; `eci=07` gives no shift; map these correctly or you absorb fraud costs
- **Never proceed on `transStatus=N` or `transStatus=R`** — these are hard declines from the issuer; presenting them to authorisation wastes the authorisation attempt and risks flagging the merchant
