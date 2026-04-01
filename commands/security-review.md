---
name: security-review
description: Security and PCI review of current files — OWASP Top 10 + payment-specific issues
allowed_tools: ["Bash", "Read", "Grep", "Glob"]
---

# /security-review

## Goal
Run a comprehensive security review covering OWASP Top 10 (payment-adapted) and PCI-DSS requirements. Identify issues before they reach production.

## Steps
1. Determine scope: current file, `git diff --staged`, or entire `app/` directory
2. Run automated scans:
   ```bash
   # Debug output
   grep -rn "dd(\|var_dump\|print_r\|console\.log" app/ src/
   # Disabled TLS
   grep -rn "CURLOPT_SSL_VERIFYPEER.*false\|InsecureSkipVerify.*true\|verify.*=.*False" .
   # PAN patterns
   grep -rn -E '\b4[0-9]{12,15}\b|\b5[1-5][0-9]{14}\b|\b3[47][0-9]{13}\b' app/ src/
   # Hardcoded secrets
   grep -rn -Ei '(secret|password|token|key)\s*=\s*["\x27][^"\x27]{8,}' app/
   # Raw SQL
   grep -rn "DB::statement\|whereRaw\|selectRaw\|->raw(" app/
   # Discarded Go errors
   grep -rn "_ = " ./ --include="*.go"
   ```
3. Run `composer audit` (PHP) or `govulncheck ./...` (Go) for dependency vulnerabilities
4. Check OWASP A01–A10 for payment-adapted risks
5. Check PCI-DSS: CHD handling, encryption, audit logging, access control
6. Assign severity: CRITICAL / HIGH / MEDIUM / LOW
7. Output findings table and overall verdict

## Output
```
SECURITY REVIEW
────────────────────────────────────────────────────────────────────
Severity  File:Line                         Issue                     Fix
────────────────────────────────────────────────────────────────────
CRITICAL  app/Host/Client.php:44            TLS verify disabled       Set to true
HIGH      internal/host/client.go:31        Error discarded           Handle error
MEDIUM    app/Models/Transaction.php:20     PAN in log message        Mask to last 4
LOW       app/Services/PayService.php:10    Missing return type       Add: Transaction
────────────────────────────────────────────────────────────────────
PCI CHD scan:       PASS — no raw PAN patterns found
Dependency audit:   PASS — 0 vulnerabilities
OWASP A01-A10:      2 findings (see above)
────────────────────────────────────────────────────────────────────
VERDICT: BLOCKED — resolve CRITICAL before merge
```
