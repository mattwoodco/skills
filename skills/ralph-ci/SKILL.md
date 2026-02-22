---
name: ralph-ci
description: >
  CI infrastructure for Ralph loops: GitHub Actions (matrix parallelism) and VPS (PM2).
  Adds deterministic success gates, zombie protection, kill switches, webhook alerts,
  cost controls, and circuit breakers. Downstream consumer of add-project — layers CI
  onto an existing project shell that already has .ralph/PLAN.md, .ralph/PROMPT.md, .ralphrc.
  Use when the user says "add CI to ralph", "ralph CI", "ralph github actions",
  "ralph VPS", "add CI loops", "ralph harness", or "CI for ralph".
metadata:
  author: "@mattwoodco"
  version: 2.0.0
  created: 2026-02-18
  updated: 2026-02-19
  dependencies: [add-project]
---

# Ralph CI — Reliable Loop Infrastructure

Single skill with two modes (GitHub Actions vs VPS) controlled by `ralph.config.json`.
The harness scripts are identical across modes — only the process manager differs.

**This skill is a downstream consumer of `add-project`.** It layers CI infrastructure
onto an existing project that already has `.ralph/PLAN.md`, `.ralph/PROMPT.md`, `.ralphrc`, etc.

---

## What Gets Created

```
ralph.config.json                    # Central config (mode, iterations, budget, checks, webhook, sms)
harness/
  run.sh                             # Main loop runner (~250 lines, GitHub Actions UI)
  check.sh                           # Deterministic success gate (~100 lines)
  report.sh                          # Structured logging + webhook + SMS reporting (~200 lines)
harness/vps/
  bootstrap.sh                       # Hetzner/DO VPS provisioning script
  ecosystem.config.cjs               # PM2 process definitions
  cleanup.sh                         # Chrome zombie killer (cron)
.github/workflows/
  ralph-loop.yml                     # Main CI loop with matrix strategy
  ralph-watchdog.yml                 # Scheduled health check (cron)
  ralph-kill.yml                     # Emergency kill switch via workflow_dispatch
  ralph-pause.yml                    # One-click pause (graceful, state preserved)
  ralph-resume.yml                   # One-click resume (unpauses + triggers loop)
```

---

## Prerequisites

- Project with `.ralph/PLAN.md`, `.ralph/PROMPT.md`, `.ralphrc` (created by `add-project`)
- Git repository initialized with at least one commit
- `jq` available on the system (standard on GitHub Actions runners, installed by VPS bootstrap)
- **GitHub Actions secrets** (F24):
  - `ANTHROPIC_API_KEY` — must be a direct Anthropic API key (`sk-ant-*`), NOT a gateway/proxy key (`vck_*`, etc.). Claude Code CLI only accepts direct Anthropic keys.
  - `GH_PAT` — GitHub Personal Access Token with repo variable write access (for kill switch + pause/resume)
  - `N8N_SMS_KEY` — (optional) API key for SMS notifications via n8n webhook

---

## Phases

| Phase | What It Does |
|-------|-------------|
| 1. Configure | Generate `ralph.config.json` with project-specific values |
| 2. Harness | Create `harness/run.sh`, `check.sh`, `report.sh` |
| 3. GitHub Actions | Create `.github/workflows/ralph-loop.yml`, `ralph-watchdog.yml`, `ralph-kill.yml`, `ralph-pause.yml`, `ralph-resume.yml` |
| 4. VPS (optional) | Create `harness/vps/bootstrap.sh`, `ecosystem.config.cjs`, `cleanup.sh` |
| 5. Template Setup | Configure repo as GitHub template (optional), add badges to README |
| 6. Verification | Test check.sh standalone, test kill switch, validate YAML/JSON |

---

## Phase 1: Generate `ralph.config.json`

Create the central configuration file at the project root. This file supersedes `.ralphrc`
for CI — `.ralphrc` is still sourced for claude-specific settings (tools, session), but the
harness reads all loop config from this JSON file.

See [references/ralph-config-schema.md](references/ralph-config-schema.md) for full schema docs.

### Detection: Build vs Polish mode

Ask the user, or detect automatically:

- If `.ralph/PLAN.md` has PENDING steps with "Apply `X` skill" → **build** mode
- If `.ralph/PLAN.md` has only lint/typecheck/test steps → **polish** mode
- If no `.ralph/PLAN.md` → ask the user

### Default config

```json
{
  "mode": "build",
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
    "url": "",
    "events": ["failure", "success", "stalled", "circuit_breaker"]
  },
  "circuitBreaker": {
    "noProgressThreshold": 3,
    "sameErrorThreshold": 5
  },
  "sms": {
    "enabled": false,
    "url": "https://n8n.mattwood.co/webhook/surge-sms",
    "apiKeyEnv": "N8N_SMS_KEY",
    "to": "",
    "events": [
      "phase_complete",
      "success",
      "failure",
      "circuit_breaker",
      "budget_exceeded",
      "max_iterations",
      "kill_switch",
      "paused",
      "resumed",
      "verify_failure"
    ]
  },
  "artifacts": ["logs", "diffs", "screenshots"],
  "vps": {
    "enabled": false,
    "processManager": "pm2",
    "chromeCleanup": true
  }
}
```

### Customization prompts

Ask the user about:

1. **Mode** — build or polish? (default: build)
2. **Max iterations** — how many loops before stopping? (default: 40)
3. **Budget** — max USD to spend? (default: $50)
4. **Concurrency** — how many parallel loops in CI? (default: 3)
5. **Webhook URL** — Slack/Discord webhook for alerts? (default: empty)
6. **VPS mode** — deploy to VPS? (default: false)
7. **Checks** — which checks to gate on? (default: all four)
8. **SMS notifications** — phone number for SMS alerts? (default: disabled)
   If provided, set `sms.enabled: true` and `sms.to` to the phone number.

Write the config:

```bash
cat > ralph.config.json << 'EOF'
{CONFIG_JSON}
EOF
```

Validate:

```bash
jq . ralph.config.json > /dev/null && echo "OK: valid JSON" || echo "FAIL: invalid JSON"
```

**Do not proceed until ralph.config.json validates.**

---

## Phase 2: Create Harness Scripts

Create `harness/` directory and the three core scripts.

```bash
mkdir -p harness
```

### 2a: `harness/run.sh` — Main Loop Runner

This is the core of Ralph CI. It orchestrates the loop, handles crashes, tracks budget,
and enforces all safety mechanisms.

**Key design choices:**

- Uses `set -uo pipefail` (no `-e`) so the loop survives individual command failures
- State files are scoped by `RALPH_LOOP_ID` so parallel loops don't collide
- Claude JSON output is captured raw (not piped through sanitize) to preserve cost parsing
- Uses `gtimeout` on macOS, `timeout` on Linux (auto-detected)
- All git commands use `--no-pager` to prevent hangs on VPS
- GitHub Actions integration: `::group::`/`::endgroup::` for collapsible iteration sections
- Step name from PLAN.md displayed in group labels and `$GITHUB_STEP_SUMMARY`
- Pause check (`RALPH_PAUSED`) for graceful stop/resume (F25)
- Phase completion detection with SMS notifications (F26)

