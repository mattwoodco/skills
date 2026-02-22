---
name: auth
description: Setup better-auth authentication with email/password, social providers, role-based access control, account management, and session handling. Use this skill when the user says "setup auth", "add authentication", "setup better-auth", "add login", or "setup user auth".
metadata:
  author: "@mattwoodco"
  version: "2.1.0"
  created: "2026-01-11"
  updated: "2026-02-13"
  dependencies: [env-config, docker, db]
---

# Authentication Setup with better-auth

Sets up a complete authentication system using better-auth with email/password, social OAuth providers, role-based access control, account management, session management, and Drizzle ORM integration.

## What Gets Created

### Core Files

1. **`src/lib/auth.tsx`** - Server-side auth configuration (JSX for email templates)
2. **`src/lib/auth-client.ts`** - Client-side auth hooks and methods
3. **`src/lib/auth-guard.ts`** - Protected route helpers for API routes
4. **`src/app/api/auth/[...all]/route.ts`** - Auth API route handler
5. **`drizzle.config.ts`** - Drizzle ORM configuration
6. **`src/db/index.ts`** - Database client
7. **`src/db/schema/auth.ts`** - Drizzle schema for auth tables
8. **`src/proxy.ts`** - Route protection (Next.js 16+)

### UI Components

1. **`src/components/auth/auth-card.tsx`** - Pre-built sign-in/sign-up card
2. **`src/components/nav-bar.tsx`** - Navigation with user menu dropdown
3. **`src/app/(auth)/sign-in/page.tsx`** - Sign-in page
4. **`src/app/(auth)/sign-up/page.tsx`** - Sign-up page
5. **`src/app/(auth)/layout.tsx`** - Auth pages layout

### Account Management

1. **`src/app/account/layout.tsx`** - Account pages layout with sidebar
2. **`src/app/account/page.tsx`** - Profile management (name, email, avatar)
3. **`src/app/account/security/page.tsx`** - Security settings (password, sessions)
4. **`src/app/api/account/delete/route.tsx`** - Account deletion endpoint

## Project Structure Note

This skill uses paths with `src/` prefix (standard Next.js structure with src directory).

**If your project uses `--no-src-dir` (app and lib in root):**

- Replace `src/lib/` with `lib/`
- Replace `src/app/` with `app/`
- Replace `src/components/` with `components/`
- Replace `src/db/` with `db/`
- Replace `src/emails/` with `emails/`
- Move `src/proxy.ts` to root as `proxy.ts`

## Prerequisites

Before using this skill:

1. **Docker must be running** with PostgreSQL container (dependency: `docker` skill)
2. **env-config skill completed** - Requires `env.ts` and `.env.local` with validation
3. **Recommended: email skill** - Provides email templates and sendEmail function

## Installation

```bash
bun add better-auth @daveyplate/better-auth-ui drizzle-orm postgres drizzle-kit -d
bun add -d @tailwindcss/postcss
```

**Note**: `@tailwindcss/postcss` is required for Tailwind CSS v4.

## Environment Variables

### Update `env.ts`

Add these variables to your environment schema:

```typescript
// In env.ts, add to server object:
server: {
  // ... existing variables
  BETTER_AUTH_SECRET: z.string().min(32),
  BETTER_AUTH_URL: z.string().url(),
  EMAIL_FROM: z.string().email().optional(),
  // Optional OAuth
  GOOGLE_CLIENT_ID: z.string().optional(),
  GOOGLE_CLIENT_SECRET: z.string().optional(),
  GITHUB_CLIENT_ID: z.string().optional(),
  GITHUB_CLIENT_SECRET: z.string().optional(),
},

// Add to runtimeEnv:
runtimeEnv: {
  // ... existing variables
  BETTER_AUTH_SECRET: process.env.BETTER_AUTH_SECRET,
  BETTER_AUTH_URL: process.env.BETTER_AUTH_URL,
  EMAIL_FROM: process.env.EMAIL_FROM,
  GOOGLE_CLIENT_ID: process.env.GOOGLE_CLIENT_ID,
  GOOGLE_CLIENT_SECRET: process.env.GOOGLE_CLIENT_SECRET,
  GITHUB_CLIENT_ID: process.env.GITHUB_CLIENT_ID,
  GITHUB_CLIENT_SECRET: process.env.GITHUB_CLIENT_SECRET,
},
```

### Add to `.env.local`

> **Note:** `EMAIL_FROM` is owned by the `email` skill (applied first in Layer 1). If the `email` skill is already applied, `EMAIL_FROM` is already set — no need to configure it again.

```env
# Auth Core (generate: openssl rand -base64 32)
BETTER_AUTH_SECRET=your-secret-key-here
BETTER_AUTH_URL=http://localhost:3000

# Database
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/store

# Email (for verification/password reset — provided by `email` skill if already applied)
EMAIL_FROM=noreply@example.com
SMTP_HOST=localhost
SMTP_PORT=1025

# Google OAuth (optional)
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=

# GitHub OAuth (optional)
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
```

