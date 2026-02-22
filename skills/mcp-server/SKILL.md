---
name: mcp-server
description: Deploy a remote MCP (Model Context Protocol) server with OAuth 2.1 authentication. Agents connect via Streamable HTTP, authenticate with PKCE, and access your custom tools. Use this skill when the user says "setup mcp server", "create mcp server", "serve mcp tools", "deploy mcp", or "remote mcp server".
author: "@mattwoodco"
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
dependencies: []
---

# Remote MCP Server with OAuth 2.1

Creates a standalone, deployable MCP server that agents (Claude Code, Claude Desktop, VS Code, etc.) can connect to via URL and authenticate using OAuth 2.1 with PKCE. Built with Hono, the MCP TypeScript SDK, Drizzle ORM, and PostgreSQL.

## What This Creates

A single deployable server exposing:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/mcp` | POST/GET/DELETE | MCP Streamable HTTP transport |
| `/.well-known/oauth-protected-resource` | GET | Protected Resource Metadata (RFC 9728) |
| `/.well-known/oauth-authorization-server` | GET | Authorization Server Metadata (RFC 8414) |
| `/oauth/register` | POST | Dynamic Client Registration (RFC 7591) |
| `/oauth/authorize` | GET/POST | User login + consent page |
| `/oauth/token` | POST | Token exchange and refresh |
| `/health` | GET | Health check |

Agents connect by adding:
```bash
claude mcp add --transport http my-server https://your-server.com/mcp
```

## Project Structure

```
├── src/
│   ├── index.ts                 # Entry point — HTTP server + Hono + MCP handler
│   ├── env.ts                   # Zod-validated environment
│   ├── db/
│   │   ├── index.ts             # Drizzle client (postgres.js)
│   │   └── schema.ts            # All tables: users, oauth_clients, codes, tokens
│   ├── auth/
│   │   └── password.ts          # scrypt password hashing
│   ├── oauth/
│   │   ├── metadata.ts          # .well-known endpoints
│   │   ├── register.ts          # Dynamic Client Registration
│   │   ├── authorize.ts         # Login + consent page
│   │   ├── token.ts             # Token exchange + refresh
│   │   └── verify.ts            # Token verification + generation
│   ├── mcp/
│   │   ├── server.ts            # McpServer instance + tool registration
│   │   └── handler.ts           # Streamable HTTP session manager
│   └── seed.ts                  # Seed a test user
├── docker-compose.yml           # PostgreSQL 17
├── drizzle.config.ts            # Drizzle Kit config
├── tsconfig.json
├── package.json
└── .env.local
```

## Prerequisites

- **Bun** installed (`curl -fsSL https://bun.sh/install | bash`)
- **Docker** running (for PostgreSQL)

## Installation

```bash
bun init -y
bun add hono @hono/node-server @modelcontextprotocol/sdk drizzle-orm postgres zod
bun add -d drizzle-kit @types/node typescript
```

## Environment Variables

### Create `.env.local`

```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/mcp
MCP_SERVER_URL=http://localhost:3001
PORT=3001
```

**Production**: Set `MCP_SERVER_URL` to your public HTTPS URL (e.g., `https://mcp.yourapp.com`).

## Docker Setup

### Create `docker-compose.yml`

```yaml
services:
  postgres:
    image: postgres:17-alpine
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: mcp
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 30s
    restart: unless-stopped

volumes:
  postgres_data:
```

Start PostgreSQL:

```bash
docker compose up -d
```

## Setup Steps

### Step 1: Create `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true,
    "outDir": "dist",
    "rootDir": "src",
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    },
    "types": ["bun-types"]
  },
  "include": ["src/**/*.ts"],
  "exclude": ["node_modules"]
}
```

### Step 2: Create `drizzle.config.ts`

```typescript
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: {
    url: process.env.DATABASE_URL ?? "",
  },
});
```

### Step 3: Create `src/env.ts`

```typescript
import { z } from "zod";

const envSchema = z.object({
  DATABASE_URL: z.string(),
  MCP_SERVER_URL: z.string().url(),
  PORT: z.coerce.number().default(3001),
});

export const env = envSchema.parse(process.env);
```

### Step 4: Create `src/db/index.ts`

```typescript
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error("DATABASE_URL is not set");
}

export const client = postgres(connectionString);
export const db = drizzle(client, { schema });
```

### Step 5: Create `src/db/schema.ts`

All database tables in one file — users and OAuth entities.

```typescript
import { pgTable, text, timestamp, jsonb } from "drizzle-orm/pg-core";

// --- Users ---

