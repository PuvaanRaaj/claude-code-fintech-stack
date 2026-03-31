# Bun 1.x Rules

## bun.lock Commit Policy

`bun.lock` must be committed to the repository and must not be in `.gitignore`.

```bash
# Correct — commit bun.lock
git add bun.lock
git commit -m "chore(deps): update bun.lock"

# Incorrect — gitignoring bun.lock breaks reproducible installs
echo "bun.lock" >> .gitignore  # NEVER do this
```

When resolving merge conflicts in `bun.lock`: delete it and run `bun install` to regenerate. Never hand-edit `bun.lock`.

## Bun.file() and Bun.write() Preference

Use Bun's native file APIs instead of Node.js `fs` when running under Bun — they are significantly faster:

```ts
// Correct — Bun native file API
const file = Bun.file('./config/settings.json')
const config = await file.json()
const text = await file.text()
const buffer = await file.arrayBuffer()

// Write
await Bun.write('./output/report.json', JSON.stringify(data, null, 2))
await Bun.write('./output/receipt.pdf', pdfBuffer)

// Stream a large file
const stream = Bun.file('./large-export.csv').stream()
```

Fall back to `node:fs` only for operations Bun.file doesn't support (e.g., `watch`, `mkdir`).

## bun:test API

Use Bun's native test runner. Do not install Vitest or Jest in Bun projects.

```ts
// test/payment.test.ts
import { describe, it, expect, beforeEach, afterEach, mock } from 'bun:test'
import { PaymentService } from '../src/services/PaymentService.js'

describe('PaymentService', () => {
  let service: PaymentService

  beforeEach(() => {
    service = new PaymentService()
  })

  it('masks PAN in response', async () => {
    const result = await service.process({ pan: '4111111111111111', amount: 100 })
    expect(result.maskedPan).toBe('411111****1111')
    expect(result).not.toHaveProperty('pan')  // raw PAN must not be in result
  })

  it('throws on invalid amount', () => {
    expect(() => service.process({ pan: '4111111111111111', amount: -1 }))
      .toThrow('amount must be positive')
  })
})
```

Run tests: `bun test` or `bun test --watch` for development.
Coverage: `bun test --coverage` (built-in, no extra config).

## Bun.serve() and Bun.connect()

Use Bun's native HTTP and TCP servers for new Node.js services:

```ts
// HTTP server
const server = Bun.serve({
  port: 3000,
  async fetch(req) {
    const url = new URL(req.url)
    if (url.pathname === '/health') {
      return Response.json({ status: 'ok' })
    }
    return new Response('Not Found', { status: 404 })
  },
  error(err) {
    console.error('Server error:', err)
    return new Response('Internal Server Error', { status: 500 })
  },
})

console.log(`Listening on ${server.url}`)
```

```ts
// TCP client for ISO 8583 payment host
const conn = await Bun.connect({
  hostname: process.env.PAYMENT_HOST!,
  port: parseInt(process.env.PAYMENT_PORT!),
  socket: {
    data(socket, data) {
      handleHostResponse(data)
    },
    error(socket, err) {
      console.error('Socket error:', err)
    },
    close(socket) {
      console.log('Connection closed, reconnecting...')
    },
  },
})
```

## No Mixing bun and npm Installs

A project must use one package manager. Detect and enforce:

- Bun project: `bun.lock` present → use `bun install`, `bun add`, `bun remove`
- npm project: `package-lock.json` present → use `npm install`, `npm install --save`
- Both present: error state — delete one lockfile and reinstall from scratch

```bash
# If both exist, clean up:
rm package-lock.json
bun install  # regenerates bun.lock from package.json
```

CI scripts must use `bun install --frozen-lockfile` to prevent accidental lockfile mutations.

## TypeScript Native Compilation

Bun compiles TypeScript natively — no `tsc` build step required for running:

```bash
# Run TypeScript directly
bun run src/index.ts

# Type-check only (Bun does not type-check, use tsc for CI)
bunx tsc --noEmit
```

For production builds that output JavaScript (e.g., for Docker or npm publishing):
```bash
bun build ./src/index.ts --outdir ./dist --target=bun --sourcemap=external
```

`tsconfig.json` must include:
```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "types": ["bun-types"]
  }
}
```
