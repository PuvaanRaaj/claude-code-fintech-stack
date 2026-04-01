# Settlement Rules Reference

Rules and field reference for T+1 payment settlement in fintech services.

---

## Settlement Timing

| Rule | Value |
|------|-------|
| Business day cutoff | 23:59:59 MYT (UTC+8) |
| Settlement type | T+1 — funds credited next business day |
| Batch generation window | 23:45–23:59 MYT |
| Acquirer submission deadline | 00:30 next day (confirm per acquirer SLA) |

---

## ISO 8583 TC Message Types

| MTI | Purpose |
|-----|---------|
| `0500` | Capture request (individual transaction) |
| `0510` | Capture response |
| `0520` | Batch upload request |
| `0530` | Batch upload response |

Key fields in TC message:
- DE 3: Processing code (`200000` = capture)
- DE 4: Amount (12 digits, minor units)
- DE 11: STAN (System Trace Audit Number)
- DE 12/13: Local transaction time/date
- DE 41: Terminal ID
- DE 42: Merchant ID
- DE 49: Currency code (ISO 4217 numeric, e.g. `458` = MYR)

---

## Settlement File Fields

Fixed-width format, one record per transaction:

| Field | Start | Length | Format | Notes |
|-------|-------|--------|--------|-------|
| Merchant ID | 1 | 15 | AN | Left-padded |
| Terminal ID | 16 | 8 | AN | |
| Batch number | 24 | 6 | N | Zero-padded |
| STAN | 30 | 6 | N | Zero-padded |
| Amount | 36 | 12 | N | Minor units, zero-padded |
| Currency | 48 | 3 | AN | ISO 4217 alpha |
| Transaction date | 51 | 8 | N | YYYYMMDD |
| Transaction time | 59 | 6 | N | HHMMSS |
| Auth code | 65 | 6 | AN | Right-padded |
| Response code | 71 | 2 | AN | `00` = approved |
| Card last 4 | 73 | 4 | N | |

---

## Net vs Gross Settlement

- **Gross**: sum of all approved transaction amounts for the day
- **Net**: gross minus refunds and reversals processed on the same day
- **MDR** (Merchant Discount Rate): deducted by acquirer from gross before crediting merchant
- Report gross in the settlement file; acquirer applies MDR on their side

---

## Validation Rules

- Flag any variance between DB total and file total that exceeds **MYR 0.01** (1 cent)
- Count mismatch of even 1 transaction must be investigated before submission
- Never include `pending`, `reversed`, or `declined` transactions in the batch
- Confirm all transactions in the batch have `auth_code` — transactions without auth codes were not approved

---

## Mismatch Handling

| Type | Action |
|------|--------|
| DB-only (in DB, not in file) | Check if reversed; if not, add to batch |
| File-only (in file, not in DB) | Investigate — possible duplicate or ghost transaction |
| Amount mismatch | Check for partial captures; escalate to acquirer ops |
| Duplicate in file | Flag for acquirer; expect RC `94` on resubmission |

---

## Resubmission Rules

- Wait **24 hours** before resubmitting a rejected batch
- If acquirer returns RC `94` (duplicate batch), confirm receipt before resubmitting — do not resubmit blindly
- Generate a new STAN for every resubmission
- Log resubmission timestamp, reason, and result

---

## Prohibited Actions

- **Never** include partial or pending authorisations in a settlement batch
- **Never** resubmit without confirming the acquirer did not process the original batch
- **Never** modify transaction amounts to resolve a mismatch — investigate the root cause
- **Never** run settlement twice for the same date without confirming the first run failed completely
- **Never** submit a settlement file with a count of zero — treat as an error condition
