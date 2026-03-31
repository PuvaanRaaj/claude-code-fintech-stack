#!/bin/bash
set -e

if [ ! -f "vendor/bin/phpunit" ]; then
    echo "✗ phpunit not found. Run: composer install"
    exit 1
fi

ARGS=""
[ "${COVERAGE}" = "1" ] && ARGS="$ARGS --coverage-text"
[ "${CI}" = "1" ] && ARGS="$ARGS --log-junit storage/test-results/junit.xml"

echo "→ Running PHPUnit..."
./vendor/bin/phpunit $ARGS
echo "✓ PHPUnit: all tests passed"
