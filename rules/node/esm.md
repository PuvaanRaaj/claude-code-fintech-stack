# Node.js ESM Rules

## type: module in package.json

All Node.js projects must declare ESM as the default module system:

```json
{
  "type": "module",
  "engines": { "node": ">=20.0.0" }
}
```

With `"type": "module"`, all `.js` files are treated as ES modules. Use `.cjs` extension for files that must be CommonJS.

## .js Extension on Imports

All relative imports must include the `.js` extension, even when importing `.ts` files (TypeScript resolves `.ts` from `.js`):

```ts
// Correct
import { maskPAN } from './utils/card.js'
import { PaymentService } from '../services/PaymentService.js'
import type { Transaction } from '../types/payment.js'

// Incorrect — missing extension
import { maskPAN } from './utils/card'
import { PaymentService } from '../services/PaymentService'
```

For directory imports, import the `index.js` explicitly:
```ts
import { routes } from './routes/index.js'
```

## import.meta.url for __dirname

`__dirname` and `__filename` are not available in ESM. Use `import.meta.url`:

```ts
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// Common pattern: resolve relative paths
const configPath = join(__dirname, '../config/default.json')
```

For Bun: use `import.meta.dir` directly (Bun-specific shorthand).

## Top-Level Await

ESM supports top-level await in module scope. Use it for async initialization:

```ts
// Correct — top-level await for database connection
import { createPool } from './db/pool.js'

const pool = await createPool({
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
})

export { pool }
```

Only use top-level await in entry points or initialization modules — not in library modules that might be imported in sync contexts.

## exports Field

Define explicit package exports in `package.json` for libraries:

```json
{
  "exports": {
    ".": {
      "import": "./dist/index.js",
      "types": "./dist/index.d.ts"
    },
    "./payment": {
      "import": "./dist/payment/index.js",
      "types": "./dist/payment/index.d.ts"
    }
  },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts"
}
```

The `exports` field restricts which internal paths are importable. Callers cannot import `./dist/internal/secret.js` unless it is explicitly exported.

## No require()

Never use `require()` in ESM files:

```ts
// FORBIDDEN
const fs = require('fs')
const config = require('./config.json')

// Correct
import fs from 'node:fs'
import { readFileSync } from 'node:fs'

// JSON import (Node 22+ with --experimental-json-modules, or use fs)
import config from './config.json' with { type: 'json' }
// Or:
const config = JSON.parse(readFileSync(new URL('./config.json', import.meta.url), 'utf8'))
```

Use `node:` prefix on all Node built-in imports:
```ts
import { createServer } from 'node:http'
import { join } from 'node:path'
import { readFile } from 'node:fs/promises'
```
