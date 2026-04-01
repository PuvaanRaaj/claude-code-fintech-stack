---
name: vue-patterns
description: Vue 3 Composition API patterns for fintech — usePaymentForm composable with idempotency key, useCardFormatter with Luhn validation and masking, useTransactions pagination, useApiError, Pinia for session-only state, and multi-step payment flow with emit.
origin: fintech-stack
---

# Vue Patterns

Vue 3 composables are the right unit of abstraction for payment UI logic — they keep card formatting, submission state, and pagination out of components and make the PCI boundary explicit: Pinia stores hold session metadata, never card numbers.

## When to Activate

- Writing Vue 3 components or composables for payment UIs
- Setting up Pinia stores for payment state
- Handling card formatting, Luhn validation, or masked display
- Building a transaction list with pagination

---

## Payment Form Composable

```typescript
// composables/usePaymentForm.ts
import { ref, computed } from 'vue'
import type { PaymentRequest, PaymentResult } from '@/types/payment'

type Status = 'idle' | 'submitting' | 'approved' | 'declined' | 'error'

export function usePaymentForm() {
  const status = ref<Status>('idle')
  const error = ref<string | null>(null)
  const result = ref<PaymentResult | null>(null)

  const isSubmitting = computed(() => status.value === 'submitting')
  const isComplete = computed(() => ['approved', 'declined'].includes(status.value))

  async function submit(payload: PaymentRequest): Promise<void> {
    status.value = 'submitting'
    error.value = null
    result.value = null

    try {
      const res = await fetch('/api/v1/payments', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': crypto.randomUUID(),
        },
        body: JSON.stringify(payload),
      })

      const data = await res.json()

      if (res.ok) {
        result.value = data.data
        status.value = data.data.status === 'approved' ? 'approved' : 'declined'
      } else {
        error.value = data.error?.message ?? 'Payment failed'
        status.value = 'error'
      }
    } catch {
      error.value = 'Network error. Please try again.'
      status.value = 'error'
    }
  }

  function reset(): void {
    status.value = 'idle'
    error.value = null
    result.value = null
  }

  return { status, error, result, isSubmitting, isComplete, submit, reset }
}
```

---

## Card Formatter Composable

Handles Luhn validation, display formatting, masking, expiry formatting, and brand detection.

```typescript
// composables/useCardFormatter.ts
import { computed, ref } from 'vue'

export function useCardFormatter() {
  const rawValue = ref('')

  function luhn(pan: string): boolean {
    const digits = pan.replace(/\D/g, '')
    let sum = 0
    let alt = false
    for (let i = digits.length - 1; i >= 0; i--) {
      let n = parseInt(digits[i], 10)
      if (alt) {
        n *= 2
        if (n > 9) n -= 9
      }
      sum += n
      alt = !alt
    }
    return sum % 10 === 0
  }

  // Format: 4111 1111 1111 1111
  function formatCardNumber(value: string): string {
    const digits = value.replace(/\D/g, '').slice(0, 16)
    return digits.replace(/(\d{4})(?=\d)/g, '$1 ')
  }

  // Mask: **** **** **** 1111
  function maskCardNumber(value: string): string {
    const digits = value.replace(/\D/g, '')
    const last4 = digits.slice(-4)
    const masked = '*'.repeat(Math.max(0, digits.length - 4))
    return (masked + last4).replace(/(.{4})(?=.)/g, '$1 ')
  }

  // Format expiry: MM/YY
  function formatExpiry(value: string): string {
    const digits = value.replace(/\D/g, '').slice(0, 4)
    if (digits.length >= 3) return `${digits.slice(0, 2)}/${digits.slice(2)}`
    return digits
  }

  function getCardBrand(pan: string): string {
    const digits = pan.replace(/\D/g, '')
    if (/^4/.test(digits)) return 'visa'
    if (/^5[1-5]/.test(digits)) return 'mastercard'
    if (/^3[47]/.test(digits)) return 'amex'
    return 'unknown'
  }

  const isValid = computed(() => luhn(rawValue.value) && rawValue.value.replace(/\D/g, '').length >= 13)
  const brand = computed(() => getCardBrand(rawValue.value))

  return { rawValue, formatCardNumber, maskCardNumber, formatExpiry, getCardBrand, isValid, brand, luhn }
}
```

---

## Transaction List with Pagination

