# Vue 3 Composition API Rules

## script setup with TypeScript

Every component must use `<script setup lang="ts">`. No Options API. No `defineComponent`.

```vue
<!-- Correct -->
<script setup lang="ts">
const props = defineProps<{ title: string; amount: number }>()
</script>

<!-- Incorrect -->
<script>
export default defineComponent({ ... })
</script>
```

All component files use `.vue` extension. Component names are PascalCase.

## defineProps with TypeScript Generics

Always use the TypeScript generic form for `defineProps`. Never use the runtime object syntax.

```vue
<script setup lang="ts">
// Correct — TypeScript interface form
interface Props {
  merchantId: string
  amount: number
  currency?: string
  readonly: boolean
}
const props = defineProps<Props>()

// Correct — withDefaults for optional props
const props = withDefaults(defineProps<Props>(), {
  currency: 'USD',
  readonly: false,
})

// Incorrect — runtime object form
const props = defineProps({
  merchantId: String,
  amount: Number,
})
</script>
```

## defineEmits Typed

All emits must be typed with the function overload form:

```vue
<script setup lang="ts">
// Correct — typed emits
const emit = defineEmits<{
  submit: [payload: PaymentPayload]
  cancel: []
  'update:modelValue': [value: string]
}>()

// Incorrect — untyped string array
const emit = defineEmits(['submit', 'cancel'])
</script>
```

## Composables Conventions

- Composable files: `use` prefix, camelCase: `usePaymentForm.ts`, `useCardValidation.ts`
- Composables live in `src/composables/`
- Always return an object (named exports), never a primitive directly
- Composables that wrap `fetch`/`axios` must accept a `signal?: AbortSignal` parameter
- Reactive state returned from composables uses `readonly()` wrapper to prevent external mutation

```ts
// src/composables/useCardValidation.ts
export function useCardValidation() {
  const cardNumber = ref('')
  const isValid = computed(() => validateLuhn(cardNumber.value))
  const maskedDisplay = computed(() => maskCardNumber(cardNumber.value))

  return {
    cardNumber,
    isValid: readonly(isValid),
    maskedDisplay: readonly(maskedDisplay),
  }
}
```

## v-for Key Rules

Every `v-for` must have a `:key` bound to a stable unique identifier — never use array index as key:

```vue
<!-- Correct — stable ID key -->
<tr v-for="tx in transactions" :key="tx.id">

<!-- Correct — compound key if no single ID -->
<option v-for="c in currencies" :key="c.code" :value="c.code">

<!-- Incorrect — index as key breaks reconciliation on reorder/delete -->
<tr v-for="(tx, index) in transactions" :key="index">
```

## No Direct DOM Manipulation

Never use `document.getElementById`, `document.querySelector`, or `element.style` directly. Use template refs:

```vue
<script setup lang="ts">
// Correct
const inputRef = useTemplateRef<HTMLInputElement>('cardInput')

function focusInput() {
  inputRef.value?.focus()
}
</script>

<template>
  <input ref="cardInput" />
</template>
```

Never call `.focus()`, `.blur()`, `.click()`, or `.setAttribute()` on raw DOM in component logic outside template refs.

## Payment UI: Never Retain Raw Card Data in State

Card component PCI rules:

```vue
<script setup lang="ts">
// FORBIDDEN — never hold raw card number in reactive state
const cardNumber = ref('4111111111111111')

// Correct — store masked value, send tokenized payload
const maskedPan = ref('')        // display only, last 4 digits
const token = ref('')            // from tokenization service

// Card number input: mask on blur
function onCardBlur(event: FocusEvent) {
  const el = event.target as HTMLInputElement
  maskedPan.value = '****' + el.value.slice(-4)
  // do not store el.value anywhere
}

// On submit: emit token, not raw PAN
function onSubmit() {
  emit('submit', { token: token.value, amount: props.amount })
  // clear any in-memory card fields
  token.value = ''
}
</script>
```

- CVV field: `autocomplete="cc-csc"`, clear `v-model` immediately after tokenization
- Expiry: `autocomplete="cc-exp"`, format MM/YY client-side only
- Never `console.log` card-related reactive data

## Event Naming

Custom events use kebab-case:

```vue
<!-- Correct -->
emit('payment-complete', payload)
emit('form-cancelled')
emit('update:model-value', value)

<!-- In template -->
<PaymentForm @payment-complete="handleComplete" />

<!-- Incorrect — camelCase event names -->
emit('paymentComplete', payload)
```

Exception: `update:modelValue` follows Vue's v-model convention exactly.

## Accessibility

Payment and form components must include:
- `role="alert"` and `aria-live="polite"` on error message containers
- `aria-invalid="true"` on inputs in error state
- `aria-describedby` linking input to its error message
- Labels associated via `for`/`id` or wrapping `<label>`
- Loading state: `aria-busy="true"` on submit button

```vue
<template>
  <div>
    <label for="card-number">Card Number</label>
    <input
      id="card-number"
      :aria-invalid="!!errors.cardNumber"
      :aria-describedby="errors.cardNumber ? 'card-number-error' : undefined"
      autocomplete="cc-number"
    />
    <div
      v-if="errors.cardNumber"
      id="card-number-error"
      role="alert"
      aria-live="polite"
    >
      {{ errors.cardNumber }}
    </div>
  </div>
</template>
```
