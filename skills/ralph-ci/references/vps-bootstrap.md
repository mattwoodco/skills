# VPS Bootstrap Guide

Complete guide for running Ralph CI on a VPS (Hetzner, DigitalOcean, or any Ubuntu 22.04+ server).

---

## Quick Start

```bash
# 1. SSH into your VPS
ssh root@your-server-ip

# 2. Create a non-root user (if needed)
adduser ralph
usermod -aG sudo ralph
su - ralph

# 3. Clone your project
git clone https://github.com/you/your-project.git
cd your-project

# 4. Run bootstrap
bash harness/vps/bootstrap.sh

# 5. Set your API key
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc
source ~/.bashrc

# 6. Start Ralph loops
pm2 start harness/vps/ecosystem.config.cjs

# 7. Monitor
pm2 logs
pm2 monit
```

---

## Recommended VPS Providers + Sizing

### Hetzner Cloud (Best value)

| Loops | Plan | vCPU | RAM | Storage | Cost |
|-------|------|------|-----|---------|------|
| 1-2 | CX22 | 2 | 4 GB | 40 GB | ~$6/mo |
| 3-5 | CPX31 | 8 | 16 GB | 160 GB | ~$28/mo |
| 6-12 | CPX51 | 16 | 32 GB | 320 GB | ~$49/mo |

**Recommended**: CPX31 for most projects. Shared vCPU is fine — Ralph is I/O bound (waiting for API responses), not CPU bound.

### DigitalOcean

| Loops | Plan | vCPU | RAM | Storage | Cost |
|-------|------|------|-----|---------|------|
| 1-2 | Basic | 2 | 4 GB | 80 GB | ~$24/mo |
| 3-5 | CPU-Optimized | 8 | 16 GB | 100 GB | ~$84/mo |
| 6-12 | CPU-Optimized | 16 | 32 GB | 200 GB | ~$168/mo |

### Sizing Rule of Thumb

Each concurrent Ralph loop needs:
- **CPU**: ~2 vCPU (chromium is the biggest consumer)
- **RAM**: ~3 GB (1 GB node + 1.5 GB chromium + 0.5 GB overhead)
- **Disk**: ~5 GB per project (node_modules + .next build artifacts)

Formula: `vCPU = loops × 2`, `RAM = loops × 3 + 2 GB (system)`

---

## What Bootstrap Installs

The `harness/vps/bootstrap.sh` script is idempotent — safe to re-run.

| Component | Version | Why |
|-----------|---------|-----|
| Node.js | 20.x | Claude Code runtime, npm packages |
| Bun | latest | Fast package manager, test runner |
| Claude Code | latest | AI agent CLI |
| PM2 | latest | Process manager for loop supervision |
| Chromium | system | Headless browser for playwright-cli |
| Playwright deps | matching chromium | Browser automation libraries |
| jq | system | JSON parsing in harness scripts |
| bc | system | Floating-point math for budget tracking |
| UFW | system | Firewall (SSH + outbound only) |
| unattended-upgrades | system | Auto security patches |
| logrotate | system | Log file rotation for ralph logs |

---

## Security Configuration

### Firewall (UFW)

Bootstrap configures UFW with:
- **Deny** all incoming (except SSH)
- **Allow** all outgoing (needed for API calls, git, npm)
- **Allow** SSH (port 22)

```bash
# Check status
sudo ufw status

# Add custom rules (e.g., for monitoring dashboard)
sudo ufw allow 3000/tcp  # Next.js dev server
sudo ufw allow 9090/tcp  # PM2 web UI
```

### API Key Security

**Never store API keys in files on disk.** Use environment variables:

```bash
# Option A: bashrc (persistent, user-scoped)
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc

# Option B: systemd environment file (for systemd service)
sudo tee /etc/ralph-env > /dev/null << EOF
ANTHROPIC_API_KEY=sk-ant-...
EOF
sudo chmod 600 /etc/ralph-env

# Option C: PM2 ecosystem env (loaded at process start)
# Already configured in ecosystem.config.cjs — set ANTHROPIC_API_KEY in environment
```

### SSH Hardening (Recommended)

```bash
# Disable password auth (key-only)
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Add your SSH key
mkdir -p ~/.ssh
echo "your-public-key" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## PM2 Management

### Common Commands

```bash
# Start all loops
pm2 start harness/vps/ecosystem.config.cjs

# Stop all loops
pm2 stop all

# Restart all loops
pm2 restart all

# Stop specific loop
pm2 stop ralph-loop-1

# View logs (all loops)
pm2 logs

# View logs (specific loop)
pm2 logs ralph-loop-1

# Real-time monitoring
pm2 monit

# Status overview
pm2 status

# Flush logs
pm2 flush
```

### PM2 as systemd Service

Bootstrap configures PM2 to start on boot:

```bash
# Generate startup script (done by bootstrap)
pm2 startup systemd -u $USER --hp $HOME

# Save current process list (run after starting loops)
pm2 save

# Verify it will start on boot
systemctl status pm2-$USER
```

### Updating Loop Count

Edit `ralph.config.json` to change `concurrency`, then restart PM2:

```bash
# Edit concurrency in ralph.config.json
jq '.concurrency = 5' ralph.config.json > tmp.json && mv tmp.json ralph.config.json

