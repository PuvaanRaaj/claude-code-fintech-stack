---
name: payment-testing
description: Payment-specific testing patterns — test card table by scenario, PHP Http::fake() for host mocking, Go httptest.NewServer table-driven tests, idempotency verification with Http::assertSentCount, and reversal flow testing with Http::sequence().
origin: fintech-stack
---

# Payment Testing

Payment code has failure modes that only appear in production: host timeouts that leave transactions in an unknown state, duplicate requests from retrying clients, and reversals that must fire even when the original outcome is unclear. These patterns cover all of them without hitting a live host.

## When to Activate

- Writing tests for payment processing, reversal, or settlement flows
- Mocking payment host responses (approve, decline, timeout)
- Testing idempotency or retry behaviour
- Developer asks "how do I test a declined payment?" or "how do I test timeout?"

---

## Test Card Numbers by Scenario

| Scenario | PAN | Notes |
|----------|-----|-------|
| Visa approved | 4111111111111111 | Standard approval |
| Visa declined (insufficient funds) | 4000000000000002 | Response code 51 |
| Visa declined (do not honour) | 4000000000000069 | Response code 05 |
| Visa 3DS required | 4000000000003220 | Triggers 3DS challenge |
| Mastercard approved | 5555555555554444 | Standard approval |
| Mastercard declined | 5200828282828210 | Response code 51 |
| Amex approved | 378282246310005 | 15-digit PAN |
| Expired card | 4111111111111111 | Use past expiry date |

Never use real card numbers in tests. Fail the test suite if a real PAN pattern is detected.

---

## PHP / Laravel — Mocking the Payment Host

```php
<?php declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Services\PaymentHostClient;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class PaymentHostClientTest extends TestCase
{
    public function test_approved_response_returns_approved_status(): void
    {
        Http::fake([
            'payment-host.internal/authorise' => Http::response([
                'response_code' => '00',
                'auth_code'     => 'XYZ789',
                'stan'          => '000001',
            ], 200),
        ]);

        $client = app(PaymentHostClient::class);
        $result = $client->authorise([
            'amount'   => 1000,
            'currency' => 'MYR',
            'pan'      => '4111111111111111', // test card
        ]);

        $this->assertTrue($result->isApproved());
        $this->assertEquals('XYZ789', $result->authCode);
        Http::assertSent(fn($req) => $req->url() === 'https://payment-host.internal/authorise');
    }

    public function test_declined_response_51_returns_declined_status(): void
    {
        Http::fake([
            'payment-host.internal/authorise' => Http::response(['response_code' => '51'], 200),
        ]);

        $result = app(PaymentHostClient::class)->authorise([
            'amount'   => 1000,
            'currency' => 'MYR',
            'pan'      => '4000000000000002', // test: insufficient funds
        ]);

        $this->assertFalse($result->isApproved());
        $this->assertEquals('51', $result->responseCode);
    }

    public function test_host_timeout_throws_timeout_exception(): void
    {
        Http::fake([
            'payment-host.internal/authorise' => Http::response(null, 504),
        ]);

        $this->expectException(\App\Exceptions\PaymentHostTimeoutException::class);
        app(PaymentHostClient::class)->authorise([
            'amount' => 1000, 'currency' => 'MYR', 'pan' => '4111111111111111',
        ]);
    }
}
```

---

## Go — Table-Driven Tests with httptest

