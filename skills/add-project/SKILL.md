---
name: add-project
description: >
  End-to-end project builder: idea → spec → shell → ralph loop → secrets → report.
  SMS notification after every phase. Creates a project directory with symlinked
  skills and a ralph execution loop. Does NOT scaffold Next.js — ralph does that
  as step 1.1 of the plan. Use when the user says "build project", "build a project",
  "new project", "create project", "build from idea", "scaffold and notify",
  "spec a project", "plan a project", or "scaffold project".
metadata:
  author: "@mattwoodco"
  version: 6.4.0
  created: 2026-02-17
  updated: 2026-02-22
---

# Add Project — Idea to Ralph Loop

Single entry point for new projects. Creates the project shell and ralph loop — ralph does the actual building.

**Project path:** The user provides the new project path (e.g. project name or full directory path). add-project creates the shell and the ralph loop at that path. In addition to everything below, add-project (1) **adds the ralph loop to the loops catalog** (`loops/<project-name>/`) so it is registered for future reference and evaluation, and (2) **creates the loop at the user-provided path** in `.ralph/` — the execution loop (PLAN.md, PROMPT.md, AGENT.md, etc.) lives in `{user-path}/.ralph/`.

```
Phase 1: Spec     — idea → docs/specs/{name}.md         (parallel scanning)
Phase 2: Shell    — spec → project dir with symlinks     (NO Next.js — ralph does that)
Phase 3: Ralph    — generate .ralph/ loop from spec      (PLAN.md, PROMPT.md, AGENT.md) + register in loops/
Phase 4: Secrets  — 1Password → .env.local               (batched — one biometric)
Phase 5: Report   — summary + next steps

SMS notification is sent after EVERY phase completes (see "Phase SMS Notifications" below).
Phase summary is presented after EVERY phase (see "Phase Summary" below).
```

**KEY PRINCIPLE: add-project creates the shell. Ralph builds the app.**

add-project currently runs in **fresh-only** mode. PLAN.md step 1.1 is always "Apply `create-next` skill" (Ralph scaffolds Next.js). add-project never runs `create-next-app` itself.

**Scaffold guide:** For skill ordering and the tiered scaffold model (what to install and in what order), use [references/SCAFFOLD.md](references/SCAFFOLD.md) and [references/scaffold-dag.json](references/scaffold-dag.json). The DAG defines Tier 0 (every project: app-shell → runtime → ui-data → testing), Tier 1 (most apps: auth, ai, background-jobs), Tier 2 (specialized packs: collaboration, video-media, visual), and Tier 3 (ops). Use it whenever you derive a skill list or PLAN step order from a no-frills spec.

---

## Subagent Strategy

### Model Routing

| Task Type | Model | Why |
|-----------|-------|-----|
| Skill catalog scanning | haiku | Read-only, fast, 5x cheaper |
| Plan/doc reading | haiku | Simple extraction |
| Template file generation | haiku | Filling known values |
| Dependency graph + mapping | sonnet | Moderate reasoning for toposort |
| Verification checks | haiku | Mechanical validation |
| User interaction + orchestration | opus (inherited) | Complex coordination |

### Parallelization Rules

1. **Independent work = parallel subagents**: Launch multiple Task calls in a single message
2. **Early-start where safe**: Phase 4 (1Password) can start during Phase 3
3. **Converge before user-facing steps**: Wait for all subagents before presenting results

---

## Phase 1: Generate the Project Spec (Delegate to add-spec)

**Invoke the add-spec skill** to produce the spec. add-spec runs the full brainstorming workflow (explore context → clarify → approaches → design approval → design doc), then writes a no-frills spec to `docs/specs/{project-name}.md`.

1. Invoke **add-spec** (load and follow [skills/add-spec/SKILL.md](skills/add-spec/SKILL.md)).
2. add-spec will create:
   - `docs/plans/YYYY-MM-DD-<topic>-design.md` (design doc)
   - `docs/specs/{project-name}.md` (no-frills spec: Mission, Main Features, Major User Flows, Required Screens, Required Features mapped to /skills, Open Gaps, Constraints)
3. Wait until add-spec completes and the spec file exists at `docs/specs/{project-name}.md`.
4. Proceed only after the user has approved the spec (add-spec obtains approval before writing).

**Do not proceed until spec is approved and add-spec has written the spec file.**

