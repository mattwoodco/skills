---
name: video-room
description: LiveKit video room infrastructure — server client, JWT token generation, room management API routes, and a client-side hook for joining rooms. Use this skill when the user says "add video", "setup video rooms", "add livekit", "video calling", or "setup video-room".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [auth, env-config]
---

# Video Room

LiveKit-powered video room infrastructure with server-side room management, JWT token generation secured by better-auth, and a client-side hook for joining rooms and managing local media tracks.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `auth` skill installed (`withAuth` available at `@/lib/auth-guard`)
- `env-config` skill installed (`src/env.ts` with Zod schema)
- LiveKit Cloud account or self-hosted LiveKit server

## Installation

```bash
bun add livekit-client livekit-server-sdk @livekit/components-react @livekit/components-styles
```

## Environment Variables

Add to `.env.local`:

```env
# LiveKit
LIVEKIT_API_KEY=your-api-key
LIVEKIT_API_SECRET=your-api-secret
NEXT_PUBLIC_LIVEKIT_URL=wss://your-project.livekit.cloud
```

### Update `src/env.ts`

Add to the `server` object:

```typescript
server: {
  // ... existing variables
  LIVEKIT_API_KEY: z.string().min(1),
  LIVEKIT_API_SECRET: z.string().min(1),
},
```

Add to the `client` object:

```typescript
client: {
  // ... existing variables
  NEXT_PUBLIC_LIVEKIT_URL: z.string().url(),
},
```

Add to the `runtimeEnv` object:

```typescript
runtimeEnv: {
  // ... existing variables
  LIVEKIT_API_KEY: process.env.LIVEKIT_API_KEY,
  LIVEKIT_API_SECRET: process.env.LIVEKIT_API_SECRET,
  NEXT_PUBLIC_LIVEKIT_URL: process.env.NEXT_PUBLIC_LIVEKIT_URL,
},
```

## What Gets Created

```
src/
├── lib/
│   └── video/
│       ├── livekit.ts        # Server-side LiveKit RoomServiceClient
│       ├── types.ts          # Room, Participant, Track, and grant types
│       ├── token.ts          # Server-side JWT token generation
│       └── use-room.ts       # Client hook for joining rooms + managing local tracks
└── app/
    └── api/
        └── video/
            ├── rooms/
            │   └── route.ts  # POST create room, GET list rooms
            └── token/
                └── route.ts  # POST generate participant token (auth required)
```

## Setup Steps

### Step 1: Create `src/lib/video/types.ts`

```typescript
import type { Track as LKTrack } from "livekit-client";

export type VideoRoom = {
  name: string;
  sid: string;
  numParticipants: number;
  maxParticipants: number;
  creationTime: number;
  metadata: string;
};

export type VideoParticipant = {
  sid: string;
  identity: string;
  name: string;
  metadata: string;
  joinedAt: number;
  isSpeaking: boolean;
  connectionQuality: string;
};

export type VideoTrack = {
  sid: string;
  type: LKTrack.Kind;
  source: LKTrack.Source;
  muted: boolean;
  width?: number;
  height?: number;
};

export type TokenGrants = {
  canPublish: boolean;
  canSubscribe: boolean;
  canPublishData: boolean;
};

export type CreateRoomRequest = {
  name: string;
  maxParticipants?: number;
  metadata?: string;
  emptyTimeout?: number;
};

export type CreateRoomResponse = {
  room: VideoRoom;
};

export type TokenRequest = {
  roomName: string;
  participantName?: string;
  grants?: Partial<TokenGrants>;
};

export type TokenResponse = {
  token: string;
  url: string;
};

export type RoomListResponse = {
  rooms: VideoRoom[];
};
```

### Step 2: Create `src/lib/video/livekit.ts`

```typescript
import { RoomServiceClient } from "livekit-server-sdk";

function getLiveKitCredentials(): { apiKey: string; apiSecret: string; wsUrl: string } {
  const apiKey = process.env.LIVEKIT_API_KEY;
  const apiSecret = process.env.LIVEKIT_API_SECRET;
  const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;

  if (!apiKey) throw new Error("LIVEKIT_API_KEY is not set");
  if (!apiSecret) throw new Error("LIVEKIT_API_SECRET is not set");
  if (!wsUrl) throw new Error("NEXT_PUBLIC_LIVEKIT_URL is not set");

  return { apiKey, apiSecret, wsUrl };
}

let roomServiceClient: RoomServiceClient | null = null;

export function getRoomServiceClient(): RoomServiceClient {
  if (roomServiceClient) return roomServiceClient;

  const { apiKey, apiSecret, wsUrl } = getLiveKitCredentials();

  // Convert wss:// to https:// for REST API
  const httpUrl = wsUrl.replace("wss://", "https://").replace("ws://", "http://");

  roomServiceClient = new RoomServiceClient(httpUrl, apiKey, apiSecret);
  return roomServiceClient;
}

export { getLiveKitCredentials };
```

