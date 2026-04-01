---
name: iso8583-patterns
description: ISO 8583 message construction and parsing — MTI reference, bitmap encoding, field types (BCD vs ASCII), TCP socket framing, keepalive patterns, EMV TLV field 55, and common host integration gotchas.
origin: fintech-stack
---

# ISO 8583 Patterns

ISO 8583 is the messaging standard that carries most card-present payment transactions. Its documentation is distributed under NDA, its field definitions vary by acquirer, and a one-byte framing error drops the host connection silently. This skill encodes the patterns for building and debugging ISO 8583 integrations without the trial-and-error.

## When to Activate

- Building or debugging a connection to an acquiring host or payment switch
- Constructing authorisation (0100), reversal (0400), or echo (0800) messages
- Decoding a hex dump of a raw ISO 8583 message
- Diagnosing silent connection drops, RC 30 format errors, or bitmap parse failures
- Implementing field 55 (ICC/EMV data) for chip card transactions

---

## Message Structure

```
┌──────────────────────────────────────────────────────────────────┐
│  Length Prefix  │  MTI   │ Primary Bitmap │ Secondary Bitmap │ Fields
│  2 or 4 bytes   │ 4 hex  │   8 bytes      │   8 bytes (if F1)│
└──────────────────────────────────────────────────────────────────┘
```

### Message Type Indicators (MTI)

| MTI  | Description |
|------|-------------|
| 0100 | Authorisation Request |
| 0110 | Authorisation Response |
| 0200 | Financial Transaction Request |
| 0210 | Financial Transaction Response |
| 0400 | Reversal Request |
| 0410 | Reversal Response |
| 0420 | Reversal Advice |
| 0800 | Network Management Request (echo / sign-on) |
| 0810 | Network Management Response |

---

## Common Fields

| Field | Name | Type | Length | Notes |
|-------|------|------|--------|-------|
| F2 | PAN | LLVAR n | 12–19 | Length-prefixed; never log raw |
| F3 | Processing Code | n | 6 | First 2 bytes = txn type (00=purchase, 20=refund) |
| F4 | Amount, Transaction | n | 12 | Minor units, zero-padded right-justified |
| F7 | Transmission Date/Time | n | 10 | MMDDhhmmss |
| F11 | STAN | n | 6 | System Trace Audit Number — unique per request session |
| F12 | Time, Local | n | 6 | hhmmss |
| F13 | Date, Local | n | 4 | MMDD |
| F22 | POS Entry Mode | n | 3 | 051=chip, 071=contactless, 010=manual |
| F35 | Track 2 Equivalent | LLVAR z | — | Never log; PAN is embedded |
| F37 | Retrieval Reference Number | an | 12 | Echo this exactly in reversal F37 |
| F38 | Authorization Code | an | 6 | Present in 0110 when RC = 00 |
| F39 | Response Code | an | 2 | 00=approved, 05=decline, 91=issuer unavailable |
| F41 | Terminal ID | ans | 8 | Right-padded with spaces |
| F42 | Merchant ID | ans | 15 | Right-padded with spaces |
| F49 | Currency Code | n | 3 | ISO 4217 numeric: 458=MYR, 840=USD, 978=EUR |
| F55 | ICC Data (EMV) | LLLVAR b | — | Binary TLV — see EMV section below |
| F70 | Network Management Info | n | 3 | 001=sign-on, 301=echo |

---

## Bitmap Encoding

```
Primary bitmap:   8 bytes = 64 bits, covering fields 1–64
Secondary bitmap: 8 bytes = 64 bits, covering fields 65–128
                  Present when bit 1 of primary bitmap is set

Each bit position N (1-indexed, MSB first) indicates whether field N is present.

Example: fields 2, 3, 4, 7, 11, 12, 13, 37, 38, 39, 41, 42, 49
Primary bitmap (hex): 72 34 00 01 28 C1 82 00
```

### Go — Bitmap

```go
type Bitmap [8]byte

// Set marks field as present (fields are 1-indexed)
func (b *Bitmap) Set(field int) {
    if field < 1 || field > 64 {
        return
    }
    byteIdx := (field - 1) / 8
    bitIdx  := 7 - ((field - 1) % 8) // MSB-first
    b[byteIdx] |= 1 << bitIdx
}

func (b *Bitmap) IsSet(field int) bool {
    if field < 1 || field > 64 {
        return false
    }
    byteIdx := (field - 1) / 8
    bitIdx  := 7 - ((field - 1) % 8)
    return b[byteIdx]&(1<<bitIdx) != 0
}
```

---

## Field Encoding Types

| Code | Meaning | Encoding |
|------|---------|----------|
| n | Numeric | BCD or ASCII — **confirm with acquirer** |
| a | Alpha | ASCII, space-padded right |
| an | Alphanumeric | ASCII |
| ans | Alpha-num-special | ASCII |
| b | Binary | Raw bytes |
| z | Track 2 | Hex digits + separator D |
| LLVAR | Variable, 2-digit length prefix | prefix + value |
| LLLVAR | Variable, 3-digit length prefix | prefix + value |

> **BCD vs ASCII is the most common integration bug.** Getting it wrong produces byte-level garbage; the host closes the connection with no error. Test with a minimal known-good message before adding fields.

```go
// BCD encoding — two decimal digits per byte
func EncodeBCD(digits string) []byte {
    if len(digits)%2 != 0 {
        digits = "0" + digits // Left-pad to even length
    }
    out := make([]byte, len(digits)/2)
    for i := range out {
        hi := digits[i*2] - '0'
        lo := digits[i*2+1] - '0'
        out[i] = (hi << 4) | lo
    }
    return out
}
```

