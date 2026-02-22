---
name: env-config
description: Setup environment configuration with type-safe validation and local development defaults. Use this skill when the user says "setup env", "configure environment", "env vars", or "environment setup".
author: "@mattwoodco"
version: 1.3.0
created: 2026-01-11
updated: 2026-02-19
validated: 2026-02-13
---

# Environment Configuration Setup

Creates a type-safe environment configuration system using `@t3-oss/env-nextjs` with Zod validation, plus a `.env.local` template for local development.

## Installation

```bash
bun add @t3-oss/env-nextjs zod
```

## What Gets Created

### `env.ts` or `src/env.ts`

Create this file with type-safe environment variable validation:

- **With src directory** (Next.js with `--src-dir`): `src/env.ts`
- **Without src directory** (Next.js with `--no-src-dir`): `env.ts` in project root

Check your project structure first:

```bash
# If you have a src directory, use src/env.ts
ls src/ 2>/dev/null && echo "Use src/env.ts" || echo "Use env.ts"
```

```typescript
import { createEnv } from "@t3-oss/env-nextjs";
import { z } from "zod";

export const env = createEnv({
  server: {
    // --- Core (always required) ---
    DATABASE_URL: z.string().url(),
    BETTER_AUTH_SECRET: z.string().min(1),

    // --- Infrastructure (optional — add based on project needs) ---
    REDIS_URL: z.string().url().optional(),
    S3_ENDPOINT: z.string().url().optional(),
    S3_ACCESS_KEY: z.string().optional(),
    S3_SECRET_KEY: z.string().optional(),
    S3_REGION: z.string().default("us-east-1"),
    S3_BUCKET: z.string().optional(),
    BLOB_READ_WRITE_TOKEN: z.string().optional(),
    SMTP_HOST: z.string().optional(),
    SMTP_PORT: z.string().optional(),
    RESEND_API_KEY: z.string().optional(),
    MEILI_URL: z.string().url().optional(),
    MEILI_MASTER_KEY: z.string().optional(),

    // --- Payments (optional — add if using Stripe) ---
    STRIPE_SECRET_KEY: z.string().optional(),
    STRIPE_WEBHOOK_SECRET: z.string().optional(),

    // --- AI Services (optional — add based on providers used) ---
    OPENAI_API_KEY: z.string().optional(),
    FAL_KEY: z.string().optional(),
    REPLICATE_API_TOKEN: z.string().optional(),
    AI_GATEWAY_API_KEY: z.string().optional(),
    AI_GATEWAY_MODEL: z.string().default("google/gemini-2.5-flash-lite"),
    EXA_API_KEY: z.string().optional(),

    // --- Queue (optional — Inngest defaults for local dev) ---
    INNGEST_EVENT_KEY: z.string().default("local"),
    INNGEST_SIGNING_KEY: z.string().default("local"),
  },
  client: {
    NEXT_PUBLIC_APP_URL: z.string().url(),
    NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY: z.string().optional(),
  },
  runtimeEnv: {
    DATABASE_URL: process.env.DATABASE_URL,
    BETTER_AUTH_SECRET: process.env.BETTER_AUTH_SECRET,
    REDIS_URL: process.env.REDIS_URL,
    S3_ENDPOINT: process.env.S3_ENDPOINT,
    S3_ACCESS_KEY: process.env.S3_ACCESS_KEY,
    S3_SECRET_KEY: process.env.S3_SECRET_KEY,
    S3_REGION: process.env.S3_REGION,
    S3_BUCKET: process.env.S3_BUCKET,
    BLOB_READ_WRITE_TOKEN: process.env.BLOB_READ_WRITE_TOKEN,
    SMTP_HOST: process.env.SMTP_HOST,
    SMTP_PORT: process.env.SMTP_PORT,
    RESEND_API_KEY: process.env.RESEND_API_KEY,
    MEILI_URL: process.env.MEILI_URL,
    MEILI_MASTER_KEY: process.env.MEILI_MASTER_KEY,
    STRIPE_SECRET_KEY: process.env.STRIPE_SECRET_KEY,
    STRIPE_WEBHOOK_SECRET: process.env.STRIPE_WEBHOOK_SECRET,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
    FAL_KEY: process.env.FAL_KEY,
    REPLICATE_API_TOKEN: process.env.REPLICATE_API_TOKEN,
    AI_GATEWAY_API_KEY: process.env.AI_GATEWAY_API_KEY,
    AI_GATEWAY_MODEL: process.env.AI_GATEWAY_MODEL,
    EXA_API_KEY: process.env.EXA_API_KEY,
    INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
    INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
    NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
    NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY:
      process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY,
  },
});
```

**Features:**

- Type-safe environment variable validation at build time
- Separates server-only and client-safe variables
- Descriptive error messages for missing variables
- Works with local Docker stack by default
- Supports production services (Neon, Upstash, Vercel Blob, Resend, etc.)

