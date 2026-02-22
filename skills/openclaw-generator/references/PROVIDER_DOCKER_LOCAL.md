# OpenClaw on Docker (Local)

## Provider Overview

**Docker** lets you run OpenClaw in a container on your own machine — your laptop, desktop, or any computer you control. This is the simplest and most cost-effective deployment option because there is no cloud server to pay for. OpenClaw runs locally, your data stays on your machine, and you only pay for AI API usage.

Docker containers provide isolation and reproducibility. OpenClaw runs in its own sandboxed environment with all dependencies included, so it will not conflict with anything else on your system.

This guide covers three approaches, from simplest to most customizable:

1. **Quick Start** — Clone the repo and run the setup script (recommended for most users)
2. **Manual Docker Compose** — Write your own Compose file for full control
3. **Standalone Container** — Run a single `docker run` command

---

## Prerequisites

Before you begin, make sure you have:

- **Docker Desktop** (macOS/Windows) or **Docker Engine + Docker Compose v2** (Linux)
- **An API key for your AI provider** — At minimum, an `ANTHROPIC_API_KEY`

### Installing Docker

**macOS:**
1. Download [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/)
2. Open the `.dmg` file and drag Docker to Applications
3. Launch Docker Desktop and wait for the whale icon to appear in the menu bar

**Windows:**
1. Download [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/)
2. Run the installer
3. Restart your computer if prompted
4. Launch Docker Desktop

**Linux (Ubuntu/Debian):**
```bash
# Install Docker Engine
curl -fsSL https://get.docker.com | sh

# Add your user to the docker group (avoids needing sudo)
sudo usermod -aG docker $USER

# Log out and back in for the group change to take effect
# Then verify:
docker --version
docker compose version
```

### Verify Docker is Working

```bash
docker --version
# Expected: Docker version 24.x or later

docker compose version
# Expected: Docker Compose version v2.x or later

docker run hello-world
# Expected: "Hello from Docker!" message
```

---

## Cost Estimate

| Resource | Cost |
|----------|------|
| Docker | Free (Docker Desktop is free for personal use) |
| Server costs | $0 (runs on your own machine) |
| AI API usage | Pay-per-use (varies by provider) |
| **Total** | **Free** + AI API usage |

---

## Quick Start (Recommended)

This is the fastest way to get OpenClaw running locally.

### Step 1: Clone the Repository

```bash
git clone https://github.com/openclaw/openclaw.git && cd openclaw
```

### Step 2: Run the Setup Script

```bash
./docker-setup.sh
```

This script does everything for you:

1. Builds the OpenClaw Docker image from source
2. Launches the interactive onboarding wizard
3. Asks you to set a gateway auth token
4. Asks for your AI provider API keys
5. Starts the gateway container

Follow the on-screen prompts. The entire process takes about 3-5 minutes.

### Step 3: Access the Control UI

Once the setup script finishes, open your browser and go to:

```
http://127.0.0.1:18789/
```

You will see the OpenClaw Control UI.

### Step 4: Log In

Click **Settings** and enter the auth token that was displayed during setup. If you did not save it, you can find it in the configuration:

```bash
docker exec openclaw cat /data/openclaw/openclaw.json | grep authToken
```

### Step 5: Verify

The Control UI should show:

- Gateway status: **Running**
- Your configured API keys listed under Settings
- No errors in the status page

**Congratulations!** OpenClaw is running locally in Docker.

---

## Manual Docker Compose

Use this method if you want full control over the configuration, or if you prefer not to clone the repo.

### Step 1: Create a Project Directory

```bash
mkdir openclaw && cd openclaw
```

### Step 2: Create the Docker Compose File

Create a file named `docker-compose.yml` with the following contents:

```yaml
version: '3'
services:
  openclaw:
    image: openclaw:latest
    container_name: openclaw
    ports:
      - "18789:18789"
    volumes:
      - openclaw-data:/data/openclaw
    environment:
      OPENCLAW_STATE_DIR: /data/openclaw
      OPENCLAW_GATEWAY_BIND: loopback
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://127.0.0.1:18789/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  openclaw-data:
```

> **About `OPENCLAW_GATEWAY_BIND: loopback`** — This ensures OpenClaw only listens on 127.0.0.1 (localhost). Since Docker maps the port, you can still access it from the host machine, but it will not be accessible from the network. This is the most secure option for local development.

### Step 3: Build the Image

If you have the source code (cloned in Step 1 of the Quick Start), build the image:

```bash
docker build -t openclaw:latest -f Dockerfile .
```

