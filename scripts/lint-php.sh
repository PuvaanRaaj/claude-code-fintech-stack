#!/bin/bash
set -e

echo "→ Running Laravel Pint..."
if [ ! -f "vendor/bin/pint" ]; then
    echo "✗ vendor/bin/pint not found. Run: composer install"
    exit 1
fi

if [ "${1}" = "--check" ] || [ "${CI}" = "1" ]; then
    ./vendor/bin/pint --test
    echo "✓ PHP code style: clean"
else
    ./vendor/bin/pint
    echo "✓ PHP code style: formatted"
fi
