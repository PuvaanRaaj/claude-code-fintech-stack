#!/bin/bash
# Verify all scripts are executable and have valid shebang
set -e
echo "→ Testing scripts..."

errors=0
for script in scripts/*.sh; do
    if [ ! -x "$script" ]; then
        echo "  ✗ Not executable: $script (run: chmod +x $script)"
        errors=$((errors + 1))
        continue
    fi

    first_line=$(head -1 "$script")
    if [[ "$first_line" != "#!/bin/bash" ]] && [[ "$first_line" != "#!/bin/sh" ]]; then
        echo "  ✗ Missing shebang in: $script"
        errors=$((errors + 1))
        continue
    fi

    echo "  ✓ $script"
done

if [ $errors -gt 0 ]; then
    echo "✗ $errors script(s) failed validation"
    exit 1
fi
echo "✓ All scripts valid"
