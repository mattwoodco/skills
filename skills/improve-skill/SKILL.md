---
name: improve-skill
description: Iteratively refine and validate agent skill markdown files by implementing them in a sandbox, running validation checks (TypeScript, linting, build, browser tests), writing tests, reflecting on errors, and updating the skill documentation until it produces error-free code. Use this skill when you need to polish a skill, refine a skill, test a skill, improve skill documentation, validate a skill, debug skill instructions, or ensure a skill works end-to-end.
metadata:
  author: "@mattwoodco"
  version: 1.2.0
  created: 2026-02-13
  updated: 2026-02-13
---

# Skill Polish — Iterative Skill Refinement Loop

Takes a draft skill markdown file and iteratively implements it in a `sandbox/` directory (its own git repo), validates the output, reflects on errors, updates the markdown, reverts, and retries — until the skill produces a clean, error-free implementation on a fresh run.

## Quick Start

```
1. Point at a skill markdown file (e.g., v1-skills/auth/SKILL.md)
2. Sandbox initializes as its own git repo with a project scaffold
3. Loop: implement → validate → reflect → update markdown → revert → retry
4. Final polished skill saved to skills/<feature>/SKILL.md
```

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                    SKILL POLISH LOOP                     │
│                                                         │
│  ┌──────────┐    ┌───────────┐    ┌──────────────────┐  │
│  │ IMPLEMENT │───▶│ VALIDATE  │───▶│ ERRORS FOUND?    │  │
│  │ in sandbox│    │ tsc/lint/ │    │                  │  │
│  └──────────┘    │ build/    │    │  YES ──▶ REFLECT  │  │
│       ▲          │ browser   │    │         & UPDATE  │  │
│       │          └───────────┘    │         MARKDOWN  │  │
│       │                           │         ▼         │  │
│       │                           │       REVERT      │  │
│       │                           │       SANDBOX     │  │
│       └───────────────────────────│─────────┘         │  │
│                                   │                   │  │
│                                   │  NO ──▶ FINALIZE  │  │
│                                   └──────────────────┘  │
└─────────────────────────────────────────────────────────┘

Sandbox is its own git repo — reverts are instant via git reset.
```

## Prerequisites

- `sandbox/` directory (working area — becomes its own git repo)
- `skills/` directory (output for polished skills)
- Node.js / Bun runtime for validation
- Source skill markdown file to polish

## Workflow Steps

### Phase 0: Pre-flight Checks

Verify the environment before starting.

```bash
# Check sandbox state
ls sandbox/

# If sandbox has a git repo with baseline commit, ask user:
# "Sandbox has baseline. Reuse it or start fresh?"
cd sandbox && git log --oneline -1 2>/dev/null && cd ..

