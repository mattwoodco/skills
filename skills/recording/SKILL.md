---
name: recording
description: Server-side room recording with LiveKit Egress — composite and track-based recording, S3 storage, recording metadata in Postgres. Use this skill when the user says "add recording", "record room", "record video", "record meeting", "egress recording", or "save recording".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [video-room, storage, queue, env-config]
---

# Recording (LiveKit Egress)

Server-side room recording using [LiveKit Egress](https://docs.livekit.io/egress/). Supports both composite recording (all participants in a single layout) and track-based recording (individual participant tracks). Recordings are stored to S3-compatible storage via `EncodedFileOutput` and tracked in Postgres with full metadata.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `video-room` skill applied (provides `livekit-server-sdk`, LiveKit server configuration)
- `storage` skill applied (provides S3-compatible storage with bucket)
- `queue` skill applied (provides Inngest for async job tracking)
- `env-config` skill applied (provides Zod env validation)

## Installation

No additional packages required. Uses `livekit-server-sdk` from the `video-room` skill and `@aws-sdk/client-s3` from the `storage` skill.

## Environment Variables

Uses existing environment variables from dependencies:

```env
# LiveKit (from video-room)
LIVEKIT_API_KEY=your_api_key
LIVEKIT_API_SECRET=your_api_secret
NEXT_PUBLIC_LIVEKIT_URL=wss://your-project.livekit.cloud

# S3 Storage (from storage)
S3_ENDPOINT=http://localhost:9000
S3_ACCESS_KEY=rustfsadmin
S3_SECRET_KEY=rustfsadmin
S3_BUCKET=uploads
S3_REGION=us-east-1
```

Add to `src/env.ts` server schema (if not already present from `video-room`):

```typescript
LIVEKIT_API_KEY: z.string().min(1).optional(),
LIVEKIT_API_SECRET: z.string().min(1).optional(),
```

And client schema:

```typescript
NEXT_PUBLIC_LIVEKIT_URL: z.string().url().optional(),
```

## What Gets Created

```
src/
├── lib/
│   ├── video/
│   │   ├── recording.ts               # Server functions: start, stop, list recordings
│   │   └── types-recording.ts         # RecordingConfig, RecordingResult, RecordingStatus
│   └── db/
│       └── schema/
│           └── recordings.ts          # Drizzle schema: recordings table
└── app/
    └── api/
        └── video/
            └── recordings/
                ├── route.ts           # POST start recording, GET list recordings
                └── [id]/
                    └── route.ts       # GET recording status/download URL, PATCH stop, DELETE
```

## Setup Steps

### Step 1: Create `src/lib/video/types-recording.ts`

```typescript
export type RecordingLayout = "speaker" | "grid" | "single-speaker";

export type RecordingResolution = {
  width: number;
  height: number;
};

export const RECORDING_PRESETS = {
  "720p": { width: 1280, height: 720 },
  "1080p": { width: 1920, height: 1080 },
  "480p": { width: 854, height: 480 },
} as const;

export type RecordingPreset = keyof typeof RECORDING_PRESETS;

export type RecordingCodec = "h264" | "vp8";

export type RecordingConfig = {
  roomName: string;
  layout?: RecordingLayout;
  resolution?: RecordingPreset;
  codec?: RecordingCodec;
  audioBitrate?: number;
  videoBitrate?: number;
  /** If true, records individual tracks instead of composite */
  trackBased?: boolean;
  /** Specific track SID to record (for track-based recording) */
  trackSid?: string;
};

export type RecordingStatusValue =
  | "starting"
  | "active"
  | "stopping"
  | "completed"
  | "failed";

export type RecordingResult = {
  id: string;
  roomName: string;
  egressId: string;
  status: RecordingStatusValue;
  startedAt: Date;
  stoppedAt: Date | null;
  fileUrl: string | null;
  duration: number | null;
  fileSize: number | null;
};

export type StartRecordingResponse = {
  recordingId: string;
  egressId: string;
  status: RecordingStatusValue;
};

export type StopRecordingResponse = {
  recordingId: string;
  egressId: string;
  status: RecordingStatusValue;
  fileUrl: string | null;
  duration: number | null;
};
```

### Step 2: Create `src/lib/db/schema/recordings.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  integer,
  real,
} from "drizzle-orm/pg-core";

