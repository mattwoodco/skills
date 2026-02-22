# OpenClaw -- Platform Overview & Reference

## What Is OpenClaw?

OpenClaw is a free, open-source, self-hosted AI agent platform (MIT license). It connects
your favorite chat apps (WhatsApp, Telegram, Discord, Slack, Teams, Signal, iMessage, Google Chat)
to AI models (Claude, GPT, Gemini, local via Ollama) through a single WebSocket-based Gateway.

- **Repository**: github.com/openclaw/openclaw
- **Website**: openclaw.ai
- **Docs**: docs.openclaw.ai
- **License**: MIT

## System Requirements

| Requirement | Details |
|-------------|---------|
| Node.js | 22+ (required; Bun unsupported for service mode) |
| OS | macOS 12+, Linux (systemd), Windows 10/11 via WSL2 |
| Disk | ~500MB install + space for sessions/workspace |
| Network | Outbound HTTPS for model providers, inbound port 18789 |
| API Key | At least one model provider (Anthropic recommended) |

## Architecture

```
Chat Apps (WhatsApp, Telegram, Discord, etc.)
        |
        v
   [ Gateway ]  <--- WebSocket-based control plane (port 18789)
        |
   +----+----+
   |    |    |
   v    v    v
 Agent  Browser  Plugins
 Skills  Control  Channels
```

The Gateway is the single process that:
- Bridges chat channels to AI agents
- Routes sessions and conversations
- Manages plugins and skills
- Controls a dedicated browser instance
- Exposes a web Control UI

## Installation (Quick Reference)

**Installer script (recommended):**
```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

**npm global install:**
```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

**Docker:**
```bash
git clone https://github.com/openclaw/openclaw.git && cd openclaw
./docker-setup.sh
```

## Core Environment Variables

### Path & Network

| Variable | Purpose | Default |
|----------|---------|---------|
| `OPENCLAW_STATE_DIR` | State directory | `~/.openclaw` |
| `OPENCLAW_CONFIG_PATH` | Config file path | `~/.openclaw/openclaw.json` |
| `OPENCLAW_GATEWAY_PORT` | WebSocket port | `18789` |
| `OPENCLAW_GATEWAY_BIND` | Network binding (`loopback`/`lan`/`tailnet`) | `loopback` |
| `OPENCLAW_GATEWAY_TOKEN` | Auth token | (none) |
| `OPENCLAW_NO_ONBOARD` | Skip onboarding | `false` |

### Model Provider API Keys

| Variable | Provider |
|----------|----------|
| `ANTHROPIC_API_KEY` | Anthropic (Claude) |
| `OPENAI_API_KEY` | OpenAI (GPT) |
| `GEMINI_API_KEY` | Google Gemini |
| `OPENROUTER_API_KEY` | OpenRouter |
| `XAI_API_KEY` | xAI (Grok) |
| `GROQ_API_KEY` | Groq |

### Channel Tokens

| Variable | Channel |
|----------|---------|
| `TELEGRAM_BOT_TOKEN` | Telegram |
| `DISCORD_BOT_TOKEN` | Discord |
| `SLACK_BOT_TOKEN` | Slack (xoxb-) |
| `SLACK_APP_TOKEN` | Slack (xapp-) |

## Configuration File

Located at `~/.openclaw/openclaw.json`. Minimal example:

```json
{
  "agent": {
    "model": "anthropic/claude-sonnet-4-6"
  },
  "gateway": {
    "port": 18789,
    "bind": "loopback",
    "auth": {
      "token": "your-secure-token"
    }
  }
}
```

## Network Binding Modes

| Mode | Listens | Auth Required | Use Case |
|------|---------|---------------|----------|
| `loopback` | 127.0.0.1 | Optional | Local use, SSH tunnel |
| `lan` | 0.0.0.0 | **Required** | Server/cloud deploy |
| `tailnet` | Tailscale IP | **Required** | Private mesh network |

**Important**: Cloud deployments MUST use `lan` binding with a strong auth token.

## Essential CLI Commands

```bash
# Setup & config
openclaw onboard --install-daemon    # Guided first-time setup
openclaw configure                    # Interactive config wizard
openclaw doctor --deep                # Health checks

# Gateway management
openclaw gateway install              # Create system service
openclaw gateway start                # Start service
openclaw gateway stop                 # Stop service
openclaw gateway restart              # Restart
openclaw gateway status --deep        # Full status check
openclaw gateway probe                # Test WebSocket

# Model management
openclaw models list --all            # List available models
openclaw models status --probe        # Live model status
openclaw models set <model-id>        # Set default model
openclaw models auth setup-token --provider anthropic

# Channel management
openclaw channels list                # Show channels
openclaw channels add                 # Add channel wizard
openclaw channels login               # Login (WhatsApp Web, etc.)
openclaw channels status --probe      # Channel health

# Diagnostics
openclaw status --deep --usage        # Full system status
openclaw health --json                # System health JSON
openclaw logs --follow                # Tail logs

# Security
openclaw security audit --deep        # Security audit
```

## Post-Deploy Verification Checklist

Run these commands after any deployment to confirm success:

```bash
openclaw gateway status               # Service running?
openclaw gateway probe                # WebSocket reachable?
openclaw status                       # Config valid?
openclaw health --json                # System health
openclaw models status --probe        # Model auth valid?
openclaw channels status --probe      # Channels connected? (if configured)
```

Expected healthy probe response: `"ok (XXXms)"`

## Supported AI Providers (20+)

Anthropic, OpenAI, Google Gemini, Google Vertex, OpenRouter, xAI (Grok), Groq,
Cerebras, Mistral, GitHub Copilot, Hugging Face, Vercel AI Gateway, Ollama (local),
vLLM (local), LM Studio (local), and more via custom provider config.

## Security Notes

- Always set a strong `OPENCLAW_GATEWAY_TOKEN` for any non-loopback deployment
- DM pairing is enabled by default (unknown senders get pairing codes)
- The project is explicitly **not enterprise-ready** as of February 2026
- Run `openclaw security audit --deep` after deployment
- Consider Tailscale for private network access instead of public binding
