---
name: spec
description: Draft a technical spec from a one-line description — covers requirements, architecture, API design, test plan
allowed_tools: ["Bash", "Read", "Grep", "Glob"]
---

# /spec

## Goal
Turn a one-line feature description into a structured technical specification. Covers functional requirements, architecture decisions, API design, data model, and test plan. Used before implementation starts.

## Steps
1. Take the feature description from the user's message
2. Search codebase for related existing code to understand constraints
3. Draft the spec with these sections:

### Spec Sections
**Overview** — what this feature does and why (2-3 sentences)

**Functional Requirements** — numbered list of must-haves

**Out of Scope** — explicit exclusions to prevent scope creep

**Architecture** — how it fits into existing layers (controller → service → repo → model)

**Data Model** — new tables, columns, or schema changes

**API Design** — endpoint, method, request/response shapes, error codes

**Idempotency** — how duplicate requests are handled

**Security** — PCI considerations, auth requirements, audit logging

**Test Plan**:
- Unit tests: which classes
- Feature tests: which scenarios (approved, declined, timeout, duplicate)
- E2E: which user flow

**Open Questions** — decisions not yet made that need input

4. Output the spec as a markdown document
5. Optionally write to `docs/specs/{feature-name}.md`

## Output
```
TECHNICAL SPEC: {feature name}
════════════════════════════════════════════════

## Overview
...

## Functional Requirements
1.
2.
3.

## Out of Scope
- ...

## Architecture
...

## API Design
POST /api/v1/...
Request: ...
Response: ...

## Test Plan
- Unit: ...
- Feature: approved / declined / timeout
- E2E: ...

## Open Questions
- [ ] ...
════════════════════════════════════════════════
```
