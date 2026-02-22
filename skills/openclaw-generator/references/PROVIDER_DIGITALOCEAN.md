# OpenClaw on DigitalOcean

## Provider Overview

**DigitalOcean** is a developer-friendly cloud platform known for simple pricing, an intuitive dashboard, and a 1-Click Marketplace that lets you spin up pre-configured applications in minutes. It is an excellent choice for running OpenClaw because you get a dedicated server with predictable monthly costs and no surprise bills.

DigitalOcean calls its virtual machines **Droplets**. You will create one Droplet to run your OpenClaw gateway.

---

## Prerequisites

Before you begin, make sure you have:

- **A DigitalOcean account** — Sign up at [cloud.digitalocean.com](https://cloud.digitalocean.com/registrations/new). New accounts often receive free credits.
- **An SSH key pair** — You need this to securely log into your Droplet. If you do not have one, generate it on your local machine:
  ```bash
  ssh-keygen -t ed25519 -C "your-email@example.com"
  ```
  Then add the public key (`~/.ssh/id_ed25519.pub`) to your DigitalOcean account under **Settings → Security → SSH Keys**.
- **An API key for your AI provider** — At minimum, an `ANTHROPIC_API_KEY`. You can also add keys for OpenAI, Google, etc.

---

## Cost Estimate

| Resource | Monthly Cost |
|----------|-------------|
| Basic Droplet (1 vCPU, 1 GB RAM, 25 GB disk) | $12/month |
| Regular Droplet (1 vCPU, 2 GB RAM, 50 GB disk) | $18/month |
| Regular Droplet (2 vCPU, 2 GB RAM, 60 GB disk) | $24/month |

**Recommendation:** Start with the **$12/month** plan. OpenClaw is lightweight and runs comfortably on 1 GB of RAM. You can resize later if needed.

> **Note:** These costs are for the server only. You will also pay your AI provider (Anthropic, OpenAI, etc.) separately based on token usage.

---

## Path A: 1-Click Marketplace (Easiest)

This is the fastest way to get OpenClaw running. The Marketplace image comes pre-installed with OpenClaw, all dependencies, and a setup wizard.

### Step 1: Visit the DigitalOcean Marketplace

Go to the OpenClaw listing on the DigitalOcean Marketplace:

```
https://marketplace.digitalocean.com/apps/openclaw
```

### Step 2: Click "Create OpenClaw Droplet"

Click the blue **Create OpenClaw Droplet** button. This takes you to the Droplet creation page with the OpenClaw image pre-selected.

### Step 3: Choose a Plan

Select the **$12/month** plan:

- **1 vCPU**
- **1 GB RAM**
- **25 GB SSD disk**

This is sufficient for personal use and small teams.

### Step 4: Select a Region

Choose the datacenter region **closest to you** for the lowest latency. For example:

- US users → **New York (NYC1)** or **San Francisco (SFO3)**
- EU users → **Frankfurt (FRA1)** or **Amsterdam (AMS3)**
- Asia users → **Singapore (SGP1)** or **Bangalore (BLR1)**

### Step 5: Add Your SSH Key

Under **Authentication**, select **SSH Key** and choose the key you added to your account. If you have not added one yet, click **New SSH Key** and paste your public key.

> **Important:** Do not use password authentication. SSH keys are far more secure.

### Step 6: Create the Droplet

Optionally give your Droplet a hostname like `openclaw-gateway`, then click **Create Droplet**. Wait 30-60 seconds for it to provision.

Once ready, copy the **IP address** shown in the dashboard.

### Step 7: SSH into Your Droplet

Open a terminal on your local machine and connect:

```bash
ssh root@YOUR_DROPLET_IP
```

Replace `YOUR_DROPLET_IP` with the actual IP address (e.g., `164.90.154.72`).

### Step 8: Run the Setup Wizard

On the 1-Click image, the setup wizard **starts automatically** on your first login. It will walk you through:

- Accepting the terms of service
- Choosing a gateway auth token (or generating one)
- Selecting which AI providers to configure

Follow the on-screen prompts.

### Step 9: Set Your API Keys

When the wizard asks for API keys, enter them:

```
Enter your Anthropic API key: sk-ant-api03-xxxxxxxxxxxxx
```

You can also add keys for other providers (OpenAI, Google, etc.) or skip them for now and add them later.

### Step 10: Access the Control UI

Once the wizard completes, OpenClaw is running. Open your browser and go to:

```
http://YOUR_DROPLET_IP:18789
```

You will see the OpenClaw Control UI. Enter your auth token to log in and complete any remaining onboarding steps.

**Congratulations!** Your OpenClaw gateway is live.

---

## Path B: Manual Installation

If you prefer to install OpenClaw yourself, or the 1-Click image is not available in your region, follow these steps.

### Step 1: Create an Ubuntu Droplet

In the DigitalOcean dashboard:

1. Click **Create → Droplets**
2. Choose **Ubuntu 22.04 (LTS) x64** as the image
3. Select the **$12/month** plan (1 vCPU, 1 GB RAM, 25 GB disk)
4. Pick your preferred region
5. Add your SSH key
6. Click **Create Droplet**

### Step 2: SSH into Your Droplet

```bash
ssh root@YOUR_DROPLET_IP
```

### Step 3: Update the System

Bring the system packages up to date:

```bash
apt update && apt upgrade -y
```

This may take a minute or two. If prompted about restarting services, press Enter to accept defaults.

### Step 4: Install OpenClaw

Run the official installer script:

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

This downloads and installs the OpenClaw CLI and all required dependencies. The process typically takes 2-3 minutes.

### Step 5: Configure Network Binding

By default, OpenClaw only listens on localhost (127.0.0.1). Since you are accessing it remotely, you need to change the bind setting to allow LAN connections.

Edit the configuration file:

```bash
nano ~/.openclaw/openclaw.json
```

Find the `gateway` section and change the `bind` value:

```json
{
  "gateway": {
    "bind": "lan"
  }
}
```

Save and exit (`Ctrl+O`, then `Ctrl+X` in nano).

> **What does "lan" mean?** It binds to `0.0.0.0`, allowing connections from any IP. You will use a firewall (Step 10) to restrict access.

### Step 6: Set Your Auth Token

Run the configure command to set your gateway auth token:

```bash
openclaw configure
```

Follow the prompts to set a secure token. Alternatively, edit the config directly:

```bash
nano ~/.openclaw/openclaw.json
```

And set the `authToken` field under `gateway`.

### Step 7: Set Your API Keys

Create an environment file for your API keys:

```bash
nano ~/.openclaw/.env
```

Add your keys:

```bash
ANTHROPIC_API_KEY=sk-ant-api03-your-key-here
# Optional: add more providers
# OPENAI_API_KEY=sk-your-openai-key-here
# GOOGLE_API_KEY=your-google-key-here
```

Save and exit.

### Step 8: Install as a System Service

This ensures OpenClaw starts automatically when the Droplet reboots:

```bash
openclaw gateway install
```

This creates a systemd service file so the gateway runs in the background and survives reboots.

### Step 9: Start the Gateway

```bash
openclaw gateway start
```

You should see output confirming the gateway is running on port 18789.

### Step 10: Configure the Firewall

Lock down your Droplet so only SSH and OpenClaw traffic are allowed:

```bash
# Allow SSH (so you don't lock yourself out!)
ufw allow 22/tcp

# Allow OpenClaw
ufw allow 18789/tcp

# Enable the firewall
ufw enable
```

When prompted to proceed, type `y` and press Enter.

Verify the firewall rules:

```bash
ufw status
```

Expected output:

```
Status: active

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere
18789/tcp                  ALLOW       Anywhere
22/tcp (v6)                ALLOW       Anywhere (v6)
18789/tcp (v6)             ALLOW       Anywhere (v6)
```

### Step 11: Verify the Installation

Run a deep health check:

```bash
openclaw gateway status --deep
```

This checks the gateway process, port binding, configuration, and API key validity. All checks should show green/passing.

Then open your browser and go to:

```
http://YOUR_DROPLET_IP:18789
```

---

## Updating OpenClaw

### On the 1-Click Image

The 1-Click image includes a pre-built update script:

```bash
/opt/update-openclaw.sh
```

This script:
1. Stops the gateway
2. Downloads the latest version
3. Restarts the gateway
4. Verifies the update

### On Manual Installations

```bash
openclaw gateway stop
curl -fsSL https://openclaw.ai/install.sh | bash
openclaw gateway start
openclaw gateway status --deep
```

---

## Security Hardening

Your OpenClaw gateway is exposed to the internet by default. Here are three ways to improve security, from simplest to most secure.

### Option 1: Restrict Firewall by IP

If you have a static IP address, restrict OpenClaw access to only your IP:

```bash
# Remove the open rule
ufw delete allow 18789/tcp

# Allow only your IP
ufw allow from YOUR_HOME_IP to any port 18789 proto tcp
```

Replace `YOUR_HOME_IP` with your actual public IP (find it at [whatismyip.com](https://whatismyip.com)).

### Option 2: Use Tailscale (Recommended)

Tailscale creates a private network between your devices. No ports need to be open to the public internet.

On your Droplet:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
```

On your local machine, also install Tailscale and join the same network.

Then update your OpenClaw config to bind only to the Tailscale interface, and remove the public firewall rule:

```bash
ufw delete allow 18789/tcp
```

Access OpenClaw via your Droplet's Tailscale IP (e.g., `http://100.x.y.z:18789`).

### Option 3: SSH Tunnel

Use an SSH tunnel to access OpenClaw without opening port 18789 at all:

```bash
# On your local machine
ssh -L 18789:localhost:18789 root@YOUR_DROPLET_IP
```

Then access OpenClaw at `http://127.0.0.1:18789` on your local machine. The traffic is encrypted through the SSH tunnel.

With this approach, you can remove the public firewall rule entirely:

```bash
# On the Droplet
ufw delete allow 18789/tcp
```

And change the OpenClaw bind setting back to `"loopback"` in `~/.openclaw/openclaw.json`.

---

## Validation Commands

Run these commands on the Droplet to confirm everything is working:

```bash
# Check the gateway is running
openclaw gateway status

# Deep health check (process, port, config, API keys)
openclaw gateway status --deep

# Check the systemd service
systemctl status openclaw-gateway

# View recent logs
journalctl -u openclaw-gateway --no-pager -n 50

# Test the HTTP endpoint from the Droplet itself
curl -s http://127.0.0.1:18789/health
```

From your **local machine**, test remote access:

```bash
curl -s http://YOUR_DROPLET_IP:18789/health
```

---

## Troubleshooting

### Cannot SSH into the Droplet

- **Check the IP address** — Make sure you are using the correct IP from the DigitalOcean dashboard.
- **Check your SSH key** — Ensure the key you added to DigitalOcean matches the one on your local machine (`~/.ssh/id_ed25519` or `~/.ssh/id_rsa`).
- **Try verbose mode:** `ssh -v root@YOUR_DROPLET_IP`

### Gateway Fails to Start

```bash
# Check logs for error messages
journalctl -u openclaw-gateway --no-pager -n 100

# Check if the port is already in use
ss -tlnp | grep 18789

# Try starting manually to see errors in real time
openclaw gateway run
```

### Cannot Access Control UI in Browser

- **Check the firewall:** `ufw status` — Port 18789 must be ALLOWed.
- **Check the bind setting** — Must be `"lan"` in `~/.openclaw/openclaw.json`, not `"loopback"`.
- **Check the gateway is running:** `openclaw gateway status`
- **Try from the Droplet itself:** `curl http://127.0.0.1:18789` — If this works but the browser does not, it is a firewall or bind issue.

### API Keys Not Working

```bash
# Verify keys are loaded
openclaw gateway status --deep

# Check the .env file exists and is readable
cat ~/.openclaw/.env

# Re-enter keys
openclaw configure
```

### Out of Memory (on $12/month plan)

If the gateway crashes due to OOM (Out of Memory), add swap space:

```bash
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

Or resize your Droplet to the $18/month plan (2 GB RAM) via the DigitalOcean dashboard.

---

## Teardown

To completely remove your OpenClaw deployment and stop all charges:

1. Go to the [DigitalOcean dashboard](https://cloud.digitalocean.com/droplets)
2. Click on your OpenClaw Droplet
3. In the left sidebar, click **Destroy**
4. Click **Destroy this Droplet**
5. Confirm by clicking **Confirm**

> **Warning:** This permanently deletes the Droplet and all data on it. If you want to keep your OpenClaw configuration, SSH in first and copy `~/.openclaw/` to your local machine:
> ```bash
> scp -r root@YOUR_DROPLET_IP:~/.openclaw/ ./openclaw-backup/
> ```

Once the Droplet is destroyed, billing stops immediately.
