# ralph.config.json — Schema Reference

Central configuration file for Ralph CI. Lives at the project root.
Read by all harness scripts (`run.sh`, `check.sh`, `report.sh`).

---

## Full Schema

```json
{
  "mode": "build | polish",
  "maxIterations": 40,
  "timeoutMinutes": 180,
  "iterationTimeoutMinutes": 30,
  "model": "claude-sonnet-4-6",
  "killSwitch": "RALPH_ENABLED",
  "budgetMaxUsd": 50,
  "concurrency": 3,
  "logRetention": 20,
  "checks": ["build", "typecheck", "lint", "test"],
  "webhook": {
    "url": "https://hooks.slack.com/...",
    "events": ["failure", "success", "stalled", "circuit_breaker"]
  },
  "circuitBreaker": {
    "noProgressThreshold": 3,
    "sameErrorThreshold": 5
  },
  "artifacts": ["logs", "diffs", "screenshots"],
  "vps": {
    "enabled": false,
    "processManager": "pm2",
    "chromeCleanup": true
  }
}
```

---

## Field Reference

### Top-Level Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mode` | `"build" \| "polish"` | `"build"` | **Build**: PLAN.md-driven incremental execution. **Polish**: lint/typecheck/build/test gate with revert on failure. |
| `maxIterations` | `number` | `40` | Hard cap on total loop iterations. Prevents runaway loops. Range: 1-200. |
| `timeoutMinutes` | `number` | `180` | Total wall-clock timeout for the entire harness run. Range: 10-720. |
| `iterationTimeoutMinutes` | `number` | `30` | Per-iteration timeout wrapping the `claude` CLI call. Range: 5-120. |
| `model` | `string` | `"claude-sonnet-4-6"` | Claude model ID. Options: `claude-sonnet-4-6`, `claude-opus-4-6`, `claude-haiku-4-5-20251001`. |
| `killSwitch` | `string` | `"RALPH_ENABLED"` | Name of the environment variable checked each iteration. Set to `"false"` or `"0"` to stop. |
| `budgetMaxUsd` | `number` | `50` | Maximum accumulated USD cost. Harness exits with code 4 when exceeded. Range: 1-500. |
| `concurrency` | `number` | `3` | Number of parallel loops in GitHub Actions matrix / PM2 processes. Range: 1-12. |
| `logRetention` | `number` | `20` | Number of log files to keep before rotation. Oldest are deleted first. Range: 5-100. |
| `checks` | `string[]` | `["build", "typecheck", "lint", "test"]` | Ordered list of checks for `check.sh` to run. See "Available Checks" below. |
| `artifacts` | `string[]` | `["logs", "diffs", "screenshots"]` | Artifact types to upload in GitHub Actions. |

### `webhook` Object

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `url` | `string` | `""` | Webhook endpoint URL. Supports Slack, Discord, or any HTTP endpoint accepting JSON POST. Empty string disables webhooks. |
| `events` | `string[]` | `["failure", "success", "stalled", "circuit_breaker"]` | Events that trigger webhook delivery. |

**Webhook events:**

| Event | Trigger |
|-------|---------|
| `failure` | Any non-zero exit from `run.sh` (timeout, budget, error) |
| `success` | All checks pass — ralph is done |
| `stalled` | Watchdog detects no commits in 24h |
| `circuit_breaker` | No-progress or same-error threshold hit |

**Webhook payload format:**

```json
{
  "text": "Ralph CI [repo-name] — failure (iter 15, $23.50 spent, 12/40 done)",
  "event": "failure",
  "repo": "repo-name",
  "branch": "main",
  "iteration": 15,
  "total_cost_usd": 23.50,
  "plan_progress": "12/40",
  "git_sha": "abc1234",
  "reason": "budget_exceeded",
  "exit_code": 4
}
```

**Slack integration**: Paste a Slack incoming webhook URL. The `text` field renders as the message.

**Discord integration**: Use a Discord webhook URL with `/slack` appended (e.g., `https://discord.com/api/webhooks/.../slack`). Discord's Slack-compatible endpoint reads the `text` field.

**Security warning**: Webhook URLs committed to public repos are visible to anyone. For
public repos, leave `url` empty in the committed config and pass the URL via environment
variable or GitHub Actions secret (`${{ secrets.RALPH_WEBHOOK_URL }}`). The harness also
checks the `RALPH_WEBHOOK_URL` env var as an override.

### `circuitBreaker` Object

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `noProgressThreshold` | `number` | `3` | Number of consecutive iterations with 0 files changed before tripping. Range: 1-10. |
| `sameErrorThreshold` | `number` | `5` | Number of consecutive iterations with the identical error before tripping. Range: 2-20. |

**How progress is detected:**

