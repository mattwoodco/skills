---
name: outpaint
description: AI image outpainting API — extend an image's borders to fill a target aspect ratio using OpenAI's image edit endpoint. Use this skill when the user says "add outpainting", "extend image", "ai image resize", or "outpaint".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: [storage, env-config]
---

# Outpaint

Server-side AI outpainting powered by OpenAI's image edit endpoint. Accepts a source image and a target resolution, centers the source on a transparent canvas, and asks OpenAI to naturally extend the background into the transparent regions. The result is uploaded to storage and the permanent URL is returned.

## Prerequisites

- Next.js app with App Router (no `src/` directory)
- `storage` skill applied (for `/api/storage/upload`)
- `env-config` skill applied (for typed env vars)
- `auth` skill applied (better-auth session check)

## Installation

```bash
bun add openai sharp
```

## Environment Variables

Add to `.env.local`:

```env
OPENAI_API_KEY=sk-...
```

Add to your `env.ts` server schema (env-config pattern):

```typescript
OPENAI_API_KEY: z.string().min(1),
```

## What Gets Created

```
app/
└── api/
    └── outpaint/
        └── route.ts      # POST /api/outpaint — multipart/form-data handler
lib/
└── outpaint/
    └── index.ts          # Core outpaintImage() function, types
```

## Setup Steps

### Step 1: Create `lib/outpaint/index.ts`

```typescript
import sharp from "sharp";
import OpenAI from "openai";

export interface OutpaintInput {
  imageBuffer: Buffer;
  imageWidth: number;
  imageHeight: number;
  targetWidth: number;
  targetHeight: number;
}

export interface OutpaintResult {
  buffer: Buffer;
  width: number;
  height: number;
}

const OUTPAINT_PROMPT =
  "Naturally extend the background to fill the transparent areas, maintaining consistent lighting, color, and style. Do not add new subjects. Keep existing content exactly as-is.";

/**
 * Create a transparent RGBA canvas at targetWidth × targetHeight,
 * composite the source image centered, then call OpenAI images.edit
 * to fill in the transparent regions.
 */
export async function outpaintImage(input: OutpaintInput): Promise<OutpaintResult> {
  const { imageBuffer, imageWidth, imageHeight, targetWidth, targetHeight } = input;

  if (targetWidth <= 0 || targetHeight <= 0) {
    throw new Error("Target dimensions must be positive integers");
  }

  // Compute centered offsets
  const offsetX = Math.round((targetWidth - imageWidth) / 2);
  const offsetY = Math.round((targetHeight - imageHeight) / 2);

  // Build a transparent PNG canvas at target size with source centered
  const paddedBuffer = await sharp({
    create: {
      width: targetWidth,
      height: targetHeight,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([
      {
        input: imageBuffer,
        left: Math.max(0, offsetX),
        top: Math.max(0, offsetY),
      },
    ])
    .png()
    .toBuffer();

  // OpenAI images.edit requires a File object
  const paddedFile = new File([paddedBuffer], "padded.png", { type: "image/png" });

  const client = new OpenAI();

  const response = await client.images.edit({
    model: "dall-e-2",
    image: paddedFile,
    prompt: OUTPAINT_PROMPT,
    n: 1,
    size: resolveOpenAISize(targetWidth, targetHeight),
    response_format: "b64_json",
  });

  const b64 = response.data[0]?.b64_json;
  if (!b64) {
    throw new Error("OpenAI did not return image data");
  }

  const resultBuffer = Buffer.from(b64, "base64");

  return {
    buffer: resultBuffer,
    width: targetWidth,
    height: targetHeight,
  };
}

/**
 * OpenAI DALL-E 2 edit only accepts specific square sizes.
 * We round up to the nearest supported size and let sharp resize afterward.
 */
function resolveOpenAISize(
  width: number,
  height: number
): "256x256" | "512x512" | "1024x1024" {
  const max = Math.max(width, height);
  if (max <= 256) return "256x256";
  if (max <= 512) return "512x512";
  return "1024x1024";
}
```

### Step 2: Create `app/api/outpaint/route.ts`

