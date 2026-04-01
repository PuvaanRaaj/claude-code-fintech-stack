---
name: frontend-patterns
description: PCI-safe payment form patterns for Vue 3 and React — card number masking, CVV clearing, loading state management, 3DS redirect handling, and accessibility requirements for payment UIs.
origin: fintech-stack
---

# Frontend Patterns

A payment form is the most security-sensitive UI component a frontend developer writes. Raw card numbers stored in state, a CVV field not cleared after submit, or a response code shown verbatim to users are all compliance failures. This skill covers the safe patterns for payment forms in Vue 3 and React, with accessibility and error handling included.

## When to Activate

- Building or reviewing a payment form component
- Handling loading states, error messages, or 3DS redirects in the UI
- Developer asks about PCI-safe frontend patterns or form accessibility

---

## PCI-Safe Rules

- Never store raw card numbers in component state, Pinia stores, or Redux
- Mask the card number display after blur: show only last 4 digits
- Clear CVV field immediately after form submission
- Never log card input events
- Use `autocomplete="cc-number"` for browser autofill but clear on submit
- Consider hosted fields (iframe-based) for the highest PCI compliance level

---

## Vue 3 — Payment Form Component

```vue
<!-- components/PaymentForm.vue -->
<script setup lang="ts">
import { ref, computed } from 'vue'
import { usePaymentForm } from '@/composables/usePaymentForm'
import { useCardFormatter } from '@/composables/useCardFormatter'

const { submit, status, error, isSubmitting } = usePaymentForm()
const { maskCardNumber } = useCardFormatter()

const rawCardNumber = ref('')       // cleared after submit
const maskedDisplay = ref('')       // shown to user after blur
const expiry = ref('')
const cvv = ref('')                 // cleared after submit

const displayValue = computed(() => maskedDisplay.value || rawCardNumber.value)

function onCardBlur() {
  if (rawCardNumber.value) {
    maskedDisplay.value = maskCardNumber(rawCardNumber.value)
  }
}

function onCardFocus() {
  maskedDisplay.value = ''  // show raw input again while editing
}

async function onSubmit() {
  await submit({ cardNumber: rawCardNumber.value, expiry: expiry.value, cvv: cvv.value })
  // Clear sensitive data immediately after submit — do not leave in memory
  rawCardNumber.value = ''
  maskedDisplay.value = ''
  cvv.value = ''
}
</script>

<template>
  <form @submit.prevent="onSubmit" novalidate>
    <div role="group" aria-labelledby="card-section-label">
      <span id="card-section-label">Card details</span>

      <label for="card-number">Card number</label>
      <input
        id="card-number"
        :value="displayValue"
        type="tel"
        inputmode="numeric"
        autocomplete="cc-number"
        placeholder="0000 0000 0000 0000"
        aria-describedby="card-error"
        @blur="onCardBlur"
        @focus="onCardFocus"
        @input="(e) => (rawCardNumber = (e.target as HTMLInputElement).value)"
      />
      <span id="card-error" role="alert" v-if="error?.field === 'card_number'">
        {{ error.message }}
      </span>
    </div>

    <button type="submit" :disabled="isSubmitting" :aria-busy="isSubmitting">
      <span v-if="isSubmitting">Processing…</span>
      <span v-else>Pay</span>
    </button>

    <!-- aria-live announces payment result to screen readers -->
    <div aria-live="polite" aria-atomic="true">
      <span v-if="status === 'approved'">Payment approved</span>
      <span v-else-if="status === 'declined'">Payment declined. Please try another card.</span>
      <span v-else-if="status === 'error'">An error occurred. Please try again.</span>
    </div>
  </form>
</template>
```

### Payment Form Composable

```typescript
// composables/usePaymentForm.ts
export function usePaymentForm() {
  const status = ref<'idle' | 'submitting' | 'approved' | 'declined' | 'error'>('idle')
  const error = ref<{ field?: string; message: string } | null>(null)
  const isSubmitting = computed(() => status.value === 'submitting')

  async function submit(payload: PaymentPayload) {
    status.value = 'submitting'
    error.value = null

    try {
      const result = await paymentApi.create({
        ...payload,
        idempotencyKey: crypto.randomUUID(),
      })
      status.value = result.data.status === 'approved' ? 'approved' : 'declined'
    } catch (err) {
      if (err instanceof PaymentApiError) {
        error.value = { message: err.userMessage }
      }
      status.value = 'error'
    }
  }

  return { submit, status, error, isSubmitting }
}
```

---

## React — Payment Form Hooks

```tsx
// hooks/usePayment.ts
export function usePayment() {
  const [status, setStatus] = useState<PaymentStatus>('idle')
  const [error, setError] = useState<string | null>(null)

  const submit = useCallback(async (payload: PaymentPayload) => {
    setStatus('submitting')
    setError(null)
    try {
      const result = await paymentApi.create(payload)
      setStatus(result.status === 'approved' ? 'approved' : 'declined')
    } catch (err) {
      setError(err instanceof PaymentApiError ? err.userMessage : 'Unexpected error')
      setStatus('error')
    }
  }, [])

  return { status, error, submit, isSubmitting: status === 'submitting' }
}

// PaymentForm.tsx
export function PaymentForm() {
  const { submit, isSubmitting, status, error } = usePayment()
  const cardRef = useRef<HTMLInputElement>(null)

  const handleSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    const form = e.currentTarget
    const data = new FormData(form)
    await submit({ cardNumber: data.get('card') as string })
    // Clear sensitive fields after submit
    if (cardRef.current) cardRef.current.value = ''
  }

  return (
    <form onSubmit={handleSubmit}>
      <input ref={cardRef} name="card" type="tel" autoComplete="cc-number" />
      <button type="submit" disabled={isSubmitting} aria-busy={isSubmitting}>
        {isSubmitting ? 'Processing…' : 'Pay'}
      </button>
      <div role="status" aria-live="polite">
        {status === 'approved' && 'Payment approved'}
        {status === 'declined' && 'Payment declined. Please try another card.'}
        {error && <span role="alert">{error}</span>}
      </div>
    </form>
  )
}
```

---

## Error Handling Hierarchy

| Scenario | User-visible message |
|----------|----------------------|
| Network error | "Connection error. Please check your connection and try again." |
| Declined (RC != 00) | "Payment declined. Please try another card." |
| 3DS required | Redirect or open iframe — never show raw 3DS error |
| Validation error (422) | Field-level errors from API response |
| Server error (5xx) | "An unexpected error occurred. Please try again." |

Never expose raw payment host response codes (RC 51, RC 05, etc.) to users.

---

## Accessibility Requirements

- `aria-live="polite"` on the payment status container
- `aria-busy="true"` on the submit button during processing
- `role="alert"` on error messages
- `aria-describedby` linking inputs to their error messages
- Full keyboard navigation without mouse
- Focus moves to the status message after the payment result is received

---

## Best Practices

- **Clear CVV after every submit** — it must not persist in state after the transaction completes
- **Clear card number after submit** — the last 4 digits are acceptable to display; the full number must go
- **Disable the submit button during processing** — prevents double-submission and the resulting duplicate charges
- **Never log `event.target.value` on card input events** — browser devtools logs can capture them
- **`aria-live` is not optional** — screen reader users must hear the payment result without page reload
- **Hosted fields over raw inputs** — if PCI scope is a concern, iframe-based hosted fields move card capture out of your page entirely
