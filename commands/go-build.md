---
name: go-build
description: Fix Go build errors — module issues, missing imports, type mismatches
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /go-build

## Goal
Diagnose and fix Go build failures. Covers missing modules, import cycle, type mismatch, and interface compliance errors.

## Steps
1. Run the build and capture full output:
   ```bash
   go build ./... 2>&1
   ```
2. Categorise the error:
   - `no required module provides` → run `go get <module>@<version>`
   - `cannot find package` → check import path spelling and go.mod
   - `does not implement interface` → check method signatures
   - `cannot use X as type Y` → type mismatch in assignment or function call
   - `import cycle` → circular dependency between packages, needs restructuring
   - `undefined: X` → missing import or typo
3. Read the failing file at the reported line
4. Apply minimal fix — do not refactor unrelated code
5. Re-run `go build ./...` to verify
6. Run `go vet ./...` to catch any follow-on issues
7. Run `go test -race ./...` for the affected package

## Output
```
GO BUILD FIX
────────────────────────────────────────────────
Error:    internal/host/client.go:12:2: no required module provides golang.org/x/net
Category: Missing module
Fix:      go get golang.org/x/net@v0.22.0 → go.mod updated
────────────────────────────────────────────────
go build ./...  → PASS
go vet ./...    → PASS
────────────────────────────────────────────────
FIXED
```