**→ Present Phase 1 Summary, then send Phase 1 SMS** (see "Phase SMS Notifications" below)

---

## Phase 2: Create Project Shell (Fast, Sequential)

**Project directory:** Use the path the user provided for the new project (e.g. `{project-name}` or full path). All shell and .ralph artifacts are created under that path; the ralph loop will live in `{user-path}/.ralph/`.

Read the spec. **Skill list:** Extract skill names from the no-frills spec's **Required Features (from /skills)** table. Include `create-next` if not already listed (needed for Ralph step 1.1). **Order** the skill list using [references/scaffold-dag.json](references/scaffold-dag.json): Tier 0 layers first (app-shell, runtime, ui-data, testing), then Tier 1 (auth, ai, background-jobs as present), then Tier 2 packs by dependency; this matches [references/SCAFFOLD.md](references/SCAFFOLD.md) and ensures symlinks and later PLAN steps follow the scaffold guide.

**Fresh mode** — This phase creates ONLY the directory and skill symlinks. No Next.js. No packages.

```bash
# 1. Create project directory
mkdir -p {project-name}/.claude/skills

# 2. Resolve the skills source root once
SKILLS_ROOT=$(cd "$(dirname "$(realpath skills/add-project/SKILL.md)")/../.." && pwd)

# 3. Symlink all skills from the spec using SKILLS_ROOT
cd {project-name}/.claude/skills
for skill in {skills-from-spec}; do
  ln -s "$SKILLS_ROOT/skills/$skill" "$skill"
done
```

**Verify:**

```bash
# All symlinks resolve
for link in {project-name}/.claude/skills/*/SKILL.md; do
  test -f "$link" || echo "BROKEN: $link"
done
```

### 2b: Generate .ralphrc (tool permissions)

**CRITICAL: Without this file, ralph has no tool permissions and will halt on loop 1.**

```bash
cat > {project-name}/.ralphrc << 'RALPHRC'
# Ralph Configuration for {PROJECT_NAME}
# Generated by add-project skill

# Model — use sonnet for balanced cost/capability, opus for complex projects
CLAUDE_MODEL=claude-sonnet-4-6

# Rate limiting
MAX_CALLS_PER_HOUR=100

# Claude timeout per loop iteration (minutes)
CLAUDE_TIMEOUT_MINUTES=15

# Output format
CLAUDE_OUTPUT_FORMAT=json

# Allowed tools — MUST include Task for parallel subagents
# Bash(*) is used instead of granular Bash(cmd *) patterns because:
# 1. Skills install arbitrary packages (bun add, bunx, drizzle-kit, biome, etc.)
# 2. Docker commands vary by project (docker compose, docker exec, etc.)
# 3. Granular patterns are fragile — any new command halts ralph
# 4. Ralph runs locally under developer control, not in production
# playwright-cli is available globally — runs via Bash, no MCP needed
CLAUDE_ALLOWED_TOOLS="Write,Read,Edit,Glob,Grep,Bash(*),Task,WebFetch,WebSearch,ToolSearch,Skill"

# Session continuity — resume between loops
CLAUDE_USE_CONTINUE=true

# Session expiry (hours)
CLAUDE_SESSION_EXPIRY_HOURS=24

# Additional directories to reference (resolved skills root)
ADD_DIRS="{SKILLS_ROOT}"

# Circuit breaker settings
CB_NO_PROGRESS_THRESHOLD=3
CB_SAME_ERROR_THRESHOLD=5
CB_OUTPUT_DECLINE_THRESHOLD=70
CB_COOLDOWN_MINUTES=30
CB_AUTO_RESET=false
RALPHRC
```

Replace `{PROJECT_NAME}`, `{SKILLS_ROOT}` with actual values.

**Model selection for .ralphrc:**

- `claude-sonnet-4-6` — default for most projects (good balance of speed/capability)
- `claude-opus-4-6` — for complex multi-skill projects (20+ skills, heavy custom code)
- `claude-haiku-4-5-20251001` — for simple projects (few skills, mostly boilerplate)

**Why these specific tools:**

| Tool | Why Ralph Needs It |
|------|-------------------|
| `Task` | Parallel subagents (dynamic model selection in PROMPT.md) |
| `Bash(*)` | Skills run arbitrary CLI commands (bun, docker, drizzle-kit, biome, curl, op, playwright-cli) |
| `WebFetch/WebSearch` | Documentation lookups during skill application |
| `ToolSearch` | Discovers and loads MCP tools at runtime |
| `Skill` | Invokes project skills directly |

