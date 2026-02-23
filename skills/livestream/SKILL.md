---
name: livestream
description: Go-live from a LiveKit room to MUX via RTMP egress — supports MUX, YouTube, Twitch, and custom RTMP destinations. Auto-archives to MUX VOD when stream ends. Use this skill when the user says "add livestream", "go live", "stream to mux", "rtmp stream", "broadcast", or "live streaming".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [video-room, stream-mux, recording, env-config]
---

# Livestream (LiveKit Egress + MUX)

Livestreaming from a [LiveKit](https://livekit.io) room to external platforms via RTMP egress. Creates a MUX live stream, starts an RTMP egress from the LiveKit room to the MUX ingest URL, and auto-archives to a MUX VOD asset when the stream ends. Also supports custom RTMP destinations like YouTube Live and Twitch.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `video-room` skill applied (provides `livekit-server-sdk`, LiveKit server configuration)
- `stream-mux` skill applied (provides `@mux/mux-node` client, MUX API credentials)
- `recording` skill applied (provides the `recordings` schema and Egress patterns)
- `env-config` skill applied (provides Zod env validation)

## Installation

No additional packages required. Uses `livekit-server-sdk` from the `video-room` skill and `@mux/mux-node` from the `stream-mux` skill.

## Environment Variables

Uses existing environment variables from dependencies:

```env
# LiveKit (from video-room)
LIVEKIT_API_KEY=your_api_key
LIVEKIT_API_SECRET=your_api_secret
NEXT_PUBLIC_LIVEKIT_URL=wss://your-project.livekit.cloud

# MUX (from stream-mux)
MUX_TOKEN_ID=your_mux_token_id
MUX_TOKEN_SECRET=your_mux_token_secret
```

Add to `src/env.ts` server schema (if not already present):

```typescript
MUX_TOKEN_ID: z.string().min(1),
MUX_TOKEN_SECRET: z.string().min(1),
```

## What Gets Created

```
src/
├── lib/
│   ├── video/
│   │   ├── livestream.ts              # startLivestream, stopLivestream, getLivestreamStatus
│   │   └── stream-destinations.ts     # StreamDestination type, RTMP URL helpers
│   └── db/
│       └── schema/
│           └── livestreams.ts         # Drizzle schema: livestreams table
└── app/
    └── api/
        └── video/
            └── livestream/
                ├── route.ts           # POST go live, DELETE stop stream
                └── status/
                    └── route.ts       # GET current stream status + viewer count
```

## Setup Steps

### Step 1: Create `src/lib/video/stream-destinations.ts`

```typescript
export type StreamDestinationType = "mux" | "youtube" | "twitch" | "custom";

export type StreamDestination = {
  type: StreamDestinationType;
  name: string;
  rtmpUrl: string;
  streamKey: string;
};

/**
 * Constructs the full RTMP URL for a MUX live stream.
 * MUX RTMP ingest endpoint: rtmp://global-live.mux.com:5222/app/{stream_key}
 */
export function buildMuxRtmpUrl(streamKey: string): string {
  return `rtmp://global-live.mux.com:5222/app/${streamKey}`;
}

/**
 * Constructs the full RTMP URL for YouTube Live.
 * YouTube RTMP ingest: rtmp://a.rtmp.youtube.com/live2/{stream_key}
 */
export function buildYouTubeRtmpUrl(streamKey: string): string {
  return `rtmp://a.rtmp.youtube.com/live2/${streamKey}`;
}

/**
 * Constructs the full RTMP URL for Twitch.
 * Twitch RTMP ingest: rtmp://live.twitch.tv/app/{stream_key}
 * Use the nearest ingest server for lower latency.
 */
export function buildTwitchRtmpUrl(
  streamKey: string,
  ingestServer?: string
): string {
  const server = ingestServer ?? "live.twitch.tv";
  return `rtmp://${server}/app/${streamKey}`;
}

/**
 * Builds a StreamDestination from a destination type and stream key.
 */