### Step 3: Create `src/lib/video/token.ts`

```typescript
import { AccessToken } from "livekit-server-sdk";
import { getLiveKitCredentials } from "@/lib/video/livekit";
import type { TokenGrants } from "@/lib/video/types";

type GenerateTokenParams = {
  roomName: string;
  participantIdentity: string;
  participantName: string;
  grants?: Partial<TokenGrants>;
  metadata?: string;
  ttlSeconds?: number;
};

const DEFAULT_GRANTS: TokenGrants = {
  canPublish: true,
  canSubscribe: true,
  canPublishData: true,
};

export async function generateParticipantToken({
  roomName,
  participantIdentity,
  participantName,
  grants,
  metadata,
  ttlSeconds = 3600,
}: GenerateTokenParams): Promise<string> {
  const { apiKey, apiSecret } = getLiveKitCredentials();

  const mergedGrants: TokenGrants = {
    ...DEFAULT_GRANTS,
    ...grants,
  };

  const token = new AccessToken(apiKey, apiSecret, {
    identity: participantIdentity,
    name: participantName,
    metadata,
    ttl: ttlSeconds,
  });

  token.addGrant({
    room: roomName,
    roomJoin: true,
    canPublish: mergedGrants.canPublish,
    canSubscribe: mergedGrants.canSubscribe,
    canPublishData: mergedGrants.canPublishData,
  });

  return await token.toJwt();
}
```

### Step 4: Create `src/lib/video/use-room.ts`

```typescript
"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import {
  Room,
  RoomEvent,
  Track,
  type LocalTrackPublication,
  type RoomOptions,
  type RoomConnectOptions,
} from "livekit-client";
import type { TokenResponse } from "@/lib/video/types";

type UseRoomOptions = {
  roomName: string;
  participantName?: string;
  autoConnect?: boolean;
  roomOptions?: RoomOptions;
  connectOptions?: RoomConnectOptions;
};

type UseRoomReturn = {
  room: Room | null;
  isConnecting: boolean;
  isConnected: boolean;
  error: string | null;
  connect: () => Promise<void>;
  disconnect: () => void;
  toggleMicrophone: () => Promise<void>;
  toggleCamera: () => Promise<void>;
  isMicEnabled: boolean;
  isCameraEnabled: boolean;
};

export function useRoom({
  roomName,
  participantName,
  autoConnect = false,
  roomOptions,
  connectOptions,
}: UseRoomOptions): UseRoomReturn {
  const [room, setRoom] = useState<Room | null>(null);
  const [isConnecting, setIsConnecting] = useState(false);
  const [isConnected, setIsConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isMicEnabled, setIsMicEnabled] = useState(true);
  const [isCameraEnabled, setIsCameraEnabled] = useState(true);
  const roomRef = useRef<Room | null>(null);

  const fetchToken = useCallback(async (): Promise<TokenResponse> => {
    const res = await fetch("/api/video/token", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        roomName,
        participantName,
      }),
    });

    if (!res.ok) {
      const body = await res.json().catch(() => ({ error: "Failed to get token" }));
      throw new Error((body as { error: string }).error);
    }

    return res.json() as Promise<TokenResponse>;
  }, [roomName, participantName]);

  const connect = useCallback(async () => {
    if (roomRef.current?.state === "connected") return;

    setIsConnecting(true);
    setError(null);

    try {
      const { token, url } = await fetchToken();

      const newRoom = new Room(roomOptions);
      roomRef.current = newRoom;

      newRoom.on(RoomEvent.Connected, () => {
        setIsConnected(true);
        setIsConnecting(false);
      });

      newRoom.on(RoomEvent.Disconnected, () => {
        setIsConnected(false);
      });

      newRoom.on(RoomEvent.LocalTrackPublished, (publication: LocalTrackPublication) => {
        if (publication.track?.source === Track.Source.Microphone) {
          setIsMicEnabled(!publication.isMuted);
        }
        if (publication.track?.source === Track.Source.Camera) {
          setIsCameraEnabled(!publication.isMuted);
        }
      });

      newRoom.on(RoomEvent.TrackMuted, (publication) => {
        if (publication.track?.source === Track.Source.Microphone) {
          setIsMicEnabled(false);
        }
        if (publication.track?.source === Track.Source.Camera) {
          setIsCameraEnabled(false);
        }
      });

      newRoom.on(RoomEvent.TrackUnmuted, (publication) => {
        if (publication.track?.source === Track.Source.Microphone) {
          setIsMicEnabled(true);
        }
        if (publication.track?.source === Track.Source.Camera) {
          setIsCameraEnabled(true);
        }
      });

      await newRoom.connect(url, token, connectOptions);
      setRoom(newRoom);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Failed to connect";
      setError(message);
      setIsConnecting(false);
    }
  }, [fetchToken, roomOptions, connectOptions]);

  const disconnect = useCallback(() => {
    if (roomRef.current) {
      roomRef.current.disconnect();
      roomRef.current = null;
      setRoom(null);
      setIsConnected(false);
      setIsMicEnabled(true);
      setIsCameraEnabled(true);
    }
  }, []);

  const toggleMicrophone = useCallback(async () => {
    if (!roomRef.current?.localParticipant) return;
    const enabled = roomRef.current.localParticipant.isMicrophoneEnabled;
    await roomRef.current.localParticipant.setMicrophoneEnabled(!enabled);
    setIsMicEnabled(!enabled);
  }, []);

  const toggleCamera = useCallback(async () => {
    if (!roomRef.current?.localParticipant) return;
    const enabled = roomRef.current.localParticipant.isCameraEnabled;
    await roomRef.current.localParticipant.setCameraEnabled(!enabled);
    setIsCameraEnabled(!enabled);
  }, []);

  // Auto-connect if enabled
  useEffect(() => {
    if (autoConnect) {
      connect();
    }
    return () => {
      disconnect();
    };
    // Only run on mount/unmount when autoConnect is true
    // biome-ignore lint/correctness/useExhaustiveDependencies: intentional mount-only effect
  }, [autoConnect]);

  return {
    room,
    isConnecting,
    isConnected,
    error,
    connect,
    disconnect,
    toggleMicrophone,
    toggleCamera,
    isMicEnabled,
    isCameraEnabled,
  };
}
```

