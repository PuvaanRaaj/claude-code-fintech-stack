# ISO 8583 Reference: Bitmaps, Fields, MTI, and EMV

## MTI Reference Table

The Message Type Indicator is 4 decimal digits: `V C F O`
- V = ISO version (0=1987, 1=1993, 2=2003)
- C = Message class
- F = Message function
- O = Message origin

| MTI  | Description |
|------|-------------|
| 0100 | Authorization Request |
| 0110 | Authorization Response |
| 0120 | Authorization Advice |
| 0130 | Authorization Advice Response |
| 0200 | Financial Transaction Request (Purchase) |
| 0210 | Financial Transaction Response |
| 0220 | Financial Transaction Advice |
| 0230 | Financial Transaction Advice Response |
| 0400 | Reversal Request |
| 0410 | Reversal Response |
| 0420 | Reversal Advice |
| 0430 | Reversal Advice Response |
| 0500 | Reconciliation Request |
| 0510 | Reconciliation Response |
| 0600 | Administrative Request |
| 0610 | Administrative Response |
| 0800 | Network Management Request |
| 0810 | Network Management Response |
| 0820 | Network Management Advice |

## Bitmap Construction Algorithm

The primary bitmap covers fields 1–64. The secondary bitmap covers fields 65–128.

**Construction:**
1. Create an 8-byte (64-bit) array, all zeros
2. For each field N (1-64) present in the message: set bit `N-1` in the bitmap (MSB first)
3. If any field 65–128 is present: set bit 0 (field 1 = secondary bitmap indicator)
4. Create second 8-byte array for fields 65–128 the same way

**Bit addressing formula:** Field N → byte index `(N-1) / 8`, bit position `7 - ((N-1) % 8)`

**Example:** Fields 2, 3, 4, 7, 11, 12, 13, 22, 25, 35, 37, 38, 39, 41, 42, 55 present:
```
Byte 1: 0111 0000  (fields 2,3,4 set; field 5,6,7,8 clear) → 0x70
Wait: field 2 = bit index 1, field 3 = bit 2, field 4 = bit 3
Byte 1 bits 7..0 = fields 1..8
Field 2 → bit 6 = 0100 0000 → adds to byte 1
Correct byte 1: fields 2,3,4 → bits 6,5,4 → 0111 0000 → 0x70
```

## Field Dictionary: Fields 1–64

