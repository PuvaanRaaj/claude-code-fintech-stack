---
name: pci-review
description: PCI-DSS compliance review — cardholder data handling, logging, encryption, access control
allowed_tools: ["Bash", "Read", "Grep", "Glob"]
---

# /pci-review

## Goal
Review code and configuration for PCI-DSS compliance. Covers cardholder data environment (CDE) rules: CHD handling, logging safety, encryption, access control, and audit trails.

## Steps
1. Scan for PAN patterns (must not appear in code, logs, or test fixtures):
   ```bash
   grep -rn -E '\b4[0-9]{12,15}\b|\b5[1-5][0-9]{14}\b|\b3[47][0-9]{13}\b' app/ src/ tests/
   ```
   Exception: masked PANs (e.g., `4111 **** **** 1111`) are acceptable.

2. Scan for CVV/CVC storage (must never be stored after authorisation):
   ```bash
   grep -rn -i "cvv\|cvc\|security.code" app/Models/ app/Http/Requests/ database/
   ```
   Flag any database column or model attribute named cvv/cvc.

3. Check log statements near card-handling code:
   ```bash
   grep -rn "Log::" app/Services/Payment* app/Services/Card*
   grep -rn "->info\|->debug\|->warning\|->error" app/Services/Payment*
   ```
   Verify no PAN, CVV, expiry, or track data is logged.

4. Check TLS enforcement:
   ```bash
   grep -rn "CURLOPT_SSL_VERIFYPEER\|InsecureSkipVerify\|verify.*false" app/ internal/
   ```
   Any `false` or `true` for InsecureSkipVerify = FAIL.

5. Check access control on payment endpoints:
   - All payment routes behind auth middleware
   - Merchant data scoped to authenticated merchant only
   - Admin-only functions behind separate role check

6. Check audit log completeness:
   - Every payment attempt logged (approve + decline + timeout)
   - Log entry includes: timestamp, merchant_id, amount, response_code
   - Log entry does NOT include: full PAN, CVV, track data

7. Check encryption at rest:
   - Card tokens stored (not raw PANs)
   - Encryption key not hardcoded

## Output
```
PCI-DSS REVIEW
────────────────────────────────────────────────────────────────────
Requirement         Status   Detail
────────────────────────────────────────────────────────────────────
No PAN in code      PASS     No raw PAN patterns found
No CVV stored       PASS     No cvv column in migrations
Log safety          FAIL     app/Services/PayService.php:88 logs full PAN
TLS enforced        PASS     CURLOPT_SSL_VERIFYPEER = true
Access control      PASS     Auth middleware on all /payments routes
Audit logging       PASS     All payment events logged
CHD encryption      PASS     Tokens used, no raw PANs stored
────────────────────────────────────────────────────────────────────
FINDINGS: 1 CRITICAL — PAN in log statement
────────────────────────────────────────────────────────────────────
VERDICT: FAIL — resolve log statement before deployment
Fix: mask PAN to last 4 digits before passing to Log::info()
```
