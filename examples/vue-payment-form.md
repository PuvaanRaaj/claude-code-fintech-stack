# Vue 3 Payment Form Component

A complete PCI-safe Vue 3 payment form with card number masking, Luhn validation feedback, expiry formatter, CVV field, accessibility attributes, and tokenized emit.

## Component: PaymentForm.vue

```vue
<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useCardValidation } from '@/composables/useCardValidation.js'
import { useExpiryInput } from '@/composables/useExpiryInput.js'

interface Props {
  amount: number
  currency: string
  disabled?: boolean
}

interface TokenizedPayload {
  token: string
  maskedPan: string
  expiryMonth: string
  expiryYear: string
  amount: number
  currency: string
}

const props = withDefaults(defineProps<Props>(), {
  disabled: false,
})

const emit = defineEmits<{
  submit: [payload: TokenizedPayload]
  cancel: []
}>()

// --- Card number state ---
// We never store raw PAN in reactive state.
// The input's DOM value holds the raw digits temporarily;
// we only retain the masked display and the token reference.
const cardInputRef = ref<HTMLInputElement | null>(null)
const maskedPan = ref('')
const cardToken = ref('')    // from tokenization service
const cardError = ref('')

const { isValidLuhn, cardBrand, formatCardDisplay } = useCardValidation()

// --- Expiry state ---
const { expiry, expiryMonth, expiryYear, expiryError, handleExpiryInput } = useExpiryInput()

// --- CVV state ---
const cvvInputRef = ref<HTMLInputElement | null>(null)
const cvvError = ref('')

// --- Form state ---
const isSubmitting = ref(false)
const formError = ref('')

// --- Card number handlers ---
function onCardInput(event: Event) {
  const el = event.target as HTMLInputElement
  const raw = el.value.replace(/\D/g, '').slice(0, 19)

  // Format for display: groups of 4 (e.g., 4111 1111 1111 1111)
  el.value = formatCardDisplay(raw)

  cardError.value = ''
  maskedPan.value = ''
  cardToken.value = ''
}

function onCardBlur(event: FocusEvent) {
  const el = event.target as HTMLInputElement
  const raw = el.value.replace(/\D/g, '')

  if (!raw) {
    cardError.value = 'Card number is required'
    return
  }

  if (!isValidLuhn(raw)) {
    cardError.value = 'Invalid card number'
    el.value = ''
    return
  }

  // Show only last 4 digits after blur (PCI-safe masking)
  maskedPan.value = '****' + raw.slice(-4)

  // Tokenize the raw PAN — do NOT store raw in any reactive ref
  tokenizeCard(raw, el)
}

async function tokenizeCard(rawPan: string, inputEl: HTMLInputElement) {
  try {
    // Call your tokenization service here
    // The raw PAN must not leave this function as a reactive value
    const token = await tokenizationService.tokenize(rawPan)
    cardToken.value = token

    // Clear the input's DOM value — raw digits no longer needed
    inputEl.value = maskedPan.value
  } catch (err) {
    cardError.value = 'Unable to process card. Please try again.'
    inputEl.value = ''
    maskedPan.value = ''
  }
}

// --- CVV handlers ---
function onCvvBlur(event: FocusEvent) {
  const el = event.target as HTMLInputElement
  const raw = el.value.replace(/\D/g, '')

  if (!raw || (raw.length !== 3 && raw.length !== 4)) {
    cvvError.value = 'Enter a valid security code'
    return
  }
  cvvError.value = ''
  // CVV is not stored in reactive state — it stays in the DOM input only
}

// --- Submit ---
async function handleSubmit() {
  // Validate all fields before submitting
  if (!cardToken.value) {
    cardError.value = 'Please enter a valid card number'
    cardInputRef.value?.focus()
    return
  }
  if (expiryError.value || !expiryMonth.value || !expiryYear.value) {
    return
  }

  const cvvEl = cvvInputRef.value
  const cvvRaw = cvvEl?.value.replace(/\D/g, '') ?? ''
  if (!cvvRaw || (cvvRaw.length !== 3 && cvvRaw.length !== 4)) {
    cvvError.value = 'Security code is required'
    cvvEl?.focus()
    return
  }

  isSubmitting.value = true
  formError.value = ''

  try {
    // Emit tokenized payload — raw card data never leaves this component
    emit('submit', {
      token: cardToken.value,
      maskedPan: maskedPan.value,
      expiryMonth: expiryMonth.value,
      expiryYear: expiryYear.value,
      amount: props.amount,
      currency: props.currency,
    })
  } catch (err) {
    formError.value = 'Payment failed. Please try again.'
  } finally {
    isSubmitting.value = false

    // Clear sensitive fields from DOM after submit
    if (cvvEl) cvvEl.value = ''
    cardToken.value = ''
  }
}

function handleCancel() {
  // Clear sensitive fields before cancelling
  if (cardInputRef.value) cardInputRef.value.value = ''
  if (cvvInputRef.value) cvvInputRef.value.value = ''
  cardToken.value = ''
  maskedPan.value = ''
  emit('cancel')
}

// Computed display
const formattedAmount = computed(() =>
  new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: props.currency,
    minimumFractionDigits: 2,
  }).format(props.amount / 100)
)
</script>

<template>
  <form
    novalidate
    aria-label="Payment form"
    @submit.prevent="handleSubmit"
  >
    <h2 class="text-lg font-semibold mb-4">
      Pay {{ formattedAmount }}
    </h2>

    <!-- Card Number -->
    <div class="field-group">
      <label for="card-number" class="field-label">
        Card Number
      </label>
      <input
        id="card-number"
        ref="cardInputRef"
        type="text"
        inputmode="numeric"
        autocomplete="cc-number"
        placeholder="1234 5678 9012 3456"
        maxlength="23"
        :disabled="disabled || isSubmitting"
        :aria-invalid="!!cardError"
        :aria-describedby="cardError ? 'card-number-error' : undefined"
        class="field-input"
        :class="{ 'field-input--error': cardError }"
        @input="onCardInput"
        @blur="onCardBlur"
      />
      <div
        v-if="cardError"
        id="card-number-error"
        role="alert"
        aria-live="polite"
        class="field-error"
      >
        {{ cardError }}
      </div>
      <div v-if="cardBrand && !cardError" class="field-hint">
        {{ cardBrand }}
      </div>
    </div>

    <!-- Expiry + CVV row -->
    <div class="field-row">
      <!-- Expiry Date -->
      <div class="field-group field-group--half">
        <label for="expiry" class="field-label">
          Expiry Date
        </label>
        <input
          id="expiry"
          type="text"
          inputmode="numeric"
          autocomplete="cc-exp"
          placeholder="MM / YY"
          maxlength="7"
          :disabled="disabled || isSubmitting"
          :value="expiry"
          :aria-invalid="!!expiryError"
          :aria-describedby="expiryError ? 'expiry-error' : undefined"
          class="field-input"
          :class="{ 'field-input--error': expiryError }"
          @input="handleExpiryInput"
        />
        <div
          v-if="expiryError"
          id="expiry-error"
          role="alert"
          aria-live="polite"
          class="field-error"
        >
          {{ expiryError }}
        </div>
      </div>

      <!-- CVV -->
      <div class="field-group field-group--half">
        <label for="cvv" class="field-label">
          Security Code
        </label>
        <input
          id="cvv"
          ref="cvvInputRef"
          type="password"
          inputmode="numeric"
          autocomplete="cc-csc"
          placeholder="CVV"
          maxlength="4"
          :disabled="disabled || isSubmitting"
          :aria-invalid="!!cvvError"
          :aria-describedby="cvvError ? 'cvv-error' : undefined"
          class="field-input"
          :class="{ 'field-input--error': cvvError }"
          @blur="onCvvBlur"
        />
        <div
          v-if="cvvError"
          id="cvv-error"
          role="alert"
          aria-live="polite"
          class="field-error"
        >
          {{ cvvError }}
        </div>
      </div>
    </div>

    <!-- Form-level error -->
    <div
      v-if="formError"
      role="alert"
      aria-live="assertive"
      class="form-error"
    >
      {{ formError }}
    </div>

    <!-- Actions -->
    <div class="form-actions">
      <button
        type="button"
        :disabled="isSubmitting"
        class="btn btn--secondary"
        @click="handleCancel"
      >
        Cancel
      </button>
      <button
        type="submit"
        :disabled="disabled || isSubmitting"
        :aria-busy="isSubmitting"
        class="btn btn--primary"
      >
        {{ isSubmitting ? 'Processing...' : `Pay ${formattedAmount}` }}
      </button>
    </div>
  </form>
</template>
```

