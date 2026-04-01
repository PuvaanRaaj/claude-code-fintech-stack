---
name: learn
description: Extract a reusable pattern from current work and save to skills or memory
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /learn

## Goal
Capture a reusable pattern, technique, or decision from the current work and save it to the right place — either a skill file or a memory file. Makes the pattern available in future sessions.

## Steps
1. Ask (or infer): what is the pattern or learning to capture?
2. Determine the destination:
   - Repeatable workflow → skill file in `skills/{name}/SKILL.md`
   - Project-specific fact → `memory/core/` appropriate file
   - Architectural decision → `memory/core/decisions.md` with rationale
3. If saving to skills:
   - Check if a similar skill already exists: `ls .claude/skills/` or `ls skills/`
   - If skill exists, append to it; if not, create new with full SKILL.md format
4. If saving to memory:
   - Read the appropriate memory file
   - Append one-line fact (no prose)
   - Update index in `memory/MEMORY.md` if new topic
5. Show what was saved

## Output
```
PATTERN SAVED
────────────────────────────────────────────────
Pattern: TCP connection deadline pattern for payment host clients
Saved to: skills/go-patterns/SKILL.md (appended to section 1)

Content added:
  "Always set conn.SetDeadline(ctx.Deadline()) before Read/Write —
   otherwise connection blocks indefinitely on a silent host drop."
────────────────────────────────────────────────
SAVED
```
