---
name: auth-dev
description: Dev-mode authentication tooling — seed dev users and quick sign-in buttons for each role. Use this skill when the user says "setup dev auth", "add dev login", "setup dev users", "seed test users", or "dev sign-in".
author: "@mattwoodco"
version: 1.1.0
created: 2026-02-14
updated: 2026-02-19
dependencies: [auth]
---

# Dev Authentication Tooling

Adds one-click dev sign-in buttons directly on the login screen, a development-only `/dev` console page, and an API endpoint that seeds dev users into the database. Users are auto-seeded when the login page loads. Everything is gated behind `NODE_ENV !== 'production'` so none of this code runs in production builds.

## What Gets Created

1. **`src/app/api/dev/seed/route.ts`** — Seeds dev users via better-auth internal API + Drizzle role patch
2. **`src/components/auth/dev-login-panel.tsx`** — One-click sign-in buttons shown below the login form (auto-seeds on mount)
3. **`src/app/(auth)/sign-in/page.tsx`** — Updated to include DevLoginPanel in development
4. **`src/app/dev/layout.tsx`** — Dev-only layout guard (returns 404 in production)
5. **`src/app/dev/page.tsx`** — Dev console with seed button + quick sign-in cards

## Prerequisites

- `auth` skill fully applied (auth config, database schema, auth client)
- Database running and schema pushed (`bunx drizzle-kit push`)
- Dev server running (`bun run dev`)

## Dev Users

| Role   | Email              | Password   |
|--------|--------------------|------------|
| admin  | <admin@example.com>  | Admin123!  |
| member | <member@example.com> | Member123! |

## Setup Steps

### 1. Create Dev Layout Guard (`src/app/dev/layout.tsx`)

```tsx
import { notFound } from "next/navigation";

export default function DevLayout({ children }: { children: React.ReactNode }) {
  if (process.env.NODE_ENV === "production") {
    notFound();
  }

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <div className="mx-auto max-w-xl px-4 py-12">
        <div className="mb-8 rounded-lg border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm text-amber-400">
          Development only — this page is not available in production.
        </div>
        {children}
      </div>
    </div>
  );
}
```

### 2. Create Dev Console Page (`src/app/dev/page.tsx`)

```tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { signIn, signOut, useSession } from "@src/lib/auth-client";

const DEV_USERS = [
  { email: "admin@example.com", password: "Admin123!", name: "Admin User", role: "admin" },
  { email: "member@example.com", password: "Member123!", name: "Member User", role: "member" },
] as const;

export default function DevPage() {
  const router = useRouter();
  const { data: session, isPending } = useSession();
  const [seeding, setSeeding] = useState(false);
  const [seedResult, setSeedResult] = useState<string | null>(null);
  const [signingIn, setSigningIn] = useState<string | null>(null);

  const handleSeed = async () => {
    setSeeding(true);
    setSeedResult(null);
    try {
      const res = await fetch("/api/dev/seed", { method: "POST" });
      const data = await res.json();
      if (res.ok) {
        setSeedResult(`Seeded ${data.results.length} users: ${data.results.map((r: { email: string; status: string }) => `${r.email} (${r.status})`).join(", ")}`);
      } else {
        setSeedResult(`Error: ${data.error}`);
      }
    } catch (err) {
      setSeedResult(`Network error: ${err instanceof Error ? err.message : "unknown"}`);
    } finally {
      setSeeding(false);
    }
  };

  const handleSignIn = async (email: string, password: string) => {
    setSigningIn(email);
    try {
      const result = await signIn.email({ email, password });
      if (result.error) {
        setSeedResult(`Sign-in failed for ${email}: ${result.error.message ?? "unknown error"} — try seeding first.`);
      } else {
        router.push("/");
        router.refresh();
      }
    } finally {
      setSigningIn(null);
    }
  };

  const handleSignOut = async () => {
    await signOut();
    router.refresh();
  };

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold">Dev Console</h1>
        <p className="mt-1 text-sm text-zinc-400">Quick authentication for development</p>
      </div>

      {/* Current session */}
      <div className="rounded-xl border border-zinc-800 bg-zinc-900 p-5">
        <h2 className="mb-3 text-sm font-medium uppercase tracking-wider text-zinc-500">Current Session</h2>
        {isPending ? (
          <div className="h-5 w-32 animate-pulse rounded bg-zinc-800" />
        ) : session ? (
          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium">{session.user.name}</p>
              <p className="text-sm text-zinc-400">{session.user.email}</p>
            </div>
            <button
              type="button"
              onClick={handleSignOut}
              className="rounded-lg border border-zinc-700 px-3 py-1.5 text-sm hover:bg-zinc-800"
            >
              Sign Out
            </button>
          </div>
        ) : (
          <p className="text-sm text-zinc-500">Not signed in</p>
        )}
      </div>

      {/* Seed */}
      <div className="rounded-xl border border-zinc-800 bg-zinc-900 p-5">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-sm font-medium uppercase tracking-wider text-zinc-500">Database Seed</h2>
            <p className="mt-1 text-sm text-zinc-400">Create dev users in the database</p>
          </div>
          <button
            type="button"
            onClick={handleSeed}
            disabled={seeding}
            className="rounded-lg bg-amber-600 px-4 py-2 text-sm font-medium text-white hover:bg-amber-500 disabled:opacity-50"
          >
            {seeding ? "Seeding..." : "Seed Users"}
          </button>
        </div>
        {seedResult && (
          <p className="mt-3 rounded-lg bg-zinc-800 px-3 py-2 text-sm text-zinc-300">{seedResult}</p>
        )}
      </div>

      {/* Quick sign-in cards */}
      <div>
        <h2 className="mb-4 text-sm font-medium uppercase tracking-wider text-zinc-500">Quick Sign In</h2>
        <div className="grid gap-4">
          {DEV_USERS.map((devUser) => (
            <div
              key={devUser.email}
              className="flex items-center justify-between rounded-xl border border-zinc-800 bg-zinc-900 p-5"
            >
              <div>
                <p className="font-medium">{devUser.name}</p>
                <p className="text-sm text-zinc-400">{devUser.email}</p>
                <span className="mt-1 inline-block rounded-full bg-zinc-800 px-2.5 py-0.5 text-xs text-zinc-300">
                  {devUser.role}
                </span>
              </div>
              <button
                type="button"
                onClick={() => handleSignIn(devUser.email, devUser.password)}
                disabled={signingIn === devUser.email}
                className="rounded-lg bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-900 hover:bg-white disabled:opacity-50"
              >
                {signingIn === devUser.email ? "Signing in..." : "Sign In"}
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
```