## Quick Setup

### 1. Create Auth Configuration (`src/lib/auth.tsx`)

**IMPORTANT**: Use `.tsx` extension for JSX support in email templates.

**Email Template Dependencies**: This file requires three email templates:

- `PasswordResetEmail` - For password reset emails
- `VerificationEmail` - For email verification
- `WelcomeEmail` - For new user welcome emails

These should be created using the `email` skill first, or you can create them manually in `src/emails/`.

```tsx
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { db } from "@/db";
import * as schema from "@/db/schema/auth";
import { env } from "@/env";
import { sendEmail } from "@/lib/email";
import { PasswordResetEmail } from "@/emails/password-reset";
import { VerificationEmail } from "@/emails/verification";
import { WelcomeEmail } from "@/emails/welcome";

export const auth = betterAuth({
  database: drizzleAdapter(db, {
    provider: "pg",
    schema,
    debugLogs: true, // Enable for troubleshooting
  }),
  emailAndPassword: {
    enabled: true,
    requireEmailVerification: false, // Set to true in production
    sendResetPassword: async ({ user, url }) => {
      await sendEmail({
        to: user.email,
        subject: "Reset your password",
        template: <PasswordResetEmail url={url} />,
      });
    },
  },
  emailVerification: {
    sendOnSignUp: true,
    autoSignInAfterVerification: true,
    sendVerificationEmail: async ({ user, url }) => {
      await sendEmail({
        to: user.email,
        subject: "Verify your email address",
        template: <VerificationEmail verificationUrl={url} />,
      });
    },
  },
  socialProviders: {
    google: {
      clientId: env.GOOGLE_CLIENT_ID ?? "",
      clientSecret: env.GOOGLE_CLIENT_SECRET ?? "",
      enabled: !!env.GOOGLE_CLIENT_ID,
    },
    github: {
      clientId: env.GITHUB_CLIENT_ID ?? "",
      clientSecret: env.GITHUB_CLIENT_SECRET ?? "",
      enabled: !!env.GITHUB_CLIENT_ID,
    },
  },
  plugins: [
    // Plugins disabled by default - require additional database tables
    // See "Advanced: Plugins" section below
  ],
  user: {
    additionalFields: {
      role: {
        type: "string",
        defaultValue: "member",
        input: false,
      },
    },
  },
  session: {
    expiresIn: 60 * 60 * 24 * 7, // 7 days
    updateAge: 60 * 60 * 24, // 1 day
  },
  account: {
    accountLinking: {
      enabled: true,
      trustedProviders: ["google", "github"],
    },
  },
  databaseHooks: {
    user: {
      create: {
        after: async (user) => {
          await sendEmail({
            to: user.email,
            subject: "Welcome to our platform!",
            template: <WelcomeEmail userName={user.name} loginUrl={env.BETTER_AUTH_URL} />,
          });
        },
      },
    },
  },
  secret: env.BETTER_AUTH_SECRET,
  baseURL: env.BETTER_AUTH_URL,
});

export type Session = typeof auth.$Infer.Session;
export type User = typeof auth.$Infer.Session.user;
```

### 2. Create Auth Client (`src/lib/auth-client.ts`)

```typescript
"use client";

import { createAuthClient } from "better-auth/react";

export const authClient = createAuthClient({
  baseURL: process.env.NEXT_PUBLIC_APP_URL,
  plugins: [],
});

export const {
  signIn,
  signUp,
  signOut,
  useSession,
  getSession,
} = authClient;
```

### 3. Create Auth Guard Helpers (`src/lib/auth-guard.ts`)

```typescript
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

type Session = typeof auth.$Infer.Session;
type User = Session["user"];

type AuthenticatedHandler<T = unknown> = (
  request: NextRequest,
  context: { session: Session; user: User }
) => Promise<NextResponse<T> | Response>;

type RoleGuardOptions = {
  allowedRoles?: string[];
  requireVerifiedEmail?: boolean;
};

/**
 * Wraps an API route handler to require authentication.
 *
 * @example
 * export const GET = withAuth(async (request, { session, user }) => {
 *   return NextResponse.json({ message: `Hello ${user.name}` });
 * });
 */
export function withAuth<T = unknown>(
  handler: AuthenticatedHandler<T>,
  options: RoleGuardOptions = {}
): (request: NextRequest) => Promise<NextResponse | Response> {
  return async (request: NextRequest) => {
    const session = await auth.api.getSession({
      headers: await headers(),
    });

    if (!session) {
      return NextResponse.json(
        { error: "Unauthorized", message: "Authentication required" },
        { status: 401 }
      );
    }

    if (options.requireVerifiedEmail && !session.user.emailVerified) {
      return NextResponse.json(
        { error: "Email not verified" },
        { status: 403 }
      );
    }

    if (options.allowedRoles?.length) {
      const userRole = (session.user as { role?: string }).role ?? "member";
      if (!options.allowedRoles.includes(userRole)) {
        return NextResponse.json(
          { error: "Forbidden", message: "Insufficient permissions" },
          { status: 403 }
        );
      }
    }

    return handler(request, { session, user: session.user });
  };
}

/**
 * Require admin role for route access.
 */
export function withAdmin<T = unknown>(
  handler: AuthenticatedHandler<T>
): (request: NextRequest) => Promise<NextResponse | Response> {
  return withAuth(handler, { allowedRoles: ["admin"] });
}

/**
 * Get current session in server components.
 */
export async function getServerSession(): Promise<Session | null> {
  return auth.api.getSession({
    headers: await headers(),
  });
}

/**
 * Require authentication in server components.
 */
export async function requireAuth(): Promise<{ session: Session; user: User }> {
  const session = await getServerSession();
  if (!session) {
    const { redirect } = await import("next/navigation");
    redirect("/sign-in");
    throw new Error("Unreachable");
  }
  return { session, user: session.user };
}
```

