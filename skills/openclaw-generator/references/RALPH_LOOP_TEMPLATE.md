# Ralph Loop Templates for OpenClaw Generator

These templates are used by the openclaw-generator skill to scaffold a resumable
Ralph loop in the user's target project directory.

---

## .ralphrc Template

```
# Ralph Configuration for OpenClaw Deployment
# Provider: {PROVIDER_NAME}

# Model -- use sonnet for deployment tasks (needs reasoning for config)
CLAUDE_MODEL=claude-sonnet-4-6

# Rate limiting
MAX_CALLS_PER_HOUR=30

# Claude timeout per loop iteration (minutes)
CLAUDE_TIMEOUT_MINUTES=15

# Output format
CLAUDE_OUTPUT_FORMAT=json

# Allowed tools
CLAUDE_ALLOWED_TOOLS="Write,Read,Edit,Glob,Grep,Bash(*),Task,WebFetch,WebSearch"

# Session continuity -- critical for resumability
CLAUDE_USE_CONTINUE=true

# Session expiry (hours)
CLAUDE_SESSION_EXPIRY_HOURS=24

# Verbose progress logging
VERBOSE_PROGRESS=true
```

---

## PROMPT.md Template

```markdown
# Ralph -- OpenClaw Deployer ({PROVIDER_NAME})

## Context
You are Ralph, deploying an OpenClaw instance to {PROVIDER_NAME}.
Your reference docs are in `references/` -- read them before acting.

## Pre-Flight Already Completed
The following were handled interactively BEFORE this loop started:
- Provider CLI is installed and authenticated
- AI model API key is verified and saved in `.env`
- Gateway auth token is generated and saved in `.env`
- All prerequisites have been validated

**You do NOT need to ask the user for anything.** Source `.env` for secrets.
If a step fails, diagnose and fix it autonomously. Do not exit with BLOCKED
expecting user input -- that defeats the purpose of pre-flight.

## Non-Negotiable Loop Discipline

Each loop = one micro-step only.

- Read `.ralph/PLAN.md` and execute only the first `PENDING` step.
- Never combine multiple steps in one loop.
- Budget work for a short loop. If a step is too large, mark it `PARTIAL` and stop.
- Stop immediately after updating tracking files and status block.

## Files You Must Keep Updated Every Loop

- `.ralph/PLAN.md` -- mark current step DONE or PARTIAL
- `.ralph/PROGRESS.md` -- append timestamped entry
- `.ralph/LESSONS.md` -- append any learnings (provider gotchas, config fixes)

## Micro-Step Types

1. **Config step** -- create or edit a configuration file
2. **Deploy step** -- run a deployment command
3. **Verify step** -- run a health check or status command
4. **Fix step** -- diagnose and fix one failure
5. **Port-back step** -- update the skill's reference docs with lessons learned

## Verification Gates

After any deploy or config step, run:
1. The provider's status/health command
2. `curl` or `openclaw` CLI health check
3. Screenshot or log capture of the result

## Problem-Fix Rule

When fixing a defect:
1. List 3-5 plausible causes
2. Pick the top 1-2 most likely
3. Add temporary diagnostics to validate
4. Fix only after assumptions confirmed
5. Remove diagnostic noise after fix

Capture reasoning in `PROGRESS.md`.

## Port-Back Rule

Every 5th loop iteration (steps 5, 10, 15, ...):
1. Review LESSONS.md for new entries
2. If there are new lessons, update the relevant provider reference doc
3. Log what was ported back in PROGRESS.md

## Status Block (required every loop)

```text
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
TASKS_COMPLETED_THIS_LOOP: 0 | 1
STEP_ID: <step number>
PROVIDER: {PROVIDER_NAME}
DEPLOY_STATUS: NOT_STARTED | IN_PROGRESS | DEPLOYED | FAILED
HEALTH_CHECK: PASSING | FAILING | NOT_RUN
EXIT_SIGNAL: false | true
RECOMMENDATION: <next micro-step id and action>
---END_RALPH_STATUS---
```
```

---

## PLAN.md Template -- Fly.io

```markdown
# OpenClaw Deployment Plan -- Fly.io

| Step | Status | Task | Verify |
|------|--------|------|--------|
| 1 | PENDING | Source `.env`, create Fly app: `fly launch --name openclaw-{name} --region iad --no-deploy` | `fly apps list` shows app |
| 2 | PENDING | Create persistent volume: `fly volumes create openclaw_data --size 1 --region iad` | `fly volumes list` shows volume |
| 3 | PENDING | Create fly.toml with gateway config, mounts, services | fly.toml exists and is valid |
| 4 | PENDING | Verify Dockerfile exists (created by pre-flight scaffolding) | Dockerfile exists |
| 5 | PENDING | Set secrets from .env: `fly secrets set OPENCLAW_GATEWAY_TOKEN=... ANTHROPIC_API_KEY=...` | `fly secrets list` shows keys |
| 6 | PENDING | Port-back: review LESSONS.md, update reference docs | LESSONS.md reviewed |
| 7 | PENDING | Deploy: `fly deploy` | `fly status` shows running |
| 8 | PENDING | Verify health: `fly ssh console -C "openclaw health --json"` | Health JSON shows ok |
| 9 | PENDING | Access Control UI and confirm login | Screenshot or curl of UI |
| 10 | PENDING | Final status report | All checks passing |
```

---

## PLAN.md Template -- Railway

