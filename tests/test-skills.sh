#!/bin/bash
# Validate all skill directories have SKILL.md with required frontmatter
set -e
echo "→ Validating skills..."

python3 - <<'PYTHON'
import os, sys, re

skills_dir = ".claude/skills"
errors = []
count = 0

for skill_name in sorted(os.listdir(skills_dir)):
    skill_path = os.path.join(skills_dir, skill_name)
    if not os.path.isdir(skill_path):
        continue

    skill_md = os.path.join(skill_path, "SKILL.md")
    if not os.path.isfile(skill_md):
        errors.append(f"Missing SKILL.md: {skill_path}")
        continue

    with open(skill_md) as f:
        content = f.read()

    if not content.startswith("---"):
        errors.append(f"Missing YAML frontmatter: {skill_md}")
        continue

    if "name:" not in content:
        errors.append(f"Missing 'name:' in frontmatter: {skill_md}")
    if "description:" not in content:
        errors.append(f"Missing 'description:' in frontmatter: {skill_md}")

    count += 1
    print(f"  ✓ {skill_name}")

if errors:
    for e in errors:
        print(f"  ✗ {e}")
    sys.exit(1)

print(f"\n✓ All {count} skills valid")
PYTHON