### 4. Create API Route (`src/app/api/auth/[...all]/route.ts`)

```typescript
import { auth } from "@/lib/auth";
import { toNextJsHandler } from "better-auth/next-js";
import type { NextRequest } from "next/server";

const handler = toNextJsHandler(auth);

export async function GET(request: NextRequest) {
  try {
    return await handler.GET(request);
  } catch (error) {
    console.error("[AUTH GET ERROR]", error);
    throw error;
  }
}

export async function POST(request: NextRequest) {
  try {
    return await handler.POST(request);
  } catch (error) {
    console.error("[AUTH POST ERROR]", error);
    throw error;
  }
}
```

### 5. Setup Drizzle Configuration (`drizzle.config.ts`)

Create at project root:

```typescript
import { defineConfig } from "drizzle-kit";
import { config } from "dotenv";

config({ path: ".env.local" });

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/db/schema/*.ts",  // or "./db/schema/*.ts" without src/
  out: "./src/db/migrations",      // or "./db/migrations" without src/
  dbCredentials: {
    url: process.env.DATABASE_URL ?? "",
  },
});
```

### 6. Create Database Client (`src/db/index.ts`)

```typescript
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema/auth";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error("DATABASE_URL is not set");

// Disable prefetch as it's not supported for "Transaction" pool mode
export const client = postgres(connectionString, { prepare: false });
export const db = drizzle(client, { schema });
```

### 7. Create Auth Schema (`src/db/schema/auth.ts`)

```typescript
import {
  pgTable,
  text,
  timestamp,
  boolean,
} from "drizzle-orm/pg-core";

export const user = pgTable("user", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  email: text("email").notNull().unique(),
  emailVerified: boolean("email_verified").notNull().default(false),
  image: text("image"),
  role: text("role").notNull().default("member"),
  normalizedEmail: text("normalized_email").unique(), // For emailHarmony plugin
  createdAt: timestamp("created_at").notNull().defaultNow(),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});

export const session = pgTable("session", {
  id: text("id").primaryKey(),
  expiresAt: timestamp("expires_at").notNull(),
  token: text("token").notNull().unique(),
  ipAddress: text("ip_address"),
  userAgent: text("user_agent"),
  userId: text("user_id")
    .notNull()
    .references(() => user.id, { onDelete: "cascade" }),
  createdAt: timestamp("created_at").notNull().defaultNow(),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});

export const account = pgTable("account", {
  id: text("id").primaryKey(),
  accountId: text("account_id").notNull(),
  providerId: text("provider_id").notNull(),
  userId: text("user_id")
    .notNull()
    .references(() => user.id, { onDelete: "cascade" }),
  accessToken: text("access_token"),
  refreshToken: text("refresh_token"),
  idToken: text("id_token"),
  expiresAt: timestamp("expires_at"),
  password: text("password"),
  createdAt: timestamp("created_at").notNull().defaultNow(),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});

export const verification = pgTable("verification", {
  id: text("id").primaryKey(),
  identifier: text("identifier").notNull(),
  value: text("value").notNull(),
  expiresAt: timestamp("expires_at").notNull(),
  createdAt: timestamp("created_at").notNull().defaultNow(),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});
```

### 8. Create Route Protection (`src/proxy.ts`)

For Next.js 16+, use `proxy.ts` instead of `middleware.ts`:

> **IMPORTANT**: The proxy must short-circuit for non-protected routes to avoid calling `auth.api.getSession()` on every request. Without this, static pages (/, /~offline, etc.) will hang if the database is not running. Also use dynamic `import()` for the auth module to avoid eager initialization.