```bash
cat > harness/run.sh << 'RUNSH'
#!/usr/bin/env bash
set -uo pipefail

# Ralph CI — Main Loop Runner
# Exit codes: 0=success, 2=circuit breaker, 3=kill switch, 4=budget exceeded, 5=timeout, 6=paused
#
# GitHub Actions integration:
#   - Each iteration wrapped in ::group:: / ::endgroup:: (collapsible sections)
#   - Step name from PLAN.md used as group label
#   - Progress table written to $GITHUB_STEP_SUMMARY after each iteration
#   - ::notice:: and ::error:: annotations for key events

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$PROJECT_DIR/ralph.config.json"
STATE_DIR="$PROJECT_DIR/.ralph"
LOG_DIR="$STATE_DIR/logs"

# ─── Detect GitHub Actions ──────────────────────────────────────────────────
IS_CI="${GITHUB_ACTIONS:-false}"

# GitHub Actions log grouping helpers
gh_group() {
  if [[ "$IS_CI" == "true" ]]; then
    echo "::group::$1"
  else
    echo "─── $1 ───"
  fi
}

gh_endgroup() {
  if [[ "$IS_CI" == "true" ]]; then
    echo "::endgroup::"
  fi
}

gh_notice() {
  if [[ "$IS_CI" == "true" ]]; then
    echo "::notice::$1"
  fi
}

gh_error() {
  if [[ "$IS_CI" == "true" ]]; then
    echo "::error::$1"
  fi
}

gh_warning() {
  if [[ "$IS_CI" == "true" ]]; then
    echo "::warning::$1"
  fi
}

# ─── Loop ID (for parallel execution isolation) ─────────────────────────────
LOOP_ID="${RALPH_LOOP_ID:-0}"
STATE_FILE="$STATE_DIR/.harness_state_${LOOP_ID}"

# ─── Load Config ─────────────────────────────────────────────────────────────
if [[ ! -f "$CONFIG" ]]; then
  echo "FATAL: $CONFIG not found" >&2
  exit 1
fi
if ! jq empty "$CONFIG" 2>/dev/null; then
  echo "FATAL: $CONFIG is not valid JSON" >&2
  exit 1
fi

config() { jq -r "$1 // empty" "$CONFIG"; }

MODE=$(config '.mode')
MAX_ITER=$(config '.maxIterations')
TIMEOUT_MIN=$(config '.timeoutMinutes')
ITER_TIMEOUT_MIN=$(config '.iterationTimeoutMinutes')
MODEL=$(config '.model')
KILL_VAR=$(config '.killSwitch')
BUDGET_MAX=$(config '.budgetMaxUsd')
LOG_RETENTION=$(config '.logRetention')
NO_PROGRESS_THRESH=$(config '.circuitBreaker.noProgressThreshold')
SAME_ERROR_THRESH=$(config '.circuitBreaker.sameErrorThreshold')

# Defaults for missing config fields
: "${MODE:=build}"
: "${MAX_ITER:=40}"
: "${TIMEOUT_MIN:=180}"
: "${ITER_TIMEOUT_MIN:=30}"
: "${MODEL:=claude-sonnet-4-6}"
: "${KILL_VAR:=RALPH_ENABLED}"
: "${BUDGET_MAX:=50}"
: "${LOG_RETENTION:=20}"
: "${NO_PROGRESS_THRESH:=3}"
: "${SAME_ERROR_THRESH:=5}"

# ─── Cross-platform timeout command ─────────────────────────────────────────
if command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout"
else
  echo "WARN: No timeout command found (install coreutils). Per-iteration timeout disabled." >&2
  TIMEOUT_CMD=""
fi

# ─── Source .ralphrc for claude settings ─────────────────────────────────────
RALPHRC="$PROJECT_DIR/.ralphrc"
if [[ -f "$RALPHRC" ]]; then
  # shellcheck source=/dev/null
  source "$RALPHRC"
fi

# ─── Init State ──────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    ITERATION=$(jq -r '.iteration // 0' "$STATE_FILE")
    TOTAL_COST=$(jq -r '.total_cost // 0' "$STATE_FILE")
    NO_PROGRESS_COUNT=$(jq -r '.no_progress_count // 0' "$STATE_FILE")
    LAST_ERROR=$(jq -r '.last_error // ""' "$STATE_FILE")
    SAME_ERROR_COUNT=$(jq -r '.same_error_count // 0' "$STATE_FILE")
  else
    ITERATION=0
    TOTAL_COST=0
    NO_PROGRESS_COUNT=0
    LAST_ERROR=""
    SAME_ERROR_COUNT=0
  fi
}

save_state() {
  local tmp_state="${STATE_FILE}.tmp"
  cat > "$tmp_state" << STATEEOF
{
  "iteration": $ITERATION,
  "total_cost": $TOTAL_COST,
  "no_progress_count": $NO_PROGRESS_COUNT,
  "last_error": $(echo "$LAST_ERROR" | jq -Rs .),
  "same_error_count": $SAME_ERROR_COUNT,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "mode": "$MODE",
  "loop_id": "$LOOP_ID"
}
STATEEOF
  mv "$tmp_state" "$STATE_FILE"  # atomic write
}

load_state

# ─── Secret-safe logging ────────────────────────────────────────────────────
sanitize() {
  sed -E 's/(API_KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL)[=:][^ "]+/\1=***REDACTED***/gi'
}

log() {
  echo "[$(date -u +%H:%M:%S)][loop-$LOOP_ID] $*" | sanitize
}

# ─── Read current step name from PLAN.md ─────────────────────────────────────
get_next_step() {
  local plan="$STATE_DIR/PLAN.md"
  if [[ -f "$plan" ]]; then
    local line
    line=$(grep -m1 "PENDING:" "$plan" 2>/dev/null || echo "")
    if [[ -n "$line" ]]; then
      local step_num task_desc
      step_num=$(echo "$line" | sed -n 's/.*| \([0-9]*\.[0-9]*\) |.*/\1/p')
      task_desc=$(echo "$line" | sed -n 's/.*PENDING: \(.*\) |.*/\1/p' | head -c 80)
      echo "${step_num}: ${task_desc}"
      return
    fi
  fi
  echo "unknown step"
}

# ─── Plan progress counts ───────────────────────────────────────────────────
get_plan_progress() {
  local plan="$STATE_DIR/PLAN.md"
  local done_count=0
  local pending_count=0
  if [[ -f "$plan" ]]; then
    done_count=$(grep -c "DONE:" "$plan" 2>/dev/null) || true
    pending_count=$(grep -c "PENDING:" "$plan" 2>/dev/null) || true
    : "${done_count:=0}"
    : "${pending_count:=0}"
  fi
  echo "$done_count $pending_count"
}

# ─── Phase name lookup (customize per project in PLAN.md) ───────────────────
phase_name() {
  case "$1" in
    1) echo "Foundation" ;;
    2) echo "Core Features" ;;
    3) echo "Advanced Features" ;;
    4) echo "Testing + Polish" ;;
    *) echo "Phase $1" ;;
  esac
}

# ─── Write GitHub Step Summary ──────────────────────────────────────────────
write_summary() {
  [[ "$IS_CI" != "true" ]] && return
  [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] && return

  local progress
  progress=$(get_plan_progress)
  local done_count=${progress%% *}
  local pending_count=${progress##* }
  local total=$((done_count + pending_count))
  local pct=0
  [[ $total -gt 0 ]] && pct=$((done_count * 100 / total))

  # Build phase progress rows
  local plan="$STATE_DIR/PLAN.md"
  local phase_rows=""
  for phase in 1 2 3 4; do
    local p_done=0
    local p_pending=0
    local p_total=0
    if [[ -f "$plan" ]]; then
      p_done=$(grep "| ${phase}\.[0-9]" "$plan" 2>/dev/null | grep -c "DONE:" 2>/dev/null) || true
      p_pending=$(grep "| ${phase}\.[0-9]" "$plan" 2>/dev/null | grep -c "PENDING:" 2>/dev/null) || true
      : "${p_done:=0}"
      : "${p_pending:=0}"
      p_total=$((p_done + p_pending))
    fi

    local status_emoji="⏳"
    if [[ $p_pending -eq 0 && $p_done -gt 0 ]]; then
      status_emoji="✅"
    elif [[ $p_done -gt 0 ]]; then
      status_emoji="🔨"
    fi

    phase_rows="${phase_rows}| ${status_emoji} Phase ${phase}: $(phase_name "$phase") | ${p_done}/${p_total} |"$'\n'
  done

  # Progress bar (20 chars wide)
  local filled=$((pct / 5))
  local empty=$((20 - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar="${bar}█"; done
  for ((i=0; i<empty; i++)); do bar="${bar}░"; done

  local repo_name
  repo_name=$(basename "$PROJECT_DIR")

  cat > "$GITHUB_STEP_SUMMARY" << SUMMARYEOF
## Ralph CI — ${repo_name} Build Progress

\`${bar}\` **${pct}%** (${done_count}/${total} steps)

| Phase | Progress |
|-------|----------|
${phase_rows}
**Loop ${LOOP_ID}** · Iteration ${ITERATION}/${MAX_ITER} · Cost: \$${TOTAL_COST} / \$${BUDGET_MAX} · Model: ${MODEL}

| Metric | Value |
|--------|-------|
| Current step | $(get_next_step) |
| Files changed this iter | ${FILES_CHANGED:-0} |
| No-progress count | ${NO_PROGRESS_COUNT}/${NO_PROGRESS_THRESH} |
| Elapsed | ${ELAPSED_MIN:-0}m / ${TIMEOUT_MIN}m |
SUMMARYEOF
}

# ─── Cleanup trap ────────────────────────────────────────────────────────────
cleanup() {
  local exit_code=$?
  gh_endgroup  # close any open group
  log "Cleaning up (exit code: $exit_code)"

  # Kill orphaned chromium processes
  pkill -f "chromium.*--headless" 2>/dev/null || true
  pkill -f "chrome.*--headless" 2>/dev/null || true

  # Save final state
  save_state

  # Write final summary
  FILES_CHANGED="${FILES_CHANGED:-0}"
  ELAPSED_MIN="${ELAPSED_MIN:-0}"
  write_summary

  # Report final status (include last check output for fix step generation)
  if [[ $exit_code -ne 0 ]]; then
    local check_arg=""
    if [[ -f "${ITER_LOG:-}.check" ]]; then
      check_arg="--check-output ${ITER_LOG}.check"
    fi
    "$SCRIPT_DIR/report.sh" --event failure --exit-code "$exit_code" --loop-id "$LOOP_ID" $check_arg || true
  fi
}
trap cleanup EXIT

# ─── Log rotation ────────────────────────────────────────────────────────────
rotate_logs() {
  local count
  count=$(find "$LOG_DIR" -name "loop_${LOOP_ID}_*.log" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$count" -gt "$LOG_RETENTION" ]]; then
    local to_remove=$((count - LOG_RETENTION))
    find "$LOG_DIR" -name "loop_${LOOP_ID}_*.log" -type f -print0 | \
      xargs -0 ls -t | tail -n "$to_remove" | xargs rm -f
    log "Rotated $to_remove old log files"
  fi
}

# ─── Main Loop ───────────────────────────────────────────────────────────────
gh_group "🚀 Ralph CI — Starting (mode=$MODE, budget=\$$BUDGET_MAX, model=$MODEL)"
log "Ralph CI starting — mode=$MODE, max_iter=$MAX_ITER, budget=\$$BUDGET_MAX"
log "Resuming from iteration $ITERATION, accumulated cost=\$$TOTAL_COST"
gh_endgroup

LOOP_START=$(date +%s)
ELAPSED_MIN=0
FILES_CHANGED=0

while [[ "$ITERATION" -lt "$MAX_ITER" ]]; do
  ITERATION=$((ITERATION + 1))
  ITER_LOG="$LOG_DIR/loop_${LOOP_ID}_iter_${ITERATION}.log"

  # Read current step name for the group label
  STEP_NAME=$(get_next_step)

  gh_group "⚡ Iteration ${ITERATION}/${MAX_ITER} — ${STEP_NAME}"
  log "━━━ Iteration $ITERATION / $MAX_ITER — $STEP_NAME ━━━"

  # ── 1. Kill switch check ──
  KILL_VALUE="${!KILL_VAR:-true}"
  if [[ "$KILL_VALUE" == "false" || "$KILL_VALUE" == "0" ]]; then
    log "Kill switch $KILL_VAR is disabled. Exiting."
    gh_error "Kill switch $KILL_VAR is disabled — ralph stopped"
    gh_endgroup
    "$SCRIPT_DIR/report.sh" --event kill_switch --loop-id "$LOOP_ID" || true
    exit 3
  fi

  # ── 1b. Pause check (F25) ──
  PAUSED="${RALPH_PAUSED:-false}"
  if [[ "$PAUSED" == "true" || "$PAUSED" == "1" ]]; then
    log "Ralph is PAUSED. Saving state and exiting gracefully."
    gh_warning "Ralph is PAUSED — saving state at iteration $ITERATION"
    gh_endgroup
    save_state
    "$SCRIPT_DIR/report.sh" --event paused --iteration "$ITERATION" --total-cost "$TOTAL_COST" --loop-id "$LOOP_ID" || true
    exit 6
  fi

  # ── 2. Workflow timeout check ──
  NOW=$(date +%s)
  ELAPSED_MIN=$(( (NOW - LOOP_START) / 60 ))
  if [[ "$ELAPSED_MIN" -ge "$TIMEOUT_MIN" ]]; then
    log "Workflow timeout reached ($ELAPSED_MIN >= $TIMEOUT_MIN min). Exiting."
    gh_warning "Workflow timeout reached (${ELAPSED_MIN}m >= ${TIMEOUT_MIN}m)"
    gh_endgroup
    exit 5
  fi

  # ── 3. Record start SHA ──
  START_SHA=$(cd "$PROJECT_DIR" && git --no-pager rev-parse HEAD 2>/dev/null || echo "no-git")

  # ── 4. Run check.sh — if passes, we're done ──
  log "Running check.sh..."
  if "$SCRIPT_DIR/check.sh" > "$ITER_LOG.check" 2>&1; then
    log "All checks passed! Ralph CI complete."
    gh_notice "✅ All checks passed — build complete!"
    gh_endgroup
    "$SCRIPT_DIR/report.sh" --event success --loop-id "$LOOP_ID" || true
    write_summary
    exit 0
  fi

  # ── 5. Run claude with per-iteration timeout ──
  log "Running claude (timeout: ${ITER_TIMEOUT_MIN}m, model: $MODEL)..."

  # F22: --print requires -p flag for prompt, NOT a positional argument
  RALPH_PROMPT="Read .ralph/PROMPT.md for loop discipline, then read .ralph/PLAN.md, find the first PENDING step, execute it, run checks, update PLAN.md and PROGRESS.md, then git commit."

  CLAUDE_ARGS=(
    --print
    --output-format json
    --model "$MODEL"
    --max-turns 30
    -p "$RALPH_PROMPT"
  )

  # Add allowed tools from .ralphrc
  if [[ -n "${CLAUDE_ALLOWED_TOOLS:-}" ]]; then
    CLAUDE_ARGS+=(--allowedTools "$CLAUDE_ALLOWED_TOOLS")
  fi

  # Capture raw JSON output (do NOT pipe through sanitize — it corrupts JSON fields)
  CLAUDE_OUTPUT=""
  CLAUDE_EXIT=0
  if [[ -n "$TIMEOUT_CMD" ]]; then
    CLAUDE_OUTPUT=$(cd "$PROJECT_DIR" && "$TIMEOUT_CMD" "${ITER_TIMEOUT_MIN}m" \
      claude "${CLAUDE_ARGS[@]}" \
      2>"$ITER_LOG") || CLAUDE_EXIT=$?
  else
    CLAUDE_OUTPUT=$(cd "$PROJECT_DIR" && \
      claude "${CLAUDE_ARGS[@]}" \
      2>"$ITER_LOG") || CLAUDE_EXIT=$?
  fi

  if [[ $CLAUDE_EXIT -eq 124 ]]; then
    log "Claude timed out after ${ITER_TIMEOUT_MIN}m"
    gh_warning "Claude timed out after ${ITER_TIMEOUT_MIN}m on: ${STEP_NAME}"
  elif [[ $CLAUDE_EXIT -ne 0 ]]; then
    log "Claude exited with code $CLAUDE_EXIT"
    gh_error "Claude exited with code $CLAUDE_EXIT on: ${STEP_NAME}"
  else
    log "Claude completed successfully"
  fi

  # ── 6. Parse output for cost ──
  ITER_COST=0
  if [[ -n "$CLAUDE_OUTPUT" ]]; then
    ITER_COST=$(echo "$CLAUDE_OUTPUT" | jq -r '.cost_usd // .total_cost_usd // .result.cost_usd // 0' 2>/dev/null || echo "0")
  fi
  TOTAL_COST=$(echo "$TOTAL_COST + $ITER_COST" | bc 2>/dev/null || echo "$TOTAL_COST")

  # ── 7. Budget check ──
  OVER_BUDGET=$(echo "$TOTAL_COST > $BUDGET_MAX" | bc 2>/dev/null || echo "0")
  if [[ "$OVER_BUDGET" == "1" ]]; then
    log "Budget exceeded: \$$TOTAL_COST > \$$BUDGET_MAX. Exiting."
    gh_error "Budget exceeded: \$$TOTAL_COST > \$$BUDGET_MAX"
    gh_endgroup
    "$SCRIPT_DIR/report.sh" --event budget_exceeded --loop-id "$LOOP_ID" || true
    exit 4
  fi

  # ── 8. Progress detection ──
  END_SHA=$(cd "$PROJECT_DIR" && git --no-pager rev-parse HEAD 2>/dev/null || echo "no-git")
  FILES_CHANGED=0
  if [[ "$START_SHA" != "$END_SHA" && "$START_SHA" != "no-git" ]]; then
    FILES_CHANGED=$(cd "$PROJECT_DIR" && git --no-pager diff --name-only "$START_SHA" HEAD 2>/dev/null | wc -l | tr -d ' ')
  else
    # Check for unstaged + staged changes
    FILES_CHANGED=$(cd "$PROJECT_DIR" && git --no-pager diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')
    STAGED=$(cd "$PROJECT_DIR" && git --no-pager diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    FILES_CHANGED=$((FILES_CHANGED + STAGED))
  fi

  log "Files changed: $FILES_CHANGED, cost this iteration: \$$ITER_COST"

  # ── 9. Circuit breaker: no-progress ──
  if [[ "$FILES_CHANGED" -eq 0 ]]; then
    NO_PROGRESS_COUNT=$((NO_PROGRESS_COUNT + 1))
    log "No progress detected ($NO_PROGRESS_COUNT / $NO_PROGRESS_THRESH)"
    gh_warning "No progress on: ${STEP_NAME} (${NO_PROGRESS_COUNT}/${NO_PROGRESS_THRESH})"
    if [[ "$NO_PROGRESS_COUNT" -ge "$NO_PROGRESS_THRESH" ]]; then
      log "Circuit breaker tripped: no progress for $NO_PROGRESS_THRESH iterations"
      gh_error "Circuit breaker: no progress for $NO_PROGRESS_THRESH iterations on ${STEP_NAME}"
      gh_endgroup
      "$SCRIPT_DIR/report.sh" --event circuit_breaker --reason "no_progress" --loop-id "$LOOP_ID" || true
      exit 2
    fi
  else
    NO_PROGRESS_COUNT=0
    gh_notice "✅ Iteration ${ITERATION} complete — ${STEP_NAME} (+${FILES_CHANGED} files, \$${ITER_COST})"
  fi

  # ── 10. Circuit breaker: same error ──
  CURRENT_ERROR=""
  if [[ -f "$ITER_LOG.check" ]]; then
    CURRENT_ERROR=$(jq -r '.errors[0] // ""' "$ITER_LOG.check" 2>/dev/null || head -1 "$ITER_LOG.check" 2>/dev/null || echo "")
  fi
  if [[ -n "$CURRENT_ERROR" && "$CURRENT_ERROR" == "$LAST_ERROR" ]]; then
    SAME_ERROR_COUNT=$((SAME_ERROR_COUNT + 1))
    log "Same error repeated ($SAME_ERROR_COUNT / $SAME_ERROR_THRESH): $CURRENT_ERROR"
    gh_warning "Same error repeated (${SAME_ERROR_COUNT}/${SAME_ERROR_THRESH}): ${CURRENT_ERROR}"
    if [[ "$SAME_ERROR_COUNT" -ge "$SAME_ERROR_THRESH" ]]; then
      log "Circuit breaker tripped: same error for $SAME_ERROR_THRESH iterations"
      gh_error "Circuit breaker: same error repeated $SAME_ERROR_THRESH times: ${CURRENT_ERROR}"
      gh_endgroup
      "$SCRIPT_DIR/report.sh" --event circuit_breaker --reason "same_error" --loop-id "$LOOP_ID" || true
      exit 2
    fi
  else
    SAME_ERROR_COUNT=0
    LAST_ERROR="$CURRENT_ERROR"
  fi

  # ── 11. Git commit if changes exist ──
  if [[ "$FILES_CHANGED" -gt 0 ]]; then
    (cd "$PROJECT_DIR" && git add -A && git commit -m "ralph-ci: loop $LOOP_ID, iteration $ITERATION" --no-verify) || true
  fi

  # ── 12. Report iteration ──
  "$SCRIPT_DIR/report.sh" --event iteration \
    --iteration "$ITERATION" \
    --cost "$ITER_COST" \
    --total-cost "$TOTAL_COST" \
    --files-changed "$FILES_CHANGED" \
    --loop-id "$LOOP_ID" || true

  # ── 12b. Detect phase completion ──
  PLAN_FILE="$STATE_DIR/PLAN.md"
  PHASES_DONE_FILE="$STATE_DIR/.phases_done_${LOOP_ID}"
  if [[ -f "$PLAN_FILE" ]]; then
    PREV_PHASES_DONE=""
    [[ -f "$PHASES_DONE_FILE" ]] && PREV_PHASES_DONE=$(cat "$PHASES_DONE_FILE" 2>/dev/null)

    CURRENT_PHASES_DONE=""
    for phase in 1 2 3 4; do
      phase_pending_actual=$(grep "| ${phase}\.[0-9]" "$PLAN_FILE" 2>/dev/null | grep -c "PENDING:" 2>/dev/null) || true
      : "${phase_pending_actual:=0}"
      phase_done=$(grep "| ${phase}\.[0-9]" "$PLAN_FILE" 2>/dev/null | grep -c "DONE:" 2>/dev/null) || true
      : "${phase_done:=0}"

      if [[ "$phase_pending_actual" -eq 0 && "$phase_done" -gt 0 ]]; then
        CURRENT_PHASES_DONE="${CURRENT_PHASES_DONE}${phase},"
        if [[ ! "$PREV_PHASES_DONE" == *"${phase},"* ]]; then
          log "Phase $phase complete! ($phase_done steps done)"
          gh_notice "🎉 Phase ${phase} ($(phase_name "$phase")) complete! (${phase_done} steps)"
          "$SCRIPT_DIR/report.sh" --event phase_complete \
            --reason "phase_${phase}" \
            --iteration "$ITERATION" \
            --cost "$ITER_COST" \
            --total-cost "$TOTAL_COST" \
            --loop-id "$LOOP_ID" || true
        fi
      fi
    done
    echo -n "$CURRENT_PHASES_DONE" > "$PHASES_DONE_FILE"
  fi

  # ── 12c. Update GitHub Step Summary ──
  write_summary

  # Close this iteration's group
  gh_endgroup

  # ── 13. Polish mode: revert if checks fail ──
  if [[ "$MODE" == "polish" && "$FILES_CHANGED" -gt 0 ]]; then
    if ! "$SCRIPT_DIR/check.sh" > /dev/null 2>&1; then
      log "Polish mode: checks failed after iteration, reverting..."
      (cd "$PROJECT_DIR" && git reset --hard HEAD~1) || true
    fi
  fi

  # ── 14. Save state + rotate logs ──
  save_state
  rotate_logs

  log "Iteration $ITERATION complete. Cost so far: \$$TOTAL_COST"
done

log "Max iterations reached ($MAX_ITER). Exiting."
gh_error "Max iterations reached ($MAX_ITER) — ralph stopped"
"$SCRIPT_DIR/report.sh" --event max_iterations --loop-id "$LOOP_ID" || true
exit 2
RUNSH

chmod +x harness/run.sh
```

