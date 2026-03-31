#!/bin/bash
set -e

echo "→ Running Go tests (with race detector)..."

ARGS="-race -count=1"
[ "${COVERAGE}" = "1" ] && ARGS="$ARGS -coverprofile=coverage.out"
[ "${BENCH}" = "1" ] && ARGS="$ARGS -bench=."

go test $ARGS ./...
echo "✓ Go tests: all passed"

if [ "${COVERAGE}" = "1" ] && [ -f coverage.out ]; then
    go tool cover -func=coverage.out | tail -1
fi