> **Note:** `playwright-cli` runs via `Bash(*)` — no MCP tool permissions needed.

### 2c: Initialize Git Repository

**CRITICAL: Without a git repo, Ralph's circuit breaker kills the loop.**

Ralph detects progress by running `git diff` to count changed files between loops.
Without a git repo, `files_changed` is always 0, the circuit breaker sees "no progress"
for 3 consecutive loops, and trips — halting execution even though work is actually being done.

```bash
# Ensure .env files are gitignored BEFORE the initial commit
cat >> {project-name}/.gitignore << 'EOF'
.env
.env.local
EOF

# Initialize repo and create initial commit
cd {project-name}
git init
git add -A
git commit -m "initial scaffold"
```

**Important notes:**

- Add `.env` and `.env.local` to `.gitignore` **before** the initial commit to avoid committing secrets
- If using `create-next-app` later (ralph step 1.1), do NOT pass `--disable-git`
- If git was disabled or skipped for any reason, manually run the commands above

**Do not proceed until all symlinks resolve, .ralphrc exists, and git repo is initialized.**

**→ Present Phase 2 Summary, then send Phase 2 SMS** (see "Phase SMS Notifications" below)

---

## Phase 3: Generate Ralph Loop Files

Create the `.ralph/` directory with everything ralph needs to build the project autonomously.

**This is the most important phase. The quality of these files determines how well ralph executes.**

### 3a: Create directory structure

```bash
mkdir -p {project-name}/.ralph/logs
mkdir -p {project-name}/.ralph/screenshots
```

### 3b: Generate PLAN.md from spec

Read the spec file and treat scaffold as **fresh-only**. Build PLAN.md by ordering skills and gaps using [references/scaffold-dag.json](references/scaffold-dag.json): step 1.1 = "Apply `create-next` skill", then one PENDING step per Tier 0 layer (runtime, ui-data, testing) as needed, then Tier 1 (auth, ai, queue) as needed, then Tier 2 packs from the Required Features table in DAG order, then one step per Open Gaps item; add Phase 4 E2E steps for major user flows from the spec. See [references/SCAFFOLD.md](references/SCAFFOLD.md) for the human-readable tier and pack layout.

**MICRO-STEP RULE**: Every step must be small and independently verifiable.

- Each step does ONE thing: apply one skill, create one table, write one component
- Each step has a concrete "Verify" column: a command that returns pass/fail
- Never combine "install + configure + test" into one step — that's three steps
- CUSTOM implementations should be broken into the smallest meaningful units
  (e.g., "create storyboards table" is one step, "create shots table" is another)
- Phase 4 E2E: one Playwright test per user action (never "test the whole page")
- Validation + fix steps at end of each phase: "Validate Phase N" then "Fix Phase N errors"

**Format (fresh):**

```markdown
# {Project Name} — Master Execution Plan

**Created:** {date}
**Status:** READY TO START
**Goal:** {description from spec}
**Scaffold:** fresh

---

## Overview

Apply {skill-count} skills + {custom-count} custom implementations to build {project-name}.
Every step must be tested. ONE step per Ralph loop.

**Rule: ONE step per Ralph loop. Test before marking done.**

### Testing Requirements
...
### Progressive Test Writing
...

---

## Phase 1: Shared Substrate
| Step | Task | Test |
|------|------|------|
| 1.1 | PENDING: Apply `create-next` skill (scaffold Next.js, AGENTS.md, biome, bun install) | `bun run build` passes |
| 1.2 | PENDING: Apply `docker` skill (...) | ... |
...
```

### 3c: Generate PROMPT.md (with dynamic models + parallel subagents)

**This file tells ralph HOW to work. It must include dynamic model selection and
parallel subagent instructions.**

