# claude-code-fintech-stack

> Battle-tested Claude Code configuration for fintech and payment engineering — PHP/Laravel, Go, ISO 8583, Vue/React/Vite, Node.js/Bun, and AI integration.

This plugin encodes hard-won knowledge from building production payment gateways: the gotchas in PHP services that process thousands of transactions per hour, the Go socket clients talking to banking hosts, the Vue forms that must never retain a card number beyond the current session, and the ISO 8583 bitmaps that break silently when you get byte order wrong.

---

## What's Inside

- **20+ specialized agents** — domain-expert AI sub-personalities for PHP/Laravel, Go, ISO 8583, Vue, React, Node, security, and AI integration
- **25+ skills** — auto-invocable modules covering TDD, security review, payment protocols, PCI audit, onboarding, and memory management
- **30+ slash commands** — manually triggered workflows for common fintech dev tasks
- **Language rules** — coding standards for PHP 8.3+, Go 1.22+, JavaScript ES2024, Vue 3, React 18, Node.js 22, ISO 8583
- **Cursor IDE hooks** — auto-formatting, PCI safety guards, and quality gates wired into your editor
- **PCI-DSS aware hooks** — shell hooks that block raw cardholder data writes before they reach disk or logs
- **MCP server configuration** — ready-to-use connections to payment gateway, Git, database, and search MCP servers
- **Real-world examples** — worked examples from payment gateway development for each stack layer

---

## Quick Install

### Via Claude Code Plugin Marketplace

```bash
/plugin marketplace add PuvaanRaaj/claude-code-fintech-stack
/plugin install claude-code-fintech-stack@claude-code-fintech-stack
```

### Manual Install

```bash
git clone https://github.com/PuvaanRaaj/claude-code-fintech-stack
cd claude-code-fintech-stack

# Install Claude Code agents and skills
cp -r .claude/* ~/.claude/

# Install Cursor IDE rules and hooks
cp -r rules ~/.cursor/rules
cp -r .cursor/rules ~/.cursor/rules
cp -r .cursor/hooks ~/.cursor/hooks
```

### Per-Project Install (recommended)

```bash
# Clone into your project root
git clone https://github.com/PuvaanRaaj/claude-code-fintech-stack .fintech-stack

# Symlink or copy into project .claude/
cp -r .fintech-stack/.claude/skills .claude/
cp -r .fintech-stack/.claude/commands .claude/

# Add hooks to your project settings
cat .fintech-stack/hooks/hooks.json >> .claude/settings.local.json
```

---

## Agents

Agents are domain-expert AI sub-personalities. They activate when you reference their domain, or you can invoke them explicitly with `@agent-name`.

| Agent | Purpose | Trigger |
|---|---|---|
| `php-laravel-agent` | PHP 8.3+ / Laravel 11+ development — Eloquent, queues, jobs, services, API resources | `@php-laravel-agent` or when editing `.php` files |
| `go-agent` | Go microservices, goroutines, channels, error wrapping, TCP clients | `@go-agent` or when editing `.go` files |
| `iso8583-agent` | ISO 8583 message construction, MTI codes, bitmap parsing, EMV TLV, field requirements | `@iso8583-agent` or when ISO 8583 terms appear |
| `payment-security-agent` | PCI-DSS controls, HSM integration, key management, cardholder data flow | `@payment-security-agent` or when PCI topics appear |
| `vue-agent` | Vue 3 Composition API, Pinia, Vue Router, payment forms, reactive state | `@vue-agent` or when editing `.vue` files |
| `react-agent` | React 18 hooks, payment UI components, server components, form handling | `@react-agent` or when editing `.tsx/.jsx` files |
| `vite-agent` | Vite 5 config, plugins, build optimization, chunk splitting, env vars | `@vite-agent` or when editing `vite.config.*` |
| `node-agent` | Node.js 22 APIs, streams, workers, Express/Fastify endpoints | `@node-agent` or when editing Node.js services |
| `bun-agent` | Bun 1.x runtime, Bun.serve, Bun.file, Bun shell scripts, test runner | `@bun-agent` or when `bun` tooling is in scope |
| `ai-integration-agent` | Anthropic SDK, Claude API, streaming, tool use, agent orchestration | `@ai-integration-agent` or when Claude API code appears |
| `security-reviewer-agent` | OWASP Top 10, SQL injection, XSS, SSRF, auth bypass, secrets in code | `@security-reviewer-agent` for security review tasks |
| `database-agent` | MySQL 8, PostgreSQL 16, query optimization, indexes, migrations, transactions | `@database-agent` or when SQL/migrations are in scope |
| `devops-agent` | Docker multi-arch, Kubernetes, GitHub Actions CI, deployment pipelines | `@devops-agent` or when infra/config files are in scope |
| `testing-agent` | PHPUnit, Pest, Go testing, Jest, Playwright — TDD workflow, coverage targets | `@testing-agent` or when test files are in scope |
| `api-design-agent` | REST API design, OpenAPI/Swagger, versioning, pagination, error contracts | `@api-design-agent` when designing new API endpoints |
| `queue-worker-agent` | Laravel queues, Redis, job design, retry logic, dead letter handling | `@queue-worker-agent` when working with jobs/queues |
| `tcp-socket-agent` | TCP socket clients for payment hosts, framing, keep-alive, reconnect logic | `@tcp-socket-agent` when writing socket communication code |
| `emv-agent` | EMV chip, contactless, tokenisation, 3DS 2.x, cryptogram validation | `@emv-agent` when EMV/chip/3DS topics arise |
| `scheme-agent` | Visa, Mastercard, AMEX, MyDebit scheme rules, interchange, settlement | `@scheme-agent` when working with card scheme integrations |
| `logging-agent` | Structured logging, PCI-safe log design, log levels, observability | `@logging-agent` when designing or auditing logging code |
| `migration-agent` | Database migrations, zero-downtime deploys, rollback safety | `@migration-agent` when writing or reviewing migrations |

