#!/bin/bash
# Run all plugin test suites and report a final summary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUITES=(
    "test-plugin.sh"
    "test-skills.sh"
    "test-hooks.sh"
    "test-scripts.sh"
)

passed=0
failed=0
failed_suites=()

for suite in "${SUITES[@]}"; do
    echo ""
    echo "→ Running $suite..."
    echo "----------------------------------------"
    set +e
    bash "$SCRIPT_DIR/$suite"
    exit_code=$?
    set -e
    if [ $exit_code -eq 0 ]; then
        echo "  ✓ $suite passed"
        passed=$((passed + 1))
    else
        echo "  ✗ $suite failed (exit code $exit_code)"
        failed=$((failed + 1))
        failed_suites+=("$suite")
    fi
done

total=$((passed + failed))
echo ""
echo "========================================"
echo "  $passed/$total test suites passed"

if [ ${#failed_suites[@]} -gt 0 ]; then
    echo ""
    for s in "${failed_suites[@]}"; do
        echo "  ✗ $s"
    done
    echo "========================================"
    exit 1
fi

echo "========================================"
exit 0
