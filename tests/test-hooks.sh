#!/bin/bash
# Test hook scripts are executable and handle benign input cleanly
set -e
echo "→ Testing hook scripts..."

BENIGN_WRITE='{"tool_name":"Write","tool_input":{"file_path":"test.php","content":"<?php echo '\''hello'\'';"}}'
BENIGN_EDIT='{"tool_name":"Edit","tool_input":{"file_path":"test.go","old_string":"foo","new_string":"bar"}}'

for script in hooks/*.sh; do
    if [ ! -x "$script" ]; then
        echo "  ✗ Not executable: $script"
        exit 1
    fi

    output=$(echo "$BENIGN_WRITE" | bash "$script" 2>/dev/null || true)

    # PreToolUse hooks must output valid JSON with 'decision' field
    if [[ "$script" == *"block"* ]]; then
        if ! echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'decision' in d" 2>/dev/null; then
            echo "  ✗ Hook must output JSON with 'decision': $script"
            exit 1
        fi
        decision=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['decision'])")
        echo "  ✓ $script → decision: $decision"
    else
        echo "  ✓ $script → PostToolUse (non-blocking)"
    fi
done

echo "✓ All hooks valid"
