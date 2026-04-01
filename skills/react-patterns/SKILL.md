---
name: react-patterns
description: React 18 patterns for payment UIs — usePayment hook with idempotency, useCardValidation with Luhn and brand detection, PaymentSessionContext for session-only state, React Query with cache invalidation after payment, PaymentErrorBoundary, and stop-polling pattern for pending status.
origin: fintech-stack
---

# React Patterns

React payment UIs have two layers: hooks that manage submission state and card validation logic, and React Query that keeps the transaction list fresh. The PCI boundary is explicit — context holds session metadata, never card numbers.

## When to Activate

- Writing React components or hooks for payment UIs
- Setting up React Query for transaction data or context for session state
- Adding error boundaries or payment status polling to payment components
- Developer asks about payment-specific React patterns

---

## usePayment Hook

```typescript
// hooks/usePayment.ts
import { useState, useCallback } from 'react'
import type { PaymentPayload, PaymentResult } from '@/types/payment'

type PaymentStatus = 'idle' | 'submitting' | 'approved' | 'declined' | 'error'

export function usePayment() {
  const [status, setStatus] = useState<PaymentStatus>('idle')
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<PaymentResult | null>(null)

  const submit = useCallback(async (payload: PaymentPayload): Promise<void> => {
    setStatus('submitting')
    setError(null)
    setResult(null)

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
        setResult(data.data)
        setStatus(data.data.status === 'approved' ? 'approved' : 'declined')
      } else {
        setError(data.error?.message ?? 'Payment failed')
        setStatus('error')
      }
    } catch {
      setError('Network error. Please check your connection and try again.')
      setStatus('error')
    }
  }, [])

  const reset = useCallback(() => {
    setStatus('idle')
    setError(null)
    setResult(null)
  }, [])

  return {
    status,
    error,
    result,
    isSubmitting: status === 'submitting',
    submit,
    reset,
  }
}
```

---

## useCardValidation Hook

```typescript
// hooks/useCardValidation.ts
import { useState, useCallback } from 'react'

interface CardState {
  number: string
  expiry: string
  cvv: string
  brand: string
  isValid: boolean
}

function luhn(pan: string): boolean {
  const digits = pan.replace(/\D/g, '')
  let sum = 0
  let alt = false
  for (let i = digits.length - 1; i >= 0; i--) {
    let n = parseInt(digits[i], 10)
    if (alt) { n *= 2; if (n > 9) n -= 9 }
    sum += n
    alt = !alt
  }
  return sum % 10 === 0
}

function detectBrand(pan: string): string {
  const digits = pan.replace(/\D/g, '')
  if (/^4/.test(digits)) return 'visa'
  if (/^5[1-5]/.test(digits)) return 'mastercard'
  if (/^3[47]/.test(digits)) return 'amex'
  return 'unknown'
}

export function useCardValidation() {
  const [card, setCard] = useState<CardState>({
    number: '', expiry: '', cvv: '', brand: 'unknown', isValid: false,
  })

  const setNumber = useCallback((raw: string) => {
    const digits = raw.replace(/\D/g, '').slice(0, 16)
    const formatted = digits.replace(/(\d{4})(?=\d)/g, '$1 ')
    setCard(prev => ({
      ...prev,
      number:  formatted,
      brand:   detectBrand(digits),
      isValid: digits.length >= 13 && luhn(digits),
    }))
  }, [])

  const setExpiry = useCallback((raw: string) => {
    const digits = raw.replace(/\D/g, '').slice(0, 4)
    const formatted = digits.length >= 3 ? `${digits.slice(0, 2)}/${digits.slice(2)}` : digits
    setCard(prev => ({ ...prev, expiry: formatted }))
  }, [])

  const setCvv = useCallback((raw: string) => {
    const digits = raw.replace(/\D/g, '').slice(0, 4)
    setCard(prev => ({ ...prev, cvv: digits }))
  }, [])

  return { card, setNumber, setExpiry, setCvv }
}
```

---

## PaymentSessionContext

