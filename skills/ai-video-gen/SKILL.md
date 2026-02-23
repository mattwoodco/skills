---
name: ai-video-gen
description: AI video generation with Replicate and fal.ai — text-to-video, image-to-video with multiple model support. Use this skill when the user says "add video generation", "setup ai video", "text to video", "image to video", or "ai video gen".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-13
updated: 2026-02-13
dependencies: [db, env-config, auth, storage, add-shadcn]
---

# AI Video Generation

Multi-provider AI video generation using [Replicate](https://replicate.com) and [fal.ai](https://fal.ai). Supports text-to-video and image-to-video with models like Minimax, Kling, and Luma. Videos are stored permanently via the `storage` skill.

## Prerequisites

- Next.js app with App Router (with `src/` directory)
- `db` skill applied (Drizzle + Postgres)
- `env-config` skill applied
- `auth` skill applied
- `storage` skill applied (for permanent video storage)
- `replicate` and `@fal-ai/client` packages installed (from `ai-image-gen` or install separately)

## Installation

```bash
bun add replicate @fal-ai/client
```

## Environment Variables

Same as `ai-image-gen` — add to `.env.local` if not already present:

```env
REPLICATE_API_TOKEN=r8_...
FAL_KEY=fal_...
```

> **Note:** `REPLICATE_API_TOKEN` and `FAL_KEY` are owned by the `ai-image-gen` skill (applied first in Layer 2). If `ai-image-gen` is already applied, these are already set — no need to configure them again.

If keys are missing, use the `/env-from-1password` skill to load them from 1Password.

## What Gets Created

```
app/
└── api/
    └── ai/
        └── videos/
            ├── route.ts                # POST generate, GET list generations
            └── [id]/
                └── route.ts            # GET status/result, DELETE
lib/
└── ai/
    └── video-gen/
        ├── types.ts                    # VideoGenRequest, VideoGenResult, VideoModelConfig
        ├── models.ts                   # Video model registry
        ├── providers/
        │   ├── replicate.ts            # Replicate video prediction
        │   └── fal.ts                  # fal.ai video queue
        └── generate.ts                 # Unified video generation
db/
└── schema/
    └── video-generations.ts            # Drizzle schema: video_generations table
```

## Setup Steps

### Step 1: Create `db/schema/video-generations.ts`

```typescript
import { pgTable, text, integer, timestamp, jsonb, uuid } from "drizzle-orm/pg-core";

export const videoGenerations = pgTable("video_generations", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull(),
  type: text("type", {
    enum: ["text-to-video", "image-to-video"],
  }).notNull(),
  status: text("status", {
    enum: ["pending", "processing", "completed", "failed"],
  }).notNull().default("pending"),
  provider: text("provider").notNull(),
  model: text("model").notNull(),
  prompt: text("prompt").notNull(),
  inputImageUrl: text("input_image_url"),
  duration: integer("duration"),
  width: integer("width").default(1280),
  height: integer("height").default(720),
  resultUrl: text("result_url"),
  thumbnailUrl: text("thumbnail_url"),
  providerJobId: text("provider_job_id"),
  metadata: jsonb("metadata"),
  error: text("error"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  completedAt: timestamp("completed_at"),
});

export type VideoGeneration = typeof videoGenerations.$inferSelect;
export type NewVideoGeneration = typeof videoGenerations.$inferInsert;
```

### Step 2: Add export to `db/schema/index.ts`

```typescript
export * from "./video-generations";
```

### Step 3: Create `lib/ai/video-gen/types.ts`

```typescript
export type VideoProvider = "replicate" | "fal";

export type VideoGenRequest = {
  prompt: string;
  model?: string;
  inputImageUrl?: string;
  duration?: number;
  width?: number;
  height?: number;
  seed?: number;
};

export type VideoGenResult = {
  url: string;
  duration: number;
  width: number;
  height: number;
  provider: VideoProvider;
  model: string;
  providerJobId: string;
};

export type VideoModelConfig = {
  provider: VideoProvider;
  modelId: string;
  name: string;
  description: string;
  maxDuration: number;
  defaults: {
    width: number;
    height: number;
    duration: number;
  };
  capabilities: ("text-to-video" | "image-to-video")[];
};
```

### Step 4: Create `lib/ai/video-gen/models.ts`

```typescript
import type { VideoModelConfig } from "./types";

export const VIDEO_MODELS: Record<string, VideoModelConfig> = {
  "minimax-video": {
    provider: "replicate",
    modelId: "minimax/video-01",
    name: "Minimax Video-01",
    description: "Fast, high quality video generation",
    maxDuration: 6,
    defaults: { width: 1280, height: 720, duration: 5 },
    capabilities: ["text-to-video", "image-to-video"],
  },
  "luma-dream-machine": {
    provider: "fal",
    modelId: "fal-ai/luma-dream-machine",
    name: "Luma Dream Machine",
    description: "Cinematic quality, longer videos",
    maxDuration: 10,
    defaults: { width: 1280, height: 720, duration: 5 },
    capabilities: ["text-to-video", "image-to-video"],
  },
  "kling-video": {
    provider: "fal",
    modelId: "fal-ai/kling-video/v1.5/pro",
    name: "Kling Video v1.5",
    description: "Professional quality, good motion",
    maxDuration: 10,
    defaults: { width: 1280, height: 720, duration: 5 },
    capabilities: ["text-to-video", "image-to-video"],
  },
};

export const DEFAULT_VIDEO_MODEL = "minimax-video";

export function getVideoModelConfig(modelName?: string): VideoModelConfig {
  const name = modelName ?? DEFAULT_VIDEO_MODEL;
  const config = VIDEO_MODELS[name];
  if (!config) {
    throw new Error(
      `Unknown video model: ${name}. Available: ${Object.keys(VIDEO_MODELS).join(", ")}`
    );
  }
  return config;
}
```

### Step 5: Create `lib/ai/video-gen/providers/replicate.ts`

```typescript
import Replicate from "replicate";

const replicate = new Replicate();

export async function generateVideoWithReplicate(params: {
  modelId: string;
  prompt: string;
  inputImageUrl?: string;
  duration?: number;
  width?: number;
  height?: number;
}): Promise<{ url: string; predictionId: string }> {
  const input: Record<string, unknown> = {
    prompt: params.prompt,
  };

  if (params.inputImageUrl) input.first_frame_image = params.inputImageUrl;
  if (params.duration) input.duration = params.duration;

  const prediction = await replicate.predictions.create({
    model: params.modelId as `${string}/${string}`,
    input,
  });

  // Poll for completion — video generation can take 30s-5min
  let result = prediction;
  const maxWait = 5 * 60 * 1000; // 5 minutes
  const start = Date.now();

  while (result.status !== "succeeded" && result.status !== "failed") {
    if (Date.now() - start > maxWait) {
      throw new Error("Video generation timed out after 5 minutes");
    }
    await new Promise((resolve) => setTimeout(resolve, 3000));
    result = await replicate.predictions.get(prediction.id);
  }

  if (result.status === "failed") {
    throw new Error(`Replicate prediction failed: ${result.error}`);
  }

  const output = result.output;
  const url = typeof output === "string" ? output : Array.isArray(output) ? String(output[0]) : String(output);

  return { url, predictionId: prediction.id };
}
```

### Step 6: Create `lib/ai/video-gen/providers/fal.ts`

```typescript
import { fal } from "@fal-ai/client";

export async function generateVideoWithFal(params: {
  modelId: string;
  prompt: string;
  inputImageUrl?: string;
  duration?: number;
  width?: number;
  height?: number;
}): Promise<{ url: string; requestId: string }> {
  const input: Record<string, unknown> = {
    prompt: params.prompt,
  };

  if (params.inputImageUrl) input.image_url = params.inputImageUrl;
  if (params.duration) input.duration = params.duration;

  const result = await fal.subscribe(params.modelId, {
    input,
    pollInterval: 3000,
  });

  type FalVideo = { url: string };
  const data = result.data as { video?: FalVideo };
  const url = data.video?.url;

  if (!url) {
    throw new Error("No video URL in fal.ai response");
  }

  return { url, requestId: result.requestId };
}
```

### Step 7: Create `lib/ai/video-gen/generate.ts`

```typescript
import { getVideoModelConfig } from "./models";
import { generateVideoWithReplicate } from "./providers/replicate";
import { generateVideoWithFal } from "./providers/fal";
import { getStorageProvider } from "@src/lib/storage/storage-provider";
import type { VideoGenRequest, VideoGenResult } from "./types";

export async function generateVideo(
  request: VideoGenRequest
): Promise<VideoGenResult> {
  const config = getVideoModelConfig(request.model);

  const width = request.width ?? config.defaults.width;
  const height = request.height ?? config.defaults.height;
  const duration = Math.min(request.duration ?? config.defaults.duration, config.maxDuration);

  let providerUrl: string;
  let providerJobId: string;

  if (config.provider === "replicate") {
    const result = await generateVideoWithReplicate({
      modelId: config.modelId,
      prompt: request.prompt,
      inputImageUrl: request.inputImageUrl,
      duration,
      width,
      height,
    });
    providerUrl = result.url;
    providerJobId = result.predictionId;
  } else {
    const result = await generateVideoWithFal({
      modelId: config.modelId,
      prompt: request.prompt,
      inputImageUrl: request.inputImageUrl,
      duration,
      width,
      height,
    });
    providerUrl = result.url;
    providerJobId = result.requestId;
  }

  // Download and store permanently
  const videoResponse = await fetch(providerUrl);
  const arrayBuffer = await videoResponse.arrayBuffer();
  const buffer = Buffer.from(arrayBuffer);

  const storage = getStorageProvider();
  const storageKey = `videos/${Date.now()}.mp4`;
  const stored = await storage.upload(storageKey, buffer, {
    contentType: "video/mp4",
  });

  return {
    url: stored.url,
    duration,
    width,
    height,
    provider: config.provider,
    model: request.model ?? "minimax-video",
    providerJobId,
  };
}
```

### Step 8: Create `app/api/ai/videos/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod";
import { db } from "@src/lib/db";
import { videoGenerations } from "@src/lib/db/schema";
import { eq, desc } from "drizzle-orm";
import { generateVideo } from "@src/lib/ai/video-gen/generate";
import { auth } from "@src/lib/auth";
import { headers } from "next/headers";

const generateSchema = z.object({
  prompt: z.string().min(1).max(2000),
  model: z.string().optional(),
  inputImageUrl: z.string().url().optional(),
  duration: z.number().min(1).max(10).optional(),
  width: z.number().min(480).max(1920).optional(),
  height: z.number().min(480).max(1080).optional(),
});

export async function POST(request: Request) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json();
  const params = generateSchema.parse(body);

  const type = params.inputImageUrl ? "image-to-video" : "text-to-video";

  // Create record
  const [generation] = await db
    .insert(videoGenerations)
    .values({
      userId: session.user.id,
      type,
      provider: "replicate",
      model: params.model ?? "minimax-video",
      prompt: params.prompt,
      inputImageUrl: params.inputImageUrl,
      duration: params.duration,
      width: params.width,
      height: params.height,
      status: "processing",
    })
    .returning();

  try {
    const result = await generateVideo(params);

    const [updated] = await db
      .update(videoGenerations)
      .set({
        status: "completed",
        resultUrl: result.url,
        provider: result.provider,
        model: result.model,
        duration: result.duration,
        providerJobId: result.providerJobId,
        completedAt: new Date(),
      })
      .where(eq(videoGenerations.id, generation.id))
      .returning();

    return NextResponse.json(updated);
  } catch (error) {
    await db
      .update(videoGenerations)
      .set({
        status: "failed",
        error: error instanceof Error ? error.message : "Unknown error",
      })
      .where(eq(videoGenerations.id, generation.id));

    return NextResponse.json(
      { error: "Video generation failed", details: error instanceof Error ? error.message : "Unknown" },
      { status: 500 }
    );
  }
}

