# OpenClaw Provider Reference: Render

## Provider Overview

**Render** is a zero-config cloud platform that builds and deploys web services directly from Git repositories. Render supports Docker-based deployments, persistent disks, managed TLS, and Infrastructure-as-Code through `render.yaml` blueprint files.

Render is a strong choice for OpenClaw because:

- Blueprint files (`render.yaml`) define the entire infrastructure declaratively
- Automatic builds and deploys on Git push
- Persistent disks for state storage
- Free TLS on `*.onrender.com` domains
- Simple dashboard for environment variable management
- No CLI required (everything works through Git + dashboard)

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Render account** | Sign up at [render.com](https://render.com). |
| **GitHub or GitLab account** | Required for connecting your repository. |
| **Git** | Installed locally for pushing code. |
| **API keys** | At least one model provider API key (e.g., `ANTHROPIC_API_KEY`). |

---

## Cost Estimate

| Resource | Monthly Cost |
|---|---|
| Starter instance (512 MB RAM, 0.5 CPU) | $7/month |
| Persistent disk (1 GB) | ~$0.25/month |
| Bandwidth (100 GB included) | $0 (typical usage) |
| **Total estimate** | **$7-25/month** |

> Render's free tier does **not** support persistent disks and has aggressive cold starts (service spins down after 15 minutes of inactivity). For OpenClaw, the **Starter plan or higher** is strongly recommended to ensure the gateway stays available and state persists.

---

## Step-by-Step Deployment

### Step 1: Create a project directory and initialize Git

```bash
mkdir openclaw-render && cd openclaw-render
git init
```

### Step 2: Create render.yaml

Create a `render.yaml` file in the project root. This blueprint file tells Render exactly how to deploy your service:

```yaml
services:
  - type: web
    name: openclaw
    runtime: docker
    plan: starter
    region: oregon
    healthCheckPath: /
    disk:
      name: openclaw-data
      mountPath: /data
      sizeGB: 1
    envVars:
      - key: OPENCLAW_STATE_DIR
        value: /data/.openclaw
      - key: OPENCLAW_WORKSPACE_DIR
        value: /data/workspace
      - key: OPENCLAW_GATEWAY_BIND
        value: lan
      - key: PORT
        value: "18789"
      - key: OPENCLAW_GATEWAY_TOKEN
        generateValue: true
      - key: SETUP_PASSWORD
        generateValue: true
```

Key details:

- **`plan: starter`** - The minimum plan that supports persistent disks. Do not use `free` for OpenClaw.
- **`region: oregon`** - Render's default region. Options include `oregon`, `ohio`, `virginia`, `frankfurt`, `singapore`.
- **`disk`** - Creates a 1 GB persistent disk mounted at `/data`. This survives deploys and restarts.
- **`generateValue: true`** - Render automatically generates a random value for these secrets on first deploy.
- **`healthCheckPath: /`** - Render will check this endpoint to determine if the service is healthy.

### Step 3: Create the Dockerfile

Create a `Dockerfile` in the same directory:

```dockerfile
FROM node:22-slim

# Install openclaw globally
RUN npm install -g openclaw@latest

# Create data directories for persistent storage
RUN mkdir -p /data/.openclaw /data/workspace

# Set working directory
WORKDIR /data/workspace

# Expose the gateway port
EXPOSE 18789

# Start the OpenClaw gateway
CMD ["openclaw", "gateway", "--port", "18789", "--bind", "lan"]
```

### Step 4: Create a .gitignore

Create a `.gitignore` to keep the repo clean:

```
node_modules/
.env
*.log
```

### Step 5: Commit and push to GitHub

```bash
git add .
git commit -m "Initial OpenClaw deployment configuration"
```

Create a new repository on GitHub (via the GitHub UI or CLI):

```bash
gh repo create openclaw-render --private --source=. --push
```

Or manually:

```bash
git remote add origin https://github.com/YOUR-USERNAME/openclaw-render.git
git branch -M main
git push -u origin main
```

### Step 6: Deploy with Render Blueprint

1. Go to [dashboard.render.com](https://dashboard.render.com)
2. Click **New** in the top navigation
3. Select **Blueprint**
4. Connect your GitHub/GitLab account if not already connected
5. Search for and select your `openclaw-render` repository
6. Render auto-detects the `render.yaml` file and shows the planned resources
7. Review the configuration and click **Apply**

Render will:

- Build the Docker image from your Dockerfile
- Create the persistent disk
- Generate random values for `OPENCLAW_GATEWAY_TOKEN` and `SETUP_PASSWORD`
- Deploy the service
- Provision a TLS certificate for the `.onrender.com` domain

The first deploy takes 3-7 minutes.

### Step 7: Set model API keys

The `render.yaml` blueprint does not include API keys for security reasons. Add them manually:

1. In the Render dashboard, click on your **openclaw** service
2. Go to the **Environment** tab
3. Click **Add Environment Variable**
4. Add your model provider keys:

| Key | Value |
|---|---|
| `ANTHROPIC_API_KEY` | `sk-ant-your-key-here` |
| `OPENAI_API_KEY` | `sk-your-openai-key` (optional) |

5. Click **Save Changes**

Render automatically redeploys the service when environment variables change.

### Step 8: Access your OpenClaw instance

Your service is available at:

```
https://openclaw-XXXX.onrender.com
```

Find the exact URL in the Render dashboard under your service's **Settings** tab, or at the top of the service page.

**Setup wizard:**

```
https://openclaw-XXXX.onrender.com/setup
```

Complete the onboarding wizard:

1. Set an admin password
2. Confirm or add API keys
3. Configure your first channel

**Control UI:**

```
https://openclaw-XXXX.onrender.com/openclaw
```

---

## Validation

### From the Render dashboard

1. Go to your service in the Render dashboard
2. Click the **Logs** tab to view real-time logs
3. The **Events** tab shows deploy history and status changes

### From the command line

```bash
# Check the health endpoint
curl -s https://openclaw-XXXX.onrender.com/

# Check with authentication
curl -s -H "Authorization: Bearer YOUR_GATEWAY_TOKEN" \
  https://openclaw-XXXX.onrender.com/api/status

# Continuous log monitoring (using Render CLI if installed)
# Note: Render CLI is optional. Most operations happen through the dashboard.
```

### Expected healthy response

A successful health check returns an HTTP 200 status. The gateway logs should show:

```
OpenClaw gateway listening on 0.0.0.0:18789
```

---

## Troubleshooting

### Cold starts on Starter plan

**Symptom:** First request after a period of inactivity takes 10-30 seconds.

**Cause:** Render's Starter plan may spin down the service after inactivity, though this is less aggressive than the free tier.

**Fix:**

- Upgrade to the **Standard plan** ($25/month) for always-on instances
- Set up an external health check (e.g., UptimeRobot) to ping your service every 5 minutes and keep it warm
- Add the health check path in `render.yaml` (already included in the config above)

### Disk persistence issues

**Symptom:** Data is lost after a deploy. Configuration resets.

**Cause:** The disk is not properly configured, or the mount path does not match the environment variables.

**Fix:**

1. In the Render dashboard, go to your service's **Disks** tab
2. Verify the disk exists and shows the correct mount path (`/data`)
3. Confirm environment variables match:
   - `OPENCLAW_STATE_DIR` = `/data/.openclaw`
   - `OPENCLAW_WORKSPACE_DIR` = `/data/workspace`
4. Redeploy after fixing

> **Important:** Render persistent disks survive deploys and restarts, but they are deleted if you delete the service. Always export your data before deleting.

### Deploy fails: "Build failed"

**Symptom:** Render shows a failed build in the Events tab.

**Cause:** Usually a Dockerfile syntax error or a network issue during `npm install`.

**Fix:**

1. Check the build logs in the Render dashboard (Events tab → click the failed deploy)
2. Test the Dockerfile locally:

```bash
docker build -t openclaw-test .
docker run -p 18789:18789 openclaw-test
```

3. Common issues:
   - Typo in Dockerfile
   - `npm install` timeout (retry the deploy)
   - Base image not available (check `node:22-slim` exists)

### Port mismatch: "Service failed to bind to $PORT"

**Symptom:** Deploy succeeds but the service immediately crashes with a port error.

**Cause:** Render expects the service to bind to the port specified in the `PORT` environment variable. If the Dockerfile CMD uses a different port, the health check fails and Render kills the service.

**Fix:** Ensure consistency across all three locations:

- `PORT` env var in `render.yaml` = `18789`
- `EXPOSE` in Dockerfile = `18789`
- `--port` in Dockerfile CMD = `18789`

### Service shows "Deploy failed" repeatedly

**Symptom:** Every deploy fails and the service never comes online.

**Fix:**

1. Check the deploy logs for the specific error message
2. Verify all required environment variables are set
3. Try a manual deploy: In the Render dashboard, click **Manual Deploy** → **Deploy latest commit**
4. If the disk is corrupted, delete and recreate it in the dashboard

---

## Updating OpenClaw

To update to the latest version of OpenClaw:

1. No code changes needed if your Dockerfile uses `openclaw@latest`
2. In the Render dashboard, click **Manual Deploy** → **Clear build cache & deploy**
3. This forces a fresh `npm install` that pulls the latest version

Alternatively, push any commit to your repo:

```bash
git commit --allow-empty -m "Trigger redeploy for OpenClaw update"
git push
```

---

## Teardown

To completely remove the OpenClaw deployment:

1. **Export your data first** (optional but recommended):
   - Visit `https://openclaw-XXXX.onrender.com/setup/export`
   - Download the export file

2. **Delete the service:**
   - Go to the Render dashboard
   - Click on your **openclaw** service
   - Go to the **Settings** tab
   - Scroll to the bottom
   - Click **Delete Web Service**
   - Type the service name to confirm

> **Warning:** Deleting the service also deletes the attached persistent disk and all data on it. This action is irreversible.

3. **Clean up the Git repo** (optional):

```bash
gh repo delete openclaw-render --yes
```

Or delete the repository from the GitHub UI.
