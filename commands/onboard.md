---
name: onboard
description: Generate onboarding documentation for this project from codebase context
allowed_tools: ["Bash", "Read", "Grep", "Glob"]
---

# /onboard

## Goal
Generate a comprehensive onboarding document for a new developer joining this project. Covers architecture, local setup, key concepts, coding standards, and where to start.

## Steps
1. Read `CLAUDE.md` for project context
2. Read `memory/core/` files for architecture, decisions, conventions
3. Scan codebase structure:
   - `app/` or `internal/` — main application code
   - `tests/` — test structure
   - `routes/` or `cmd/` — entry points
   - `database/migrations/` — schema history
4. Find the most recent commit that added a significant feature (context for "how things get done here")
5. Read `docker-compose.yml` for local services
6. Identify the payment flow entry point and trace it one level
7. Compose the document covering:
   - What this service does (2-3 sentences)
   - Tech stack with versions
   - Local setup steps
   - Key architectural concepts (layering, patterns used)
   - Where to find things (important file paths)
   - How to run tests
   - Coding standards summary
   - Who to ask / where to find decisions
8. Write to `docs/ONBOARDING.md` (or output inline if no docs/ directory)

## Output
Produces a `docs/ONBOARDING.md` (or equivalent) covering:
- Project purpose
- Stack and versions
- Quick start (5 commands to get running)
- Architecture overview
- Key file paths
- Test suite commands
- Standards summary
- Links to ADRs and memory files