```markdown
# Ralph — {Project Name} Builder

## Context
You are Ralph, an autonomous AI development agent building {project-name}.
You compose {skill-count} skills + {custom-count} custom implementations into
a working Next.js application with playwright-cli-validated interactions.

## CRITICAL: Loop Discipline

**Each loop = ONE task from the plan. Period.**

- Read PLAN.md → find first PENDING step → execute ONLY that step → update PROGRESS.md → STOP
- Do NOT combine multiple steps into one loop
- Do NOT start the next step after finishing one
- Budget: ~50 seconds of work per loop (leaving 10s buffer)
- If a step takes too long, mark it PARTIAL and continue next loop

## Dynamic Model Selection

Use the right model for each sub-task within a step. Launch parallel subagents
whenever tasks are independent.

| Task Type | Model | When to Use |
|-----------|-------|-------------|
| Read a SKILL.md file | haiku | Simple file reading, no reasoning |
| Generate boilerplate files | haiku | Templates with known values (configs, schemas) |
| Install packages + verify | haiku | Mechanical: bun add, check imports |
| Write API routes | sonnet | Moderate logic: request handling, validation |
| Write React components | sonnet | UI logic, hooks, state management |
| Custom architecture (C1-C14) | sonnet | Design decisions, integration patterns |
| Write Playwright tests | sonnet | Test logic, assertions, page objects |
| Write unit/integration tests | sonnet | Test logic, mocking, assertions |
| Write e2e tests (playwright-cli) | sonnet | Browser automation, page assertions |
| Debug build/type errors | sonnet | Error analysis, fix reasoning |
| Complex multi-file changes | opus | Architectural changes touching 5+ files |
| Orchestration + user decisions | opus (inherited) | The main loop always runs on opus |

### Parallel Subagent Rules

**Within each step, maximize parallelism:**

1. When a skill creates multiple independent files → launch parallel haiku/sonnet subagents
   ```

   Example: "Apply db skill" creates schema.ts, drizzle.config.ts, migrate script
   → Launch 3 parallel haiku agents, one per file

   ```

2. When running verification → launch build + lint in parallel
   ```

   Bash: bun run build  (background)
   Bash: bunx biome check .  (background)
   → Wait for both, report results

   ```

3. When testing multiple routes → parallel curl commands
   ```

   Bash: curl /api/route-a & curl /api/route-b & curl /route-c & wait

   ```

4. When a skill needs packages + files → install packages in background while writing files
   ```

   Bash(background): bun add react-hook-form zod @hookform/resolvers
   Write: src/components/form.tsx  (parallel with install)
   → Wait for install before build test

   ```

**NEVER launch subagents across steps. Each step is atomic.**

## How to Apply a Skill

For each "Apply X skill" step:
1. Read `.claude/skills/{skill-name}/SKILL.md`
2. Follow instructions exactly — create files, install packages, modify configs
3. Use parallel subagents for independent file creation within the step
4. After applying: run `bun run build` + `bunx biome check .`
5. If build fails: fix errors (they count as part of this step)
6. If a page was created: verify it returns 200

## Testing Requirements (CRITICAL)

**Every step MUST be tested. Non-negotiable.**

### Build + Lint + Test (every step):
- `bun run build` — must pass
- `bunx biome check .` — must pass
- `bun test` — all tests must pass

### Progressive Test Writing (every step):

Write tests WITH each step — never defer to a later phase:

**Unit tests** (`__tests__/unit/`):
- Utility functions, lib helpers, formatters, validators
- Run with `bun test __tests__/unit/`

**Integration tests** (`__tests__/integration/`):
- API routes, database queries, auth flows
- Run with `bun test __tests__/integration/`

**E2E tests** (`__tests__/e2e/`):
- UI pages, user flows via playwright-cli
- `playwright-cli goto http://localhost:3000/{route}`
- `playwright-cli snapshot` — verify DOM structure
- `playwright-cli click <ref>` — test interactions
- `playwright-cli screenshot --output .ralph/screenshots/{step}.png`
- `playwright-cli console` — check for JS errors
- `playwright-cli eval "document.title"` — assert page state

### For skill steps:
- `bun run build` — must pass
- `bunx biome check .` — must pass
- `bun test` — must pass
- If skill creates a page: `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/{route}` → 200

### For protected pages (after auth):
- Seed: `curl -X POST http://localhost:3000/api/dev/seed`
- Sign in: `curl -c /tmp/cookies.txt -X POST .../api/auth/sign-in/email`
- Test: `curl -b /tmp/cookies.txt http://localhost:3000/{route}` → 200