### Step 5: Create `src/app/api/video/rooms/route.ts`

```typescript
import { NextResponse } from "next/server";
import { getRoomServiceClient } from "@/lib/video/livekit";
import type {
  CreateRoomRequest,
  CreateRoomResponse,
  RoomListResponse,
  VideoRoom,
} from "@/lib/video/types";

function mapRoom(room: { name: string; sid: string; numParticipants: number; maxParticipants: number; creationTime: bigint; metadata: string }): VideoRoom {
  return {
    name: room.name,
    sid: room.sid,
    numParticipants: room.numParticipants,
    maxParticipants: room.maxParticipants,
    creationTime: Number(room.creationTime),
    metadata: room.metadata,
  };
}

/** POST /api/video/rooms — Create a new room */
export async function POST(request: Request): Promise<NextResponse<CreateRoomResponse | { error: string }>> {
  try {
    const body: CreateRoomRequest = await request.json();

    if (!body.name || body.name.trim().length === 0) {
      return NextResponse.json({ error: "Room name is required" }, { status: 400 });
    }

    const client = getRoomServiceClient();
    const room = await client.createRoom({
      name: body.name.trim(),
      maxParticipants: body.maxParticipants ?? 20,
      metadata: body.metadata ?? "",
      emptyTimeout: body.emptyTimeout ?? 600,
    });

    return NextResponse.json(
      { room: mapRoom(room) },
      { status: 201 }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to create room";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

/** GET /api/video/rooms — List all active rooms */
export async function GET(): Promise<NextResponse<RoomListResponse | { error: string }>> {
  try {
    const client = getRoomServiceClient();
    const rooms = await client.listRooms();

    return NextResponse.json({
      rooms: rooms.map(mapRoom),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to list rooms";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 6: Create `src/app/api/video/token/route.ts`

This route is protected by `withAuth` — only authenticated users can obtain a LiveKit token.

```typescript
import { NextResponse } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { generateParticipantToken } from "@/lib/video/token";
import type { TokenRequest, TokenResponse } from "@/lib/video/types";