---

## Skills

Skills are auto-invocable modules. Claude activates them when context matches — no explicit trigger needed. You can also say the trigger phrase directly.

| Skill | Trigger Phrase | What It Does |
|---|---|---|
| `pci-review` | "review this for PCI" / "check PCI compliance" | Full PCI-DSS audit of payment code: logging safety, cardholder data exposure, key handling |
| `iso8583-parse` | "parse this ISO message" / "decode this hex" | Decodes ISO 8583 hex, extracts MTI, bitmap, fields, and explains each field value |
| `iso8583-build` | "build an ISO 8583 message" / "construct a purchase request" | Constructs a valid ISO 8583 message for a given MTI/scheme with required fields |
| `payment-endpoint` | "create a payment endpoint" / "add a charge route" | Scaffolds a PCI-compliant PHP/Go payment endpoint with validation, logging, and error handling |
| `tdd-cycle` | "write tests first" / "TDD this" | Red-green-refactor cycle — writes failing test, implements minimum code, refactors |
| `security-review` | "review for security" / "check for vulnerabilities" | OWASP Top 10 review: injection, auth, XSS, SSRF, secrets, misconfiguration |
| `log-audit` | "audit the logs" / "check if logs are PCI safe" | Scans logging calls for cardholder data, PAN, CVV, PIN — flags violations |
| `swagger-gen` | "generate swagger" / "update API docs" | Regenerates OpenAPI/Swagger docs, checks for missing annotations on new endpoints |
| `onboard` | "onboard a new dev" / "generate onboarding doc" | Produces a developer onboarding document from codebase memory and architecture |
| `rca` | "why is this failing" / "root cause this" | Traces a bug or incident to root cause using logs, tests, and code context |
| `task-plan` | "plan this task" / "how do I implement X" | Breaks a development task into steps informed by codebase context |
| `done-task` | "I'm done" / "wrap up this session" | Extracts learnings from the session and persists them to shared memory |
| `changelog` | "generate changelog" / "what changed" | Produces a changelog from recent commits and branch memory |
| `review` | "review my changes" / "self-review before commit" | Reviews staged changes for gotchas, missing tests, hardcoded values |
| `trace` | "trace this request" / "how does a purchase flow" | Traces a payment scheme request through the full codebase |
| `explain` | "what does this file do" / "explain this module" | Explains a file or module using memory and code context |
| `remember` | "remember this" / "save this to memory" | Persists a specific learning to shared codebase memory |
| `debt` | "what's the tech debt here" / "flag code smells" | Identifies and logs technical debt in current files |
| `compact-memory` | "compact memory" / "memory is too long" | Compresses and deduplicates memory files when context grows too large |
| `setup` | "set up my local environment" | Runs full local dev setup: dependencies, .env, migrations, test verification |
| `hotfix` | "apply a hotfix" / "urgent prod bug" | Diagnoses root cause, applies minimal fix, commits with [HOTFIX] prefix |
| `spec` | "draft a spec" / "write a technical spec" | Drafts a technical specification from a one-liner description |
| `adr` | "record this decision" / "write an ADR" | Writes an Architecture Decision Record and saves it to memory |
| `why` | "why is it written this way" / "why does this exist" | Explains code decisions using memory and git history |
| `sync-memory` | "sync memory" / "rebuild context files" | Regenerates CLAUDE.md and .cursorrules from /memory/ |