### 2b: `harness/check.sh` — Deterministic Success Gate

Runs ALL checks even if one fails (provides full picture). Outputs structured JSON
to stdout, progress to stderr. Smart skip logic for missing tools.

**Key design choices:**

- No `set -e` so ALL checks run even if one fails
- Exit code captured correctly (no `|| true` masking)
- In build mode, also verifies PLAN.md has no PENDING steps
- Biome detection handles both `biome.json` and `biome.jsonc`
- Empty arrays handled safely with bash 4+ `${arr[@]+"${arr[@]}"}` pattern

```bash
cat > harness/check.sh << 'CHECKSH'
#!/usr/bin/env bash
set -uo pipefail

# Ralph CI — Deterministic Success Gate
# Outputs JSON to stdout. Progress to stderr.
# Exit 0 = all checks pass. Exit 1 = at least one check failed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$PROJECT_DIR/ralph.config.json"

config() { jq -r "$1 // empty" "$CONFIG" 2>/dev/null; }

MODE=$(config '.mode')
: "${MODE:=build}"

CHECKS=$(config '.checks[]' 2>/dev/null || echo -e "build\ntypecheck\nlint\ntest")

RESULTS=()
ALL_PASS=true
ERRORS=()

cd "$PROJECT_DIR"

run_check() {
  local name="$1"
  local cmd="$2"
  local skip_if="$3"

  # Smart skip logic
  if [[ -n "$skip_if" && ! -f "$skip_if" ]]; then
    echo "  SKIP: $name ($skip_if not found)" >&2
    RESULTS+=("{\"name\":\"$name\",\"status\":\"skipped\",\"reason\":\"$skip_if not found\"}")
    return 0
  fi

  echo "  RUN:  $name" >&2
  local output start_time end_time duration exit_code
  start_time=$(date +%s)

  # Capture exit code WITHOUT || true (which masks failures)
  output=$(eval "$cmd" 2>&1)
  exit_code=$?

  end_time=$(date +%s)
  duration=$((end_time - start_time))

  if [[ $exit_code -eq 0 ]]; then
    echo "  PASS: $name (${duration}s)" >&2
    RESULTS+=("{\"name\":\"$name\",\"status\":\"pass\",\"duration\":$duration}")
  else
    echo "  FAIL: $name (exit $exit_code, ${duration}s)" >&2
    ALL_PASS=false
    local safe_output
    safe_output=$(echo "$output" | head -20 | jq -Rs .)
    RESULTS+=("{\"name\":\"$name\",\"status\":\"fail\",\"duration\":$duration,\"exit_code\":$exit_code,\"output\":$safe_output}")
    ERRORS+=("$name")
  fi
}

echo "Ralph CI — Running checks..." >&2

# ─── Build mode: check PLAN.md for PENDING steps ────────────────────────────
if [[ "$MODE" == "build" ]]; then
  PLAN_FILE="$PROJECT_DIR/.ralph/PLAN.md"
  if [[ -f "$PLAN_FILE" ]]; then
    PENDING_COUNT=$(grep -c "PENDING:" "$PLAN_FILE" 2>/dev/null) || true
    : "${PENDING_COUNT:=0}"
    if [[ "$PENDING_COUNT" -gt 0 ]]; then
      echo "  FAIL: plan_complete ($PENDING_COUNT PENDING steps remain)" >&2
      ALL_PASS=false
      RESULTS+=("{\"name\":\"plan_complete\",\"status\":\"fail\",\"output\":\"$PENDING_COUNT PENDING steps in PLAN.md\"}")
      ERRORS+=("plan_complete")
    else
      echo "  PASS: plan_complete (no PENDING steps)" >&2
      RESULTS+=("{\"name\":\"plan_complete\",\"status\":\"pass\"}")
    fi
  else
    echo "  SKIP: plan_complete (no PLAN.md found)" >&2
    RESULTS+=("{\"name\":\"plan_complete\",\"status\":\"skipped\",\"reason\":\"no PLAN.md\"}")
  fi
fi

# ─── Run configured checks ──────────────────────────────────────────────────
while IFS= read -r check; do
  [[ -z "$check" ]] && continue
  case "$check" in
    build)
      run_check "build" "bun run build" "package.json"
      ;;
    typecheck)
      run_check "typecheck" "bunx tsc --noEmit" "tsconfig.json"
      ;;
    lint)
      # Check for biome first (both .json and .jsonc), then eslint
      if [[ -f "biome.json" ]]; then
        run_check "lint" "bunx biome check ." ""
      elif [[ -f "biome.jsonc" ]]; then
        run_check "lint" "bunx biome check ." ""
      elif [[ -f ".eslintrc.json" || -f ".eslintrc.js" || -f "eslint.config.js" || -f "eslint.config.mjs" ]]; then
        run_check "lint" "bunx eslint ." ""
      else
        echo "  SKIP: lint (no linter config found)" >&2
        RESULTS+=("{\"name\":\"lint\",\"status\":\"skipped\",\"reason\":\"no linter config\"}")
      fi
      ;;
    test)
      # Check for test files
      TEST_FILES=$(find . -path ./node_modules -prune -o \( -name "*.test.*" -o -name "*.spec.*" \) -print 2>/dev/null | head -1)
      if [[ -n "$TEST_FILES" ]]; then
        run_check "test" "bun test" ""
      else
        echo "  SKIP: test (no test files found)" >&2
        RESULTS+=("{\"name\":\"test\",\"status\":\"skipped\",\"reason\":\"no test files\"}")
      fi
      ;;
    *)
      echo "  WARN: Unknown check '$check'" >&2
      ;;
  esac
done <<< "$CHECKS"

# ─── Build JSON output (safe empty-array handling) ──────────────────────────
if [[ ${#RESULTS[@]} -gt 0 ]]; then
  RESULTS_JSON=$(printf '%s\n' "${RESULTS[@]}" | jq -s '.')
else
  RESULTS_JSON="[]"
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  ERRORS_JSON=$(printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '.')
else
  ERRORS_JSON="[]"
fi

cat << CHECKEOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "all_pass": $ALL_PASS,
  "mode": "$MODE",
  "checks": $RESULTS_JSON,
  "errors": $ERRORS_JSON
}
CHECKEOF

if $ALL_PASS; then
  exit 0
else
  exit 1
fi
CHECKSH

chmod +x harness/check.sh
```

### 2c: `harness/report.sh` — Structured Reporting

Writes `report_{LOOP_ID}.json` (current snapshot, overwritten) and `report_history_{LOOP_ID}.jsonl`
(append-only for trends). Loop-scoped so parallel loops don't collide.
Sends webhook alerts for configured events.

