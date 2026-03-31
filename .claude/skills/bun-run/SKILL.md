---
name: bun-run
description: Run Bun scripts, manage bun package operations, troubleshoot bun lockfile and dependency issues
argument-hint: <command: install|run|test|add|remove>
---

Manage Bun package and script operations. Triggers in projects with `bun.lock` or `bunfig.toml`.

## Trigger Phrases
"bun install", "bun run", "bun test", "lockfile conflict", "bun add", "bun error"

## Steps

1. **Detect project type** — check for `bun.lock` (Bun project) vs `package-lock.json` (npm project)

2. **Route to correct command**:
   - Install deps: `bun install`
   - Run script: `bun run <script>`
   - Run tests: `bun test` (or `bun test --watch`)
   - Add package: `bun add <pkg>` / `bun add -d <pkg>`
   - Remove: `bun remove <pkg>`
   - Build: `bun build ./src/index.ts --outdir ./dist --target=bun`

3. **Lockfile conflict** — if `bun.lock` has merge conflicts:
   ```bash
   bun install  # regenerates bun.lock from package.json
   git add bun.lock
   ```

4. **Verify no mixing** — warn loudly if both `bun.lock` AND `package-lock.json` exist

5. **Common errors**:
   - "Cannot find module" → check `tsconfig.json` paths, check `bun.lock` is current
   - "SyntaxError: Cannot use import" → ensure `"type": "module"` in `package.json`
   - Slow install → `bun install --frozen-lockfile` (faster, uses existing lock)

## Output Format
- Command run + output
- Error diagnosis if failed
- Next step suggestion
