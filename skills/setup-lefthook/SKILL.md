---
name: setup-lefthook
description: Configure lefthook git hooks with biome linting and type checking. Use when user says "setup lefthook", "add git hooks", "configure pre-commit", or "setup lefthook".
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
validated: 2026-02-13
---

# Setup Lefthook Git Hooks

## Prerequisites

- Biome must be installed (`biome.json` should exist)
- TypeScript must be configured (`tsconfig.json` should exist)
- Git repository must be initialized

## Installation Steps

First, verify prerequisites exist:

```bash
# Check for biome.json and tsconfig.json
ls biome.json tsconfig.json
```

1. **Install lefthook as dev dependency:**

```bash
bun add -d lefthook
```

2. **Create `.lefthook.yml` configuration:**

**Ask the user:** "Do you want the **basic** configuration (just linting and type checking) or the **full** configuration (includes Vercel & Sanity deployment)?"

Then create the appropriate configuration:

### Basic Configuration (Recommended for most projects)

```yaml
pre-commit:
  parallel: true
  commands:
    lint:
      run: bunx biome check --write --staged --unsafe || (echo "No files to lint" && exit 0)
    types:
      run: bunx tsc --noEmit

pre-push:
  commands:
    check-types:
      run: bunx tsc --noEmit
    lint-ci:
      run: bunx biome ci . --max-diagnostics=100 --files-ignore-unknown=true
```

### Full Configuration (Includes Vercel & Sanity deployment)

Only use if project has Vercel and Sanity configured:

```yaml
pre-commit:
  parallel: true
  commands:
    lint:
      run: bunx biome check --write --staged --unsafe || (echo "No files to lint" && exit 0)
    types:
      run: bunx tsc --noEmit

pre-push:
  commands:
    check-types:
      run: bunx tsc --noEmit
    lint-ci:
      run: bunx biome ci . --max-diagnostics=100 --files-ignore-unknown=true
    build-deploy:
      interactive: true
      run: vercel build --prod && vercel deploy --prebuilt --prod --archive=tgz && bunx sanity deploy
```

3. **Install git hooks:**

```bash
bunx lefthook install
```

## What This Configures

### Pre-commit (runs in parallel):
- **Lint**: Auto-fixes staged files with Biome
- **Types**: Validates TypeScript types

### Pre-push (Basic):
- **Check types**: Full TypeScript validation
- **Lint CI**: Biome CI check with diagnostics

### Pre-push (Full - optional):
- **Build & Deploy**: Interactive Vercel and Sanity deployment

## Verification

Test the hooks:

```bash
# Test pre-commit hook
echo "// test" >> app/page.tsx
git add app/page.tsx
git commit -m "test commit"

# Should run biome check and tsc
```

## Notes

- Hooks run automatically on git commit/push
- Pre-commit runs only on staged files
- Build-deploy hook is interactive and requires user confirmation