```bash
cat > harness/report.sh << 'REPORTSH'
#!/usr/bin/env bash
set -uo pipefail

# Ralph CI — Structured Reporting + Webhook Alerts
# Usage: report.sh --event <event> [--iteration N] [--cost N] [--total-cost N]
#        [--files-changed N] [--exit-code N] [--reason STR] [--loop-id N]
#        [--check-output FILE_OR_JSON]

# ─── Fix step generator (pattern-matching, no API calls) ─────────────────────
generate_fix_steps() {
  local check_output="$1"
  if [[ -z "$check_output" ]]; then
    echo "Check CI logs for error details"
    return
  fi

  # Read from file if path given, otherwise treat as inline JSON
  local content=""
  if [[ -f "$check_output" ]]; then
    content=$(cat "$check_output" 2>/dev/null || echo "")
  else
    content="$check_output"
  fi

  if [[ -z "$content" ]]; then
    echo "Check CI logs for error details"
    return
  fi

  # Pattern-match common errors and return actionable fix steps
  if echo "$content" | grep -qi "DATABASE_URL"; then
    echo "Add DATABASE_URL to GitHub Actions env vars (see Phase 2.5 docker service mapping)"
  elif echo "$content" | grep -qi "REDIS_URL\|S3_ENDPOINT\|MEILI_URL"; then
    echo "Add missing env vars — check docker-compose.yml services and Phase 2.5 mapping"
  elif echo "$content" | grep -qi "BETTER_AUTH_SECRET"; then
    echo "Add BETTER_AUTH_SECRET to GitHub Actions env vars"
  elif echo "$content" | grep -qi "module not found\|Cannot find module"; then
    echo "Run 'bun install' — missing dependency"
  elif echo "$content" | grep -qi '"build".*"FAIL"\|build.*failed\|next build.*error'; then
    echo "Build failed — check CI logs for build errors"
  elif echo "$content" | grep -qi '"typecheck".*"FAIL"\|tsc.*error'; then
    echo "Run 'bunx tsc --noEmit' locally and fix type errors"
  elif echo "$content" | grep -qi '"lint".*"FAIL"\|biome.*error'; then
    echo "Run 'bunx biome check --fix .' locally and push"
  elif echo "$content" | grep -qi '"test".*"FAIL"\|test.*failed'; then
    echo "Run 'bun test' locally — check test output in CI logs"
  elif echo "$content" | grep -qi '"plan_complete".*"FAIL"\|PENDING'; then
    local pending_count
    pending_count=$(echo "$content" | grep -o '"PENDING"' 2>/dev/null | wc -l | tr -d ' ')
    echo "${pending_count:-N} PENDING steps remain — ralph needs more iterations"
  else
    echo "Check CI logs for error details"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$PROJECT_DIR/ralph.config.json"
STATE_DIR="$PROJECT_DIR/.ralph"

config() { jq -r "$1 // empty" "$CONFIG" 2>/dev/null; }

# ─── Parse args ──────────────────────────────────────────────────────────────
EVENT=""
ITERATION=""
COST="0"
TOTAL_COST="0"
FILES_CHANGED="0"
EXIT_CODE=""
REASON=""
LOOP_ID="${RALPH_LOOP_ID:-0}"
CHECK_OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)        EVENT="$2"; shift 2 ;;
    --iteration)    ITERATION="$2"; shift 2 ;;
    --cost)         COST="$2"; shift 2 ;;
    --total-cost)   TOTAL_COST="$2"; shift 2 ;;
    --files-changed) FILES_CHANGED="$2"; shift 2 ;;
    --exit-code)    EXIT_CODE="$2"; shift 2 ;;
    --reason)       REASON="$2"; shift 2 ;;
    --loop-id)      LOOP_ID="$2"; shift 2 ;;
    --check-output) CHECK_OUTPUT="$2"; shift 2 ;;
    *)              shift ;;
  esac
done

# Loop-scoped output files (prevents parallel loops from stomping each other)
REPORT_FILE="$STATE_DIR/report_${LOOP_ID}.json"
HISTORY_FILE="$STATE_DIR/report_history_${LOOP_ID}.jsonl"

mkdir -p "$STATE_DIR"

# ─── Gather project metrics ─────────────────────────────────────────────────
GIT_SHA=$(cd "$PROJECT_DIR" && git --no-pager rev-parse --short HEAD 2>/dev/null || echo "unknown")
BRANCH=$(cd "$PROJECT_DIR" && git --no-pager branch --show-current 2>/dev/null || echo "unknown")

# Parse PLAN.md for progress
DONE_COUNT=0
PENDING_COUNT=0
TOTAL_STEPS=0
if [[ -f "$STATE_DIR/PLAN.md" ]]; then
  DONE_COUNT=$(grep -c "DONE:" "$STATE_DIR/PLAN.md" 2>/dev/null) || true
  PENDING_COUNT=$(grep -c "PENDING:" "$STATE_DIR/PLAN.md" 2>/dev/null) || true
  : "${DONE_COUNT:=0}"
  : "${PENDING_COUNT:=0}"
  TOTAL_STEPS=$((DONE_COUNT + PENDING_COUNT))
fi

# ─── Write report.json (atomic — write to tmp then mv) ──────────────────────
TMP_REPORT="${REPORT_FILE}.tmp"
cat > "$TMP_REPORT" << REPORTEOF
{
  "event": "$EVENT",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "loop_id": "$LOOP_ID",
  "iteration": ${ITERATION:-0},
  "git_sha": "$GIT_SHA",
  "branch": "$BRANCH",
  "mode": "$(config '.mode')",
  "cost_usd": $COST,
  "total_cost_usd": $TOTAL_COST,
  "files_changed": $FILES_CHANGED,
  "plan_done": $DONE_COUNT,
  "plan_pending": $PENDING_COUNT,
  "plan_total": $TOTAL_STEPS,
  "exit_code": ${EXIT_CODE:-null},
  "reason": $(echo "${REASON:-}" | jq -Rs .)
}
REPORTEOF
mv "$TMP_REPORT" "$REPORT_FILE"

# ─── Append to history (JSONL — append-only for trends) ─────────────────────
jq -c '.' "$REPORT_FILE" >> "$HISTORY_FILE"

# ─── SMS delivery ───────────────────────────────────────────────────────────
SMS_ENABLED=$(config '.sms.enabled')
SMS_URL=$(config '.sms.url')
SMS_TO=$(config '.sms.to')
SMS_API_KEY_ENV=$(config '.sms.apiKeyEnv')
SMS_EVENTS=$(config '.sms.events[]' 2>/dev/null || echo "")

should_sms() {
  local event="$1"
  echo "$SMS_EVENTS" | grep -qw "$event"
}

send_sms() {
  local body="$1"
  local api_key=""

  # Try env var first, then .env.local
  if [[ -n "$SMS_API_KEY_ENV" ]]; then
    api_key="${!SMS_API_KEY_ENV:-}"
  fi
  if [[ -z "$api_key" && -f "$PROJECT_DIR/.env.local" ]]; then
    api_key=$(grep "^${SMS_API_KEY_ENV}=" "$PROJECT_DIR/.env.local" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d ' ')
  fi

  if [[ -z "$api_key" ]]; then
    echo "WARN: SMS API key ($SMS_API_KEY_ENV) not available — skipping SMS" >&2
    return 0
  fi

  curl -s -X POST "$SMS_URL" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $api_key" \
    -d "{\"body\": \"$body\", \"to\": \"$SMS_TO\"}" \
    --max-time 10 > /dev/null 2>&1 || echo "WARN: SMS delivery failed" >&2
}

REPO_NAME=$(basename "$PROJECT_DIR")

if [[ "$SMS_ENABLED" == "true" && -n "$SMS_URL" ]]; then
  SMS_BODY=""
  case "$EVENT" in
    phase_complete)
      PHASE_NUM="${REASON#phase_}"
      SMS_BODY="$REPO_NAME — Phase ${PHASE_NUM} complete. ${DONE_COUNT}/${TOTAL_STEPS} steps done, \$${TOTAL_COST} spent."
      should_sms "phase_complete" && send_sms "$SMS_BODY"
      ;;
    success)
      SMS_BODY="$REPO_NAME — BUILD COMPLETE! All ${TOTAL_STEPS} steps done. Total cost: \$${TOTAL_COST}."
      should_sms "success" && send_sms "$SMS_BODY"
      ;;
    failure)
      FIX_STEPS=$(generate_fix_steps "$CHECK_OUTPUT")
      SMS_BODY="$REPO_NAME — ERROR: Loop ${LOOP_ID} failed (exit ${EXIT_CODE:-?}). ${DONE_COUNT}/${TOTAL_STEPS} done, \$${TOTAL_COST} spent. Fix: ${FIX_STEPS}"
      should_sms "failure" && send_sms "$SMS_BODY"
      ;;
    circuit_breaker)
      SMS_BODY="$REPO_NAME — CIRCUIT BREAKER: ${REASON:-unknown}. ${DONE_COUNT}/${TOTAL_STEPS} done, \$${TOTAL_COST} spent. Needs attention."
      should_sms "circuit_breaker" && send_sms "$SMS_BODY"
      ;;
    budget_exceeded)
      SMS_BODY="$REPO_NAME — BUDGET EXCEEDED: \$${TOTAL_COST} > budget. ${DONE_COUNT}/${TOTAL_STEPS} done."
      should_sms "budget_exceeded" && send_sms "$SMS_BODY"
      ;;
    max_iterations)
      SMS_BODY="$REPO_NAME — MAX ITERATIONS: Hit ${ITERATION:-?} loops. ${DONE_COUNT}/${TOTAL_STEPS} done, \$${TOTAL_COST} spent."
      should_sms "max_iterations" && send_sms "$SMS_BODY"
      ;;
    kill_switch)
      SMS_BODY="$REPO_NAME — KILLED: Loop stopped by kill switch. ${DONE_COUNT}/${TOTAL_STEPS} done."
      should_sms "kill_switch" && send_sms "$SMS_BODY"
      ;;
    paused)
      SMS_BODY="$REPO_NAME — PAUSED: Loop ${LOOP_ID} paused at iter ${ITERATION:-?}. ${DONE_COUNT}/${TOTAL_STEPS} done, \$${TOTAL_COST} spent. Resume from Actions tab."
      should_sms "paused" && send_sms "$SMS_BODY"
      ;;
    resumed)
      SMS_BODY="$REPO_NAME — RESUMED: Loop restarting. ${DONE_COUNT}/${TOTAL_STEPS} done, \$${TOTAL_COST} spent."
      should_sms "resumed" && send_sms "$SMS_BODY"
      ;;
    verify_failure)
      FIX_STEPS=$(generate_fix_steps "$CHECK_OUTPUT")
      SMS_BODY="$REPO_NAME — VERIFY FAILED: Post-loop checks did not pass. ${DONE_COUNT}/${TOTAL_STEPS} done. Fix: ${FIX_STEPS}"
      should_sms "verify_failure" && send_sms "$SMS_BODY"
      ;;
  esac
fi

# ─── Webhook delivery ───────────────────────────────────────────────────────
WEBHOOK_URL=$(config '.webhook.url')
WEBHOOK_EVENTS=$(config '.webhook.events[]' 2>/dev/null || echo "")

should_notify() {
  local event="$1"
  echo "$WEBHOOK_EVENTS" | grep -qw "$event"
}

if [[ -n "$WEBHOOK_URL" && "$WEBHOOK_URL" != "null" && "$WEBHOOK_URL" != "" ]]; then
  # Map events to webhook event names
  NOTIFY_EVENT=""
  case "$EVENT" in
    success)         should_notify "success" && NOTIFY_EVENT="success" ;;
    failure)         should_notify "failure" && NOTIFY_EVENT="failure" ;;
    circuit_breaker) should_notify "circuit_breaker" && NOTIFY_EVENT="circuit_breaker" ;;
    kill_switch)     should_notify "failure" && NOTIFY_EVENT="kill_switch" ;;
    budget_exceeded) should_notify "failure" && NOTIFY_EVENT="budget_exceeded" ;;
    stalled)         should_notify "stalled" && NOTIFY_EVENT="stalled" ;;
    max_iterations)  should_notify "failure" && NOTIFY_EVENT="max_iterations" ;;
    phase_complete)  should_notify "success" && NOTIFY_EVENT="phase_complete" ;;
    paused)          should_notify "stalled" && NOTIFY_EVENT="paused" ;;
    resumed)         should_notify "success" && NOTIFY_EVENT="resumed" ;;
  esac

  if [[ -n "$NOTIFY_EVENT" ]]; then
    PAYLOAD=$(cat << WEBHOOKEOF
{
  "text": "Ralph CI [$REPO_NAME] — $NOTIFY_EVENT (loop $LOOP_ID, iter ${ITERATION:-0}, \$$TOTAL_COST spent, $DONE_COUNT/$TOTAL_STEPS done)",
  "event": "$NOTIFY_EVENT",
  "repo": "$REPO_NAME",
  "branch": "$BRANCH",
  "loop_id": "$LOOP_ID",
  "iteration": ${ITERATION:-0},
  "total_cost_usd": $TOTAL_COST,
  "plan_progress": "$DONE_COUNT/$TOTAL_STEPS",
  "git_sha": "$GIT_SHA",
  "reason": "${REASON:-}",
  "exit_code": ${EXIT_CODE:-null}
}
WEBHOOKEOF
)
    curl -s -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      --max-time 10 || echo "WARN: Webhook delivery failed" >&2
  fi
fi
REPORTSH

chmod +x harness/report.sh
```

### 2d: `.gitignore` entries for harness artifacts

**CRITICAL: Without this, `git add -A` in run.sh commits logs, state files, and
growing JSONL history into the repo, bloating it rapidly.**

```bash
cat >> .gitignore << 'GITIGNORE'

# Ralph CI harness artifacts
.ralph/.harness_state*
.ralph/.phases_done*
.ralph/report*.json
.ralph/report_history*.jsonl
.ralph/logs/
.ralph/screenshots/
GITIGNORE
```

**Verify Phase 2:**

```bash
# All scripts are executable
test -x harness/run.sh && echo "OK: run.sh" || echo "FAIL: run.sh"
test -x harness/check.sh && echo "OK: check.sh" || echo "FAIL: check.sh"
test -x harness/report.sh && echo "OK: report.sh" || echo "FAIL: report.sh"

# .gitignore has harness entries
grep -q "harness_state" .gitignore && echo "OK: .gitignore" || echo "FAIL: .gitignore missing harness entries"
```

**Do not proceed until all three scripts exist and are executable, and .gitignore is updated.**

---

## Phase 2.5: Detect Docker Services for CI

If the project has a `docker-compose.yml` (created by the `docker` skill), the GitHub Actions
workflow needs matching `services:` blocks so that `next build`, tests, and other checks can
reach databases, caches, and object stores. Without this, `@t3-oss/env-nextjs` Zod validation
crashes at build time with errors like `Error: DATABASE_URL is not set`.

### Detection

Read `docker-compose.yml` and extract service names:

```bash
if [[ -f docker-compose.yml ]]; then
  DETECTED_SERVICES=$(grep -E '^\s{2}\w+:' docker-compose.yml | sed 's/://;s/^ *//' | sort)
  echo "Detected services: $DETECTED_SERVICES"
else
  echo "No docker-compose.yml — skipping service detection"
fi
```

### Service Mapping Table

Map each docker-compose service to a GitHub Actions service container. **Only include
services that were detected** — do not add services the project doesn't use.

| docker-compose service | GHA image | Health check | Env vars |
|---|---|---|---|
| `postgres` | `pgvector/pgvector:pg16` | `pg_isready -U app` | `DATABASE_URL=postgresql://app:password@postgres:5432/appdb` |
| `redis` | `redis:7-alpine` | `redis-cli ping` | `REDIS_URL=redis://redis:6379` |
| `s3` | `rustfs/rustfs:latest` | *(none)* | `S3_ENDPOINT=http://s3:9000`, `S3_ACCESS_KEY=minioadmin`, `S3_SECRET_KEY=minioadmin` |
| `meilisearch` | `getmeili/meilisearch:v1.10` | `curl -f http://localhost:7700/health` | `MEILI_URL=http://meilisearch:7700`, `MEILI_MASTER_KEY=ci-master-key` |
| `mailpit` | `axllent/mailpit:latest` | *(none)* | `SMTP_HOST=mailpit`, `SMTP_PORT=1025` |
| `ollama` | **SKIP** — dev-only, too heavy for CI | | |
| `jaeger` | **SKIP** — dev-only observability | | |

**Critical**: GHA service containers use the **service name** as hostname (`postgres`, not `localhost`).
Connection strings must use the service name: `postgresql://app:password@postgres:5432/appdb`.

### YAML Fragments for Each Service

**Postgres** (most common — any project with `db` skill):