export const users = pgTable("users", {
  id: text("id").primaryKey(),
  email: text("email").notNull().unique(),
  passwordHash: text("password_hash").notNull(),
  name: text("name").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// --- OAuth Clients (from Dynamic Client Registration) ---

export const oauthClients = pgTable("oauth_clients", {
  clientId: text("client_id").primaryKey(),
  clientSecret: text("client_secret"),
  clientName: text("client_name").notNull(),
  redirectUris: jsonb("redirect_uris").$type<string[]>().notNull(),
  grantTypes: jsonb("grant_types").$type<string[]>().notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// --- Authorization Codes ---

export const oauthCodes = pgTable("oauth_codes", {
  code: text("code").primaryKey(),
  clientId: text("client_id")
    .notNull()
    .references(() => oauthClients.clientId),
  userId: text("user_id")
    .notNull()
    .references(() => users.id),
  redirectUri: text("redirect_uri").notNull(),
  scope: text("scope").notNull().default(""),
  codeChallenge: text("code_challenge").notNull(),
  codeChallengeMethod: text("code_challenge_method").notNull().default("S256"),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// --- Access Tokens ---

export const oauthAccessTokens = pgTable("oauth_access_tokens", {
  token: text("token").primaryKey(),
  clientId: text("client_id")
    .notNull()
    .references(() => oauthClients.clientId),
  userId: text("user_id")
    .notNull()
    .references(() => users.id),
  scope: text("scope").notNull().default(""),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// --- Refresh Tokens ---

export const oauthRefreshTokens = pgTable("oauth_refresh_tokens", {
  token: text("token").primaryKey(),
  clientId: text("client_id")
    .notNull()
    .references(() => oauthClients.clientId),
  userId: text("user_id")
    .notNull()
    .references(() => users.id),
  scope: text("scope").notNull().default(""),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});
```

### Step 6: Create `src/auth/password.ts`

```typescript
import { scryptSync, randomBytes, timingSafeEqual } from "node:crypto";

const SCRYPT_PARAMS = { N: 16384, r: 8, p: 1, maxmem: 128 * 16384 * 8 * 2 };
const KEY_LENGTH = 64;

export function hashPassword(password: string): string {
  const salt = randomBytes(16).toString("hex");
  const key = scryptSync(password, salt, KEY_LENGTH, SCRYPT_PARAMS);
  return `${salt}:${key.toString("hex")}`;
}

export function verifyPassword(password: string, hash: string): boolean {
  const [salt, key] = hash.split(":");
  if (!salt || !key) return false;
  const derived = scryptSync(password, salt, KEY_LENGTH, SCRYPT_PARAMS);
  return timingSafeEqual(Buffer.from(key, "hex"), derived);
}
```

### Step 7: Create `src/oauth/verify.ts`

Shared utilities for token generation and verification.

```typescript
import { randomBytes, createHash } from "node:crypto";
import { db } from "@/db";
import { oauthAccessTokens } from "@/db/schema";
import { eq } from "drizzle-orm";

export function generateToken(): string {
  return randomBytes(32).toString("hex");
}

export function generateClientId(): string {
  return `client_${randomBytes(16).toString("hex")}`;
}

export function generateClientSecret(): string {
  return `secret_${randomBytes(32).toString("hex")}`;
}

export function verifyCodeChallenge(
  verifier: string,
  challenge: string,
  method: string,
): boolean {
  if (method === "S256") {
    const computed = createHash("sha256").update(verifier).digest("base64url");
    return computed === challenge;
  }
  return verifier === challenge;
}

type VerifiedToken = {
  userId: string;
  clientId: string;
  scope: string;
};

export async function verifyAccessToken(
  token: string,
): Promise<VerifiedToken | null> {
  const [record] = await db
    .select()
    .from(oauthAccessTokens)
    .where(eq(oauthAccessTokens.token, token))
    .limit(1);

  if (!record) return null;
  if (record.expiresAt < new Date()) return null;

  return {
    userId: record.userId,
    clientId: record.clientId,
    scope: record.scope,
  };
}
```

### Step 8: Create `src/oauth/metadata.ts`

Serves the two `.well-known` metadata endpoints required by the MCP spec.

```typescript
import { Hono } from "hono";
import { env } from "@/env";

export const metadataApp = new Hono();

// RFC 9728 — Protected Resource Metadata
metadataApp.get("/oauth-protected-resource", (c) => {
  return c.json({
    resource: `${env.MCP_SERVER_URL}/mcp`,
    authorization_servers: [env.MCP_SERVER_URL],
    scopes_supported: ["mcp:tools"],
  });
});

// RFC 8414 — Authorization Server Metadata
metadataApp.get("/oauth-authorization-server", (c) => {
  return c.json({
    issuer: env.MCP_SERVER_URL,
    authorization_endpoint: `${env.MCP_SERVER_URL}/oauth/authorize`,
    token_endpoint: `${env.MCP_SERVER_URL}/oauth/token`,
    registration_endpoint: `${env.MCP_SERVER_URL}/oauth/register`,
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none", "client_secret_post"],
    scopes_supported: ["mcp:tools"],
  });
});
```

### Step 9: Create `src/oauth/register.ts`

Dynamic Client Registration (RFC 7591). MCP clients call this to register themselves before starting the OAuth flow.

```typescript
import { Hono } from "hono";
import { db } from "@/db";
import { oauthClients } from "@/db/schema";
import { generateClientId, generateClientSecret } from "./verify";

export const registerApp = new Hono();

type RegistrationBody = {
  client_name: string;
  redirect_uris: string[];
  grant_types?: string[];
  response_types?: string[];
};

registerApp.post("/register", async (c) => {
  const body = await c.req.json<RegistrationBody>();

  if (!body.client_name || !Array.isArray(body.redirect_uris)) {
    return c.json(
      { error: "invalid_client_metadata", error_description: "client_name and redirect_uris are required" },
      400,
    );
  }

  if (body.redirect_uris.length === 0) {
    return c.json(
      { error: "invalid_client_metadata", error_description: "At least one redirect_uri is required" },
      400,
    );
  }

  const clientId = generateClientId();
  const clientSecret = generateClientSecret();
  const grantTypes = body.grant_types ?? ["authorization_code", "refresh_token"];

  await db.insert(oauthClients).values({
    clientId,
    clientSecret,
    clientName: body.client_name,
    redirectUris: body.redirect_uris,
    grantTypes,
  });

  return c.json(
    {
      client_id: clientId,
      client_secret: clientSecret,
      client_name: body.client_name,
      redirect_uris: body.redirect_uris,
      grant_types: grantTypes,
      response_types: body.response_types ?? ["code"],
    },
    201,
  );
});
```

### Step 10: Create `src/oauth/authorize.ts`

Authorization endpoint — renders a login + consent page and processes the form submission.

```typescript
import { Hono } from "hono";
import { html } from "hono/html";
import { db } from "@/db";
import { oauthClients, oauthCodes, users } from "@/db/schema";
import { eq } from "drizzle-orm";
import { verifyPassword } from "@/auth/password";
import { generateToken } from "./verify";

export const authorizeApp = new Hono();

// GET — render login + consent page
authorizeApp.get("/authorize", async (c) => {
  const clientId = c.req.query("client_id") ?? "";
  const redirectUri = c.req.query("redirect_uri") ?? "";
  const state = c.req.query("state") ?? "";
  const codeChallenge = c.req.query("code_challenge") ?? "";
  const codeChallengeMethod = c.req.query("code_challenge_method") ?? "S256";
  const scope = c.req.query("scope") ?? "mcp:tools";
  const resource = c.req.query("resource") ?? "";

  // Validate client
  const [client] = await db
    .select()
    .from(oauthClients)
    .where(eq(oauthClients.clientId, clientId))
    .limit(1);

  if (!client) {
    return c.html(errorPage("Invalid client_id"), 400);
  }

  if (!client.redirectUris.includes(redirectUri)) {
    return c.html(errorPage("Invalid redirect_uri for this client"), 400);
  }

  if (!codeChallenge) {
    return c.html(errorPage("code_challenge is required (PKCE)"), 400);
  }

  return c.html(
    consentPage({
      clientName: client.clientName,
      scope,
      clientId,
      redirectUri,
      state,
      codeChallenge,
      codeChallengeMethod,
      resource,
    }),
  );
});

// POST — process login + consent
authorizeApp.post("/authorize", async (c) => {
  const body = await c.req.parseBody();
  const email = String(body.email ?? "");
  const password = String(body.password ?? "");
  const clientId = String(body.client_id ?? "");
  const redirectUri = String(body.redirect_uri ?? "");
  const state = String(body.state ?? "");
  const codeChallenge = String(body.code_challenge ?? "");
  const codeChallengeMethod = String(body.code_challenge_method ?? "S256");
  const scope = String(body.scope ?? "mcp:tools");

  // Validate client
  const [client] = await db
    .select()
    .from(oauthClients)
    .where(eq(oauthClients.clientId, clientId))
    .limit(1);

  if (!client || !client.redirectUris.includes(redirectUri)) {
    return c.html(errorPage("Invalid client"), 400);
  }

  // Authenticate user
  const [user] = await db
    .select()
    .from(users)
    .where(eq(users.email, email))
    .limit(1);

  if (!user || !verifyPassword(password, user.passwordHash)) {
    return c.html(
      consentPage({
        clientName: client.clientName,
        scope,
        clientId,
        redirectUri,
        state,
        codeChallenge,
        codeChallengeMethod,
        resource: "",
        error: "Invalid email or password",
      }),
      401,
    );
  }

  // Generate authorization code
  const code = generateToken();
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

  await db.insert(oauthCodes).values({
    code,
    clientId,
    userId: user.id,
    redirectUri,
    scope,
    codeChallenge,
    codeChallengeMethod,
    expiresAt,
  });

  // Redirect back to client with code
  const redirectUrl = new URL(redirectUri);
  redirectUrl.searchParams.set("code", code);
  if (state) redirectUrl.searchParams.set("state", state);

  return c.redirect(redirectUrl.toString(), 302);
});

// --- HTML Templates ---

type ConsentPageParams = {
  clientName: string;
  scope: string;
  clientId: string;
  redirectUri: string;
  state: string;
  codeChallenge: string;
  codeChallengeMethod: string;
  resource: string;
  error?: string;
};

function consentPage(params: ConsentPageParams) {
  return html`<!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Authorize ${params.clientName}</title>
        <style>
          *{box-sizing:border-box;margin:0;padding:0}
          body{font-family:system-ui,-apple-system,sans-serif;background:#f4f4f5;display:flex;align-items:center;justify-content:center;min-height:100vh;padding:1rem}
          .card{background:#fff;border-radius:12px;box-shadow:0 1px 3px rgba(0,0,0,.1);padding:2rem;max-width:400px;width:100%}
          h1{font-size:1.25rem;margin-bottom:.5rem}
          .subtitle{color:#71717a;font-size:.875rem;margin-bottom:1.5rem}
          .scope{background:#f4f4f5;border-radius:8px;padding:.75rem 1rem;margin-bottom:1.5rem;font-size:.875rem;color:#3f3f46}
          label{display:block;font-size:.875rem;font-weight:500;margin-bottom:.25rem;color:#3f3f46}
          input[type=email],input[type=password]{width:100%;padding:.5rem .75rem;border:1px solid #d4d4d8;border-radius:8px;font-size:.875rem;margin-bottom:1rem;outline:none}
          input:focus{border-color:#3b82f6;box-shadow:0 0 0 2px rgba(59,130,246,.15)}
          button{width:100%;padding:.625rem;background:#18181b;color:#fff;border:none;border-radius:8px;font-size:.875rem;font-weight:500;cursor:pointer}
          button:hover{background:#27272a}
          .error{background:#fef2f2;color:#dc2626;padding:.75rem 1rem;border-radius:8px;margin-bottom:1rem;font-size:.875rem}
        </style>
      </head>
      <body>
        <div class="card">
          <h1>Authorize</h1>
          <p class="subtitle">
            <strong>${params.clientName}</strong> wants to access your MCP
            tools.
          </p>
          <div class="scope">Scope: ${params.scope || "mcp:tools"}</div>
          ${params.error ? html`<div class="error">${params.error}</div>` : ""}
          <form method="POST" action="/oauth/authorize">
            <input type="hidden" name="client_id" value="${params.clientId}" />
            <input
              type="hidden"
              name="redirect_uri"
              value="${params.redirectUri}"
            />
            <input type="hidden" name="state" value="${params.state}" />
            <input
              type="hidden"
              name="code_challenge"
              value="${params.codeChallenge}"
            />
            <input
              type="hidden"
              name="code_challenge_method"
              value="${params.codeChallengeMethod}"
            />
            <input type="hidden" name="scope" value="${params.scope}" />
            <label for="email">Email</label>
            <input
              type="email"
              id="email"
              name="email"
              required
              autocomplete="email"
            />
            <label for="password">Password</label>
            <input
              type="password"
              id="password"
              name="password"
              required
              autocomplete="current-password"
            />
            <button type="submit">Authorize</button>
          </form>
        </div>
      </body>
    </html>`;
}

function errorPage(message: string) {
  return html`<!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>Error</title>
        <style>
          body{font-family:system-ui;display:flex;align-items:center;justify-content:center;min-height:100vh;background:#f4f4f5}
          .card{background:#fff;padding:2rem;border-radius:12px;box-shadow:0 1px 3px rgba(0,0,0,.1);max-width:400px}
          h1{color:#dc2626;font-size:1.25rem;margin-bottom:.5rem}
          p{color:#71717a;font-size:.875rem}
        </style>
      </head>
      <body>
        <div class="card">
          <h1>Authorization Error</h1>
          <p>${message}</p>
        </div>
      </body>
    </html>`;
}
```

### Step 11: Create `src/oauth/token.ts`

Token endpoint — handles authorization code exchange and refresh token grants.

```typescript
import { Hono, type Context } from "hono";
import { db } from "@/db";
import {
  oauthCodes,
  oauthAccessTokens,
  oauthRefreshTokens,
} from "@/db/schema";
import { eq } from "drizzle-orm";
import { generateToken, verifyCodeChallenge } from "./verify";

export const tokenApp = new Hono();

type FormBody = Record<string, string | File>;

tokenApp.post("/token", async (c) => {
  const body = await c.req.parseBody();
  const grantType = String(body.grant_type ?? "");

  if (grantType === "authorization_code") {
    return handleAuthorizationCode(c, body);
  }

  if (grantType === "refresh_token") {
    return handleRefreshToken(c, body);
  }

  return c.json(
    { error: "unsupported_grant_type", error_description: "Only authorization_code and refresh_token are supported" },
    400,
  );
});

async function handleAuthorizationCode(
  c: Context,
  body: FormBody,
) {
  const code = String(body.code ?? "");
  const redirectUri = String(body.redirect_uri ?? "");
  const codeVerifier = String(body.code_verifier ?? "");
  const clientId = String(body.client_id ?? "");

  if (!code || !redirectUri || !codeVerifier || !clientId) {
    return c.json(
      { error: "invalid_request", error_description: "Missing required parameters" },
      400,
    );
  }

  // Look up and validate authorization code
  const [codeRecord] = await db
    .select()
    .from(oauthCodes)
    .where(eq(oauthCodes.code, code))
    .limit(1);

  if (!codeRecord) {
    return c.json({ error: "invalid_grant", error_description: "Invalid authorization code" }, 400);
  }

  if (codeRecord.expiresAt < new Date()) {
    await db.delete(oauthCodes).where(eq(oauthCodes.code, code));
    return c.json({ error: "invalid_grant", error_description: "Authorization code expired" }, 400);
  }

  if (codeRecord.clientId !== clientId) {
    return c.json({ error: "invalid_grant", error_description: "Client mismatch" }, 400);
  }

  if (codeRecord.redirectUri !== redirectUri) {
    return c.json({ error: "invalid_grant", error_description: "Redirect URI mismatch" }, 400);
  }

  // Verify PKCE
  if (
    !verifyCodeChallenge(
      codeVerifier,
      codeRecord.codeChallenge,
      codeRecord.codeChallengeMethod,
    )
  ) {
    return c.json({ error: "invalid_grant", error_description: "PKCE verification failed" }, 400);
  }

  // Delete used code
  await db.delete(oauthCodes).where(eq(oauthCodes.code, code));

  // Issue tokens
  const accessToken = generateToken();
  const refreshToken = generateToken();
  const accessExpiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1 hour
  const refreshExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days

  await db.insert(oauthAccessTokens).values({
    token: accessToken,
    clientId: codeRecord.clientId,
    userId: codeRecord.userId,
    scope: codeRecord.scope,
    expiresAt: accessExpiresAt,
  });

  await db.insert(oauthRefreshTokens).values({
    token: refreshToken,
    clientId: codeRecord.clientId,
    userId: codeRecord.userId,
    scope: codeRecord.scope,
    expiresAt: refreshExpiresAt,
  });

  return c.json({
    access_token: accessToken,
    token_type: "Bearer",
    expires_in: 3600,
    refresh_token: refreshToken,
    scope: codeRecord.scope,
  });
}

async function handleRefreshToken(
  c: Context,
  body: FormBody,
) {
  const refreshTokenValue = String(body.refresh_token ?? "");
  const clientId = String(body.client_id ?? "");

  if (!refreshTokenValue || !clientId) {
    return c.json(
      { error: "invalid_request", error_description: "Missing required parameters" },
      400,
    );
  }

  // Look up refresh token
  const [refreshRecord] = await db
    .select()
    .from(oauthRefreshTokens)
    .where(eq(oauthRefreshTokens.token, refreshTokenValue))
    .limit(1);

  if (!refreshRecord) {
    return c.json({ error: "invalid_grant", error_description: "Invalid refresh token" }, 400);
  }

  if (refreshRecord.expiresAt < new Date()) {
    await db
      .delete(oauthRefreshTokens)
      .where(eq(oauthRefreshTokens.token, refreshTokenValue));
    return c.json({ error: "invalid_grant", error_description: "Refresh token expired" }, 400);
  }

  if (refreshRecord.clientId !== clientId) {
    return c.json({ error: "invalid_grant", error_description: "Client mismatch" }, 400);
  }

  // Rotate: delete old refresh token, issue new access + refresh tokens
  await db
    .delete(oauthRefreshTokens)
    .where(eq(oauthRefreshTokens.token, refreshTokenValue));

  const newAccessToken = generateToken();
  const newRefreshToken = generateToken();
  const accessExpiresAt = new Date(Date.now() + 60 * 60 * 1000);
  const refreshExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

  await db.insert(oauthAccessTokens).values({
    token: newAccessToken,
    clientId: refreshRecord.clientId,
    userId: refreshRecord.userId,
    scope: refreshRecord.scope,
    expiresAt: accessExpiresAt,
  });

  await db.insert(oauthRefreshTokens).values({
    token: newRefreshToken,
    clientId: refreshRecord.clientId,
    userId: refreshRecord.userId,
    scope: refreshRecord.scope,
    expiresAt: refreshExpiresAt,
  });

  return c.json({
    access_token: newAccessToken,
    token_type: "Bearer",
    expires_in: 3600,
    refresh_token: newRefreshToken,
    scope: refreshRecord.scope,
  });
}
```

### Step 12: Create `src/mcp/server.ts`

The MCP server instance with example tools. Add your custom tools here.

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function createMcpServer(): McpServer {
  const server = new McpServer({
    name: "my-mcp-server",
    version: "1.0.0",
  });

  // --- Example Tools ---

  server.tool(
    "greet",
    "Greet a user by name",
    { name: z.string().describe("The name to greet") },
    async ({ name }) => ({
      content: [
        { type: "text", text: `Hello, ${name}! Welcome to the MCP server.` },
      ],
    }),
  );

  server.tool(
    "echo",
    "Echo back the input message",
    { message: z.string().describe("The message to echo") },
    async ({ message }) => ({
      content: [{ type: "text", text: message }],
    }),
  );

  server.tool(
    "get_time",
    "Get the current server time in ISO format",
    {},
    async () => ({
      content: [
        { type: "text", text: new Date().toISOString() },
      ],
    }),
  );

  return server;
}
```

### Step 13: Create `src/mcp/handler.ts`

Manages Streamable HTTP sessions and routes POST/GET/DELETE to the correct transport.

```typescript
import type { IncomingMessage, ServerResponse } from "node:http";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { isInitializeRequest } from "@modelcontextprotocol/sdk/types.js";
import { randomUUID } from "node:crypto";
import { createMcpServer } from "./server";

const sessions = new Map<string, StreamableHTTPServerTransport>();

export async function handleMCP(
  req: IncomingMessage,
  res: ServerResponse,
): Promise<void> {
  const method = req.method?.toUpperCase();

  if (method === "POST") {
    await handlePost(req, res);
  } else if (method === "GET") {
    await handleGet(req, res);
  } else if (method === "DELETE") {
    await handleDelete(req, res);
  } else {
    res.writeHead(405, { Allow: "GET, POST, DELETE" });
    res.end();
  }
}

async function handlePost(
  req: IncomingMessage,
  res: ServerResponse,
): Promise<void> {
  const body = await parseBody(req);
  const sessionId = req.headers["mcp-session-id"] as string | undefined;

  // Existing session
  if (sessionId && sessions.has(sessionId)) {
    const transport = sessions.get(sessionId)!;
    await transport.handleRequest(req, res, body);
    return;
  }

  // New session — must be an initialize request
  if (!sessionId && isInitializeRequest(body)) {
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => randomUUID(),
      onsessioninitialized: (sid) => {
        sessions.set(sid, transport);
      },
    });

    transport.onclose = () => {
      if (transport.sessionId) {
        sessions.delete(transport.sessionId);
      }
    };

    const server = createMcpServer();
    await server.connect(transport);
    await transport.handleRequest(req, res, body);
    return;
  }

  // Bad request
  res.writeHead(400, { "Content-Type": "application/json" });
  res.end(
    JSON.stringify({
      jsonrpc: "2.0",
      error: {
        code: -32000,
        message: "Bad Request: missing session ID or not an initialize request",
      },
      id: null,
    }),
  );
}

async function handleGet(
  req: IncomingMessage,
  res: ServerResponse,
): Promise<void> {
  const sessionId = req.headers["mcp-session-id"] as string | undefined;

  if (!sessionId || !sessions.has(sessionId)) {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Invalid or missing session ID" }));
    return;
  }

  await sessions.get(sessionId)!.handleRequest(req, res);
}

async function handleDelete(
  req: IncomingMessage,
  res: ServerResponse,
): Promise<void> {
  const sessionId = req.headers["mcp-session-id"] as string | undefined;

  if (!sessionId || !sessions.has(sessionId)) {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Invalid or missing session ID" }));
    return;
  }

  await sessions.get(sessionId)!.handleRequest(req, res);
}

function parseBody(req: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf-8");
      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new Error("Invalid JSON body"));
      }
    });
    req.on("error", reject);
  });
}
```

### Step 14: Create `src/index.ts`

Main entry point — creates the HTTP server, mounts Hono for OAuth routes, and handles MCP requests with raw Node.js HTTP for streaming support.

```typescript
import { createServer } from "node:http";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { getRequestListener } from "@hono/node-server";
import { env } from "@/env";
import { handleMCP } from "@/mcp/handler";
import { verifyAccessToken } from "@/oauth/verify";
import { metadataApp } from "@/oauth/metadata";
import { registerApp } from "@/oauth/register";
import { authorizeApp } from "@/oauth/authorize";
import { tokenApp } from "@/oauth/token";

const app = new Hono();

// CORS for OAuth endpoints
app.use("/oauth/*", cors());

// Health check
app.get("/health", (c) => c.json({ status: "ok" }));

// .well-known metadata
app.route("/.well-known", metadataApp);

// OAuth endpoints
app.route("/oauth", registerApp);
app.route("/oauth", authorizeApp);
app.route("/oauth", tokenApp);

// Convert Hono app to Node.js request listener
const honoListener = getRequestListener((request) => app.fetch(request));

// HTTP server — routes /mcp to the MCP handler, everything else to Hono
const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", `http://${req.headers.host}`);

  if (url.pathname === "/mcp") {
    // Validate bearer token for MCP requests
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith("Bearer ")) {
      const metadataUrl = `${env.MCP_SERVER_URL}/.well-known/oauth-protected-resource`;
      res.writeHead(401, {
        "Content-Type": "application/json",
        "WWW-Authenticate": `Bearer resource_metadata="${metadataUrl}"`,
      });
      res.end(JSON.stringify({ error: "unauthorized" }));
      return;
    }

    const token = authHeader.slice(7);
    const verified = await verifyAccessToken(token);
    if (!verified) {
      const metadataUrl = `${env.MCP_SERVER_URL}/.well-known/oauth-protected-resource`;
      res.writeHead(401, {
        "Content-Type": "application/json",
        "WWW-Authenticate": `Bearer resource_metadata="${metadataUrl}"`,
      });
      res.end(JSON.stringify({ error: "invalid_token" }));
      return;
    }

    await handleMCP(req, res);
    return;
  }

  // All other routes handled by Hono
  honoListener(req, res);
});

server.listen(env.PORT, () => {
  console.log(`\nMCP Server running on port ${env.PORT}`);
  console.log(`  MCP endpoint:  ${env.MCP_SERVER_URL}/mcp`);
  console.log(`  OAuth:         ${env.MCP_SERVER_URL}/oauth/authorize`);
  console.log(`  Health:        ${env.MCP_SERVER_URL}/health`);
  console.log(`  Metadata:      ${env.MCP_SERVER_URL}/.well-known/oauth-protected-resource\n`);
});
```

### Step 15: Create `src/seed.ts`

Creates a test user for the OAuth consent page.

```typescript
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { users } from "./db/schema";
import { hashPassword } from "./auth/password";
import { randomBytes } from "node:crypto";

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error("DATABASE_URL is required");
  process.exit(1);
}

const client = postgres(DATABASE_URL);
const db = drizzle(client);

async function seed() {
  const id = randomBytes(16).toString("hex");
  const hash = hashPassword("password123");

  await db
    .insert(users)
    .values({
      id,
      email: "admin@example.com",
      passwordHash: hash,
      name: "Admin",
    })
    .onConflictDoNothing();

  console.log("Seeded user: admin@example.com / password123");
  await client.end();
}

seed().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

### Step 16: Update `package.json` scripts

Add these scripts:

```json
{
  "scripts": {
    "dev": "bun --watch src/index.ts",
    "start": "bun src/index.ts",
    "db:push": "drizzle-kit push",
    "db:generate": "drizzle-kit generate",
    "db:studio": "drizzle-kit studio",
    "seed": "bun src/seed.ts",
    "typecheck": "tsc --noEmit"
  }
}
```

## Running Locally

```bash
# 1. Start PostgreSQL
docker compose up -d

# 2. Push schema to database
bun run db:push

# 3. Seed a test user
bun run seed

# 4. Start the MCP server
bun run dev
```

The server starts on `http://localhost:3001`. Verify with:

```bash
# Health check
curl http://localhost:3001/health

# Protected Resource Metadata
curl http://localhost:3001/.well-known/oauth-protected-resource

# Authorization Server Metadata
curl http://localhost:3001/.well-known/oauth-authorization-server

# MCP endpoint without token → 401
curl -v http://localhost:3001/mcp
```

## Connecting MCP Clients

### Claude Code

```bash
claude mcp add --transport http my-server http://localhost:3001/mcp
```

Then inside Claude Code, run `/mcp` to authenticate. Claude Code will:
1. Discover your OAuth endpoints via `.well-known`
2. Register itself via Dynamic Client Registration
3. Open your browser to the consent page
4. You log in with `admin@example.com` / `password123`
5. Claude Code receives the token and stores it securely

After authentication, your tools (`greet`, `echo`, `get_time`) are available.

### Claude Desktop

1. Go to **Settings > Connectors**
2. Add a new connector with URL: `http://localhost:3001/mcp`
3. Complete the OAuth flow when prompted

**Important**: When deploying to production, allowlist these callback URLs in your OAuth clients:
- `https://claude.ai/api/mcp/auth_callback`
- `https://claude.com/api/mcp/auth_callback`

### Other MCP Clients

Any MCP client supporting Streamable HTTP transport + OAuth 2.1 can connect. The discovery flow is automatic via the `.well-known` endpoints.

## Adding Custom Tools

Edit `src/mcp/server.ts` to add your own tools:

```typescript
import { z } from "zod";

// Inside createMcpServer():

server.tool(
  "search_docs",
  "Search documentation by keyword",
  {
    query: z.string().describe("Search query"),
    limit: z.number().optional().describe("Max results (default 10)"),
  },
  async ({ query, limit }) => {
    const maxResults = limit ?? 10;
    // Your search logic here
    const results = await searchDocuments(query, maxResults);
    return {
      content: [{ type: "text", text: JSON.stringify(results, null, 2) }],
    };
  },
);
```

Tools support:
- **Zod schemas** for input validation
- **Async handlers** for database queries, API calls, etc.
- **Multiple content types**: `text`, `image` (base64), `resource` (embedded)

## Deployment

### Dockerfile

```dockerfile
FROM oven/bun:1 AS base
WORKDIR /app

FROM base AS deps
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile --production

FROM base AS runner
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV NODE_ENV=production
EXPOSE 3001

CMD ["bun", "src/index.ts"]
```

### Deploy to any container platform

```bash
# Build
docker build -t my-mcp-server .

# Run
docker run -p 3001:3001 \
  -e DATABASE_URL=postgresql://user:pass@db:5432/mcp \
  -e MCP_SERVER_URL=https://mcp.yourapp.com \
  -e PORT=3001 \
  my-mcp-server
```

**Production checklist**:
- Set `MCP_SERVER_URL` to your public HTTPS URL
- Use a managed PostgreSQL (Neon, Supabase, RDS)
- Enable HTTPS (via reverse proxy or platform)
- Create users via the seed script or add a registration endpoint

## Troubleshooting

### 401 Unauthorized on /mcp

**Cause**: Missing or invalid Bearer token.

**Fix**: Complete the OAuth flow first. In Claude Code, run `/mcp` to authenticate.

### "Invalid client_id" on authorize page

**Cause**: The MCP client hasn't registered via DCR yet.

**Fix**: The client should POST to `/oauth/register` first. Most MCP clients handle this automatically via the `.well-known` discovery flow.

### "Invalid email or password" on consent page

**Cause**: No user seeded or wrong credentials.

**Fix**: Run `bun run seed` and log in with `admin@example.com` / `password123`.

### Port 3001 already in use

**Fix**: Change `PORT` in `.env.local` or stop the conflicting process:
```bash
lsof -i :3001
```

### Database connection refused

**Fix**: Ensure PostgreSQL is running:
```bash
docker compose up -d
docker compose ps
```

### PKCE verification failed

**Cause**: The `code_verifier` doesn't match the `code_challenge` sent during authorization.

**Fix**: This is typically a client bug. Ensure the client uses SHA-256 for the code challenge method.

## Acceptance Criteria

- `bun run typecheck` passes with no errors
- `docker compose up -d` starts PostgreSQL
- `bun run db:push` creates all tables
- `bun run seed` creates a test user
- `bun run dev` starts the server on the configured port
- `GET /health` returns `{ "status": "ok" }`
- `GET /.well-known/oauth-protected-resource` returns valid RFC 9728 metadata
- `GET /.well-known/oauth-authorization-server` returns valid RFC 8414 metadata
- `POST /oauth/register` creates a new OAuth client and returns `client_id`
- `GET /oauth/authorize` renders a login + consent page
- `POST /oauth/authorize` authenticates and redirects with an authorization code
- `POST /oauth/token` exchanges code for access + refresh tokens
- `POST /mcp` without token returns 401 with `WWW-Authenticate` header
- `POST /mcp` with valid token processes MCP JSON-RPC messages
- Tools (`greet`, `echo`, `get_time`) are discoverable and callable
- Claude Code can connect via `claude mcp add --transport http`
- No usage of `any` type anywhere
- Uses `postgres` package (NOT `pg`)
- Uses `drizzle-orm/postgres-js`
