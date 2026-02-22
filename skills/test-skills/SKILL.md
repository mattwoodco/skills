---
name: test-skills
description: Meta skill that applies ALL skills into sandboxes in dependency order, validates the full composition, fixes errors in the skill markdowns, and ports fixes back to skills/. Use this skill when you need to test all skills together, validate skill composition, run integration tests across skills, test dependency ordering, or verify that skills work when layered on top of each other.
metadata:
  author: "@mattwoodco"
  version: 1.0.0
  created: 2026-02-13
  updated: 2026-02-13
---

# Test All Skills — Full Composition Validation
<!-- markdownlint-disable MD040 MD060 -->

Applies **every** skill into sandboxes in topological (dependency) order, validates each layer, fixes broken skill markdowns, and ports fixes back to `skills/`. This tests real-world skill composition — not just individual skills in isolation.

## Quick Start

```
1. Scan all skills/*/SKILL.md — parse frontmatter, build dependency graph
2. Topologically sort skills, group into sandbox families
3. Present execution plan to user for approval
4. Per sandbox group: scaffold → layered implementation loop → report
5. Final report at test-results/report.md
```

## How It Works

```
┌────────────────────────────────────────────────────────────────────┐
│                     TEST ALL SKILLS                                │
│                                                                    │
│  ┌──────────────┐    ┌──────────────┐    ┌─────────────────────┐  │
│  │ SCAN & PLAN  │───▶│  INIT GROUP  │───▶│ LAYERED IMPL LOOP   │  │
│  │ parse deps,  │    │  sandbox per │    │                     │  │
│  │ topo sort,   │    │  family      │    │  for skill in order:│  │
│  │ group skills │    └──────────────┘    │    tag ──▶ impl     │  │
│  └──────────────┘                        │    ──▶ validate     │  │
│                                          │    ──▶ on error:    │  │
│                                          │       fix markdown  │  │
│                                          │       revert to tag │  │
│                                          │       retry (max 3) │  │
│                                          │    ──▶ on success:  │  │
│                                          │       tag + next    │  │
│                                          └─────────────────────┘  │
│                                                    │               │
│                                          ┌─────────▼───────────┐  │
│                                          │      REPORT         │  │
│                                          │  test-results/      │  │
│                                          │  report.md          │  │
│                                          └─────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘

Each skill is git-tagged so any skill can be reverted independently.
```

## Prerequisites

- `skills/` directory with polished skill markdowns
- `sandbox/` directory (working area — created per group)
- Node.js / Bun runtime for validation
- `scripts/validate.sh` from this skill's directory

## Workflow Steps

### Phase 0: Scan & Plan

Parse every saved skill, build the dependency graph, topologically sort, group into sandbox families, and present the execution plan.

**Agent instructions:**

1. **Scan all skills:**

```bash
ls skills/*/SKILL.md
```

1. **Parse frontmatter** from each skill:
   - Extract `name` field
   - Extract `dependencies` array (may be empty or missing)
   - Record skill path

2. **Build dependency graph** — see [DEPENDENCY_RESOLUTION.md](references/DEPENDENCY_RESOLUTION.md):
   - Create adjacency list: `skill → [dependencies]`
   - Detect cycles (error if found — report and stop)
   - Topologically sort using Kahn's algorithm
   - Group into sandbox families using connected components

3. **Known sandbox groups** (based on current skills):

**Group A — Next.js Family** (~38 skills connected through dependency chains):

Skills that directly or transitively depend on `create-next`, `env-config`, `docker`, or connect through shared dependencies like `auth`, `db`, `storage`:

```
Layer 0 (no deps):     create-next, docker, env-config
Layer 1:               add-shadcn, add-pwa, add-seo, auth, db, storage, email, ai-core
Layer 2:               auth-dev, storage-ui, media-bunny, realtime, image-editor, ai-chat,
                       payments, queue, ai-image-gen, ai-video-gen, ai-rag-ingest, ai-rag-viewer
Layer 3:               cms, ai-tools, ai-reasoning, ai-rag-vectors,
                       embeddable-widget, voice-retell
Layer 4:               ai-memory, ai-tasks, ai-artifacts, ai-generative-ui, ai-rag-chat, ai-mcp,
                       knowledge-sync
Layer 5:               ai-rag-app
```

