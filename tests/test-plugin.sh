#!/bin/bash
# Validate plugin.json structure
set -e
PLUGIN=".claude-plugin/plugin.json"
echo "→ Validating $PLUGIN..."

python3 - <<PYTHON
import json, sys, os

with open("$PLUGIN") as f:
    p = json.load(f)

errors = []

# Required fields
for field in ["name", "version", "description", "agents", "skills"]:
    if field not in p:
        errors.append(f"Missing required field: {field}")

# Arrays check
for field in ["agents", "skills"]:
    if field in p and not isinstance(p[field], list):
        errors.append(f"'{field}' must be an array")

# Hooks must NOT be in plugin.json
if "hooks" in p:
    errors.append("'hooks' must NOT be declared in plugin.json (auto-loaded from hooks/hooks.json)")

# Agent files must exist and be file paths
if "agents" in p:
    for path in p["agents"]:
        if not os.path.isfile(path):
            errors.append(f"Agent file not found: {path}")

# Skill directories must exist
if "skills" in p:
    for path in p["skills"]:
        if not os.path.isdir(path):
            errors.append(f"Skill directory not found: {path}")
        elif not os.path.isfile(os.path.join(path, "SKILL.md")):
            errors.append(f"SKILL.md missing in: {path}")

if errors:
    for e in errors:
        print(f"  ✗ {e}")
    sys.exit(1)
else:
    print(f"  ✓ plugin.json valid: {len(p['agents'])} agents, {len(p['skills'])} skills, version={p['version']}")
PYTHON
echo "✓ Plugin validation passed"