```typescript
// context/PaymentSessionContext.tsx
import { createContext, useContext, useState, type ReactNode } from 'react'

interface PaymentSession {
  sessionId:  string
  merchantId: string
  amount:     number
  currency:   string
  orderRef:   string
}

interface PaymentSessionContextValue {
  session:      PaymentSession | null
  setSession:   (session: PaymentSession) => void
  clearSession: () => void
}

const PaymentSessionContext = createContext<PaymentSessionContextValue | null>(null)

export function PaymentSessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<PaymentSession | null>(null)

  return (
    <PaymentSessionContext.Provider value={{
      session,
      setSession,
      clearSession: () => setSession(null),
    }}>
      {children}
    </PaymentSessionContext.Provider>
  )
}

export function usePaymentSession() {
  const ctx = useContext(PaymentSessionContext)
  if (!ctx) throw new Error('usePaymentSession must be used within PaymentSessionProvider')
  return ctx
}

// Never store card numbers, CVV, or expiry in context
```

---

## React Query for Transactions

Cache invalidates automatically after a new payment so the transaction list refreshes without a manual reload.

```typescript
// queries/useTransactions.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'

export function useTransactionHistory(merchantId: string, page = 1) {
  return useQuery({
    queryKey: ['transactions', merchantId, page],
    queryFn: async () => {
      const res = await fetch(`/api/v1/transactions?merchant_id=${merchantId}&page=${page}`)
      if (!res.ok) throw new Error('Failed to load transactions')
      return res.json()
    },
    staleTime: 30_000,
  })
}

export function useCreatePayment() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (payload: unknown) => {
      const res = await fetch('/api/v1/payments', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': crypto.randomUUID(),
        },
        body: JSON.stringify(payload),
      })
      if (!res.ok) throw await res.json()
      return res.json()
    },
    onSuccess: (_, variables: any) => {
      // Invalidate transaction list for this merchant after payment
      queryClient.invalidateQueries({ queryKey: ['transactions', variables.merchant_id] })
    },
  })
}
```

---

## PaymentErrorBoundary

```tsx
// components/PaymentErrorBoundary.tsx
import { Component, type ReactNode, type ErrorInfo } from 'react'

interface Props { children: ReactNode; fallback?: ReactNode }
interface State { hasError: boolean; error: Error | null }

export class PaymentErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // Log to monitoring — but not card data
    console.error('[PaymentErrorBoundary]', error.message, info.componentStack)
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback ?? (
        <div role="alert">
          <p>Payment could not be processed. Please refresh and try again.</p>
        </div>
      )
    }
    return this.props.children
  }
}

// Usage:
// <PaymentErrorBoundary fallback={<PaymentFailedScreen />}>
//   <PaymentForm />
// </PaymentErrorBoundary>
```

---

## Payment Status Polling with Stop Condition

```typescript
// Stop polling once a terminal status is reached — approved or declined
export function usePaymentStatus(paymentId: string) {
  return useQuery({
    queryKey: ['payment-status', paymentId],
    queryFn: async () => {
      const res = await fetch(`/api/v1/payments/${paymentId}`)
      return res.json()
    },
    refetchInterval: (data) => {
      if (data?.data?.status === 'approved' || data?.data?.status === 'declined') {
        return false // stop polling
      }
      return 2000 // poll every 2s while pending
    },
    staleTime: 0,
  })
}
```

---

## Best Practices

- **`crypto.randomUUID()` per submit call** — generates a fresh idempotency key for each attempt; prevents accidental double-charge on retry
- **Context holds session metadata, not card data** — `sessionId`, `merchantId`, `amount`; card state lives only in `useCardValidation` during entry
- **`useCallback` on handlers passed as props** — prevents child re-renders during payment form input
- **`queryClient.invalidateQueries` on payment success** — keeps the transaction list consistent without a manual refresh
- **Stop-polling pattern** — `refetchInterval` returns `false` on terminal status; avoids unnecessary requests after completion
- **Error boundary on every payment form** — runtime errors in payment components must not crash the whole page