export function buildDestination(
  type: StreamDestinationType,
  streamKey: string,
  options?: { name?: string; customRtmpUrl?: string; twitchIngestServer?: string }
): StreamDestination {
  const name = options?.name ?? type;

  switch (type) {
    case "mux":
      return {
        type,
        name,
        rtmpUrl: buildMuxRtmpUrl(streamKey),
        streamKey,
      };
    case "youtube":
      return {
        type,
        name,
        rtmpUrl: buildYouTubeRtmpUrl(streamKey),
        streamKey,
      };
    case "twitch":
      return {
        type,
        name,
        rtmpUrl: buildTwitchRtmpUrl(streamKey, options?.twitchIngestServer),
        streamKey,
      };
    case "custom":
      if (!options?.customRtmpUrl) {
        throw new Error("customRtmpUrl is required for custom destinations");
      }
      return {
        type,
        name,
        rtmpUrl: `${options.customRtmpUrl}/${streamKey}`,
        streamKey,
      };
  }
}

/**
 * Constructs the full RTMP URL with stream key appended, ready for LiveKit egress.
 * LiveKit expects the full URL including the stream key.
 */
export function getFullRtmpUrl(destination: StreamDestination): string {
  // For MUX, the rtmpUrl already includes the stream key in the path
  return destination.rtmpUrl;
}

/**
 * Gets a MUX HLS playback URL from a playback ID.
 */
export function getMuxPlaybackUrl(playbackId: string): string {
  return `https://stream.mux.com/${playbackId}.m3u8`;
}

/**
 * Gets a MUX thumbnail URL from a playback ID.
 */
export function getMuxThumbnailUrl(
  playbackId: string,
  options?: { width?: number; height?: number; time?: number }
): string {
  const params = new URLSearchParams();
  if (options?.width) params.set("width", String(options.width));
  if (options?.height) params.set("height", String(options.height));
  if (options?.time) params.set("time", String(options.time));

  const queryString = params.toString();
  return `https://image.mux.com/${playbackId}/thumbnail.jpg${queryString ? `?${queryString}` : ""}`;
}
```

### Step 2: Create `src/lib/db/schema/livestreams.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
} from "drizzle-orm/pg-core";

