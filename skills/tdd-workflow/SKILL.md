---
name: tdd-workflow
description: Red→Green→Refactor TDD cycle for PHP/Laravel and Go payment code — failing test first, minimum implementation, race-safe green, coverage targets, and test case requirements for payment scenarios.
origin: fintech-stack
---

# TDD Workflow

Test-driven development in payment systems is not optional — it is the only way to confidently verify that a declined card, a host timeout, and an idempotent retry all behave correctly without a live payment host. Write the test first, confirm it fails, implement the minimum to make it pass, then refactor safely.

## When to Activate

- Developer says "write a test", "TDD", "test-first", or "red green refactor"
- Writing new payment processing logic, controllers, or service classes
- Adding a new API endpoint or Go handler

---

## PHP / Laravel (PHPUnit)

### Write the Failing Test First

```php
// tests/Feature/Payment/ProcessPaymentTest.php
<?php declare(strict_types=1);

namespace Tests\Feature\Payment;

use App\Models\Transaction;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class ProcessPaymentTest extends TestCase
{
    public function test_successful_payment_creates_approved_transaction(): void
    {
        Http::fake([
            'payment-host.internal/*' => Http::response([
                'response_code' => '00',
                'auth_code'     => 'ABC123',
            ], 200),
        ]);

        $response = $this->postJson('/api/v1/payments', [
            'amount'      => 1000,
            'currency'    => 'MYR',
            'card_token'  => 'tok_test_visa',
            'merchant_id' => 'MERCH001',
        ]);

        $response->assertStatus(201)
                 ->assertJsonPath('data.status', 'approved')
                 ->assertJsonPath('data.auth_code', 'ABC123');

        $this->assertDatabaseHas('transactions', [
            'merchant_id' => 'MERCH001',
            'status'      => 'approved',
            'amount'      => 1000,
        ]);
    }

    public function test_declined_payment_returns_declined_error(): void
    {
        Http::fake([
            'payment-host.internal/*' => Http::response(['response_code' => '51'], 200),
        ]);

        $this->postJson('/api/v1/payments', [
            'amount'      => 1000,
            'currency'    => 'MYR',
            'card_token'  => 'tok_test_visa',
            'merchant_id' => 'MERCH001',
        ])->assertStatus(422)->assertJsonPath('error.code', 'CARD_DECLINED');
    }

    public function test_host_timeout_returns_pending_status(): void
    {
        Http::fake([
            'payment-host.internal/*' => Http::response(null, 504),
        ]);

        $this->postJson('/api/v1/payments', [
            'amount'      => 1000,
            'currency'    => 'MYR',
            'card_token'  => 'tok_test_visa',
            'merchant_id' => 'MERCH001',
        ])->assertStatus(202)->assertJsonPath('data.status', 'pending');
    }
}
```

### Red → Green → Refactor

```bash
# 1. Confirm red
./vendor/bin/phpunit --filter ProcessPaymentTest

# 2. Implement minimum code to pass

# 3. Confirm green
./vendor/bin/phpunit --filter ProcessPaymentTest

# 4. Check coverage
./vendor/bin/phpunit --coverage-text --filter ProcessPaymentTest

# 5. Refactor — always run tests again after
./vendor/bin/phpunit --filter ProcessPaymentTest
```

---

## Go (table-driven tests)

### Write the Failing Test First

```go
// payment/service_test.go
package payment_test

import (
    "context"
    "net/http"
    "net/http/httptest"
    "testing"

    "github.com/yourorg/payment"
)

func TestProcessPayment(t *testing.T) {
    tests := []struct {
        name         string
        hostResponse string
        hostStatus   int
        wantStatus   string
        wantErr      bool
    }{
        {
            name:         "approved payment",
            hostResponse: `{"response_code":"00","auth_code":"ABC123"}`,
            hostStatus:   http.StatusOK,
            wantStatus:   "approved",
        },
        {
            name:         "declined payment",
            hostResponse: `{"response_code":"51"}`,
            hostStatus:   http.StatusOK,
            wantStatus:   "declined",
        },
        {
            name:       "host timeout returns pending",
            hostStatus: http.StatusGatewayTimeout,
            wantStatus: "pending",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.WriteHeader(tt.hostStatus)
                if tt.hostResponse != "" {
                    w.Write([]byte(tt.hostResponse))
                }
            }))
            defer server.Close()

            svc := payment.NewService(payment.Config{HostURL: server.URL})
            result, err := svc.Process(context.Background(), payment.Request{
                Amount:   1000,
                Currency: "MYR",
            })

            if (err != nil) != tt.wantErr {
                t.Errorf("Process() error = %v, wantErr %v", err, tt.wantErr)
            }
            if result != nil && result.Status != tt.wantStatus {
                t.Errorf("Process() status = %v, want %v", result.Status, tt.wantStatus)
            }
        })
    }
}
```

### Red → Green → Refactor

```bash
# 1. Confirm red
go test -run TestProcessPayment ./payment/...

# 2. Implement minimum code to pass

# 3. Confirm green with race detector
go test -race -run TestProcessPayment ./payment/...

# 4. Run full suite
go test -race ./...

# 5. Refactor — always re-run step 3 after
```

---

## Required Test Cases for Payment Code

Every payment service test suite must cover:
- Happy path (approved)
- Hard decline (RC 05 or 51)
- Host timeout / 504 (pending state, not error)
- Invalid card / format error
- Idempotency: duplicate request returns same result without double-charging
- Reversal: timeout flow results in reversal job being dispatched

---

## Coverage Requirements

- Minimum 80% coverage for all payment packages
- Run coverage reports:
  - PHP: `./vendor/bin/phpunit --coverage-html coverage/`
  - Go: `go test -coverprofile=coverage.out ./... && go tool cover -html=coverage.out`

---

## Best Practices

- **Write the test before a single line of implementation** — if you write the test after, you tend to write the test that the code passes, not the test that the feature requires
- **Table-driven tests in Go** — one test function, many scenarios; adding a new scenario is one extra struct entry
- **`Http::fake()` in PHP, `httptest.NewServer` in Go** — never make real HTTP calls to a payment host in tests
- **Race detector is mandatory for Go** — run `go test -race`; goroutine races in payment code corrupt transaction state
- **Test the timeout case** — RC 91, RC 96, and 504 responses are the most common failure mode in production and the most commonly untested
