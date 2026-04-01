---
name: webhook-patterns
description: Secure webhook handling for payment systems — signature verification, idempotent processing, retry with exponential backoff, and dead-letter queue patterns for both inbound and outbound webhooks.
origin: fintech-stack
---

# Webhook Patterns

Webhooks in payment systems carry financial events — failed deliveries, duplicate processing, or forged payloads have direct money consequences. This skill covers the full lifecycle: verifying what arrives, processing it exactly once, and delivering outbound notifications reliably.

## When to Activate

- Adding a new inbound webhook endpoint from a payment provider or scheme
- Implementing outbound merchant callback/notification delivery
- Debugging missed, duplicate, or out-of-order webhook deliveries
- Reviewing existing webhook handlers for security gaps (missing signature check, synchronous processing)

---

## Inbound Webhook Security

### Signature Verification

Verify the HMAC signature **before** any body parsing. Never trust an unverified payload.

```php
<?php declare(strict_types=1);

namespace App\Services\Webhook;

final class SignatureVerifier
{
    public function __construct(
        private readonly string $secret,
        private readonly int    $toleranceSeconds = 300,
    ) {}

    public function verify(string $rawBody, ?string $signature, ?string $timestamp): bool
    {
        if (! $signature || ! $timestamp) {
            return false;
        }

        // Reject stale timestamps — replay attack prevention
        if (abs(time() - (int) $timestamp) > $this->toleranceSeconds) {
            return false;
        }

        $expected = 'sha256=' . hash_hmac('sha256', $timestamp . '.' . $rawBody, $this->secret);

        return hash_equals($expected, $signature);
    }
}
```

```go
func VerifySignature(r *http.Request, secret string) ([]byte, error) {
    body, err := io.ReadAll(r.Body)
    if err != nil {
        return nil, fmt.Errorf("read body: %w", err)
    }

    sig   := r.Header.Get("X-Webhook-Signature")
    tsStr := r.Header.Get("X-Webhook-Timestamp")
    if sig == "" || tsStr == "" {
        return nil, fmt.Errorf("missing signature headers")
    }

    ts, err := strconv.ParseInt(tsStr, 10, 64)
    if err != nil || abs(time.Now().Unix()-ts) > 300 {
        return nil, fmt.Errorf("timestamp out of tolerance")
    }

    mac := hmac.New(sha256.New, []byte(secret))
    fmt.Fprintf(mac, "%d.%s", ts, body)
    expected := "sha256=" + hex.EncodeToString(mac.Sum(nil))

    if !hmac.Equal([]byte(expected), []byte(sig)) {
        return nil, fmt.Errorf("signature mismatch")
    }
    return body, nil
}
```

### Idempotent Controller — Ack Fast, Process Async

```php
final class PaymentProviderWebhookController
{
    public function __invoke(Request $request): Response
    {
        $rawBody   = $request->getContent();
        $signature = $request->header('X-Webhook-Signature');
        $timestamp = $request->header('X-Webhook-Timestamp');

        if (! $this->verifier->verify($rawBody, $signature, $timestamp)) {
            return response('Forbidden', 403);
        }

        // Deduplicate by event ID
        $eventId = $request->header('X-Event-Id') ?? hash('sha256', $rawBody);
        if (cache()->has("webhook:seen:{$eventId}")) {
            return response('', 200); // Already queued — ack and discard
        }

        cache()->put("webhook:seen:{$eventId}", true, now()->addDays(7));
        ProcessWebhookPayload::dispatch($request->json()->all(), $eventId)->onQueue('webhooks');

        return response('', 200); // Never make the provider wait
    }
}
```

---

## Idempotent Job Processor

```php
final class ProcessWebhookPayload implements ShouldQueue
{
    use Queueable;

    public int $tries   = 3;
    public int $backoff = 60;
    public int $timeout = 30;

    public function __construct(
        private readonly array  $payload,
        private readonly string $eventId,
    ) {}

    public function handle(PaymentStatusService $service): void
    {
        $type          = $this->payload['event_type'] ?? 'unknown';
        $transactionId = $this->payload['data']['transaction_id'] ?? null;

        Log::info('webhook.processing', [
            'event_id'       => $this->eventId,
            'event_type'     => $type,
            'transaction_id' => $transactionId,
        ]);

        match ($type) {
            'payment.approved' => $service->markApproved($transactionId, $this->payload),
            'payment.declined' => $service->markDeclined($transactionId, $this->payload),
            'payment.refunded' => $service->markRefunded($transactionId, $this->payload),
            'payment.reversed' => $service->markReversed($transactionId, $this->payload),
            default            => Log::warning('webhook.unknown_type', ['type' => $type]),
        };
    }

    public function failed(\Throwable $e): void
    {
        Log::error('webhook.failed', [
            'event_id' => $this->eventId,
            'error'    => $e->getMessage(),
        ]);
        // Alert on-call — manual review required
    }
}
```

---

## Outbound Webhook Delivery

### Sending with Signature and Retry

```php
final class OutboundWebhookDispatcher
{
    public function dispatch(string $url, string $secret, array $payload): bool
    {
        $timestamp = time();
        $body      = json_encode($payload, JSON_THROW_ON_ERROR);
        $signature = 'sha256=' . hash_hmac('sha256', $timestamp . '.' . $body, $secret);

        $response = Http::timeout(10)
            ->withHeaders([
                'Content-Type'        => 'application/json',
                'X-Webhook-Timestamp' => (string) $timestamp,
                'X-Webhook-Signature' => $signature,
                'X-Event-Id'          => $payload['event_id'],
            ])
            ->retry(3, 1000, fn($e) =>
                $e instanceof ConnectionException
                || ($e instanceof RequestException && $e->response->serverError())
            )
            ->post($url, $payload);

        Log::info('webhook.outbound', [
            'url'         => $url,
            'event_id'    => $payload['event_id'],
            'status_code' => $response->status(),
        ]);

        return $response->successful();
    }
}
```

### Exponential Backoff Schedule

```php
// Job retry schedule for outbound delivery
public function backoff(): array
{
    return [30, 120, 600, 3600, 86400]; // 30s, 2min, 10min, 1hr, 24hr
}

public int $maxExceptions = 5;
```

```go
// Go: exponential backoff
func (d *Dispatcher) sendWithBackoff(ctx context.Context, url string, payload []byte, maxAttempts int) error {
    var lastErr error
    for attempt := 0; attempt < maxAttempts; attempt++ {
        if err := d.send(ctx, url, payload); err == nil {
            return nil
        } else {
            lastErr = err
        }
        backoff := time.Duration(1<<attempt) * time.Second
        if backoff > 24*time.Hour {
            backoff = 24 * time.Hour
        }
        select {
        case <-ctx.Done():
            return ctx.Err()
        case <-time.After(backoff):
        }
    }
    return fmt.Errorf("delivery failed after %d attempts: %w", maxAttempts, lastErr)
}
```

---

## Best Practices

- **Verify signature before parsing body** — forged payloads are a real attack vector against payment hooks
- **Return 200 immediately, process async** — never make the provider wait; timeouts cause retries and duplicates
- **Deduplicate by event ID** — payment providers retry on any non-2xx response; your handler will see duplicates
- **5-minute timestamp window** — tight enough to block replays, wide enough for clock skew
- **Do not retry on 4xx responses** — your endpoint rejected the payload; retrying won't fix it
- **Never log the full webhook body** — it may contain card tokens, amounts, or PII
- **Alert when dead-letter queue depth rises** — silent failures in webhook delivery = merchants not notified of payment outcomes