```yaml
    services:
      postgres:
        image: pgvector/pgvector:pg16
        env:
          POSTGRES_USER: app
          POSTGRES_PASSWORD: password
          POSTGRES_DB: appdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U app"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
```

**Redis**:

```yaml
      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
```

**S3 (RustFS/MinIO)**:

```yaml
      s3:
        image: rustfs/rustfs:latest
        env:
          RUSTFS_ROOT_USER: minioadmin
          RUSTFS_ROOT_PASSWORD: minioadmin
        ports:
          - 9000:9000
```

**Meilisearch**:

```yaml
      meilisearch:
        image: getmeili/meilisearch:v1.10
        env:
          MEILI_MASTER_KEY: ci-master-key
        ports:
          - 7700:7700
        options: >-
          --health-cmd "curl -f http://localhost:7700/health"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
```

**Mailpit**:

```yaml
      mailpit:
        image: axllent/mailpit:latest
        ports:
          - 1025:1025
          - 8025:8025
```

### Required Env Vars Block

Always include these env vars in the "Run Ralph loop" step **and** the verify job steps,
matching whichever services were detected:

```yaml
        env:
          # --- Service container env vars (auto-detected from docker-compose.yml) ---
          DATABASE_URL: postgresql://app:password@postgres:5432/appdb    # if postgres detected
          REDIS_URL: redis://redis:6379                                  # if redis detected
          S3_ENDPOINT: http://s3:9000                                    # if s3 detected
          S3_ACCESS_KEY: minioadmin                                      # if s3 detected
          S3_SECRET_KEY: minioadmin                                      # if s3 detected
          MEILI_URL: http://meilisearch:7700                             # if meilisearch detected
          MEILI_MASTER_KEY: ci-master-key                                # if meilisearch detected
          SMTP_HOST: mailpit                                             # if mailpit detected
          SMTP_PORT: "1025"                                              # if mailpit detected
          # --- Always required (env-config skill expects these) ---
          BETTER_AUTH_SECRET: ci-test-secret
          NEXT_PUBLIC_APP_URL: http://localhost:3000
```

### Instructions

1. Run the detection script above during Phase 3a (before writing workflow YAML)
2. For each detected service, include its `services:` fragment in **both** the `loop` and `verify` jobs
3. Add matching env vars to the `env:` block of the "Run Ralph loop" step and all verify job steps
4. **ALWAYS include these env vars even when no docker-compose.yml exists** — the `env-config` skill validates them at build time and `next build` will crash without them:
   - `DATABASE_URL: postgresql://ci:ci@localhost:5432/ci` (dummy — passes Zod `.url().startsWith("postgres")` validation)
   - `BETTER_AUTH_SECRET: ci-test-secret-min-32-chars-long!!` (dummy — passes `.min(32)` validation)
   - `NEXT_PUBLIC_APP_URL: http://localhost:3000`
5. Add comments `# --- Build-time env vars (env-config skill validates at build time) ---` in the YAML
6. If no `docker-compose.yml` exists, skip the `services:` blocks but still include the env vars from step 4

---

## Phase 3: GitHub Actions Workflows

```bash
mkdir -p .github/workflows
```

### 3a: `ralph-loop.yml` — Main CI Loop

```yaml
# .github/workflows/ralph-loop.yml
name: Ralph Loop

on:
  workflow_dispatch:
    inputs:
      max_iterations:
        description: "Max loop iterations"
        required: false
        default: "40"
        type: string
      concurrency_count:
        description: "Parallel loops (1-12)"
        required: false
        default: "3"
        type: string
      timeout_minutes:
        description: "Workflow timeout (minutes)"
        required: false
        default: "180"
        type: string
      model:
        description: "Claude model"
        required: false
        default: "claude-sonnet-4-6"
        type: choice
        options:
          - claude-sonnet-4-6
          - claude-opus-4-6
          - claude-haiku-4-5-20251001
      fresh_start:
        description: "Reset harness state (ignore cached iteration count)"
        required: false
        default: "false"
        type: boolean
  push:
    branches:
      - "ralph/**"
  schedule:
    - cron: "0 2 * * *"  # Nightly at 2 AM UTC

# F23: contents:write needed for push step to push ralph commits back to repo
permissions:
  contents: write

concurrency:
  group: ralph-${{ github.ref }}
  cancel-in-progress: false

env:
  RALPH_ENABLED: ${{ vars.RALPH_ENABLED || 'true' }}
  RALPH_PAUSED: ${{ vars.RALPH_PAUSED || 'false' }}

jobs:
  setup:
    runs-on: ubuntu-22.04
    outputs:
      matrix: ${{ steps.matrix.outputs.value }}
    steps:
      - name: Generate matrix
        id: matrix
        run: |
          COUNT="${{ inputs.concurrency_count || '3' }}"
          SEQ=$(seq 1 "$COUNT" | jq -R . | jq -sc '{"loop": .}')
          echo "value=$SEQ" >> "$GITHUB_OUTPUT"

  loop:
    needs: setup
    runs-on: ubuntu-22.04
    timeout-minutes: ${{ fromJSON(inputs.timeout_minutes || '180') }}
    strategy:
      matrix: ${{ fromJSON(needs.setup.outputs.matrix) }}
      fail-fast: false
    # --- Service containers (auto-detected from docker-compose.yml) ---
    # Include ONLY services detected in the project's docker-compose.yml.
    # Remove any services the project doesn't use.
    services:
      postgres:
        image: pgvector/pgvector:pg16
        env:
          POSTGRES_USER: app
          POSTGRES_PASSWORD: password
          POSTGRES_DB: appdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U app"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      # redis:
      #   image: redis:7-alpine
      #   ports:
      #     - 6379:6379
      #   options: >-
      #     --health-cmd "redis-cli ping"
      #     --health-interval 10s
      #     --health-timeout 5s
      #     --health-retries 5
      # s3:
      #   image: rustfs/rustfs:latest
      #   env:
      #     RUSTFS_ROOT_USER: minioadmin
      #     RUSTFS_ROOT_PASSWORD: minioadmin
      #   ports:
      #     - 9000:9000
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup Node 20 + Bun
        uses: actions/setup-node@v4
        with:
          node-version: "20"
      - uses: oven-sh/setup-bun@v2

      - name: Cache bun dependencies
        uses: actions/cache@v4
        with:
          path: ~/.bun/install/cache
          key: bun-${{ runner.os }}-${{ hashFiles('**/bun.lockb') }}
          restore-keys: bun-${{ runner.os }}-

      - name: Install system deps
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y -qq chromium-browser jq bc
          npx playwright install-deps chromium

      - name: Install Claude Code
        run: npm install -g @anthropic-ai/claude-code

      # F21: In build mode, package.json doesn't exist yet — ralph step 1.1 creates it
      - name: Install project deps
        run: |
          if [ -f package.json ]; then
            bun install --frozen-lockfile || bun install
          else
            echo "No package.json yet — Ralph step 1.1 will create it"
          fi

      - name: Restore harness state
        if: ${{ !inputs.fresh_start }}
        uses: actions/cache@v4
        with:
          path: |
            .ralph/.harness_state_${{ matrix.loop }}
            .ralph/.phases_done_${{ matrix.loop }}
            .ralph/logs
            .ralph/report_history_${{ matrix.loop }}.jsonl
          key: ralph-state-${{ matrix.loop }}-${{ github.run_number }}
          restore-keys: |
            ralph-state-${{ matrix.loop }}-

      - name: Reset harness state
        if: ${{ inputs.fresh_start }}
        run: rm -f .ralph/.harness_state_${{ matrix.loop }}

      - name: Run Ralph loop
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          N8N_SMS_KEY: ${{ secrets.N8N_SMS_KEY }}
          RALPH_ENABLED: ${{ vars.RALPH_ENABLED || 'true' }}
          RALPH_PAUSED: ${{ vars.RALPH_PAUSED || 'false' }}
          RALPH_LOOP_ID: ${{ matrix.loop }}
          # --- Service container env vars (auto-detected from docker-compose.yml) ---
          DATABASE_URL: postgresql://app:password@postgres:5432/appdb
          # REDIS_URL: redis://redis:6379
          # S3_ENDPOINT: http://s3:9000
          # S3_ACCESS_KEY: minioadmin
          # S3_SECRET_KEY: minioadmin
          # --- Always required (env-config skill expects these) ---
          BETTER_AUTH_SECRET: ci-test-secret
          NEXT_PUBLIC_APP_URL: http://localhost:3000
        run: |
          mkdir -p .ralph/logs
          chmod +x harness/*.sh
          bash harness/run.sh 2>&1 | tee ".ralph/logs/ci_loop_${{ matrix.loop }}.log"

      # F23: Push ralph's commits back to the repo so work isn't lost when runner shuts down
      - name: Push changes back to repo
        if: always()
        run: |
          git config user.name "ralph-ci"
          git config user.email "ralph-ci@noreply.github.com"
          # Stage any unstaged changes from the last iteration
          git add -A
          git diff --cached --quiet || git commit -m "ralph-ci: unstaged changes from loop ${{ matrix.loop }}"
          # Push all commits back to the repo
          git push origin HEAD:${{ github.ref_name }} || echo "WARN: push failed (likely concurrent push conflict)"

      - name: Upload artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: ralph-loop-${{ matrix.loop }}
          path: |
            .ralph/logs/
            .ralph/report_${{ matrix.loop }}.json
            .ralph/report_history_${{ matrix.loop }}.jsonl
            .ralph/screenshots/
          retention-days: 14

  verify:
    needs: loop
    if: always()
    runs-on: ubuntu-22.04
    timeout-minutes: 30
    # --- Service containers (auto-detected from docker-compose.yml) ---
    # Must match the loop job's services so verify checks (build, test) can reach DBs
    services:
      postgres:
        image: pgvector/pgvector:pg16
        env:
          POSTGRES_USER: app
          POSTGRES_PASSWORD: password
          POSTGRES_DB: appdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U app"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: ${{ github.ref }}

      - name: Setup Node 20 + Bun
        uses: actions/setup-node@v4
        with:
          node-version: "20"
      - uses: oven-sh/setup-bun@v2

      # F21: package.json may not exist if ralph hasn't scaffolded yet
      - name: Install deps
        run: |
          if [ -f package.json ]; then
            bun install --frozen-lockfile || bun install
          else
            echo "No package.json — skipping install"
          fi

      - name: Pull latest changes
        run: git pull origin "${{ github.ref_name }}" || true

      - name: Run final verification
        env:
          # --- Service container env vars (auto-detected from docker-compose.yml) ---
          DATABASE_URL: postgresql://app:password@postgres:5432/appdb
          # REDIS_URL: redis://redis:6379
          # --- Always required (env-config skill expects these) ---
          BETTER_AUTH_SECRET: ci-test-secret
          NEXT_PUBLIC_APP_URL: http://localhost:3000
        run: |
          chmod +x harness/*.sh
          bash harness/check.sh | tee /tmp/check_output.json

      - name: Report verify failure
        if: failure()
        env:
          N8N_SMS_KEY: ${{ secrets.N8N_SMS_KEY }}
          # --- Service container env vars (same as verify step) ---
          DATABASE_URL: postgresql://app:password@postgres:5432/appdb
          BETTER_AUTH_SECRET: ci-test-secret
          NEXT_PUBLIC_APP_URL: http://localhost:3000
        run: |
          chmod +x harness/*.sh
          bash harness/report.sh --event verify_failure --check-output /tmp/check_output.json

      - name: Upload final report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: ralph-final-report
          path: |
            .ralph/report_*.json
            .ralph/report_history_*.jsonl
            /tmp/check_output.json
          retention-days: 30
```

### 3b: `ralph-watchdog.yml` — Scheduled Health Check

```yaml
# .github/workflows/ralph-watchdog.yml
name: Ralph Watchdog

on:
  schedule:
    - cron: "0 6 * * *"  # Daily at 6 AM UTC
  workflow_dispatch:

jobs:
  watchdog:
    runs-on: ubuntu-22.04
    timeout-minutes: 5
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 10

      - name: Check for stale repos
        id: stale
        run: |
          LAST_COMMIT=$(git log -1 --format=%ct)
          NOW=$(date +%s)
          HOURS_SINCE=$(( (NOW - LAST_COMMIT) / 3600 ))
          echo "hours_since=$HOURS_SINCE" >> "$GITHUB_OUTPUT"
          if [[ "$HOURS_SINCE" -gt 24 ]]; then
            echo "stale=true" >> "$GITHUB_OUTPUT"
            echo "WARN: No commits in ${HOURS_SINCE}h"
          else
            echo "stale=false" >> "$GITHUB_OUTPUT"
            echo "OK: Last commit ${HOURS_SINCE}h ago"
          fi

      - name: Read webhook config
        id: webhook
        if: steps.stale.outputs.stale == 'true'
        run: |
          if [[ -f ralph.config.json ]]; then
            URL=$(jq -r '.webhook.url // ""' ralph.config.json)
            echo "url=$URL" >> "$GITHUB_OUTPUT"
          fi

      - name: Alert via webhook
        if: steps.stale.outputs.stale == 'true' && steps.webhook.outputs.url != ''
        run: |
          REPO="${{ github.repository }}"
          HOURS="${{ steps.stale.outputs.hours_since }}"
          curl -s -X POST "${{ steps.webhook.outputs.url }}" \
            -H "Content-Type: application/json" \
            -d "{
              \"text\": \"Ralph Watchdog [$REPO] — STALLED: No commits in ${HOURS}h\",
              \"event\": \"stalled\",
              \"repo\": \"$REPO\",
              \"hours_since_commit\": $HOURS
            }" --max-time 10
```

### 3c: `ralph-kill.yml` — Emergency Kill Switch

**Requires a `GH_PAT` secret** — a GitHub Personal Access Token with `repo` scope.
The built-in `GITHUB_TOKEN` cannot manage repository variables (HTTP 403).

