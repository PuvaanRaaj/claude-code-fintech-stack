---
name: vue-component
description: Scaffold a Vue 3 Composition API component following project conventions. Supports forms, lists, modals, and payment UI patterns.
argument-hint: <component name and purpose>
---

Create a new Vue 3 component. Auto-triggers on "create component", "Vue form", "add UI for X".

## Trigger Phrases
"create component", "Vue component", "add form", "build UI for", "scaffold Vue"

## Steps

1. **Read existing components** — Glob `src/components/**/*.vue` to understand naming and style conventions used in this project

2. **Determine component type** from $ARGUMENTS:
   - Form component → include `defineEmits` with `submit`/`cancel`
   - Display component → props-only, no emits
   - Input wrapper → support `v-model` via `modelValue` prop + `update:modelValue` emit
   - Payment form → apply PCI-safe patterns (no raw card state retained)

3. **Scaffold component**:
   ```vue
   <script setup lang="ts">
   interface Props {
     // typed props
   }
   const props = defineProps<Props>()
   const emit = defineEmits<{
     submit: [payload: PayloadType]
     cancel: []
   }>()
   </script>

   <template>
     <!-- semantic HTML + Tailwind -->
   </template>
   ```

4. **Payment form specifics** (when building payment UI):
   - Card number: `autocomplete="cc-number"`, mask after blur to last 4 digits
   - CVV: `autocomplete="cc-csc"`, clear from state after submit
   - Expiry: `autocomplete="cc-exp"`, format as MM/YY
   - Submit emits tokenized payload — never raw PAN
   - `role="alert"` on error messages

5. **Add composable** if reusable state logic detected (card validation, form state)

6. **Write component** to appropriate path under `src/components/` or as specified

## Output Format
- Single `.vue` file with `<script setup lang="ts">`, `<template>`, optional `<style>`
- Companion composable file if applicable
- Usage example snippet
