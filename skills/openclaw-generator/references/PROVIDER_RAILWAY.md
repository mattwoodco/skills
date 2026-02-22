# OpenClaw Provider Reference: Railway

## Provider Overview

**Railway** is a managed infrastructure platform that deploys apps from Git repositories or Docker images with zero configuration. Railway handles builds, networking, TLS, environment variables, and persistent storage through a polished dashboard and CLI.

Railway is a strong choice for OpenClaw because:

- One-command deploys from a local directory or Git push
- Built-in persistent volumes for state storage
- Automatic HTTPS with custom domain support
- Usage-based billing (pay only for what you use)
- Simple environment variable management through the dashboard

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Railway account** | Sign up at [railway.app](https://railway.app). |
| **GitHub account** | Needed if deploying from a Git repo (optional for CLI deploys). |
| **Railway CLI** | Installed in Step 1 below. |
| **Node.js 18+** | Required for the Railway CLI installation. |
| **API keys** | At least one model provider API key (e.g., `ANTHROPIC_API_KEY`). |

---

## Cost Estimate

| Resource | Monthly Cost |
|---|---|
| Compute (0.5 vCPU, 512 MB) | ~$5-10/month |
| Persistent volume (1 GB) | ~$0.25/month |
| Network egress (typical) | ~$0-5/month |
| **Total estimate** | **$5-20/month** |

> Railway uses usage-based pricing. You pay per minute of compute and per GB of storage and bandwidth. The Trial plan includes $5 of free credit. The Hobby plan is $5/month and includes $5 of usage credit.

---

## Step-by-Step Deployment

### Step 1: Install the Railway CLI

```bash
npm install -g @railway/cli
```

Then log in to your Railway account:

```bash
railway login
```

This opens a browser window for authentication. Complete the login and return to your terminal.

Verify the CLI is working:

```bash
railway whoami
```

### Step 2: Create a project directory

```bash
mkdir openclaw-instance && cd openclaw-instance
```

### Step 3: Initialize a Railway project

```bash
railway init --name openclaw-instance
```

Select your team/workspace when prompted. This links your local directory to a new Railway project.

### Step 4: Create the Dockerfile

Create a `Dockerfile` in the project directory:

```dockerfile
FROM node:22-slim

# Install openclaw globally
RUN npm install -g openclaw@latest

# Create data directories for persistent storage
RUN mkdir -p /data/.openclaw /data/workspace

# Set working directory
WORKDIR /data/workspace

# Expose the gateway port
EXPOSE 8080

# Start the OpenClaw gateway
CMD ["openclaw", "gateway", "--port", "8080", "--bind", "lan"]
```

### Step 5: Add a persistent volume

Volumes must be added through the Railway dashboard:

1. Open your project at [railway.app/dashboard](https://railway.app/dashboard)
2. Click on your service
3. Go to the **Settings** tab
4. Scroll to **Volumes**
5. Click **Add Volume**
6. Set the mount path to `/data`
7. Click **Save**

> The volume persists OpenClaw state, workspace files, and configuration across deploys and restarts.

### Step 6: Set environment variables

You can set environment variables via the CLI or the dashboard.

**Via CLI:**

```bash
railway variables set OPENCLAW_STATE_DIR=/data/.openclaw
railway variables set OPENCLAW_WORKSPACE_DIR=/data/workspace
railway variables set PORT=8080
railway variables set OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
railway variables set SETUP_PASSWORD=$(openssl rand -hex 16)
railway variables set ANTHROPIC_API_KEY=sk-ant-your-key-here
```

**Via Dashboard:**

1. Open your project at [railway.app/dashboard](https://railway.app/dashboard)
2. Click on your service
3. Go to the **Variables** tab
4. Add each variable:

| Variable | Value |
|---|---|
| `OPENCLAW_STATE_DIR` | `/data/.openclaw` |
| `OPENCLAW_WORKSPACE_DIR` | `/data/workspace` |
| `PORT` | `8080` |
| `OPENCLAW_GATEWAY_TOKEN` | (generate a random 64-char hex string) |
| `SETUP_PASSWORD` | (generate a random 32-char hex string) |
| `ANTHROPIC_API_KEY` | Your Anthropic API key |

Add any additional model provider keys as needed (e.g., `OPENAI_API_KEY`).

> **Tip:** To generate a random hex string, run `openssl rand -hex 32` in your terminal and paste the output.

### Step 7: Deploy

```bash
railway up
```

This builds the Docker image and deploys it to Railway. The first deploy takes 2-5 minutes.

Watch the build output in your terminal. You should see:

- Docker image building
- Image pushing to Railway's registry
- Deployment starting

### Step 8: Get your domain

Railway assigns a random domain by default. Retrieve it:

```bash
railway domain
```

If no domain is assigned, generate one:

1. Open your project in the Railway dashboard
2. Click on your service
3. Go to the **Settings** tab
4. Under **Networking**, click **Generate Domain**

You can also add a custom domain in the same section.

Your domain will look like: `openclaw-instance-production-XXXX.up.railway.app`

### Step 9: Access the setup wizard

Open your browser and navigate to:

```
https://YOUR-DOMAIN/setup
```

The setup wizard walks you through initial configuration:

1. **Admin password** - Set a password for the control panel
2. **API keys** - Confirm or add model provider API keys
3. **Channels** - Configure your first communication channel

### Step 10: Access the Control UI

After completing the setup wizard, the Control UI is available at:

```
https://YOUR-DOMAIN/openclaw
```

Log in with the admin credentials you created during setup.

---

## Validation Commands

Run these to confirm everything is working:

```bash
# View deploy logs in real-time
railway logs

# Check service status
railway status

# Test the health endpoint
curl -s https://YOUR-DOMAIN/

# Test with authentication header
curl -s -H "Authorization: Bearer YOUR_GATEWAY_TOKEN" https://YOUR-DOMAIN/api/status

# Open the project in Railway dashboard
railway open
```

---

## Backup

OpenClaw supports exporting your configuration and data through the setup interface:

```
https://YOUR-DOMAIN/setup/export
```

This exports:

- Channel configurations
- API key references (not the actual keys)
- Workspace settings
- Custom configurations

> **Recommendation:** Export a backup before any major changes or before tearing down the deployment.

---

## Troubleshooting

### Deploy fails with build errors

**Symptom:** `railway up` fails during the Docker build step.

**Cause:** Usually a network issue pulling the base image or installing packages.

**Fix:**

```bash
# Retry the deploy
railway up

# If it persists, check your Dockerfile syntax
docker build -t test-build .
```

### Volume not persisting data

**Symptom:** State is lost after redeploy. Configuration resets to defaults.

**Cause:** Volume mount path does not match the `OPENCLAW_STATE_DIR` environment variable.

**Fix:**

1. In the Railway dashboard, check the volume mount path (should be `/data`)
2. Confirm `OPENCLAW_STATE_DIR` is set to `/data/.openclaw`
3. Confirm `OPENCLAW_WORKSPACE_DIR` is set to `/data/workspace`
4. Redeploy after fixing

### Port binding errors

**Symptom:** Service crashes immediately after starting. Logs show `EADDRINUSE` or similar.

**Cause:** The `PORT` environment variable does not match the port in the Dockerfile CMD.

**Fix:** Ensure consistency:

- `PORT` env var = `8080`
- Dockerfile `EXPOSE` = `8080`
- Dockerfile CMD `--port` = `8080`

### Service keeps restarting

**Symptom:** Railway shows the service in a restart loop.

**Cause:** Often an out-of-memory issue or a missing required environment variable.

**Fix:**

```bash
# Check logs for the specific error
railway logs

# Common fixes:
# 1. Ensure all required env vars are set
# 2. Increase memory in Railway dashboard (Settings → Resources)
# 3. Check that the volume is properly mounted
```

### Cannot access the domain

**Symptom:** Browser shows "site can't be reached" or times out.

**Cause:** Domain not generated, or service is not running.

**Fix:**

1. Run `railway status` to check if the service is active
2. Run `railway domain` to confirm a domain is assigned
3. Check the Railway dashboard for deployment status
4. Wait 1-2 minutes for DNS propagation if the domain was just created

---

## Teardown

To completely remove the OpenClaw deployment:

### Step 1: Stop the service

```bash
railway down
```

### Step 2: Delete the project

1. Open the Railway dashboard
2. Navigate to your project
3. Click **Settings**
4. Scroll to the bottom
5. Click **Delete Project**
6. Type the project name to confirm

> **Warning:** This permanently deletes the service, volume, and all data. Export any important data before proceeding. See the Backup section above.

### Alternative: Remove via CLI

```bash
# Remove the current deployment
railway down

# Unlink the local directory
railway unlink
```

Then delete the project from the Railway dashboard as described above.
