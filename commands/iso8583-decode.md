---
name: iso8583-decode
description: Decode an ISO 8583 hex message — shows MTI, bitmap fields, F55 EMV TLV breakdown
allowed_tools: ["Bash", "Read"]
---

# /iso8583-decode

## Goal
Decode a raw ISO 8583 hex message and display it in a readable format. Shows the MTI, primary/secondary bitmap, field values, and F55 EMV TLV breakdown if present.

## Steps
1. Accept the hex string from the user (with or without spaces/dashes)
2. Strip whitespace and normalise to uppercase hex
3. Parse structure:
   - Bytes 0–3: Message Length Indicator (2-byte big-endian if present)
   - Bytes 0–1 (or 2–3): MTI — 4 BCD digits
   - Next 8 bytes: Primary Bitmap (64 bits)
   - If bit 1 set: next 8 bytes are Secondary Bitmap
   - Remaining bytes: field data per ISO 8583 field definitions
4. For each set bit in bitmap, parse the corresponding field:
   - Fixed-length fields: F2 (19), F3 (6), F4 (12), F7 (10), F11 (6), F12 (6), F13 (4), F14 (4), F22 (3), F25 (2), F37 (12), F38 (6), F39 (2), F41 (8), F42 (15)
   - Variable-length fields: F35 (LL), F45 (LL), F55 (LLL), F62 (LLL)
5. If F55 present: parse as EMV TLV data and expand each tag
6. Flag PCI-sensitive fields: F2 (PAN), F35 (Track 2), F45 (Track 1) — mask in output

## Output
```
ISO 8583 DECODE
────────────────────────────────────────────────
MTI:  0200  (Financial Transaction Request)
────────────────────────────────────────────────
Bitmap (Primary):   7234000080200000
  Bit 01: OFF (no secondary bitmap)
  Bit 02: ON  — F02 PAN
  Bit 03: ON  — F03 Processing Code
  Bit 04: ON  — F04 Amount, Transaction
  ...
────────────────────────────────────────────────
F02  PAN                   4111 **** **** 1111   [MASKED]
F03  Processing Code       000000  (Purchase)
F04  Amount, Transaction   000000001000  (MYR 10.00)
F07  Transmission DateTime 0115103000
F11  STAN                  000001
F12  Local Time            103000
F13  Local Date            0115
F14  Expiry Date           2612  [MASKED]
F22  POS Entry Mode        051  (Chip + PIN)
F25  POS Condition Code    00
F37  Retrieval Ref No.     000000000001
F41  Terminal ID           TERM0001
F42  Merchant ID           MERCH000000001
────────────────────────────────────────────────
F55  ICC Data (EMV TLV):
  9F26  Application Cryptogram    A1B2C3D4E5F60718
  9F10  Issuer Application Data   0110A00000...
  9F37  Unpredictable Number      1A2B3C4D
  9F36  Application Transaction Counter  0042
  95    Terminal Verification Results    0000000000
  9A    Transaction Date          240115
  9C    Transaction Type          00
  5F2A  Transaction Currency Code 0458 (MYR)
────────────────────────────────────────────────
```
