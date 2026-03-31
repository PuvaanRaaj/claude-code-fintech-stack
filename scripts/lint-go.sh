#!/bin/bash
set -e

echo "→ Running gofmt..."
UNFORMATTED=$(gofmt -l . 2>/dev/null | grep -v vendor || true)
if [ -n "$UNFORMATTED" ]; then
    echo "✗ Unformatted Go files:"
    echo "$UNFORMATTED"
    echo "Run: gofmt -w ."
    exit 1
fi
echo "✓ gofmt: clean"

echo "→ Running go vet..."
go vet ./...
echo "✓ go vet: clean"

if command -v golangci-lint &>/dev/null; then
    echo "→ Running golangci-lint..."
    golangci-lint run ./...
    echo "✓ golangci-lint: clean"
else
    echo "⚠ golangci-lint not installed. Install: https://golangci-lint.run/usage/install/"
fi
