#!/bin/bash
set -e

if [ -f "bun.lock" ] || [ -f "bunfig.toml" ]; then
    RUNNER="bun x"
else
    RUNNER="npx"
fi

echo "→ Running ESLint..."
$RUNNER eslint . --ext .ts,.tsx,.vue,.js,.jsx
echo "✓ ESLint: clean"

echo "→ Running Prettier check..."
$RUNNER prettier --check .
echo "✓ Prettier: clean"