---

## Commands

Slash commands are manually triggered via `/command-name`. They perform multi-step workflows.

| Command | Description |
|---|---|
| `/done-task` | End-of-session: extract learnings, update memory, clean up branch context |
| `/compact-memory` | Compress and deduplicate all memory files; regenerate CLAUDE.md index |
| `/branch-context` | Load current branch memory into context at session start |
| `/archive-branch` | Archive branch memory after merging — run as part of merge checklist |
| `/pci-audit` | Run full PCI-DSS audit on the current working tree |
| `/iso8583-decode` | Decode a hex ISO 8583 message interactively |
| `/iso8583-build` | Build an ISO 8583 message for a given MTI and scheme |
| `/payment-flow` | Generate a sequence diagram of a payment scheme request flow |
| `/new-scheme` | Scaffold a new payment scheme integration (fields, handler, tests) |
| `/new-endpoint` | Scaffold a new PCI-compliant API endpoint with validation and logging |
| `/new-job` | Scaffold a new Laravel queue job with retry logic and dead-letter handling |
| `/tcp-client` | Scaffold a Go TCP client for a payment host with framing and reconnect |
| `/emv-parse` | Parse an EMV TLV hex string and explain each tag |
| `/review-pr` | Full PR review: security, PCI, logic, test coverage, style |
| `/security-scan` | OWASP scan of staged changes |
| `/log-check` | Check all log calls in changed files for PCI data leaks |
| `/test-run` | Run test suite (PHPUnit/Pest/Go/Jest) and parse failures |
| `/swagger-update` | Regenerate OpenAPI docs for changed endpoints |
| `/changelog-gen` | Generate changelog from commits since last release tag |
| `/onboard-doc` | Generate developer onboarding doc from codebase memory |
| `/rca` | Root cause analysis from error trace or failing test |
| `/hotfix` | Apply minimal targeted hotfix with [HOTFIX] commit prefix |
| `/spec-draft` | Draft a technical specification document |
| `/adr-write` | Write an Architecture Decision Record to memory |
| `/db-migrate` | Generate and validate a zero-downtime database migration |
| `/docker-build` | Build and verify multi-arch Docker image |
| `/deploy-check` | Pre-deployment checklist: migrations, config, feature flags |
| `/load-context` | Load session context from memory for current branch |
| `/save-context` | Save current session learnings to memory immediately |
| `/sync-rules` | Sync language rules to .cursorrules and Cursor hooks |

---

## Rules

Language-specific coding standards enforced as files in `rules/` and `.cursor/rules/`.

| Rule File | Language / Domain | Key Standards |
|---|---|---|
| `rules/php.md` | PHP 8.3+ | Strict types, readonly props, match expressions, never suppress errors, no `dd()` in payment code |
| `rules/laravel.md` | Laravel 11+ | Service layer pattern, typed Eloquent models, form requests for validation, resource classes for API responses |
| `rules/go.md` | Go 1.22+ | Error wrapping with `%w`, context propagation, no naked goroutines, structured logging with `slog` |
| `rules/iso8583.md` | ISO 8583 protocol | Field length encoding, bitmap construction, MTI byte order, EBCDIC vs ASCII host differences |
| `rules/javascript.md` | JavaScript ES2024 | ESM-only, no `var`, explicit return types in JSDoc, no implicit `any` equivalents |
| `rules/vue.md` | Vue 3 | Composition API only, `<script setup>`, Pinia for state, no card data in component state beyond input lifetime |
| `rules/react.md` | React 18 | Function components only, hooks rules, no card data in component state, `useId` for form accessibility |
| `rules/node.md` | Node.js 22 | ESM, `--experimental-vm-modules`, streams over buffers for large payloads, worker threads for CPU work |
| `rules/bun.md` | Bun 1.x | Bun-native APIs preferred, `Bun.serve` over Express when possible, `bun:test` for unit tests |
| `rules/security.md` | Cross-cutting | No secrets in code, TLS always verified, card data masked in all outputs, HSM for key operations |
| `rules/testing.md` | All stacks | Test file co-location, AAA structure, no production data in fixtures, mocked payment host in tests |
| `rules/logging.md` | All stacks | Structured JSON logs, PAN always masked, CVV never logged, correlation ID on every request |