### `.env.local.example` (canonical reference)

Local development defaults pre-configured for Docker services.
**This file is the source of truth** — the reconciliation step above uses it to fill gaps in `.env.local`.

```env
# --- Core (always required) ---
DATABASE_URL=postgresql://app:password@localhost:5432/appdb
BETTER_AUTH_SECRET=dev-secret-change-in-production

# Application
NEXT_PUBLIC_APP_URL=http://localhost:3000

# --- Infrastructure (uncomment as needed) ---
REDIS_URL=redis://localhost:6379

# Storage (S3-compatible local)
S3_ENDPOINT=http://localhost:9000
S3_ACCESS_KEY=rustfsadmin
S3_SECRET_KEY=rustfsadmin
S3_BUCKET=uploads

# Email (Mailpit local)
SMTP_HOST=localhost
SMTP_PORT=1025

# Search (Meilisearch)
MEILI_URL=http://localhost:7700
MEILI_MASTER_KEY=devMasterKey123

# --- Payments (optional — add if using Stripe) ---
# STRIPE_SECRET_KEY=sk_test_...
# STRIPE_WEBHOOK_SECRET=whsec_test_...
# NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...

# --- AI Services (load from 1Password in production) ---
# OPENAI_API_KEY=sk-...
# FAL_KEY=
# REPLICATE_API_TOKEN=
# AI_GATEWAY_API_KEY=
# EXA_API_KEY=
```

## What This Does

1. Creates `env.ts` (or `src/env.ts` if using src directory) with validated environment variables
2. Creates `.env.local.example` as the canonical reference for all env vars with defaults
3. **Reconciles `.env.local`** — appends any missing keys from `.env.local.example` (preserves existing values like 1Password secrets)
4. All services point to Docker stack by default
5. Provides clear error messages for missing required vars
6. Enables type-safe `import { env } from "@/env"` throughout the app (works with both `--src-dir` and `--no-src-dir` via tsconfig paths)

## Reconcile `.env.local` (CRITICAL)

**This step prevents missing env var errors in CI and local dev.**

After creating `env.ts` and `.env.local.example`, run this reconciliation:

```bash
# If .env.local exists (e.g., from 1Password dump), append missing keys from .env.local.example.
# If .env.local doesn't exist, copy the example as the starting point.
if [[ -f .env.local ]]; then
  echo "Reconciling .env.local against .env.local.example..."
  ADDED=0
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    # Skip commented-out vars (lines starting with "# KEY=")
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # Extract key name (everything before first =)
    KEY="${line%%=*}"
    # Append if key is missing from .env.local
    if ! grep -q "^${KEY}=" .env.local 2>/dev/null; then
      echo "$line" >> .env.local
      ADDED=$((ADDED + 1))
    fi
  done < .env.local.example
  echo "Added $ADDED missing keys to .env.local"
else
  cp .env.local.example .env.local
  echo "Created .env.local from .env.local.example"
fi
```

**Why this matters:**

- add-project Phase 4 dumps 1Password → `.env.local` with secrets (API keys, tokens)
- 1Password typically doesn't include infrastructure defaults (`REDIS_URL`, `STORAGE_*`, `SMTP_*`)
- Without reconciliation, `.env.local` is incomplete and tests/build fail
- This step fills gaps with safe defaults while preserving real secrets

## Import Path Configuration

Both project structures use the same import path thanks to TypeScript path mapping:

```typescript
// In any file (API routes, components, etc.)
import { env } from "@/env";
```

**With `--src-dir`**: `@/env` resolves to `src/env.ts`
**With `--no-src-dir`**: `@/env` resolves to `env.ts` (tsconfig.json should have `"@/*": ["./*"]`)

This ensures consistent imports regardless of project structure.

## Next Steps

1. Generate a production auth secret:

   ```bash
   openssl rand -base64 32
   ```

2. **Load external service API keys from 1Password** (recommended):
   - Use the `/env-from-1password` skill to automatically load:
     - `FAL_KEY`
     - `REPLICATE_API_TOKEN`
     - `AI_GATEWAY_API_KEY`
     - `EXA_API_KEY`
     - `BLOB_READ_WRITE_TOKEN`
     - `RESEND_API_KEY`
   - Alternatively, manually copy keys from 1Password to `.env.local`
3. Start containers: `docker compose up -d`
4. Run migrations: `bun run db:migrate`

## Local Development vs Production

The configuration automatically handles:

- **Local**: Uses `DATABASE_URL`, `REDIS_URL`, S3/SMTP from Docker
- **Production**: Uses `UPSTASH_REDIS_REST_URL`, `BLOB_READ_WRITE_TOKEN`, Resend, etc.
- **Dev/Preview**: Intermediate configuration via environment detection
