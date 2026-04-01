# 3DS2 Rules Reference

Rules and field reference for EMV 3DS2 authentication in payment services.

---

## ECI Values

| ECI | Meaning | Scheme |
|-----|---------|--------|
| `05` | Fully authenticated | Visa |
| `02` | Fully authenticated | Mastercard |
| `06` | Attempted — issuer not enrolled | Visa |
| `01` | Attempted — issuer not enrolled | Mastercard |
| `07` | Not authenticated / no 3DS attempted | Visa |
| `00` | Not authenticated / no 3DS attempted | Mastercard |

---

## transStatus Values

| Value | Meaning | Proceed to auth? |
|-------|---------|-----------------|
| `Y` | Fully authenticated | Yes |
| `A` | Attempted | Yes |
| `C` | Challenge required | Only after challenge completes with Y |
| `U` | Unavailable | Fallback to 3DS1 or proceed at risk |
| `N` | Not authenticated | No — hard decline |
| `R` | Rejected by issuer | No — hard decline |

---

## Liability Shift

- ECI `05`/`02` → full liability shift to issuer (chargeback protection)
- ECI `06`/`01` → partial liability shift
- ECI `07`/`00` → no shift — merchant bears chargeback liability
- `transStatus: N` or `R` → no shift; do not authorise

---

## Required Fields for Authorisation

Pass all of these in the authorisation request after successful authentication:

| Field | Description | Format |
|-------|-------------|--------|
| `cavv` | Cardholder Authentication Verification Value | 28-char base64 |
| `eci` | E-Commerce Indicator | 2-digit string |
| `dsTransId` | Directory Server transaction ID | UUID |
| `acsTransId` | ACS transaction ID | UUID |
| `authenticationValue` | Same as CAVV for most schemes | 28-char base64 |
| `threeDsVersion` | 3DS2 version used | e.g. `2.2.0` |

---

## Timeouts and Limits

- ACS must respond to AReq within **10 seconds** — treat timeout as `transStatus: U`
- Cardholder has **10 minutes** to complete a challenge — after that, treat as abandoned (`U`)
- CAVV is single-use — never reuse a CAVV across transactions
- AReq must include `browserInfo` with all 9 required fields — missing fields cause silent ACS failures

---

## Fallback to 3DS1

Trigger 3DS1 fallback when:
- `transStatus: U` received
- ARes contains an `errorCode`
- ACS does not respond within 10 seconds

Never fall back silently — log the reason and the `dsTransId` (if present) before falling back.

---

## Prohibited Actions

- **Never** proceed with authorisation on `transStatus: N` or `R`
- **Never** cache or reuse a CAVV
- **Never** omit `dsTransId` from the authorisation request — required for liability shift evidence
- **Never** treat a challenge timeout as a hard decline — treat as `U` and fall back
- **Never** use a `messageVersion` that the ACS does not support — check ACS capabilities in the ARes
