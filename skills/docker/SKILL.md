---
name: docker
description: Setup Docker Compose local development stack with Postgres, Redis, S3 (RustFS), Mailpit, Meilisearch, Ollama, and Jaeger. Use this skill when the user says "setup docker", "docker compose", "start containers", or "docker local dev".
author: "@mattwoodco"
version: 2.1.2
created: 2026-01-11
updated: 2026-02-13
validated: 2026-02-13
---

# Docker Local Development Stack

Sets up a production-ready local development environment using Docker Compose with health checks, named volumes, and proper service configuration.

## Services Included

| Service | Port | Web UI | Purpose |
|---------|------|--------|---------|
| Postgres 16 + pgvector | 5432 | - | Primary database |
| Redis 7 | 6379 | - | Cache & session store |
| RustFS | 9000, 9001 | http://localhost:9001 | S3-compatible storage |
| Mailpit | 1025, 8025 | http://localhost:8025 | Email testing |
| Meilisearch | 7700 | http://localhost:7700 | Full-text search |
| Ollama | 11434 | - | Local LLM inference |
| Jaeger | 16686, 4318 | http://localhost:16686 | Distributed tracing |

## Setup Steps

### 1. Create docker-compose.yml

Create `docker-compose.yml` in the project root:

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-password}
      POSTGRES_DB: ${POSTGRES_DB:-appdb}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "${POSTGRES_USER:-app}"]
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 60s
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 15s
    restart: unless-stopped

  s3:
    image: rustfs/rustfs:latest
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      RUSTFS_ROOT_USER: ${S3_ACCESS_KEY:-rustfsadmin}
      RUSTFS_ROOT_PASSWORD: ${S3_SECRET_KEY:-rustfsadmin}
      RUSTFS_ACCESS_KEY: ${S3_ACCESS_KEY:-rustfsadmin}
      RUSTFS_SECRET_KEY: ${S3_SECRET_KEY:-rustfsadmin}
    volumes:
      - s3_data:/data
    command: server /data --console-address ":9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3
      start_period: 30s
    restart: unless-stopped

  mailpit:
    image: axllent/mailpit:latest
    ports:
      - "1025:1025"
      - "8025:8025"
    environment:
      MP_SMTP_AUTH_ACCEPT_ANY: "true"
      MP_SMTP_AUTH_ALLOW_INSECURE: "true"
    restart: unless-stopped

  meilisearch:
    image: getmeili/meilisearch:v1.10
    ports:
      - "7700:7700"
    environment:
      MEILI_MASTER_KEY: ${MEILI_MASTER_KEY:-masterkey}
      MEILI_NO_ANALYTICS: "true"
      MEILI_ENV: development
    volumes:
      - meilisearch_data:/meili_data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7700/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    environment:
      OLLAMA_HOST: 0.0.0.0
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped
    # Uncomment for GPU support (NVIDIA)
    # deploy:
    #   resources:
    #     reservations:
    #       devices:
    #         - driver: nvidia
    #           count: all
    #           capabilities: [gpu]

  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"  # UI
      - "4318:4318"     # OTLP HTTP
    environment:
      COLLECTOR_OTLP_ENABLED: "true"
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
  s3_data:
  meilisearch_data:
  ollama_data:
```

### 2. Create .env for Docker Compose

Docker Compose reads variable substitutions from `.env` in the project root (**not** `.env.local`). Create a `.env` file so `docker-compose.yml` can resolve `${VAR:-default}` references:

```env
# Docker Compose variable substitution
POSTGRES_USER=app
POSTGRES_PASSWORD=password
POSTGRES_DB=appdb
S3_ACCESS_KEY=rustfsadmin
S3_SECRET_KEY=rustfsadmin
MEILI_MASTER_KEY=masterkey
```

> **Note:** The defaults in `docker-compose.yml` match these values, so this file is technically optional. But creating it avoids "variable is not set" warnings and makes overrides explicit.

### 3. Create .env.local for the App

Add Docker-specific environment variables to `.env.local` (read by Next.js):

```env
# Database
POSTGRES_USER=app
POSTGRES_PASSWORD=password
POSTGRES_DB=appdb
DATABASE_URL=postgresql://app:password@localhost:5432/appdb

# Redis
REDIS_URL=redis://localhost:6379

