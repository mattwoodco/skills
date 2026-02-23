---
name: ai-image-gen
description: AI image generation with Replicate and fal.ai — text-to-image, image-to-image, inpainting with multiple model support. Use this skill when the user says "add image generation", "setup ai images", "add replicate", "text to image", or "ai image gen".
author: "@mattwoodco"
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
dependencies: [db, env-config, auth, storage, add-shadcn]
---

# AI Image Generation

Multi-provider AI image generation using [Replicate](https://replicate.com) and [fal.ai](https://fal.ai). Supports text-to-image, image-to-image, and inpainting across models like Flux, SDXL, and Ideogram. Generated images are stored permanently via the `storage` skill.

## Prerequisites

- Next.js app with App Router (with `src/` directory)
- `db` skill applied (Drizzle + Postgres)
- `env-config` skill applied
- `auth` skill applied
- `storage` skill applied (for permanent image storage)

## Installation

```bash
bun add replicate @fal-ai/client
```

## Environment Variables

Add to `.env.local`:

```env
# Image Generation Providers
REPLICATE_API_TOKEN=r8_...
FAL_KEY=fal_...
```

### Load from 1Password

If `REPLICATE_API_TOKEN` or `FAL_KEY` are empty or placeholders in `.env.local`, load them from 1Password:

```bash
# Load from 1Password (uses env-from-1password skill)
op item get "Dev Environment" --account=my.1password.com --fields label=notesPlain | tr -d '"' > /tmp/op-env.txt
grep -E "REPLICATE_API_TOKEN|FAL_KEY" /tmp/op-env.txt >> .env.local && rm /tmp/op-env.txt
```

Or use the `/env-from-1password` skill to load all keys at once — it writes `FAL_KEY`, `REPLICATE_API_TOKEN`, and other service keys to `.env.local`.

Add to `env.ts` server schema:

```typescript
REPLICATE_API_TOKEN: z.string().optional(),
FAL_KEY: z.string().optional(),
```

## What Gets Created

```
src/
├── app/
│   └── api/
│       └── ai/
│           └── images/
│               ├── route.ts                # POST generate, GET list generations
│               └── [id]/
│                   └── route.ts            # GET generation status/result
├── lib/
│   ├── ai/
│   │   └── image-gen/
│   │       ├── types.ts                    # ImageGenRequest, ImageGenResult, ModelConfig
│   │       ├── models.ts                   # Model registry: name → provider + model ID + defaults
│   │       ├── providers/
│   │       │   ├── replicate.ts            # Replicate API client
│   │       │   └── fal.ts                  # fal.ai client
│   │       └── generate.ts                 # Unified generate() — picks provider, submits, stores
│   └── db/
│       └── schema/
│           └── generations.ts              # Drizzle schema: generations table
```

## Setup Steps

### Step 1: Create `src/lib/db/schema/generations.ts`

```typescript
import { pgTable, text, integer, timestamp, jsonb, uuid } from "drizzle-orm/pg-core";

export const generations = pgTable("generations", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull(),
  type: text("type", {
    enum: ["text-to-image", "image-to-image", "inpainting"],
  }).notNull(),
  status: text("status", {
    enum: ["pending", "processing", "completed", "failed"],
  }).notNull().default("pending"),
  provider: text("provider").notNull(),
  model: text("model").notNull(),
  prompt: text("prompt").notNull(),
  negativePrompt: text("negative_prompt"),
  width: integer("width").default(1024),
  height: integer("height").default(1024),
  seed: integer("seed"),
  inputImageUrl: text("input_image_url"),
  maskImageUrl: text("mask_image_url"),
  resultUrl: text("result_url"),
  providerJobId: text("provider_job_id"),
  metadata: jsonb("metadata"),
  error: text("error"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  completedAt: timestamp("completed_at", { withTimezone: true }),
});

export type Generation = typeof generations.$inferSelect;
export type NewGeneration = typeof generations.$inferInsert;
```

### Step 2: Add export to `src/lib/db/schema/index.ts`

```typescript
export * from "./generations";
```

### Step 3: Create `src/lib/ai/image-gen/types.ts`

```typescript
export type ImageProvider = "replicate" | "fal";

export type ImageGenRequest = {
  prompt: string;
  negativePrompt?: string;
  model?: string;
  width?: number;
  height?: number;
  seed?: number;
  inputImageUrl?: string;
  maskImageUrl?: string;
  numOutputs?: number;
  guidanceScale?: number;
};

export type ImageGenResult = {
  url: string;
  seed?: number;
  width: number;
  height: number;
  provider: ImageProvider;
  model: string;
  providerJobId: string;
};

export type ModelConfig = {
  provider: ImageProvider;
  modelId: string;
  name: string;
  description: string;
  defaults: {
    width: number;
    height: number;
    guidanceScale: number;
  };
  capabilities: ("text-to-image" | "image-to-image" | "inpainting")[];
};
```

### Step 4: Create `src/lib/ai/image-gen/models.ts`

```typescript
import type { ModelConfig } from "./types";

export const IMAGE_MODELS: Record<string, ModelConfig> = {
  "flux-schnell": {
    provider: "replicate",
    modelId: "black-forest-labs/flux-schnell",
    name: "Flux Schnell",
    description: "Fast generation, good quality",
    defaults: { width: 1024, height: 1024, guidanceScale: 3.5 },
    capabilities: ["text-to-image"],
  },
  "flux-dev": {
    provider: "replicate",
    modelId: "black-forest-labs/flux-dev",
    name: "Flux Dev",
    description: "High quality, slower",
    defaults: { width: 1024, height: 1024, guidanceScale: 3.5 },
    capabilities: ["text-to-image", "image-to-image"],
  },
  "flux-pro": {
    provider: "fal",
    modelId: "fal-ai/flux-pro/v1.1",
    name: "Flux Pro",
    description: "Best quality Flux model",
    defaults: { width: 1024, height: 1024, guidanceScale: 3.5 },
    capabilities: ["text-to-image", "image-to-image"],
  },
  "sdxl": {
    provider: "replicate",
    modelId: "stability-ai/sdxl:7762fd07cf82c948538e41f63f77d685e02b063e37e496e96eefd46c929f9bdc",
    name: "Stable Diffusion XL",
    description: "Versatile, supports inpainting",
    defaults: { width: 1024, height: 1024, guidanceScale: 7.5 },
    capabilities: ["text-to-image", "image-to-image", "inpainting"],
  },
};

export const DEFAULT_MODEL = "flux-schnell";

export function getModelConfig(modelName?: string): ModelConfig {
  const name = modelName ?? DEFAULT_MODEL;
  const config = IMAGE_MODELS[name];
  if (!config) {
    throw new Error(`Unknown model: ${name}. Available: ${Object.keys(IMAGE_MODELS).join(", ")}`);
  }
  return config;
}
```

### Step 5: Create `src/lib/ai/image-gen/providers/replicate.ts`

```typescript
import Replicate from "replicate";

const replicate = new Replicate();

export async function generateWithReplicate(params: {
  modelId: string;
  prompt: string;
  negativePrompt?: string;
  width?: number;
  height?: number;
  seed?: number;
  inputImageUrl?: string;
  maskImageUrl?: string;
  guidanceScale?: number;
  numOutputs?: number;
}): Promise<{ urls: string[]; predictionId: string }> {
  const input: Record<string, unknown> = {
    prompt: params.prompt,
    width: params.width ?? 1024,
    height: params.height ?? 1024,
    num_outputs: params.numOutputs ?? 1,
  };

  if (params.negativePrompt) input.negative_prompt = params.negativePrompt;
  if (params.seed !== undefined) input.seed = params.seed;
  if (params.guidanceScale !== undefined) input.guidance_scale = params.guidanceScale;
  if (params.inputImageUrl) input.image = params.inputImageUrl;
  if (params.maskImageUrl) input.mask = params.maskImageUrl;

  const prediction = await replicate.predictions.create({
    model: params.modelId as `${string}/${string}`,
    input,
  });

  // Poll for completion
  let result = prediction;
  while (result.status !== "succeeded" && result.status !== "failed") {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    result = await replicate.predictions.get(prediction.id);
  }

  if (result.status === "failed") {
    throw new Error(`Replicate prediction failed: ${result.error}`);
  }

  const output = result.output;
  const urls = Array.isArray(output) ? (output as string[]) : [String(output)];

  return { urls, predictionId: prediction.id };
}
```

### Step 6: Create `src/lib/ai/image-gen/providers/fal.ts`

```typescript
import { fal } from "@fal-ai/client";

export async function generateWithFal(params: {
  modelId: string;
  prompt: string;
  negativePrompt?: string;
  width?: number;
  height?: number;
  seed?: number;
  inputImageUrl?: string;
  guidanceScale?: number;
  numOutputs?: number;
}): Promise<{ urls: string[]; requestId: string }> {
  const input: Record<string, unknown> = {
    prompt: params.prompt,
    image_size: {
      width: params.width ?? 1024,
      height: params.height ?? 1024,
    },
    num_images: params.numOutputs ?? 1,
  };

  if (params.negativePrompt) input.negative_prompt = params.negativePrompt;
  if (params.seed !== undefined) input.seed = params.seed;
  if (params.guidanceScale !== undefined) input.guidance_scale = params.guidanceScale;
  if (params.inputImageUrl) input.image_url = params.inputImageUrl;

  const result = await fal.subscribe(params.modelId, { input });

  type FalImage = { url: string };
  const data = result.data as { images?: FalImage[] };
  const urls = (data.images ?? []).map((img) => img.url);

  return { urls, requestId: result.requestId };
}
```

### Step 7: Create `src/lib/ai/image-gen/generate.ts`

```typescript
import { getModelConfig } from "./models";
import { generateWithReplicate } from "./providers/replicate";
import { generateWithFal } from "./providers/fal";
import { getStorageProvider } from "@/lib/storage/storage-provider";
import type { ImageGenRequest, ImageGenResult } from "./types";

export async function generateImage(
  request: ImageGenRequest
): Promise<ImageGenResult> {
  const config = getModelConfig(request.model);

  const width = request.width ?? config.defaults.width;
  const height = request.height ?? config.defaults.height;
  const guidanceScale = request.guidanceScale ?? config.defaults.guidanceScale;

  let urls: string[];
  let providerJobId: string;

  if (config.provider === "replicate") {
    const result = await generateWithReplicate({
      modelId: config.modelId,
      prompt: request.prompt,
      negativePrompt: request.negativePrompt,
      width,
      height,
      seed: request.seed,
      inputImageUrl: request.inputImageUrl,
      maskImageUrl: request.maskImageUrl,
      guidanceScale,
      numOutputs: request.numOutputs,
    });
    urls = result.urls;
    providerJobId = result.predictionId;
  } else {
    const result = await generateWithFal({
      modelId: config.modelId,
      prompt: request.prompt,
      negativePrompt: request.negativePrompt,
      width,
      height,
      seed: request.seed,
      inputImageUrl: request.inputImageUrl,
      guidanceScale,
      numOutputs: request.numOutputs,
    });
    urls = result.urls;
    providerJobId = result.requestId;
  }

  if (urls.length === 0) {
    throw new Error("No images generated");
  }

  // Download and store permanently via storage skill
  const imageResponse = await fetch(urls[0]);
  const arrayBuffer = await imageResponse.arrayBuffer();
  const buffer = Buffer.from(arrayBuffer);

  const storage = getStorageProvider();
  const stored = await storage.upload(
    `generations/${Date.now()}.png`,
    buffer,
    { contentType: "image/png" },
  );

  return {
    url: stored.url,
    seed: request.seed,
    width,
    height,
    provider: config.provider,
    model: request.model ?? "flux-schnell",
    providerJobId,
  };
}
```

### Step 8: Create `src/app/api/ai/images/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod";
import { db } from "@/lib/db";
import { generations } from "@/lib/db/schema";
import { eq, desc } from "drizzle-orm";
import { generateImage } from "@/lib/ai/image-gen/generate";
import { withAuth } from "@/lib/auth-guard";

const generateSchema = z.object({
  prompt: z.string().min(1).max(2000),
  negativePrompt: z.string().optional(),
  model: z.string().optional(),
  width: z.number().min(256).max(2048).optional(),
  height: z.number().min(256).max(2048).optional(),
  seed: z.number().optional(),
  inputImageUrl: z.string().url().optional(),
  maskImageUrl: z.string().url().optional(),
});

export const POST = withAuth(async (request, { user }) => {
  const body = await request.json();
  const params = generateSchema.parse(body);

  // Determine generation type
  let type: "text-to-image" | "image-to-image" | "inpainting" = "text-to-image";
  if (params.maskImageUrl) type = "inpainting";
  else if (params.inputImageUrl) type = "image-to-image";

  // Create generation record
  const [generation] = await db
    .insert(generations)
    .values({
      userId: user.id,
      type,
      provider: "replicate",
      model: params.model ?? "flux-schnell",
      prompt: params.prompt,
      negativePrompt: params.negativePrompt,
      width: params.width,
      height: params.height,
      seed: params.seed,
      inputImageUrl: params.inputImageUrl,
      maskImageUrl: params.maskImageUrl,
      status: "processing",
    })
    .returning();

  try {
    const result = await generateImage(params);

    // Update with result
    const [updated] = await db
      .update(generations)
      .set({
        status: "completed",
        resultUrl: result.url,
        provider: result.provider,
        model: result.model,
        seed: result.seed,
        providerJobId: result.providerJobId,
        completedAt: new Date(),
      })
      .where(eq(generations.id, generation.id))
      .returning();

    return NextResponse.json(updated);
  } catch (error) {
    await db
      .update(generations)
      .set({
        status: "failed",
        error: error instanceof Error ? error.message : "Unknown error",
      })
      .where(eq(generations.id, generation.id));

    return NextResponse.json(
      { error: "Generation failed", details: error instanceof Error ? error.message : "Unknown" },
      { status: 500 }
    );
  }
});

export const GET = withAuth(async (request, { user }) => {
  const { searchParams } = new URL(request.url);
  const limit = Math.min(parseInt(searchParams.get("limit") ?? "20", 10), 100);

  const userGenerations = await db
    .select()
    .from(generations)
    .where(eq(generations.userId, user.id))
    .orderBy(desc(generations.createdAt))
    .limit(limit);

  return NextResponse.json(userGenerations);
});
```

### Step 9: Create `src/app/api/ai/images/[id]/route.ts`

```typescript
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { db } from "@/lib/db";
import { generations } from "@/lib/db/schema";
import { eq, and } from "drizzle-orm";
import { withAuth } from "@/lib/auth-guard";

export const GET = withAuth(async (request: NextRequest, { user }) => {
  // Extract ID from URL since withAuth wraps the route context
  const id = request.nextUrl.pathname.split("/").pop() ?? "";

  const [generation] = await db
    .select()
    .from(generations)
    .where(and(eq(generations.id, id), eq(generations.userId, user.id)))
    .limit(1);

  if (!generation) {
    return NextResponse.json({ error: "Generation not found" }, { status: 404 });
  }

  return NextResponse.json(generation);
});

export const DELETE = withAuth(async (request: NextRequest, { user }) => {
  const id = request.nextUrl.pathname.split("/").pop() ?? "";

  const [deleted] = await db
    .delete(generations)
    .where(and(eq(generations.id, id), eq(generations.userId, user.id)))
    .returning();

  if (!deleted) {
    return NextResponse.json({ error: "Generation not found" }, { status: 404 });
  }

  return NextResponse.json({ success: true });
});
```

### Step 10: Push database schema

```bash
bunx drizzle-kit push
```

## Usage

### Generate an image

```typescript
const response = await fetch("/api/ai/images", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    prompt: "A sunset over mountains, oil painting style",
    model: "flux-schnell",
    width: 1024,
    height: 1024,
  }),
});
const generation = await response.json();
// { id, status: "completed", resultUrl: "https://..." }
```

### Image-to-image

```typescript
const response = await fetch("/api/ai/images", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    prompt: "Make it look like watercolor",
    model: "flux-dev",
    inputImageUrl: "https://your-storage.com/original.png",
  }),
});
```

### List generations

```typescript
const response = await fetch("/api/ai/images?limit=20");
const generations = await response.json();
```

## Available Models

| Model | Provider | Speed | Quality | Capabilities |
|-------|----------|-------|---------|-------------|
| `flux-schnell` | Replicate | Fast | Good | text-to-image |
| `flux-dev` | Replicate | Medium | High | text-to-image, image-to-image |
| `flux-pro` | fal.ai | Medium | Best | text-to-image, image-to-image |
| `sdxl` | Replicate | Medium | Good | text-to-image, image-to-image, inpainting |

## Acceptance Criteria

- POST `/api/ai/images` with a prompt → returns completed generation with result URL
- Image is stored permanently via storage skill (not ephemeral provider URL)
- GET `/api/ai/images` lists user's generations
- GET `/api/ai/images/[id]` returns individual generation
- DELETE `/api/ai/images/[id]` removes a generation
- Generation metadata (seed, model, prompt, dimensions) is persisted
- `tsc` passes with no errors
- Build succeeds