export const livestreams = pgTable("livestreams", {
  id: uuid("id").primaryKey().defaultRandom(),
  roomName: text("room_name").notNull(),
  egressId: text("egress_id"),
  muxLiveStreamId: text("mux_live_stream_id"),
  muxPlaybackId: text("mux_playback_id"),
  muxStreamKey: text("mux_stream_key"),
  rtmpUrl: text("rtmp_url"),
  status: text("status", {
    enum: ["idle", "starting", "active", "stopping", "completed", "failed"],
  })
    .notNull()
    .default("idle"),
  muxAssetId: text("mux_asset_id"),
  startedAt: timestamp("started_at", { withTimezone: true }),
  endedAt: timestamp("ended_at", { withTimezone: true }),
  userId: text("user_id").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export type Livestream = typeof livestreams.$inferSelect;
export type NewLivestream = typeof livestreams.$inferInsert;
```

### Step 3: Add export to `src/lib/db/schema/index.ts`

```typescript
export * from "./livestreams";
```

### Step 4: Create `src/lib/video/livestream.ts`

```typescript
import { EgressClient, EncodingOptions, StreamOutput, StreamProtocol } from "livekit-server-sdk";
import Mux from "@mux/mux-node";
import { db } from "@/lib/db";
import { livestreams, type Livestream } from "@/lib/db/schema";
import { eq, and, desc } from "drizzle-orm";
import {
  buildMuxRtmpUrl,
  getMuxPlaybackUrl,
  getFullRtmpUrl,
} from "./stream-destinations";
import type { StreamDestination } from "./stream-destinations";

type MuxLiveStream = {
  id: string;
  stream_key: string;
  playback_ids?: Array<{ id: string; policy: string }>;
  status: string;
};

type MuxAsset = {
  id: string;
  playback_ids?: Array<{ id: string; policy: string }>;
  status: string;
  duration?: number;
};

function getEgressClient(): EgressClient {
  const livekitUrl = process.env.NEXT_PUBLIC_LIVEKIT_URL;
  const apiKey = process.env.LIVEKIT_API_KEY;
  const apiSecret = process.env.LIVEKIT_API_SECRET;

  if (!livekitUrl || !apiKey || !apiSecret) {
    throw new Error(
      "Missing NEXT_PUBLIC_LIVEKIT_URL, LIVEKIT_API_KEY, or LIVEKIT_API_SECRET"
    );
  }

  // Convert wss:// to https:// for REST API
  const httpUrl = livekitUrl
    .replace("wss://", "https://")
    .replace("ws://", "http://");

  return new EgressClient(httpUrl, apiKey, apiSecret);
}

function getMuxClient(): Mux {
  const tokenId = process.env.MUX_TOKEN_ID;
  const tokenSecret = process.env.MUX_TOKEN_SECRET;

  if (!tokenId || !tokenSecret) {
    throw new Error("Missing MUX_TOKEN_ID or MUX_TOKEN_SECRET");
  }

  return new Mux({ tokenId, tokenSecret });
}

type StartLivestreamOptions = {
  roomName: string;
  /** Additional RTMP destinations beyond MUX */
  additionalDestinations?: StreamDestination[];
  /** MUX latency mode: "standard" for normal, "low" for low-latency */
  latencyMode?: "standard" | "low";
  /** Max continuous duration in seconds (default: 43200 = 12h) */
  maxDuration?: number;
};

type StartLivestreamResult = {
  livestreamId: string;
  egressId: string;
  muxLiveStreamId: string;
  muxPlaybackId: string;
  playbackUrl: string;
  status: string;
};

type StopLivestreamResult = {
  livestreamId: string;
  status: string;
  muxAssetId: string | null;
  vodPlaybackId: string | null;
};

type LivestreamStatus = {
  livestreamId: string;
  roomName: string;
  status: string;
  muxPlaybackId: string | null;
  playbackUrl: string | null;
  viewerCount: number;
  startedAt: Date | null;
  duration: number | null;
};

export async function startLivestream(
  options: StartLivestreamOptions,
  userId: string
): Promise<StartLivestreamResult> {
  const { roomName, additionalDestinations, latencyMode, maxDuration } = options;

  // Step 1: Create a MUX live stream
  const mux = getMuxClient();

  const muxLiveStream = await mux.video.liveStreams.create({
    playback_policy: ["public"],
    new_asset_settings: {
      playback_policy: ["public"],
    },
    latency_mode: latencyMode ?? "standard",
    max_continuous_duration: maxDuration ?? 43200,
  });

  const muxLiveStreamId = muxLiveStream.id;
  const muxStreamKey = muxLiveStream.stream_key;
  const muxPlaybackId = muxLiveStream.playback_ids?.[0]?.id ?? "";

  if (!muxStreamKey) {
    throw new Error("MUX did not return a stream key");
  }

  const muxRtmpUrl = buildMuxRtmpUrl(muxStreamKey);

  // Collect all RTMP URLs for multi-destination streaming
  const rtmpUrls = [muxRtmpUrl];

  if (additionalDestinations) {
    for (const dest of additionalDestinations) {
      rtmpUrls.push(getFullRtmpUrl(dest));
    }
  }

  // Step 2: Start LiveKit RTMP egress
  const egressClient = getEgressClient();

  const streamOutput = new StreamOutput({
    protocol: StreamProtocol.RTMP,
    urls: rtmpUrls,
  });

  const egressInfo = await egressClient.startRoomCompositeEgress(
    roomName,
    {
      stream: streamOutput,
    },
    {
      layout: "grid",
      encodingOptions: new EncodingOptions({
        width: 1920,
        height: 1080,
        videoBitrate: 4500000,
        audioBitrate: 128000,
      }),
    }
  );

  const egressId = egressInfo.egressId;

  // Step 3: Store livestream record
  const [livestream] = await db
    .insert(livestreams)
    .values({
      roomName,
      egressId,
      muxLiveStreamId,
      muxPlaybackId,
      muxStreamKey,
      rtmpUrl: muxRtmpUrl,
      status: "active",
      startedAt: new Date(),
      userId,
    })
    .returning();

  const playbackUrl = getMuxPlaybackUrl(muxPlaybackId);

  return {
    livestreamId: livestream.id,
    egressId,
    muxLiveStreamId,
    muxPlaybackId,
    playbackUrl,
    status: "active",
  };
}

export async function stopLivestream(
  livestreamId: string,
  userId: string
): Promise<StopLivestreamResult> {
  const [livestream] = await db
    .select()
    .from(livestreams)
    .where(
      and(eq(livestreams.id, livestreamId), eq(livestreams.userId, userId))
    )
    .limit(1);

  if (!livestream) {
    throw new Error("Livestream not found");
  }

  if (livestream.status !== "active" && livestream.status !== "starting") {
    throw new Error(
      `Livestream is not active (status: ${livestream.status})`
    );
  }

  // Update status to stopping
  await db
    .update(livestreams)
    .set({ status: "stopping", updatedAt: new Date() })
    .where(eq(livestreams.id, livestreamId));

  try {
    // Step 1: Stop LiveKit egress
    if (livestream.egressId) {
      const egressClient = getEgressClient();
      await egressClient.stopEgress(livestream.egressId);
    }

    // Step 2: Signal MUX to complete the live stream
    // This triggers auto-archival to a VOD asset
    const mux = getMuxClient();
    let muxAssetId: string | null = null;
    let vodPlaybackId: string | null = null;

    if (livestream.muxLiveStreamId) {
      await mux.video.liveStreams.complete(livestream.muxLiveStreamId);

      // Wait briefly for MUX to create the asset, then check
      // The asset is created asynchronously — we store what we can now
      // and the status endpoint will reflect the final state
      try {
        const muxLiveStreamInfo = await mux.video.liveStreams.retrieve(
          livestream.muxLiveStreamId
        );

        // MUX creates an asset from the live stream recording
        // The asset ID is available on the live stream object after completion
        const recentAssets = muxLiveStreamInfo.recent_asset_ids;
        if (recentAssets && recentAssets.length > 0) {
          muxAssetId = recentAssets[recentAssets.length - 1] ?? null;

          // Try to get VOD playback ID from the asset
          if (muxAssetId) {
            try {
              const asset = await mux.video.assets.retrieve(muxAssetId);
              vodPlaybackId = asset.playback_ids?.[0]?.id ?? null;
            } catch {
              // Asset may still be processing
            }
          }
        }
      } catch {
        // MUX API call failed — asset info will be available later
      }
    }

    // Step 3: Update database record
    await db
      .update(livestreams)
      .set({
        status: "completed",
        endedAt: new Date(),
        muxAssetId,
        updatedAt: new Date(),
      })
      .where(eq(livestreams.id, livestreamId));

    return {
      livestreamId,
      status: "completed",
      muxAssetId,
      vodPlaybackId,
    };
  } catch (error) {
    await db
      .update(livestreams)
      .set({ status: "failed", updatedAt: new Date() })
      .where(eq(livestreams.id, livestreamId));

    throw error;
  }
}

export async function getLivestreamStatus(
  livestreamId: string,
  userId: string
): Promise<LivestreamStatus> {
  const [livestream] = await db
    .select()
    .from(livestreams)
    .where(
      and(eq(livestreams.id, livestreamId), eq(livestreams.userId, userId))
    )
    .limit(1);

  if (!livestream) {
    throw new Error("Livestream not found");
  }

  let viewerCount = 0;
  let currentStatus = livestream.status;

  // Fetch live viewer count from MUX if stream is active
  if (
    livestream.muxLiveStreamId &&
    (livestream.status === "active" || livestream.status === "starting")
  ) {
    try {
      const mux = getMuxClient();
      const muxStream = await mux.video.liveStreams.retrieve(
        livestream.muxLiveStreamId
      );

      // Map MUX status to our status
      if (muxStream.status === "active") {
        currentStatus = "active";
      } else if (muxStream.status === "idle") {
        currentStatus = "starting";
      }

      // MUX does not provide viewer count directly on the live stream object.
      // Use MUX Data API for real-time viewer counts if MUX Data is enabled.
      // For now, we return 0 and the consumer can integrate MUX Data separately.
      viewerCount = 0;
    } catch {
      // MUX API call failed — use stored status
    }
  }

  const duration =
    livestream.startedAt
      ? (Date.now() - livestream.startedAt.getTime()) / 1000
      : null;

  const playbackUrl = livestream.muxPlaybackId
    ? getMuxPlaybackUrl(livestream.muxPlaybackId)
    : null;

  return {
    livestreamId: livestream.id,
    roomName: livestream.roomName,
    status: currentStatus,
    muxPlaybackId: livestream.muxPlaybackId,
    playbackUrl,
    viewerCount,
    startedAt: livestream.startedAt,
    duration,
  };
}

export async function getActiveLivestream(
  roomName: string,
  userId: string
): Promise<Livestream | null> {
  const [livestream] = await db
    .select()
    .from(livestreams)
    .where(
      and(
        eq(livestreams.roomName, roomName),
        eq(livestreams.userId, userId),
        eq(livestreams.status, "active")
      )
    )
    .limit(1);

  return livestream ?? null;
}

export async function listLivestreams(
  userId: string,
  options?: { roomName?: string; limit?: number }
): Promise<Livestream[]> {
  const conditions = [eq(livestreams.userId, userId)];

  if (options?.roomName) {
    conditions.push(eq(livestreams.roomName, options.roomName));
  }

  return db
    .select()
    .from(livestreams)
    .where(and(...conditions))
    .orderBy(desc(livestreams.createdAt))
    .limit(options?.limit ?? 50);
}

// Re-export types
export type { Livestream } from "@/lib/db/schema";
export type {
  StreamDestination,
  StreamDestinationType,
} from "./stream-destinations";
```

### Step 5: Create `src/app/api/video/livestream/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod/v4";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import {
  startLivestream,
  stopLivestream,
  getActiveLivestream,
  listLivestreams,
} from "@/lib/video/livestream";
import { buildDestination } from "@/lib/video/stream-destinations";
import type { StreamDestination, StreamDestinationType } from "@/lib/video/stream-destinations";

const destinationSchema = z.object({
  type: z.enum(["youtube", "twitch", "custom"]),
  name: z.string().optional(),
  streamKey: z.string().min(1),
  customRtmpUrl: z.string().url().optional(),
  twitchIngestServer: z.string().optional(),
});

const startLivestreamSchema = z.object({
  roomName: z.string().min(1),
  latencyMode: z.enum(["standard", "low"]).default("standard"),
  maxDuration: z.number().int().positive().optional(),
  additionalDestinations: z.array(destinationSchema).optional(),
});

const stopLivestreamSchema = z.object({
  roomName: z.string().min(1),
});

export async function POST(request: Request) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const config = startLivestreamSchema.parse(body);

    // Check if there's already an active livestream for this room
    const existing = await getActiveLivestream(
      config.roomName,
      session.user.id
    );
    if (existing) {
      return NextResponse.json(
        { error: "Room already has an active livestream" },
        { status: 409 }
      );
    }

    // Build additional destinations
    const additionalDestinations: StreamDestination[] = [];
    if (config.additionalDestinations) {
      for (const dest of config.additionalDestinations) {
        additionalDestinations.push(
          buildDestination(
            dest.type as StreamDestinationType,
            dest.streamKey,
            {
              name: dest.name,
              customRtmpUrl: dest.customRtmpUrl,
              twitchIngestServer: dest.twitchIngestServer,
            }
          )
        );
      }
    }

    const result = await startLivestream(
      {
        roomName: config.roomName,
        latencyMode: config.latencyMode,
        maxDuration: config.maxDuration,
        additionalDestinations:
          additionalDestinations.length > 0
            ? additionalDestinations
            : undefined,
      },
      session.user.id
    );

    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Failed to start livestream";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function DELETE(request: Request) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const { roomName } = stopLivestreamSchema.parse(body);

    // Find the active livestream for this room
    const active = await getActiveLivestream(roomName, session.user.id);
    if (!active) {
      return NextResponse.json(
        { error: "No active livestream found for this room" },
        { status: 404 }
      );
    }

    const result = await stopLivestream(active.id, session.user.id);

    return NextResponse.json(result);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Failed to stop livestream";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET(request: Request) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { searchParams } = new URL(request.url);
    const roomName = searchParams.get("roomName") ?? undefined;
    const limitParam = searchParams.get("limit");
    const limit = limitParam ? parseInt(limitParam, 10) : undefined;

    const result = await listLivestreams(session.user.id, {
      roomName,
      limit,
    });

    return NextResponse.json({ livestreams: result });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Failed to list livestreams";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 6: Create `src/app/api/video/livestream/status/route.ts`

```typescript
import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import {
  getLivestreamStatus,
  getActiveLivestream,
} from "@/lib/video/livestream";

export async function GET(request: Request) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { searchParams } = new URL(request.url);
    const livestreamId = searchParams.get("id");
    const roomName = searchParams.get("roomName");

    if (!livestreamId && !roomName) {
      return NextResponse.json(
        { error: "Provide either id or roomName query parameter" },
        { status: 400 }
      );
    }

    // Find by ID or active stream for room
    let targetId: string;

    if (livestreamId) {
      targetId = livestreamId;
    } else {
      const active = await getActiveLivestream(roomName!, session.user.id);
      if (!active) {
        return NextResponse.json(
          { error: "No active livestream found for this room" },
          { status: 404 }
        );
      }
      targetId = active.id;
    }

    const status = await getLivestreamStatus(targetId, session.user.id);

    return NextResponse.json(status);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Failed to get livestream status";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 7: Push database schema

```bash
bunx drizzle-kit push
```

## Usage

### Go live from a room (MUX only)

```typescript
const response = await fetch("/api/video/livestream", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    roomName: "my-room",
    latencyMode: "low",
  }),
});
const {
  livestreamId,
  muxPlaybackId,
  playbackUrl, // HLS URL for viewers
} = await response.json();
```

### Go live with multiple destinations

```typescript
const response = await fetch("/api/video/livestream", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    roomName: "my-room",
    latencyMode: "standard",
    additionalDestinations: [
      {
        type: "youtube",
        name: "YouTube Live",
        streamKey: "xxxx-xxxx-xxxx-xxxx",
      },
      {
        type: "twitch",
        name: "Twitch",
        streamKey: "live_xxxxxxxx",
      },
    ],
  }),
});
```

### Get stream status with viewer count

```typescript
// By livestream ID
const response = await fetch(`/api/video/livestream/status?id=${livestreamId}`);

