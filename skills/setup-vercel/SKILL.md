---
name: setup-vercel
description: Setup Vercel for a project. Use this skill when the user says "setup vercel", "set up vercel", "configure vercel", or "link to vercel".
author: "@mattwoodco"
version: 2.1.0
created: 2026-01-11
---

# Vercel Setup Process

Complete setup for deploying Next.js projects to Vercel with type-safe configuration.

## Setup Steps

### 1. Install Vercel CLI

```bash
bun add -g vercel
```

### 2. Authenticate

```bash
vercel login
```

Verify authentication:

```bash
vercel whoami
```

### 3. Link Project

```bash
vercel link --yes
```

This creates a `.vercel` directory with project configuration. The directory is automatically added to `.gitignore`.

### 4. Install Dependencies

```bash
bun add -D @vercel/config
```

### 5. Create vercel.ts Configuration

Create `vercel.ts` in the project root with type-safe configuration:

> **Note:** `analytics` and `speedInsights` are NOT part of the Vercel deployment config (`VercelConfig`). Enable them via the `@vercel/analytics` and `@vercel/speed-insights` packages in your Next.js layout instead.

```typescript
import type { VercelConfig } from '@vercel/config/v1'

const securityHeaders = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'X-XSS-Protection', value: '0' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
]

export const config: VercelConfig = {
  functions: {
    // Configure based on your API routes:
    // 'app/api/ai/route.ts': { maxDuration: 60, memory: 1024 },
    // 'app/api/stripe/webhook/route.ts': { maxDuration: 30 },
    // 'app/api/search/route.ts': { maxDuration: 10 },
  },

  headers: [
    { source: '/api/(.*)', headers: securityHeaders },
  ],

  rewrites: [
    // { source: '/sitemap.xml', destination: '/api/sitemap' },
  ],

  crons: [
    // { path: '/api/cron/cleanup', schedule: '0 3 * * *' },
  ],
}
```

### 5b. Enable Analytics & Speed Insights (optional)

Install the packages and add them to your root layout:

```bash
bun add @vercel/analytics @vercel/speed-insights
```

In `src/app/layout.tsx`:

```typescript
import { Analytics } from '@vercel/analytics/react'
import { SpeedInsights } from '@vercel/speed-insights/next'

// Add inside the <body> tag:
<Analytics />
<SpeedInsights />
```

### 6. Pull Environment Variables

Pull existing environment variables for local development:

```bash
vercel env pull .env.local
```

## Environment Variables

### Managing Variables

```bash
# List all variables
vercel env ls

# Add variable (interactive)
vercel env add MY_VAR

# Add to specific environment
vercel env add MY_VAR production
vercel env add MY_VAR preview
vercel env add MY_VAR development

# Remove variable
vercel env rm MY_VAR production

# Pull to local file
vercel env pull .env.local
```

### Environment Types

| Environment | Trigger | Usage |
|-------------|---------|-------|
| Production | `vercel --prod`, main branch | Live site |
| Preview | `vercel`, feature branches | Testing |
| Development | `vercel dev` | Local dev |

### Important Notes

- Use `NEXT_PUBLIC_` prefix for client-side variables
- Changes apply to **new deployments only**
- Max 64 KB total per deployment
- Never commit secrets to git

## Deployment Commands

```bash
# Preview deployment
vercel

# Production deployment
vercel --prod

# Local development with Vercel env vars
vercel dev
```

## Configuration Options

### Function Limits

```typescript
functions: {
  'app/api/heavy/route.ts': {
    memory: 1024,      // MB (128-3009)
    maxDuration: 60,   // seconds (depends on plan)
  },
}
```

### Headers

```typescript
headers: [
  {
    source: '/(.*)',
    headers: [
      { key: 'X-Frame-Options', value: 'DENY' },
    ],
  },
],
```

### Rewrites

```typescript
rewrites: [
  { source: '/api/v1/:path*', destination: '/api/:path*' },
  { source: '/blog/:slug', destination: '/posts/:slug' },
],
```

### Redirects

```typescript
redirects: [
  { source: '/old-page', destination: '/new-page', permanent: true },
],
```

### Cron Jobs

```typescript
crons: [
  { path: '/api/cron/daily', schedule: '0 0 * * *' },
  { path: '/api/cron/hourly', schedule: '0 * * * *' },
],
```

## CI/CD Variables

For automated deployments, set these in your CI environment:

| Variable | Description |
|----------|-------------|
| `VERCEL_TOKEN` | API token from account settings |
| `VERCEL_ORG_ID` | Found in `.vercel/project.json` |
| `VERCEL_PROJECT_ID` | Found in `.vercel/project.json` |

## CLI Reference

| Command | Description |
|---------|-------------|
| `vercel` | Deploy to preview |
| `vercel --prod` | Deploy to production |
| `vercel dev` | Local dev server |
| `vercel link` | Link to project |
| `vercel env pull` | Pull env vars |
| `vercel env ls` | List env vars |
| `vercel logs` | View logs |
| `vercel inspect <url>` | Inspect deployment |
| `vercel rollback` | Rollback deployment |
| `vercel promote` | Promote preview to production |

## Setup Checklist

- [ ] Vercel CLI installed (`bun add -g vercel`)
- [ ] Authenticated (`vercel login`)
- [ ] Project linked (`vercel link --yes`)
- [ ] `@vercel/config` installed
- [ ] `vercel.ts` created with configuration
- [ ] Environment variables configured
- [ ] `.vercel` in `.gitignore`