**Group B — Standalone** (skills with no deps that don't assume Next.js):

```
setup-lefthook, mcp-server, yt-dlp, lottie, react-flow, react-three-fiber, e2e,
env-from-1password, workflow
```

**Note:** `e2e` has no `dependencies` frontmatter but assumes a Next.js app exists. If it fails standalone, move it to Group A at the appropriate layer.

### Phase 0b: Catalog Health Validation (required)

Before presenting the plan, validate catalog consistency so renamed/deleted skills are caught early.

Run:

```bash
# Skills on disk
DISK_SKILLS=$(ls -d skills/*/SKILL.md 2>/dev/null | sed 's|skills/||;s|/SKILL.md||' | sort)

# Skills listed in README markdown tables
README_SKILLS=$(rg -o '(?<=\\| `)[^`]+' README.md | sort)

# Skills listed in add-feature catalog bullets
ADD_FEATURE_SKILLS=$(rg -o '^- [a-z0-9-]+' skills/add-feature/SKILL.md | sed 's/^- //' | sort)

# Skill names referenced by scaffold DAG
DAG_SKILLS=$(jq -r '
  [
    .tiers[].layers[]?.skills[]?,
    .tiers[].packs[]?[]?.skills[]?,
    .extensionPoints[]?.id?
  ] | .[]
' skills/add-project/references/scaffold-dag.json | sort -u)

echo "---- On disk but missing from README ----"
comm -23 <(echo "$DISK_SKILLS") <(echo "$README_SKILLS")

echo "---- In README but missing on disk ----"
comm -13 <(echo "$DISK_SKILLS") <(echo "$README_SKILLS")

echo "---- In add-feature but missing on disk ----"
comm -13 <(echo "$DISK_SKILLS") <(echo "$ADD_FEATURE_SKILLS")

echo "---- On disk but missing from add-feature ----"
comm -23 <(echo "$DISK_SKILLS") <(echo "$ADD_FEATURE_SKILLS")

echo "---- In scaffold DAG but missing on disk ----"
comm -13 <(echo "$DISK_SKILLS") <(echo "$DAG_SKILLS")
```

If any of these lists are non-empty, treat as a catalog drift defect and fix docs before continuing skill composition tests.

1. **Present plan to user** — show:
   - Total skill count per group
   - Layered execution order for Group A
   - List of standalone skills for Group B
   - Estimated scope ("Group A: ~38 skills across 6 layers, Group B: ~8 standalone")

2. **Wait for user approval** before proceeding. User may:
   - Approve full plan
   - Request only Group A or Group B
   - Request a subset of layers
   - Skip specific skills

---

### Phase 1: Initialize Sandbox (per group)

**Agent instructions — repeat for each sandbox group:**

1. **Determine sandbox directory:**

```bash
# Group A uses: sandbox/
# Group B uses: sandbox-standalone/
```

1. **Clean and scaffold:**

```bash
# Group A (Next.js):
rm -rf sandbox/* sandbox/.* 2>/dev/null
cd sandbox && bunx create-next-app@latest . --typescript --tailwind --eslint --app --src-dir --no-import-alias --use-bun && cd ..

# Group B (Node.js / varies per skill):
rm -rf sandbox-standalone/* sandbox-standalone/.* 2>/dev/null
cd sandbox-standalone && bun init -y && cd ..
```

1. **Git init + baseline commit:**

```bash
cd sandbox
git init
git add -A
git commit -m "baseline: scaffold for test-skills group-a"
cd ..
```

1. **Verify clean build:**

```bash
cd sandbox && bun run build && cd ..
```

---

### Phase 2: Layered Implementation Loop

Process skills in topological order within each group. Each skill builds on top of the previous ones.

**Set tracking variables:**

```
RESULTS = {}          # skill → { status, attempts, fixes }
CURRENT_LAYER = 0
```

**For each skill in topological order:**

#### Step 2a: Tag Before Implementation

Create a git tag so this skill can be reverted independently:

```bash
cd sandbox
git tag "before-<SKILL_NAME>"
cd ..
```

#### Step 2b: Implement

Read the skill markdown and implement it on top of the current sandbox state.

**Agent instructions:**

1. Read `skills/<SKILL_NAME>/SKILL.md` completely
2. Follow every Setup Step / Implementation instruction
3. Create all files from "What Gets Created" section
4. Run all installation commands
5. Use placeholder values for env vars
6. **Do not improvise** — test whether the markdown alone is sufficient
7. **Respect existing files** — skills layer on top of each other; do NOT overwrite files created by previous skills unless the current skill explicitly says to modify them

**File mapping**: All skill paths are relative to sandbox root:

- `src/lib/auth.tsx` → `sandbox/src/lib/auth.tsx`

#### Step 2c: Validate

Run the validation script:

```bash
cd sandbox && ../scripts/validate.sh . && cd ..
```

**Collect errors** into structured format:

```
VALIDATION_ERRORS = [
  { source: "tsc", file: "...", line: N, message: "..." },
  ...
]
```

#### Step 2d: Decision Point

**If VALIDATION_ERRORS is empty:**

- Record: `RESULTS[SKILL_NAME] = { status: "PASS", attempts: 1, fixes: [] }`
- Write progressive tests for this skill (see Step 2g)
- Tag success: `cd sandbox && git add -A && git commit -m "skill: <SKILL_NAME>" && git tag "after-<SKILL_NAME>" && cd ..`
- Continue to next skill

**If VALIDATION_ERRORS is not empty and attempts < 3:**

- Continue to Step 2e (fix and retry)

**If attempts >= 3:**

- Record: `RESULTS[SKILL_NAME] = { status: "FAIL", attempts: 3, fixes: [...], remaining_errors: [...] }`
- **Revert this skill only**: `cd sandbox && git reset --hard "before-<SKILL_NAME>" && git clean -fd && cd ..`
- **Skip this skill** and continue to next
- **IMPORTANT**: Downstream skills that depend on this one should also be skipped. Add them to a `SKIPPED` set with reason "dependency <SKILL_NAME> failed"

#### Step 2e: Fix Markdown and Retry

**CRITICAL**: Analyze each error and determine what the skill markdown should have said to prevent it.

**Agent instructions:**

1. **Classify each error** — see [ERROR_CLASSIFICATION.md](references/ERROR_CLASSIFICATION.md)

2. **Determine the fix** — What specific markdown change prevents this error?

3. **Apply the fix** directly to `skills/<SKILL_NAME>/SKILL.md`:
   - Add missing dependencies to Installation
   - Fix code snippets
   - Add missing files to "What Gets Created"
   - Update import paths
   - **IMPORTANT**: Consider composition context. Errors may arise because the skill doesn't account for files/types created by its dependencies. The fix should make the skill markdown aware of its dependency context.

4. **Composition-specific error types** (beyond standard ERROR_CLASSIFICATION):

| Error Type | Description | Fix Location |
|---|---|---|
| `composition-conflict` | Two skills create/modify the same file incompatibly | Later skill's Setup Steps — add merge instructions |
| `missing-import-from-dep` | Skill imports from a dependency's file but path is wrong | Code snippet import paths |
| `type-mismatch-across-skills` | Type exported by one skill doesn't match what another expects | Earlier or later skill's type definitions |
| `env-var-collision` | Two skills use same env var name for different purposes | Environment Variables section |
| `route-conflict` | Two skills register the same API route | Later skill's route path |

1. **Revert this skill's changes only:**

```bash
cd sandbox
git reset --hard "before-<SKILL_NAME>"
git clean -fd
cd ..
```

1. **Increment attempt counter** and go back to Step 2b

Record fixes: `RESULTS[SKILL_NAME].fixes.push({ error_type, description })`

#### Step 2f: Layer Boundary Check

When all skills in a layer are processed, verify the cumulative build still passes:

```bash
cd sandbox && ../scripts/validate.sh . && cd ..
```

If the validate.sh check fails with errors not attributable to any single skill, investigate composition issues between skills in this layer.

Also run all accumulated tests at layer boundaries:

```bash
cd sandbox && bun test 2>&1 && cd ..
```

If a test fails at the layer boundary that wasn't failing after individual skills, investigate composition issues between skills in this layer.

#### Step 2g: Progressive Test Writing

After each skill passes validation (Step 2d PASS branch), write tests for that skill's contribution:

**Agent instructions:**

1. **Determine what this skill added** — new files, new routes, new components, new utilities
2. **Write tests** organized by skill:

```bash
mkdir -p sandbox/__tests__/<SKILL_NAME>
```

- **Unit tests**: For utility functions, lib helpers, validators added by the skill
- **Integration tests**: For API routes, database operations added by the skill
- **E2E tests**: For UI pages/components added by the skill (using playwright-cli)

1. **Run all accumulated tests:**

```bash
cd sandbox && bun test 2>&1
```

1. **If a previously-passing test fails** → composition regression detected:
   - The current skill broke something a previous skill relied on
   - Fix the current skill's markdown to prevent the conflict
   - This is a `composition-conflict` error type (see Step 2e)

2. **Install vitest on first use** (if not already installed):

```bash
cd sandbox && bun add -d vitest @testing-library/react @testing-library/jest-dom 2>/dev/null
```

**Track test counts:** `RESULTS[SKILL_NAME].tests_written = N`

---

### Phase 3: Report

Generate a comprehensive test report.

**Agent instructions:**

1. **Create report directory:**

```bash
mkdir -p test-results
```

1. **Generate `test-results/report.md`:**

```markdown
# Test All Skills — Report

**Date:** YYYY-MM-DD
**Total skills:** N
**Passed:** N | **Failed:** N | **Skipped:** N

## Summary

| Skill | Group | Layer | Status | Attempts | Fixes Applied | Tests Written |
|-------|-------|-------|--------|----------|---------------|---------------|
| create-next | A | 0 | PASS | 1 | 0 | 2 |
| auth | A | 1 | PASS | 2 | 1 | 5 |
| ... | ... | ... | ... | ... | ... | ... |

## Fixes Applied

### <skill-name> (attempt N)

**Error:** <classification> — <description>
**Fix:** <what was changed in the markdown>
**File:** skills/<skill-name>/SKILL.md

---

## Failed Skills

### <skill-name>

**Attempts:** 3
**Remaining errors:**
- <error details>

**Downstream impact:** [list of skipped skills]

---

## Composition Issues

Any cross-skill conflicts discovered during layered validation.

## Test Coverage

| Layer | Skills | Tests Written | Tests Passing |
|-------|--------|--------------|---------------|
| 0 | N | N | N |
| 1 | N | N | N |
| ... | ... | ... | ... |
| **Total** | **N** | **N** | **N** |

Regression tests caught: N (tests that failed due to composition conflicts)

---

## Recommendations

- Skills that need manual attention
- Dependency ordering suggestions
- Composition patterns that should be documented
```

1. **Report to user:**

```
Test All Skills — Complete!

Group A (Next.js):  X/Y passed, Z failed
Group B (Standalone): X/Y passed, Z failed

Fixes applied: N total across M skills
Fixes ported back to skills/

Full report: test-results/report.md
```

---

## Handling Edge Cases

### Circular Dependencies

If the topological sort detects a cycle:

1. Report the cycle to the user: "Circular dependency detected: A → B → C → A"
2. Ask user how to break the cycle (which dependency to remove)
3. Do NOT proceed until the cycle is resolved

### Missing Dependencies

If a skill lists a dependency that doesn't exist in `skills/`:

1. Report: "Skill `NAME` depends on `MISSING_DEPENDENCY` which is not in skills/"
2. Options: skip the skill, or proceed without that dependency

### Skills That Modify Shared Files

Common shared files that multiple skills touch:

- `src/app/layout.tsx` — many skills add providers here
- `src/lib/db/schema.ts` — database skills add tables
- `.env.local` — most skills add env vars
- `next.config.ts` — some skills add config

**Strategy**: Skills should use comment slots (`// [skill-name]: description`) to mark where they inject code. When implementing a skill that modifies a shared file, look for existing comment slots from dependency skills and inject at the right location.

### Standalone Skills with Hidden Next.js Assumptions

Some Group B skills may fail because they implicitly assume a Next.js project despite having no declared dependencies. If a standalone skill fails with errors like "Cannot find module 'next/...'" or missing `tsconfig.json` paths:

1. Move the skill to Group A at Layer 0 (alongside `create-next`)
2. Add `create-next` to its `dependencies` in the frontmatter as a fix
3. Port the dependency fix back to `skills/<name>/SKILL.md`
4. Re-run in Group A

---

## Acceptance Criteria

- [ ] Agent scans all skills and parses dependency frontmatter
- [ ] Catalog health check passes across README.md, add-feature catalog, and scaffold-dag.json
- [ ] Agent builds dependency graph and detects cycles
- [ ] Agent topologically sorts skills and groups into sandbox families
- [ ] Agent presents execution plan to user and waits for approval
- [ ] Agent initializes separate sandboxes per group with git repos
- [ ] Agent implements skills in topological order, each git-tagged
- [ ] Agent validates after each skill implementation
- [ ] On errors: agent fixes skill markdown and retries (max 3 attempts)
- [ ] On failure after 3 attempts: agent skips skill and its dependents
- [ ] Fixes are applied directly to `skills/<name>/SKILL.md`
- [ ] Layer boundary checks validate cumulative composition
- [ ] Progressive tests written for each passing skill
- [ ] All accumulated tests pass at layer boundaries
- [ ] Test counts tracked per skill in results
- [ ] Agent generates `test-results/report.md` with full results
- [ ] Agent reports summary to user with pass/fail counts

## Additional References

- **[DEPENDENCY_RESOLUTION.md](references/DEPENDENCY_RESOLUTION.md)** — Topological sort, cycle detection, grouping algorithm
- **[ERROR_CLASSIFICATION.md](references/ERROR_CLASSIFICATION.md)** — Error types and markdown fix locations