export const recordings = pgTable("recordings", {
  id: uuid("id").primaryKey().defaultRandom(),
  roomName: text("room_name").notNull(),
  roomSid: text("room_sid"),
  egressId: text("egress_id").notNull(),
  status: text("status", {
    enum: ["starting", "active", "stopping", "completed", "failed"],
  })
    .notNull()
    .default("starting"),
  layout: text("layout", {
    enum: ["speaker", "grid", "single-speaker"],
  }).default("grid"),
  codec: text("codec").default("h264"),
  resolution: text("resolution").default("1080p"),
  startedAt: timestamp("started_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  stoppedAt: timestamp("stopped_at", { withTimezone: true }),
  fileUrl: text("file_url"),
  storageKey: text("storage_key"),
  fileSize: integer("file_size"),
  duration: real("duration"),
  userId: text("user_id").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export type Recording = typeof recordings.$inferSelect;
export type NewRecording = typeof recordings.$inferInsert;
```

### Step 3: Add export to `src/lib/db/schema/index.ts`

```typescript
export * from "./recordings";
```

### Step 4: Create `src/lib/video/recording.ts`

> **Important**: Use `EncodingOptionsPreset` (enum values) for encoding options instead of constructing partial `EncodingOptions` objects. The `EncodingOptions` interface requires many fields (depth, framerate, audioCodec, etc.) and partial objects will fail type-checking. Use `DirectFileOutput` (not `EncodedFileOutput`) for track-based egress — `startTrackEgress` requires `DirectFileOutput | string`.

```typescript
import {
  EgressClient,
  EncodedFileOutput,
  EncodedFileType,
  DirectFileOutput,
  EncodingOptionsPreset,
} from "livekit-server-sdk";
import { db } from "@/lib/db";
import { recordings } from "@/lib/db/schema/recordings";
import { eq, desc, and } from "drizzle-orm";
import type {
  RecordingConfig,
  RecordingStatusValue,
  StartRecordingResponse,
  StopRecordingResponse,
} from "./types-recording";
import type { Recording } from "@/lib/db/schema/recordings";
import type { RecordingPreset } from "./types-recording";

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
  const httpUrl = livekitUrl.replace("wss://", "https://").replace("ws://", "http://");
  return new EgressClient(httpUrl, apiKey, apiSecret);
}

function getEncodingPreset(resolution: RecordingPreset | undefined): EncodingOptionsPreset {
  switch (resolution) {
    case "480p":
      return EncodingOptionsPreset.H264_720P_30; // closest available preset
    case "720p":
      return EncodingOptionsPreset.H264_720P_30;
    case "1080p":
      return EncodingOptionsPreset.H264_1080P_30;
    default:
      return EncodingOptionsPreset.H264_1080P_30;
  }
}

function buildFileOutput(roomName: string, fileType: EncodedFileType): EncodedFileOutput {
  const bucket = process.env.S3_BUCKET ?? "uploads";
  const timestamp = Date.now();
  const filepath = `recordings/${roomName}/${timestamp}`;

  const output = new EncodedFileOutput({
    fileType,
    filepath,
    output: {
      case: "s3",
      value: {
        accessKey: process.env.S3_ACCESS_KEY ?? "",
        secret: process.env.S3_SECRET_KEY ?? "",
        region: process.env.S3_REGION ?? "us-east-1",
        bucket,
        endpoint: process.env.S3_ENDPOINT ?? "",
        forcePathStyle: true,
      },
    },
  });

  return output;
}

function buildDirectFileOutput(roomName: string): DirectFileOutput {
  const bucket = process.env.S3_BUCKET ?? "uploads";
  const timestamp = Date.now();
  const filepath = `recordings/${roomName}/${timestamp}`;

  return new DirectFileOutput({
    filepath,
    output: {
      case: "s3",
      value: {
        accessKey: process.env.S3_ACCESS_KEY ?? "",
        secret: process.env.S3_SECRET_KEY ?? "",
        region: process.env.S3_REGION ?? "us-east-1",
        bucket,
        endpoint: process.env.S3_ENDPOINT ?? "",
        forcePathStyle: true,
      },
    },
  });
}

export async function startRoomCompositeRecording(
  config: RecordingConfig,
  userId: string
): Promise<StartRecordingResponse> {
  const egressClient = getEgressClient();

  const fileType =
    config.codec === "vp8" ? EncodedFileType.OGG : EncodedFileType.MP4;

  const fileOutput = buildFileOutput(config.roomName, fileType);

  const layoutStr = config.layout ?? "grid";

  const egressInfo = await egressClient.startRoomCompositeEgress(
    config.roomName,
    fileOutput,
    {
      layout: layoutStr,
      encodingOptions: getEncodingPreset(config.resolution),
    }
  );

  const egressId = egressInfo.egressId;

  const [recording] = await db
    .insert(recordings)
    .values({
      roomName: config.roomName,
      roomSid: egressInfo.roomName,
      egressId,
      status: "active",
      layout: layoutStr,
      codec: config.codec ?? "h264",
      resolution: config.resolution ?? "1080p",
      userId,
    })
    .returning();

  return {
    recordingId: recording.id,
    egressId,
    status: "active",
  };
}

export async function startTrackRecording(
  config: RecordingConfig & { trackSid: string },
  userId: string
): Promise<StartRecordingResponse> {
  const egressClient = getEgressClient();

  const fileOutput = buildDirectFileOutput(config.roomName);

  const egressInfo = await egressClient.startTrackEgress(
    config.roomName,
    fileOutput,
    config.trackSid
  );

  const egressId = egressInfo.egressId;

  const [recording] = await db
    .insert(recordings)
    .values({
      roomName: config.roomName,
      roomSid: egressInfo.roomName,
      egressId,
      status: "active",
      layout: "single-speaker",
      codec: config.codec ?? "h264",
      resolution: config.resolution ?? "1080p",
      userId,
    })
    .returning();

  return {
    recordingId: recording.id,
    egressId,
    status: "active",
  };
}

export async function stopRecording(
  recordingId: string,
  userId: string
): Promise<StopRecordingResponse> {
  const [recording] = await db
    .select()
    .from(recordings)
    .where(
      and(eq(recordings.id, recordingId), eq(recordings.userId, userId))
    )
    .limit(1);

  if (!recording) {
    throw new Error("Recording not found");
  }

  if (recording.status !== "active") {
    throw new Error(`Recording is not active (status: ${recording.status})`);
  }

  const egressClient = getEgressClient();

  // Update status to stopping
  await db
    .update(recordings)
    .set({ status: "stopping", updatedAt: new Date() })
    .where(eq(recordings.id, recordingId));

  try {
    const egressInfo = await egressClient.stopEgress(recording.egressId);

    let fileUrl: string | null = null;
    let duration: number | null = null;
    let fileSize: number | null = null;
    let storageKey: string | null = null;

    const fileResults = egressInfo.fileResults;
    if (fileResults && fileResults.length > 0) {
      const firstFile = fileResults[0];
      fileUrl = firstFile.location;
      duration = Number(firstFile.duration) / 1_000_000_000; // nanoseconds to seconds
      fileSize = Number(firstFile.size);
      storageKey = firstFile.filename;
    }

    const stoppedAt = new Date();

    await db
      .update(recordings)
      .set({
        status: "completed",
        stoppedAt,
        fileUrl,
        storageKey,
        fileSize,
        duration,
        updatedAt: new Date(),
      })
      .where(eq(recordings.id, recordingId));

    return {
      recordingId,
      egressId: recording.egressId,
      status: "completed",
      fileUrl,
      duration,
    };
  } catch (error) {
    await db
      .update(recordings)
      .set({ status: "failed", updatedAt: new Date() })
      .where(eq(recordings.id, recordingId));

    throw error;
  }
}

export async function getRecording(
  recordingId: string,
  userId: string
): Promise<Recording | null> {
  const [recording] = await db
    .select()
    .from(recordings)
    .where(
      and(eq(recordings.id, recordingId), eq(recordings.userId, userId))
    )
    .limit(1);

  return recording ?? null;
}

export async function listRecordings(
  userId: string,
  options?: { roomName?: string; limit?: number }
): Promise<Recording[]> {
  const conditions = [eq(recordings.userId, userId)];

  if (options?.roomName) {
    conditions.push(eq(recordings.roomName, options.roomName));
  }

  return db
    .select()
    .from(recordings)
    .where(and(...conditions))
    .orderBy(desc(recordings.createdAt))
    .limit(options?.limit ?? 50);
}

export async function deleteRecording(
  recordingId: string,
  userId: string
): Promise<void> {
  const [recording] = await db
    .select()
    .from(recordings)
    .where(
      and(eq(recordings.id, recordingId), eq(recordings.userId, userId))
    )
    .limit(1);

  if (!recording) {
    throw new Error("Recording not found");
  }

  if (recording.status === "active") {
    const egressClient = getEgressClient();
    try {
      await egressClient.stopEgress(recording.egressId);
    } catch {
      // Egress may have already stopped
    }
  }

  await db.delete(recordings).where(eq(recordings.id, recordingId));
}

export async function getRecordingStatus(
  egressId: string
): Promise<RecordingStatusValue> {
  const egressClient = getEgressClient();

  try {
    const egressList = await egressClient.listEgress({ egressId });

    if (egressList.length === 0) {
      return "failed";
    }

    const egress = egressList[0];
    const statusValue = egress.status;

    // Map LiveKit EgressStatus to our status
    // EgressStatus values: EGRESS_STARTING=0, EGRESS_ACTIVE=1,
    // EGRESS_ENDING=2, EGRESS_COMPLETE=3, EGRESS_FAILED=4
    switch (statusValue) {
      case 0:
        return "starting";
      case 1:
        return "active";
      case 2:
        return "stopping";
      case 3:
        return "completed";
      case 4:
        return "failed";
      default:
        return "failed";
    }
  } catch {
    return "failed";
  }
}
```

### Step 5: Create `src/app/api/video/recordings/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod/v4";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import {
  startRoomCompositeRecording,
  startTrackRecording,
  listRecordings,
} from "@/lib/video/recording";
import type { RecordingConfig } from "@/lib/video/types-recording";

const startRecordingSchema = z.object({
  roomName: z.string().min(1),
  layout: z.enum(["speaker", "grid", "single-speaker"]).default("grid"),
  resolution: z.enum(["480p", "720p", "1080p"]).default("1080p"),
  codec: z.enum(["h264", "vp8"]).default("h264"),
  audioBitrate: z.number().int().positive().optional(),
  videoBitrate: z.number().int().positive().optional(),
  trackBased: z.boolean().default(false),
  trackSid: z.string().optional(),
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
    const config = startRecordingSchema.parse(body);

    if (config.trackBased) {
      if (!config.trackSid) {
        return NextResponse.json(
          { error: "trackSid is required for track-based recording" },
          { status: 400 }
        );
      }

      const result = await startTrackRecording(
        {
          ...config,
          trackSid: config.trackSid,
        },
        session.user.id
      );

      return NextResponse.json(result, { status: 201 });
    }

    const recordingConfig: RecordingConfig = {
      roomName: config.roomName,
      layout: config.layout,
      resolution: config.resolution,
      codec: config.codec,
      audioBitrate: config.audioBitrate,
      videoBitrate: config.videoBitrate,
    };

    const result = await startRoomCompositeRecording(
      recordingConfig,
      session.user.id
    );

    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Failed to start recording";
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

    const result = await listRecordings(session.user.id, {
      roomName,
      limit,
    });

    return NextResponse.json({ recordings: result });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Failed to list recordings";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 6: Create `src/app/api/video/recordings/[id]/route.ts`

```typescript
import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import {
  getRecording,
  stopRecording,
  deleteRecording,
  getRecordingStatus,
} from "@/lib/video/recording";
import { getStorageProvider } from "@/lib/storage/storage-provider";

type RouteParams = { params: Promise<{ id: string }> };

export async function GET(
  _request: Request,
  { params }: RouteParams
) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const recording = await getRecording(id, session.user.id);

    if (!recording) {
      return NextResponse.json(
        { error: "Recording not found" },
        { status: 404 }
      );
    }

    // If recording is active, check live status from LiveKit
    let liveStatus = recording.status;
    if (recording.status === "active" || recording.status === "starting") {
      liveStatus = await getRecordingStatus(recording.egressId);
    }

    // Generate a download URL if recording is completed and has a storage key
    let downloadUrl: string | null = null;
    if (recording.status === "completed" && recording.storageKey) {
      try {
        const storage = getStorageProvider();
        downloadUrl = await storage.getUrl(recording.storageKey, 3600);
      } catch {
        // Storage URL generation failed — return fileUrl as fallback
        downloadUrl = recording.fileUrl;
      }
    }

    return NextResponse.json({
      recording: {
        ...recording,
        status: liveStatus,
      },
      downloadUrl,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Failed to get recording";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function PATCH(
  _request: Request,
  { params }: RouteParams
) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const result = await stopRecording(id, session.user.id);
    return NextResponse.json(result);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Failed to stop recording";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function DELETE(
  _request: Request,
  { params }: RouteParams
) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    await deleteRecording(id, session.user.id);
    return NextResponse.json({ success: true });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Failed to delete recording";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 7: Push database schema

```bash
bunx drizzle-kit push
```

## Usage

### Start a composite recording

```typescript
const response = await fetch("/api/video/recordings", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    roomName: "my-room",
    layout: "grid",
    resolution: "1080p",
    codec: "h264",
  }),
});
const { recordingId, egressId, status } = await response.json();
```

### Start a track-based recording

```typescript
const response = await fetch("/api/video/recordings", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    roomName: "my-room",
    trackBased: true,
    trackSid: "TR_abc123",
  }),
});
const { recordingId } = await response.json();
```

### Stop a recording

```typescript
const response = await fetch(`/api/video/recordings/${recordingId}`, {
  method: "PATCH",
});
const { status, fileUrl, duration } = await response.json();
```

### Get recording with download URL

```typescript
const response = await fetch(`/api/video/recordings/${recordingId}`);
const { recording, downloadUrl } = await response.json();
// downloadUrl is a presigned S3 URL valid for 1 hour
```

### List recordings for a room

```typescript
const response = await fetch("/api/video/recordings?roomName=my-room&limit=20");
const { recordings } = await response.json();
```

### Delete a recording

```typescript
await fetch(`/api/video/recordings/${recordingId}`, {
  method: "DELETE",
});
```

### Server-side usage in other API routes

```typescript
import {
  startRoomCompositeRecording,
  stopRecording,
  listRecordings,
} from "@/lib/video/recording";

