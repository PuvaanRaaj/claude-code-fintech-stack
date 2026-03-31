---
name: iso8583-parse
description: Decode a raw ISO 8583 hex string into a human-readable field map with EMV TLV parsing for field 55
argument-hint: <hex-string or 'staged'>
---

Decode an ISO 8583 message from a hex string. Use when a developer pastes a hex dump, asks "what does this message mean", or is debugging a payment host response.

## Steps

1. **Accept input** — read hex string from $ARGUMENTS or the most recently mentioned hex blob in conversation

2. **Parse MTI** — first 4 hex chars (2 bytes BCD): version|class|function|origin
   - `02` = ISO 8583-1:1987 version; `00` = financial; `00` = request; `0200` = purchase request
   - Map to human label from MTI reference table

3. **Parse primary bitmap** — next 16 hex chars (8 bytes). Convert each byte to 8 bits. Bit N is set if byte[(N-1)/8] has bit (7 - ((N-1)%8)) set.

4. **Check bit 1** — if set, read next 16 hex chars (8 bytes) as secondary bitmap covering fields 65–128

5. **For each set bit**, decode the field:
   - Fixed-length fields: read exactly N chars
   - LLVAR: read 2-char decimal length prefix, then that many chars
   - LLLVAR: read 3-char decimal length prefix, then that many chars
   - Binary fields (type b): length is in bytes, not chars — read 2N hex chars

6. **Special handling for Field 55** (ICC/EMV data):
   - Parse as BER-TLV recursively
   - For each TLV: output tag (hex), tag name (from dictionary), length, hex value, decoded meaning
   - Key tags to label: 9F26 (Application Cryptogram), 9F27 (Cryptogram Info), 9F02 (Amount), 9F36 (ATC), 5F2A (Currency)

7. **Output** as markdown table:
   ```
   | Field | Name | Raw Value | Decoded |
   |-------|------|-----------|---------|
   | MTI   | Message Type | 0200 | Financial Transaction Request |
   | 2 | PAN | 4111111111111111 | MASKED: 411111****1111 |
   | 4 | Amount | 000000010000 | 100.00 |
   | 55 | EMV Data | ... | [TLV breakdown below] |
   ```

8. **Security**: automatically mask F2 (PAN), F35 (track 2), F52 (PIN block) in output — never display raw values

## Output Format
- Table of all fields present
- TLV sub-table for F55 if present
- Summary: MTI label, response code meaning (if F39 present), approval/decline status
