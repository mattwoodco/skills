---
name: openclaw-generator
description: >
  Create a resumable Ralph loop that deploys an OpenClaw instance on any supported provider.
  Beginner-friendly guided setup with provider selection, prerequisite checks, and automatic
  port-back of lessons learned. Supports Fly.io, Railway, Render, DigitalOcean, Coolify,
  and Docker local. Use when the user says "deploy openclaw", "setup openclaw", "openclaw on fly",
  "openclaw on railway", "create openclaw instance", "openclaw generator", "new openclaw",
  "openclaw deploy", or "self-host openclaw".
metadata:
  author: "@mattwoodco"
  version: 1.0.0
  created: 2026-02-19
  updated: 2026-02-19
  validated: 2026-02-19
---

# OpenClaw Generator -- Deploy OpenClaw Anywhere via Ralph Loop

Creates a fully resumable Ralph loop that deploys an OpenClaw instance step-by-step
on the user's chosen provider. Each loop iteration is one micro-step (prereq check,
config, deploy, verify, or fix). Lessons learned during deployment are automatically
ported back to the skill's reference docs.

---

## What Gets Created

```
{project-dir}/
  .ralph/
    PLAN.md                    # Provider-specific deployment plan (micro-steps)
    PROMPT.md                  # Ralph loop discipline + instructions
    PROGRESS.md                # Timestamped progress log (Ralph appends)
    LESSONS.md                 # Deployment gotchas discovered (Ralph appends)
  .ralphrc                     # Ralph configuration (model, tools, timeouts)
  .env                         # Secrets (API keys, tokens) -- gitignored
  references/                  # Symlinked from skill -- provider docs + overview
    OPENCLAW_OVERVIEW.md
    PROVIDER_{NAME}.md
    RALPH_LOOP_TEMPLATE.md
  Dockerfile                   # (cloud providers only) OpenClaw container image
  fly.toml                     # (Fly.io only)
  render.yaml                  # (Render only)
  docker-compose.yml           # (Docker local only)
  .gitignore
  README.md                    # Quick-reference for the deployment
```

---

## Supported Providers

| Provider | Difficulty | Cost | Best For |
|----------|-----------|------|----------|
| **Docker Local** | Easiest | Free (API costs only) | Trying OpenClaw on your machine |
| **Railway** | Easy | $5-20/month | Quick cloud deploy with web wizard |
| **Fly.io** | Easy | $5-15/month | Global edge deployment |
| **DigitalOcean** | Easy | $12-24/month | 1-Click marketplace or manual VPS |
| **Coolify** | Moderate | Free + VPS costs | Self-hosted PaaS on your own server |
| **Render** | Easy | $7-25/month | Zero-config cloud with render.yaml |

---

## Prerequisites

- **Claude Code CLI** with Ralph loop support
- **Git** installed
- **Node.js 22+** (for local testing; cloud providers handle this)
- **At least one AI model API key** (Anthropic recommended: `ANTHROPIC_API_KEY`)
- **Provider-specific tooling** (installed during the loop):
  - Fly.io: `flyctl`
  - Railway: `@railway/cli`
  - DigitalOcean: `doctl` or browser
  - Docker: Docker Desktop or Docker Engine
  - Coolify: Browser access to Coolify dashboard
  - Render: Browser access to Render dashboard

---

## Phase 0: Provider Selection

Ask the user which provider they want to deploy to. Use `AskUserQuestion` with these options:

```
AskUserQuestion:
  question: "Which provider do you want to deploy OpenClaw to?"
  header: "Provider"
  options:
    - label: "Docker Local (Recommended for beginners)"
      description: "Run OpenClaw in Docker on your machine. Free, instant, great for trying it out."
    - label: "Railway"
      description: "One-click cloud deploy with web setup wizard. $5-20/month usage-based."
    - label: "Fly.io"
      description: "Global edge deployment with persistent volumes. $5-15/month."
    - label: "DigitalOcean"
      description: "1-Click Droplet or manual VPS. $12-24/month. Most documented."
  multiSelect: false
```

If the user picks "Other", follow up with a second question offering Coolify and Render.