// Start recording programmatically
const result = await startRoomCompositeRecording(
  {
    roomName: "meeting-123",
    layout: "speaker",
    resolution: "720p",
  },
  userId
);

// Stop recording
const stopped = await stopRecording(result.recordingId, userId);

// List recordings
const userRecordings = await listRecordings(userId, {
  roomName: "meeting-123",
});
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/video/recordings` | Start recording (composite or track-based) |
| GET | `/api/video/recordings?roomName=&limit=` | List user's recordings |
| GET | `/api/video/recordings/[id]` | Get recording status + download URL |
| PATCH | `/api/video/recordings/[id]` | Stop a recording |
| DELETE | `/api/video/recordings/[id]` | Delete a recording |

## Acceptance Criteria

- [ ] POST `/api/video/recordings` starts a LiveKit room composite egress and returns recording ID
- [ ] Track-based recording works when `trackBased: true` and `trackSid` are provided
- [ ] PATCH `/api/video/recordings/[id]` stops the egress and updates the database record
- [ ] GET `/api/video/recordings/[id]` returns recording metadata and a presigned download URL
- [ ] GET `/api/video/recordings` lists recordings filtered by user, optional roomName
- [ ] DELETE `/api/video/recordings/[id]` stops active recording and removes the database record
- [ ] Recording files are stored to S3 via `EncodedFileOutput` with proper credentials
- [ ] `recordings` table in Postgres has correct schema with all columns
- [ ] All routes require authentication
- [ ] Duration is correctly converted from nanoseconds to seconds
- [ ] No `any` casts anywhere
- [ ] `tsc` passes with no errors
- [ ] Build succeeds

## Troubleshooting

### "Egress not found" when starting recording

**Symptoms**: `startRoomCompositeEgress` throws an error about the room not existing.

**Cause**: The room must have at least one active participant for egress to start.

**Fix**: Ensure participants have joined the room before starting a recording. The LiveKit room is only created when the first participant connects.

### Recording file is empty (0 bytes)

**Symptoms**: Recording completes but the file in S3 is empty.

**Cause**: The egress was stopped too quickly, or no media was being published in the room.

**Fix**: Ensure at least one participant is publishing audio or video. Wait at least a few seconds after starting recording before stopping.

### S3 permission denied

**Symptoms**: Egress fails with an S3 access error.

**Cause**: The S3 credentials in the `EncodedFileOutput` don't have write permission to the bucket.

**Fix**: Verify `S3_ACCESS_KEY`, `S3_SECRET_KEY`, and `S3_BUCKET` are correct. For local development with RustFS/MinIO, ensure the bucket exists:

```bash
bunx @rustfs/mc alias set local http://localhost:9000 rustfsadmin rustfsadmin
bunx @rustfs/mc mb local/uploads
```

### Recording status stuck on "starting"

**Symptoms**: Recording was started but status never changes to "active".

**Cause**: LiveKit Egress service may not be running or configured.

**Fix**: On LiveKit Cloud, Egress is enabled by default. For self-hosted, ensure the Egress service is running alongside the LiveKit server. Check LiveKit dashboard for egress status.

### Download URL expired

**Symptoms**: Presigned URL returns 403 Forbidden.

**Cause**: The presigned URL has expired (default 1 hour).

**Fix**: Re-fetch the recording via `GET /api/video/recordings/[id]` to generate a new presigned URL.

### EncodingOptions type errors

**Symptoms**: TypeScript error about missing properties on `EncodingOptions` (depth, framerate, audioCodec, etc.).

**Cause**: The `EncodingOptions` interface from `@livekit/protocol` requires many fields. Passing a partial object fails type-checking.

**Fix**: Use `EncodingOptionsPreset` enum values instead of constructing `EncodingOptions` objects. The SDK provides presets like `EncodingOptionsPreset.H264_720P_30`, `EncodingOptionsPreset.H264_1080P_30`, etc. Pass these to `RoomCompositeOptions.encodingOptions`.

### Track egress type errors

**Symptoms**: TypeScript error when passing `EncodedFileOutput` to `startTrackEgress`.

**Cause**: `startTrackEgress` expects `DirectFileOutput | string`, not `EncodedFileOutput`.

**Fix**: Use `DirectFileOutput` instead of `EncodedFileOutput` for track-based recording. The `DirectFileOutput` has the same S3 output configuration but without encoding-specific fields like `fileType`.
