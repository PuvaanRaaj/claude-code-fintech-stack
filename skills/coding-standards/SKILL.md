---
name: coding-standards
description: Coding standards for PHP (PSR-12 + Laravel), Go, and TypeScript payment codebases — strict types, error wrapping, interface naming, commit message format, branch naming, and pre-commit checklist.
origin: fintech-stack
---

# Coding Standards

Consistent standards across PHP, Go, and TypeScript make payment code auditable: a reviewer can spot a missing `declare(strict_types=1)` or an unhandled error immediately because every file follows the same shape.

## When to Activate

- Developer asks "does this follow standards?", "fix formatting", or "check style"
- Before commit or PR — apply the pre-commit checklist
- When onboarding new code to the repository

---

## PHP (PSR-12 + Laravel)

```php
<?php declare(strict_types=1);  // always first line

namespace App\Services\Payment;

use App\DTOs\PaymentDto;
use App\Models\Transaction;
use App\Repositories\TransactionRepository;

final class PaymentService
{
    public function __construct(
        private readonly TransactionRepository $transactions,
    ) {}

    // Return types required on all methods
    public function process(PaymentDto $dto): Transaction
    {
        // ...
    }

    public function buildSummary(int $amount, string $currency): string
    {
        return sprintf('%s %.2f', $currency, $amount / 100);
    }
}
```

**Rules:**
- `declare(strict_types=1)` on every file
- Explicit return types on every method (including `void`)
- Constructor promotion with `readonly` for injected dependencies
- `final` on service classes unless extension is intended
- No `public` properties — use getters or readonly
- `use` statements alphabetically sorted
- Run Pint before every commit: `./vendor/bin/pint`
- PHPStan level 8 must pass: `./vendor/bin/phpstan analyse`

---

## Go

```go
package payment  // lowercase, single word, no underscores

import (
    // stdlib first
    "context"
    "fmt"

    // third-party second (blank line separates groups)
    "github.com/prometheus/client_golang/prometheus"
)

// Service handles payment authorisation against the upstream host.
type Service struct {
    host   HostClient
    repo   TransactionRepository
    logger *slog.Logger
}

// NewService constructs a Service. All dependencies are required.
func NewService(host HostClient, repo TransactionRepository, logger *slog.Logger) *Service {
    return &Service{host: host, repo: repo, logger: logger}
}

// Process initiates a payment authorisation and persists the result.
func (s *Service) Process(ctx context.Context, p Payment) (*Transaction, error) {
    resp, err := s.host.Authorise(ctx, p)
    if err != nil {
        return nil, fmt.Errorf("host authorise: %w", err) // always wrap errors
    }
    return s.repo.Create(ctx, p, resp)
}
```

**Rules:**
- `gofmt` applied before every commit — zero tolerance
- `go vet` must pass
- All errors handled — never `_ = err` in production code
- `fmt.Errorf("context: %w", err)` to wrap errors
- `context` as first parameter in all exported functions that do I/O
- Package names: lowercase, no underscores, no plurals
- Interface names: single method → `{Verb}er` (e.g., `Authoriser`, `Storer`)
- `golangci-lint run` must pass

---

## TypeScript

```typescript
// strict TypeScript — no `any`
import { type PaymentRequest, type PaymentResponse } from '@/types/payment'

export async function processPayment(request: PaymentRequest): Promise<PaymentResponse> {
  const response = await fetch('/api/v1/payments', {
    method: 'POST',
    headers: {
      'Content-Type':    'application/json',
      'Idempotency-Key': request.idempotencyKey,
    },
    body: JSON.stringify(request),
  })

  if (!response.ok) {
    throw new PaymentError(await response.json())
  }

  return response.json() as Promise<PaymentResponse>
}
```

**Rules:**
- `strict: true` in `tsconfig.json` — no `any` types
- Explicit return types on all exported functions
- No `console.log` — use structured logger
- ESLint must pass: `bun x eslint . --max-warnings 0`
- Prettier formatting enforced
- `useEffect` hooks must return a cleanup function when they set up subscriptions or timers

---

## Commit Message Format

```
<type>(<scope>): <subject>   ← max 72 chars, imperative mood

Body: what changed and why. Risk / rollback if non-trivial.

Risk-Level: low|medium|high
AI-Agent: claude-sonnet-4-6
```

Types: `feat` | `fix` | `refactor` | `chore` | `docs` | `test`

---

## Branch Naming

```
feat/payment-reversal-flow
fix/timeout-handling-host-connect
chore/upgrade-laravel-11
```

---

## Pre-Commit Checklist

- [ ] `declare(strict_types=1)` present (PHP)
- [ ] Return types on all methods (PHP)
- [ ] `gofmt` applied (Go)
- [ ] Errors handled, not discarded (Go)
- [ ] No `dd()`, `var_dump()`, `console.log` left in
- [ ] No hardcoded secrets or credentials
- [ ] Tests written for new behaviour
- [ ] Commit message follows format above

---

## Best Practices

- **Report violations by file and line** — "Standards check: X violations — run `./vendor/bin/pint && gofmt -w .` to auto-fix formatting"
- **PHPStan level 8** — catches nullability and type errors that strict_types alone misses
- **`golangci-lint`** — enforces error handling and unused imports that `go vet` skips
- **No `any` in TypeScript** — payment response types must be explicit; `any` hides card data leaks
- **Alphabetical `use` imports in PHP** — makes diff reviews cleaner and avoids duplicate import conflicts