If you do not have the source, pull the pre-built image (if available):

```bash
docker pull openclaw:latest
```

### Step 4: Run the Onboarding Wizard

Before starting the gateway, run the onboarding wizard to set up your configuration:

```bash
docker compose run --rm openclaw onboard
```

This interactive wizard will:

- Ask you to accept the terms of service
- Generate or set a gateway auth token
- Ask for your AI provider API keys
- Write the configuration to the persistent volume

### Step 5: Start the Gateway

```bash
docker compose up -d
```

The `-d` flag runs the container in the background (detached mode).

### Step 6: Verify

Check that the container is running:

```bash
docker compose ps
```

Expected output:

```
NAME       IMAGE             COMMAND                  SERVICE    CREATED         STATUS                   PORTS
openclaw   openclaw:latest   "openclaw gateway run"   openclaw   5 seconds ago   Up 4 seconds (healthy)   0.0.0.0:18789->18789/tcp
```

View the logs:

```bash
docker compose logs -f
```

Press `Ctrl+C` to stop following the logs.

Open the Control UI:

```
http://127.0.0.1:18789/
```

---

## Standalone Container

If you prefer a single `docker run` command without Docker Compose:

```bash
docker run -d \
  --name openclaw \
  -p 18789:18789 \
  -v ~/.openclaw:/data/openclaw \
  -e OPENCLAW_STATE_DIR=/data/openclaw \
  openclaw:latest
```

**What this command does:**

| Flag | Purpose |
|------|---------|
| `-d` | Run in the background (detached) |
| `--name openclaw` | Name the container "openclaw" for easy reference |
| `-p 18789:18789` | Map host port 18789 to container port 18789 |
| `-v ~/.openclaw:/data/openclaw` | Bind-mount your local `~/.openclaw` directory into the container for persistent data |
| `-e OPENCLAW_STATE_DIR=/data/openclaw` | Tell OpenClaw where to store its data |

> **Note:** This uses a bind mount (`~/.openclaw`) instead of a Docker volume. This makes it easy to inspect and edit configuration files directly on your host machine.

To run the onboarding wizard with the standalone container:

```bash
docker exec -it openclaw openclaw onboard
```

---

## Optional Environment Variables

These optional variables customize the Docker container behavior:

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_STATE_DIR` | `/data/openclaw` | Directory inside the container where OpenClaw stores configuration, profiles, and state |
| `OPENCLAW_GATEWAY_BIND` | `loopback` | Network binding: `loopback` (127.0.0.1 only) or `lan` (0.0.0.0, all interfaces) |
| `OPENCLAW_DOCKER_APT_PACKAGES` | (none) | Space-separated list of additional apt packages to install in the container on startup. Example: `OPENCLAW_DOCKER_APT_PACKAGES="git vim curl"` |
| `OPENCLAW_EXTRA_MOUNTS` | (none) | Additional volume mounts for the container. Useful for giving OpenClaw access to local project directories |
| `OPENCLAW_HOME_VOLUME` | (none) | Custom path for the home directory volume inside the container |

### Example: Adding Extra Packages and Mounts

```yaml
version: '3'
services:
  openclaw:
    image: openclaw:latest
    container_name: openclaw
    ports:
      - "18789:18789"
    volumes:
      - openclaw-data:/data/openclaw
      - ~/projects:/home/node/projects:ro
    environment:
      OPENCLAW_STATE_DIR: /data/openclaw
      OPENCLAW_GATEWAY_BIND: loopback
      OPENCLAW_DOCKER_APT_PACKAGES: "git ripgrep fd-find"
    restart: unless-stopped

volumes:
  openclaw-data:
```

This mounts your local `~/projects` directory as read-only inside the container and installs `git`, `ripgrep`, and `fd-find`.

---

## Security

The OpenClaw Docker image follows container security best practices:

- **Runs as non-root user** — The container process runs as the `node` user (UID 1000), not root. This limits the damage if the container is compromised.
- **Loopback binding by default** — With `OPENCLAW_GATEWAY_BIND=loopback`, OpenClaw only accepts connections from inside the container. Docker's port mapping makes it accessible from the host, but not from the network.
- **No privileged mode** — The container does not require `--privileged` or elevated capabilities.

### Recommendations

- **Do not expose port 18789 to the network** unless you intentionally want remote access. The default Docker Compose configuration only binds to `127.0.0.1` via port mapping.
- **If you need remote access**, consider using Tailscale, WireGuard, or an SSH tunnel instead of opening the port directly.
- **Keep API keys in environment variables** — Never bake API keys into the Docker image. Use environment variables or `.env` files (and add `.env` to your `.gitignore`).

---

## Validation

Run these commands to confirm everything is working:

### Check the Container Status

```bash
docker compose ps
```

You should see the `openclaw` container with status `Up` and `(healthy)`.

### View Logs

```bash
docker compose logs --tail 50
```

Look for:
- `OpenClaw gateway listening on ...` — confirms the gateway started
- No error messages or stack traces

### Test the Health Endpoint

```bash
curl -s http://127.0.0.1:18789/health
```

You should get a JSON response indicating the gateway is healthy.

### Test from the Browser

Open `http://127.0.0.1:18789/` and verify the Control UI loads.