## Composable: useCardValidation.ts

```ts
// src/composables/useCardValidation.ts
import { ref, computed } from 'vue'

export function useCardValidation() {
  function isValidLuhn(digits: string): boolean {
    let sum = 0
    let alternate = false
    for (let i = digits.length - 1; i >= 0; i--) {
      let n = parseInt(digits[i], 10)
      if (alternate) {
        n *= 2
        if (n > 9) n -= 9
      }
      sum += n
      alternate = !alternate
    }
    return sum % 10 === 0
  }

  function cardBrandFromPan(pan: string): string {
    if (/^4/.test(pan)) return 'Visa'
    if (/^5[1-5]/.test(pan)) return 'Mastercard'
    if (/^3[47]/.test(pan)) return 'American Express'
    if (/^6/.test(pan)) return 'Discover / UnionPay'
    return ''
  }

  const cardBrand = ref('')

  function formatCardDisplay(digits: string): string {
    cardBrand.value = cardBrandFromPan(digits)
    // Amex: 4-6-5
    if (/^3[47]/.test(digits)) {
      return digits.replace(/(\d{4})(\d{0,6})(\d{0,5})/, (_, a, b, c) =>
        [a, b, c].filter(Boolean).join(' ')
      )
    }
    // Default: 4-4-4-4
    return digits.replace(/(\d{4})(?=\d)/g, '$1 ')
  }

  return { isValidLuhn, cardBrand, formatCardDisplay }
}
```

