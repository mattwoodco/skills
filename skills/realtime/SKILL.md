---
name: realtime
description: Real-time collaboration with Liveblocks — presence cursors, conflict-free state sync, and room-based access. Use this skill when the user says "add realtime", "setup collaboration", "add liveblocks", "multiplayer", "live cursors", or "real-time sync".
author: "@mattwoodco"
version: 1.1.0
created: 2026-02-13
updated: 2026-02-19
dependencies: [auth, env-config]
---

# Real-time Collaboration (Liveblocks)

Real-time collaboration using [Liveblocks](https://liveblocks.io). Room-based presence (cursors + avatars), conflict-free state synchronization via CRDT storage, and authenticated room access. Designed to integrate with any canvas or collaborative UI.

## Prerequisites

- Next.js app with App Router (no `src/` directory)
- `auth` skill applied (for user authentication)
- `env-config` skill applied

## Installation

```bash
bun add @liveblocks/react @liveblocks/node
```

## Environment Variables

Add to `.env.local`:

```env
# Liveblocks
LIVEBLOCKS_SECRET_KEY=sk_dev_...
NEXT_PUBLIC_LIVEBLOCKS_PUBLIC_KEY=pk_dev_...
```

Add to `env.ts`:

```typescript
// Server schema
LIVEBLOCKS_SECRET_KEY: z.string().startsWith("sk_"),

// Client schema
NEXT_PUBLIC_LIVEBLOCKS_PUBLIC_KEY: z.string().startsWith("pk_"),
```

## What Gets Created

```
app/
└── api/
    └── liveblocks/
        └── auth/
            └── route.ts               # POST: authenticate user for room access
lib/
└── realtime/
    └── types.ts                       # Presence, Storage, UserMeta types
components/
└── realtime/
    ├── room-provider.tsx              # Liveblocks RoomProvider wrapper
    ├── cursors.tsx                    # Live cursor overlay with user avatars
    └── presence-bar.tsx               # "N users online" indicator
liveblocks.config.ts                   # Root-level Liveblocks type configuration
```

## Setup Steps

### Step 1: Create `liveblocks.config.ts` (project root)

```typescript
declare global {
  interface Liveblocks {
    Presence: {
      cursor: { x: number; y: number } | null;
      name: string;
      avatar: string;
      color: string;
    };
    Storage: Record<string, never>;
    UserMeta: {
      id: string;
      info: {
        name: string;
        email: string;
        avatar: string;
        color: string;
      };
    };
    RoomEvent: Record<string, never>;
    ThreadMetadata: Record<string, never>;
    RoomInfo: Record<string, never>;
  }
}

export {};
```

### Step 2: Create `lib/realtime/types.ts`

```typescript
export type CursorPosition = {
  x: number;
  y: number;
};

export type UserPresence = {
  cursor: CursorPosition | null;
  name: string;
  avatar: string;
  color: string;
};

export type RoomUser = {
  id: string;
  name: string;
  email: string;
  avatar: string;
  color: string;
};

// Predefined user colors for presence
export const USER_COLORS = [
  "#ef4444", "#f97316", "#eab308", "#22c55e",
  "#06b6d4", "#3b82f6", "#8b5cf6", "#ec4899",
] as const;

export function getUserColor(userId: string): string {
  let hash = 0;
  for (let i = 0; i < userId.length; i++) {
    hash = userId.charCodeAt(i) + ((hash << 5) - hash);
  }
  return USER_COLORS[Math.abs(hash) % USER_COLORS.length];
}
```

### Step 3: Create `app/api/liveblocks/auth/route.ts`

```typescript
import { NextResponse } from "next/server";
import { Liveblocks } from "@liveblocks/node";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import { getUserColor } from "@/lib/realtime/types";

const liveblocks = new Liveblocks({
  secret: process.env.LIVEBLOCKS_SECRET_KEY ?? "",
});

export async function POST(request: Request) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });

  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const user = session.user;

  const liveblocksSession = liveblocks.prepareSession(user.id, {
    userInfo: {
      name: user.name ?? "Anonymous",
      email: user.email,
      avatar: user.image ?? "",
      color: getUserColor(user.id),
    },
  });

  // Parse the request body to get the room ID
  const body = await request.json();
  const { room } = body as { room: string };

  if (room) {
    // Grant full access to the requested room
    liveblocksSession.allow(room, liveblocksSession.FULL_ACCESS);
  }

  const { status, body: responseBody } = await liveblocksSession.authorize();

  return new NextResponse(responseBody, { status });
}
```

### Step 4: Create `components/realtime/room-provider.tsx`

```typescript
"use client";

import type { ReactNode } from "react";
import { LiveblocksProvider, RoomProvider, ClientSideSuspense } from "@liveblocks/react";

type RealtimeRoomProps = {
  roomId: string;
  children: ReactNode;
  fallback?: ReactNode;
  initialPresence?: Partial<Liveblocks["Presence"]>;
};

export function RealtimeRoom({
  roomId,
  children,
  fallback,
  initialPresence,
}: RealtimeRoomProps) {
  return (
    <LiveblocksProvider authEndpoint="/api/liveblocks/auth">
      <RoomProvider
        id={roomId}
        initialPresence={{
          cursor: null,
          name: "",
          avatar: "",
          color: "#3b82f6",
          ...initialPresence,
        }}
      >
        <ClientSideSuspense
          fallback={fallback ?? <div className="animate-pulse p-4">Connecting...</div>}
        >
          {children}
        </ClientSideSuspense>
      </RoomProvider>
    </LiveblocksProvider>
  );
}
```

### Step 5: Create `components/realtime/cursors.tsx`

```typescript
"use client";

import { useCallback, useRef } from "react";
import { useOthers, useUpdateMyPresence } from "@liveblocks/react";

type CursorsProps = {
  containerRef: React.RefObject<HTMLElement | null>;
};

export function Cursors({ containerRef }: CursorsProps) {
  const others = useOthers();
  const updateMyPresence = useUpdateMyPresence();
  const rafRef = useRef<number | null>(null);

  const handlePointerMove = useCallback(
    (e: React.PointerEvent) => {
      const container = containerRef.current;
      if (!container) return;

      const clientX = e.clientX;
      const clientY = e.clientY;

      if (rafRef.current !== null) return;
      rafRef.current = requestAnimationFrame(() => {
        rafRef.current = null;
        const rect = container.getBoundingClientRect();
        updateMyPresence({ cursor: { x: clientX - rect.left, y: clientY - rect.top } });
      });
    },
    [containerRef, updateMyPresence]
  );

  const handlePointerLeave = useCallback(() => {
    updateMyPresence({ cursor: null });
  }, [updateMyPresence]);

  return (
    <div
      className="absolute inset-0 pointer-events-auto"
      onPointerMove={handlePointerMove}
      onPointerLeave={handlePointerLeave}
      style={{ zIndex: 50 }}
    >
      {others.map(({ connectionId, presence, info }) => {
        if (!presence.cursor) return null;

        return (
          <div
            key={connectionId}
            className="absolute pointer-events-none transition-transform duration-75"
            style={{
              left: presence.cursor.x,
              top: presence.cursor.y,
              transform: "translate(-2px, -2px)",
            }}
          >
            {/* Cursor arrow */}
            <svg
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              style={{ filter: "drop-shadow(0 1px 2px rgba(0,0,0,0.3))" }}
            >
              <path
                d="M5 3L19 12L12 12L8 20L5 3Z"
                fill={info.color}
                stroke="white"
                strokeWidth="1.5"
              />
            </svg>
            {/* Name label */}
            <div
              className="absolute left-5 top-4 whitespace-nowrap rounded-full px-2 py-0.5 text-xs text-white shadow-sm"
              style={{ backgroundColor: info.color }}
            >
              {info.name}
            </div>
          </div>
        );
      })}
    </div>
  );
}

export function useCursorTracking(containerRef: React.RefObject<HTMLElement | null>) {
  const updateMyPresence = useUpdateMyPresence();

  const handlePointerMove = useCallback(
    (e: React.PointerEvent) => {
      const container = containerRef.current;
      if (!container) return;

      const rect = container.getBoundingClientRect();
      updateMyPresence({
        cursor: {
          x: e.clientX - rect.left,
          y: e.clientY - rect.top,
        },
      });
    },
    [containerRef, updateMyPresence]
  );

  const handlePointerLeave = useCallback(() => {
    updateMyPresence({ cursor: null });
  }, [updateMyPresence]);

  return { handlePointerMove, handlePointerLeave };
}
```

### Step 6: Create `components/realtime/presence-bar.tsx`

```typescript
"use client";

import { useOthers, useSelf } from "@liveblocks/react";

export function PresenceBar() {
  const others = useOthers();
  const self = useSelf();

  const allUsers = [
    ...(self ? [{ id: self.id, info: self.info, isSelf: true }] : []),
    ...others.map((other) => ({
      id: other.id,
      info: other.info,
      isSelf: false,
    })),
  ];

  return (
    <div className="flex items-center gap-2">
      <div className="flex -space-x-2">
        {allUsers.slice(0, 5).map((user) => (
          <div
            key={user.id}
            className="relative h-8 w-8 rounded-full border-2 border-background"
            style={{ backgroundColor: user.info.color }}
            title={`${user.info.name}${user.isSelf ? " (you)" : ""}`}
          >
            {user.info.avatar ? (
              <img
                src={user.info.avatar}
                alt={user.info.name}
                className="h-full w-full rounded-full object-cover"
              />
            ) : (
              <span className="flex h-full w-full items-center justify-center text-xs font-medium text-white">
                {user.info.name.charAt(0).toUpperCase()}
              </span>
            )}
          </div>
        ))}
      </div>
      {allUsers.length > 5 && (
        <span className="text-xs text-muted-foreground">
          +{allUsers.length - 5} more
        </span>
      )}
      <span className="text-xs text-muted-foreground">
        {allUsers.length} {allUsers.length === 1 ? "user" : "users"} online
      </span>
    </div>
  );
}
```

## Usage

### Wrap a page with real-time

The multiplayer wrapper should export the `isLiveblocksConfigured` flag so that the parent page can show a "Local" badge when Liveblocks is not configured (instead of a full header bar which wastes vertical space).

```tsx
// components/realtime/multiplayer-wrapper.tsx
"use client";

import { RealtimeRoom } from "@/components/realtime/room-provider";

export const isLiveblocksConfigured =
  !!process.env.NEXT_PUBLIC_LIVEBLOCKS_PUBLIC_KEY;

type MultiplayerWrapperProps = {
  roomId: string;
  children: React.ReactNode;
};

export function MultiplayerWrapper({ roomId, children }: MultiplayerWrapperProps) {
  if (!isLiveblocksConfigured) {
    return <>{children}</>;
  }

  return (
    <RealtimeRoom roomId={roomId}>
      {children}
    </RealtimeRoom>
  );
}
```

Then in the page, show a compact "Local" badge next to the title when Liveblocks is not configured:

```tsx
// app/workspace/[id]/page.tsx
import { isLiveblocksConfigured, MultiplayerWrapper } from "@/components/realtime/multiplayer-wrapper";
import { PresenceBar } from "@/components/realtime/presence-bar";

export default async function WorkspacePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <MultiplayerWrapper roomId={`workspace-${id}`}>
      <div className="flex flex-col h-screen">
        <header className="flex items-center justify-between p-4 border-b">
          <div className="flex items-center gap-2">
            <h1>Workspace</h1>
            {!isLiveblocksConfigured && (
              <span className="rounded-md bg-muted px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground">
                Local
              </span>
            )}
          </div>
          {isLiveblocksConfigured && <PresenceBar />}
        </header>
        <main className="flex-1 relative">
          {/* Your collaborative content here */}
        </main>
      </div>
    </MultiplayerWrapper>
  );
}
```

**Why a badge instead of a header bar?** The old pattern used a full-width "Local mode" bar above the content, wasting 40px of vertical space. A small badge next to the title communicates the same information without layout cost.

### Add live cursors to a container

```tsx
"use client";

import { useRef } from "react";
import { Cursors } from "@/components/realtime/cursors";

export function CollaborativeCanvas() {
  const containerRef = useRef<HTMLDivElement>(null);

  return (
    <div ref={containerRef} className="relative w-full h-full">
      <Cursors containerRef={containerRef} />
      {/* Your canvas/content here */}
    </div>
  );
}
```

### Use cursor tracking hook directly

```tsx
"use client";

import { useRef } from "react";
import { useCursorTracking } from "@/components/realtime/cursors";

export function MyComponent() {
  const ref = useRef<HTMLDivElement>(null);
  const { handlePointerMove, handlePointerLeave } = useCursorTracking(ref);

  return (
    <div
      ref={ref}
      onPointerMove={handlePointerMove}
      onPointerLeave={handlePointerLeave}
    >
      Content here
    </div>
  );
}
```

## Acceptance Criteria

- RoomProvider connects to Liveblocks successfully
- `/api/liveblocks/auth` authenticates users and grants room access
- Live cursors appear for other users in the same room
- PresenceBar shows connected users with avatars
- Cursor position updates in real-time (< 100ms latency)
- User disconnection removes their cursor
- When Liveblocks is not configured, content renders without wrapper overhead and a "Local" badge appears next to the page title
- No full-width "Local mode" header bars — use inline badges only
- `tsc` passes with no errors
- Build succeeds
