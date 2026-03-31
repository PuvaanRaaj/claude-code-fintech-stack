#!/bin/bash
# PostToolUse hook: Run Laravel Pint on PHP files after write
# Non-blocking — notifies but doesn't block the write

python3 - <<'PYTHON'
import json
import sys
import subprocess
import os

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

file_path = data.get("tool_input", {}).get("file_path", "") or \
            data.get("tool_input", {}).get("path", "")

if not file_path or not file_path.endswith(".php"):
    sys.exit(0)

# Find pint binary
pint_candidates = [
    "./vendor/bin/pint",
    "vendor/bin/pint",
]

pint_bin = next((p for p in pint_candidates if os.path.isfile(p)), None)

if not pint_bin:
    sys.exit(0)

try:
    result = subprocess.run(
        [pint_bin, file_path],
        capture_output=True, text=True, timeout=30
    )
    if "FIXED" in result.stdout or result.returncode == 1:
        print(f"[pint] Reformatted: {file_path}", file=sys.stderr)
except Exception:
    pass
PYTHON