# Verify output directory exists
ls skills/
```

**CRITICAL**: The sandbox is its own git repo, completely independent of the parent project. The parent project does NOT need to be a git repository.

**User decision:**

- **Reuse**: Skip Phase 2, go straight to Phase 1 → Phase 3
- **Start fresh**: Wipe sandbox and re-scaffold in Phase 2

### Phase 1: Select Source Skill

**Agent instructions:**

1. Ask: "Which skill markdown file should I polish?"
2. Accept a file path (e.g., `v1-skills/auth/SKILL.md`)
3. Read the source markdown completely
4. Extract `FEATURE_NAME` from frontmatter `name:` field
5. Copy source to working location:

```bash
mkdir -p skills/<FEATURE_NAME>
cp <SOURCE_PATH> skills/<FEATURE_NAME>/SKILL.md
```

**IMPORTANT**: All markdown edits happen to `skills/<FEATURE_NAME>/SKILL.md`. Never modify the original.

### Phase 2: Initialize Sandbox Project

**Skip this phase if reusing existing baseline** (user chose "Reuse" in Phase 0).

**Agent instructions:**

1. Read skill's Prerequisites and Installation sections to determine project type
2. Clean sandbox:

```bash
rm -rf sandbox/* sandbox/.* 2>/dev/null
```

1. Initialize appropriate project:

```bash
# Example for Next.js:
cd sandbox && bunx create-next-app@latest . --typescript --tailwind --eslint --app --src-dir --no-import-alias --use-bun && cd ..

# Example for Node.js:
cd sandbox && bun init -y && cd ..
```

1. Install skill-specified dependencies
2. Verify clean build: `cd sandbox && bun run build && cd ..`
3. **Initialize sandbox git repo and commit baseline:**

```bash
cd sandbox
git init
git add -A
git commit -m "baseline: scaffold for <FEATURE_NAME>"
cd ..
```

This baseline enables fast reverts without touching the parent project.

### Phase 3: Implementation Loop

Set `ITERATION=1` and `MAX_ITERATIONS=10`.

---

#### Step 3a: Implement

Read the **current** working markdown (`skills/<FEATURE_NAME>/SKILL.md`) and follow it exactly.

**Agent instructions:**

1. Read the full skill markdown
2. Follow every Setup Step / Implementation instruction
3. Create all files from "What Gets Created" section
4. Run all installation commands
5. Use placeholder values for env vars
6. **Do not improvise** — test whether the markdown alone is sufficient

**File mapping**: All skill paths are relative to sandbox root:

- `src/lib/auth.tsx` → `sandbox/src/lib/auth.tsx`

#### Step 3b: Validate

Run the automated validation script:

```bash
./scripts/validate.sh
```

This script runs multi-tier validation and outputs structured error JSON. See [VALIDATION.md](references/VALIDATION.md) for validation strategies.

**Manual validation tiers** (if not using script):

**Tier 1 — TypeScript (always run):**

```bash
cd sandbox && bunx tsc --noEmit 2>&1
```

**Tier 2 — Linting (if configured):**

```bash
cd sandbox && bunx biome check . 2>&1
# OR: bunx eslint . 2>&1
```

**Tier 3 — Build (if build script exists):**

```bash
cd sandbox && bun run build 2>&1
```

**Tier 4 — Browser (if skill has TEST_PAGE.md):**

```bash
# Start dev server in background
cd sandbox && bun run dev &
DEV_PID=$!
sleep 3
```

Use **playwright-cli** (runs via Bash, no MCP needed) to validate:

- `playwright-cli open http://localhost:3000/<test-route>` → navigate to the test route
- `playwright-cli snapshot` → verify elements are present in the DOM
- `playwright-cli console` → check for JS errors or warnings
- `playwright-cli screenshot --output screenshots/<feature>.png` → capture visual state
- `playwright-cli click <ref>` → interact with UI elements

```bash
kill $DEV_PID
```

**Tier 5 — Test Writing (after Tiers 1-4 pass):**

Once the implementation passes Tiers 1-4, write tests for the skill's code:

- **Unit tests** (`sandbox/__tests__/unit/`): utility functions, lib helpers, validators
- **Integration tests** (`sandbox/__tests__/integration/`): API routes, database queries
- **Component tests** (`sandbox/__tests__/e2e/`): UI pages via playwright-cli

```bash
cd sandbox && bun test 2>&1
```

Test failures feed back into the reflection loop — classify as `test-failure` errors and update the skill markdown with fixes (missing exports, wrong function signatures, etc.).

**Collect errors** into structured format:

```
VALIDATION_ERRORS = [
  { source: "tsc", file: "...", line: N, message: "..." },
  ...
]
```

#### Step 3c: Decision Point

**If VALIDATION_ERRORS is empty:**
→ Skip to **Phase 4: Finalize**

**If VALIDATION_ERRORS is not empty and ITERATION < MAX_ITERATIONS:**
→ Continue to **Step 3d: Reflect**

**If ITERATION >= MAX_ITERATIONS:**
→ Stop and report:
> "Reached maximum iterations (10). Remaining errors: [list]. Markdown saved but may need manual refinement."

#### Step 3d: Reflect and Update Markdown

**CRITICAL**: Analyze each error and determine what the skill markdown should have said to prevent it.

**Agent instructions for each error:**

1. **Classify the error** — see [ERROR_CLASSIFICATION.md](references/ERROR_CLASSIFICATION.md) for types:
   - `missing-dependency` — Package not in Installation section
   - `missing-file` — Imported file not created by skill
   - `type-error` — TypeScript type mismatch
   - `api-change` — Library API changed
   - `missing-config` — Config file or env var missing
   - `wrong-path` — File path mismatch
   - `missing-step` — Undocumented setup step
   - `code-error` — Bug in code snippet

2. **Determine the fix:**
   - What specific markdown change would prevent this error?
   - Add dependency? Fix snippet? Add file? Reorder steps?

3. **Apply the fix** to `skills/<FEATURE_NAME>/SKILL.md`:
   - Edit relevant section
   - Add missing dependencies to Installation
   - Fix code snippets
   - Add missing files to "What Gets Created"
   - Update import paths

**Reflection comment** (add to markdown):

```markdown
<!-- POLISH ITERATION {N}
Errors found: {count}
Fixes applied:
- {classification}: {brief description}
-->
```

#### Step 3e: Revert Sandbox

Reset sandbox to baseline using its own git repo:

```bash
cd sandbox
git checkout -- .
git clean -fd
cd ..
```

**Verify revert:**

```bash
cd sandbox && git status --porcelain && cd ..
# Should be empty (clean working tree)
```

#### Step 3f: Increment and Loop

```
ITERATION = ITERATION + 1
```

→ Go back to **Step 3a: Implement**

---

### Phase 4: Finalize

Implementation passed all validation. Markdown is polished.

**Agent instructions:**

1. **Clean up markdown:**
   - Remove `<!-- POLISH ITERATION -->` comments
   - Bump patch version in frontmatter
   - Update `updated:` date
   - Verify "What Gets Created" is accurate
   - Verify Installation has all packages

2. **Revert sandbox** one final time:

```bash
cd sandbox
git checkout -- .
git clean -fd
cd ..
```

1. **Report to user:**

```
Skill polished successfully!

Feature: <FEATURE_NAME>
Iterations: {ITERATION}
Output: skills/<FEATURE_NAME>/SKILL.md

Changes made during polishing:
- {summary of key fixes}

The skill markdown now produces a clean, error-free implementation.
Sandbox baseline preserved for future runs.
```

## Acceptance Criteria

- [ ] Agent checks sandbox state (reuse baseline or start fresh)
- [ ] Agent asks user to select source skill markdown
- [ ] Agent copies source to `skills/<feature>/SKILL.md` (never modifies original)
- [ ] Agent initializes sandbox as its own git repo with scaffold (or reuses existing)
- [ ] Agent implements the skill exactly as written (no improvisation)
- [ ] Agent runs TypeScript, lint, build, and browser validation
- [ ] Agent writes unit/integration/e2e tests after implementation passes validation
- [ ] On errors (including test failures): agent reflects, classifies, and updates markdown
- [ ] On errors: agent reverts sandbox via git before re-implementing
- [ ] Agent loops until clean validation or max iterations
- [ ] On success: agent cleans markdown, reverts sandbox to baseline
- [ ] Final markdown at `skills/<feature>/SKILL.md`
- [ ] Original source markdown never modified
- [ ] Sandbox baseline preserved for future runs

## Additional References

- **[VALIDATION.md](references/VALIDATION.md)** — Validation strategies and tier details
- **[ERROR_CLASSIFICATION.md](references/ERROR_CLASSIFICATION.md)** — Error types and markdown fix locations
- **[EDGE_CASES.md](references/EDGE_CASES.md)** — Edge cases and troubleshooting guide