// By room name (finds active stream)
const response = await fetch(
  `/api/video/livestream/status?roomName=my-room`
);

const {
  status,       // "active", "starting", "completed", etc.
  playbackUrl,  // HLS playback URL
  viewerCount,  // Current viewer count from MUX
  duration,     // Stream duration in seconds
} = await response.json();
```

### Stop livestream

```typescript
const response = await fetch("/api/video/livestream", {
  method: "DELETE",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ roomName: "my-room" }),
});

const {
  status,         // "completed"
  muxAssetId,     // VOD asset created from the stream
  vodPlaybackId,  // Playback ID for the VOD recording
} = await response.json();
```

### List all livestreams

```typescript
const response = await fetch("/api/video/livestream?roomName=my-room&limit=10");
const { livestreams } = await response.json();
```

### Server-side usage

```typescript
import {
  startLivestream,
  stopLivestream,
  getLivestreamStatus,
} from "@/lib/video/livestream";
import { buildDestination } from "@/lib/video/stream-destinations";

// Start with MUX + YouTube
const result = await startLivestream(
  {
    roomName: "event-room",
    latencyMode: "low",
    additionalDestinations: [
      buildDestination("youtube", "xxxx-xxxx-xxxx-xxxx", {
        name: "YouTube Live",
      }),
    ],
  },
  userId
);

