#!/bin/bash
# PreToolUse hook: Block writes containing raw cardholder data patterns
# Reads JSON from stdin, checks file content for PAN/CVV/track data

python3 - <<'PYTHON'
import json
import sys
import re

try:
    data = json.load(sys.stdin)
except Exception:
    print(json.dumps({"decision": "allow"}))
    sys.exit(0)

tool_input = data.get("tool_input", {})
content = tool_input.get("content", "") or tool_input.get("new_string", "")

if not isinstance(content, str):
    print(json.dumps({"decision": "allow"}))
    sys.exit(0)

# PAN pattern: 13-19 consecutive digits (potential card number)
pan_pattern = re.compile(r'\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{1,7}\b')

# Track 2 equivalent: ;digits=digits
track2_pattern = re.compile(r';\d{13,19}=\d{4}')

# PIN block: 16 hex chars in payment context (heuristic)
pin_context_pattern = re.compile(r'(?:pin.?block|pinblock|PIN_BLOCK)["\s:=]+[0-9A-Fa-f]{16}', re.IGNORECASE)

findings = []

if track2_pattern.search(content):
    findings.append("Track 2 equivalent data pattern detected (;PAN=expiry)")

if pin_context_pattern.search(content):
    findings.append("PIN block pattern detected near PIN-related keyword")

# PAN check: only flag if it looks like a real card number (Luhn-adjacent heuristic)
pan_matches = pan_pattern.findall(content)
for match in pan_matches:
    digits = re.sub(r'[\s-]', '', match)
    if len(digits) >= 13 and digits[0] in '3456':  # Visa, MC, Amex, Discover prefix
        findings.append(f"Potential PAN detected: {digits[:6]}****{digits[-4:]}")
        break

if findings:
    reason = "Content contains raw cardholder data (PCI violation):\n" + "\n".join(f"  - {f}" for f in findings)
    reason += "\n\nMask card numbers as: first6****last4. Never write raw PANs, track data, or PIN blocks to files."
    print(json.dumps({"decision": "block", "reason": reason}))
else:
    print(json.dumps({"decision": "allow"}))
PYTHON