```go
package payment_test

import (
    "context"
    "net/http"
    "net/http/httptest"
    "testing"

    "github.com/yourorg/payment"
)

func TestHostClient_Authorise(t *testing.T) {
    tests := []struct {
        name       string
        statusCode int
        body       string
        wantCode   string
        wantErr    bool
    }{
        {"approved",          200, `{"response_code":"00","auth_code":"ABC"}`, "00", false},
        {"declined 51",       200, `{"response_code":"51"}`,                   "51", false},
        {"host timeout",      504, "",                                          "",   true},
        {"connection refused", 0,  "",                                          "",   true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            var server *httptest.Server
            if tt.statusCode == 0 {
                server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
                server.Close() // simulate connection refused
            } else {
                server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                    w.WriteHeader(tt.statusCode)
                    if tt.body != "" {
                        w.Write([]byte(tt.body))
                    }
                }))
                defer server.Close()
            }

            client := payment.NewHostClient(payment.HostConfig{URL: server.URL})
            resp, err := client.Authorise(context.Background(), payment.AuthRequest{
                Amount: 1000, Currency: "MYR",
            })

            if (err != nil) != tt.wantErr {
                t.Errorf("err = %v, wantErr = %v", err, tt.wantErr)
            }
            if err == nil && resp.ResponseCode != tt.wantCode {
                t.Errorf("response code = %q, want %q", resp.ResponseCode, tt.wantCode)
            }
        })
    }
}
```

---

## Testing Idempotency

```php
public function test_duplicate_request_returns_same_result(): void
{
    Http::fake(['payment-host.internal/*' => Http::response([
        'response_code' => '00',
        'auth_code'     => 'SAME123',
    ], 200)]);

    $key     = Str::uuid()->toString();
    $payload = [
        'amount'      => 1000,
        'currency'    => 'MYR',
        'card_token'  => 'tok_test_visa',
        'merchant_id' => 'MERCH001',
    ];

    $first  = $this->postJson('/api/v1/payments', $payload, ['Idempotency-Key' => $key]);
    $second = $this->postJson('/api/v1/payments', $payload, ['Idempotency-Key' => $key]);

    $first->assertStatus(201);
    $second->assertStatus(201);

    // Same auth code — same result, not a second charge
    $this->assertEquals($first->json('data.auth_code'), $second->json('data.auth_code'));

    // Payment host called exactly once
    Http::assertSentCount(1);
}
```

---

## Testing Reversal Flow

```php
public function test_timed_out_payment_is_auto_reversed(): void
{
    Http::fake([
        'payment-host.internal/authorise' => Http::sequence()
            ->push(null, 504)               // timeout on first call
            ->push(['response_code' => '00'], 200), // reversal succeeds
    ]);

    $response = $this->postJson('/api/v1/payments', [
        'amount'      => 1000,
        'currency'    => 'MYR',
        'card_token'  => 'tok_test_visa',
        'merchant_id' => 'MERCH001',
    ], ['Idempotency-Key' => Str::uuid()]);

    // Timeout returns pending — not an error
    $response->assertStatus(202)->assertJsonPath('data.status', 'pending');

    $transactionId = $response->json('data.id');

    // Simulate reversal job running
    $this->artisan('payments:reverse-timeouts');

    $this->assertDatabaseHas('transactions', [
        'id'     => $transactionId,
        'status' => 'reversed',
    ]);
}
```

---

## Required Test Cases

Every payment service test suite must cover:

- Happy path (approved, RC `00`)
- Hard decline (RC `05` or `51`)
- Host timeout / 504 (pending state, not error)
- Invalid card / format error
- Idempotency: duplicate request returns same result, host called once
- Reversal: timeout flow results in reversal job being dispatched

---

## Best Practices

- **`Http::fake()` in PHP, `httptest.NewServer` in Go** — never make real HTTP calls to a payment host in tests
- **`Http::assertSentCount(1)` for idempotency** — proves the host was called once, not twice on a duplicate request
- **`Http::sequence()` for reversal flows** — simulates timeout on first call, success on reversal call without juggling multiple fakes
- **Table-driven tests in Go** — adding a new response code scenario is one extra struct entry
- **Race detector mandatory in Go** — run `go test -race`; goroutine races in payment code corrupt transaction state
- **Test the timeout case** — RC `91`, RC `96`, and `504` responses are the most common failure mode in production and the most commonly untested
