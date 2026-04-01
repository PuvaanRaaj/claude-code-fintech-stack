---
name: changelog
description: Generate a changelog from recent commits — categorised by feat/fix/chore/security
allowed_tools: ["Bash", "Read", "Write"]
---

# /changelog

## Goal
Generate a structured changelog from recent git commits. Groups changes by type (feat, fix, security, chore) and formats for inclusion in CHANGELOG.md.

## Steps
1. Determine the range:
   - Since last tag: `git log $(git describe --tags --abbrev=0)..HEAD --oneline`
   - Or last 30 commits: `git log --oneline -30`
2. Get full commit list with types:
   ```bash
   git log $(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD~30")..HEAD \
     --format="%h %s" --no-merges
   ```
3. Categorise commits by conventional commit type:
   - `feat:` → Added
   - `fix:` → Fixed
   - `security:` or `fix(security):` → Security
   - `refactor:` → Changed
   - `chore:` / `docs:` → Maintenance
   - `test:` → omit from user-facing changelog
4. Format as Keep a Changelog style:
   ```markdown
   ## [Unreleased] — 2024-01-15

   ### Added
   - POST /api/v1/payments/{id}/refund endpoint for partial and full refunds

   ### Fixed
   - Idempotency key not validated on refund endpoint
   - Timeout returns correct `pending` status instead of `error`

   ### Security
   - Upgraded dependency X from 1.2.0 to 1.3.1 (CVE-2024-1234)

   ### Changed
   - Transaction status `timeout` renamed to `pending` for clarity
   ```
5. Prepend to `CHANGELOG.md` under `## [Unreleased]`

## Output
Formatted changelog section ready to paste into `CHANGELOG.md`, or written directly to the file.