| F# | Name | Type | Len | Format | Notes |
|----|------|------|-----|--------|-------|
| 1  | Secondary Bitmap | b | 8 | Fixed | Present if F65–F128 used |
| 2  | PAN | n | ..19 | LLVAR | Primary Account Number — mask in logs |
| 3  | Processing Code | n | 6 | Fixed | First 2: transaction type; next 2: from acct; last 2: to acct |
| 4  | Transaction Amount | n | 12 | Fixed | In minor currency units, right-aligned, zero-padded |
| 5  | Settlement Amount | n | 12 | Fixed | In settlement currency |
| 6  | Cardholder Billing Amount | n | 12 | Fixed | |
| 7  | Transmission Date/Time | n | 10 | Fixed | MMDDhhmmss |
| 8  | Cardholder Billing Fee Amount | n | 8 | Fixed | |
| 9  | Settlement Conversion Rate | n | 8 | Fixed | |
| 10 | Cardholder Billing Conversion Rate | n | 8 | Fixed | |
| 11 | STAN | n | 6 | Fixed | System Trace Audit Number — unique per originator per day |
| 12 | Local Transaction Time | n | 6 | Fixed | hhmmss |
| 13 | Local Transaction Date | n | 4 | Fixed | MMDD |
| 14 | Expiry Date | n | 4 | Fixed | YYMM — never store with PAN |
| 15 | Settlement Date | n | 4 | Fixed | MMDD |
| 16 | Currency Conversion Date | n | 4 | Fixed | MMDD |
| 17 | Capture Date | n | 4 | Fixed | MMDD |
| 18 | Merchant Category Code | n | 4 | Fixed | MCC — ISO 18245 |
| 19 | Acquiring Institution Country Code | n | 3 | Fixed | ISO 3166 numeric |
| 20 | PAN Extended | n | 3 | Fixed | |
| 21 | Forwarding Institution Country Code | n | 3 | Fixed | |
| 22 | POS Entry Mode | n | 3 | Fixed | First 2: card entry; last 1: PIN capability |
| 23 | Card Sequence Number | n | 3 | Fixed | |
| 24 | Network International ID | n | 3 | Fixed | |
| 25 | POS Condition Code | n | 2 | Fixed | 00=normal, 01=unattended, 08=mail/phone |
| 26 | POS PIN Capture Code | n | 2 | Fixed | |
| 27 | Authorization ID Response Length | n | 1 | Fixed | |
| 28 | Transaction Fee | x+n | 8 | Fixed | |
| 29 | Settlement Fee | x+n | 8 | Fixed | |
| 30 | Transaction Processing Fee | x+n | 8 | Fixed | |
| 31 | Settlement Processing Fee | x+n | 8 | Fixed | |
| 32 | Acquiring Institution ID | n | ..11 | LLVAR | BIN of acquirer |
| 33 | Forwarding Institution ID | n | ..11 | LLVAR | BIN of forwarder |
| 34 | PAN Extended | ns | ..28 | LLVAR | |
| 35 | Track 2 Equivalent | z | ..37 | LLVAR | Mask entirely in logs |
| 36 | Track 3 Equivalent | n | ..104 | LLLVAR | Rarely used |
| 37 | Retrieval Reference Number | an | 12 | Fixed | Acquirer-assigned; echoed in response |
| 38 | Authorization ID Response | an | 6 | Fixed | Approval code from issuer |
| 39 | Response Code | an | 2 | Fixed | 00=approved; see response code table |
| 40 | Service Restriction Code | n | 3 | Fixed | |
| 41 | Card Acceptor Terminal ID | ans | 8 | Fixed | POS terminal ID (TID) |
| 42 | Card Acceptor ID | ans | 15 | Fixed | Merchant ID (MID) |
| 43 | Card Acceptor Name/Location | ans | 40 | Fixed | Merchant name and location |
| 44 | Additional Response Data | an | ..25 | LLVAR | |
| 45 | Track 1 Data | ans | ..76 | LLVAR | Mask in logs |
| 46 | Additional Data (ISO) | an | ...999 | LLLVAR | |
| 47 | Additional Data (National) | an | ...999 | LLLVAR | |
| 48 | Additional Data (Private) | an | ...999 | LLLVAR | Scheme/acquirer-specific |
| 49 | Transaction Currency Code | n | 3 | Fixed | ISO 4217 numeric (e.g., 458=MYR, 840=USD) |
| 50 | Settlement Currency Code | n | 3 | Fixed | |
| 51 | Cardholder Billing Currency Code | n | 3 | Fixed | |
| 52 | PIN Data | b | 8 | Fixed | Encrypted PIN block — never log |
| 53 | Security-Related Control Info | n | 16 | Fixed | |
| 54 | Additional Amounts | an | ..120 | LLVAR | Cash-back, tip, etc. |
| 55 | ICC Data / EMV | b | ...999 | LLLVAR | BER-TLV encoded EMV data |
| 56 | Reserved (ISO) | — | — | — | |
| 57 | Reserved (National) | — | — | — | |
| 58 | Reserved (National) | — | — | — | |
| 59 | Reserved (National) | — | — | — | |
| 60 | Reserved (Private) | an | ...999 | LLLVAR | Acquirer-specific |
| 61 | Reserved (Private) | an | ...999 | LLLVAR | |
| 62 | Reserved (Private) | an | ...999 | LLLVAR | |
| 63 | Reserved (Private) | an | ...999 | LLLVAR | Often used for additional PIN/crypto |
| 64 | MAC (Primary) | b | 8 | Fixed | Message Authentication Code |

## Field Dictionary: Fields 65–128 (Secondary Bitmap)

| F# | Name | Type | Len | Notes |
|----|------|------|-----|-------|
| 65 | Bitmap Tertiary Indicator | b | 1 | Rarely used |
| 66 | Settlement Code | n | 1 | |
| 67 | Extended Payment Data | n | 2 | |
| 70 | Network Management Information Code | n | 3 | 001=sign-on, 002=sign-off, 301=echo |
| 90 | Original Data Elements | n | 42 | For reversals: original MTI, STAN, date, acquirer BIN |
| 95 | Replacement Amounts | n | 42 | |
| 100 | Receiving Institution ID | n | ..11 | LLVAR |
| 102 | Account ID 1 | ans | ..28 | LLVAR |
| 103 | Account ID 2 | ans | ..28 | LLVAR |
| 128 | MAC (Secondary) | b | 8 | |

## Processing Code Table (Field 3)

First 2 digits define transaction type:

| Code | Transaction Type |
|------|-----------------|
| 00   | Purchase |
| 01   | Cash Advance / ATM Withdrawal |
| 09   | Purchase with Cashback |
| 20   | Return / Refund |
| 22   | Adjustment |
| 28   | Payment |
| 30   | Available Funds Inquiry |
| 31   | Balance Inquiry |
| 40   | Transfer From Account |
| 50   | Payment From Account |

Second pair (from account type): 00=default, 10=savings, 20=checking, 30=credit, 40=universal
Third pair (to account type): same codes

## Response Code Table (Field 39)

