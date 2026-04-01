---
name: build-fix
description: Diagnose and fix build errors for PHP/composer, Go modules, npm/bun, or Docker
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /build-fix

## Goal
Identify the root cause of a build failure and fix it. Works across PHP (composer), Go (modules), JavaScript (bun/npm), and Docker. Does not guess — reads the actual error output first.

## Steps
1. Run the build command and capture full output:
   - PHP: `composer install 2>&1` or `composer update 2>&1`
   - Go: `go build ./... 2>&1`
   - JS: `bun run build 2>&1`
   - Docker: `docker build . 2>&1`
2. Parse the error output — identify:
   - Missing dependency or version conflict
   - Type mismatch or compilation error
   - Missing import or unresolved reference
   - Docker layer failure (missing file, wrong base image, network issue)
3. Look up the exact file and line causing the issue
4. Read the surrounding context in that file
5. Apply a targeted fix — touch only what's necessary
6. Re-run the build to confirm it passes
7. If the fix involved adding a dependency, run the security audit:
   - `composer audit`
   - `go list -m all | govulncheck`
   - `bun audit`

## Output
```
BUILD FIX
────────────────────────────────────────
Error:    go build ./...: internal/host/client.go:12:2: no required module provides github.com/foo/bar
Root cause: missing import in go.mod
Fix:      ran: go get github.com/foo/bar@v1.2.3
          updated: go.mod, go.sum
────────────────────────────────────────
Re-run:   go build ./... → PASS
Audit:    govulncheck → 0 vulnerabilities
────────────────────────────────────────
FIXED
```