```yaml
# .github/workflows/ralph-kill.yml
name: Ralph Kill Switch

on:
  workflow_dispatch:
    inputs:
      action:
        description: "Enable or disable Ralph loops"
        required: true
        type: choice
        options:
          - disable
          - enable

permissions:
  actions: write

jobs:
  toggle:
    runs-on: ubuntu-22.04
    timeout-minutes: 2
    steps:
      - name: Toggle kill switch
        env:
          GH_TOKEN: ${{ secrets.GH_PAT }}
        run: |
          REPO="${{ github.repository }}"
          ACTION="${{ inputs.action }}"

          if [[ "$ACTION" == "disable" ]]; then
            gh variable set RALPH_ENABLED --body "false" --repo "$REPO"
            echo "Ralph loops DISABLED for $REPO"
          else
            gh variable set RALPH_ENABLED --body "true" --repo "$REPO"
            echo "Ralph loops ENABLED for $REPO"
          fi

      - name: Cancel running workflows
        if: inputs.action == 'disable'
        env:
          GH_TOKEN: ${{ secrets.GH_PAT }}
        run: |
          REPO="${{ github.repository }}"
          # Cancel all running Ralph Loop workflows
          gh run list --workflow=ralph-loop.yml --status=in_progress --repo "$REPO" --json databaseId -q '.[].databaseId' | \
            while read -r RUN_ID; do
              echo "Cancelling run $RUN_ID"
              gh run cancel "$RUN_ID" --repo "$REPO" || true
            done
```

### 3d: `ralph-pause.yml` — One-Click Pause (F25)

Zero-input workflow. Click "Run workflow" and ralph stops gracefully after
the current iteration. State is preserved — no work is lost.

```yaml
# .github/workflows/ralph-pause.yml
name: "Ralph: Pause"

on:
  workflow_dispatch:

permissions:
  actions: write

jobs:
  pause:
    runs-on: ubuntu-22.04
    timeout-minutes: 2
    steps:
      - name: Pause Ralph
        env:
          GH_TOKEN: ${{ secrets.GH_PAT }}
        run: |
          REPO="${{ github.repository }}"
          gh variable set RALPH_PAUSED --body "true" --repo "$REPO"
          echo "::notice::Ralph loops PAUSED for $REPO"
          echo "Running loops will finish their current iteration and stop."
          echo "Use the **Ralph: Resume** workflow to start them back up."

          # Write step summary
          cat >> "$GITHUB_STEP_SUMMARY" << 'EOF'
          ## Ralph Paused

          Running loops will finish their current iteration and exit gracefully.
          State is saved — no work is lost.

          **To resume:** Run the **Ralph: Resume** workflow.
          EOF
```

### 3e: `ralph-resume.yml` — One-Click Resume (F25)

Zero-input workflow. Clears the pause flag and triggers a new Ralph Loop
that picks up from saved state.

```yaml
# .github/workflows/ralph-resume.yml
name: "Ralph: Resume"

on:
  workflow_dispatch:

permissions:
  actions: write

jobs:
  resume:
    runs-on: ubuntu-22.04
    timeout-minutes: 2
    steps:
      - name: Unpause Ralph
        env:
          GH_TOKEN: ${{ secrets.GH_PAT }}
        run: |
          REPO="${{ github.repository }}"
          gh variable set RALPH_PAUSED --body "false" --repo "$REPO"
          echo "::notice::Ralph loops UNPAUSED for $REPO"

      - name: Trigger Ralph Loop
        env:
          GH_TOKEN: ${{ secrets.GH_PAT }}
        run: |
          REPO="${{ github.repository }}"
          gh workflow run ralph-loop.yml --repo "$REPO" --ref main
          echo "::notice::Ralph Loop triggered — resuming from last saved state"

          # Write step summary
          cat >> "$GITHUB_STEP_SUMMARY" << 'EOF'
          ## Ralph Resumed

          Loops unpaused and a new Ralph Loop workflow has been triggered.
          It will pick up from where it left off (state is preserved).
          EOF
```

**Pause vs Kill:**

- **Pause** — graceful. Finishes current iteration, saves state, exits code 6. Resume picks up exactly where it left off.
- **Kill** — hard stop. Cancels running jobs immediately, sets `RALPH_ENABLED=false`. Must re-enable via kill switch workflow.

**Verify Phase 3:**

```bash
# Validate YAML syntax (if yq available)
for f in .github/workflows/ralph-*.yml; do
  if command -v yq &>/dev/null; then
    yq . "$f" > /dev/null && echo "OK: $f" || echo "FAIL: $f"
  elif command -v python3 &>/dev/null; then
    python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "OK: $f" || echo "FAIL: $f"
  else
    echo "SKIP: No YAML validator available for $f"
  fi
done
```

**Do not proceed until all 3 workflow files exist and parse as valid YAML.**

---

## Phase 4: VPS Mode (Optional)

**Only create these files if `ralph.config.json` has `"vps.enabled": true` or the user requests VPS mode.**

See [references/vps-bootstrap.md](references/vps-bootstrap.md) for full VPS setup guide.

```bash
mkdir -p harness/vps
```

### 4a: `harness/vps/bootstrap.sh` — VPS Provisioning

```bash
cat > harness/vps/bootstrap.sh << 'BOOTSTRAP'
#!/usr/bin/env bash
set -euo pipefail

# Ralph CI — VPS Bootstrap (Hetzner/DigitalOcean/Any Ubuntu 22.04+)
# Idempotent — safe to re-run. Checks `command -v` before installing.

echo "━━━ Ralph CI VPS Bootstrap ━━━"

# ─── System packages ────────────────────────────────────────────────────────
sudo apt-get update -qq
sudo apt-get install -y -qq \
  curl git jq bc unzip \
  chromium-browser \
  ufw \
  unattended-upgrades \
  logrotate

# ─── Node.js 20 ─────────────────────────────────────────────────────────────
if ! command -v node &>/dev/null || [[ "$(node -v)" != v20* ]]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y -qq nodejs
fi
echo "Node: $(node -v)"

# ─── Bun ─────────────────────────────────────────────────────────────────────
if ! command -v bun &>/dev/null; then
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
  echo 'export PATH="$HOME/.bun/bin:$PATH"' >> "$HOME/.bashrc"
fi
echo "Bun: $(bun -v)"

# ─── Claude Code ─────────────────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
  npm install -g @anthropic-ai/claude-code
fi
echo "Claude: $(claude --version 2>/dev/null || echo 'installed')"

# ─── PM2 ─────────────────────────────────────────────────────────────────────
if ! command -v pm2 &>/dev/null; then
  npm install -g pm2
  pm2 startup systemd -u "$USER" --hp "$HOME" || true
fi
echo "PM2: $(pm2 -v)"

# ─── Playwright deps ────────────────────────────────────────────────────────
npx playwright install-deps chromium 2>/dev/null || true

# ─── Firewall (SSH + outbound only) ─────────────────────────────────────────
if command -v ufw &>/dev/null; then
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow ssh
  sudo ufw --force enable
  echo "UFW: enabled (SSH + outbound)"
fi

# ─── Unattended upgrades ────────────────────────────────────────────────────
sudo dpkg-reconfigure -f noninteractive unattended-upgrades 2>/dev/null || true

# ─── Logrotate for ralph logs ────────────────────────────────────────────────
sudo tee /etc/logrotate.d/ralph > /dev/null << 'LOGROTATE'
/home/*/projects/*/.ralph/logs/*.log {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
}
LOGROTATE

# ─── Chrome zombie cleanup cron ─────────────────────────────────────────────
CRON_LINE="*/15 * * * * pkill -f 'chromium.*--headless' 2>/dev/null; pkill -f 'chrome.*--headless' 2>/dev/null"
(crontab -l 2>/dev/null | grep -v "chromium.*--headless"; echo "$CRON_LINE") | crontab -

echo ""
echo "━━━ Bootstrap complete ━━━"
echo "Next steps:"
echo "  1. Set ANTHROPIC_API_KEY in environment"
echo "  2. Clone your project repo"
echo "  3. Run: cd project && pm2 start harness/vps/ecosystem.config.cjs"
BOOTSTRAP

chmod +x harness/vps/bootstrap.sh
```

### 4b: `harness/vps/ecosystem.config.cjs` — PM2 Process Definitions

```javascript
// harness/vps/ecosystem.config.cjs
// PM2 process definitions for Ralph CI loops
// Usage: pm2 start harness/vps/ecosystem.config.cjs

const fs = require("fs");
const path = require("path");

const projectDir = path.resolve(__dirname, "../..");
const configPath = path.join(projectDir, "ralph.config.json");

let config = { concurrency: 3 };
try {
  config = JSON.parse(fs.readFileSync(configPath, "utf8"));
} catch {
  console.warn("WARN: Could not read ralph.config.json, using defaults");
}

const loops = [];
for (let i = 1; i <= (config.concurrency || 3); i++) {
  loops.push({
    name: `ralph-loop-${i}`,
    script: path.join(projectDir, "harness/run.sh"),
    cwd: projectDir,
    interpreter: "/usr/bin/env",
    interpreter_args: "bash",
    env: {
      RALPH_ENABLED: "true",
      RALPH_LOOP_ID: String(i),
      ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || "",
    },
    max_restarts: 3,
    restart_delay: 60000, // 1 minute between restarts
    autorestart: false,   // Don't auto-restart — let the harness handle it
    log_date_format: "YYYY-MM-DD HH:mm:ss",
    error_file: path.join(projectDir, `.ralph/logs/pm2_loop_${i}_error.log`),
    out_file: path.join(projectDir, `.ralph/logs/pm2_loop_${i}_out.log`),
    merge_logs: true,
  });
}

module.exports = { apps: loops };
```

### 4c: `harness/vps/cleanup.sh` — Chrome Zombie Killer

```bash
cat > harness/vps/cleanup.sh << 'CLEANUP'
#!/usr/bin/env bash
# Ralph CI — Chrome zombie cleanup
# Run via cron: */15 * * * * /path/to/cleanup.sh

KILLED=0

for PROC in "chromium.*--headless" "chrome.*--headless" "playwright.*chromium"; do
  PIDS=$(pgrep -f "$PROC" 2>/dev/null || true)
  if [[ -n "$PIDS" ]]; then
    for PID in $PIDS; do
      # Only kill processes older than 30 minutes
      ELAPSED=$(ps -o etimes= -p "$PID" 2>/dev/null | tr -d ' ')
      if [[ -n "$ELAPSED" && "$ELAPSED" -gt 1800 ]]; then
        kill "$PID" 2>/dev/null && KILLED=$((KILLED + 1))
      fi
    done
  fi
done

if [[ $KILLED -gt 0 ]]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Cleaned up $KILLED zombie chrome processes"
fi
CLEANUP

chmod +x harness/vps/cleanup.sh
```

**Verify Phase 4:**

```bash
test -x harness/vps/bootstrap.sh && echo "OK: bootstrap.sh" || echo "FAIL: bootstrap.sh"
test -f harness/vps/ecosystem.config.cjs && echo "OK: ecosystem.config.cjs" || echo "FAIL: ecosystem.config.cjs"
test -x harness/vps/cleanup.sh && echo "OK: cleanup.sh" || echo "FAIL: cleanup.sh"

# Validate ecosystem config syntax
node -e "require('./harness/vps/ecosystem.config.cjs')" && echo "OK: ecosystem.config.cjs loads" || echo "FAIL: ecosystem.config.cjs"
```

---

## Phase 5: Template Setup (Optional)

If the user wants to make this repo a reusable template:

### 5a: GitHub Template

```bash
# Configure repo as GitHub template (requires gh CLI)
gh repo edit --template
```

### 5b: README Badges

Add CI status badges to the project README:

```markdown
<!-- Add at top of README.md -->
[![Ralph Loop](https://github.com/{OWNER}/{REPO}/actions/workflows/ralph-loop.yml/badge.svg)](https://github.com/{OWNER}/{REPO}/actions/workflows/ralph-loop.yml)
[![Ralph Watchdog](https://github.com/{OWNER}/{REPO}/actions/workflows/ralph-watchdog.yml/badge.svg)](https://github.com/{OWNER}/{REPO}/actions/workflows/ralph-watchdog.yml)
```

Replace `{OWNER}` and `{REPO}` with actual values.

---

## Phase 6: Verification

Run these checks to validate the entire setup.

### 6a: JSON validation

```bash
jq . ralph.config.json > /dev/null && echo "OK: ralph.config.json" || echo "FAIL: ralph.config.json"
```

### 6b: check.sh standalone test

```bash
# Should run without errors (may skip checks if no package.json etc.)
bash harness/check.sh 2>&1
echo "Exit code: $?"
```

### 6c: Kill switch test

```bash
# Should exit immediately with code 3
RALPH_ENABLED=false bash harness/run.sh
echo "Exit code: $?"  # expect 3
```

### 6d: YAML validation

```bash
for f in .github/workflows/ralph-*.yml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>/dev/null && \
    echo "OK: $f" || echo "FAIL: $f"
done
```

### 6e: report.sh produces valid JSON

```bash
RALPH_LOOP_ID=0 bash harness/report.sh --event test --iteration 0 --cost 0 --total-cost 0 --loop-id 0
jq . .ralph/report_0.json > /dev/null && echo "OK: report.json" || echo "FAIL: report.json"
```

### 6f: Webhook test (optional)

```bash
WEBHOOK_URL=$(jq -r '.webhook.url' ralph.config.json)
if [[ -n "$WEBHOOK_URL" && "$WEBHOOK_URL" != "null" ]]; then
  curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"text":"Ralph CI test webhook — setup verification","event":"test"}' \
    --max-time 10
  echo "Webhook test sent"
else
  echo "SKIP: No webhook URL configured"
fi
```