| Code | Meaning | Action |
|------|---------|--------|
| 00   | Approved | Proceed |
| 01   | Refer to Card Issuer | Decline, call issuer |
| 03   | Invalid Merchant | Config error |
| 04   | Pick Up Card | Hard decline, capture card |
| 05   | Do Not Honor | Soft decline, retry discouraged |
| 06   | Error | Transient, may retry |
| 12   | Invalid Transaction | Hard decline |
| 13   | Invalid Amount | Hard decline |
| 14   | Invalid Card Number | Hard decline |
| 15   | No Such Issuer | Hard decline |
| 30   | Format Error | Config/implementation error |
| 41   | Lost Card | Hard decline |
| 43   | Stolen Card | Hard decline |
| 51   | Insufficient Funds | Soft decline |
| 54   | Expired Card | Hard decline |
| 55   | Invalid PIN | Soft decline (3 retries max) |
| 57   | Transaction Not Permitted to Cardholder | Hard decline |
| 58   | Transaction Not Permitted to Terminal | Config error |
| 61   | Exceeds Withdrawal Limit | Soft decline |
| 65   | Exceeds Withdrawal Frequency | Soft decline |
| 75   | PIN Tries Exceeded | Hard decline |
| 76   | Inoperative | Try different service |
| 91   | Issuer Unavailable | Transient, retry with backoff |
| 96   | System Malfunction | Transient, retry with backoff |

## EMV TLV Tag Reference (Field 55)

BER-TLV encoding: `[tag][length][value]`. Tags are 1 or 2 bytes; if first byte low nibble = `1F`, read next byte too.

| Tag  | Name | Length | Notes |
|------|------|--------|-------|
| 5A   | PAN | var | Mask in output |
| 5F24 | Application Expiry Date | 3 | YYMMDD |
| 5F2A | Transaction Currency Code | 2 | ISO 4217 numeric BCD |
| 5F34 | PAN Sequence Number | 1 | |
| 82   | Application Interchange Profile | 2 | Bit flags for capabilities |
| 84   | Dedicated File Name | var | AID |
| 8A   | Authorization Response Code | 2 | ASCII, e.g., `30 30` = "00" |
| 95   | Terminal Verification Results | 5 | Bit flags, all zeros = no issues |
| 9A   | Transaction Date | 3 | YYMMDD |
| 9C   | Transaction Type | 1 | 00=purchase, 01=cash, 20=refund |
| 9F02 | Authorized Amount | 6 | Numeric BCD, 12 digits |
| 9F03 | Other Amount | 6 | Cashback amount |
| 9F06 | AID | var | Application Identifier |
| 9F09 | Application Version Number | 2 | |
| 9F10 | Issuer Application Data | var | CVR, counters — issuer proprietary |
| 9F1A | Terminal Country Code | 2 | ISO 3166 numeric BCD |
| 9F1E | IFD Serial Number | 8 | Terminal serial |
| 9F21 | Transaction Time | 3 | hhmmss BCD |
| 9F26 | Application Cryptogram (AC) | 8 | ARQC/TC/AAC — key auth data |
| 9F27 | Cryptogram Information Data | 1 | 80=ARQC, 40=TC, 00=AAC |
| 9F33 | Terminal Capabilities | 3 | |
| 9F34 | CVM Results | 3 | How cardholder was verified |
| 9F35 | Terminal Type | 1 | |
| 9F36 | ATC | 2 | Application Transaction Counter — replay protection |
| 9F37 | Unpredictable Number | 4 | Random, used in AC computation |
| 9F41 | Transaction Sequence Counter | 4 | |

## TCP Framing Rules

ISO 8583 messages over TCP must use a length prefix:

- **2-byte big-endian** (most common): `len_high len_low | message_bytes`
  - Max message: 65535 bytes
  - Read exactly: `binary.BigEndian.Uint16(lenBuf)` bytes after the 2-byte header
- **4-byte big-endian**: used by some Visa/Mastercard direct connections
- **TPDU header** (5 bytes): some legacy networks prepend a TPDU before length

Read pattern (Go):
```go
lenBuf := make([]byte, 2)
io.ReadFull(conn, lenBuf)
msgLen := binary.BigEndian.Uint16(lenBuf)
msgBuf := make([]byte, msgLen)
io.ReadFull(conn, msgBuf)
```

Always set read/write deadlines. Never block indefinitely on a payment socket.

## Scheme-Specific Notes

**Visa (VisaNet / BASE I):**
- Uses F60 and F63 for additional data
- STIP (Stand-In Processing): issuer unavailable responses — check F39=91 with F60 STIP indicator
- CPS (Custom Payment Service) profile in F60 for card-present qualification

**Mastercard (Banknet):**
- F48 extensively used for additional data (DE48)
- Trace ID in F90 for reversals must match original exactly
- Banknet Reference Number (BRN) in F63

**Local Debit Networks (generic):**
- Often use F48 or F60/F61/F62 for domestic routing data
- Network-specific processing codes for inter-bank transfer
- PIN required for debit; F52 must be present for PIN-verified transactions
- Some networks require MAC in F64 on all financial messages

**UnionPay (CUP):**
- F47/F48 used for Chinese characters in merchant name
- Specific F55 tags for QPBOC (offline EMV variant)
- F60 subfields for UnionPay-specific routing flags
