#!/bin/bash
set -e

ARGS=""
[ "${COVERAGE}" = "1" ] && ARGS="$ARGS --coverage"

if [ -f "bun.lock" ]; then
    echo "→ Running Bun tests..."
    bun test $ARGS
elif command -v vitest &>/dev/null || [ -f "node_modules/.bin/vitest" ]; then
    echo "→ Running Vitest..."
    npx vitest run $ARGS
else
    echo "→ Running npm test..."
    npm test
fi
echo "✓ JS tests: all passed"