---

## Safety Mechanisms (14 Layers)

The harness implements 14 layers of protection to prevent runaway loops:

| # | Mechanism | Where | Trigger |
|---|-----------|-------|---------|
| 1 | **Kill switch** | `run.sh` | `RALPH_ENABLED=false` → exit 3 |
| 2 | **Pause/Resume** | `run.sh` | `RALPH_PAUSED=true` → exit 6 (state preserved) |
| 3 | **Max iterations** | `run.sh` | Loop counter ≥ `maxIterations` → exit 2 |
| 4 | **Per-iteration timeout** | `run.sh` | `timeout` command on claude → exit 5 |
| 5 | **Workflow timeout** | `ralph-loop.yml` | `timeout-minutes` on job → GitHub cancels |
| 6 | **Circuit breaker: no-progress** | `run.sh` | 0 files changed for N iterations → exit 2 |
| 7 | **Circuit breaker: same-error** | `run.sh` | Same error N times → exit 2 |
| 8 | **Budget guard** | `run.sh` | `total_cost_usd > budgetMaxUsd` → exit 4 |
| 9 | **Concurrency control** | `ralph-loop.yml` | `concurrency.group` prevents duplicate runs |
| 10 | **Webhook death alerts** | `report.sh` | ERR trap posts to Slack/Discord |
| 11 | **SMS notifications** | `report.sh` | Sends SMS for critical events (phase complete, errors, paused) |
| 12 | **Watchdog cron** | `ralph-watchdog.yml` | Daily stale-loop detection |
| 13 | **Verify failure SMS** | `report.sh` + `ralph-loop.yml` | Post-loop check failure → SMS with fix steps |
| 14 | **Docker service containers** | `ralph-loop.yml` | Auto-detected from docker-compose.yml → services + env vars |

VPS mode adds a 15th layer:
| 15 | **Chrome zombie cleanup** | `cleanup.sh` + cron | Kills orphaned chromium every 15 min |

---

## Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | All checks pass | Success — ralph is done |
| 2 | Circuit breaker tripped | Investigate logs, may need manual intervention |
| 3 | Kill switch disabled | Re-enable via `ralph-kill.yml` or env var |
| 4 | Budget exceeded | Increase `budgetMaxUsd` or investigate cost spike |
| 5 | Timeout | Increase `timeoutMinutes` or `iterationTimeoutMinutes` |
| 6 | Paused | Run `ralph-resume.yml` to continue from saved state |

---

## Mode Differences

### Build Mode (`"mode": "build"`)

- `check.sh` gates on PLAN.md having no PENDING steps + all checks pass
- Iterations are **incremental** — each builds on the previous
- `run.sh` does NOT revert on failure — keeps partial progress
- Budget is typically higher ($50-100) for full project builds

### Polish Mode (`"mode": "polish"`)

- `check.sh` gates on lint + typecheck + build + test only
- `run.sh` **reverts** sandbox between iterations if checks fail
- Each iteration is semi-independent — the project is already built
- Budget is typically lower ($10-20) for refinement passes
- Good for fixing lint errors, type errors, test failures across a codebase

---

## Integration with .ralphrc

The harness sources `.ralphrc` for Claude-specific settings:

| Setting | Source | Used By |
|---------|--------|---------|
| `CLAUDE_ALLOWED_TOOLS` | `.ralphrc` | `run.sh` passes to `claude --allowedTools` |
| `CLAUDE_MODEL` | `.ralphrc` (fallback) | Overridden by `ralph.config.json` `model` field |
| `CLAUDE_TIMEOUT_MINUTES` | `.ralphrc` (fallback) | Overridden by `ralph.config.json` `iterationTimeoutMinutes` |
| Loop config (iterations, budget, etc.) | `ralph.config.json` | All harness scripts |

**`ralph.config.json` takes precedence** for any setting defined in both files.

---

## Recommended VPS Sizing

| Loops | Provider | Spec | Cost |
|-------|----------|------|------|
| 1-2 | Hetzner CX22 | 2 vCPU / 4GB | ~$6/mo |
| 3-5 | Hetzner CPX31 | 8 vCPU / 16GB | ~$28/mo |
| 6-12 | Hetzner CPX51 | 16 vCPU / 32GB | ~$49/mo |
| 1-2 | DigitalOcean Basic | 2 vCPU / 4GB | ~$24/mo |
| 3-5 | DigitalOcean CPU-Opt | 8 vCPU / 16GB | ~$84/mo |

**Rule of thumb**: Each concurrent Ralph loop needs ~2 vCPU and ~3GB RAM (chromium is the
biggest consumer). Size VPS at `(loops × 2)` vCPU and `(loops × 3 + 2)` GB RAM.

---

## Acceptance Criteria

- [ ] `ralph.config.json` exists and passes `jq` validation
- [ ] `harness/run.sh` exists, is executable, handles all 10 safety layers
- [ ] `harness/check.sh` exists, is executable, outputs valid JSON
- [ ] `harness/report.sh` exists, is executable, writes `report_{N}.json` + `report_history_{N}.jsonl`
- [ ] `.github/workflows/ralph-loop.yml` exists and parses as valid YAML
- [ ] `.github/workflows/ralph-watchdog.yml` exists and parses as valid YAML
- [ ] `.github/workflows/ralph-kill.yml` exists and parses as valid YAML
- [ ] `.github/workflows/ralph-pause.yml` exists and parses as valid YAML
- [ ] `.github/workflows/ralph-resume.yml` exists and parses as valid YAML
- [ ] Kill switch test passes (RALPH_ENABLED=false → exit 3)
- [ ] Pause test passes (RALPH_PAUSED=true → exit 6)
- [ ] SMS delivery works (if sms.enabled = true and phone number configured)
- [ ] check.sh runs standalone without errors
- [ ] report.sh produces valid JSON
- [ ] VPS files created (if vps.enabled = true): bootstrap.sh, ecosystem.config.cjs, cleanup.sh
- [ ] All workflow YAML validated
- [ ] Webhook test fires (if webhook URL configured)
- [ ] If docker-compose.yml exists, workflows include matching `services:` blocks and env vars
- [ ] Service container env vars use service name as hostname (not localhost)
- [ ] `report.sh` `generate_fix_steps()` returns actionable text for common errors
- [ ] `verify_failure` event triggers SMS with fix steps
- [ ] SMS includes fix steps when check output available, generic fallback otherwise

---

## Fixes & Lessons

### F1: .ralphrc vs ralph.config.json scope

**Problem**: Unclear which config file the harness should read for loop settings.
**Fix**: `.ralphrc` owns Claude-specific settings (tools, session, model fallback).
`ralph.config.json` owns harness settings (iterations, budget, circuit breaker, webhook).
The harness sources both but `ralph.config.json` takes precedence for overlapping keys.

### F2: check.sh must run ALL checks

**Problem**: Early versions of check.sh used `set -e` and exited on first failure.
This gave an incomplete picture — one failing check hid others.
**Fix**: check.sh uses `set -uo pipefail` (no `-e`), runs ALL checks, and reports
the full results as structured JSON. Exit 0 only if ALL pass.

### F3: Chrome zombies on VPS

**Problem**: Headless chromium processes from playwright-cli leaked on crash/timeout,
accumulating until the VPS ran out of memory.
**Fix**: Three-layer cleanup: (1) EXIT trap in run.sh kills orphaned chrome,
(2) cleanup.sh cron every 15 min kills chrome processes older than 30 min,
(3) PM2 restarts the loop process if it crashes.

### F4: Budget tracking across restarts

**Problem**: If the harness crashed and restarted, it lost track of accumulated cost,
potentially exceeding the budget.
**Fix**: State persisted to `.ralph/.harness_state` with total_cost. On startup, run.sh
loads state and resumes from the last known iteration + cost.

### F5: Secret leaking in logs

**Problem**: Claude output and check.sh logs sometimes contained API keys or tokens
from environment variables or .env.local files.
**Fix**: All log output piped through `sanitize()` which strips patterns matching
`API_KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL` followed by `=` or `:`.
**Important**: Claude JSON output is NOT piped through sanitize (see F6) — only log() calls.

### F6: sanitize() corrupted Claude JSON output

**Problem**: Piping Claude's `--output-format json` through `sanitize()` mangled JSON
field names containing "token", "secret", etc., breaking `jq` cost parsing. Budget guard
would never trigger because `cost_usd` always parsed as 0.
**Fix**: Claude output is captured raw into a variable. Only human-readable log messages
pass through `sanitize()`. Cost is extracted from raw JSON before any transformation.

### F7: check.sh exit code capture was masked by `|| true`

**Problem**: `output=$(eval "$cmd" 2>&1) || true` forces `$?` to 0. Then
`exit_code=${PIPESTATUS[0]:-$?}` always saw 0 because PIPESTATUS refers to the last
pipeline, not a command substitution. Every check appeared to pass, and ralph would
declare success on iteration 1.
**Fix**: Removed `|| true`. With `set -uo pipefail` (no `-e`), the failed exit code is
captured in `$?` without terminating the script. `exit_code=$?` now gets the real value.

### F8: Parallel loops stomped on shared state files

**Problem**: With `concurrency > 1` (PM2 on VPS or matrix in CI), all loops wrote to
the same `.harness_state`, `report.json`, and `report_history.jsonl`. Race condition
corrupted budget tracking — each loop only saw its own cost, total was wrong.
**Fix**: All output files are now scoped by `RALPH_LOOP_ID`:

- State: `.harness_state_0`, `.harness_state_1`, etc.
- Reports: `report_0.json`, `report_history_0.jsonl`
- Logs: `loop_0_iter_1.log`, `loop_1_iter_1.log`
- Git commits include loop ID: `ralph-ci: loop 1, iteration 5`
State writes use atomic mv (write to `.tmp`, then rename) to prevent corruption.

### F9: Empty bash arrays crashed with set -u

**Problem**: `${ERRORS[@]:-}` doesn't work for arrays in bash. With `set -u`, referencing
an empty array `${ERRORS[@]}` throws "unbound variable" and check.sh crashes before
producing JSON output. The harness then couldn't parse check results.
**Fix**: Check `${#ERRORS[@]} -gt 0` before expanding. Build the JSON arrays conditionally.

### F10: Build mode didn't gate on PLAN.md

**Problem**: The docs and schema said "build mode success = all checks pass AND PLAN.md
has no PENDING steps." But check.sh only ran lint/build/typecheck/test — it never read
PLAN.md. Build mode would declare success after the first clean iteration, even with
30 PENDING steps remaining.
**Fix**: check.sh now reads `.ralph/PLAN.md` in build mode, counts PENDING steps, and
reports `plan_complete` as a check. If PENDING > 0, check fails.

### F11: biome.jsonc lint detection was broken

**Problem**: The lint check had `if [[ -f "biome.json" || -f "biome.jsonc" ]]` but then
called `run_check "lint" "bunx biome check ." "biome.json"` with `biome.json` as the
skip_if parameter. If only `biome.jsonc` existed, the outer condition passed, but
`run_check` saw `biome.json` missing and silently skipped the check.
**Fix**: Separate the conditions into two elif branches. When biome is detected (either
config file), pass empty string as skip_if since we already confirmed the file exists.

### F12: `timeout` command missing on macOS

**Problem**: `timeout` is GNU coreutils. macOS doesn't have it. Developers testing
harness scripts locally on macOS would get "command not found" and the script would crash.
**Fix**: Auto-detect: try `timeout` first, then `gtimeout` (Homebrew coreutils), then
warn and disable per-iteration timeout. The workflow timeout and kill switch still protect.

### F13: Harness artifacts bloated git repo

**Problem**: `git add -A` in run.sh committed `.harness_state`, `report.json`,
`report_history.jsonl`, and iteration logs into the repo. Over 40 iterations this added
megabytes of state files to git history.
**Fix**: Phase 2 now includes a step to append harness artifact patterns to `.gitignore`.

### F14: Git commands hung on VPS with configured pager

**Problem**: `git diff --name-only` and `git branch --show-current` on a VPS with a
configured pager (e.g., `less`) would hang waiting for interactive input, freezing the loop.
**Fix**: All git commands now use `git --no-pager` flag.

### F15: Webhook URL exposed in public repos

**Problem**: `ralph.config.json` is committed to the repo. If the repo is public,
Slack/Discord webhook URLs are exposed, allowing anyone to post to the channel.
**Mitigation**: Webhook URL should use GitHub Actions secrets or environment variables
instead of being hardcoded in config. The config supports `""` (empty) which disables
webhooks — recommended for public repos. Use `${{ secrets.RALPH_WEBHOOK_URL }}` in CI
and pass as env var to run.sh.

### F16: `grep -c` with `|| echo "0"` produces double output

**Problem**: `grep -c "PATTERN" file || echo "0"` — when grep finds 0 matches, it outputs
`0` to stdout AND returns exit code 1. The `|| echo "0"` fallback appends a second `0`,
producing `"0\n0"` in the variable. This crashes `$((...))` arithmetic with
`syntax error in expression`.
**Fix**: Use `$(grep -c ... ) || true` instead of `|| echo "0"`. `grep -c` always outputs
the count (even 0), so `|| true` just suppresses the non-zero exit code. Add `: "${VAR:=0}"`
as a safety net for the case where stderr redirect swallows all output.

### F17: GitHub Actions matrix output must be single-line JSON

**Problem**: The setup job used `jq -s '{"loop": .}'` which produces pretty-printed multiline
JSON. Writing this to `$GITHUB_OUTPUT` via `echo "value=$SEQ"` failed with
`Invalid format '  "loop": ['` because GitHub Actions expects single-line values unless
using the `<<EOF` heredoc delimiter format.
**Fix**: Use `jq -sc` (compact + slurp) to produce single-line JSON output.

### F18: `tee` fails before run.sh creates logs directory

