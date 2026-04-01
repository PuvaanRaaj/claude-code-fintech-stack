---
name: save-session
description: Save session learnings to memory — patterns, decisions, and gotchas from this session
allowed_tools: ["Bash", "Read", "Write", "Grep"]
---

# /save-session

## Goal
Extract and persist useful learnings from this session to the project's shared memory. Prevents the same discoveries from being made twice.

## Steps
1. Review what was done in this session:
   - What problem was solved?
   - What approach was tried and abandoned?
   - What non-obvious behaviour was discovered?
   - What patterns are now established for this project?
2. Categorise learnings:
   - **Pattern** — reusable implementation approach
   - **Decision** — architectural or design choice with a reason
   - **Gotcha** — non-obvious behaviour or trap to avoid
   - **Convention** — project-specific naming or structure rule
3. Read existing memory files:
   - `memory/core/gotchas.md`
   - `memory/core/decisions.md`
   - `memory/core/conventions.md`
4. Append new entries — one line per fact, no prose
5. Update `memory/MEMORY.md` index if new topics added
6. Check `memory/MEMORY.md` is under 200 lines

## Output
```
SESSION LEARNINGS SAVED
────────────────────────────────────────────────
Saved to memory/core/gotchas.md:
  - Payment host returns 504 for timeout — not a connection error; mark transaction pending
  - Http::fake() must be called before the service is resolved from container

Saved to memory/core/decisions.md:
  - Idempotency keys stored in Redis with 24h TTL (ADR-004)
  - Amount always stored as minor units (integer) — never float

Saved to memory/core/conventions.md:
  - Test file location: tests/Feature/{Domain}/{FeatureName}Test.php
────────────────────────────────────────────────
MEMORY UPDATED
```
