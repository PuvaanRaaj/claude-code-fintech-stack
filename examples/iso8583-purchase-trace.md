# ISO 8583 Purchase Trace: Visa Card-Present 0200/0210

A complete walkthrough of a Visa chip card purchase request and response, with field-by-field decode, response handling, and auto-reversal logic.

## The Scenario

- Terminal: attended POS, chip+PIN
- Merchant: retail, MCC 5411 (grocery)
- Amount: MYR 125.50 (12550 in minor units)
- Currency: MYR (ISO 4217 numeric: 458)

## 0200 Purchase Request Hex Stream

```
0200                   -- MTI: Financial Transaction Request
7234054128C18200       -- Primary bitmap (8 bytes)
0000000000000000       -- Secondary bitmap (fields 65-128 not used here)
```

**Full message hex** (whitespace added for readability):
```
0200
7234 0541 28C1 8200
16 4111111111111111
000000
000000012550
0321143022
123456
143022
0321
0101
22 011
01 00
37 4111111111111111 D2503201000000000
123456789012
        GROCERY STORE       KUALA LUMPUR MY
MYR
82 0200
84 A0000000031010
95 0000000000
9A 260321
9C 00
9F02 000000012550
9F10 06010A03A00000
9F1A 0458
9F26 A1B2C3D4E5F6A7B8
9F27 80
9F36 0042
9F37 A9B8C7D6
```

## Field-by-Field Decode Table

| Field | Name | Raw Value | Decoded |
|-------|------|-----------|---------|
| MTI | Message Type Indicator | 0200 | Financial Transaction Request (Purchase) |
| Bitmap | Primary Bitmap | 7234054128C18200 | Fields 2,3,4,7,11,12,13,22,25,35,37,38,39,41,42,49,55 set |
| F2 | PAN | 4111111111111111 | **411111\*\*\*\*1111** (masked) |
| F3 | Processing Code | 000000 | 00=Purchase, 00=Savings, 00=Savings |
| F4 | Transaction Amount | 000000012550 | **125.50** (12550 minor units) |
| F7 | Transmission Date/Time | 0321143022 | Mar 21, 14:30:22 UTC |
| F11 | STAN | 123456 | System Trace Audit Number: 123456 |
| F12 | Local Time | 143022 | 14:30:22 local |
| F13 | Local Date | 0321 | March 21 |
| F14 | Expiry Date | 2503 | **2025-03** (YYMM) |
| F22 | POS Entry Mode | 051 | 05=Chip read (ICC), 1=PIN capable |
| F25 | POS Condition Code | 00 | Normal transaction, attended terminal |
| F35 | Track 2 Equivalent | ;4111...=2503... | **[MASKED — track 2 never logged]** |
| F37 | Retrieval Reference Number | 123456789012 | Acquirer RRN — echoed in response |
| F41 | Terminal ID | TERM0001 | POS Terminal ID |
| F42 | Merchant ID | MERCH123456789 | Merchant ID (15 chars) |
| F43 | Card Acceptor Name | GROCERY STORE KL | Display name and location |
| F49 | Currency Code | 458 | MYR (Malaysian Ringgit) |
| F55 | EMV / ICC Data | [binary TLV] | See TLV decode below |

## Field 55 — EMV TLV Breakdown

| Tag | Name | Value | Decoded |
|-----|------|-------|---------|
| 82 | Application Interchange Profile | 0200 | SDA supported, cardholder verification required |
| 84 | Dedicated File Name (AID) | A0000000031010 | Visa Credit/Debit |
| 95 | Terminal Verification Results | 0000000000 | No issues — all checks passed |
| 9A | Transaction Date | 260321 | 2026-03-21 |
| 9C | Transaction Type | 00 | Purchase |
| 9F02 | Authorized Amount | 000000012550 | MYR 125.50 |
| 9F10 | Issuer Application Data | 06010A03A00000 | Issuer-proprietary CVR and counters |
| 9F1A | Terminal Country Code | 0458 | Malaysia (ISO 3166: 458) |
| 9F26 | Application Cryptogram | A1B2C3D4E5F6A7B8 | ARQC — sent to issuer for online auth |
| 9F27 | Cryptogram Information Data | 80 | 0x80 = ARQC (online auth requested) |
| 9F36 | Application Transaction Counter | 0042 | ATC = 66 — replay protection |
| 9F37 | Unpredictable Number | A9B8C7D6 | Terminal random — part of AC input |

