---
name: stream-mux
description: MUX video infrastructure — live streaming, VOD uploads, asset management, and webhook processing. Use this skill when the user says "add mux", "setup video streaming", "add live streaming", "setup mux", "video uploads", or "stream-mux".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [env-config, db, storage]
---

# Stream MUX

MUX-powered video infrastructure with live streaming (RTMP ingest + HLS playback), client-side direct uploads for VOD, asset lifecycle management, and webhook processing for real-time status updates. All asset metadata is persisted to Postgres via Drizzle.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `env-config` skill applied (`src/env.ts` with Zod schema)
- `db` skill applied (Drizzle ORM + Postgres)
- `storage` skill applied (for supplementary file storage)
- MUX account with API credentials ([mux.com/dashboard](https://dashboard.mux.com))

## Installation

```bash
bun add @mux/mux-node
```

## Environment Variables

Add to `.env.local`:

```env
# MUX Video
MUX_TOKEN_ID=your-mux-token-id
MUX_TOKEN_SECRET=your-mux-token-secret
MUX_WEBHOOK_SIGNING_SECRET=your-mux-webhook-signing-secret
```

### Update `src/env.ts`

Add to the `server` object:

```typescript
server: {
  // ... existing variables
  MUX_TOKEN_ID: z.string().min(1).optional(),
  MUX_TOKEN_SECRET: z.string().min(1).optional(),
  MUX_WEBHOOK_SIGNING_SECRET: z.string().optional(),
},
```

Add to the `runtimeEnv` object:

```typescript
runtimeEnv: {
  // ... existing variables
  MUX_TOKEN_ID: process.env.MUX_TOKEN_ID,
  MUX_TOKEN_SECRET: process.env.MUX_TOKEN_SECRET,
  MUX_WEBHOOK_SIGNING_SECRET: process.env.MUX_WEBHOOK_SIGNING_SECRET,
},
```

## What Gets Created

```
src/
├── lib/
│   ├── video/
│   │   ├── mux.ts              # getMuxClient() singleton
│   │   ├── mux-live.ts         # Live stream CRUD operations
│   │   ├── mux-vod.ts          # VOD upload + asset management
│   │   ├── mux-webhooks.ts     # Webhook verification + event handling
│   │   └── types-mux.ts        # MuxAsset, MuxLiveStream, MuxUpload types
│   └── db/
│       └── schema/
│           └── mux-assets.ts   # Drizzle schema: mux_assets table
└── app/
    └── api/
        └── mux/
            ├── upload/
            │   └── route.ts    # POST — get direct upload URL
            ├── assets/
            │   ├── route.ts    # GET — list assets
            │   └── [id]/
            │       └── route.ts # GET asset, DELETE asset
            ├── live/
            │   └── route.ts    # POST create, GET list live streams
            └── webhook/
                └── route.ts    # POST — MUX webhook handler
```

## Setup Steps

### Step 1: Create `src/lib/video/types-mux.ts`

```typescript
export type MuxAssetStatus =
  | "preparing"
  | "ready"
  | "errored"
  | "deleted";

export type MuxAssetType = "vod" | "live";

export type MuxAsset = {
  id: string;
  playbackId: string;
  status: MuxAssetStatus;
  duration: number | null;
  resolution: string | null;
  createdAt: Date;
};

export type MuxLiveStream = {
  id: string;
  streamKey: string;
  rtmpUrl: string;
  playbackId: string;
  status: string;
};

export type MuxUpload = {
  id: string;
  url: string;
  assetId: string | null;
  status: string;
};

export type CreateLiveStreamOptions = {
  playbackPolicy?: "public" | "signed";
  reconnectWindow?: number;
  maxContinuousDuration?: number;
  newAssetSettings?: {
    playbackPolicy?: "public" | "signed";
  };
};

export type MuxWebhookEvent = {
  type: string;
  data: {
    id: string;
    playback_ids?: Array<{ id: string; policy: string }>;
    status?: string;
    duration?: number;
    resolution_tier?: string;
    stream_key?: string;
    asset_id?: string;
    upload_id?: string;
    new_asset_settings?: Record<string, unknown>;
    [key: string]: unknown;
  };
  environment?: { name: string; id: string };
  created_at: string;
};
```

### Step 2: Create `src/lib/video/mux.ts`

```typescript
import Mux from "@mux/mux-node";

let muxClient: Mux | null = null;

export function getMuxClient(): Mux {
  if (muxClient) return muxClient;

  const tokenId = process.env.MUX_TOKEN_ID;
  const tokenSecret = process.env.MUX_TOKEN_SECRET;

  if (!tokenId) throw new Error("MUX_TOKEN_ID is not set");
  if (!tokenSecret) throw new Error("MUX_TOKEN_SECRET is not set");

  muxClient = new Mux({
    tokenId,
    tokenSecret,
  });

  return muxClient;
}
```

### Step 3: Create `src/lib/video/mux-live.ts`

```typescript
import { getMuxClient } from "@/lib/video/mux";
import type {
  MuxLiveStream,
  CreateLiveStreamOptions,
} from "@/lib/video/types-mux";

/**
 * Create a new MUX live stream with RTMP ingest.
 * Returns the stream key, RTMP URL, and playback ID.
 */
export async function createLiveStream(
  options: CreateLiveStreamOptions = {}
): Promise<MuxLiveStream> {
  const mux = getMuxClient();

  const stream = await mux.video.liveStreams.create({
    playback_policy: [options.playbackPolicy ?? "public"],
    reconnect_window: options.reconnectWindow ?? 60,
    max_continuous_duration: options.maxContinuousDuration ?? 43200,
    new_asset_settings: {
      playback_policy: [
        options.newAssetSettings?.playbackPolicy ?? "public",
      ],
    },
  });

  const playbackId = stream.playback_ids?.[0]?.id ?? "";

  return {
    id: stream.id,
    streamKey: stream.stream_key ?? "",
    rtmpUrl: `rtmp://global-live.mux.com:5222/app/${stream.stream_key ?? ""}`,
    playbackId,
    status: stream.status ?? "idle",
  };
}

