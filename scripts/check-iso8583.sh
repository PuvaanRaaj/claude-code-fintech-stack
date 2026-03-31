#!/bin/bash
# Validate and decode an ISO 8583 hex string
# Usage: ./scripts/check-iso8583.sh <hex-string>

if [ -z "$1" ]; then
    echo "Usage: $0 <iso8583-hex-string>"
    echo "Example: $0 02007234054128C18200..."
    exit 1
fi

python3 - "$1" <<'PYTHON'
import sys
import struct

def decode_mti(hex_str):
    mtis = {
        "0100": "Authorization Request", "0110": "Authorization Response",
        "0200": "Financial Transaction Request (Purchase)", "0210": "Financial Transaction Response",
        "0400": "Reversal Request", "0410": "Reversal Response",
        "0420": "Reversal Advice", "0430": "Reversal Advice Response",
        "0800": "Network Management Request", "0810": "Network Management Response",
    }
    return mtis.get(hex_str, f"Unknown ({hex_str})")

def parse_bitmap(hex_str):
    bits = []
    for byte in bytes.fromhex(hex_str):
        for i in range(7, -1, -1):
            bits.append((byte >> i) & 1)
    return bits

hex_input = sys.argv[1].replace(" ", "").upper()

try:
    mti = hex_input[0:4]
    print(f"\n{'='*60}")
    print(f"ISO 8583 Message Decoder")
    print(f"{'='*60}")
    print(f"MTI: {mti} → {decode_mti(mti)}")

    bitmap_hex = hex_input[4:20]
    primary_bits = parse_bitmap(bitmap_hex)

    secondary_hex = ""
    data_start = 20
    if primary_bits[0]:  # bit 1 set = secondary bitmap
        secondary_hex = hex_input[20:36]
        secondary_bits = parse_bitmap(secondary_hex)
        all_bits = primary_bits + secondary_bits
        data_start = 36
        print(f"Primary Bitmap:   {bitmap_hex}")
        print(f"Secondary Bitmap: {secondary_hex}")
    else:
        all_bits = primary_bits + [0]*64
        print(f"Bitmap: {bitmap_hex}")

    set_fields = [i+1 for i, b in enumerate(all_bits) if b and i+1 != 1]
    print(f"\nFields present: {set_fields}")
    print(f"\n{'─'*60}")
    print(f"{'Field':<8} {'Name':<35} {'Offset':<8}")
    print(f"{'─'*60}")

    field_names = {
        2: "PAN", 3: "Processing Code", 4: "Transaction Amount",
        7: "Transmission Date/Time", 11: "STAN", 12: "Local Time",
        13: "Local Date", 14: "Expiry Date", 22: "POS Entry Mode",
        25: "POS Condition Code", 35: "Track 2 Equivalent",
        37: "Retrieval Reference Number", 38: "Auth ID Response",
        39: "Response Code", 41: "Terminal ID", 42: "Merchant ID",
        49: "Currency Code", 52: "PIN Data", 55: "EMV/ICC Data",
        60: "Private Reserved 1", 63: "Private Reserved 2",
    }

    offset = data_start
    for field in set_fields:
        name = field_names.get(field, f"Field {field}")
        print(f"  F{field:<6} {name:<35} offset={offset}")
        offset += 4  # simplified — real impl needs field dictionary lengths

    print(f"\n✓ Decode complete. {len(set_fields)} fields present.")
    print("Note: Full field values require field-length dictionary. Use the iso8583-parse skill for complete decode.\n")

except Exception as e:
    print(f"✗ Parse error: {e}")
    sys.exit(1)
PYTHON