## Composable: useExpiryInput.ts

```ts
// src/composables/useExpiryInput.ts
import { ref, computed } from 'vue'

export function useExpiryInput() {
  const expiry = ref('')
  const expiryError = ref('')

  const expiryMonth = computed(() => expiry.value.slice(0, 2))
  const expiryYear = computed(() => expiry.value.slice(-2))

  function handleExpiryInput(event: Event) {
    const el = event.target as HTMLInputElement
    const raw = el.value.replace(/\D/g, '').slice(0, 4)

    // Format as MM / YY
    if (raw.length >= 3) {
      expiry.value = raw.slice(0, 2) + ' / ' + raw.slice(2)
    } else {
      expiry.value = raw
    }

    el.value = expiry.value
    validateExpiry(raw)
  }

  function validateExpiry(digits: string) {
    if (digits.length < 4) {
      expiryError.value = ''
      return
    }
    const month = parseInt(digits.slice(0, 2), 10)
    const year = parseInt('20' + digits.slice(2), 10)
    const now = new Date()
    const expDate = new Date(year, month - 1)

    if (month < 1 || month > 12) {
      expiryError.value = 'Invalid month'
    } else if (expDate < new Date(now.getFullYear(), now.getMonth())) {
      expiryError.value = 'Card has expired'
    } else {
      expiryError.value = ''
    }
  }

  return { expiry, expiryMonth, expiryYear, expiryError, handleExpiryInput }
}
```

## Usage

```vue
<PaymentForm
  :amount="12550"
  currency="MYR"
  @submit="handlePaymentSubmit"
  @cancel="router.back()"
/>
```

```ts
async function handlePaymentSubmit(payload: TokenizedPayload) {
  // payload.token — send to your backend
  // payload.maskedPan — for display/receipt
  // Raw card data never reached this handler
  await api.post('/v1/payments', payload)
}
```