/**
 * Get the current status of a live stream.
 */
export async function getLiveStreamStatus(
  liveStreamId: string
): Promise<MuxLiveStream> {
  const mux = getMuxClient();
  const stream = await mux.video.liveStreams.retrieve(liveStreamId);
  const playbackId = stream.playback_ids?.[0]?.id ?? "";

  return {
    id: stream.id,
    streamKey: stream.stream_key ?? "",
    rtmpUrl: `rtmp://global-live.mux.com:5222/app/${stream.stream_key ?? ""}`,
    playbackId,
    status: stream.status ?? "idle",
  };
}

/**
 * Delete a live stream.
 */
export async function deleteLiveStream(liveStreamId: string): Promise<void> {
  const mux = getMuxClient();
  await mux.video.liveStreams.delete(liveStreamId);
}

/**
 * List all live streams.
 */
export async function listLiveStreams(): Promise<MuxLiveStream[]> {
  const mux = getMuxClient();
  const streams = await mux.video.liveStreams.list();

  const results: MuxLiveStream[] = [];
  for await (const stream of streams) {
    const playbackId = stream.playback_ids?.[0]?.id ?? "";
    results.push({
      id: stream.id,
      streamKey: stream.stream_key ?? "",
      rtmpUrl: `rtmp://global-live.mux.com:5222/app/${stream.stream_key ?? ""}`,
      playbackId,
      status: stream.status ?? "idle",
    });
  }

  return results;
}
```

### Step 4: Create `src/lib/video/mux-vod.ts`

```typescript
import { getMuxClient } from "@/lib/video/mux";
import type { MuxAsset, MuxUpload } from "@/lib/video/types-mux";

/**
 * Create a direct upload URL for client-side video uploads.
 * The client POSTs the video file directly to this URL.
 */
export async function createUploadUrl(): Promise<MuxUpload> {
  const mux = getMuxClient();

  const upload = await mux.video.uploads.create({
    cors_origin: "*",
    new_asset_settings: {
      playback_policy: ["public"],
      encoding_tier: "baseline",
    },
  });

  return {
    id: upload.id,
    url: upload.url ?? "",
    assetId: upload.asset_id ?? null,
    status: upload.status ?? "waiting",
  };
}

/**
 * Get a single MUX asset by ID.
 */
