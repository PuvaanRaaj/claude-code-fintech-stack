# Vite 5 Rules

## Environment Variables

All client-exposed environment variables must be prefixed with `VITE_`:

```ts
// Correct — only VITE_ vars are exposed to the browser bundle
const apiBase = import.meta.env.VITE_API_BASE_URL
const featureFlag = import.meta.env.VITE_ENABLE_SANDBOX === 'true'

// Incorrect — non-VITE_ vars are undefined in the browser
const secret = import.meta.env.PAYMENT_SECRET_KEY  // undefined at runtime
```

Never prefix secret keys with `VITE_` — they will be bundled into the client.
Server-only vars (e.g., `DATABASE_URL`, `PAYMENT_SECRET_KEY`) must have no `VITE_` prefix.

## Entry Point Strategy

Single entry for SPA: `index.html` at project root. Vite auto-discovers it.
For multi-page or SSR: declare explicitly in `vite.config.ts`:

```ts
export default defineConfig({
  build: {
    rollupOptions: {
      input: {
        main: 'index.html',
        admin: 'admin/index.html',
      },
    },
  },
})
```

## Aliases Configuration

Define path aliases in `vite.config.ts` and mirror in `tsconfig.json`:

```ts
// vite.config.ts
import { defineConfig } from 'vite'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      '@components': fileURLToPath(new URL('./src/components', import.meta.url)),
      '@composables': fileURLToPath(new URL('./src/composables', import.meta.url)),
      '@types': fileURLToPath(new URL('./src/types', import.meta.url)),
    },
  },
})
```

```json
// tsconfig.json paths section
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./src/*"],
      "@components/*": ["./src/components/*"]
    }
  }
}
```

## Dynamic Imports for Code Splitting

Use dynamic `import()` for route-level code splitting and heavy components:

```ts
// Route-level splitting (Vue Router)
const PaymentHistory = () => import('@/pages/PaymentHistory.vue')
const AdminDashboard = () => import('@/pages/AdminDashboard.vue')

// Lazy-load heavy chart library
const ChartComponent = defineAsyncComponent(() =>
  import('@/components/charts/TransactionChart.vue')
)
```

Do not lazy-load components that are always visible above the fold (adds latency).

## define for Build-Time Constants

Use Vite's `define` for build-time constant replacement:

```ts
// vite.config.ts
export default defineConfig({
  define: {
    __APP_VERSION__: JSON.stringify(process.env.npm_package_version),
    __BUILD_DATE__: JSON.stringify(new Date().toISOString()),
    __IS_PROD__: process.env.NODE_ENV === 'production',
  },
})
```

Declare in `env.d.ts` for TypeScript:
```ts
declare const __APP_VERSION__: string
declare const __BUILD_DATE__: string
declare const __IS_PROD__: boolean
```

## laravel-vite-plugin Integration

For Laravel projects with Vite frontend:

```ts
// vite.config.ts
import { defineConfig } from 'vite'
import laravel from 'laravel-vite-plugin'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [
    laravel({
      input: ['resources/css/app.css', 'resources/js/app.ts'],
      refresh: true,  // auto-reload on Blade/PHP changes
    }),
    vue(),
  ],
  server: {
    host: '0.0.0.0',
    hmr: {
      host: 'localhost',
    },
  },
})
```

Run with: `npm run dev` (starts Vite dev server alongside `php artisan serve`).

## CSS Patterns

- Use CSS modules for component-scoped styles: `<style module>` in Vue, or `*.module.css` files
- Global styles: `src/assets/css/app.css`, imported once in `main.ts`
- PostCSS config: `postcss.config.js` with `tailwindcss` and `autoprefixer`
- Never use `@import` inside scoped component CSS for global files (causes duplication)
- CSS variables for design tokens: defined in `:root` in global CSS, consumed via `var(--color-primary)`
