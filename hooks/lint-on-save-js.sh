#!/bin/bash
# PostToolUse hook: Run ESLint on JS/TS/Vue files after write

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

valid_exts = (".ts", ".tsx", ".vue", ".js", ".jsx")
if not file_path or not any(file_path.endswith(ext) for ext in valid_exts):
    sys.exit(0)

# Detect bun vs npm project
use_bun = os.path.isfile("bun.lock") or os.path.isfile("bunfig.toml")

eslint_local = "node_modules/.bin/eslint"
if not os.path.isfile(eslint_local):
    sys.exit(0)

try:
    cmd = ["bun", "x", "eslint", "--fix", file_path] if use_bun else [eslint_local, "--fix", file_path]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode not in (0, 1):
        print(f"[eslint] Warning on {file_path}", file=sys.stderr)
except Exception:
    pass
PYTHON