---

## Hooks

Hooks run automatically before or after Claude actions. Shell hooks live in `hooks/`; Cursor hooks live in `.cursor/hooks/`.

### Claude Code Hooks

| Hook | Trigger | What It Does |
|---|---|---|
| `block-pci-data.sh` | `PreToolUse: Write` | Blocks writes containing patterns matching raw PAN, CVV, PIN, or track data |
| `block-env-files.sh` | `PreToolUse: Read,Grep` | Blocks reads on `.env`, `.env.*`, `.envrc` files |
| `block-sensitive-files.sh` | `PreToolUse: Read,Grep` | Blocks reads on known sensitive filenames: `global.inc`, `RDS.inc`, `credentials`, private keys |
| `mask-log-output.sh` | `PostToolUse: Bash` | Post-processes bash output to mask 16-digit card numbers before they appear in context |
| `validate-migration.sh` | `PreToolUse: Write` | Validates new migration files have `up()` and `down()` methods before writing |
| `check-test-coverage.sh` | `PostToolUse: Bash` | After test runs, warns if coverage drops below configured threshold |

### Cursor IDE Hooks

| Hook | Type | What It Does |
|---|---|---|
| `pci-guard.js` | Save hook | Scans file content on save for PAN/CVV patterns; blocks save and highlights violations |
| `php-format.js` | Save hook | Runs `php-cs-fixer` on PHP files on save using project config |
| `go-format.js` | Save hook | Runs `gofmt` and `goimports` on Go files on save |
| `js-format.js` | Save hook | Runs `prettier` then `eslint --fix` on JS/TS/Vue files on save |
| `migration-lint.js` | Save hook | Checks migration files for `down()` method and warns on destructive operations |

---

## MCP Servers

Configured MCP servers provide Claude direct access to external systems without copy-pasting.

| Server | Purpose | Config Location |
|---|---|---|
| `github` | Read PRs, issues, commits, and diffs from GitHub repositories | `.claude/mcp/github.json` |
| `gitlab` | Read MRs, issues, pipelines, and diffs from GitLab | `.claude/mcp/gitlab.json` |
| `postgres` | Run read-only SQL queries against a PostgreSQL database | `.claude/mcp/postgres.json` |
| `mysql` | Run read-only SQL queries against a MySQL 8 database | `.claude/mcp/mysql.json` |
| `filesystem` | Read project files with awareness of PCI exclusions | `.claude/mcp/filesystem.json` |
| `brave-search` | Search the web for documentation, CVEs, and payment standards | `.claude/mcp/brave-search.json` |
| `redis` | Inspect Redis queues, cache keys, and job states | `.claude/mcp/redis.json` |

---

## Stack Coverage

| Technology | Agents | Skills | Rules |
|---|---|---|---|
| PHP 8.3+ / Laravel 11+ | `php-laravel-agent`, `queue-worker-agent`, `migration-agent` | `payment-endpoint`, `tdd-cycle`, `log-audit` | `rules/php.md`, `rules/laravel.md` |
| Go 1.22+ | `go-agent`, `tcp-socket-agent` | `tdd-cycle`, `security-review` | `rules/go.md` |
| ISO 8583 | `iso8583-agent`, `emv-agent`, `scheme-agent`, `tcp-socket-agent` | `iso8583-parse`, `iso8583-build`, `trace` | `rules/iso8583.md` |
| Vue 3 | `vue-agent`, `vite-agent` | `tdd-cycle`, `security-review` | `rules/vue.md` |
| React 18 | `react-agent`, `vite-agent` | `tdd-cycle`, `security-review` | `rules/react.md` |
| Vite 5 | `vite-agent` | — | — |
| Node.js 22 / Bun 1.x | `node-agent`, `bun-agent` | `tdd-cycle`, `security-review` | `rules/node.md`, `rules/bun.md` |
| AI / Claude API | `ai-integration-agent` | `spec`, `task-plan` | — |
| PCI-DSS / Security | `payment-security-agent`, `security-reviewer-agent`, `logging-agent` | `pci-review`, `log-audit`, `security-review` | `rules/security.md`, `rules/logging.md` |
| Database | `database-agent`, `migration-agent` | `db-migrate`, `rca` | — |
| DevOps / Docker | `devops-agent` | `setup`, `hotfix` | — |