```markdown
# OpenClaw Deployment Plan -- Railway

| Step | Status | Task | Verify |
|------|--------|------|--------|
| 1 | PENDING | Source `.env`, init Railway project: `railway init` | Railway project linked |
| 2 | PENDING | Verify Dockerfile exists (created by pre-flight scaffolding) | Dockerfile valid |
| 3 | PENDING | Set environment variables from .env in Railway | `railway variables` shows all keys |
| 4 | PENDING | Add persistent volume at /data via Railway dashboard | Volume visible |
| 5 | PENDING | Port-back: review LESSONS.md, update reference docs | LESSONS.md reviewed |
| 6 | PENDING | Deploy: `railway up` | `railway status` shows deployed |
| 7 | PENDING | Get public domain: `railway domain` | URL returned |
| 8 | PENDING | Access setup wizard at /setup, complete onboarding | Setup complete |
| 9 | PENDING | Verify health via Control UI | UI accessible, health green |
| 10 | PENDING | Port-back: review LESSONS.md, update reference docs | LESSONS.md reviewed |
| 11 | PENDING | Final status report | All checks passing |
```

---

## PLAN.md Template -- Render

```markdown
# OpenClaw Deployment Plan -- Render

| Step | Status | Task | Verify |
|------|--------|------|--------|
| 1 | PENDING | Source `.env`, verify Dockerfile and render.yaml exist | Files valid |
| 2 | PENDING | Init GitHub repo and push | Git push succeeds |
| 3 | PENDING | Create Blueprint in Render dashboard from repo | Service deploying |
| 4 | PENDING | Set model API keys from .env in Render dashboard | Keys set |
| 5 | PENDING | Port-back: review LESSONS.md | LESSONS.md reviewed |
| 6 | PENDING | Wait for deploy and verify health | Service running, health ok |
| 7 | PENDING | Access Control UI | UI accessible |
| 8 | PENDING | Final status report | All checks passing |
```

---

## PLAN.md Template -- DigitalOcean

```markdown
# OpenClaw Deployment Plan -- DigitalOcean

| Step | Status | Task | Verify |
|------|--------|------|--------|
| 1 | PENDING | Source `.env`, create Droplet (1-Click or Ubuntu 22.04 via doctl/dashboard) | Droplet running |
| 2 | PENDING | SSH into Droplet | SSH session active |
| 3 | PENDING | Install OpenClaw (if manual) or run setup wizard (if 1-Click) | OpenClaw installed |
| 4 | PENDING | Configure gateway binding to `lan` and set auth token from .env | Config set |
| 5 | PENDING | Port-back: review LESSONS.md | LESSONS.md reviewed |
| 6 | PENDING | Set model API keys from .env | Keys configured |
| 7 | PENDING | Start gateway service: `openclaw gateway install && openclaw gateway start` | Service running |
| 8 | PENDING | Configure firewall: `ufw allow 18789/tcp` | Port open |
| 9 | PENDING | Verify health: `openclaw gateway status --deep` | All green |
| 10 | PENDING | Port-back: review LESSONS.md | LESSONS.md reviewed |
| 11 | PENDING | Access Control UI | UI accessible |
| 12 | PENDING | Final status report | All checks passing |
```

---

## PLAN.md Template -- Coolify

```markdown
# OpenClaw Deployment Plan -- Coolify

| Step | Status | Task | Verify |
|------|--------|------|--------|
| 1 | PENDING | Source `.env`, create OpenClaw service in Coolify (Services > New > OpenClaw) | Service created |
| 2 | PENDING | Configure env vars from .env (token, API keys, OPENCLAW_STATE_DIR=/data) | Vars set |
| 3 | PENDING | Configure persistent storage at /data | Volume attached |
| 4 | PENDING | Deploy service | Service deploying |
| 5 | PENDING | Port-back: review LESSONS.md | LESSONS.md reviewed |
| 6 | PENDING | Wait for deploy and check logs | Logs show gateway started |
| 7 | PENDING | Access Control UI via Coolify domain | UI accessible |
| 8 | PENDING | Final status report | All checks passing |
```

---

## PLAN.md Template -- Docker Local

```markdown
# OpenClaw Deployment Plan -- Docker Local

| Step | Status | Task | Verify |
|------|--------|------|--------|
| 1 | PENDING | Source `.env`, verify docker-compose.yml and Dockerfile exist | Files valid |
| 2 | PENDING | Build Docker image: `docker compose build` | `docker images` shows openclaw |
| 3 | PENDING | Run onboarding: `docker compose run --rm openclaw-cli onboard` (non-interactive, using .env) | Onboarding complete |
| 4 | PENDING | Start gateway: `docker compose up -d` | Container running |
| 5 | PENDING | Port-back: review LESSONS.md | LESSONS.md reviewed |
| 6 | PENDING | Verify: `docker compose ps` and `curl http://127.0.0.1:18789/` | All healthy |
| 7 | PENDING | Access Control UI at http://127.0.0.1:18789/ | UI loads |
| 8 | PENDING | Enter auth token from .env in Settings | Token accepted |
| 9 | PENDING | Final status report | All checks passing |
```

---

## PROGRESS.md Template

```markdown
# OpenClaw Deployment Progress -- {PROVIDER_NAME}

## Session Info
- **Provider**: {PROVIDER_NAME}
- **Started**: {DATE}
- **Status**: IN_PROGRESS

## Progress Log

<!-- Ralph appends entries here each loop iteration -->
```

---

## LESSONS.md Template

```markdown
# Lessons Learned -- OpenClaw on {PROVIDER_NAME}

## Purpose
This file captures deployment gotchas, config quirks, and fixes discovered
during the Ralph loop. Every 5th iteration, new lessons are ported back
to the provider reference doc in `references/PROVIDER_{NAME}.md`.

## Lessons

<!-- Ralph appends entries here as issues are discovered -->
```
