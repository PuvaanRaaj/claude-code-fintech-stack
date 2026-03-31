---
name: go-lint
description: Run Go linters (gofmt + golangci-lint) on changed files, parse results, auto-fix formatting issues
argument-hint: <file path or 'all'>
---

Lint Go code. Triggers on "lint go", "gofmt", "go style issues".

## Trigger Phrases
"lint go", "go lint", "fix go style", "gofmt", "golangci-lint", "go fmt"

## Steps

1. **gofmt check**: `gofmt -l .` — list files that need formatting
   - If any output: `gofmt -w .` to fix all
   - Report which files were reformatted

2. **go vet**: `go vet ./...` — built-in checks for suspicious constructs
   - Parse and report any findings as HIGH severity

3. **golangci-lint** (if installed): `golangci-lint run ./...`
   - Group by severity:
     - HIGH: `errcheck`, `staticcheck`, `govet`
     - MEDIUM: `gosimple`, `ineffassign`, `unused`
     - LOW: `stylecheck`, `godot`, `wsl`

4. **Auto-fixable** — offer to fix:
   - Formatting: `gofmt -w .` (safe)
   - Unused imports: `goimports -w .` (safe)
   - Ask for HIGH/MEDIUM findings: show diff, confirm before applying

5. **Ask**: "Auto-fix formatting only / fix all auto-fixable / show only / abort?"

6. **Verify after fix**: `gofmt -l .` should return empty, `go vet ./...` should pass

## Output Format
- List of issues grouped by severity
- Which are auto-fixable
- Result after fixes applied
