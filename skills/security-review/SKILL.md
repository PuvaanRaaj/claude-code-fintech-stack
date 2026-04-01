---
name: security-review
description: Comprehensive security and PCI-DSS review for payment code — OWASP Top 10, cardholder data exposure, encryption, access control, audit logging, and language-specific vulnerability scans for PHP and Go.
origin: fintech-stack
---

# Security Review

In payment systems, security review is part of the definition of done — not a post-release activity. A single unmasked PAN in a log file is a reportable incident. A disabled TLS check "just for testing" that reaches production is how credentials get stolen. This skill covers the OWASP Top 10 through a payment lens, PCI-DSS specific checks, and language-specific scans.

## When to Activate

- Before merging any code that touches payment processing, card data, or authentication
- When adding new API endpoints, logging configuration, or external service integrations
- Developer asks for "security review", "PCI review", or "OWASP check"

---

## OWASP Top 10 (Payment-Adapted)

| # | Risk | What to check |
|---|------|---------------|
| A01 | Broken Access Control | Auth middleware on all payment routes; merchant scoping on queries |
| A02 | Cryptographic Failures | TLS enforced for host connections; card data encrypted at rest |
| A03 | Injection | Parameterised queries; no raw SQL; validated inputs |
| A04 | Insecure Design | Idempotency keys present; amount validation; currency allowlisting |
| A05 | Security Misconfiguration | `.env` not committed; debug mode off in prod; security headers set |
| A06 | Vulnerable Components | `composer audit`, `npm audit`, `govulncheck` |
| A07 | Auth Failures | Token expiry; rate limiting on auth endpoints; no credential logging |
| A08 | Software Integrity | Signed Docker images; pinned dependency versions |
| A09 | Logging Failures | Audit log for all payment events; no sensitive data in logs |
| A10 | SSRF | Validated URLs for webhooks; allowlisted outbound hosts |

---

## PCI-DSS Checks

**Cardholder Data (CHD):**
- PAN must never appear in logs — grep: `\b4[0-9]{12,15}\b`, `\b5[1-5][0-9]{14}\b`
- CVV/CVC must not be stored after authorisation
- Expiry dates must not be logged
- Only last 4 digits are acceptable in logs and UI

**Encryption:**
- TLS 1.2 minimum for all payment host connections
- AES-256 for card data at rest
- Check for disabled TLS verification: `CURLOPT_SSL_VERIFYPEER`, `InsecureSkipVerify`, `verify=False`

**Access Control:**
- Payment functions require explicit role/permission check
- Admin functions have separate auth from customer-facing APIs
- No shared credentials between environments

**Audit Logging:**
- Every payment attempt logged with timestamp, merchant, amount, response code
- Log entries are immutable (append-only table or external log service)
- Logs contain enough detail to reconstruct the full transaction flow

---

## PHP-Specific Scans

```bash
# Find debug output left in code
grep -rn "dd(" app/ routes/
grep -rn "var_dump\|print_r\|dump(" app/

# Find disabled TLS
grep -rn "CURLOPT_SSL_VERIFYPEER.*false" app/
grep -rn "verify.*false" app/

# Find raw SQL (potential injection)
grep -rn "DB::statement\|whereRaw\|selectRaw\|orderByRaw" app/

# Find hardcoded secrets
grep -rn "sk_live\|pk_live\|password.*=.*['\"]" app/ --include="*.php"

# Find files missing strict_types
grep -rL "declare(strict_types=1)" app/**/*.php
```

---

## Go-Specific Scans

```bash
# Find discarded errors
grep -rn "_ = " ./ --include="*.go" | grep -v "_test.go"

# Find disabled TLS
grep -rn "InsecureSkipVerify.*true" ./ --include="*.go"

# Find potential goroutine leaks
grep -rn "go func" ./ --include="*.go"

# Find missing context propagation
grep -rn "context.Background()" ./ --include="*.go" | grep -v "_test.go"

# Run Go vulnerability scanner
govulncheck ./...
```

---

## Scan for PAN Patterns in Diff

```bash
git diff HEAD~1 | grep -E '\b4[0-9]{12,15}\b|\b5[1-5][0-9]{14}\b|\b3[47][0-9]{13}\b'
```

If any match is found: BLOCK — do not merge. This is a PCI incident.

---

## Review Output Format

```
SECURITY REVIEW FINDINGS
────────────────────────────────────────────────────────────────────
Severity  File:Line                       Issue                       Fix
────────────────────────────────────────────────────────────────────
CRITICAL  app/Payment/HostClient.php:42   TLS verify disabled         Set CURLOPT_SSL_VERIFYPEER true
HIGH      app/Http/Controllers/Pay.php:88 dd() left in code           Remove before merge
HIGH      internal/host/client.go:31      Error discarded             Handle or wrap
MEDIUM    app/Models/Transaction.php:54   Full PAN in log message     Mask to last 4 digits
LOW       app/Services/PayService.php:12  Missing return type hint    Add: string
────────────────────────────────────────────────────────────────────
PCI CHD scan: PASS — no PAN patterns found in diff
OWASP A01-A10: 1 finding (see above)
────────────────────────────────────────────────────────────────────
VERDICT: BLOCKED — resolve CRITICAL and HIGH findings before merge
```

---

## Best Practices

- **PAN in a diff = immediate block** — treat it as a breach scenario; rotate any real credentials in scope
- **Never disable TLS verification for any reason** — "just for testing" environments become production environments
- **Run `composer audit` and `govulncheck` in CI** — dependency vulnerabilities are found after the fact if not automated
- **Audit logs must be immutable** — an append-only table or external logging service; no `UPDATE` or `DELETE` on audit rows
- **Review outbound URLs in webhook handlers** — unvalidated URLs are SSRF waiting to happen; allowlist outbound hosts