### Ralph Loop After Each Step:
1. Implement the step
2. Write unit/integration tests for new code
3. `bun run build` + `bunx biome check .`
4. Start dev server (if UI step)
5. `bun test` — run all tests
6. `playwright-cli` for UI validation (if UI step)
7. Mark step done in PLAN.md (change PENDING to DONE)
8. Add a **structured entry** to PROGRESS.md: step id, step label, skills applied for this step (from the plan or "Apply X skill"), outcome (PASS | FAIL | PARTIAL), and ISO timestamp. Use the format in PROGRESS.md (HTML comment + one-line summary) so evaluations can parse loop structure and skill combinations.
9. `git add -A && git commit -m "step {N}: {short description}"` — commit all changes

## Key Principles
- **ONE step per loop** — non-negotiable
- **Git commit after every step** — `git add -A && git commit -m "step {N}: {description}"`
- **Write tests WITH each step** — unit + integration + e2e alongside implementation
- **Use parallel subagents** within steps for independent work
- **Use dynamic models** — haiku for templates, sonnet for logic, opus for architecture
- Read skill files before applying them
- Port fixes back to skills/ via symlinks
- Never cast to `any`, use `useId` for keys, react-hook-form for forms
- API routes over server components for dynamic data

## Status Reporting

At the end of EVERY response, emit the block below. Include **STEP_ID** and **SKILLS_THIS_STEP** so loop structure and skill combinations are traceable for evaluations (e.g. report scripts or loops catalog).

\`\`\`
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
STEP_ID: <e.g. 1.2>
SKILLS_THIS_STEP: <comma-separated skill names applied this loop, e.g. docker,env-config>
TASKS_COMPLETED_THIS_LOOP: 0 | 1
FILES_MODIFIED: <number>
TESTS_STATUS: PASSING | FAILING | NOT_RUN
BUILD_STATUS: PASSING | FAILING | NOT_RUN
PAGES_TESTED: <routes>
TESTS_WRITTEN: <count>
TEST_TYPES: unit | integration | e2e
SUBAGENTS_USED: <count> (haiku: N, sonnet: N)
WORK_TYPE: IMPLEMENTATION | TESTING | FIX
EXIT_SIGNAL: false | true
RECOMMENDATION: <next step>
---END_RALPH_STATUS---
\`\`\`
```

### 3d: Generate AGENT.md

```markdown
# {Project Name} — Agent Instructions

## Project Type
{description from spec}

## Directory Layout
\`\`\`
.claude/skills/    # Symlinked skills ({count} total)
src/               # Next.js app (created by ralph step 1.1)
__tests__/         # Unit, integration, e2e tests
.ralph/            # Execution tracking
  ├── PLAN.md      # Master plan ({step-count} steps)
  ├── PROMPT.md    # Loop discipline + model routing
  ├── PROGRESS.md  # Progress log
  └── screenshots/ # Playwright captures
\`\`\`

## How to Run Validation
1. `bun run build` — zero errors
2. `bunx biome check .` — zero lint violations
3. `bun test` — all tests pass
4. `playwright-cli` for UI validation (runs via Bash, no MCP needed)
5. `curl` for API routes

## Technology Stack
{extracted from spec constraints}
```

### 3e: Generate PROGRESS.md

Ralph updates this file every loop so evaluations can track loop structure and skill combinations over time. Use a **structured entry format** so tooling can parse step id, skills applied, and outcome:

```markdown
# {Project Name} — Progress Log

## How to Use
After each step, append one entry below. Each entry MUST include: step id, step label, skills applied (comma-separated), outcome (PASS | FAIL | PARTIAL), and ISO timestamp. This allows evaluations to track loop structure and skill combinations as the loop runs.

### Entry format (one per step)
<!-- STEP step_id="{N.M}" label="{short label}" skills="{skill-a, skill-b}" outcome="PASS|FAIL|PARTIAL" at="{ISO8601}" -->

---

(empty — ralph fills this in)
```

**Example entry Ralph would add:**
```markdown
<!-- STEP step_id="1.2" label="Apply docker skill" skills="docker,env-config" outcome="PASS" at="2026-02-22T14:30:00Z" -->
**1.2** Apply docker skill — PASS @ 2026-02-22T14:30:00Z
```

### 3f: Generate state files

```bash
echo '{"status": "ready", "timestamp": "{date}"}' > {project-name}/.ralph/progress.json
echo '{"timestamp": "{date}", "loop_count": 0, "status": "ready"}' > {project-name}/.ralph/status.json
```

### 3g: Register the loop in the loops catalog