---

## PCI-DSS Safety

This plugin treats PCI-DSS compliance as a first-class concern, not an afterthought.

### What Gets Blocked

The `block-pci-data.sh` hook intercepts all `Write` operations and scans content for:

- **Primary Account Numbers (PAN)** — 13–19 digit sequences matching Luhn-valid card number patterns
- **CVV/CVC values** — 3–4 digit sequences appearing adjacent to card-related field names
- **PIN blocks** — hex-encoded PIN block patterns (ISO 9564 Format 0, 1, 3, 4)
- **Track 1 / Track 2 data** — magnetic stripe data patterns (`%B...^`, `;...=`)
- **Cryptographic keys** — raw key material patterns appearing in application code (not key management systems)

When a violation is detected, the hook:
1. Blocks the write and returns a non-zero exit code
2. Prints the line number and pattern that triggered the block
3. Suggests the correct approach (masking, tokenisation, or using the HSM)

### What's Safe

- **Masked PAN** — `4111 **** **** 1111` or `411111******1111` patterns are allowed
- **Tokens** — non-card-format references to transactions (UUIDs, opaque token strings)
- **Test card numbers** — known test PANs (`4111111111111111`, `5500000000000004`) are flagged with a warning, not a hard block
- **Key references** — key IDs and key check values (KCVs) are allowed; raw key bytes are not

### Hook Configuration

```json
{
  "hooks": [
    {
      "event": "PreToolUse",
      "tools": ["Write"],
      "script": "hooks/block-pci-data.sh"
    }
  ]
}
```

The hook script is at `hooks/block-pci-data.sh`. It reads the file content from the tool input JSON, runs pattern matching, and exits non-zero on any violation.

### Cursor IDE PCI Guard

The `.cursor/hooks/pci-guard.js` hook provides the same protection in the Cursor editor — scanning file content on every save and blocking the save operation when violations are detected. It highlights the offending lines in the editor.

### Why This Matters

Under PCI DSS v4.0 Requirement 3, storing sensitive authentication data (SAD) after authorisation is prohibited. A developer accidentally logging a full PAN in a debug statement, or saving card data to a temporary file, is a compliance incident — regardless of intent. These hooks make the default safe: you have to explicitly bypass them to write raw card data, which means you have to make a conscious decision to do so.

---

## Examples

The `examples/` directory contains worked examples for each stack layer:

| Example | Stack | What It Shows |
|---|---|---|
| `examples/php/purchase-controller.php` | PHP/Laravel | PCI-compliant purchase endpoint with tokenised card reference |
| `examples/php/iso8583-service.php` | PHP/Laravel | ISO 8583 message construction service |
| `examples/go/tcp-client.go` | Go | TCP socket client for payment host with framing and reconnect |
| `examples/go/iso8583-parser.go` | Go | ISO 8583 message parser with bitmap extraction |
| `examples/vue/payment-form.vue` | Vue 3 | Payment form that clears card fields after submission |
| `examples/react/payment-form.tsx` | React 18 | Payment form with PCI-safe state management |
| `examples/node/webhook-handler.js` | Node.js | Payment gateway webhook handler with signature verification |

---

## Contributing

Contributions are welcome. Before opening a PR:

1. Run `bash tests/test-plugin.sh` to validate plugin.json
2. Run `bash tests/test-skills.sh` to validate all skills load correctly
3. Run `bash tests/test-hooks.sh` to verify hook scripts exit correctly
4. Follow the commit message format: `type(scope): subject` — see CLAUDE.md
5. Add a real-world example in `examples/` for any new agent or skill

For security-related changes (hooks, PCI rules), include a test case in `tests/` that demonstrates the pattern being blocked.

---

## License

MIT — see LICENSE file.

Built with real payment gateway experience. Use it to move faster without cutting corners.
