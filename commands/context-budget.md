---
name: context-budget
description: Check token usage and suggest context compression if approaching limits
allowed_tools: ["Bash", "Read", "Glob"]
---

# /context-budget

## Goal
Assess the current context window usage and recommend compression actions if approaching limits. Helps keep sessions efficient during long implementation tasks.

## Steps
1. Check current memory file sizes:
   ```bash
   wc -l memory/MEMORY.md memory/core/*.md memory/branches/*.md 2>/dev/null | sort -rn
   ```
2. Check `CLAUDE.md` size:
   ```bash
   wc -l CLAUDE.md
   ```
   Warn if over 200 lines.
3. Estimate loaded context from files referenced in MEMORY.md
4. If memory files are large:
   - Identify files over 100 lines that could be compressed
   - List entries that are outdated or superseded
   - Suggest running `/compact-memory` command
5. If branch memory exists for closed branches, suggest archiving:
   ```bash
   ls memory/branches/
   git branch -a | grep -v "$(ls memory/branches/ | sed 's/.md//')"
   ```
6. Recommend actions based on findings

## Output
```
CONTEXT BUDGET
────────────────────────────────────────────────
File                           Lines   Status
────────────────────────────────────────────────
memory/MEMORY.md               185     WARN (close to 200 limit)
memory/core/gotchas.md          62     OK
memory/core/decisions.md        48     OK
memory/core/conventions.md      35     OK
memory/branches/feat-refund.md  88     OK
CLAUDE.md                       142    OK
────────────────────────────────────────────────
Total memory lines: 560

Recommendations:
  1. memory/MEMORY.md is near 200-line limit
     → Run /compact-memory to deduplicate and compress
  2. memory/branches/feat-old-feature.md — branch merged 3 weeks ago
     → Archive with /archive-branch feat-old-feature
────────────────────────────────────────────────
Context health: WARN — action recommended
```