export async function getAsset(assetId: string): Promise<MuxAsset> {
  const mux = getMuxClient();
  const asset = await mux.video.assets.retrieve(assetId);
  const playbackId = asset.playback_ids?.[0]?.id ?? "";

  return {
    id: asset.id,
    playbackId,
    status: mapAssetStatus(asset.status ?? "preparing"),
    duration: asset.duration ?? null,
    resolution: asset.resolution_tier ?? null,
    createdAt: new Date(asset.created_at ?? Date.now()),
  };
}

/**
 * List all MUX assets.
 */
export async function listAssets(): Promise<MuxAsset[]> {
  const mux = getMuxClient();
  const assets = await mux.video.assets.list();

  const results: MuxAsset[] = [];
  for await (const asset of assets) {
    const playbackId = asset.playback_ids?.[0]?.id ?? "";
    results.push({
      id: asset.id,
      playbackId,
      status: mapAssetStatus(asset.status ?? "preparing"),
      duration: asset.duration ?? null,
      resolution: asset.resolution_tier ?? null,
      createdAt: new Date(asset.created_at ?? Date.now()),
    });
  }

  return results;
}

/**
 * Delete a MUX asset.
 */
export async function deleteAsset(assetId: string): Promise<void> {
  const mux = getMuxClient();
  await mux.video.assets.delete(assetId);
}

/**
 * Construct the MUX HLS playback URL for a given playback ID.
 */
export function getPlaybackUrl(playbackId: string): string {
  return `https://stream.mux.com/${playbackId}.m3u8`;
}

/**
 * Get the MUX thumbnail URL for a given playback ID.
 */
export function getThumbnailUrl(
  playbackId: string,
  options?: { width?: number; height?: number; time?: number; fitMode?: string }
): string {
  const params = new URLSearchParams();
  if (options?.width) params.set("width", String(options.width));
  if (options?.height) params.set("height", String(options.height));
  if (options?.time !== undefined) params.set("time", String(options.time));
  if (options?.fitMode) params.set("fit_mode", options.fitMode);
  const qs = params.toString();
  return `https://image.mux.com/${playbackId}/thumbnail.jpg${qs ? `?${qs}` : ""}`;
}

function mapAssetStatus(
  status: string
): "preparing" | "ready" | "errored" | "deleted" {
  switch (status) {
    case "ready":
      return "ready";
    case "errored":
      return "errored";
    case "deleted":
      return "deleted";
    default:
      return "preparing";
  }
}
```

### Step 5: Create `src/lib/video/mux-webhooks.ts`

```typescript
import { db } from "@/lib/db";
import { muxAssets } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import type { MuxWebhookEvent } from "@/lib/video/types-mux";

/**
 * Verify MUX webhook signature.
 * MUX uses a raw body + signature header for verification.
 */
export async function verifyMuxWebhook(
  rawBody: string,
  signatureHeader: string,
  signingSecret: string
): Promise<MuxWebhookEvent> {
  // Parse the signature header: t=<timestamp>,v1=<signature>
  const parts = signatureHeader.split(",");
  const timestampPart = parts.find((p) => p.startsWith("t="));
  const signaturePart = parts.find((p) => p.startsWith("v1="));

  if (!timestampPart || !signaturePart) {
    throw new Error("Invalid mux-signature format");
  }

  const timestamp = timestampPart.slice(2);
  const expectedSignature = signaturePart.slice(3);

  // Build the signed payload: timestamp.rawBody
  const payload = `${timestamp}.${rawBody}`;

  // Compute HMAC-SHA256
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(signingSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signatureBytes = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(payload)
  );
  const computedSignature = Array.from(new Uint8Array(signatureBytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  if (computedSignature !== expectedSignature) {
    throw new Error("Invalid webhook signature");
  }

  // Check timestamp freshness (within 5 minutes)
  const webhookTimestamp = Number.parseInt(timestamp, 10);
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - webhookTimestamp) > 300) {
    throw new Error("Webhook timestamp too old");
  }

  return JSON.parse(rawBody) as MuxWebhookEvent;
}

/**
 * Process a MUX webhook event and update database records.
 */
