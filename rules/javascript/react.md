# React 18+ Rules

## Functional Components Only

All components must be functional. No class components. No `React.Component` or `React.PureComponent`.

```tsx
// Correct — functional with TypeScript
interface PaymentCardProps {
  amount: number
  currency: string
  onSubmit: (token: string) => void
}

export function PaymentCard({ amount, currency, onSubmit }: PaymentCardProps) {
  return <div>...</div>
}

// Incorrect — class component
class PaymentCard extends React.Component { ... }
```

Components are named exports except for page/route components (default export for routing conventions).

## useEffect Cleanup Requirement

Every `useEffect` that sets up a subscription, timer, or async operation must return a cleanup function:

```tsx
// Correct — cleanup aborts fetch
useEffect(() => {
  const controller = new AbortController()

  fetchTransaction(transactionId, controller.signal)
    .then(setTransaction)
    .catch((err) => {
      if (err.name !== 'AbortError') setError(err)
    })

  return () => controller.abort()
}, [transactionId])

// Correct — cleanup removes listener
useEffect(() => {
  const handler = (e: Event) => handlePaymentComplete(e)
  window.addEventListener('payment-complete', handler)
  return () => window.removeEventListener('payment-complete', handler)
}, [])

// Incorrect — no cleanup, potential memory leak
useEffect(() => {
  fetch('/api/transactions').then(r => r.json()).then(setData)
}, [])
```

## Stable Keys in Lists

Keys must be stable, unique, and not array indices:

```tsx
// Correct — stable entity ID
{transactions.map((tx) => (
  <TransactionRow key={tx.id} transaction={tx} />
))}

// Incorrect — array index as key
{transactions.map((tx, i) => (
  <TransactionRow key={i} transaction={tx} />
))}
```

If the list item lacks a natural ID, derive a stable key from its unique properties.

## Custom Hook Conventions

- Custom hooks: `use` prefix, camelCase filename: `usePaymentForm.ts`
- Custom hooks live in `src/hooks/`
- Hooks that fetch data must return `{ data, isLoading, error }` shape
- Hooks must not contain JSX
- Hooks that manage subscriptions must clean up in their `useEffect`

```ts
// src/hooks/useTransaction.ts
export function useTransaction(id: string) {
  const [data, setData] = useState<Transaction | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  useEffect(() => {
    const controller = new AbortController()
    setIsLoading(true)

    getTransaction(id, controller.signal)
      .then(setData)
      .catch((err) => { if (err.name !== 'AbortError') setError(err) })
      .finally(() => setIsLoading(false))

    return () => controller.abort()
  }, [id])

  return { data, isLoading, error }
}
```

## memo / useMemo / useCallback Policy

Use only when profiling shows a real performance problem — not preemptively.

```tsx
// Justified — expensive computation, re-runs only on dependency change
const sortedTransactions = useMemo(
  () => [...transactions].sort((a, b) => b.createdAt - a.createdAt),
  [transactions]
)

// Justified — stable reference for child component that is React.memo'd
const handleSubmit = useCallback((payload: PaymentPayload) => {
  processPayment(payload)
}, [processPayment])

// Unjustified — simple derivation, memo adds overhead
const total = useMemo(() => amount + fee, [amount, fee])  // just write: amount + fee
```

`React.memo` wrapping: only for components that receive the same props frequently and re-render expensively (e.g., large tables, chart components).

## useTransition for Non-Urgent Updates

Use `useTransition` when a state update triggers a slow render and should not block user interaction:

```tsx
const [isPending, startTransition] = useTransition()

function handleCurrencyChange(currency: string) {
  startTransition(() => {
    // Refiltering a large transaction list — non-urgent
    setFilteredTransactions(transactions.filter(t => t.currency === currency))
  })
}

return (
  <button onClick={() => handleCurrencyChange('USD')} disabled={isPending}>
    {isPending ? 'Updating...' : 'Filter USD'}
  </button>
)
```

Do not use `useTransition` for mutations (form submissions, API calls) — those are urgent.

## Payment Component Rules

Same PCI constraints as Vue components:

```tsx
// FORBIDDEN — raw card number in state
const [cardNumber, setCardNumber] = useState('4111111111111111')

// Correct — never store raw PAN in React state
const [maskedDisplay, setMaskedDisplay] = useState('')
const [token, setToken] = useState('')

function handleCardBlur(e: React.FocusEvent<HTMLInputElement>) {
  const raw = e.target.value
  setMaskedDisplay('****' + raw.slice(-4))
  // tokenize raw here, then clear
  tokenize(raw).then(setToken)
  e.target.value = '' // clear the input value
}

function handleSubmit(e: React.FormEvent) {
  e.preventDefault()
  onSubmit({ token, amount })
  setToken('')   // clear after submit
}
```

- `autocomplete="cc-number"` on card number field
- `autocomplete="cc-csc"` on CVV field, clear after tokenization
- `role="alert"` on error messages
- Never log card-related state to console

## Component Folder Structure

```
src/
  components/
    payment/
      PaymentForm.tsx
      PaymentForm.test.tsx
      CardNumberInput.tsx
      ExpiryInput.tsx
    common/
      Button.tsx
      ErrorAlert.tsx
  hooks/
    useTransaction.ts
    usePaymentForm.ts
  types/
    payment.ts
```

Test files co-located with component files, named `ComponentName.test.tsx`.
