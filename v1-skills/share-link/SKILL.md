---
name: share-link
description: Token-based public sharing — create, access, and revoke shareable URLs for private content with optional expiry. Use this skill when the user says "add share link", "public sharing", "shareable url", "share with client", or "public link".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: [auth, db, env-config]
---

# Share Link

Token-based public sharing system that lets authenticated users generate shareable URLs for private content. Tokens are URL-safe, 12 characters, and support optional expiry and view-count limits. Revocation sets a `revokedAt` timestamp so history is preserved.

## Prerequisites

- Next.js app with App Router (no `src/` directory)
- `@/lib/auth` exporting `auth` (better-auth)
- `@/db` exporting `db` (Drizzle + Postgres)
- `db/schema/index.ts` exporting all schema tables
- `NEXT_PUBLIC_APP_URL` set in environment

## Installation

No new packages required. Uses Node.js built-in `crypto`.

## What Gets Created

```
app/
└── api/
    └── share/
        ├── route.ts            POST create link, GET list my links
        └── [token]/
            └── route.ts        GET public access, DELETE revoke
db/
└── schema/
    └── shared-links.ts
lib/
└── share-link/
    └── index.ts
```

## Setup Steps

### Step 1: Create `db/schema/shared-links.ts`

```typescript
import { integer, jsonb, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core"

export const sharedLinks = pgTable("shared_links", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull(),
  token: text("token").notNull().unique(),
  resourceType: text("resource_type").notNull(),
  resourceId: text("resource_id").notNull(),
  resourceData: jsonb("resource_data").notNull(),
  label: text("label"),
  expiresAt: timestamp("expires_at"),
  viewCount: integer("view_count").default(0).notNull(),
  maxViews: integer("max_views"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  revokedAt: timestamp("revoked_at"),
})
```

### Step 2: Export from `db/schema/index.ts`

Add this export to your existing `db/schema/index.ts`:

```typescript
export * from "./shared-links"
```

### Step 3: Create `lib/share-link/index.ts`

```typescript
import type { sharedLinks } from "@/db/schema"
import type { InferSelectModel } from "drizzle-orm"

export type ShareLink = InferSelectModel<typeof sharedLinks>

export function generateShareUrl(token: string): string {
  const base = process.env.NEXT_PUBLIC_APP_URL ?? ""
  return `${base}/share/${token}`
}

export function isExpired(link: ShareLink): boolean {
  if (!link.expiresAt) return false
  return link.expiresAt < new Date()
}

export function isRevoked(link: ShareLink): boolean {
  return link.revokedAt !== null
}

export function isOverLimit(link: ShareLink): boolean {
  if (link.maxViews === null || link.maxViews === undefined) return false
  return link.viewCount >= link.maxViews
}

export function isAccessible(link: ShareLink): boolean {
  return !isRevoked(link) && !isExpired(link) && !isOverLimit(link)
}
```

### Step 4: Create `app/api/share/route.ts`

```typescript
import { db } from "@/db"
import { sharedLinks } from "@/db/schema"
import { auth } from "@/lib/auth"
import { generateShareUrl } from "@/lib/share-link"
import { eq, and, isNull, or, gt } from "drizzle-orm"
import { headers } from "next/headers"
import { NextResponse } from "next/server"
import { randomBytes } from "node:crypto"

function generateToken(): string {
  return randomBytes(9).toString("base64url")
}

export async function POST(request: Request): Promise<NextResponse> {
  const session = await auth.api.getSession({ headers: await headers() })
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: unknown
  try {
    body = await request.json()
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 })
  }

  const parsed = body as Record<string, unknown>

  if (
    typeof parsed.resourceType !== "string" ||
    typeof parsed.resourceId !== "string" ||
    parsed.resourceData === undefined
  ) {
    return NextResponse.json(
      { error: "resourceType, resourceId, and resourceData are required" },
      { status: 400 },
    )
  }

  const token = generateToken()
  const expiresAt =
    typeof parsed.expiresAt === "string" ? new Date(parsed.expiresAt) : null
  const maxViews =
    typeof parsed.maxViews === "number" ? parsed.maxViews : null
  const label =
    typeof parsed.label === "string" ? parsed.label : null

  const [row] = await db
    .insert(sharedLinks)
    .values({
      userId: session.user.id,
      token,
      resourceType: parsed.resourceType,
      resourceId: parsed.resourceId,
      resourceData: parsed.resourceData as Record<string, unknown>,
      label,
      expiresAt,
      maxViews,
    })
    .returning({
      id: sharedLinks.id,
      token: sharedLinks.token,
      expiresAt: sharedLinks.expiresAt,
    })

  return NextResponse.json({
    id: row.id,
    token: row.token,
    url: generateShareUrl(row.token),
    expiresAt: row.expiresAt,
  })
}

export async function GET(): Promise<NextResponse> {
  const session = await auth.api.getSession({ headers: await headers() })
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const now = new Date()

  const links = await db
    .select()
    .from(sharedLinks)
    .where(
      and(
        eq(sharedLinks.userId, session.user.id),
        isNull(sharedLinks.revokedAt),
        or(isNull(sharedLinks.expiresAt), gt(sharedLinks.expiresAt, now)),
      ),
    )

  const result = links.map((link) => ({
    ...link,
    url: generateShareUrl(link.token),
  }))

  return NextResponse.json(result)
}
```

