# CLAUDE.md

## Project Overview

This is the `claude-code-fintech-stack` plugin — a Claude Code plugin for fintech and payment engineering teams. Stack: PHP 8.3+/Laravel 11+, Go 1.22+, ISO 8583, Vue 3, React 18, Vite 5, Node.js 22, Bun 1.x, and AI/Claude API integration. Not an application — a plugin repo to be installed into target projects. Users install it via the Claude Code plugin marketplace or by copying files manually.

## Common Commands

```bash
# Validate plugin.json structure and required fields
bash tests/test-plugin.sh

# Validate all skills load and have required SKILL.md files
bash tests/test-skills.sh

# Test hook scripts exit correctly for clean and violating inputs
bash tests/test-hooks.sh

# Verify all scripts in scripts/ are executable and syntactically valid
bash tests/test-scripts.sh

# Run the full test suite
bash tests/run-all.sh
```

## Architecture

```
agents/              — 20+ agent pairs (.md definition + .json config)
.claude/skills/      — auto-invocable skill modules (one dir per skill, SKILL.md inside)
commands/            — slash command definitions (.md per command)
rules/               — language/domain coding standards (php.md, go.md, iso8583.md, etc.)
.cursor/rules/       — Cursor IDE rule files (same content, different format expected by Cursor)
.cursor/hooks/       — Cursor IDE hooks (JavaScript, run on file save)
hooks/               — Claude Code hooks (shell scripts + hooks.json config)
scripts/             — standalone lint/validation/test runner scripts
examples/            — worked real-world examples per stack layer
tests/               — test scripts for validating the plugin itself
plugin.json          — plugin manifest (agents, skills, version)
```

### Key Relationships

- `plugin.json` references agents as explicit file paths and skills as directory paths
- `hooks/hooks.json` is auto-loaded by Claude Code — never add a `hooks` key to `plugin.json`
- Skills in `.claude/skills/` activate automatically when context matches the trigger in SKILL.md
- Commands in `commands/` are invoked manually via `/command-name`
- Rules in `rules/` are reference docs; `.cursor/rules/` are the same content in Cursor format

## Working Style

- Plan before coding for any task with 3+ steps or architectural impact
- Use subagents for research, file exploration, and parallel analysis — keep main context clean
- Verify before marking done — run tests, check diffs, confirm hook scripts exit correctly
- Minimal impact — a new agent doesn't need a refactor of existing ones; fix only what's needed
- When adding a skill, add a corresponding test in `tests/test-skills.sh`
- When adding a hook, add a corresponding test case in `tests/test-hooks.sh`

## Commit Message Format

```
type(scope): subject line under 72 chars
```

Types: `feat` | `fix` | `chore` | `docs` | `test`

Scopes: `agents` | `skills` | `commands` | `rules` | `hooks` | `cursor` | `tests` | `plugin`

Body (optional): what changed and why; rollback steps if non-trivial.

Trailers:
```bash
git commit \
  --trailer "Risk-Level: low|medium|high" \
  --trailer "AI-Agent: claude-sonnet-4-6" \
  -m "feat(agents): add emv-agent for EMV TLV and 3DS workflows"
```

## Plugin Schema Rules

- `agents` in plugin.json must be an array of explicit file paths (e.g. `"agents/php-laravel-agent.md"`)
- `skills` must be an array of directory paths (e.g. `".claude/skills/pci-review"`)
- Never add a `hooks` key to plugin.json — hooks are auto-loaded from `hooks/hooks.json`
- `version` field is mandatory in plugin.json and must follow semver
- Each agent `.md` file must have a corresponding `.json` config file with the same base name
- Each skill directory must contain a `SKILL.md` file — this is what Claude Code loads

## PCI Safety Rules

- Never write raw PAN, CVV, PIN, or track data anywhere in this repo — including test fixtures
- Use known test card numbers (`4111111111111111`) in examples only, always labelled as test data
- Hook scripts must be deterministic and fast — they run on every write operation
- The `block-pci-data.sh` hook is a hard gate; do not weaken its patterns without a documented reason

## Decisions

Non-obvious decisions are documented in `memory/core/decisions.md`. Key standing decisions:

- Hooks use shell scripts (not JS) for maximum portability and minimal dependency surface
- Agent definitions are split into `.md` (human-readable) and `.json` (machine config) for clarity
- Skills auto-activate; commands are manual — this distinction is intentional and must be preserved
- Rules are duplicated into `.cursor/rules/` because Cursor and Claude Code use different file conventions
