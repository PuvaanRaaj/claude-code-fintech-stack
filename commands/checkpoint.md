---
name: checkpoint
description: Create a git checkpoint commit with a descriptive message — use during TDD cycles
allowed_tools: ["Bash"]
---

# /checkpoint

## Goal
Create a WIP checkpoint commit during a TDD cycle or long implementation session. Makes it easy to return to a known-good state. Uses the correct commit message format.

## Steps
1. Run `git status` to see what's staged and unstaged
2. Run `git diff --stat` to summarise changes
3. Stage all relevant files (excluding `.env`, secrets, build artifacts):
   ```bash
   git add -p   # interactive staging (preferred)
   # or:
   git add app/ tests/ resources/ internal/ src/
   ```
4. Compose a checkpoint commit message following the format:
   ```
   wip(scope): checkpoint — {brief description of current state}
   ```
5. Commit:
   ```bash
   git commit \
     --trailer "Risk-Level: low" \
     --trailer "AI-Agent: claude-sonnet-4-6" \
     -m "wip(scope): checkpoint — {description}"
   ```
6. Report the commit hash for easy revert reference

## Output
```
CHECKPOINT
────────────────────────────────────────────────
Staged: 4 files
  app/Services/PaymentService.php
  app/Repositories/TransactionRepository.php
  tests/Feature/Payment/ProcessPaymentTest.php (GREEN)
  tests/Unit/Repositories/TransactionRepositoryTest.php (GREEN)
────────────────────────────────────────────────
Commit: abc1234
Message: wip(payment): checkpoint — service and repo complete, tests green

To revert: git reset --hard abc1234
────────────────────────────────────────────────
CHECKPOINT CREATED
```