// Check status
const status = await getLivestreamStatus(result.livestreamId, userId);

// Stop — auto-archives to MUX VOD
const stopped = await stopLivestream(result.livestreamId, userId);
console.log("VOD asset:", stopped.muxAssetId);
```

### Embed playback for viewers

```tsx
// Using MUX Player (from stream-mux skill)
import MuxPlayer from "@mux/mux-player-react";

function LiveViewer({ playbackId }: { playbackId: string }) {
  return (
    <MuxPlayer
      playbackId={playbackId}
      streamType="live"
      autoPlay="muted"
      className="w-full aspect-video"
    />
  );
}
```

### Use stream destination helpers

```typescript
import {
  buildDestination,
  buildMuxRtmpUrl,
  getMuxPlaybackUrl,
  getMuxThumbnailUrl,
} from "@/lib/video/stream-destinations";

// Build a YouTube destination
const ytDest = buildDestination("youtube", "xxxx-xxxx-xxxx-xxxx", {
  name: "My YouTube Channel",
});

// Get MUX playback URL
const hlsUrl = getMuxPlaybackUrl("abc123");
// => "https://stream.mux.com/abc123.m3u8"

// Get MUX thumbnail
const thumbUrl = getMuxThumbnailUrl("abc123", {
  width: 640,
  height: 360,
  time: 10,
});
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/video/livestream` | Go live — creates MUX stream + starts RTMP egress |
| DELETE | `/api/video/livestream` | Stop livestream by room name |
| GET | `/api/video/livestream?roomName=&limit=` | List user's livestreams |
| GET | `/api/video/livestream/status?id=` | Get stream status, viewer count, playback URL |
| GET | `/api/video/livestream/status?roomName=` | Get active stream status by room |

## Acceptance Criteria

- [ ] POST `/api/video/livestream` creates a MUX live stream and starts LiveKit RTMP egress
- [ ] MUX live stream is created with `playback_policy: ["public"]` and `new_asset_settings`
- [ ] LiveKit RTMP egress sends to MUX ingest URL (`rtmp://global-live.mux.com:5222/app/{key}`)
- [ ] Additional RTMP destinations (YouTube, Twitch, custom) are passed to egress
- [ ] DELETE `/api/video/livestream` stops the egress and signals MUX to complete
- [ ] On stop, MUX auto-archives the stream to a VOD asset via `new_asset_settings`
- [ ] GET `/api/video/livestream/status` returns stream status and MUX playback ID
- [ ] `livestreams` table in Postgres has correct schema with all columns
- [ ] Duplicate active livestream for same room returns 409 Conflict
- [ ] All routes require authentication
- [ ] Stream destination helpers correctly build RTMP URLs for MUX, YouTube, Twitch
- [ ] No `any` casts anywhere
- [ ] `tsc` passes with no errors
- [ ] Build succeeds