```typescript
// composables/useTransactions.ts
import { ref, computed, watch } from 'vue'
import type { Transaction, TransactionMeta } from '@/types/transaction'

export function useTransactions(merchantId: string) {
  const transactions = ref<Transaction[]>([])
  const meta = ref<TransactionMeta | null>(null)
  const page = ref(1)
  const perPage = ref(25)
  const loading = ref(false)
  const error = ref<string | null>(null)

  const hasNext = computed(() => meta.value ? page.value < meta.value.last_page : false)
  const hasPrev = computed(() => page.value > 1)

  async function load(): Promise<void> {
    loading.value = true
    error.value = null
    try {
      const params = new URLSearchParams({
        merchant_id: merchantId,
        page: page.value.toString(),
        per_page: perPage.value.toString(),
      })
      const res = await fetch(`/api/v1/transactions?${params}`)
      const data = await res.json()
      transactions.value = data.data
      meta.value = data.meta
    } catch {
      error.value = 'Failed to load transactions.'
    } finally {
      loading.value = false
    }
  }

  function nextPage(): void { if (hasNext.value) { page.value++ } }
  function prevPage(): void { if (hasPrev.value) { page.value-- } }

  watch(page, load, { immediate: true })

  return { transactions, meta, page, loading, error, hasNext, hasPrev, nextPage, prevPage }
}
```

---

## API Error Composable

```typescript
// composables/useApiError.ts
import { ref, computed } from 'vue'

interface ApiError {
  code: string
  message: string
  field?: string
}

export function useApiError() {
  const errors = ref<ApiError[]>([])

  function setFromResponse(response: { error?: ApiError; errors?: ApiError[] }): void {
    if (response.error) {
      errors.value = [response.error]
    } else if (response.errors) {
      errors.value = response.errors
    }
  }

  function clear(): void { errors.value = [] }

  const fieldError = (field: string) =>
    computed(() => errors.value.find(e => e.field === field)?.message)

  const globalError = computed(() =>
    errors.value.find(e => !e.field)?.message ?? null
  )

  return { errors, setFromResponse, clear, fieldError, globalError }
}
```

---

## Pinia Store for Session State

```typescript
// stores/payment.ts
import { defineStore } from 'pinia'
import type { PaymentSession } from '@/types/payment'

// Store session state only — never card data
export const usePaymentStore = defineStore('payment', {
  state: () => ({
    sessionId: null as string | null,
    merchantId: null as string | null,
    orderRef: null as string | null,
    amount: 0,
    currency: 'MYR',
    returnUrl: null as string | null,
  }),

  getters: {
    formattedAmount: (state) =>
      new Intl.NumberFormat('en-MY', { style: 'currency', currency: state.currency })
        .format(state.amount / 100),
  },

  actions: {
    initSession(session: PaymentSession): void {
      this.sessionId  = session.id
      this.merchantId = session.merchant_id
      this.orderRef   = session.order_ref
      this.amount     = session.amount
      this.currency   = session.currency
      this.returnUrl  = session.return_url
    },

    clearSession(): void {
      this.$reset()
    },
  },
})
```

---

## Multi-Step Payment Flow

```vue
<!-- Parent orchestrates steps via emit -->
<script setup lang="ts">
import { ref } from 'vue'

type Step = 'details' | 'card' | 'confirm' | 'result'
const step = ref<Step>('details')
const orderRef = ref('')
const amount = ref(0)

function onDetailsComplete(data: { orderRef: string; amount: number }) {
  orderRef.value = data.orderRef
  amount.value = data.amount
  step.value = 'card'
}

function onCardComplete() { step.value = 'result' }
</script>

<template>
  <OrderDetailsStep v-if="step === 'details'" @complete="onDetailsComplete" />
  <CardInputStep v-else-if="step === 'card'" :amount="amount" @complete="onCardComplete" />
  <PaymentResultStep v-else-if="step === 'result'" />
</template>
```

---

## Best Practices

- **`crypto.randomUUID()` per submit call** — generates a fresh idempotency key for each attempt; do not reuse across retries unless intentionally replaying
- **Pinia stores hold session metadata, not card data** — `sessionId`, `merchantId`, `amount`; card number and CVV must never reach the store
- **`<script setup lang="ts">` always** — explicit `ref<T>()` and `computed<T>()` types make PCI data flow auditable
- **Composable returns a plain object** — not an array; named exports make it clear what each composable provides
- **`maskCardNumber` for display, raw value for submission** — show masked on screen, send tokenised value to API; never send raw PAN
- **`watch(page, load, { immediate: true })`** — drives the initial fetch and re-fetches on page change without duplicating calls