### 3. Create Seed API Route (`src/app/api/dev/seed/route.ts`)

> Uses better-auth's internal `signUpEmail` API so password hashing is handled automatically — no need for manual scrypt. Falls back gracefully if users already exist.

```typescript
import { NextResponse } from "next/server";

const DEV_USERS = [
  { email: "admin@example.com", password: "Admin123!", name: "Admin User", role: "admin" },
  { email: "member@example.com", password: "Member123!", name: "Member User", role: "member" },
] as const;

export async function POST() {
  if (process.env.NODE_ENV === "production") {
    return NextResponse.json({ error: "Not available in production" }, { status: 404 });
  }

  const { auth } = await import("@src/lib/auth");
  const { db } = await import("@src/lib/db");
  const { user } = await import("@src/lib/db/schema/auth");
  const { eq } = await import("drizzle-orm");

  const results: { email: string; status: string }[] = [];

  for (const devUser of DEV_USERS) {
    // Check if user already exists
    const existing = await db
      .select({ id: user.id })
      .from(user)
      .where(eq(user.email, devUser.email))
      .limit(1);

    if (existing.length > 0) {
      // Ensure role is correct
      await db
        .update(user)
        .set({ role: devUser.role })
        .where(eq(user.email, devUser.email));
      results.push({ email: devUser.email, status: "exists" });
      continue;
    }

    // Create user via better-auth internal API (handles password hashing)
    try {
      await auth.api.signUpEmail({
        body: {
          email: devUser.email,
          password: devUser.password,
          name: devUser.name,
        },
      });

      // Patch role + mark email as verified
      await db
        .update(user)
        .set({ role: devUser.role, emailVerified: true })
        .where(eq(user.email, devUser.email));

      results.push({ email: devUser.email, status: "created" });
    } catch (err) {
      const message = err instanceof Error ? err.message : "unknown";
      results.push({ email: devUser.email, status: `error: ${message}` });
    }
  }

  return NextResponse.json({ results });
}
```

### 4. Create Dev Login Panel (`src/components/auth/dev-login-panel.tsx`)

> Shown directly on the sign-in page in development. Auto-seeds dev users on mount so clicking a button just works — no manual seeding step needed.

