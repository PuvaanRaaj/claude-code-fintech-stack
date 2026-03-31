#!/bin/bash
# PostToolUse hook: Run gofmt on Go files after write

python3 - <<'PYTHON'
import json
import sys
import subprocess
import shutil

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

file_path = data.get("tool_input", {}).get("file_path", "") or \
            data.get("tool_input", {}).get("path", "")

if not file_path or not file_path.endswith(".go"):
    sys.exit(0)

if not shutil.which("gofmt"):
    sys.exit(0)

try:
    # Check if file needs formatting
    check = subprocess.run(["gofmt", "-l", file_path], capture_output=True, text=True, timeout=15)
    if check.stdout.strip():
        subprocess.run(["gofmt", "-w", file_path], timeout=15)
        print(f"[gofmt] Reformatted: {file_path}", file=sys.stderr)
except Exception:
    pass
PYTHON