### Step 5: Create `app/api/share/[token]/route.ts`

```typescript
import { db } from "@/db"
import { sharedLinks } from "@/db/schema"
import { auth } from "@/lib/auth"
import { isAccessible, isExpired, isOverLimit, isRevoked } from "@/lib/share-link"
import { eq } from "drizzle-orm"
import { headers } from "next/headers"
import { NextResponse } from "next/server"

type RouteContext = {
  params: Promise<{ token: string }>
}

export async function GET(
  _request: Request,
  { params }: RouteContext,
): Promise<NextResponse> {
  const { token } = await params

  const [link] = await db
    .select()
    .from(sharedLinks)
    .where(eq(sharedLinks.token, token))
    .limit(1)

  if (!link) {
    return NextResponse.json({ error: "Not found" }, { status: 404 })
  }

  if (isRevoked(link) || isExpired(link)) {
    return NextResponse.json(
      { error: "This link has expired or been revoked" },
      { status: 410 },
    )
  }

  if (isOverLimit(link)) {
    return NextResponse.json(
      { error: "This link has reached its maximum view count" },
      { status: 429 },
    )
  }

  await db
    .update(sharedLinks)
    .set({ viewCount: (link.viewCount ?? 0) + 1 })
    .where(eq(sharedLinks.token, token))

  return NextResponse.json({
    resourceType: link.resourceType,
    resourceId: link.resourceId,
    resourceData: link.resourceData,
    label: link.label,
    viewCount: (link.viewCount ?? 0) + 1,
    createdAt: link.createdAt,
  })
}

export async function DELETE(
  _request: Request,
  { params }: RouteContext,
): Promise<NextResponse> {
  const session = await auth.api.getSession({ headers: await headers() })
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { token } = await params

  const [link] = await db
    .select()
    .from(sharedLinks)
    .where(eq(sharedLinks.token, token))
    .limit(1)

  if (!link) {
    return NextResponse.json({ error: "Not found" }, { status: 404 })
  }

  if (link.userId !== session.user.id) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 })
  }

  await db
    .update(sharedLinks)
    .set({ revokedAt: new Date() })
    .where(eq(sharedLinks.token, token))

  return NextResponse.json({ success: true })
}
```

### Step 6: Push the schema

```bash
bunx drizzle-kit push
```

## Usage

```typescript
// Create a share link (authenticated)
const res = await fetch("/api/share", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    resourceType: "storyboard",
    resourceId: "abc123",
    resourceData: { title: "My Storyboard", shots: [] },
    label: "Client Review Draft",
    expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    maxViews: 50,
  }),
})
const { token, url } = await res.json()
// url => "https://myapp.com/share/aB3xY9mK2pQ"

// Access publicly (no auth)
const data = await fetch(`/api/share/${token}`).then((r) => r.json())
// data => { resourceType, resourceId, resourceData, label, viewCount, createdAt }

// List my links (authenticated)
const links = await fetch("/api/share").then((r) => r.json())

// Revoke (authenticated, must own)
await fetch(`/api/share/${token}`, { method: "DELETE" })

// Helpers
import { generateShareUrl, isAccessible, isExpired, isRevoked } from "@/lib/share-link"

generateShareUrl("aB3xY9mK2pQ") // => "https://myapp.com/share/aB3xY9mK2pQ"
```

## Acceptance Criteria

- POST `/api/share` (authenticated) returns `{ token, url, id, expiresAt }`
- POST `/api/share` returns 401 when called without a session
- GET `/api/share/[token]` (unauthenticated) returns resource data and increments `viewCount`
- GET `/api/share/[token]` returns 404 for unknown tokens
- GET `/api/share/[token]` returns 410 after the link is revoked via DELETE
- GET `/api/share/[token]` returns 410 when `expiresAt` is in the past
- GET `/api/share/[token]` returns 429 when `viewCount >= maxViews`
- DELETE `/api/share/[token]` returns 403 when called by a user who does not own the link
- Token is exactly 12 characters and URL-safe (base64url alphabet)
- GET `/api/share` returns only non-revoked, non-expired links for the authenticated user
- `bunx drizzle-kit push` completes without errors
- `tsc --noEmit` passes with no errors
- `bun run build` succeeds