### 9F27 CID Values
| Hex | Meaning |
|-----|---------|
| 80 | ARQC — online authorization requested |
| 40 | TC — transaction certificate (offline approved) |
| 00 | AAC — application authentication cryptogram (offline declined) |

## 0210 Financial Transaction Response — Expected Fields

| Field | Name | Value | Decoded |
|-------|------|-------|---------|
| MTI | Message Type | 0210 | Financial Transaction Response |
| F2 | PAN | (echoed) | Masked in logs |
| F3 | Processing Code | 000000 | Echoed |
| F4 | Amount | 000000012550 | Echoed — 125.50 |
| F7 | Transmission Date | Echoed | |
| F11 | STAN | 123456 | Must match request |
| F12 | Local Time | Echoed | |
| F13 | Local Date | Echoed | |
| F37 | RRN | 123456789012 | Must match request |
| F38 | Authorization ID Response | 663412 | **Approval code** — store for receipt |
| F39 | Response Code | **00** | **Approved** |
| F41 | Terminal ID | Echoed | |
| F42 | Merchant ID | Echoed | |
| F49 | Currency | 458 | Echoed |
| F55 | EMV Response Data | [ARPC TLV] | Issuer authentication of terminal |

### F55 Response TLV (from issuer)

| Tag | Name | Value | Decoded |
|-----|------|-------|---------|
| 8A | Authorization Response Code | 3030 | ASCII "00" = approved |
| 91 | Issuer Authentication Data | [16 bytes] | ARPC — terminal verifies issuer |
| 71 | Issuer Script Template 1 | (optional) | Post-issuance script for card update |
| 72 | Issuer Script Template 2 | (optional) | Post-issuance script |

## What Each Critical Field Means

**F11 STAN** — System Trace Audit Number. Generated by acquirer. Used to match request/response pairs. Must be unique per originator per calendar day. Used in reversal to identify the original transaction.

**F37 RRN** — Retrieval Reference Number. 12-character acquirer-assigned reference. Echoed verbatim in every response and advice. Used by merchant reconciliation and dispute handling.

**F38 Approval Code** — Only present on approved (F39=00) responses. Printed on receipt. Required for voice auth fallback.

**F39 Response Code** — The definitive outcome. `00` = approved. Anything else = not approved. See response code table in `rules/iso8583/bitmap-fields.md` for full list.

**9F26 ARQC** — Application Request Cryptogram. The card's digital signature over this transaction's data (amount, ATC, unpredictable number). Verified online by the issuer. Prevents card cloning.

**9F36 ATC** — Application Transaction Counter. Increments on every transaction. Issuer checks this is higher than last seen — detects replay attacks.

## Auto-Reversal on No Response

If the terminal sends a 0200 but does not receive a 0210 within the configured timeout (typically 30s):

**CRITICAL RULE**: The transaction status is unknown. The issuer may have approved it. Do NOT retry the 0200 — that risks a duplicate charge.

**Action: send a 0400 Reversal Request**

```
MTI: 0400
F2:  Original PAN
F3:  Original processing code (000000)
F4:  Original amount (000000012550)
F11: NEW STAN (different from original)
F37: NEW RRN
F90: Original Data Elements (original MTI + STAN + date + acquirer BIN)
     "0200" + "123456" + "0321" + "000000000000" = "020012345603210000000000000"
```

**F90 format**: Original MTI (4) + Original STAN (6) + Original date (4) + Original acquirer ID (11) + Original forwarding ID (11) = 36 chars total.

The reversal must be sent even if the terminal reset or was powered off. Queue it persistently and retry until acknowledged.

## Retry Policy

| Scenario | Action |
|----------|--------|
| No response within 30s | Send 0400 reversal, do NOT re-send 0200 |
| F39=91 (issuer unavailable) | Retry 0200 up to 2 times with 5s backoff |
| F39=96 (system malfunction) | Retry once, then decline |
| F39=05,57 (do not honor) | Hard decline, no retry |
| Network disconnect after write | Assume sent — send reversal before retrying |
