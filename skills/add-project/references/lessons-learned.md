# Add Project - Lessons Learned

Historical fixes from real builds. Keep this as reference context, not primary run instructions.

## F1: Never scaffold Next.js - ralph does it

**Problem**: add-project ran `bunx create-next-app` directly, which used wrong flags (`--eslint` instead of `--biome`, missing `--react-compiler`, `--turbopack`, `--empty`).
**Fix**: add-project creates the shell only. Ralph step 1.1 reads the `create-next` SKILL.md and follows current instructions.

## F2: create-next-app conflicts with existing directories

**Problem**: `create-next-app` refuses to run if the target directory contains files (`.claude/`, `.ralph/`, etc.).
**Fix**: add-project no longer runs create-next-app. Ralph step 1.1 handles this via the create-next skill workaround.

## F3: Missing ralph loop files

**Problem**: Project had no `.ralph/` directory, so ralph could not run autonomously.
**Fix**: Phase 3 generates `PLAN.md`, `PROMPT.md`, `AGENT.md`, `PROGRESS.md`, and state files.

## F4: Multiple 1Password biometric prompts

**Problem**: Separate `op` CLI calls triggered repeated biometric prompts.
**Fix**: Batch `op` commands into one chained script in one process.

## F5: 1Password CLI not signed in despite configured accounts

**Problem**: `op whoami` failed even when accounts were listed.
**Fix**: Run `op signin --account my.1password.com` before other `op` commands.

## F6: 1Password item only fetched one key

**Problem**: Only `N8N_SMS_KEY` was fetched, leaving runtime keys missing.
**Fix**: Dump entire `notesPlain` from `Dev Environment` into `.env.local`, then verify required keys.

## F7: Haiku subagent prompt too long for catalog scan

**Problem**: Scanning all skills in one haiku subagent exceeded context limits.
**Fix**: Split scans across multiple agents or scan frontmatter only.

## F8: Steps too coarse to verify

**Problem**: Single steps combined multiple operations, making failures hard to isolate.
**Fix**: Enforce micro-steps with one action and one explicit verification command.

## F9: PROMPT.md missing dynamic model routing

**Problem**: Everything ran on the inherited high-cost model.
**Fix**: Add explicit model routing and within-step parallelization guidance.

## F10: Symlink paths varied by project location

**Problem**: Relative path assumptions broke when projects were siblings instead of nested.
**Fix**: Resolve a single skills root path and generate symlinks from it.

## F11: Missing .ralphrc caused permission_denied on loop 1

**Problem**: Shell and `.ralph/` existed, but no `.ralphrc` tool permissions.
**Fix**: Generate `.ralphrc` in Phase 2 with required tools (`Task`, `Bash(*)`, `ToolSearch`, `WebFetch`, `WebSearch`, `Skill`).

## F12: No git repo tripped circuit breaker

**Problem**: Circuit breaker used `git diff`; no repo meant false no-progress detection.
**Fix**: Initialize git and create an initial commit before ralph runs.

## F13: playwright-cli is more reliable than Playwright MCP for this flow

**Problem**: MCP tool discovery and permissions were inconsistent across environments.
**Fix**: Use `playwright-cli` via `Bash(*)` for browser verification commands.

## F14: Progressive test writing prevents test debt

**Problem**: Deferring all tests to final E2E made regressions harder to locate.
**Fix**: Write unit/integration/e2e tests incrementally with each step.

## F15: Commit every step to preserve checkpoints

**Problem**: Multi-step uncommitted work made rollback and progress auditing difficult.
**Fix**: Commit after each completed step with a step-tagged commit message.

## F16: 1Password dump lacked infrastructure defaults

**Problem**: Secrets were present but infra defaults were missing, causing CI/build validation failures.
**Fix**: `env-config` reconciles `.env.local` with `.env.local.example`, appending only missing defaults.