# S3 Storage (RustFS)
S3_ENDPOINT=http://localhost:9000
S3_ACCESS_KEY=rustfsadmin
S3_SECRET_KEY=rustfsadmin
S3_BUCKET=uploads
S3_REGION=us-east-1

# Search
MEILI_MASTER_KEY=masterkey
MEILI_URL=http://localhost:7700

# Email
SMTP_HOST=localhost
SMTP_PORT=1025
SMTP_SECURE=false

# AI (Ollama)
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=llama3.2
AI_PROVIDER=ollama

# Observability (Jaeger)
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

### 4. Start Services

```bash
docker compose up -d
```

## Health Check Best Practices

Health checks ensure services are ready before dependent services start:

- **Postgres**: Uses `pg_isready` with 60s start period for initialization
- **Redis**: Uses `redis-cli ping` with 15s start period
- **RustFS (S3)**: Uses MinIO-compatible health endpoint
- **Meilisearch**: Uses HTTP health endpoint

Use `depends_on` with `condition: service_healthy` when adding an app service:

```yaml
app:
  depends_on:
    postgres:
      condition: service_healthy
    redis:
      condition: service_healthy
```

## Volume Management

- **Named volumes** persist data across restarts
- `docker compose down` preserves volumes
- `docker compose down -v` deletes volumes (data loss!)
- Never use `-v` unless you want to reset data

## Commands Reference

| Command | Description |
|---------|-------------|
| `docker compose up -d` | Start all services |
| `docker compose down` | Stop services (keep data) |
| `docker compose down -v` | Stop and delete all data |
| `docker compose logs -f` | Follow all logs |
| `docker compose logs -f postgres` | Follow specific service |
| `docker compose ps` | List running services |
| `docker compose restart redis` | Restart specific service |

## Service URLs

After starting, access services at:

- **Postgres**: `postgresql://app:password@localhost:5432/appdb`
- **Redis**: `redis://localhost:6379`
- **S3 API**: `http://localhost:9000`
- **S3 Console**: http://localhost:9001 (login: rustfsadmin/rustfsadmin)
- **Mailpit UI**: http://localhost:8025
- **Meilisearch**: http://localhost:7700
- **Ollama API**: http://localhost:11434
- **Jaeger UI**: http://localhost:16686

## Ollama Setup

After starting Ollama, pull models:

```bash
# Pull popular models
docker exec -it $(docker compose ps -q ollama) ollama pull llama3.2
docker exec -it $(docker compose ps -q ollama) ollama pull mistral
docker exec -it $(docker compose ps -q ollama) ollama pull nomic-embed-text

# List available models
docker exec -it $(docker compose ps -q ollama) ollama list

# Test a model
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.2",
  "prompt": "Hello!",
  "stream": false
}'
```

### GPU Support (NVIDIA)

For GPU acceleration, uncomment the `deploy` section in the Ollama service and ensure:

1. NVIDIA drivers are installed
2. NVIDIA Container Toolkit is installed:
   ```bash
   # Ubuntu/Debian
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
   curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
     sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
     sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
   sudo systemctl restart docker
   ```

### macOS with Apple Silicon

On macOS with Apple Silicon, Ollama automatically uses Metal for GPU acceleration. No additional configuration needed.

## Troubleshooting

**Docker daemon not running?**
```bash
# Check if Docker is running
docker ps

# Start Docker Desktop, OrbStack, or Colima
# macOS: open -a Docker
# OrbStack: orbstack start
# Colima: colima start
```

**Service won't start?**
```bash
docker compose logs <service-name>
```

**Port already in use?**
```bash
lsof -i :<port>
```

**Reset a specific service:**
```bash
docker compose rm -sf <service-name>
docker volume rm <project>_<volume-name>
docker compose up -d <service-name>
```

## Validation Notes

This skill has been validated with the following outcomes:

1. **docker-compose.yml creation**: Successfully generates all services with correct configuration
2. **Health checks**: Properly configured for Postgres, Redis, Meilisearch, and Ollama
3. **Volume management**: Named volumes correctly defined for data persistence
4. **Environment variable compatibility**: Works with env-config skill defaults
5. **Port mappings**: All services use standard ports (Postgres 5432, Redis 6379, Mailpit 1025/8025, etc.)

**Testing requirements**: Docker daemon must be running (Docker Desktop, OrbStack, or Colima)