```typescript
import { type NextRequest, NextResponse } from "next/server";
import { headers } from "next/headers";
import sharp from "sharp";
import { auth } from "@/lib/auth";
import { outpaintImage } from "@/lib/outpaint";

interface OutpaintResponse {
  url: string;
  width: number;
  height: number;
  platform: string | null;
  originalWidth: number;
  originalHeight: number;
}

export async function POST(
  request: NextRequest
): Promise<NextResponse<OutpaintResponse | { error: string }>> {
  // Auth check
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let formData: FormData;
  try {
    formData = await request.formData();
  } catch {
    return NextResponse.json({ error: "Invalid form data" }, { status: 400 });
  }

  const imageFile = formData.get("image");
  const targetWidthRaw = formData.get("targetWidth");
  const targetHeightRaw = formData.get("targetHeight");
  const platform = formData.get("platform");

  // Validate image
  if (!imageFile || !(imageFile instanceof File)) {
    return NextResponse.json({ error: "image is required" }, { status: 400 });
  }

  // Validate dimensions
  const targetWidth = Number(targetWidthRaw);
  const targetHeight = Number(targetHeightRaw);

  if (!Number.isInteger(targetWidth) || targetWidth <= 0) {
    return NextResponse.json(
      { error: "targetWidth must be a positive integer" },
      { status: 400 }
    );
  }
  if (!Number.isInteger(targetHeight) || targetHeight <= 0) {
    return NextResponse.json(
      { error: "targetHeight must be a positive integer" },
      { status: 400 }
    );
  }

  // Read source image and get its metadata
  const imageArrayBuffer = await imageFile.arrayBuffer();
  const imageBuffer = Buffer.from(imageArrayBuffer);

  let originalWidth: number;
  let originalHeight: number;
  try {
    const meta = await sharp(imageBuffer).metadata();
    originalWidth = meta.width ?? 0;
    originalHeight = meta.height ?? 0;
    if (originalWidth === 0 || originalHeight === 0) {
      return NextResponse.json({ error: "Could not read image dimensions" }, { status: 400 });
    }
  } catch {
    return NextResponse.json({ error: "Invalid or corrupt image file" }, { status: 400 });
  }

  // Run outpaint
  let result: { buffer: Buffer; width: number; height: number };
  try {
    result = await outpaintImage({
      imageBuffer,
      imageWidth: originalWidth,
      imageHeight: originalHeight,
      targetWidth,
      targetHeight,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Outpaint failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }

  // Upload result to storage via the storage skill's upload endpoint
  const platformLabel = typeof platform === "string" && platform.trim() !== "" ? platform.trim() : null;
  const filename = platformLabel
    ? `outpaint-${platformLabel}-${Date.now()}.png`
    : `outpaint-${Date.now()}.png`;

  const uploadForm = new FormData();
  uploadForm.append(
    "file",
    new File([result.buffer], filename, { type: "image/png" })
  );

  const uploadResponse = await fetch(
    new URL("/api/storage/upload", request.nextUrl.origin).toString(),
    {
      method: "POST",
      body: uploadForm,
      headers: {
        // Forward the session cookie so the storage route can authenticate if needed
        cookie: request.headers.get("cookie") ?? "",
      },
    }
  );

  if (!uploadResponse.ok) {
    return NextResponse.json(
      { error: "Failed to upload outpainted image to storage" },
      { status: 502 }
    );
  }

  const uploadData = (await uploadResponse.json()) as { file: { url: string } };

  return NextResponse.json({
    url: uploadData.file.url,
    width: result.width,
    height: result.height,
    platform: platformLabel,
    originalWidth,
    originalHeight,
  });
}
```

## Usage

```typescript
// Client-side example — extend a 1080×1080 image to 1080×1920 (Instagram Story)
const form = new FormData();
form.append("image", imageFile);
form.append("targetWidth", "1080");
form.append("targetHeight", "1920");
form.append("platform", "Instagram Story");

const response = await fetch("/api/outpaint", {
  method: "POST",
  body: form,
});

const result = await response.json();
// {
//   url: "https://storage.example.com/outpaint-Instagram-Story-1737000000000.png",
//   width: 1080,
//   height: 1920,
//   platform: "Instagram Story",
//   originalWidth: 1080,
//   originalHeight: 1080
// }
```

### Server-side (lib function)

```typescript
import { outpaintImage } from "@/lib/outpaint";
import fs from "node:fs";

const imageBuffer = fs.readFileSync("photo.jpg");
const result = await outpaintImage({
  imageBuffer,
  imageWidth: 1080,
  imageHeight: 1080,
  targetWidth: 1280,
  targetHeight: 720,
});

fs.writeFileSync("outpainted.png", result.buffer);
```

## Acceptance Criteria

- POST `/api/outpaint` with a valid image, `targetWidth`, and `targetHeight` returns `{ url, width, height, platform, originalWidth, originalHeight }`
- Returns 401 when called without a valid session
- Returns 400 when `image` field is missing
- Returns 400 when `targetWidth` or `targetHeight` is zero, negative, or non-numeric
- Returns 400 when the uploaded file is not a valid image
- The returned `url` is a permanent storage URL (not an ephemeral OpenAI URL)
- `tsc` passes with no errors
- Build succeeds