/** POST /api/video/token — Generate a participant token (requires authentication) */
export const POST = withAuth(async (request, { user }) => {
  try {
    const body: TokenRequest = await request.json();

    if (!body.roomName || body.roomName.trim().length === 0) {
      return NextResponse.json({ error: "roomName is required" }, { status: 400 });
    }

    const wsUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;
    if (!wsUrl) {
      return NextResponse.json(
        { error: "NEXT_PUBLIC_LIVEKIT_URL is not configured" },
        { status: 500 }
      );
    }

    const participantName = body.participantName ?? user.name ?? user.email ?? "Anonymous";

    const token = await generateParticipantToken({
      roomName: body.roomName.trim(),
      participantIdentity: user.id,
      participantName,
      grants: body.grants,
      metadata: JSON.stringify({
        userId: user.id,
        email: user.email,
      }),
    });

    const response: TokenResponse = {
      token,
      url: wsUrl,
    };

    return NextResponse.json(response);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to generate token";
    return NextResponse.json({ error: message }, { status: 500 });
  }
});
```

## Usage

### Create a Room

```typescript
const res = await fetch("/api/video/rooms", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    name: "standup-2026-02-18",
    maxParticipants: 10,
    metadata: JSON.stringify({ type: "standup", team: "engineering" }),
  }),
});
const { room } = await res.json();
```

### List Active Rooms

```typescript
const res = await fetch("/api/video/rooms");
const { rooms } = await res.json();
```

### Get a Token and Join

```typescript
const res = await fetch("/api/video/token", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    roomName: "standup-2026-02-18",
    participantName: "Alice",
    grants: {
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    },
  }),
});
const { token, url } = await res.json();
```

### Using the `useRoom` Hook

```tsx
"use client";

import { useRoom } from "@/lib/video/use-room";

function VideoCall() {
  const {
    isConnecting,
    isConnected,
    error,
    connect,
    disconnect,
    toggleMicrophone,
    toggleCamera,
    isMicEnabled,
    isCameraEnabled,
  } = useRoom({
    roomName: "my-room",
    participantName: "Alice",
  });

  if (error) return <p>Error: {error}</p>;

  return (
    <div>
      {!isConnected ? (
        <button onClick={connect} disabled={isConnecting}>
          {isConnecting ? "Connecting..." : "Join Room"}
        </button>
      ) : (
        <div>
          <button onClick={toggleMicrophone}>
            {isMicEnabled ? "Mute" : "Unmute"}
          </button>
          <button onClick={toggleCamera}>
            {isCameraEnabled ? "Hide Camera" : "Show Camera"}
          </button>
          <button onClick={disconnect}>Leave</button>
        </div>
      )}
    </div>
  );
}
```

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/video/rooms` | No | Create a new LiveKit room |
| GET | `/api/video/rooms` | No | List all active rooms |
| POST | `/api/video/token` | Yes | Generate a participant JWT token |

## Acceptance Criteria

- [ ] `bun add livekit-client livekit-server-sdk @livekit/components-react @livekit/components-styles` installs without errors
- [ ] `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `NEXT_PUBLIC_LIVEKIT_URL` are validated in `src/env.ts`
- [ ] `POST /api/video/rooms` creates a room on LiveKit and returns the room object
- [ ] `GET /api/video/rooms` lists all active rooms
- [ ] `POST /api/video/token` returns 401 for unauthenticated requests
- [ ] `POST /api/video/token` returns a valid JWT for authenticated users
- [ ] Token includes correct grants (canPublish, canSubscribe, canPublishData)
- [ ] Token encodes user identity and name from the auth session
- [ ] `useRoom` hook connects to a LiveKit room and toggles mic/camera
- [ ] No usage of `any` type anywhere in the code
- [ ] `tsc` passes with no errors
- [ ] `bun run build` succeeds

## Troubleshooting

### "LIVEKIT_API_KEY is not set"

**Symptoms**: Server error when creating rooms or generating tokens.

**Cause**: Environment variables not loaded.

**Fix**: Ensure `.env.local` contains all three LiveKit variables and restart the dev server.

### Token generation fails with 401

**Symptoms**: `POST /api/video/token` returns 401.

**Cause**: User is not authenticated via better-auth.

**Fix**: Ensure the user is signed in before requesting a token. The token route uses `withAuth` which requires a valid session.

### Room connect fails with "could not connect"

**Symptoms**: `useRoom` hook sets error to "Failed to connect".

**Cause**: WebSocket URL is incorrect or LiveKit server is unreachable.

**Fix**:

1. Verify `NEXT_PUBLIC_LIVEKIT_URL` starts with `wss://`
2. Check that your LiveKit Cloud project is active or your self-hosted server is running
3. Verify the API key/secret match the LiveKit project

### Camera or microphone not working

**Symptoms**: Track publications fail silently.

**Cause**: Browser permissions denied.

**Fix**: Ensure the browser has granted camera/microphone permissions. Check `navigator.mediaDevices.getUserMedia` in the browser console.

### BigInt serialization error

**Symptoms**: `TypeError: Do not know how to serialize a BigInt` in room list.

**Cause**: LiveKit SDK returns `creationTime` as `bigint`, which `JSON.stringify` cannot serialize.

**Fix**: The `mapRoom` helper converts `bigint` to `number` via `Number(room.creationTime)`. Ensure all room data passes through this mapper before JSON serialization.
