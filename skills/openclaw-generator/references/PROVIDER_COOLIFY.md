# OpenClaw on Coolify

## Provider Overview

**Coolify** is an open-source, self-hosted Platform-as-a-Service (PaaS). Think of it as your own private Heroku or Vercel that runs on any VPS you control. Coolify gives you a web dashboard to deploy, manage, and monitor applications — including OpenClaw — without needing to SSH into servers or write systemd service files.

Coolify handles container orchestration, automatic SSL certificates, environment variable management, persistent storage, and more. You deploy OpenClaw as a **Service** in Coolify, and it takes care of the rest.

There are two ways to use Coolify:

- **Self-hosted** (free) — Install Coolify on your own VPS (DigitalOcean, Hetzner, etc.)
- **Coolify Cloud** ($5/month) — Use Coolify's managed hosting at [coolify.io](https://coolify.io). You still need a VPS for the actual workloads, but Coolify Cloud manages the Coolify dashboard for you.

---

## Prerequisites

Before you begin, make sure you have:

- **A running Coolify instance** — Either self-hosted on a VPS or via Coolify Cloud. If you do not have Coolify yet, follow the [official installation guide](https://coolify.io/docs/installation).
- **A connected server in Coolify** — At least one server must be added to your Coolify dashboard (this can be the same server Coolify runs on, listed as "localhost").
- **An API key for your AI provider** — At minimum, an `ANTHROPIC_API_KEY`. You can also add keys for OpenAI, Google, etc.

---

## Cost Estimate

| Component | Monthly Cost |
|-----------|-------------|
| Coolify software | Free (self-hosted) or $5/month (Coolify Cloud) |
| VPS (minimum: 1 vCPU, 1 GB RAM) | $4-12/month depending on provider |
| **Total** | **$4-17/month** + AI API usage |

**VPS recommendations for running Coolify + OpenClaw together:**

| Provider | Plan | Cost |
|----------|------|------|
| Hetzner | CX22 (2 vCPU, 4 GB RAM) | ~$4.50/month |
| DigitalOcean | Basic Droplet (2 vCPU, 2 GB RAM) | $18/month |
| Vultr | Cloud Compute (1 vCPU, 2 GB RAM) | $12/month |

> **Tip:** Hetzner offers the best value for Coolify deployments. A CX22 instance can run both Coolify itself and OpenClaw comfortably.

---

## Step-by-Step Deployment

### Step 1: Access the Coolify Dashboard

Open your Coolify dashboard in the browser. This is typically at:

```
https://coolify.your-domain.com
```

Or if using Coolify Cloud, log in at [app.coolify.io](https://app.coolify.io).

### Step 2: Navigate to Services

In the left sidebar, click **Projects**. Select an existing project (or create a new one), then click on an environment (e.g., "Production").

Click the **+ New** button in the top right.

### Step 3: Search for OpenClaw

In the resource creation screen:

1. Select **Service** as the resource type
2. In the service catalog, search for **"OpenClaw"**
3. Click on the **OpenClaw** service template

> **Note:** If OpenClaw does not appear in the service catalog, use the Docker Compose method described in the "Alternative" section below.

### Step 4: Click Deploy (Initial Setup)

Coolify will show you the service configuration page. Before deploying, you need to configure a few things first (Steps 5-7). But if you want to see the defaults, you can review them here.

### Step 5: Configure Environment Variables

Click on the **Environment Variables** tab (or section) and add the following:

| Variable | Value | Required |
|----------|-------|----------|
| `OPENCLAW_GATEWAY_TOKEN` | A secure random token (see below) | Yes |
| `ANTHROPIC_API_KEY` | Your Anthropic API key (`sk-ant-api03-...`) | Yes |
| `OPENCLAW_STATE_DIR` | `/data/openclaw` | Yes |
| `OPENAI_API_KEY` | Your OpenAI API key (optional) | No |
| `GOOGLE_API_KEY` | Your Google API key (optional) | No |

**Generating a secure gateway token:**

On your local machine, run one of these commands to generate a random token:

```bash
# Option 1: Using openssl
openssl rand -hex 32

# Option 2: Using python
python3 -c "import secrets; print(secrets.token_hex(32))"

# Option 3: Using uuidgen
uuidgen | tr -d '-'
```

Copy the output and paste it as the value for `OPENCLAW_GATEWAY_TOKEN`. Save this token somewhere safe — you will need it to log into the Control UI.

### Step 6: Configure Persistent Storage

Click on the **Storages** or **Volumes** tab. Ensure a persistent volume is configured:

- **Volume name:** `openclaw-data`
- **Mount path in container:** `/data/openclaw`

This is critical. Without persistent storage, you will lose all OpenClaw configuration (including API keys, profiles, and MCP server settings) whenever the container restarts.

### Step 7: Set Port Mapping

Click on the **Network** tab. Configure the port:

- **Exposed port:** `18789`
- **Container port:** `18789`

If Coolify is configured with a reverse proxy (Traefik or Caddy), you can also set up a domain like `openclaw.your-domain.com` to proxy to this port. Coolify will automatically provision an SSL certificate.

### Step 8: Deploy

Click the **Deploy** button. Coolify will:

1. Pull the OpenClaw Docker image
2. Create the container with your environment variables
3. Mount the persistent volume
4. Start the gateway

Watch the deployment logs in Coolify's log viewer. The deployment typically takes 1-2 minutes.

### Step 9: Access Your OpenClaw Instance

Once the deployment shows as **Running** in the Coolify dashboard, access OpenClaw in your browser:

- **If using Coolify's reverse proxy with a domain:** `https://openclaw.your-domain.com`
- **If using the exposed port directly:** `http://YOUR_SERVER_IP:18789`

### Step 10: Complete Onboarding

In the OpenClaw Control UI:

1. Enter the `OPENCLAW_GATEWAY_TOKEN` you generated in Step 5
2. Walk through any remaining onboarding steps
3. Verify your API keys are detected
4. Optionally configure profiles, MCP servers, and other settings

**Congratulations!** Your OpenClaw gateway is running on Coolify.

---

## Alternative: Docker Compose Deployment in Coolify

If OpenClaw is not available in Coolify's service catalog, you can deploy it using a Docker Compose file.

### Step 1: Create a New Resource

In your Coolify project/environment, click **+ New** and select **Docker Compose**.

### Step 2: Enter the Compose Configuration

Choose **Empty Compose File** and paste the following:

```yaml
version: '3'
services:
  openclaw:
    image: openclaw:latest
    ports:
      - "18789:18789"
    volumes:
      - openclaw-data:/data/openclaw
    environment:
      OPENCLAW_STATE_DIR: /data/openclaw
      OPENCLAW_GATEWAY_TOKEN: ${OPENCLAW_GATEWAY_TOKEN}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://127.0.0.1:18789/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  openclaw-data:
```

### Step 3: Set Environment Variables

In the **Environment Variables** section, add:

```
OPENCLAW_GATEWAY_TOKEN=your-generated-token-here
ANTHROPIC_API_KEY=sk-ant-api03-your-key-here
```

### Step 4: Deploy

Click **Deploy**. Coolify will parse the Compose file, create the service, and start the container.

### Step 5: Configure Domain (Optional)

In the service settings, go to the **Network** tab and add a domain (e.g., `openclaw.your-domain.com`). Coolify will set up the reverse proxy and SSL automatically.

---

## Validation

### In the Coolify Dashboard

1. Navigate to your OpenClaw service
2. Check that the status shows **Running** (green indicator)
3. Click **Logs** to view the gateway output — look for a message like:
   ```
   OpenClaw gateway listening on 0.0.0.0:18789
   ```

### From the Command Line

If you have SSH access to the server running Coolify:

```bash
# Check the container is running
docker ps | grep openclaw

# View container logs
docker logs $(docker ps -q --filter "name=openclaw") --tail 50

# Test the health endpoint
curl -s http://127.0.0.1:18789/health
```

### From Your Browser

Open the Control UI URL and verify:

- The login page loads
- You can authenticate with your gateway token
- API keys show as configured in the Settings page

---

## Troubleshooting

### Service Shows as "Exited" or "Restarting"

Check the logs in the Coolify dashboard:

1. Click on your OpenClaw service
2. Click the **Logs** tab
3. Look for error messages

Common causes:

- **Missing environment variables** — Ensure `OPENCLAW_STATE_DIR` is set to `/data/openclaw`
- **Port conflict** — Another service may already be using port 18789. Change the exposed port to something else (e.g., `18790:18789`)
- **Image not found** — Make sure the image name is correct (`openclaw:latest`)

### Cannot Access the Control UI

- **Check the port mapping** — Ensure port 18789 is exposed in the service configuration.
- **Check the server firewall** — The VPS firewall must allow traffic on the exposed port:
  ```bash
  # If using ufw
  ufw allow 18789/tcp
  ```
- **Check Coolify's proxy** — If using a custom domain, ensure the proxy configuration is correct in the **Network** tab.

### Data Lost After Restart

This means persistent storage is not configured correctly.

1. Go to your OpenClaw service in Coolify
2. Check the **Storages** / **Volumes** tab
3. Ensure a volume is mapped to `/data/openclaw`
4. Redeploy the service

### Environment Variables Not Taking Effect

After changing environment variables in Coolify, you must **redeploy** the service for changes to take effect. Click the **Redeploy** button in the service dashboard.

### Coolify Cannot Pull the OpenClaw Image

If you see "image not found" errors:

1. Check that the image name and tag are correct
2. If using a private registry, configure the registry credentials in Coolify under **Settings → Docker Registries**
3. Try pulling the image manually on the server:
   ```bash
   docker pull openclaw:latest
   ```

---

## Updating OpenClaw

To update to the latest version of OpenClaw:

1. Go to your OpenClaw service in the Coolify dashboard
2. Click **Redeploy** — Coolify will pull the latest image and restart the container
3. Check the logs to confirm the new version is running

If you pinned a specific image tag (e.g., `openclaw:1.2.0`), update the tag in the service configuration first, then redeploy.

---

## Teardown

To completely remove OpenClaw from Coolify:

1. Go to your Coolify dashboard
2. Navigate to the project and environment containing your OpenClaw service
3. Click on the OpenClaw service
4. Click **Delete** (or the trash icon)
5. When prompted, choose whether to also **delete the persistent volume** (this removes all OpenClaw data)
6. Confirm the deletion

The container, network configuration, and (optionally) stored data will be removed. If you used a custom domain, the DNS records will need to be removed separately from your DNS provider.

> **Backup before deleting:** If you want to keep your configuration, SSH into the server and copy the volume data first:
> ```bash
> docker cp $(docker ps -aq --filter "name=openclaw"):/data/openclaw ./openclaw-backup/
> ```
