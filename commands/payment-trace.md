---
name: payment-trace
description: Trace a payment flow through the codebase from HTTP request to socket send
allowed_tools: ["Bash", "Read", "Grep", "Glob"]
---

# /payment-trace

## Goal
Follow a payment request from the HTTP entry point through every layer to the payment host connection. Produces a full trace map for debugging, onboarding, or architecture review.

## Steps
1. Find the entry point:
   - Search `routes/api.php` or `cmd/*/main.go` for the payment route
2. Follow the chain:
   - Route → Controller → FormRequest (validation) → Service → Repository / HostClient
3. For each hop, note:
   - File path and line number
   - What the layer does (validate, transform, persist, send)
   - What it returns or emits
4. Identify the payment host connection:
   - TCP socket client
   - HTTP client to external API
   - Queue job dispatched
5. Note any async hops (jobs, events, listeners)
6. Check for idempotency handling in the flow
7. Check for timeout handling and what happens on timeout

## Output
```
PAYMENT TRACE: POST /api/v1/payments
────────────────────────────────────────────────────────────────────
1. routes/api.php:45
   Route: POST /api/v1/payments → PaymentController@store
   Middleware: auth:api, throttle:payment

2. app/Http/Controllers/PaymentController.php:28
   Validates via ProcessPaymentRequest::authorize() + rules()
   Calls: PaymentService::process(PaymentDto)

3. app/Http/Requests/ProcessPaymentRequest.php:22
   authorize(): checks merchant ownership
   rules(): validates amount, currency, card_token, merchant_id

4. app/Services/PaymentService.php:35
   Checks idempotency (IdempotencyService::wrap())
   Calls: PaymentHostClient::authorise(PaymentDto)
   On timeout: marks transaction pending, dispatches ReversalCheckJob

5. app/Services/PaymentHostClient.php:55
   Builds HTTP request to https://payment-host.internal/authorise
   Sets 30s timeout, TLS verify=true
   Parses response_code from JSON body

6. app/Repositories/TransactionRepository.php:44
   INSERT INTO transactions with status from host response
   Returns: Transaction model

7. [ASYNC] app/Jobs/SendWebhookJob.php
   Triggered by PaymentAuthorised event
   Delivers webhook to merchant callback URL

────────────────────────────────────────────────────────────────────
Idempotency: YES — checked at step 4, keyed on Idempotency-Key header
Timeout handling: YES — pending status, ReversalCheckJob dispatched
TLS: YES — CURLOPT_SSL_VERIFYPEER = true
────────────────────────────────────────────────────────────────────
```