```typescript
import { headers } from "next/headers";
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

const protectedRoutes = ["/dashboard", "/settings", "/admin", "/chat", "/account"];
const authRoutes = ["/sign-in", "/sign-up", "/forgot-password"];
const adminRoutes = ["/admin"];

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const isProtected = protectedRoutes.some((route) => pathname.startsWith(route));
  const isAuthRoute = authRoutes.some((route) => pathname.startsWith(route));

  // Short-circuit: only check session for routes that need it
  if (!isProtected && !isAuthRoute) {
    return NextResponse.next();
  }

  const { auth } = await import("@/lib/auth");
  const session = await auth.api.getSession({
    headers: await headers(),
  });

  // Redirect to sign-in with callback URL
  if (isProtected && !session) {
    const signInUrl = new URL("/sign-in", request.url);
    signInUrl.searchParams.set("callbackUrl", pathname);
    return NextResponse.redirect(signInUrl);
  }

  // Redirect authenticated users away from auth pages
  if (isAuthRoute && session) {
    return NextResponse.redirect(new URL("/", request.url));
  }

  // Check admin access
  const isAdminRoute = adminRoutes.some((route) => pathname.startsWith(route));
  if (isAdminRoute && (session?.user as { role?: string })?.role !== "admin") {
    return NextResponse.redirect(new URL("/", request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|public).*)"],
};
```

### 9. Create Auth Card Component (`src/components/auth/auth-card.tsx`)

```tsx
"use client";

import {
  AuthUIProvider,
  SignInForm,
  SignUpForm,
} from "@daveyplate/better-auth-ui";
import { authClient } from "@/lib/auth-client";

interface AuthCardProps {
  mode: "sign-in" | "sign-up";
}

export function AuthCard({ mode }: AuthCardProps) {
  return (
    <AuthUIProvider authClient={authClient}>
      {mode === "sign-in" ? (
        <SignInForm localization={{}} />
      ) : (
        <SignUpForm localization={{}} />
      )}
    </AuthUIProvider>
  );
}
```

### 10. Create Auth Pages Layout (`src/app/(auth)/layout.tsx`)

```tsx
export default function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-zinc-50 p-4">
      {children}
    </div>
  );
}
```

### 10b. Create Auth Loading State (`src/app/(auth)/loading.tsx`)

> **Note**: Do NOT use `@phosphor-icons/react` here — `loading.tsx` is a server component, and Phosphor icons use `createContext` which is client-only. Use a CSS spinner instead.

```tsx
export default function AuthLoading() {
  return (
    <div className="flex items-center justify-center p-8">
      <div className="h-8 w-8 animate-spin rounded-full border-4 border-zinc-200 border-t-zinc-600" />
    </div>
  );
}
```

### 11. Create Sign-In Page (`src/app/(auth)/sign-in/page.tsx`)

```tsx
import { AuthCard } from "@/components/auth/auth-card";

export default function SignInPage() {
  return <AuthCard mode="sign-in" />;
}
```

### 12. Create Sign-Up Page (`src/app/(auth)/sign-up/page.tsx`)

```tsx
import { AuthCard } from "@/components/auth/auth-card";

export default function SignUpPage() {
  return <AuthCard mode="sign-up" />;
}
```

### 13. Create NavBar with User Menu (`src/components/nav-bar.tsx`)

```tsx
"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useSession, signOut } from "@/lib/auth-client";

export function NavBar() {
  const router = useRouter();
  const { data: session, isPending } = useSession();
  const [userMenuOpen, setUserMenuOpen] = useState(false);

  const handleSignOut = async () => {
    await signOut();
    router.push("/");
    router.refresh();
  };

  return (
    <nav className="bg-white border-b shadow-sm sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between h-16">
          <div className="flex items-center">
            <Link href="/" className="text-xl font-bold">Logo</Link>
          </div>

          <div className="flex items-center gap-4">
            {isPending ? (
              <div className="w-8 h-8 rounded-full bg-zinc-100 animate-pulse" />
            ) : session ? (
              <div className="relative">
                <button
                  type="button"
                  onClick={() => setUserMenuOpen(!userMenuOpen)}
                  className="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-zinc-50"
                >
                  <div className="w-8 h-8 rounded-full bg-zinc-200 flex items-center justify-center">
                    {session.user.name?.charAt(0).toUpperCase()}
                  </div>
                  <span className="hidden lg:inline">{session.user.name}</span>
                </button>

                {userMenuOpen && (
                  <>
                    {/* biome-ignore lint/a11y/noStaticElementInteractions: backdrop overlay for closing menu */}
                    <div
                      className="fixed inset-0 z-10"
                      onClick={() => setUserMenuOpen(false)}
                      onKeyDown={() => {}}
                      role="presentation"
                    />
                    <div className="absolute right-0 mt-2 w-56 rounded-lg bg-white shadow-lg border z-20">
                      <div className="px-4 py-3 border-b">
                        <p className="font-medium">{session.user.name}</p>
                        <p className="text-xs text-zinc-500">{session.user.email}</p>
                      </div>
                      <div className="py-1">
                        <Link href="/account" className="block px-4 py-2 hover:bg-zinc-50">
                          Account Settings
                        </Link>
                        <Link href="/account/security" className="block px-4 py-2 hover:bg-zinc-50">
                          Security
                        </Link>
                      </div>
                      <div className="border-t py-1">
                        <button
                          type="button"
                          onClick={handleSignOut}
                          className="block w-full text-left px-4 py-2 text-red-600 hover:bg-red-50"
                        >
                          Sign Out
                        </button>
                      </div>
                    </div>
                  </>
                )}
              </div>
            ) : (
              <Link
                href="/sign-in"
                className="px-4 py-2 rounded-lg bg-zinc-900 text-white hover:bg-zinc-800"
              >
                Sign In
              </Link>
            )}
          </div>
        </div>
      </div>
    </nav>
  );
}
```

