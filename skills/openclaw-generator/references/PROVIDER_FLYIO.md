# OpenClaw Provider Reference: Fly.io

## Provider Overview

**Fly.io** is a container-based platform that deploys apps as Firecracker micro-VMs on a global edge network. Apps run in lightweight VMs (not shared containers), which gives strong isolation and predictable performance. Fly.io supports persistent volumes, private networking, and TLS termination out of the box.

Fly.io is a strong choice for OpenClaw because:

- Micro-VMs boot in under a second
- Persistent volumes keep state across deploys
- Built-in TLS/HTTPS on `*.fly.dev` domains
- Global regions let you deploy close to your users
- Simple CLI-driven workflow

---

## Prerequisites

| Requirement | Details |
|---|---|
| **flyctl CLI** | The Fly.io command-line tool. Installed in step 1 below. |
| **Fly.io account** | Sign up at [fly.io/app/sign-up](https://fly.io/app/sign-up). |
| **Credit card on file** | Required even for free-tier resources. Fly.io bills usage-based. |
| **API keys** | At least one model provider API key (e.g., `ANTHROPIC_API_KEY`). |

---

## Cost Estimate

| Resource | Monthly Cost |
|---|---|
| `shared-cpu-1x` VM (256 MB) | ~$3/month |
| `shared-cpu-1x` VM (512 MB, recommended) | ~$5/month |
| 1 GB persistent volume | ~$0.15/month |
| Outbound bandwidth (typical) | ~$0-2/month |
| **Total estimate** | **$5-15/month** |

> Fly.io bills per-second for compute. Costs stay low for a single always-on instance.

---

## Step-by-Step Deployment

### Step 1: Install flyctl

```bash
curl -L https://fly.io/install.sh | sh
```

After installation, add flyctl to your PATH if prompted:

```bash
export FLYCTL_INSTALL="/home/$USER/.fly"
export PATH="$FLYCTL_INSTALL/bin:$PATH"
```

Verify the installation:

```bash
fly version
```

### Step 2: Log in to Fly.io

```bash
fly auth login
```

This opens a browser window. Log in or create an account, then return to your terminal.

### Step 3: Create the Fly app

```bash
fly launch --name openclaw-USERNAME --region iad --no-deploy
```

Replace `USERNAME` with your actual username or a unique identifier.

- `--region iad` sets the primary region to Ashburn, Virginia (US East). Change to your nearest region if desired. Run `fly platform regions` to see all options.
- `--no-deploy` prevents an immediate deploy so you can configure volumes and secrets first.

This command creates a `fly.toml` file in your current directory. You will replace its contents in Step 5.

### Step 4: Create a persistent volume

```bash
fly volumes create openclaw_data --size 1 --region iad
```

- `--size 1` creates a 1 GB volume (sufficient for OpenClaw state and workspace data).
- The volume region **must match** the app region from Step 3.

Verify the volume was created:

```bash
fly volumes list
```

### Step 5: Configure fly.toml

Replace the contents of `fly.toml` with the following:

```toml
app = "openclaw-USERNAME"
primary_region = "iad"

[build]
  image = "node:22-slim"

[build.args]

[env]
  OPENCLAW_STATE_DIR = "/data/.openclaw"
  OPENCLAW_WORKSPACE_DIR = "/data/workspace"
  OPENCLAW_GATEWAY_BIND = "lan"
  PORT = "18789"

[mounts]
  source = "openclaw_data"
  destination = "/data"

[processes]
  app = "npx openclaw@latest gateway --port 18789 --bind lan"

[[services]]
  internal_port = 18789
  protocol = "tcp"
  auto_stop_machines = false
  auto_start_machines = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

  [[services.ports]]
    port = 80
    handlers = ["http"]

[checks]
  [checks.health]
    type = "http"
    port = 18789
    path = "/"
    interval = "30s"
    timeout = "5s"
    method = "GET"
```

> Replace `openclaw-USERNAME` with the app name from Step 3.

Alternatively, if you prefer a Dockerfile-based build, create a `Dockerfile` in the same directory:

```dockerfile
FROM node:22-slim

RUN npm install -g openclaw@latest

RUN mkdir -p /data/.openclaw /data/workspace

EXPOSE 18789

CMD ["openclaw", "gateway", "--port", "18789", "--bind", "lan"]
```

Then update the `[build]` section in `fly.toml`:

```toml
[build]
  dockerfile = "Dockerfile"
```

### Step 6: Set secrets

Generate a secure gateway token and set your secrets:

```bash
fly secrets set \
  OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)" \
  ANTHROPIC_API_KEY="sk-ant-your-key-here"
```

Add any additional model provider keys as needed:

```bash
fly secrets set OPENAI_API_KEY="sk-your-openai-key"
```

Verify secrets are set (values are hidden):

```bash
fly secrets list
```

### Step 7: Deploy

```bash
fly deploy
```

This builds and deploys the app. The first deploy takes 1-3 minutes. Watch the output for any errors.

If using the `npx` process approach (no Dockerfile), you may need to adjust the build. The Dockerfile approach is more reliable.

### Step 8: Verify the deployment

Check the app status:

```bash
fly status
```

You should see one machine in the `started` state.

Stream the logs to confirm OpenClaw is running:

```bash
fly logs
```

Look for output indicating the gateway is listening on port 18789.

### Step 9: Access the Control UI

Open the app in your browser:

```bash
fly open
```

This opens `https://openclaw-USERNAME.fly.dev` in your default browser. You should see the OpenClaw setup wizard or control panel.

If this is a fresh deployment, complete the onboarding wizard:

1. Set an admin password
2. Confirm or add API keys
3. Configure your first channel

---

## Validation Commands

Run these to confirm everything is working:

```bash
# Check app status and machine health
fly status

# SSH into the running machine for debugging
fly ssh console

# Inside the machine, check the data directory
ls -la /data/.openclaw
ls -la /data/workspace

# Check the health endpoint from your local machine
curl -s https://openclaw-USERNAME.fly.dev/

# Check logs for errors
fly logs --no-tail
```

---

## Troubleshooting

### Volume not attached

**Symptom:** App starts but state is lost on redeploy, or you see errors about missing directories.

**Cause:** The volume name in `fly.toml` does not match the volume created in Step 4.

**Fix:**

```bash
# List volumes to find the correct name
fly volumes list

# Ensure fly.toml [mounts] source matches exactly
# source = "openclaw_data"
```

### Port mismatch

**Symptom:** App deploys but returns 502 errors or connection refused.

**Cause:** The `internal_port` in `fly.toml` does not match the port OpenClaw is listening on.

**Fix:** Ensure all three values are consistent:

- `PORT` env var in `[env]`
- `internal_port` in `[[services]]`
- The `--port` flag in the CMD or process definition

They should all be `18789`.

### OOM on 256 MB VM

**Symptom:** Machine crashes or restarts repeatedly. Logs show `Out of memory` or `signal: killed`.

**Cause:** 256 MB is tight for Node.js + OpenClaw, especially under load.

**Fix:** Scale up the VM memory:

```bash
fly scale memory 512
```

For heavier workloads:

```bash
fly scale memory 1024
```

### Deploy fails with "no machines in group app"

**Symptom:** First deploy fails because no machines exist yet.

**Fix:**

```bash
fly machine destroy --force   # if a broken machine exists
fly deploy
```

### TLS certificate not provisioning

**Symptom:** Browser shows certificate error.

**Cause:** DNS propagation delay or Fly.io certificate issuance queue.

**Fix:** Wait 2-5 minutes and try again. Check certificate status:

```bash
fly certs list
fly certs show openclaw-USERNAME.fly.dev
```

---

## Teardown

To completely remove the OpenClaw deployment and stop all billing:

```bash
# Destroy the app (includes machines and certificates)
fly apps destroy openclaw-USERNAME

# Confirm by typing the app name when prompted
```

> **Warning:** This permanently deletes the app, all machines, and all attached volumes. Data on the volume is lost. Export any important data before running this command.

If you only want to stop the app temporarily without destroying it:

```bash
fly scale count 0
```

To restart it later:

```bash
fly scale count 1
```
