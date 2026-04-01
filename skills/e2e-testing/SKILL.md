---
name: e2e-testing
description: End-to-end payment flow testing with Playwright — PCI-safe test cards, approved/declined/3DS scenarios, webhook delivery verification, and CI integration.
origin: fintech-stack
---

# E2E Testing

Payment E2E tests have two non-negotiable rules: never use real card numbers, and never share test state between test runs. A test that accidentally uses a real PAN is a PCI incident. A test that depends on a previous test's approved transaction produces false positives in CI. This skill covers Playwright setup, standard payment scenarios, and CI integration.

## When to Activate

- Writing or reviewing Playwright tests for payment flows
- Testing 3DS redirect flows, webhook delivery, or multi-step checkout
- Developer asks about PCI-safe test cards or E2E environment setup

---

## PCI-Safe Test Cards

Never use real card numbers. Always use scheme-provided test PANs:

| Scheme | Test PAN | Result |
|--------|----------|--------|
| Visa | 4111111111111111 | Approved |
| Visa | 4000000000000002 | Declined (RC 51) |
| Mastercard | 5555555555554444 | Approved |
| Mastercard | 5200828282828210 | Declined (RC 51) |
| Amex | 378282246310005 | Approved |
| Visa (3DS required) | 4000000000003220 | Triggers 3DS challenge |

Expiry: any future date (e.g., 12/26)
CVV: 123 (or 1234 for Amex)

**Never** hard-code real PANs. Fail CI if a real-looking PAN pattern appears in test files.

---

## Playwright Setup

```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  retries: process.env.CI ? 2 : 0,
  use: {
    baseURL: process.env.E2E_BASE_URL ?? 'http://localhost:8080',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
})
```

---

## Payment Flow Tests

```typescript
// e2e/payment/checkout.spec.ts
import { test, expect } from '@playwright/test'
import { TEST_CARDS } from '../fixtures/test-cards'

test.describe('Payment checkout flow', () => {

  test('approved Visa payment completes checkout', async ({ page }) => {
    await page.goto('/checkout')
    await page.getByLabel('Amount').fill('10.00')
    await page.getByLabel('Currency').selectOption('MYR')

    await page.getByLabel('Card number').fill(TEST_CARDS.visa.approved)
    await page.getByLabel('Expiry').fill('12/26')
    await page.getByLabel('CVV').fill('123')

    await page.getByRole('button', { name: 'Pay' }).click()
    await expect(page.getByRole('button', { name: 'Pay' })).toBeDisabled()

    await expect(page.getByTestId('payment-status')).toHaveText('Payment approved', {
      timeout: 10_000,
    })

    // Receipt must show masked card only
    await expect(page.getByTestId('card-last4')).toHaveText('1111')
    await expect(page.getByTestId('auth-code')).toBeVisible()
  })

  test('declined card shows user-friendly error without raw response code', async ({ page }) => {
    await page.goto('/checkout')
    await page.getByLabel('Card number').fill(TEST_CARDS.visa.declined)
    await page.getByLabel('Expiry').fill('12/26')
    await page.getByLabel('CVV').fill('123')
    await page.getByRole('button', { name: 'Pay' }).click()

    await expect(page.getByTestId('payment-status')).toHaveText('Payment declined', {
      timeout: 10_000,
    })
    // Raw response code must NOT be shown to the user
    await expect(page.getByTestId('response-code')).not.toBeVisible()
  })

  test('3DS challenge flow completes after authentication', async ({ page }) => {
    await page.goto('/checkout')
    await page.getByLabel('Card number').fill(TEST_CARDS.visa.threeds)
    await page.getByLabel('Expiry').fill('12/26')
    await page.getByLabel('CVV').fill('123')
    await page.getByRole('button', { name: 'Pay' }).click()

    await expect(page).toHaveURL(/3ds|acs|challenge/, { timeout: 5_000 })
    await page.getByRole('button', { name: 'Approve' }).click()

    await expect(page).toHaveURL(/checkout\/complete/, { timeout: 10_000 })
    await expect(page.getByTestId('payment-status')).toHaveText('Payment approved')
  })

})
```

---

## Webhook Delivery Test

```typescript
// e2e/webhook/delivery.spec.ts
test('webhook delivered with valid HMAC signature', async ({ request }) => {
  const payment = await request.post('/api/v1/payments', {
    data: {
      amount: 1000,
      currency: 'MYR',
      card_token: 'tok_test_visa_approved',
      webhook_url: process.env.WEBHOOK_TEST_URL,
    },
    headers: {
      'Idempotency-Key': crypto.randomUUID(),
      'Authorization': `Bearer ${process.env.TEST_API_TOKEN}`,
    },
  })

  expect(payment.status()).toBe(201)

  const paymentId = (await payment.json()).data.id
  let delivered = false

  for (let i = 0; i < 10; i++) {
    await new Promise(r => setTimeout(r, 1000))
    const status = await request.get(`/api/v1/payments/${paymentId}/webhook-status`)
    if ((await status.json()).delivered) { delivered = true; break }
  }

  expect(delivered).toBe(true)
})
```

---

## CI Integration

```yaml
# .gitlab-ci.yml or .github/workflows
e2e:
  script:
    - bun install
    - bun x playwright install --with-deps chromium
    - E2E_BASE_URL=http://app:8080 bun x playwright test
  artifacts:
    when: always
    paths:
      - playwright-report/
      - test-results/
```

- Local debugging: `bun x playwright test --headed`
- CI: always headless (default)
- Use `waitForURL` and `waitForResponse` — not fixed `waitForTimeout`
- Set `retries: 2` in CI for payment flows that involve real host calls

---

## Best Practices

- **One `test.describe` per user flow** — approved flow, declined flow, 3DS flow, webhook flow are separate describes
- **Every test is independent** — no shared state, no dependency on previous tests; reset test data via API or factory before each test
- **Test cards in a fixtures file** — `e2e/fixtures/test-cards.ts` is the single source of truth; never inline test PANs in test files
- **Fail CI on real PAN patterns** — add a grep check in CI that fails the pipeline if a real-looking card number appears in `e2e/`
- **Upload artifacts on failure** — Playwright traces and screenshots are essential for debugging flaky tests in CI