**Add the ralph loop to `loops/`** so this project's loop is in the catalog (see [loops/README.md](../../loops/README.md) and [GENERATED.md](../../GENERATED.md)). Create `loops/<project-name>/` and copy **all evaluation-relevant artifacts** so the catalog can track loop structure, skill combinations, and relative output over time:

```bash
# From repo root (repo containing loops/)
mkdir -p loops/{project-name}
# Loop definition and structure
cp {project-name}/.ralph/PLAN.md loops/{project-name}/
cp {project-name}/.ralph/PROMPT.md loops/{project-name}/
cp {project-name}/.ralph/AGENT.md loops/{project-name}/
# Progress and outcomes (for evaluations on loop structure and skill combinations)
cp {project-name}/.ralph/PROGRESS.md loops/{project-name}/
cp {project-name}/.ralph/progress.json loops/{project-name}/ 2>/dev/null || true
cp {project-name}/.ralph/status.json loops/{project-name}/ 2>/dev/null || true
# Relative output from runs (when present): logs, reports, screenshots
cp -r {project-name}/.ralph/logs loops/{project-name}/ 2>/dev/null || true
cp {project-name}/.ralph/report_*.json loops/{project-name}/ 2>/dev/null || true
cp {project-name}/.ralph/report_history_*.jsonl loops/{project-name}/ 2>/dev/null || true
cp -r {project-name}/.ralph/screenshots loops/{project-name}/ 2>/dev/null || true
```

**Ongoing updates:** When the ralph loop runs (locally or in CI), sync the same relative output back into `loops/<project-name>/` (e.g. after each run or on a schedule) so the catalog always has the latest PLAN.md, PROGRESS.md, logs, report_*.json, report_history_*.jsonl, and screenshots for evaluations. Evaluations use: (1) **loop structure** — phases and steps from PLAN.md; (2) **skill combinations** — which skills per step and order from PROGRESS.md (and report history); (3) **relative output** — logs, reports, screenshots for each run.

The loop that runs is the one at **the user-provided project path** in `.ralph/`; the copies in `loops/<project-name>/` are for catalog and evaluation.

**Do not proceed until all .ralph/ files are created and the loop is registered in loops/<project-name>/.**

**→ Present Phase 3 Summary, then send Phase 3 SMS** (see "Phase SMS Notifications" below)

---

## Phase 4: Fetch ALL Secrets from 1Password

Use [references/1password-secrets.md](references/1password-secrets.md) for the full workflow.

Minimum requirements for this phase:
- Sign in with `op signin --account my.1password.com` before item reads.
- Dump full `Dev Environment` `notesPlain` into `{PROJECT_NAME}/.env.local`.
- Verify baseline and skill-specific keys exist without printing secret values.
- Batch `op` commands whenever possible to minimize biometric prompts.

**→ Present Phase 4 Summary, then send Phase 4 SMS** (see "Phase SMS Notifications" below)

---

## Phase 5: Final Report

```
Project "{PROJECT_NAME}" — shell created, ralph loop ready!

Location: {path}
Skills linked: {count} (symlinked to skills/)
Ralph loop: .ralph/PLAN.md ({step-count} steps across 4 phases)
Secrets: .env.local (all keys from 1Password "Dev Environment")
SMS: sent after every phase

Ralph features:
  - Dynamic model selection (haiku/sonnet/opus per task type)
  - Parallel subagents within each step
  - Progressive test writing (unit + integration + e2e)
  - playwright-cli validation for all UI (runs via Bash)
  - One step per loop, tested before marking done
  - GitHub Actions UI: collapsible iterations, step summary, annotations
  - Pause/resume: one-click workflows (ralph-pause.yml, ralph-resume.yml)
  - SMS notifications: phase completion, errors, budget alerts

Next steps:
1. cd {PROJECT_NAME}
2. Start ralph — it will begin from step 1.1 (scaffold Next.js via create-next)
3. Ralph applies skills in dependency order, tests each step
4. Fixes port back to skills/ via symlinks
5. Pause anytime via "Ralph: Pause" in GitHub Actions, resume with "Ralph: Resume"
```

**→ Present Phase 5 Summary, then send Phase 5 SMS** (see "Phase SMS Notifications" below)

---

## Phase Summary

**After EVERY phase completes, present a conversational summary to the user before sending the SMS.**

The summary is a narrative recap — not a dry status block. It should read like a developer
explaining what just happened to a colleague. Show your work: code references, file paths,
exact counts, decisions made, and any issues hit along the way.

### Required elements

