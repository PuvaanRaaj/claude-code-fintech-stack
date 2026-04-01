---
name: search-first
description: Search the codebase for existing implementations, helpers, and git history before writing new code — prevents duplication and re-introducing intentionally removed patterns.
origin: fintech-stack
---

# Search First

Writing new code when an equivalent already exists creates duplication, diverges behaviour, and wastes time. In payment codebases this is especially costly — a second implementation of card masking or amount formatting that behaves slightly differently becomes a data inconsistency in reports and logs. Always search before you write.

## When to Activate

- Before writing any new service class, helper, trait, or utility function
- Before adding a dependency that might already be present
- When a task sounds familiar ("add card validation", "format amount", "mask PAN")
- Automatically at the start of any implementation task

---

## Search for Existing Service Classes

```bash
# PHP — service classes matching the domain
grep -rn "class.*Service" app/Services/ --include="*.php" | grep -i "payment\|card\|transaction"

# Go equivalent
grep -rn "type.*Service struct" ./ --include="*.go"
```

## Search for Helpers, Traits, and Utility Functions

```bash
# PHP
find app/ -name "*.php" | xargs grep -l "trait\|Helper\|Utility" 2>/dev/null
grep -rn "function formatAmount\|function maskCard\|function luhn" app/

# Go
grep -rn "^func Format\|^func Mask\|^func Validate" ./ --include="*.go"
```

## Look at Adjacent Files

```bash
# If working on PaymentController, read similar controllers first
ls app/Http/Controllers/

# If working on a Go handler, read existing handlers
ls internal/handler/
```

## Check Git History for Removed Code

```bash
# Was this file deleted recently?
git log --all --full-history -- "app/Services/CardValidationService.php"

# Search commit messages
git log --oneline --all | grep -i "card\|payment\|validation"

# Show what was in a deleted file
git show HEAD~1:app/Services/OldPaymentService.php 2>/dev/null

# Search all commits for a function name
git grep "function validateCard" $(git rev-list --all)
```

## Check Dependencies

```bash
# Already have a package for this?
cat composer.json | grep -i "card\|payment\|validation"
go list -m all | grep -i "payment\|card"
```

## Document Findings Before Proceeding

After searching, summarise:

```
SEARCH RESULTS
────────────────────────────────────────────────
Query: card validation logic

Found (reusable):
  app/Services/CardService.php       — has luhn() and getBrand() methods
  app/Helpers/CardHelper.php         — has maskPan() and formatExpiry()

Found (partial — needs extension):
  app/Rules/CardNumberRule.php       — validates format but not Luhn
  → Extend this rather than creating a new CardValidationRule

Not found (needs creation):
  - BIN lookup service
  - 3DS eligibility check

Git history note:
  CardValidator.php deleted in commit a3f2b1c (2023-08-10)
  Reason: "remove legacy card validator — replaced by Stripe Elements"
  → Do NOT recreate; current approach uses tokenisation instead

────────────────────────────────────────────────
PLAN:
  Reuse:   CardService::luhn(), CardHelper::maskPan()
  Extend:  CardNumberRule — add Luhn check
  Create:  BinLookupService (new)
```

---

## Best Practices

- **Search git history before concluding something doesn't exist** — it may have been deleted intentionally; re-adding it recreates the problem that led to its removal
- **Read one adjacent file before writing** — the naming convention and patterns in a similar file tell you more than any style guide
- **If you find two implementations, merge them before writing a third** — escalate the duplication as a separate refactor task
- **`grep` for the concept, not the class name** — search for `maskPan` not `CardHelper`; the implementation may live anywhere