Store the selected provider as `{PROVIDER}` for the rest of the skill.

---

## Phase 1: Pre-Flight -- Interactive Setup (Before Ralph)

**This phase runs interactively before the Ralph loop is created.** It collects
all secrets, authenticates with the provider, and validates everything works.
Once pre-flight passes, the Ralph loop is 100% autonomous with zero user interaction.

### Step 1.1: Collect AI model API key

```
AskUserQuestion:
  question: "What is your Anthropic API key? (starts with sk-ant-)"
  header: "API Key"
  options:
    - label: "I have it in my environment"
      description: "ANTHROPIC_API_KEY is already exported in my shell"
    - label: "I'll paste it now"
      description: "I have the key ready to paste"
    - label: "I use a different provider"
      description: "I use OpenAI, OpenRouter, or another provider instead"
  multiSelect: false
```

If "already in environment", verify: `echo $ANTHROPIC_API_KEY | head -c 10` shows `sk-ant-...`.
If "paste it now", store it securely for the `.env` file.
If "different provider", ask which provider and which env var to use.

### Step 1.2: Install and authenticate provider CLI

Run the provider-specific CLI setup **interactively** so the user can complete
any browser-based auth flows:

**Fly.io:**

```bash
# Install flyctl if missing
command -v flyctl >/dev/null || curl -L https://fly.io/install.sh | sh
# Login (opens browser for OAuth)
fly auth login
# Verify
fly auth whoami
```

**Railway:**

```bash
# Install CLI if missing
command -v railway >/dev/null || npm install -g @railway/cli
# Login (opens browser for OAuth)
railway login
# Verify
railway whoami
```

**Docker Local:**

```bash
# Verify Docker is running
docker info >/dev/null 2>&1 || echo "ERROR: Docker is not running. Start Docker Desktop first."
```

**DigitalOcean:**

```bash
# If using doctl:
command -v doctl >/dev/null || brew install doctl  # or snap install doctl
doctl auth init  # prompts for API token
doctl account get
# If browser-only: skip CLI, confirm user has dashboard access
```

**Coolify:**

```
AskUserQuestion:
  question: "What is the URL of your Coolify dashboard?"
  header: "Coolify URL"
  options:
    - label: "I use Coolify Cloud"
      description: "My dashboard is at app.coolify.io"
    - label: "Self-hosted"
      description: "I'll provide my Coolify URL"
  multiSelect: false
```

**Render:**
No CLI needed -- confirm user has Render dashboard access and a GitHub repo ready.

### Step 1.3: Generate security tokens

Generate tokens that will be baked into the `.env` file:

```bash
# Generate a secure gateway auth token
OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)

# For Railway: generate a setup password
SETUP_PASSWORD=$(openssl rand -hex 16)
```

### Step 1.4: Validate all prerequisites

Run a final validation checklist and display results:

```
Pre-Flight Checklist:
  [x] AI model API key verified
  [x] Provider CLI installed and authenticated
  [x] Gateway token generated
  [x] Docker running (if Docker Local)
  [ ] Provider-specific requirements met

All checks passed. The Ralph loop will run fully autonomously from here.
```

If any check fails, tell the user exactly what to fix and re-run the check.
Do NOT proceed to Phase 2 until all checks pass.

### Step 1.5: Write .env file

Write all collected secrets to `{PROJECT_NAME}/.env`:

```bash
# .env -- OpenClaw deployment secrets (DO NOT COMMIT)
# Generated by openclaw-generator pre-flight

# AI Model Provider
ANTHROPIC_API_KEY={collected_key}

# OpenClaw Gateway Auth
OPENCLAW_GATEWAY_TOKEN={generated_token}

# Provider-specific (Railway only)
SETUP_PASSWORD={generated_password}
```

This file is gitignored. Ralph reads it via `source .env` at the start of deploy steps.

---

## Phase 2: Create Project Directory

### Step 2.1: Ask for project name

```
AskUserQuestion:
  question: "What should we name this OpenClaw deployment?"
  header: "Name"
  options:
    - label: "openclaw-local"
      description: "Default name for a local/personal instance"
    - label: "openclaw-prod"
      description: "For a production deployment"
    - label: "openclaw-dev"
      description: "For a development/testing instance"
  multiSelect: false
```