### 14. Create Account Profile Page (`src/app/account/page.tsx`)

```tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useSession, signOut, authClient } from "@/lib/auth-client";
import { CircleNotch } from "@phosphor-icons/react";

export default function AccountPage() {
  const router = useRouter();
  const { data: session, isPending } = useSession();
  const [isEditing, setIsEditing] = useState(false);
  const [name, setName] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  if (isPending) {
    return (
      <div className="flex items-center justify-center p-8">
        <CircleNotch className="h-6 w-6 animate-spin text-zinc-400" />
      </div>
    );
  }

  if (!session) return null;

  const handleSave = async () => {
    setIsSaving(true);
    try {
      await authClient.updateUser({ name: name.trim() });
      setIsEditing(false);
    } finally {
      setIsSaving(false);
    }
  };

  const handleDelete = async () => {
    if (confirm("Are you sure? This cannot be undone.")) {
      setIsDeleting(true);
      try {
        const response = await fetch("/api/account/delete", { method: "DELETE" });
        if (response.ok) {
          await signOut();
          router.push("/");
        }
      } finally {
        setIsDeleting(false);
      }
    }
  };

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Profile</h1>

      <div className="bg-white rounded-xl border p-6">
        <div className="flex items-center gap-4 mb-6">
          <div className="w-20 h-20 rounded-full bg-zinc-200 flex items-center justify-center text-2xl">
            {session.user.name?.charAt(0).toUpperCase()}
          </div>
          <div>
            <p className="font-medium">{session.user.name}</p>
            <p className="text-sm text-zinc-500">{session.user.email}</p>
          </div>
        </div>

        {isEditing ? (
          <div className="flex gap-2">
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="flex-1 px-4 py-2 border rounded-lg"
            />
            <button onClick={handleSave} disabled={isSaving} className="px-4 py-2 bg-zinc-900 text-white rounded-lg disabled:opacity-50">
              {isSaving ? <CircleNotch className="h-4 w-4 animate-spin" /> : "Save"}
            </button>
            <button onClick={() => setIsEditing(false)} disabled={isSaving} className="px-4 py-2 border rounded-lg">
              Cancel
            </button>
          </div>
        ) : (
          <button onClick={() => { setName(session.user.name); setIsEditing(true); }}>
            Edit Profile
          </button>
        )}
      </div>

      <div className="bg-white rounded-xl border border-red-200 p-6">
        <h2 className="text-lg font-semibold text-red-600 mb-4">Danger Zone</h2>
        <button
          onClick={handleDelete}
          disabled={isDeleting}
          className="px-4 py-2 border border-red-300 text-red-600 rounded-lg hover:bg-red-50 disabled:opacity-50"
        >
          {isDeleting ? <CircleNotch className="h-4 w-4 animate-spin" /> : "Delete Account"}
        </button>
      </div>
    </div>
  );
}
```

### 15. Create Security Page (`src/app/account/security/page.tsx`)