# Restart PM2 to pick up changes
pm2 delete all
pm2 start harness/vps/ecosystem.config.cjs
pm2 save
```

---

## Chrome Zombie Cleanup

Headless chromium processes can leak when playwright-cli crashes or times out.
Three layers of protection:

### Layer 1: EXIT trap in run.sh

```bash
# Runs on every exit (success or failure)
cleanup() {
  pkill -f "chromium.*--headless" 2>/dev/null || true
  pkill -f "chrome.*--headless" 2>/dev/null || true
}
trap cleanup EXIT
```

### Layer 2: cleanup.sh cron (every 15 min)

Bootstrap installs a cron job:

```
*/15 * * * * /path/to/harness/vps/cleanup.sh
```

Only kills chrome processes **older than 30 minutes** (avoids killing active sessions).

### Layer 3: Manual cleanup

```bash
# Check for zombie processes
ps aux | grep -i chrom | grep -v grep

# Kill all headless chrome
pkill -f "chromium.*--headless"
pkill -f "chrome.*--headless"

# Nuclear option — kill ALL chromium
killall -9 chromium-browser 2>/dev/null
killall -9 chrome 2>/dev/null
```

---

## Log Management

### Log Locations

| Log | Path | Rotation |
|-----|------|----------|
| Harness iteration logs | `.ralph/logs/loop_{ID}_iter_{N}.log` | Kept last N per loop (configurable via `logRetention`) |
| PM2 stdout | `.ralph/logs/pm2_loop_{ID}_out.log` | PM2 built-in rotation |
| PM2 stderr | `.ralph/logs/pm2_loop_{ID}_error.log` | PM2 built-in rotation |
| Report snapshot | `.ralph/report_{ID}.json` | Overwritten each iteration, per loop |
| Report history | `.ralph/report_history_{ID}.jsonl` | Append-only per loop (grows over time) |
| Harness state | `.ralph/.harness_state_{ID}` | Persisted per loop for crash recovery |

### Logrotate

Bootstrap installs a logrotate config at `/etc/logrotate.d/ralph`:

```
/home/*/projects/*/.ralph/logs/*.log {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
}
```

### Manual Log Cleanup

```bash
# Delete all logs older than 7 days
find .ralph/logs -name "*.log" -mtime +7 -delete

# Truncate history files (keep last 100 entries per loop)
for f in .ralph/report_history_*.jsonl; do
  tail -100 "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
done

# View cost trend (all loops)
cat .ralph/report_history_*.jsonl | jq -r '[.timestamp, .loop_id, .total_cost_usd, .plan_progress] | @tsv'
```

---

## Monitoring

### PM2 Web Dashboard

```bash
# Install PM2 web UI
pm2 install pm2-server-monit

# Or use PM2 Plus (free tier)
pm2 plus
```

### Custom Health Check Endpoint

If your project has a Next.js dev server running, add a health check:

```bash
# Check dev server is responding
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health
```

### Webhook Monitoring

Configure `ralph.config.json` webhook for real-time alerts:

```json
{
  "webhook": {
    "url": "https://hooks.slack.com/services/T.../B.../xxx",
    "events": ["failure", "success", "stalled", "circuit_breaker"]
  }
}
```

---

## Troubleshooting

### Ralph loops not starting

```bash
# Check PM2 status
pm2 status

# Check PM2 logs for errors
pm2 logs --err

# Verify ANTHROPIC_API_KEY is set
echo $ANTHROPIC_API_KEY | head -c 10

# Verify claude is installed
which claude
claude --version

# Test run.sh directly
RALPH_ENABLED=true bash harness/run.sh
```

### Out of memory

```bash
# Check memory usage
free -h

# Check per-process memory
pm2 monit

# Reduce concurrency
jq '.concurrency = 2' ralph.config.json > tmp.json && mv tmp.json ralph.config.json
pm2 delete all && pm2 start harness/vps/ecosystem.config.cjs

# Kill zombie chrome
bash harness/vps/cleanup.sh
```

### Disk full

```bash
# Check disk usage
df -h

# Find large files
du -sh .ralph/logs/ node_modules/ .next/

# Clean logs
find .ralph/logs -name "*.log" -mtime +3 -delete
pm2 flush

# Clean build cache
rm -rf .next/cache
```

### Permission errors

```bash
# Ensure harness scripts are executable
chmod +x harness/*.sh harness/vps/*.sh

# Ensure .ralph directory is writable
chmod -R u+w .ralph/
```

### Network errors (API timeouts)

```bash
# Test connectivity
curl -s https://api.anthropic.com/v1/messages -o /dev/null -w "%{http_code}"

# Check DNS
dig api.anthropic.com

# If behind a proxy
export HTTPS_PROXY=http://proxy:port
```

---

## Updating

### Update Claude Code

```bash
npm update -g @anthropic-ai/claude-code
```

### Update PM2

```bash
npm update -g pm2
pm2 update
```

### Update Bootstrap

Re-run bootstrap — it's idempotent:

```bash
bash harness/vps/bootstrap.sh
```

### Update Harness Scripts

Pull latest from git and restart PM2:

```bash
git pull origin main
pm2 restart all
```