1. Record `git --no-pager rev-parse HEAD` at iteration start
2. After claude completes, compare HEAD again
3. If HEAD changed → files_changed = count of differing files
4. If HEAD same → check unstaged + staged changes (`git diff --name-only HEAD` + `git diff --cached --name-only`)
5. 0 files changed = no progress

**Parallel loop isolation**: Each loop writes to its own state file (`.harness_state_N`),
report file (`report_N.json`), and history (`report_history_N.jsonl`), keyed by `RALPH_LOOP_ID`.
This prevents race conditions when `concurrency > 1`.

**How same-error is detected:**

1. After `check.sh` runs, extract first error from JSON output
2. Compare to previous iteration's first error (string equality)
3. Increment counter on match, reset on different error or no error

### `vps` Object

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `boolean` | `false` | Whether to create VPS provisioning scripts in Phase 4. |
| `processManager` | `"pm2"` | `"pm2"` | Process manager for VPS mode. Currently only PM2 is supported. |
| `chromeCleanup` | `boolean` | `true` | Install cron job to kill orphaned chromium processes every 15 min. |

---

## Available Checks

The `checks` array controls which checks `check.sh` runs. Order matters — checks run in array order.

| Check | Command | Skip Condition | What It Validates |
|-------|---------|----------------|-------------------|
| `build` | `bun run build` | No `package.json` | Next.js build succeeds with zero errors |
| `typecheck` | `bunx tsc --noEmit` | No `tsconfig.json` | TypeScript compiles with no type errors |
| `lint` | `bunx biome check .` or `bunx eslint .` | No linter config | Code style and lint rules pass |
| `test` | `bun test` | No `*.test.*` or `*.spec.*` files | Unit/integration/e2e tests pass |

**Smart skip logic**: Each check looks for its prerequisite file before running. If the file
doesn't exist, the check is skipped (not failed). This allows `check.sh` to run in projects
that don't yet have TypeScript, tests, or a linter configured.

**Lint detection priority**: biome.json > biome.jsonc > .eslintrc.json > .eslintrc.js > eslint.config.js > eslint.config.mjs

---

## Mode-Specific Behavior

### Build Mode

```json
{ "mode": "build" }
```

- `check.sh` success = ALL checks pass AND PLAN.md has no PENDING steps
- `check.sh` adds a `plan_complete` check that greps PLAN.md for "PENDING:" — fails if any remain
- Iterations are incremental — each builds on the previous
- No revert on failure — partial progress is kept
- Typical config: `maxIterations: 40-80`, `budgetMaxUsd: 50-100`

### Polish Mode

```json
{ "mode": "polish" }
```

- `check.sh` success = ALL checks pass (PLAN.md is ignored)
- On failure, `run.sh` reverts to the previous commit (`git reset --hard HEAD~1`)
- Each iteration is semi-independent
- Typical config: `maxIterations: 10-20`, `budgetMaxUsd: 10-20`

---

## Example Configs

### Minimal (GitHub Actions, build mode)

```json
{
  "mode": "build",
  "maxIterations": 40,
  "budgetMaxUsd": 50,
  "checks": ["build", "typecheck", "lint"]
}
```

All other fields use defaults.

### Full production (VPS + Slack alerts)

```json
{
  "mode": "build",
  "maxIterations": 80,
  "timeoutMinutes": 360,
  "iterationTimeoutMinutes": 45,
  "model": "claude-sonnet-4-6",
  "killSwitch": "RALPH_ENABLED",
  "budgetMaxUsd": 100,
  "concurrency": 6,
  "logRetention": 50,
  "checks": ["build", "typecheck", "lint", "test"],
  "webhook": {
    "url": "https://hooks.slack.com/services/T.../B.../xxx",
    "events": ["failure", "success", "stalled", "circuit_breaker"]
  },
  "circuitBreaker": {
    "noProgressThreshold": 4,
    "sameErrorThreshold": 6
  },
  "artifacts": ["logs", "diffs", "screenshots"],
  "vps": {
    "enabled": true,
    "processManager": "pm2",
    "chromeCleanup": true
  }
}
```

### Polish mode (quick refinement pass)

```json
{
  "mode": "polish",
  "maxIterations": 15,
  "iterationTimeoutMinutes": 15,
  "budgetMaxUsd": 15,
  "concurrency": 1,
  "checks": ["build", "typecheck", "lint"],
  "circuitBreaker": {
    "noProgressThreshold": 2,
    "sameErrorThreshold": 3
  }
}
```

---

## Validation

Always validate after creating or editing:

```bash
jq . ralph.config.json > /dev/null && echo "OK" || echo "FAIL: invalid JSON"
```

Programmatic schema check (optional):

```bash
# Ensure required fields exist
jq -e '.mode and .maxIterations and .budgetMaxUsd' ralph.config.json > /dev/null \
  && echo "OK: required fields present" \
  || echo "FAIL: missing required fields"
```