export async function handleMuxWebhook(
  event: MuxWebhookEvent
): Promise<void> {
  switch (event.type) {
    case "video.asset.ready": {
      const assetId = event.data.id;
      const playbackId = event.data.playback_ids?.[0]?.id ?? null;
      const duration = event.data.duration ?? null;
      const resolution = (event.data.resolution_tier as string) ?? null;

      await db
        .update(muxAssets)
        .set({
          status: "ready",
          muxPlaybackId: playbackId,
          duration: duration ? String(duration) : null,
          resolution,
          updatedAt: new Date(),
        })
        .where(eq(muxAssets.muxAssetId, assetId));
      break;
    }

    case "video.asset.errored": {
      const assetId = event.data.id;

      await db
        .update(muxAssets)
        .set({
          status: "errored",
          updatedAt: new Date(),
        })
        .where(eq(muxAssets.muxAssetId, assetId));
      break;
    }

    case "video.live_stream.active": {
      const streamId = event.data.id;

      await db
        .update(muxAssets)
        .set({
          status: "ready",
          updatedAt: new Date(),
        })
        .where(eq(muxAssets.muxAssetId, streamId));
      break;
    }

    case "video.live_stream.idle": {
      const streamId = event.data.id;

      await db
        .update(muxAssets)
        .set({
          status: "preparing",
          updatedAt: new Date(),
        })
        .where(eq(muxAssets.muxAssetId, streamId));
      break;
    }

    case "video.upload.asset_created": {
      const uploadId = event.data.id;
      const assetId = event.data.asset_id ?? null;

      if (assetId) {
        await db
          .update(muxAssets)
          .set({
            muxAssetId: assetId,
            status: "preparing",
            updatedAt: new Date(),
          })
          .where(eq(muxAssets.muxUploadId, uploadId));
      }
      break;
    }

    default:
      // Unhandled event type — log and ignore
      console.log(`Unhandled MUX webhook event: ${event.type}`);
  }
}
```

### Step 6: Create `src/lib/db/schema/mux-assets.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  pgEnum,
} from "drizzle-orm/pg-core";

export const muxAssetTypeEnum = pgEnum("mux_asset_type", ["vod", "live"]);

export const muxAssetStatusEnum = pgEnum("mux_asset_status", [
  "preparing",
  "ready",
  "errored",
  "deleted",
]);