```tsx
"use client";

import { useEffect, useId, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { signIn } from "@src/lib/auth-client";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

const DEV_USERS = [
  { email: "admin@example.com", password: "Admin123!", name: "Admin User", role: "admin" },
  { email: "member@example.com", password: "Member123!", name: "Member User", role: "member" },
] as const;

type SeedStatus = "idle" | "seeding" | "ready" | "error";

export function DevLoginPanel() {
  const router = useRouter();
  const id = useId();
  const seeded = useRef(false);
  const [seedStatus, setSeedStatus] = useState<SeedStatus>("idle");
  const [signingIn, setSigningIn] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Auto-seed dev users on mount
  useEffect(() => {
    if (seeded.current) return;
    seeded.current = true;

    setSeedStatus("seeding");
    fetch("/api/dev/seed", { method: "POST" })
      .then((res) => {
        if (res.ok) {
          setSeedStatus("ready");
        } else {
          setSeedStatus("error");
        }
      })
      .catch(() => {
        setSeedStatus("error");
      });
  }, []);

  const handleSignIn = async (email: string, password: string) => {
    setSigningIn(email);
    setError(null);
    try {
      const result = await signIn.email({ email, password });
      if (result.error) {
        setError(`Sign-in failed: ${result.error.message ?? "unknown error"}`);
      } else {
        router.push("/");
        router.refresh();
      }
    } finally {
      setSigningIn(null);
    }
  };

  if (process.env.NODE_ENV === "production") return null;

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3">
        <div className="h-px flex-1 bg-border" />
        <span className="text-xs text-muted-foreground">Dev Quick Login</span>
        <div className="h-px flex-1 bg-border" />
      </div>

      {seedStatus === "seeding" && (
        <p className="text-center text-xs text-muted-foreground animate-pulse">
          Seeding dev users...
        </p>
      )}

      {seedStatus === "error" && (
        <p className="text-center text-xs text-destructive">
          Failed to seed users. Is the database running?
        </p>
      )}

      <div className="grid gap-2">
        {DEV_USERS.map((devUser) => (
          <Button
            key={`${id}-${devUser.email}`}
            variant="outline"
            className="h-auto w-full justify-between !rounded-md px-4 py-3"
            disabled={seedStatus !== "ready" || signingIn !== null}
            onClick={() => handleSignIn(devUser.email, devUser.password)}
          >
            <div className="flex items-center gap-2 text-left">
              <div>
                <p className="text-sm font-medium">{devUser.name}</p>
                <p className="text-xs text-muted-foreground">{devUser.email}</p>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <Badge variant="secondary">{devUser.role}</Badge>
              {signingIn === devUser.email && (
                <div className="h-4 w-4 animate-spin rounded-full border-2 border-muted border-t-foreground" />
              )}
            </div>
          </Button>
        ))}
      </div>

      {error && (
        <p className="text-center text-xs text-destructive">{error}</p>
      )}
    </div>
  );
}
```

### 5. Update Sign-In Page (`src/app/(auth)/sign-in/page.tsx`)

> Add the DevLoginPanel below the existing AuthCard. The `process.env.NODE_ENV` check is compiled away by Next.js in production builds, so the import is tree-shaken out entirely.

```tsx
import { AuthCard } from "@/components/auth/auth-card";
import { DevLoginPanel } from "@/components/auth/dev-login-panel";

export default function SignInPage() {
  return (
    <div className="space-y-6">
      <AuthCard mode="sign-in" />
      {process.env.NODE_ENV !== "production" && <DevLoginPanel />}
    </div>
  );
}
```

## Usage

1. Start the dev server: `bun run dev`
2. Navigate to `http://localhost:3000/sign-in` — dev quick-login buttons appear below the form
3. Click any dev user button to instantly sign in (users are auto-seeded on page load)
4. Alternatively, visit `http://localhost:3000/dev` for the full dev console with manual seed controls

## Route Protection Note

If your `src/proxy.ts` protects the `/dev` route, add it to the exclusion list:

```typescript
// In src/proxy.ts — ensure /dev is NOT in protectedRoutes
const protectedRoutes = ["/dashboard", "/settings", "/admin", "/chat", "/account"];
// /dev is intentionally unprotected for dev access
```

## Verification

```bash
# 1. TypeScript check
bunx tsc --noEmit

# 2. Confirm sign-in page loads with dev panel
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/sign-in
# Expected: 200

# 3. Confirm dev console loads
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/dev
# Expected: 200

# 4. Seed users via API
curl -s -X POST http://localhost:3000/api/dev/seed | jq
# Expected: { "results": [{ "email": "admin@example.com", "status": "created" }, ...] }
```

## Troubleshooting

### Sign-in fails after seeding

**Symptom**: "Sign-in failed" error after clicking a user card.

**Cause**: Users weren't seeded yet, or the seed encountered an error.

**Fix**: Click "Seed Users" first and check the result message. If it shows errors, verify your database is running and schema is pushed (`bunx drizzle-kit push`).

### Dev page shows 404

**Symptom**: `/dev` returns 404 even in development.

**Cause**: `NODE_ENV` is set to `production` or the route is blocked by `proxy.ts`.

**Fix**: Ensure `NODE_ENV=development` (default for `bun run dev`) and check that `/dev` is not in the `protectedRoutes` array in `src/proxy.ts`.

### Welcome emails fail during seed

**Symptom**: Seed errors related to email sending.

**Cause**: The auth config's `databaseHooks.user.create.after` sends a welcome email. If the email service isn't running, this may error.

**Fix**: Start MailHog/Mailpit (`docker compose up -d`), or temporarily disable the `databaseHooks` in `src/lib/auth.tsx` during seeding. The seed endpoint catches errors per-user so other users will still be created.