1. **What was done** — specific actions taken, files created/modified, commands run.
   Include file paths and line numbers where relevant.

   ```
   Created project shell at ~/Developer/media-pipeline/.claude/skills/
   Symlinked 12 skills: db, auth, ai-core, ai-image-gen, storage, ...
   Generated .ralphrc with CLAUDE_MODEL=claude-sonnet-4-6 and Bash(*) permissions
   ```

2. **Key decisions** — any choices made during the phase and why.

   ```
   Used claude-sonnet-4-6 for .ralphrc — 20 skills is moderate complexity,
   sonnet balances cost/capability well here.
   ```

3. **Issues encountered** — problems hit and how they were resolved. Be specific.

   ```
   Symlink for `react-flow` initially pointed to the wrong source path.
   Fixed by resolving a single `SKILLS_ROOT` first, then linking from that path.
   ```

4. **Progress table** — current state across all phases.

   ```
   ┌────────────────┬────────┬────────┐
   │     Phase      │ Status │  Time  │
   ├────────────────┼────────┼────────┤
   │ 1 — Spec       │ DONE   │ 2m 15s │
   │ 2 — Shell      │ DONE   │ 45s    │
   │ 3 — Ralph Loop │ ...... │ .......|
   │ 4 — Secrets    │ ...... │ .......|
   │ 5 — Report     │ ...... │ .......|
   └────────────────┴────────┴────────┘
   Phase 2 of 5 complete
   ```

5. **What's next** — brief preview of the upcoming phase.

   ```
   Next: Phase 3 — Generate ralph loop files (PLAN.md, PROMPT.md, AGENT.md).
   This is the most important phase — plan quality determines ralph's success.
   ```

### Style rules

- **Be honest about mistakes.** If a count was wrong, a path was bad, or something
  needed a retry — say so. Don't hide corrections.
- **Use tables for structured data** — progress, counts, skill lists.
- **Reference specific files and lines** — `Generated .ralphrc (line 144: CLAUDE_MODEL=claude-sonnet-4-6)`
- **Keep it conversational** — not a log dump. Write like you're talking to the developer.
- **Include exact numbers** — "12 skills linked", "48 steps across 4 phases", "23 env vars loaded".
  Count from the source of truth, not memory.
- **Show diffs when applicable** — if a file was modified, show what changed.

### When to present

Present the summary AFTER the phase work is done, BEFORE sending the SMS.
The SMS is a compressed version of the summary (one line). The summary is the full story.

---

## Phase SMS Notifications

See [references/sms-notifications.md](references/sms-notifications.md) for the full send/fallback flow.

Minimum requirements:
- Send SMS after every phase.
- Read recipient from `SMS_TO` in `.env.local`.
- Never block build progress on SMS failure.

---

## Acceptance Criteria

- [ ] Spec file written and approved
- [ ] Project directory created with symlinked skills (NO Next.js yet)
- [ ] All symlinks resolve
- [ ] .ralphrc generated with tool permissions (MUST include Task for parallel subagents)
- [ ] Git repo initialized with initial commit (MUST exist before ralph runs)
- [ ] .ralph/PLAN.md generated from spec (step 1.1 = create-next)
- [ ] .ralph/PROMPT.md includes dynamic model selection + parallel subagent rules
- [ ] .ralph/AGENT.md includes project context + tech stack
- [ ] .ralph/PROGRESS.md created with structured entry format (step id, label, skills, outcome, timestamp) for evaluations on loop structure and skill combinations
- [ ] State files created (progress.json, status.json)
- [ ] Ralph loop registered in loops/<project-name>/ with all evaluation-relevant artifacts (PLAN, PROMPT, AGENT, PROGRESS, state files; logs, report_*.json, report_history_*.jsonl, screenshots when present)
- [ ] ALL env vars fetched from 1Password "Dev Environment" → .env.local (one biometric prompt)
- [ ] Critical keys verified present (DATABASE_URL, AI_GATEWAY_API_KEY, BETTER_AUTH_SECRET, N8N_SMS_KEY + skill-specific keys)
- [ ] Conversational phase summary presented after every phase (Phases 1-5)
- [ ] SMS notification sent after every phase (Phases 1-5)
- [ ] User given clear next steps to start ralph

---

## Fixes & Lessons

See [references/lessons-learned.md](references/lessons-learned.md) for historical build issues and fixes (F1-F16).