export const muxAssets = pgTable("mux_assets", {
  id: uuid("id").primaryKey().defaultRandom(),
  muxAssetId: text("mux_asset_id"),
  muxPlaybackId: text("mux_playback_id"),
  muxUploadId: text("mux_upload_id"),
  type: muxAssetTypeEnum("type").notNull().default("vod"),
  status: muxAssetStatusEnum("status").notNull().default("preparing"),
  duration: text("duration"),
  resolution: text("resolution"),
  title: text("title"),
  userId: text("user_id").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export type MuxAssetRecord = typeof muxAssets.$inferSelect;
export type NewMuxAssetRecord = typeof muxAssets.$inferInsert;
```

### Step 7: Add export to `src/lib/db/schema/index.ts`

Find the existing exports in `src/lib/db/schema/index.ts` and add:

```typescript
export * from "./mux-assets";
```

### Step 8: Create `src/app/api/mux/upload/route.ts`

```typescript
import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import { db } from "@/lib/db";
import { muxAssets } from "@/lib/db/schema";
import { createUploadUrl } from "@/lib/video/mux-vod";

type UploadResponse = {
  uploadUrl: string;
  uploadId: string;
  assetRecordId: string;
};

/** POST /api/mux/upload — Get a direct upload URL from MUX */
export async function POST(
  request: Request
): Promise<NextResponse<UploadResponse | { error: string }>> {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json().catch(() => ({}));
    const title = (body as { title?: string }).title ?? "Untitled";

    const upload = await createUploadUrl();

    // Create a database record to track this upload
    const [record] = await db
      .insert(muxAssets)
      .values({
        muxUploadId: upload.id,
        type: "vod",
        status: "preparing",
        title,
        userId: session.user.id,
      })
      .returning();

    return NextResponse.json({
      uploadUrl: upload.url,
      uploadId: upload.id,
      assetRecordId: record.id,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to create upload URL";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 9: Create `src/app/api/mux/assets/route.ts`

```typescript
import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import { db } from "@/lib/db";
import { muxAssets } from "@/lib/db/schema";
import { eq, desc } from "drizzle-orm";
import type { MuxAssetRecord } from "@/lib/db/schema/mux-assets";

type AssetsResponse = {
  assets: MuxAssetRecord[];
};

/** GET /api/mux/assets — List assets for the authenticated user */
export async function GET(): Promise<
  NextResponse<AssetsResponse | { error: string }>
> {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const assets = await db
      .select()
      .from(muxAssets)
      .where(eq(muxAssets.userId, session.user.id))
      .orderBy(desc(muxAssets.createdAt));

    return NextResponse.json({ assets });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to list assets";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 10: Create `src/app/api/mux/assets/[id]/route.ts`

```typescript
import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import { db } from "@/lib/db";
import { muxAssets } from "@/lib/db/schema";
import { eq, and } from "drizzle-orm";
import { deleteAsset } from "@/lib/video/mux-vod";
import type { MuxAssetRecord } from "@/lib/db/schema/mux-assets";

type RouteParams = { params: Promise<{ id: string }> };

/** GET /api/mux/assets/[id] — Get a single asset */
export async function GET(
  _request: Request,
  { params }: RouteParams
): Promise<NextResponse<{ asset: MuxAssetRecord } | { error: string }>> {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;

  const [asset] = await db
    .select()
    .from(muxAssets)
    .where(and(eq(muxAssets.id, id), eq(muxAssets.userId, session.user.id)))
    .limit(1);

  if (!asset) {
    return NextResponse.json({ error: "Asset not found" }, { status: 404 });
  }

  return NextResponse.json({ asset });
}

/** DELETE /api/mux/assets/[id] — Delete an asset from MUX and the database */
export async function DELETE(
  _request: Request,
  { params }: RouteParams
): Promise<NextResponse<{ success: true } | { error: string }>> {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;

  const [asset] = await db
    .select()
    .from(muxAssets)
    .where(and(eq(muxAssets.id, id), eq(muxAssets.userId, session.user.id)))
    .limit(1);

  if (!asset) {
    return NextResponse.json({ error: "Asset not found" }, { status: 404 });
  }

  try {
    // Delete from MUX if we have an asset ID
    if (asset.muxAssetId) {
      await deleteAsset(asset.muxAssetId);
    }

    // Soft-delete in database by marking as deleted
    await db
      .update(muxAssets)
      .set({ status: "deleted", updatedAt: new Date() })
      .where(eq(muxAssets.id, id));

    return NextResponse.json({ success: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to delete asset";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 11: Create `src/app/api/mux/live/route.ts`

```typescript
import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import { db } from "@/lib/db";
import { muxAssets } from "@/lib/db/schema";
import { eq, desc, and } from "drizzle-orm";
import {
  createLiveStream,
  listLiveStreams,
} from "@/lib/video/mux-live";
import type { MuxLiveStream } from "@/lib/video/types-mux";
import type { MuxAssetRecord } from "@/lib/db/schema/mux-assets";

type CreateLiveResponse = {
  stream: MuxLiveStream;
  record: MuxAssetRecord;
};

type ListLiveResponse = {
  streams: MuxLiveStream[];
};

/** POST /api/mux/live — Create a new live stream */
export async function POST(
  request: Request
): Promise<NextResponse<CreateLiveResponse | { error: string }>> {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json().catch(() => ({}));
    const title = (body as { title?: string }).title ?? "Live Stream";

    const stream = await createLiveStream();

    // Create a database record
    const [record] = await db
      .insert(muxAssets)
      .values({
        muxAssetId: stream.id,
        muxPlaybackId: stream.playbackId,
        type: "live",
        status: "preparing",
        title,
        userId: session.user.id,
      })
      .returning();

    return NextResponse.json({ stream, record }, { status: 201 });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to create live stream";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

/** GET /api/mux/live — List live streams for the authenticated user */
export async function GET(): Promise<
  NextResponse<ListLiveResponse | { error: string }>
> {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    // Get user's live stream records from our DB
    const records = await db
      .select()
      .from(muxAssets)
      .where(
        and(
          eq(muxAssets.userId, session.user.id),
          eq(muxAssets.type, "live")
        )
      )
      .orderBy(desc(muxAssets.createdAt));

    // Fetch current status from MUX
    const allStreams = await listLiveStreams();
    const recordIds = new Set(records.map((r) => r.muxAssetId));
    const userStreams = allStreams.filter((s) => recordIds.has(s.id));

    return NextResponse.json({ streams: userStreams });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to list live streams";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 12: Create `src/app/api/mux/webhook/route.ts`

```typescript
import { NextResponse } from "next/server";
import {
  verifyMuxWebhook,
  handleMuxWebhook,
} from "@/lib/video/mux-webhooks";
import type { MuxWebhookEvent } from "@/lib/video/types-mux";

/** POST /api/mux/webhook — MUX webhook handler */
export async function POST(
  request: Request
): Promise<NextResponse<{ received: true } | { error: string }>> {
  const signingSecret = process.env.MUX_WEBHOOK_SIGNING_SECRET;

  try {
    const rawBody = await request.text();
    let event: MuxWebhookEvent;

    if (signingSecret) {
      const signatureHeader = request.headers.get("mux-signature");
      if (!signatureHeader) {
        return NextResponse.json(
          { error: "Missing mux-signature header" },
          { status: 400 }
        );
      }
      // Verify the webhook signature in production
      event = await verifyMuxWebhook(rawBody, signatureHeader, signingSecret);
    } else {
      // In development, skip signature verification
      event = JSON.parse(rawBody) as MuxWebhookEvent;
      console.warn(
        "MUX_WEBHOOK_SIGNING_SECRET is not set — skipping webhook signature verification"
      );
    }

    await handleMuxWebhook(event);

    return NextResponse.json({ received: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Webhook processing failed";
    console.error("MUX webhook error:", message);
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
```

### Step 13: Push database schema

```bash
bunx drizzle-kit push
```

## Usage

### Upload a Video (Client-Side)

```typescript
// 1. Get the upload URL from your API
const res = await fetch("/api/mux/upload", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ title: "My Video" }),
});
const { uploadUrl, assetRecordId } = await res.json();

// 2. Upload the file directly to MUX
await fetch(uploadUrl, {
  method: "PUT",
  body: videoFile, // File or Blob
});

// 3. Poll for asset readiness
const poll = setInterval(async () => {
  const assetRes = await fetch(`/api/mux/assets/${assetRecordId}`);
  const { asset } = await assetRes.json();
  if (asset.status === "ready") {
    clearInterval(poll);
    console.log("Playback ID:", asset.muxPlaybackId);
  }
}, 3000);
```

### Create a Live Stream

```typescript
const res = await fetch("/api/mux/live", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ title: "Friday Standup" }),
});
const { stream, record } = await res.json();

console.log("RTMP URL:", stream.rtmpUrl);
console.log("Stream Key:", stream.streamKey);
console.log("Playback ID:", stream.playbackId);
// Use the RTMP URL + stream key in OBS, Streamyard, etc.
```

### List User Assets

```typescript
const res = await fetch("/api/mux/assets");
const { assets } = await res.json();
```

### Delete an Asset

```typescript
await fetch(`/api/mux/assets/${assetRecordId}`, {
  method: "DELETE",
});
```

### Server-Side Usage

```typescript
import { getAsset, getPlaybackUrl, getThumbnailUrl } from "@/lib/video/mux-vod";
import { createLiveStream, getLiveStreamStatus } from "@/lib/video/mux-live";

// Get playback URL
const url = getPlaybackUrl("abcd1234");
// => https://stream.mux.com/abcd1234.m3u8

// Get thumbnail
const thumb = getThumbnailUrl("abcd1234", { width: 640, time: 5 });
// => https://image.mux.com/abcd1234/thumbnail.jpg?width=640&time=5

// Get asset details
const asset = await getAsset("mux-asset-id");

// Create live stream
const stream = await createLiveStream({
  reconnectWindow: 120,
  maxContinuousDuration: 86400,
});
```

## MUX Webhook Setup

1. Go to [MUX Dashboard > Webhooks](https://dashboard.mux.com/settings/webhooks)
2. Add a webhook endpoint: `https://your-domain.com/api/mux/webhook`
3. Copy the signing secret to `.env.local` as `MUX_WEBHOOK_SIGNING_SECRET`
4. For local development, use `ngrok http 3000` and set the ngrok URL as the webhook endpoint

### Webhook Events Handled

| Event | Action |
|-------|--------|
| `video.asset.ready` | Updates asset status, playback ID, duration, resolution |
| `video.asset.errored` | Marks asset as errored |
| `video.live_stream.active` | Marks live stream as active (ready) |
| `video.live_stream.idle` | Marks live stream as idle (preparing) |
| `video.upload.asset_created` | Links upload record to the new asset ID |

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/mux/upload` | Yes | Get a direct upload URL from MUX |
| GET | `/api/mux/assets` | Yes | List assets for authenticated user |
| GET | `/api/mux/assets/[id]` | Yes | Get single asset details |
| DELETE | `/api/mux/assets/[id]` | Yes | Delete asset from MUX + database |
| POST | `/api/mux/live` | Yes | Create a new live stream |
| GET | `/api/mux/live` | Yes | List user's live streams |
| POST | `/api/mux/webhook` | No | MUX webhook handler (signature verified) |

## Acceptance Criteria

- [ ] `bun add @mux/mux-node` installs without errors
- [ ] `MUX_TOKEN_ID` and `MUX_TOKEN_SECRET` are validated in `src/env.ts`
- [ ] `getMuxClient()` returns a singleton MUX client
- [ ] `POST /api/mux/upload` returns a direct upload URL and creates a database record
- [ ] `GET /api/mux/assets` lists assets scoped to the authenticated user
- [ ] `GET /api/mux/assets/[id]` returns asset details
- [ ] `DELETE /api/mux/assets/[id]` deletes from MUX and marks as deleted in database
- [ ] `POST /api/mux/live` creates a live stream with RTMP URL and stream key
- [ ] `GET /api/mux/live` lists live streams for the authenticated user
- [ ] `POST /api/mux/webhook` verifies MUX signature and updates database records
- [ ] Webhook processes `video.asset.ready`, `video.asset.errored`, `video.live_stream.active`, `video.live_stream.idle`, `video.upload.asset_created`
- [ ] `mux_assets` table exists with correct schema (uuid PK, timestamps with timezone)
- [ ] No usage of `any` type anywhere in the code
- [ ] `tsc` passes with no errors
- [ ] `bun run build` succeeds

## Troubleshooting

### "MUX_TOKEN_ID is not set"

**Symptoms**: Server error when calling MUX API endpoints.

**Cause**: Environment variables not loaded.

**Fix**: Ensure `.env.local` contains `MUX_TOKEN_ID` and `MUX_TOKEN_SECRET`. Get these from [MUX Dashboard > Settings > API Access Tokens](https://dashboard.mux.com/settings/access-tokens). Restart the dev server after updating.

### Upload URL returns 403

**Symptoms**: Client-side PUT to the MUX upload URL fails with 403.

**Cause**: CORS origin mismatch or the upload URL has expired.

**Fix**: The `cors_origin` is set to `"*"` by default. Ensure the upload is attempted within the URL's TTL (typically 24 hours). For production, restrict `cors_origin` to your domain.

### Webhook events not updating database

**Symptoms**: Asset records stay in "preparing" status forever.

**Cause**: MUX webhooks are not reaching your server, or the signing secret is wrong.

**Fix**:
1. Check [MUX Dashboard > Webhooks](https://dashboard.mux.com/settings/webhooks) for delivery failures
2. For local dev, use ngrok: `ngrok http 3000`
3. Verify `MUX_WEBHOOK_SIGNING_SECRET` matches the dashboard value
4. Without the signing secret set, webhooks still process but skip signature verification (dev only)

### Live stream not showing as active

**Symptoms**: Stream appears idle even though you are streaming.

**Cause**: There is a delay between starting an RTMP stream and MUX recognizing it. Additionally, the `video.live_stream.active` webhook may not have been received yet.

**Fix**: Wait 10-15 seconds after starting the stream. Check the MUX dashboard to confirm the stream is active. Verify your webhook endpoint is receiving events.

### "Invalid webhook signature"

**Symptoms**: Webhook endpoint returns 400 with signature error.

**Cause**: The signing secret does not match, or the request body was modified in transit.

**Fix**: Re-copy the signing secret from MUX Dashboard. Ensure no middleware modifies the request body before it reaches the webhook handler. The webhook route reads the raw body with `request.text()` to preserve the exact bytes for signature verification.