Store the name as `{PROJECT_NAME}`.

### Step 2.2: Create directory structure

```bash
mkdir -p {PROJECT_NAME}/.ralph
mkdir -p {PROJECT_NAME}/references
cd {PROJECT_NAME}
git init
```

### Step 2.3: Create .gitignore

```gitignore
# OpenClaw state
.openclaw/

# Ralph logs (keep structure, ignore content)
.ralph/logs/

# Environment secrets
.env
.env.*

# Node
node_modules/

# OS
.DS_Store
```

---

## Phase 3: Generate Ralph Loop Files

### Step 3.1: Read the provider reference doc

Read the provider-specific reference doc from this skill's `references/` directory:

- Docker Local: `references/PROVIDER_DOCKER_LOCAL.md`
- Railway: `references/PROVIDER_RAILWAY.md`
- Fly.io: `references/PROVIDER_FLYIO.md`
- DigitalOcean: `references/PROVIDER_DIGITALOCEAN.md`
- Coolify: `references/PROVIDER_COOLIFY.md`
- Render: `references/PROVIDER_RENDER.md`

Also read `references/OPENCLAW_OVERVIEW.md` for the full OpenClaw reference.

### Step 3.2: Read the Ralph loop template

Read `references/RALPH_LOOP_TEMPLATE.md` to get the templates for all Ralph files.

### Step 3.3: Generate .ralphrc

Write `.ralphrc` to the project root using the template from `RALPH_LOOP_TEMPLATE.md`.
Replace `{PROVIDER_NAME}` with the selected provider.

### Step 3.4: Generate .ralph/PROMPT.md

Write `.ralph/PROMPT.md` using the PROMPT.md template from `RALPH_LOOP_TEMPLATE.md`.
Replace `{PROVIDER_NAME}` with the selected provider.

### Step 3.5: Generate .ralph/PLAN.md

Write `.ralph/PLAN.md` using the **provider-specific** PLAN.md template from
`RALPH_LOOP_TEMPLATE.md`. Each provider has a different plan with provider-specific
steps. Select the correct template based on `{PROVIDER}`.

### Step 3.6: Generate .ralph/PROGRESS.md

Write `.ralph/PROGRESS.md` using the PROGRESS.md template. Replace `{PROVIDER_NAME}`
and `{DATE}` with actual values.

### Step 3.7: Generate .ralph/LESSONS.md

Write `.ralph/LESSONS.md` using the LESSONS.md template. This starts empty and Ralph
populates it during the loop.

---

## Phase 4: Symlink Reference Docs

Symlink the relevant reference docs from this skill into the project's `references/`
directory so Ralph can access them during the loop:

```bash
# Always include the overview
ln -s ../../../skills-polish/skills/openclaw-generator/references/OPENCLAW_OVERVIEW.md references/OPENCLAW_OVERVIEW.md

# Include the selected provider doc
ln -s ../../../skills-polish/skills/openclaw-generator/references/PROVIDER_{PROVIDER}.md references/PROVIDER_{PROVIDER}.md

# Include the loop template for reference
ln -s ../../../skills-polish/skills/openclaw-generator/references/RALPH_LOOP_TEMPLATE.md references/RALPH_LOOP_TEMPLATE.md
```

**Note**: Adjust the relative path based on where the project directory is created.
If the path doesn't work, copy the files instead of symlinking:

```bash
cp {skill-path}/references/OPENCLAW_OVERVIEW.md references/
cp {skill-path}/references/PROVIDER_{PROVIDER}.md references/
cp {skill-path}/references/RALPH_LOOP_TEMPLATE.md references/
```

---

## Phase 5: Provider-Specific Scaffolding

Based on the selected provider, create additional files the Ralph loop will need.

### If Fly.io

Create a starter `Dockerfile`:

```dockerfile
FROM node:22-slim

RUN npm install -g openclaw@latest

ENV OPENCLAW_STATE_DIR=/data
ENV OPENCLAW_GATEWAY_BIND=lan

EXPOSE 18789

CMD ["openclaw", "gateway", "--port", "18789"]
```