```tsx
"use client";

import { useState, useEffect, useId, useCallback } from "react";
import { useSession, authClient } from "@/lib/auth-client";
import { CircleNotch } from "@phosphor-icons/react";

type SessionData = {
  id: string;
  token: string;
  userAgent?: string | null;
  ipAddress?: string | null;
};

export default function SecurityPage() {
  const { data: session } = useSession();
  const sessionListId = useId();
  const [sessions, setSessions] = useState<SessionData[]>([]);
  const [isChangingPassword, setIsChangingPassword] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [passwordForm, setPasswordForm] = useState({
    currentPassword: "",
    newPassword: "",
    confirmPassword: "",
  });

  const loadSessions = useCallback(async () => {
    const result = await authClient.listSessions();
    if (result.data) setSessions(result.data);
  }, []);

  // biome-ignore lint/correctness/useExhaustiveDependencies: load once on mount
  useEffect(() => {
    loadSessions();
  }, [loadSessions]);

  const handleChangePassword = async () => {
    if (passwordForm.newPassword !== passwordForm.confirmPassword) {
      alert("Passwords do not match");
      return;
    }
    setIsSubmitting(true);
    try {
      await authClient.changePassword({
        currentPassword: passwordForm.currentPassword,
        newPassword: passwordForm.newPassword,
      });
      setIsChangingPassword(false);
      setPasswordForm({ currentPassword: "", newPassword: "", confirmPassword: "" });
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleRevokeSession = async (token: string) => {
    await authClient.revokeSession({ token });
    loadSessions();
  };

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Security</h1>

      {/* Password Section */}
      <div className="bg-white rounded-xl border p-6">
        <h2 className="text-lg font-semibold mb-4">Password</h2>
        {isChangingPassword ? (
          <div className="space-y-4 max-w-md">
            <input
              type="password"
              placeholder="Current Password"
              value={passwordForm.currentPassword}
              onChange={(e) => setPasswordForm({ ...passwordForm, currentPassword: e.target.value })}
              className="w-full px-4 py-2 border rounded-lg"
            />
            <input
              type="password"
              placeholder="New Password"
              value={passwordForm.newPassword}
              onChange={(e) => setPasswordForm({ ...passwordForm, newPassword: e.target.value })}
              className="w-full px-4 py-2 border rounded-lg"
            />
            <input
              type="password"
              placeholder="Confirm Password"
              value={passwordForm.confirmPassword}
              onChange={(e) => setPasswordForm({ ...passwordForm, confirmPassword: e.target.value })}
              className="w-full px-4 py-2 border rounded-lg"
            />
            <div className="flex gap-2">
              <button onClick={handleChangePassword} disabled={isSubmitting} className="px-4 py-2 bg-zinc-900 text-white rounded-lg disabled:opacity-50">
                {isSubmitting ? <CircleNotch className="h-4 w-4 animate-spin" /> : "Update"}
              </button>
              <button onClick={() => setIsChangingPassword(false)} disabled={isSubmitting} className="px-4 py-2 border rounded-lg">
                Cancel
              </button>
            </div>
          </div>
        ) : (
          <button onClick={() => setIsChangingPassword(true)} className="px-4 py-2 border rounded-lg">
            Change Password
          </button>
        )}
      </div>

      {/* Sessions Section */}
      <div className="bg-white rounded-xl border p-6">
        <h2 className="text-lg font-semibold mb-4">Active Sessions</h2>
        <div className="space-y-4">
          {sessions.map((s: SessionData) => (
            <div key={`${sessionListId}-${s.id}`} className="flex items-center justify-between p-4 border rounded-lg">
              <div>
                <p className="font-medium">{s.userAgent || "Unknown device"}</p>
                <p className="text-sm text-zinc-500">{s.ipAddress || "Unknown IP"}</p>
              </div>
              {session?.session.token !== s.token && (
                <button
                  onClick={() => handleRevokeSession(s.token)}
                  className="text-red-600 hover:text-red-700"
                >
                  Revoke
                </button>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
```

### 16. Create Account Deletion API (`src/app/api/account/delete/route.tsx`)

```tsx
import { NextResponse } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/db";
import { user, session, account } from "@/db/schema/auth";
import { eq } from "drizzle-orm";

export const DELETE = withAuth(async (request, { user: currentUser }) => {
  try {
    const userId = currentUser.id;

    // Delete in order to respect foreign key constraints
    await db.delete(session).where(eq(session.userId, userId));
    await db.delete(account).where(eq(account.userId, userId));
    await db.delete(user).where(eq(user.id, userId));

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("[ACCOUNT DELETE ERROR]", error);
    return NextResponse.json({ error: "Failed to delete account" }, { status: 500 });
  }
});
```

## OAuth Provider Setup

### Google OAuth