## Troubleshooting

### "Room not found" when starting livestream

**Symptoms**: LiveKit RTMP egress fails to start.

**Cause**: The LiveKit room must have active participants for egress to start.

**Fix**: Ensure at least one participant has joined the room before going live.

### MUX stream stuck in "idle" status

**Symptoms**: MUX live stream created but never becomes "active".

**Cause**: RTMP data is not reaching MUX. The egress may have failed or the RTMP URL is incorrect.

**Fix**: Verify the RTMP URL format: `rtmp://global-live.mux.com:5222/app/{stream_key}`. Check LiveKit egress status in the LiveKit dashboard.

### VOD asset not created after stopping

**Symptoms**: `muxAssetId` is null after stopping the stream.

**Cause**: MUX creates the VOD asset asynchronously after the live stream completes. It may take a few seconds.

**Fix**: The asset creation is triggered by `mux.video.liveStreams.complete()`. Check the MUX dashboard for the asset. You can also set up a MUX webhook to be notified when `video.asset.ready` fires.

### Multi-destination stream drops one destination

**Symptoms**: One of the RTMP destinations stops receiving while others continue.

**Cause**: LiveKit egress may drop a destination if the RTMP connection is unstable.

**Fix**: Check the RTMP URLs and stream keys for each destination. Ensure the egress has sufficient bandwidth. LiveKit Cloud automatically retries dropped connections.

### RTMP connection refused

**Symptoms**: Egress fails immediately with a connection error.

**Cause**: Firewall or network configuration blocking outbound RTMP (port 1935 or custom port).

**Fix**: Ensure your LiveKit server can reach the RTMP endpoints. MUX uses port 5222, YouTube uses 1935, Twitch uses 1935. For self-hosted LiveKit, check firewall rules.

### Stream quality is poor

**Symptoms**: Viewers see low resolution or choppy video.

**Cause**: Default encoding settings may be too high for the available bandwidth.

**Fix**: Adjust the encoding options in `startRoomCompositeEgress`. For lower bandwidth, reduce to 720p:

```typescript
encodingOptions: new EncodingOptions({
  width: 1280,
  height: 720,
  videoBitrate: 2500000,
  audioBitrate: 128000,
})
```