### If Railway

Create the same Dockerfile as Fly.io, but with `EXPOSE 8080` and port `8080`:

```dockerfile
FROM node:22-slim

RUN npm install -g openclaw@latest

ENV OPENCLAW_STATE_DIR=/data/.openclaw
ENV OPENCLAW_WORKSPACE_DIR=/data/workspace
ENV OPENCLAW_GATEWAY_BIND=lan

EXPOSE 8080

CMD ["openclaw", "gateway", "--port", "8080"]
```

### If Render

Create the Dockerfile (same as Railway) plus `render.yaml`:

```yaml
services:
  - type: web
    name: openclaw
    runtime: docker
    plan: starter
    disk:
      name: openclaw-data
      mountPath: /data
      sizeGB: 1
    envVars:
      - key: OPENCLAW_STATE_DIR
        value: /data/openclaw
      - key: OPENCLAW_GATEWAY_BIND
        value: lan
      - key: OPENCLAW_GATEWAY_TOKEN
        generateValue: true
      - key: PORT
        value: "18789"
```

### If Docker Local

Create `docker-compose.yml`:

```yaml
services:
  openclaw:
    build: .
    ports:
      - "18789:18789"
    volumes:
      - openclaw-data:/data/openclaw
    environment:
      OPENCLAW_STATE_DIR: /data/openclaw
      OPENCLAW_GATEWAY_BIND: loopback
    restart: unless-stopped

volumes:
  openclaw-data:
```

And the Dockerfile:

```dockerfile
FROM node:22-slim

RUN npm install -g openclaw@latest

ENV OPENCLAW_STATE_DIR=/data/openclaw

EXPOSE 18789

CMD ["openclaw", "gateway", "--port", "18789"]
```

### If DigitalOcean or Coolify

No additional files needed -- deployment is done through the provider's UI/CLI.

---

## Phase 6: Create README

Write `README.md` in the project root:

```markdown
# {PROJECT_NAME} -- OpenClaw on {PROVIDER_NAME}

## Quick Start

This project deploys OpenClaw to {PROVIDER_NAME} using an automated Ralph loop.

### Resume the deployment loop

```bash
cd {PROJECT_NAME}
claude --continue
```

Ralph will pick up where it left off, executing the next PENDING step in `.ralph/PLAN.md`.

### Check progress

```bash
cat .ralph/PROGRESS.md
cat .ralph/PLAN.md
```

### Lessons learned

Deployment gotchas and fixes are captured in `.ralph/LESSONS.md`.
These are automatically ported back to the skill reference docs every 5 iterations.

## Provider: {PROVIDER_NAME}

See `references/PROVIDER_{PROVIDER}.md` for the full deployment guide.

## OpenClaw Reference

See `references/OPENCLAW_OVERVIEW.md` for OpenClaw docs, CLI commands, and environment variables.

```

---

## Phase 7: Initial Commit and Handoff

### Step 7.1: Stage and commit

```bash
cd {PROJECT_NAME}
git add -A
git commit -m "scaffold: OpenClaw deployment to {PROVIDER_NAME} via Ralph loop"
```

### Step 7.2: Print summary

Display to the user:

```
OpenClaw Generator -- Setup Complete

  Provider:    {PROVIDER_NAME}
  Project:     {PROJECT_NAME}/
  Plan:        .ralph/PLAN.md ({N} steps)
  Config:      .ralphrc

Pre-flight completed:
  [x] API key verified and saved to .env
  [x] Provider CLI installed and authenticated
  [x] Gateway token generated

Next steps:
  1. cd {PROJECT_NAME}
  2. Start the Ralph loop: claude --continue
  3. Ralph runs fully autonomously -- no more user input needed
  4. Resume anytime with: claude --continue

The loop is fully resumable. All secrets are in .env (gitignored).
Lessons learned are saved to .ralph/LESSONS.md and ported back to skill docs.
```

---

## Phase 8: Port-Back Mechanism

This phase runs **during the Ralph loop**, not during initial setup.

The PROMPT.md instructs Ralph to port back lessons every 5th iteration:

1. Ralph reads `.ralph/LESSONS.md` for new entries
2. If there are entries not yet ported back, Ralph reads the relevant provider
   reference doc from `references/PROVIDER_{NAME}.md`
3. Ralph appends a new section to the reference doc's Troubleshooting section
   with the discovered gotcha and fix
4. Ralph logs the port-back in `.ralph/PROGRESS.md`

### What gets ported back

- **Configuration gotchas**: Wrong env var names, missing config values, default overrides
- **Provider quirks**: Timeout values, volume mount paths, port mapping issues
- **Version changes**: Breaking changes in OpenClaw CLI, deprecated flags
- **Security fixes**: Auth token generation, binding mode issues
- **Cost gotchas**: Unexpected charges, resource sizing tips

### How port-back updates persist

Since the reference docs in the project are either symlinked or copied from the
skill directory:

- **If symlinked**: Changes propagate automatically to the skill source
- **If copied**: After the loop completes, copy the updated reference docs back:

```bash
cp references/PROVIDER_{NAME}.md {skill-path}/references/PROVIDER_{NAME}.md
```

---

## Usage

### First-time deployment

```bash
# In the skills-polish directory or any project with this skill available
/openclaw-generator
```

The skill will walk you through provider selection and scaffold the Ralph loop.

### Resuming a deployment

```bash
cd {PROJECT_NAME}
claude --continue
```

### Starting over with a different provider

```bash
# Create a new project directory (don't overwrite the old one)
/openclaw-generator
```

### Checking deployment status

```bash
cd {PROJECT_NAME}
cat .ralph/PLAN.md        # See which steps are done/pending
cat .ralph/PROGRESS.md    # See detailed progress log
cat .ralph/LESSONS.md     # See discovered gotchas
```

---

## Acceptance Criteria

- [ ] User was prompted to select a provider via AskUserQuestion
- [ ] Pre-flight: API key collected and verified
- [ ] Pre-flight: Provider CLI installed and authenticated (interactive)
- [ ] Pre-flight: Gateway token generated
- [ ] Pre-flight: All prerequisites validated before Ralph loop created
- [ ] Pre-flight: `.env` file written with all secrets (gitignored)
- [ ] User was prompted to name the project
- [ ] Project directory was created with `.ralph/`, `references/`, `.ralphrc`, `.env`
- [ ] `.ralph/PLAN.md` contains provider-specific micro-steps with status tracking
- [ ] `.ralph/PROMPT.md` contains loop discipline with port-back instructions
- [ ] `.ralph/PROGRESS.md` was initialized with session info
- [ ] `.ralph/LESSONS.md` was initialized (empty, ready for Ralph to populate)
- [ ] `.ralphrc` configures sonnet model, tools, session continuity
- [ ] Reference docs (overview + provider) are available in `references/`
- [ ] Provider-specific files created (Dockerfile, fly.toml, render.yaml, docker-compose.yml)
- [ ] `.gitignore` excludes secrets, node_modules, OpenClaw state, Ralph logs
- [ ] `README.md` documents how to resume the loop and check progress
- [ ] Initial git commit was made
- [ ] Summary with next steps was displayed to user
- [ ] Port-back mechanism is documented in PROMPT.md (every 5th iteration)

---

## Troubleshooting

### "Ralph keeps repeating the same step"

The circuit breaker in `.ralphrc` should catch this. If not, check `.ralph/PLAN.md`
to see if the step's status was actually updated to DONE. Ralph may have completed
the work but failed to update the tracking file.

### "I need to change providers mid-deploy"

Create a new project directory with the new provider. Don't try to reuse the old
Ralph loop -- the PLAN.md steps are provider-specific.

### "The symlinks don't work"

If the relative paths don't resolve (common when the project dir is in a different
location), the skill falls back to copying files. Check that `references/*.md` files
exist and contain content.

### "OpenClaw version changed since I started"

Run `npm install -g openclaw@latest` (or rebuild the Docker image) and resume the
Ralph loop. If the CLI flags changed, check `references/OPENCLAW_OVERVIEW.md` and
update if needed -- this is exactly what the port-back mechanism handles.