export async function GET(request: Request) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const limit = Math.min(parseInt(searchParams.get("limit") ?? "20", 10), 100);

  const userGenerations = await db
    .select()
    .from(videoGenerations)
    .where(eq(videoGenerations.userId, session.user.id))
    .orderBy(desc(videoGenerations.createdAt))
    .limit(limit);

  return NextResponse.json(userGenerations);
}
```

### Step 9: Create `app/api/ai/videos/[id]/route.ts`

```typescript
import { NextResponse } from "next/server";
import { db } from "@src/lib/db";
import { videoGenerations } from "@src/lib/db/schema";
import { eq, and } from "drizzle-orm";
import { auth } from "@src/lib/auth";
import { headers } from "next/headers";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;

  const [generation] = await db
    .select()
    .from(videoGenerations)
    .where(and(eq(videoGenerations.id, id), eq(videoGenerations.userId, session.user.id)))
    .limit(1);

  if (!generation) {
    return NextResponse.json({ error: "Video generation not found" }, { status: 404 });
  }

  return NextResponse.json(generation);
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;

  const [deleted] = await db
    .delete(videoGenerations)
    .where(and(eq(videoGenerations.id, id), eq(videoGenerations.userId, session.user.id)))
    .returning();

  if (!deleted) {
    return NextResponse.json({ error: "Video generation not found" }, { status: 404 });
  }

  return NextResponse.json({ success: true });
}
```

### Step 10: Push database schema

```bash
bunx drizzle-kit push
```

## Usage

### Generate a video from text

```typescript
const response = await fetch("/api/ai/videos", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    prompt: "A 5-second video of waves crashing on a beach at sunset",
    model: "minimax-video",
    duration: 5,
  }),
});
const generation = await response.json();
```

### Animate an image (image-to-video)

```typescript
const response = await fetch("/api/ai/videos", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    prompt: "Gentle camera zoom with flowing hair movement",
    model: "luma-dream-machine",
    inputImageUrl: "https://your-storage.com/portrait.png",
    duration: 5,
  }),
});
```

### List video generations

```typescript
const response = await fetch("/api/ai/videos?limit=20");
const generations = await response.json();
```

## Available Models

| Model | Provider | Speed | Max Duration | Capabilities |
|-------|----------|-------|-------------|-------------|
| `minimax-video` | Replicate | Fast | 6s | text-to-video, image-to-video |
| `luma-dream-machine` | fal.ai | Medium | 10s | text-to-video, image-to-video |
| `kling-video` | fal.ai | Slow | 10s | text-to-video, image-to-video |

## Acceptance Criteria

- POST `/api/ai/videos` with a text prompt → returns completed generation with video URL
- POST with `inputImageUrl` → performs image-to-video generation
- Video is stored permanently via storage skill
- GET `/api/ai/videos` lists user's video generations
- GET `/api/ai/videos/[id]` returns individual video status/result
- DELETE `/api/ai/videos/[id]` removes a generation
- `tsc` passes with no errors
- Build succeeds