1. Go to [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Create OAuth 2.0 credentials
3. Add redirect URI: `http://localhost:3000/api/auth/callback/google`
4. Copy Client ID and Secret to `.env.local`

### GitHub OAuth

1. Go to [GitHub Developer Settings](https://github.com/settings/developers)
2. Create OAuth App
3. Set callback URL: `http://localhost:3000/api/auth/callback/github`
4. Copy Client ID and Secret to `.env.local`

## Using Protected Routes

### In API Routes

```typescript
import { withAuth, withAdmin, withRoles } from "@/lib/auth-guard";
import { NextResponse } from "next/server";

// Require authentication
export const GET = withAuth(async (request, { user }) => {
  return NextResponse.json({ userId: user.id });
});

// Require admin role
export const DELETE = withAdmin(async (request, { user }) => {
  return NextResponse.json({ deleted: true });
});

// Require specific roles
export const POST = withRoles(["admin", "moderator"], async (request, { user }) => {
  return NextResponse.json({ success: true });
});
```

### In Server Components

```tsx
import { requireAuth, getServerSession } from "@/lib/auth-guard";
import { redirect } from "next/navigation";

export default async function ProtectedPage() {
  const { user } = await requireAuth();
  return <div>Hello {user.name}</div>;
}

// Or check manually
export default async function OptionalAuthPage() {
  const session = await getServerSession();
  if (!session) redirect("/sign-in");
  return <div>Hello {session.user.name}</div>;
}
```

## Verification and Migration

Before pushing to the database, verify TypeScript compilation:

```bash
# 1. TypeScript type check (recommended)
bunx tsc --noEmit

# 2. Push schema to database
bunx drizzle-kit push

# 3. Start dev server
bun run dev
```

## Testing Without OAuth

For initial testing, focus on email/password authentication:

1. Leave OAuth provider environment variables empty in `.env.local`
2. OAuth providers will be automatically disabled if credentials are not provided
3. Social login buttons won't appear in the better-auth UI
4. Test with sign-up at `http://localhost:3000/sign-up`
5. Once working, add OAuth credentials to enable social login

## Advanced: Plugins (Optional)

Plugins require additional database tables. Only enable after setup.

### emailHarmony Plugin

Normalizes emails (handles gmail dots, plus addressing).

1. Schema already includes `normalizedEmail` column
2. Enable in auth.tsx:

```typescript
import { emailHarmony } from "better-auth-harmony";
plugins: [emailHarmony()]
```

### Organization Plugin (Multi-tenant)

1. Generate tables: `bunx @better-auth/cli generate`
2. Enable in auth.tsx:

```typescript
import { organization } from "better-auth/plugins";
plugins: [organization({ allowUserToCreateOrganization: true })]
```

3. Enable in auth-client.ts:

```typescript
import { organizationClient } from "better-auth/client/plugins";
plugins: [organizationClient()]
```

## Dev Workflow

For quick development sign-in (seed users + one-click sign-in buttons), see the **auth-dev skill**. It creates a `/dev` page and seed API endpoint so you can instantly authenticate as any role during development.

## E2E Testing with Playwright

For testing protected pages and authentication flows with Playwright, see the **e2e skill** which includes:

- **API-based authentication** - Fast auth setup via `/api/auth/sign-in/email`
- **Multi-role storage states** - member, admin, subscribed user contexts
- **Auth fixtures** - `authenticatedPage`, `adminPage`, `pageWithRole()` helpers
- **Test user seeding** - Uses the same `auth-seed.ts` users

### Quick Setup

1. **Seed test users** (run once):

```bash
bun run seed/auth-seed.ts
```

1. **Create auth storage states**:

```bash
bunx playwright test --project=auth-setup
```

1. **Run authenticated tests**:

```bash
bunx playwright test --project=chromium-authenticated
```

### Testing Protected Routes

```typescript
// e2e/specs/dashboard.spec.ts
import { test, expect, getSession } from '../fixtures/auth';

test('authenticated user can access dashboard', async ({ authenticatedPage }) => {
  await authenticatedPage.goto('/dashboard');

  // Verify we're authenticated
  const session = await getSession(authenticatedPage);
  expect(session?.user.email).toBeTruthy();
});

test('admin can access admin panel', async ({ adminPage }) => {
  await adminPage.goto('/admin');
  await expect(adminPage).toHaveURL(/admin/);
});
```

### Test User Credentials

Default seeded users (from `auth-seed.ts`):

| Role       | Email                   | Password       |
|------------|-------------------------|----------------|
| admin      | <admin@example.com>       | Admin123!      |
| member     | <member@example.com>      | Member123!     |
| subscribed | <subscribed@example.com>  | Subscribed123! |
| guest      | <guest@example.com>       | Guest123!      |

### Seeding Test Users (`seed/auth-seed.ts`)

> **CRITICAL**: better-auth's password hashing has a subtle implementation detail.
> It passes the **hex-encoded salt STRING** to scrypt, **not the raw bytes**.
> Getting this wrong will cause `INVALID_EMAIL_OR_PASSWORD` errors during login.

```typescript
import { scrypt } from "@noble/hashes/scrypt.js";
import { randomBytes } from "node:crypto";
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { user, account } from "../src/db/schema/auth";
import { eq } from "drizzle-orm";

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error("DATABASE_URL required");
  process.exit(1);
}

const client = postgres(DATABASE_URL);
const db = drizzle(client);

const testUsers = [
  { email: "admin@example.com", password: "Admin123!", name: "Admin User", role: "admin" },
  { email: "member@example.com", password: "Member123!", name: "Member User", role: "member" },
  { email: "subscribed@example.com", password: "Subscribed123!", name: "Subscribed User", role: "subscribed" },
] as const;

/**
 * Hash password compatible with better-auth verification
 *
 * CRITICAL IMPLEMENTATION DETAIL:
 * better-auth uses: N=16384, r=16, p=1, dkLen=64
 * BUT: it passes the HEX STRING of the salt to scrypt, NOT raw bytes!
 * Format: ${saltHex}:${keyHex}
 */
function hashPassword(password: string): string {
  // Generate 16 random bytes and hex-encode them
  const saltBytes = randomBytes(16);
  const saltHex = Buffer.from(saltBytes).toString("hex");

  // CRITICAL: better-auth passes the hex string as salt, not raw bytes
  // Also normalize password the same way better-auth does
  const normalizedPassword = password.normalize("NFKC");

  const key = scrypt(normalizedPassword, saltHex, {
    N: 16384,
    r: 16,
    p: 1,
    dkLen: 64,
    maxmem: 128 * 16384 * 16 * 2, // Same maxmem as better-auth
  });

  const keyHex = Buffer.from(key).toString("hex");
  return `${saltHex}:${keyHex}`;
}

function generateId(): string {
  return randomBytes(16).toString("hex");
}

async function seed() {
  console.log("Seeding test users...\n");

  for (const testUser of testUsers) {
    const userId = generateId();
    const accountId = generateId();
    const hashedPassword = hashPassword(testUser.password);

    const existingUser = await db
      .select()
      .from(user)
      .where(eq(user.email, testUser.email))
      .limit(1);

    if (existingUser.length > 0) {
      // Update existing user's password
      await db
        .update(account)
        .set({ password: hashedPassword, updatedAt: new Date() })
        .where(eq(account.userId, existingUser[0].id));
      console.log(`  Updated: ${testUser.email}`);
    } else {
      // Create new user
      await db.insert(user).values({
        id: userId,
        name: testUser.name,
        email: testUser.email,
        emailVerified: true,
        role: testUser.role,
        normalizedEmail: testUser.email.toLowerCase(),
        createdAt: new Date(),
        updatedAt: new Date(),
      });

      await db.insert(account).values({
        id: accountId,
        accountId: userId,
        providerId: "credential",
        userId: userId,
        password: hashedPassword,
        createdAt: new Date(),
        updatedAt: new Date(),
      });
      console.log(`  Created: ${testUser.email}`);
    }
  }

  console.log("\n✅ Test users seeded!");
}

seed()
  .catch(console.error)
  .finally(() => client.end());
```

Add to `package.json`:

```json
{
  "scripts": {
    "seed:auth": "bun run seed/auth-seed.ts"
  }
}
```

### Environment Variables for Testing

```bash
# .env.test
TEST_USER_EMAIL=member@example.com
TEST_USER_PASSWORD=Member123!
TEST_ADMIN_EMAIL=admin@example.com
TEST_ADMIN_PASSWORD=Admin123!
```

## Troubleshooting

### 403 MISSING_OR_NULL_ORIGIN (Playwright API auth)

**Symptoms**: API-based auth in Playwright fails with `403 FORBIDDEN - MISSING_OR_NULL_ORIGIN`

**Cause**: better-auth validates the `Origin` header for CORS/security.

**Fix**: Always include `Origin` header in fetch requests to better-auth endpoints:

```typescript
const response = await fetch(`${baseURL}/api/auth/sign-in/email`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Origin': baseURL,              // Required!
    'Referer': `${baseURL}/sign-in`,
  },
  body: JSON.stringify({ email, password }),
});
```

### 401 INVALID_EMAIL_OR_PASSWORD (seeded test users)

**Symptoms**: Auth fails with `INVALID_EMAIL_OR_PASSWORD` even though users exist in DB.

**Cause**: Password hashing doesn't match better-auth's algorithm.

**Root cause**: better-auth passes the **hex-encoded salt string** to scrypt, not raw bytes.

**Fix**: Update your seed script:

```typescript
// WRONG - passing raw salt bytes
const key = scrypt(password, saltBytes, { N: 16384, r: 16, p: 1, dkLen: 64 });

// CORRECT - passing hex string salt
const normalizedPassword = password.normalize("NFKC");
const key = scrypt(normalizedPassword, saltHex, { N: 16384, r: 16, p: 1, dkLen: 64, maxmem: 128 * 16384 * 16 * 2 });
```

### Sign-up fails silently (422 or 500 errors)

**Symptoms**: Form submits but nothing happens. Network tab shows 422 or 500.

**Common causes**:

1. **Plugins enabled without required tables**: Disable all plugins and try again
2. **Missing database columns**: Run `bunx drizzle-kit push`
3. **Database connection issues**: Check `DATABASE_URL`

**Debug**:

```bash
# Check server logs for [AUTH POST ERROR]
# Verify database
psql $DATABASE_URL -c "\d user"
```

### "INVALID_EMAIL" error

**Cause**: `emailHarmony()` plugin enabled but `normalized_email` column missing.

**Fix**: Either add the column or disable the plugin.

### "FAILED_TO_CREATE_USER" error

**Cause**: Plugin requires database tables that don't exist.

**Fix**: Disable plugins or run `bunx @better-auth/cli generate`.

### Role not available on user type

The `role` field is added via `additionalFields`, so TypeScript doesn't include it in the base type. Use type assertion:

```typescript
const userRole = (session.user as { role?: string }).role ?? "member";
```
