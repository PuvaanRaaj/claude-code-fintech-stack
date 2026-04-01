---
name: frontend-review
description: Review Vue/React/Vite code — component patterns, accessibility, PCI-safe forms, bundle efficiency
allowed_tools: ["Bash", "Read", "Grep"]
---

# /frontend-review

## Goal
Review Vue 3 or React 18 code against fintech frontend standards. Checks PCI safety (no raw card data in state), accessibility, TypeScript strictness, and bundle efficiency.

## Steps
1. Run automated checks:
   ```bash
   bun x tsc --noEmit 2>&1                 # TypeScript
   bun x eslint . --max-warnings 0 2>&1    # Lint
   bun run build 2>&1                      # Build (catches bundle errors)
   ```
2. Review changed components/composables for:
   - No `any` types — use explicit types or `unknown`
   - No `console.log` left in
   - No raw card numbers in `ref()`, `useState()`, Pinia stores, or Redux
   - CVV cleared after form submission
   - `useEffect` returns cleanup where subscriptions created (React)
   - Stable keys in `v-for` / `.map()` — not array index unless list is static
3. Payment form checks:
   - Submit button disabled during `isSubmitting` state
   - `aria-busy` attribute set during processing
   - `aria-live="polite"` on payment status container
   - `role="alert"` on error messages
   - Card number masked after blur
4. Vue-specific: `<script setup lang="ts">`, explicit types on `ref<T>`, composable returns named object
5. React-specific: `useCallback` on handlers passed as props, error boundary wrapping payment components
6. Output findings table

## Output
```
FRONTEND REVIEW
────────────────────────────────────────────────────────────────────
Severity  File:Line                          Issue                           Fix
────────────────────────────────────────────────────────────────────
HIGH      src/components/PayForm.vue:44      card number in Pinia store     Never store card data in store
HIGH      src/components/PayForm.tsx:88      console.log left in            Remove
MEDIUM    src/components/PayForm.vue:102     Submit not disabled on submit  Add :disabled="isSubmitting"
LOW       src/composables/usePayment.ts:10   Missing return type on submit  Add: Promise<void>
────────────────────────────────────────────────────────────────────
TypeScript: PASS
ESLint:     1 finding
Build:      PASS
────────────────────────────────────────────────────────────────────
VERDICT: BLOCKED — card data in store is a PCI violation
```
