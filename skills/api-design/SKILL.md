---
name: api-design
description: RESTful API design for payment services — URL structure, HTTP method conventions, idempotency key handling, pagination envelope, request and response schemas with standard error codes, webhook signature format, and OpenAPI annotations.
origin: fintech-stack
---

# API Design

Payment APIs have stronger requirements than typical REST APIs: every state-mutating endpoint must accept an idempotency key, host timeouts return `202 Pending` rather than an error, and card numbers never appear in request bodies — only tokenised references.

## When to Activate

- Developer asks to "design an API", "add an endpoint", or "define the contract"
- Creating a new payment flow, webhook, or integration surface
- Reviewing or improving existing API design

---

## URL Structure

```
/api/v1/{resource}
/api/v1/{resource}/{id}
/api/v1/{resource}/{id}/{sub-resource}
```

- Plural nouns: `/payments`, `/transactions`, `/merchants`
- No verbs in paths — use HTTP methods instead
- Nest max 2 levels deep
- Version prefix is mandatory: `/api/v1/`, `/api/v2/`

---

## HTTP Method Conventions

| Method | Path | Meaning |
|--------|------|---------|
| POST | /api/v1/payments | Initiate a payment |
| GET | /api/v1/payments/{id} | Get payment status |
| POST | /api/v1/payments/{id}/refund | Initiate refund |
| POST | /api/v1/payments/{id}/void | Void a payment |
| GET | /api/v1/transactions | List transactions (paginated) |
| POST | /api/v1/webhooks/verify | Verify webhook signature |

---

## Idempotency

All state-mutating endpoints must accept an `Idempotency-Key` header. Store the key + result and return the cached result on duplicate requests. Key format: UUIDv4, 36 chars. TTL: 24 hours minimum.

```php
// Laravel: extract and validate idempotency key
$key = $request->header('Idempotency-Key');
if (!$key || !Str::isUuid($key)) {
    return response()->json(['error' => ['code' => 'MISSING_IDEMPOTENCY_KEY']], 422);
}
```

---

## Pagination Envelope

```json
GET /api/v1/transactions?page=2&per_page=25&merchant_id=MERCH001&from=2024-01-01&to=2024-01-31

{
  "data": [...],
  "meta": {
    "current_page": 2,
    "per_page":     25,
    "total":        482,
    "last_page":    20
  },
  "links": {
    "first": "/api/v1/transactions?page=1",
    "prev":  "/api/v1/transactions?page=1",
    "next":  "/api/v1/transactions?page=3",
    "last":  "/api/v1/transactions?page=20"
  }
}
```

---

## Request Format

```json
POST /api/v1/payments
Headers:
  Content-Type:    application/json
  Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
  Authorization:   Bearer {token}

{
  "amount":      1000,
  "currency":    "MYR",
  "card_token":  "tok_test_4111",
  "merchant_id": "MERCH001",
  "order_ref":   "ORDER-20240115-001",
  "metadata": {
    "customer_id": "CUST-999"
  }
}
```

- `amount` is always in minor units (cents): `1000` = MYR 10.00
- `currency` is ISO 4217 three-letter code
- Never accept raw card numbers — require a tokenised card reference

---

## Response Format

**Success (201 Created):**
```json
{
  "data": {
    "id":          "pay_01HXYZ",
    "status":      "approved",
    "amount":      1000,
    "currency":    "MYR",
    "auth_code":   "ABC123",
    "merchant_id": "MERCH001",
    "created_at":  "2024-01-15T10:30:00Z"
  }
}
```

**Error:**
```json
{
  "error": {
    "code":       "CARD_DECLINED",
    "message":    "Transaction declined by issuer",
    "detail":     "Insufficient funds",
    "request_id": "req_01HXYZ"
  }
}
```

**Standard error codes:**

| Code | HTTP |
|------|------|
| `CARD_DECLINED` | 422 |
| `INVALID_CARD` | 422 |
| `IDEMPOTENCY_CONFLICT` | 409 |
| `AMOUNT_INVALID` | 422 |
| `MERCHANT_NOT_FOUND` | 404 |
| `HOST_TIMEOUT` | 202 (pending state — not an error) |
| `AUTHENTICATION_FAILED` | 401 |
| `RATE_LIMIT_EXCEEDED` | 429 |

---

## Webhook Signature

```
POST {merchant_callback_url}
Headers:
  X-Webhook-Signature: sha256={hmac_hex}
  X-Webhook-Timestamp: 1705312200
  Content-Type: application/json
```

Signature: `HMAC-SHA256(secret, timestamp + "." + raw_body)`

---

## OpenAPI Annotations (PHP / Laravel)

```php
/**
 * @OA\Post(
 *   path="/api/v1/payments",
 *   summary="Initiate a payment",
 *   tags={"Payments"},
 *   security={{"BearerAuth":{}}},
 *   @OA\Parameter(name="Idempotency-Key", in="header", required=true,
 *     @OA\Schema(type="string", format="uuid")),
 *   @OA\RequestBody(required=true,
 *     @OA\JsonContent(ref="#/components/schemas/PaymentRequest")),
 *   @OA\Response(response=201, description="Payment approved",
 *     @OA\JsonContent(ref="#/components/schemas/PaymentResponse")),
 *   @OA\Response(response=422, description="Declined",
 *     @OA\JsonContent(ref="#/components/schemas/ErrorResponse"))
 * )
 */
```

---

## Best Practices

- **`HOST_TIMEOUT` returns `202`, not `5xx`** — a timeout is an unknown outcome, not a confirmed failure; `202 Pending` lets the caller poll for the result
- **Idempotency key required, not optional** — return `422 MISSING_IDEMPOTENCY_KEY` if absent; don't silently process without it
- **Amount in minor units only** — `1000` not `10.00`; eliminates floating-point rounding errors across currency pairs
- **Never accept raw PAN in request body** — only `card_token`; raw PAN in a request brings the endpoint into PCI scope
- **`request_id` in every error response** — enables support to look up the full request log without the merchant sharing sensitive data
- **Webhook timestamp in signature** — prevents replay attacks; reject webhooks with timestamps older than 5 minutes