---

## TCP Socket Framing

Most hosts use a 2-byte or 4-byte big-endian length prefix. Confirm with the acquirer spec.

```go
type Conn struct {
    conn         net.Conn
    readTimeout  time.Duration
    writeTimeout time.Duration
}

func (c *Conn) Send(msg []byte) error {
    c.conn.SetWriteDeadline(time.Now().Add(c.writeTimeout))

    length := make([]byte, 2)
    binary.BigEndian.PutUint16(length, uint16(len(msg)))

    if _, err := c.conn.Write(length); err != nil {
        return fmt.Errorf("write length prefix: %w", err)
    }
    if _, err := c.conn.Write(msg); err != nil {
        return fmt.Errorf("write body: %w", err)
    }
    return nil
}

func (c *Conn) Receive() ([]byte, error) {
    c.conn.SetReadDeadline(time.Now().Add(c.readTimeout))

    length := make([]byte, 2)
    if _, err := io.ReadFull(c.conn, length); err != nil {
        return nil, fmt.Errorf("read length prefix: %w", err)
    }

    msgLen := binary.BigEndian.Uint16(length)
    if msgLen == 0 || msgLen > 8192 {
        return nil, fmt.Errorf("suspicious message length: %d", msgLen)
    }

    body := make([]byte, msgLen)
    if _, err := io.ReadFull(c.conn, body); err != nil {
        return nil, fmt.Errorf("read body: %w", err)
    }
    return body, nil
}
```

### Keepalive (Echo / Sign-On)

Send a 0800 echo every 30 seconds. Firewalls silently drop idle TCP connections — the host won't tell you, it just stops responding.

```go
func (c *Conn) StartKeepalive(ctx context.Context) {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    for {
        select {
        case <-ticker.C:
            if err := c.Send(buildEchoMessage()); err != nil {
                c.reconnect() // Host dropped — reconnect before next transaction
                return
            }
        case <-ctx.Done():
            return
        }
    }
}
```

---

## EMV TLV (Field 55)

Field 55 carries the chip card cryptogram and ICC data. It is binary TLV (Tag-Length-Value).

| Tag | Name |
|-----|------|
| 9F26 | Application Cryptogram (ARQC) |
| 9F10 | Issuer Application Data |
| 9F37 | Unpredictable Number |
| 9F36 | ATC (Application Transaction Counter) |
| 95   | TVR (Terminal Verification Results) |
| 9A   | Transaction Date (YYMMDD) |
| 9C   | Transaction Type (00=purchase, 20=refund) |
| 5F2A | Transaction Currency Code |
| 82   | AIP (Application Interchange Profile) |
| 84   | Dedicated File Name (AID) |

```go
type TLV struct {
    Tag   []byte
    Value []byte
}

func EncodeTLVs(tlvs []TLV) []byte {
    // Some hosts require tags sorted ascending
    sort.Slice(tlvs, func(i, j int) bool {
        return bytes.Compare(tlvs[i].Tag, tlvs[j].Tag) < 0
    })

    var buf bytes.Buffer
    for _, t := range tlvs {
        buf.Write(t.Tag)
        if len(t.Value) < 128 {
            buf.WriteByte(byte(len(t.Value)))
        } else {
            buf.WriteByte(0x81)
            buf.WriteByte(byte(len(t.Value)))
        }
        buf.Write(t.Value)
    }
    return buf.Bytes()
}
```

---

## Common Gotchas

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Host drops connection silently | Length prefix is 2 bytes but host expects 4 (or vice versa) | Confirm frame format with acquirer spec |
| All fields parse as garbage | Numeric encoding mismatch (BCD vs ASCII) | Test with a minimal known-good message; hex-dump both sides |
| Bitmap shows F1 set unexpectedly | Secondary bitmap is present — F1 is the secondary bitmap indicator | Parse 8 more bytes for the secondary bitmap when F1 bit is set |
| F55 rejected by host | TLV tags not sorted by tag number | Sort tags ascending before encoding |
| STAN collision | STAN counter restarted before host cleared previous session | Use a monotonically incrementing counter; wrap at 999999 |
| Reversal not matched | F37 in 0400 doesn't match F37 from the 0110 response | Echo F37 verbatim from the 0110 into the 0400 |
| RC 30 (format error) | Field length or encoding mismatch | Hex-dump the sent message byte by byte; compare with acquirer field spec |
| Connection drops after 60s idle | Firewall state timeout | Send 0800 echo every 30 seconds |

---

## Best Practices

- **Confirm the spec with your acquirer before writing a byte** — MTI format, length prefix size, BCD vs ASCII, and character set (ASCII vs EBCDIC) vary by host and cannot be guessed
- **Dump hex at debug level only** — field 55 and field 35 contain card cryptograms; never log in production
- **Echo F37 exactly** — the retrieval reference number in the 0110 response must be echoed verbatim in the 0400 reversal; if it doesn't match, the host cannot find the original transaction
- **Keepalive is not optional** — production firewalls will drop idle connections; use 0800 echo every 30 seconds
- **STAN is per-session, not per-day** — reset to 000001 only when the host explicitly confirms session close; reuse within a session causes RC 94 (duplicate transmission)
- **Test field 55 independently** — EMV TLV encoding bugs are invisible until the host returns RC 55 (incorrect PIN) or RC 82 (negative CAM result); validate TLV structure with a parser before sending
