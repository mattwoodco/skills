# Validation Strategy Reference

This reference explains the validation tiers used during skill polish iterations to verify that skill implementations are error-free.

## Overview

Validation runs in up to 5 tiers, depending on the skill type and project configuration. Each tier provides increasingly thorough verification of the implementation.

## Validation Tiers

### Tier 1 — TypeScript Compilation (Always Run)

**Command:**
```bash
cd sandbox && bunx tsc --noEmit 2>&1
```

**Purpose:** Verify type safety and catch compilation errors.

**When to run:** Always, for any skill that creates TypeScript files.

---

### Tier 2 — Linting (Run if Linter is Configured)

**Commands:**
```bash
# If biome is installed:
cd sandbox && bunx biome check . 2>&1

# If eslint is configured:
cd sandbox && bunx eslint . 2>&1
```

**Purpose:** Catch style issues, unused variables, and code quality problems.

**When to run:** If the project has biome or eslint configured.

---

### Tier 3 — Build (Run if Build Script Exists)

**Command:**
```bash
cd sandbox && bun run build 2>&1
```

**Purpose:** Verify the entire project builds successfully, catching bundling and optimization issues.

**When to run:** If the project has a build script in package.json.

---

### Tier 4 — Browser Validation (Run if Skill Has a Test Page)

**Commands:**
```bash
# Start dev server in background
cd sandbox && bun run dev &
DEV_PID=$!

# Wait for server to be ready
sleep 3
```

Then use **playwright-cli** (runs via Bash, no MCP needed) to validate the running app:

```
playwright-cli open http://localhost:3000/<test-route>  → navigate to the test route
playwright-cli snapshot                                  → inspect the DOM / visible elements
playwright-cli console                                   → check for JS errors or warnings
playwright-cli screenshot --output screenshots/<name>.png → capture visual state for debugging
playwright-cli click <ref>                               → interact with UI elements
playwright-cli eval "document.title"                     → assert page state via JS
```

Full validation sequence:
1. Navigate to the test route defined in the skill's TEST_PAGE.md
2. Take a snapshot — verify key elements are present
3. Read console messages — fail if any `error` level messages exist
4. Interact with UI per TEST_PAGE.md acceptance criteria
5. Close the page when done

```bash
# Kill dev server when finished
kill $DEV_PID
```

**Purpose:** Verify runtime behavior, console errors, visual rendering, and user interactions.

**When to run:** If the skill includes a TEST_PAGE.md reference or targets a web UI.

> **Note:** playwright-cli runs via Bash — no MCP tool permissions or ToolSearch discovery needed.

---

### Tier 5 — Test Writing (Run After Tiers 1-4 Pass)

**Commands:**
```bash
# Run existing tests
cd sandbox && bun test 2>&1

# Or with vitest directly
cd sandbox && bunx vitest run 2>&1
```

**Purpose:** Write and run tests for the skill's code after the implementation passes all other tiers.

**Test types:**
- **Unit tests** (`__tests__/unit/`): Utility functions, lib helpers, validators, formatters
- **Integration tests** (`__tests__/integration/`): API routes, database queries, auth flows
- **Component/E2E tests** (`__tests__/e2e/`): UI pages, user flows via playwright-cli

**When to run:** After Tiers 1-4 pass cleanly. Test failures feed back into the same reflection loop — classify as `test-failure` errors in the VALIDATION_ERRORS structure and update the skill markdown accordingly.

**Error collection:**
```
VALIDATION_ERRORS = [
  { source: "test", file: "__tests__/unit/auth.test.ts", line: 15, message: "Expected signIn to return session, got undefined" },
  ...
]
```

---

## Validation Matrix by Skill Type

| Skill Type | Tier 1 | Tier 2 | Tier 3 | Tier 4 | Tier 5 |
|------------|--------|--------|--------|--------|--------|
| Next.js feature | `tsc --noEmit` | `biome check` | `bun run build` | playwright-cli | `bun test` |
| API route | `tsc --noEmit` | `biome check` | `bun run build` | `curl` test endpoints | `bun test` |
| CLI tool | `tsc --noEmit` | `biome check` | N/A | Run the CLI | `bun test` |
| Library | `tsc --noEmit` | `biome check` | `bun run build` | Unit tests | `bun test` |
| Config-only | N/A | N/A | `bun run build` | Dev server starts | N/A |

---

## Error Collection

All errors from validation tiers should be collected into a structured list:

```
VALIDATION_ERRORS = [
  { source: "tsc", file: "src/lib/auth.tsx", line: 42, message: "Property 'foo' does not exist on type 'Bar'" },
  { source: "build", file: "src/components/nav.tsx", line: 10, message: "Module not found: '@/lib/missing'" },
  ...
]
```

This structured format enables systematic reflection and targeted markdown fixes.