---

## Troubleshooting

### Permission Errors with Bind Mounts

If you see errors like `EACCES: permission denied` when using bind mounts (the standalone container method with `-v ~/.openclaw:/data/openclaw`):

```bash
# Fix ownership on the host directory
sudo chown -R 1000:1000 ~/.openclaw
```

The container runs as UID 1000 (`node` user), so the host directory must be writable by that UID.

Alternatively, use Docker volumes instead of bind mounts (as shown in the Docker Compose method). Docker volumes handle permissions automatically.

### Port 18789 Already in Use

If you see `Bind for 0.0.0.0:18789 failed: port is already allocated`:

```bash
# Find what is using the port
lsof -i :18789
# or on Linux:
ss -tlnp | grep 18789
```

Options:
- Stop the other process using the port
- Change the host port mapping to a different port:
  ```yaml
  ports:
    - "18790:18789"  # Access via http://127.0.0.1:18790
  ```

### Container Keeps Restarting

Check the logs for the error:

```bash
docker compose logs --tail 100
```

Common causes:
- **Missing configuration** — Run the onboarding wizard: `docker compose run --rm openclaw onboard`
- **Corrupt state directory** — Remove the volume and start fresh: `docker compose down -v && docker compose up -d`
- **Out of disk space** — Check with `docker system df` and clean up with `docker system prune`

### Cannot Connect to Control UI

1. **Verify the container is running:** `docker compose ps`
2. **Check the port mapping:** `docker port openclaw`
3. **Test with curl:** `curl http://127.0.0.1:18789/`
4. **Check Docker Desktop** (macOS/Windows) — Ensure Docker Desktop is running (whale icon in the menu bar/system tray)

### Image Build Fails

If `docker build` fails:

```bash
# Clean the Docker build cache
docker builder prune

# Retry the build with no cache
docker build --no-cache -t openclaw:latest -f Dockerfile .
```

### Container Uses Too Much Memory

By default, Docker Desktop allocates limited memory to containers. If OpenClaw is slow or crashing:

**Docker Desktop (macOS/Windows):**
1. Open Docker Desktop → Settings → Resources
2. Increase Memory to at least 2 GB
3. Click Apply & Restart

**Docker Engine (Linux):**
Add memory limits to the Compose file if you want to constrain usage:

```yaml
services:
  openclaw:
    # ... other settings ...
    deploy:
      resources:
        limits:
          memory: 1G
```

---

## Managing the Container

### Stop the Gateway

```bash
docker compose stop
```

This stops the container but keeps it and its data. Start it again with `docker compose start`.

### Restart the Gateway

```bash
docker compose restart
```

### View Real-Time Logs

```bash
docker compose logs -f
```

Press `Ctrl+C` to stop following.

### Enter the Container Shell

To inspect or debug inside the container:

```bash
docker exec -it openclaw /bin/bash
```

You will be logged in as the `node` user. Type `exit` to leave.

### Update to the Latest Version

```bash
# Pull the latest image
docker compose pull

# Recreate the container with the new image
docker compose up -d
```

Your data is preserved in the Docker volume across updates.

---

## Teardown

To completely remove OpenClaw and all its data:

```bash
# Stop and remove the container, network, AND volumes
docker compose down -v
```

The `-v` flag removes the named volumes (including `openclaw-data`), which deletes all OpenClaw configuration and state.

To remove only the container but **keep your data**:

```bash
docker compose down
```

The `openclaw-data` volume will remain and can be reused when you start OpenClaw again.

To also remove the Docker image:

```bash
docker rmi openclaw:latest
```

### Backup Before Teardown

If you want to save your configuration before removing everything:

```bash
# Copy data from the volume to your host
docker cp openclaw:/data/openclaw ./openclaw-backup/
```

Or if using bind mounts, your data is already at `~/.openclaw/` on the host.