**Problem**: The CI workflow pipes `run.sh` output through `tee ".ralph/logs/ci_loop_N.log"`,
but `.ralph/logs/` doesn't exist on a fresh checkout. `run.sh` creates it internally
(`mkdir -p "$LOG_DIR"`) but `tee` opens the file BEFORE `run.sh` starts. The step fails
with exit 1 even though ralph itself completed successfully.
**Fix**: Add `mkdir -p .ralph/logs` before the `chmod` and `bash harness/run.sh` commands.

### F19: CI build check fails on missing environment variables

**Problem**: Next.js builds that use server components or route handlers with database access
(Drizzle, Prisma, etc.) evaluate those modules at build time during `next build`'s "Collecting
page data" phase. Without `DATABASE_URL` and other required env vars, the build crashes with
`Error: DATABASE_URL is not set` even though TypeScript compilation succeeds.
**Fix**: Document that users must set environment variable secrets in GitHub Actions for any
env vars their build requires. Add them to the workflow's `env:` block or as step-level `env:`
entries in the "Run Ralph loop" step. Example:

```yaml
env:
  ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

Alternatively, for projects that can't provide real credentials in CI, the build check can be
removed from the `checks` array in `ralph.config.json` and replaced with `typecheck` only.

### F20: verify job "Upload final report" warning on fresh checkout

**Problem**: The verify job's "Upload final report" step tries to upload `.ralph/report_*.json`
and `.ralph/report_history_*.jsonl`, but these files are created by `report.sh` during the loop
job — they exist in the loop job's workspace, not in verify's fresh checkout. GitHub Actions
logs a warning: "No files were found with the provided path."
**Impact**: Harmless — the annotation is a warning, not a failure. The loop job already uploads
these files in its own artifact (`ralph-loop-N`). The verify job's actual failure is from
`check.sh` returning exit 1 when checks fail, which is correct behavior.
**Mitigation**: Leave as-is (the warning is cosmetic). Or remove the report upload from the
verify job since the loop job already handles artifact upload.

### F21: `bun install` fails when no `package.json` exists (build mode)

**Problem**: In build mode, the project starts as a bare shell (symlinked skills + .ralph/ files).
There's no `package.json` until Ralph step 1.1 runs `create-next-app`. The workflow's
"Install project deps" step runs `bun install` unconditionally, which fails with
"Bun could not find a package.json file to install from" and halts the entire job.
**Fix**: Wrap `bun install` in a conditional: `if [ -f package.json ]; then bun install; fi`.
Applied to both the loop job and verify job. Ralph creates `package.json` during its first
iteration, so subsequent loops will have it.

### F22: `--print` requires `-p` flag for prompt, not positional argument

**Problem**: The harness passed the prompt as a bare positional argument after `claude "${CLAUDE_ARGS[@]}"`.
Claude Code CLI's `--print` mode requires input via `-p "prompt"` or stdin — positional arguments
are not recognized. Claude exited immediately with code 1 and the error:
`"Input must be provided either through stdin or as a prompt argument when using --print"`
Every iteration showed $0 cost and 0 files changed.
**Fix**: Add the prompt to CLAUDE_ARGS via `-p "$RALPH_PROMPT"` instead of passing it as a
trailing positional argument. The prompt is defined in a variable for clarity and includes
instructions to read PROMPT.md, PLAN.md, execute the step, and commit.

### F23: CI commits not pushed back to repo

**Problem**: Ralph commits code changes locally on the CI runner during each iteration, but
those commits only exist in the runner's workspace. When the job finishes, the runner is
destroyed and all work is lost. The repo's main branch shows no changes from the ralph loop.
**Fix**: Added a "Push changes back to repo" step that runs `if: always()` (even on failure).
It stages any remaining unstaged changes, commits them, and pushes to the branch.
Requires `permissions: contents: write` at the workflow level. For parallel loops
(concurrency > 1), concurrent push conflicts may occur — the step logs a warning but
doesn't fail the job.

### F24: `AI_GATEWAY_API_KEY` vs `ANTHROPIC_API_KEY` — gateway keys don't work

**Problem**: The 1Password "Dev Environment" item stores `AI_GATEWAY_API_KEY` (a Vercel AI
Gateway key starting with `vck_`), not a direct Anthropic API key. Claude Code CLI requires
a real Anthropic API key (starting with `sk-ant-`). When the gateway key was set as the
`ANTHROPIC_API_KEY` secret, Claude exited immediately with code 1 and $0 cost.
**Fix**: The `ANTHROPIC_API_KEY` GitHub secret must be a direct Anthropic API key (`sk-ant-*`),
not a gateway/proxy key. Check 1Password for a separate "Anthropic" item (secure note category)
containing the raw key. Document this distinction in the Prerequisites section.

### F25: Pause/Resume — graceful stop without killing jobs

**Problem**: The only way to stop ralph was the kill switch, which cancels running jobs
immediately (`gh run cancel`) and sets `RALPH_ENABLED=false`. This is destructive — the
current iteration's work is lost, and re-enabling requires manually toggling the kill switch
back. Users wanted a way to temporarily stop ralph (e.g., to review progress, make manual
changes, or save API costs) and start it back up without losing state.
**Fix**: Added `RALPH_PAUSED` repo variable + two zero-input workflows:

- `ralph-pause.yml` — sets `RALPH_PAUSED=true`. Running loops check this at the start of each
  iteration, save state, and exit with code 6 (paused).
- `ralph-resume.yml` — sets `RALPH_PAUSED=false` and triggers `ralph-loop.yml`. The new loop
  picks up from saved state (iteration count, cost, circuit breaker counters all preserved).
Pause is softer than kill: finishes current iteration cleanly, no `gh run cancel`, state preserved.

### F26: GitHub Actions UI — collapsible iterations + step summary

**Problem**: When running 40+ iterations over 3 hours, all output was one giant log blob in
the GitHub Actions UI. No way to see which iteration was running, which step was being worked
on, or what the overall progress was without scrolling through thousands of lines.
**Fix**: Added three GitHub Actions UI features to `run.sh`:

1. **Collapsible sections**: Each iteration wrapped in `::group::⚡ Iteration N/40 — STEP_NAME`
   / `::endgroup::`. The step name is read from PLAN.md (first PENDING line). Users can click
   to expand/collapse individual iterations.
2. **Step summary**: Progress table written to `$GITHUB_STEP_SUMMARY` after each iteration.
   Shows progress bar, phase breakdown (with emoji status), cost metrics, and current step.
   Visible at the bottom of the GitHub Actions run page.
3. **Annotations**: `::notice::` for successful iterations, `::error::` for failures/circuit
   breakers, `::warning::` for no-progress/timeouts. These appear as highlighted lines in the
   Actions log and in the run summary.
Also added `IS_CI="${GITHUB_ACTIONS:-false}"` detection so these features are no-ops when
running locally.

### F27: SMS notifications for phase completion and errors

**Problem**: Webhook alerts (Slack/Discord) are optional and many users don't configure them.
For long-running builds (3+ hours), users had no way to know when phases completed or when
errors occurred without manually checking the GitHub Actions page.
**Fix**: Added SMS delivery to `report.sh` via n8n webhook. Config in `ralph.config.json`:

```json
"sms": {
  "enabled": true,
  "url": "https://n8n.mattwood.co/webhook/surge-sms",
  "apiKeyEnv": "N8N_SMS_KEY",
  "to": "+1XXXXXXXXXX",
  "events": ["phase_complete", "success", "failure", "circuit_breaker", "budget_exceeded",
             "max_iterations", "kill_switch", "paused", "resumed"]
}
```

SMS API key is read from env var first (for CI), then falls back to `.env.local` (for local).
Phase completion is detected by scanning PLAN.md after each iteration — when all steps in a
phase transition from PENDING to DONE, a `phase_complete` event fires with the phase number.
Phase state is tracked in `.phases_done_${LOOP_ID}` to prevent duplicate notifications.

### F28: CI build fails with `DATABASE_URL is not set` (docker service containers)

**Problem**: Projects using the `docker` + `db` + `env-config` skills have a `docker-compose.yml`
with postgres (and potentially redis, s3, meilisearch). In local dev, `docker compose up` provides
these services. But in GitHub Actions, the `ralph-loop.yml` workflow had no `services:` block and
no `DATABASE_URL` env var. `@t3-oss/env-nextjs` Zod validation runs at build time and crashes with
`Error: DATABASE_URL is not set`, failing the `next build` check before ralph can even start working.
**Fix**: Added Phase 2.5 — "Detect Docker Services for CI". Reads `docker-compose.yml`, maps each
service to a GHA service container (image, health check, ports), and generates `services:` blocks

- matching env vars for both the `loop` and `verify` jobs. Key insight: GHA service containers use
the **service name** as hostname (`postgres`, not `localhost`), so `DATABASE_URL` must be
`postgresql://app:password@postgres:5432/appdb`. Always includes `BETTER_AUTH_SECRET` and
`NEXT_PUBLIC_APP_URL` since the `env-config` skill requires them at build time.

### F29: SMS failure messages are generic — no fix steps

**Problem**: When ralph failed or the verify job failed, the SMS said something like
"ERROR: Loop 1 failed (exit 1)" but gave no indication of what broke or how to fix it.
Users had to open GitHub Actions, find the right job, and read logs to figure out the problem.
**Fix**: Added `generate_fix_steps()` function to `report.sh` — a deterministic pattern-matching
function (no AI API calls) that reads `check.sh` JSON output and maps common error patterns to
actionable fix suggestions. Examples: `DATABASE_URL` in output → "Add DATABASE_URL to GitHub
Actions env vars"; typecheck fail → "Run `bunx tsc --noEmit` locally and fix type errors".
Added `--check-output` argument to `report.sh` that accepts a file path or inline JSON.
Added `verify_failure` event to SMS config. The verify job now captures `check.sh` stdout to
`/tmp/check_output.json` and reports verify failures with fix steps included in the SMS body.
The existing `failure` case also includes fix steps when check output is available.

### F30: CI build fails without docker-compose.yml — env vars skipped entirely

**Problem**: F28 instruction #6 said "If no `docker-compose.yml` exists, skip this entire section",
which skipped ALL env vars including `DATABASE_URL`, `BETTER_AUTH_SECRET`, and `NEXT_PUBLIC_APP_URL`.
But the `env-config` skill validates these at build time via Zod (`.string().url().startsWith("postgres")`
for DATABASE_URL, `.string().min(32)` for BETTER_AUTH_SECRET). Without a docker-compose.yml, `next build`
crashes with `Invalid server environment variables: DATABASE_URL expected string, received undefined`.
This happened in the `voice` project which had the `env-config` + `db` skills but no docker-compose.yml
at the time the workflow was generated.
**Fix**: Changed instruction #6 to "skip the `services:` blocks but still include the env vars".
Added instruction #4 making env vars mandatory regardless of docker detection: dummy `DATABASE_URL`
(`postgresql://ci:ci@localhost:5432/ci`), dummy `BETTER_AUTH_SECRET` (32+ chars), and
`NEXT_PUBLIC_APP_URL`. These pass Zod validation even without a real database connection. The build
succeeds because env validation happens at module load time but the DB connection is only established
when a route actually queries the database — which doesn't happen during `next build`.

---

## Graduation Test (2026-02-19)

Validated ralph-ci on 3 real Next.js projects with different skill compositions,
run in parallel on GitHub Actions:

| Sandbox | Mode | Skills | Loop Time | Circuit Breaker | Checks |
|---------|------|--------|-----------|-----------------|--------|
| A (media/AV) | polish | 8 skills | 3m49s | no-progress at 3/3 | build FAIL, typecheck PASS, lint FAIL |
| B (streaming) | polish | 6 skills | 3m42s | no-progress at 3/3 | build FAIL, typecheck PASS, lint FAIL |
| C (e2e/comms) | build | 5 skills | 3m36s | no-progress at 3/3 | plan_complete FAIL (3 PENDING), build FAIL, typecheck PASS, lint FAIL |

**Repos**: `mattwoodco/sandbox-{a,b,c}-ralph-test` (private)

**Confirmed working**:

- All 3 workflow jobs (setup → loop → verify)
- Matrix generation with compact JSON
- Structured JSON check output with real error details
- No-progress circuit breaker fires at threshold
- Same-error tracking
- Build mode `plan_complete` check (detected 3 PENDING steps)
- Artifact upload
- Polish vs build mode differentiation
- Loop-scoped timestamped logging
- Correct exit codes (exit 2 for circuit breaker)

**Not tested in graduation**: Claude invocation, budget tracking,
cost parsing, polish-mode revert-on-failure.

## Full End-to-End Test (2026-02-19)

Validated the complete pipeline: add-project → ralph-ci → GitHub Actions → Claude working.

| Metric | Value |
|--------|-------|
| Repo | `mattwoodco/sandbox-a-ralph-test` |
| Mode | build |
| Skills | 6 (create-next, add-shadcn, docker, env-config, db, e2e) |
| Plan | 45 steps across 4 phases |
| Iterations run | 6 |
| Steps completed | 6 (1.1 through 1.6) |
| Files changed | 60+ |
| Total cost | $3.96 |
| Loop time | 17m34s |
| Circuit breaker | same-error at 5/5 (recurring lint issue) |
| Push back | All commits pushed to main |

**Confirmed working (NEW — previously untested)**:

- Claude Code invocation with `--print -p` flags
- Real API calls with `sk-ant-*` key
- Budget tracking ($3.96 across 6 iterations)
- Cost parsing from JSON output
- Git commit after each iteration
- Push back to repo from CI runner
- Conditional `bun install` (skips when no package.json)
- Step-by-step plan execution (PENDING → DONE in PLAN.md)

**Fixes applied during test**: F21 (conditional bun install), F22 (-p flag), F23 (push back), F24 (API key type)
