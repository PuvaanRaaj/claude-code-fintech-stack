---
name: plan
description: Plan a feature implementation with phases, risks, and success criteria
allowed_tools: ["Bash", "Read", "Grep", "Glob"]
---

# /plan

## Goal
Create a detailed implementation plan before writing any code. Captures phases, dependencies, risks, and success criteria. Use for any task with 3+ steps or architectural impact.

## Steps
1. Read the task description from the user's last message
2. Search the codebase for related existing code: services, models, routes, migrations
3. Identify what already exists vs what needs to be created
4. Draft phases:
   - Phase 1: Database (migrations, schema changes)
   - Phase 2: Backend (models, services, repositories, jobs)
   - Phase 3: API (controllers, routes, request/resource classes)
   - Phase 4: Frontend (components, composables/hooks, store)
   - Phase 5: Tests (unit, feature, E2E)
5. List risks (breaking changes, PCI surface, migrations on payment tables, performance impact)
6. Define success criteria (what does done look like?)
7. Estimate complexity: Low / Medium / High

## Output
```
IMPLEMENTATION PLAN: {feature name}
────────────────────────────────────────────────
Phase 1 — Database
  [ ] Migration: add X column to transactions table
  [ ] down() method verified

Phase 2 — Backend
  [ ] PaymentService::newMethod()
  [ ] TransactionRepository::query()

Phase 3 — API
  [ ] POST /api/v1/endpoint
  [ ] ProcessXRequest FormRequest
  [ ] XResource response class

Phase 4 — Frontend
  [ ] useX composable / hook
  [ ] XForm component

Phase 5 — Tests
  [ ] Unit: PaymentServiceTest
  [ ] Feature: POST /api/v1/endpoint (approved, declined, timeout)
  [ ] E2E: checkout flow

Risks:
  - Touches transactions table → backup before prod migration
  - New API endpoint → idempotency key required

Success criteria:
  - All tests pass (./vendor/bin/phpunit)
  - Security review passes (no BLOCK findings)
  - E2E checkout flow completes end-to-end

Complexity: Medium
────────────────────────────────────────────────
Proceed? (review plan before starting)
```
