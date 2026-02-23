---
name: media-bunny
description: Browser-based video processing with mediabunny — read, write, convert MP4/WebM/MKV using WebCodecs API. Server integration for storage and metadata tracking.
author: Claude
version: 1.0.1
created: 2026-02-13
updated: 2026-02-14
dependencies: [storage, db]
---

# Media Bunny — Browser Video Processing for Next.js

Browser-based video processing using the mediabunny npm package and the WebCodecs API. Supports reading video metadata, converting between MP4/WebM/MKV formats, and server-side integration for storing processed videos and tracking metadata via Drizzle.

## Prerequisites

- Next.js app with `src/` directory and App Router
- Storage skill installed (for file upload/download)
- DB skill installed (for Drizzle schema and database access)
- A modern browser with WebCodecs support (Chrome 94+, Edge 94+, Opera 80+)

## Installation

```bash
bun add mediabunny
```

The `storage` and `db` dependencies are installed by their own skills.

## What Gets Created

```
src/
├── lib/
│   ├── media-bunny/
│   │   ├── types.ts              # Shared types (VideoMetadata, ProcessingStatus, etc.)
│   │   └── use-media-bunny.ts    # React hook for mediabunny with lazy loading
│   └── db/
│       └── schema/
│           └── videos.ts         # Drizzle schema for video metadata table
├── components/
│   └── video/
│       ├── video-processor.tsx           # Main video processing component (use client)
│       └── video-processor-wrapper.tsx   # Dynamic import wrapper for SSR safety
└── app/
    ├── api/
    │   └── videos/
    │       ├── route.ts          # GET list videos, POST create video record
    │       └── [id]/
    │           └── route.ts      # GET single video, PATCH update, DELETE
    └── video/
        └── page.tsx              # Test page with minimal UI
```

## mediabunny API Reference

### Core Classes

- **`Input`** — constructor: `new Input({ formats, source })` where `formats` comes from `ALL_FORMATS` and `source` is a Source instance
  - Methods: `getFormat()`, `computeDuration()`, `getFirstTimestamp()`, `getTracks()`, `getVideoTracks()`, `getAudioTracks()`, `getPrimaryVideoTrack()`, `getPrimaryAudioTrack()`, `getMimeType()`, `getMetadataTags()`, `dispose()`
- **`Output`** — constructor: `new Output({ format, target })`
  - Methods: `addVideoTrack(source, metadata?)`, `addAudioTrack(source, metadata?)`, `start()`, `finalize()`, `cancel()`
  - Properties: `format`, `state` (`'pending'|'started'|'canceled'|'finalizing'|'finalized'`), `target`
- **`Conversion`** — static init: `Conversion.init({ input, output, video?, audio? })`
  - Methods: `execute()`, `cancel()`
  - Properties: `input`, `output`, `onProgress`

### Sources (reading)

`BlobSource(blob)`, `BufferSource`, `UrlSource`, `StreamSource`, `ReadableStreamSource`, `FilePathSource`

### Targets (writing)

`BufferTarget()`, `StreamTarget(stream)`, `FilePathTarget`, `NullTarget`

### Sinks

`VideoSampleSink(track)` — `getSample(timestamp)`, `samples(start, end)`, `samplesAtTimestamps(timestamps)`

### Sources (writing)

`VideoSampleSource(encodingConfig)` — `add(sample, encodeOptions?)`

### Output Formats

`Mp4OutputFormat`, `WebMOutputFormat`, `MkvOutputFormat`, `WavOutputFormat`

### Video Encoding Config

```typescript
{
  codec: "avc" | "hevc" | "av1" | "vp8" | "vp9";
  bitrate: number;
  keyFrameInterval?: number;
  sizeChangeBehavior?: string;
  alpha?: boolean;
  bitrateMode?: string;
  latencyMode?: string;
}
```

### Codec-Container Compatibility

| Container | Video Codecs | Audio Codecs |
|-----------|-------------|--------------|
| MP4       | avc, hevc, av1 | aac, mp3, flac |
| WebM      | vp8, vp9, av1 | opus, vorbis |
| MKV       | avc, hevc, av1, vp8, vp9 | aac, opus, mp3, vorbis, flac |

## Setup Steps

### Step 1: Create `src/lib/media-bunny/types.ts`

```typescript
export type ProcessingStatus = "pending" | "processing" | "completed" | "failed";

export type VideoMetadata = {
  id: string;
  fileName: string;
  format: string;
  duration: number;
  width: number;
  height: number;
  codec: string;
  fileSize: number;
  storageKey: string | null;
  status: ProcessingStatus;
  createdAt: Date;
  updatedAt: Date;
};

export type VideoProcessingOptions = {
  outputFormat: "mp4" | "webm";
  videoCodec?: import("mediabunny").VideoCodec;
  audioCodec?: import("mediabunny").AudioCodec;
  videoBitrate?: number;
  audioBitrate?: number;
};

export type VideoInfo = {
  duration: number;
  width: number;
  height: number;
  format: string;
  codec: string;
};

export type UseMediaBunnyReturn = {
  isLoading: boolean;
  isSupported: boolean;
  error: string | null;
  getVideoInfo: (file: File) => Promise<VideoInfo>;
  convertVideo: (
    file: File,
    options: VideoProcessingOptions,
    onProgress?: (progress: number) => void
  ) => Promise<Blob>;
};
```

### Step 2: Create `src/lib/media-bunny/use-media-bunny.ts`

```typescript
"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type {
  UseMediaBunnyReturn,
  VideoInfo,
  VideoProcessingOptions,
} from "./types";

type MediaBunnyModule = typeof import("mediabunny");

export function useMediaBunny(): UseMediaBunnyReturn {
  const [isLoading, setIsLoading] = useState(true);
  const [isSupported, setIsSupported] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const moduleRef = useRef<MediaBunnyModule | null>(null);

  useEffect(() => {
    const supported =
      typeof VideoDecoder !== "undefined" &&
      typeof VideoEncoder !== "undefined";
    setIsSupported(supported);

    if (!supported) {
      setIsLoading(false);
      setError("WebCodecs API is not supported in this browser.");
      return;
    }

    import("mediabunny")
      .then((mod) => {
        moduleRef.current = mod;
        setIsLoading(false);
      })
      .catch((err: unknown) => {
        const message =
          err instanceof Error ? err.message : "Failed to load mediabunny";
        setError(message);
        setIsLoading(false);
      });
  }, []);

  const getVideoInfo = useCallback(async (file: File): Promise<VideoInfo> => {
    const mb = moduleRef.current;
    if (!mb) {
      throw new Error("mediabunny is not loaded yet");
    }

    const source = new mb.BlobSource(file);
    const input = new mb.Input({
      formats: mb.ALL_FORMATS,
      source,
    });

    try {
      const format = await input.getFormat();
      const duration = await input.computeDuration();
      const videoTrack = await input.getPrimaryVideoTrack();

      const width = videoTrack?.displayWidth ?? 0;
      const height = videoTrack?.displayHeight ?? 0;
      const codec = videoTrack?.codec ?? "unknown";

      return {
        duration,
        width,
        height,
        format: format?.name ?? "unknown",
        codec,
      };
    } finally {
      input.dispose();
    }
  }, []);

  const convertVideo = useCallback(
    async (
      file: File,
      options: VideoProcessingOptions,
      onProgress?: (progress: number) => void
    ): Promise<Blob> => {
      const mb = moduleRef.current;
      if (!mb) {
        throw new Error("mediabunny is not loaded yet");
      }

      const source = new mb.BlobSource(file);
      const input = new mb.Input({
        formats: mb.ALL_FORMATS,
        source,
      });

      const target = new mb.BufferTarget();

      const format =
        options.outputFormat === "mp4"
          ? new mb.Mp4OutputFormat()
          : new mb.WebMOutputFormat();

      const output = new mb.Output({ format, target });

      const videoCodec =
        options.videoCodec ?? (options.outputFormat === "mp4" ? "avc" : "vp9");
      const audioCodec =
        options.audioCodec ?? (options.outputFormat === "mp4" ? "aac" : "opus");

      try {
        const conversion = await mb.Conversion.init({
          input,
          output,
          video: {
            codec: videoCodec,
            bitrate: options.videoBitrate ?? 2_000_000,
          },
          audio: {
            codec: audioCodec,
            bitrate: options.audioBitrate ?? 128_000,
          },
        });

        if (onProgress) {
          conversion.onProgress = onProgress;
        }

        await conversion.execute();

        const mimeType =
          options.outputFormat === "mp4" ? "video/mp4" : "video/webm";
        const buffer = target.buffer;
        if (!buffer) {
          throw new Error("Conversion produced no output data");
        }
        return new Blob([buffer], { type: mimeType });
      } finally {
        input.dispose();
      }
    },
    []
  );

  return { isLoading, isSupported, error, getVideoInfo, convertVideo };
}
```

### Step 3: Create `src/lib/db/schema/videos.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  integer,
  real,
} from "drizzle-orm/pg-core";

export const videos = pgTable("videos", {
  id: uuid("id").primaryKey().defaultRandom(),
  fileName: text("file_name").notNull(),
  format: text("format").notNull(),
  duration: real("duration").notNull().default(0),
  width: integer("width").notNull().default(0),
  height: integer("height").notNull().default(0),
  codec: text("codec").notNull().default("unknown"),
  fileSize: integer("file_size").notNull().default(0),
  storageKey: text("storage_key"),
  status: text("status", {
    enum: ["pending", "processing", "completed", "failed"],
  })
    .notNull()
    .default("pending"),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export type Video = typeof videos.$inferSelect;
export type NewVideo = typeof videos.$inferInsert;
```

### Step 4: Create `src/components/video/video-processor.tsx`

```tsx
"use client";

import { useCallback, useId, useRef, useState } from "react";
import { useMediaBunny } from "@src/lib/media-bunny/use-media-bunny";
import type {
  VideoInfo,
  VideoProcessingOptions,
} from "@src/lib/media-bunny/types";

type ConversionResult = {
  blob: Blob;
  url: string;
  format: string;
};

export function VideoProcessor() {
  const { isLoading, isSupported, error, getVideoInfo, convertVideo } =
    useMediaBunny();

  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [videoInfo, setVideoInfo] = useState<VideoInfo | null>(null);
  const [infoError, setInfoError] = useState<string | null>(null);
  const [progress, setProgress] = useState<number>(0);
  const [isConverting, setIsConverting] = useState(false);
  const [conversionResult, setConversionResult] =
    useState<ConversionResult | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveMessage, setSaveMessage] = useState<string | null>(null);

  const fileInputRef = useRef<HTMLInputElement>(null);
  const fileInputId = useId();
  const progressId = useId();

  const handleFileSelect = useCallback(
    async (event: React.ChangeEvent<HTMLInputElement>) => {
      const file = event.target.files?.[0];
      if (!file) return;

      setSelectedFile(file);
      setVideoInfo(null);
      setInfoError(null);
      setConversionResult(null);
      setSaveMessage(null);
      setProgress(0);

      try {
        const info = await getVideoInfo(file);
        setVideoInfo(info);
      } catch (err: unknown) {
        const message =
          err instanceof Error ? err.message : "Failed to read video info";
        setInfoError(message);
      }
    },
    [getVideoInfo]
  );

  const handleConvert = useCallback(
    async (outputFormat: "mp4" | "webm") => {
      if (!selectedFile) return;

      setIsConverting(true);
      setProgress(0);
      setConversionResult(null);
      setSaveMessage(null);

      const options: VideoProcessingOptions = {
        outputFormat,
        videoBitrate: 2_000_000,
        audioBitrate: 128_000,
      };

      try {
        const blob = await convertVideo(selectedFile, options, setProgress);
        const url = URL.createObjectURL(blob);
        setConversionResult({ blob, url, format: outputFormat });
      } catch (err: unknown) {
        const message =
          err instanceof Error ? err.message : "Conversion failed";
        setInfoError(message);
      } finally {
        setIsConverting(false);
      }
    },
    [selectedFile, convertVideo]
  );

  const handleSaveToServer = useCallback(async () => {
    if (!conversionResult || !videoInfo || !selectedFile) return;

    setIsSaving(true);
    setSaveMessage(null);

    try {
      const formData = new FormData();
      const fileName = `${selectedFile.name.replace(/\.[^.]+$/, "")}.${conversionResult.format}`;
      formData.append(
        "file",
        new File([conversionResult.blob], fileName, {
          type: conversionResult.blob.type,
        })
      );

      const uploadResponse = await fetch("/api/storage/upload", {
        method: "POST",
        body: formData,
      });

      if (!uploadResponse.ok) {
        throw new Error("Upload failed");
      }

      const uploadData = (await uploadResponse.json()) as {
        file: { key: string };
      };

      const videoRecord = {
        fileName,
        format: conversionResult.format,
        duration: videoInfo.duration,
        width: videoInfo.width,
        height: videoInfo.height,
        codec: videoInfo.codec,
        fileSize: conversionResult.blob.size,
        storageKey: uploadData.file.key,
        status: "completed" as const,
      };

      const createResponse = await fetch("/api/videos", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(videoRecord),
      });

      if (!createResponse.ok) {
        throw new Error("Failed to create video record");
      }

      setSaveMessage("Video saved successfully.");
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : "Failed to save video";
      setSaveMessage(`Error: ${message}`);
    } finally {
      setIsSaving(false);
    }
  }, [conversionResult, videoInfo, selectedFile]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center p-8">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-gray-300 border-t-blue-600" />
        <span className="ml-3 text-sm text-gray-600">
          Loading video processor...
        </span>
      </div>
    );
  }

  if (!isSupported) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-6">
        <p className="font-medium text-red-800">WebCodecs Not Supported</p>
        <p className="mt-1 text-sm text-red-600">
          {error ??
            "Your browser does not support the WebCodecs API. Please use Chrome 94+, Edge 94+, or Opera 80+."}
        </p>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6 p-6">
      <div>
        <h2 className="text-xl font-semibold">Video Processor</h2>
        <p className="mt-1 text-sm text-gray-500">
          Select a video to inspect metadata or convert between formats.
        </p>
      </div>

      {/* File Input */}
      <div>
        <label
          htmlFor={fileInputId}
          className="block text-sm font-medium text-gray-700"
        >
          Select Video File
        </label>
        <input
          ref={fileInputRef}
          id={fileInputId}
          type="file"
          accept="video/*"
          onChange={handleFileSelect}
          className="mt-1 block w-full text-sm text-gray-500 file:mr-4 file:rounded file:border-0 file:bg-blue-50 file:px-4 file:py-2 file:text-sm file:font-medium file:text-blue-700 hover:file:bg-blue-100"
        />
      </div>

      {/* Info Error */}
      {infoError && (
        <div className="rounded border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {infoError}
        </div>
      )}

      {/* Video Metadata */}
      {videoInfo && (
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <h3 className="text-sm font-semibold text-gray-700">
            Video Metadata
          </h3>
          <dl className="mt-2 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
            <dt className="text-gray-500">Duration</dt>
            <dd className="text-gray-900">{videoInfo.duration.toFixed(2)}s</dd>
            <dt className="text-gray-500">Resolution</dt>
            <dd className="text-gray-900">
              {videoInfo.width} x {videoInfo.height}
            </dd>
            <dt className="text-gray-500">Format</dt>
            <dd className="text-gray-900">{videoInfo.format}</dd>
            <dt className="text-gray-500">Codec</dt>
            <dd className="text-gray-900">{videoInfo.codec}</dd>
            {selectedFile && (
              <>
                <dt className="text-gray-500">File Size</dt>
                <dd className="text-gray-900">
                  {(selectedFile.size / (1024 * 1024)).toFixed(2)} MB
                </dd>
              </>
            )}
          </dl>
        </div>
      )}

      {/* Convert Buttons */}
      {videoInfo && !isConverting && (
        <div className="flex gap-3">
          <button
            type="button"
            onClick={() => handleConvert("mp4")}
            className="rounded bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50"
          >
            Convert to MP4
          </button>
          <button
            type="button"
            onClick={() => handleConvert("webm")}
            className="rounded bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
          >
            Convert to WebM
          </button>
        </div>
      )}

      {/* Progress Bar */}
      {isConverting && (
        <div>
          <div className="flex items-center justify-between text-sm text-gray-600">
            <span>Converting...</span>
            <span>{Math.round(progress * 100)}%</span>
          </div>
          <div className="mt-1 h-2 overflow-hidden rounded-full bg-gray-200">
            <div
              id={progressId}
              className="h-full rounded-full bg-blue-600 transition-all duration-300"
              style={{ width: `${progress * 100}%` }}
              role="progressbar"
              aria-valuenow={Math.round(progress * 100)}
              aria-valuemin={0}
              aria-valuemax={100}
            />
          </div>
        </div>
      )}

      {/* Conversion Result */}
      {conversionResult && (
        <div className="space-y-3 rounded-lg border border-green-200 bg-green-50 p-4">
          <p className="text-sm font-medium text-green-800">
            Conversion complete ({(conversionResult.blob.size / (1024 * 1024)).toFixed(2)} MB)
          </p>
          <div className="flex gap-3">
            <a
              href={conversionResult.url}
              download={`converted.${conversionResult.format}`}
              className="rounded bg-gray-800 px-4 py-2 text-sm font-medium text-white hover:bg-gray-900"
            >
              Download
            </a>
            <button
              type="button"
              onClick={handleSaveToServer}
              disabled={isSaving}
              className="rounded bg-purple-600 px-4 py-2 text-sm font-medium text-white hover:bg-purple-700 disabled:opacity-50"
            >
              {isSaving ? (
                <span className="flex items-center gap-2">
                  <span className="inline-block h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
                  Saving...
                </span>
              ) : (
                "Save to Server"
              )}
            </button>
          </div>
        </div>
      )}

      {/* Save Message */}
      {saveMessage && (
        <div
          className={`rounded border p-3 text-sm ${
            saveMessage.startsWith("Error")
              ? "border-red-200 bg-red-50 text-red-700"
              : "border-green-200 bg-green-50 text-green-700"
          }`}
        >
          {saveMessage}
        </div>
      )}
    </div>
  );
}
```

### Step 5: Create `src/components/video/video-processor-wrapper.tsx`

```tsx
"use client";

import dynamic from "next/dynamic";

const VideoProcessor = dynamic(
  () =>
    import("@/components/video/video-processor").then(
      (mod) => mod.VideoProcessor
    ),
  {
    ssr: false,
    loading: () => (
      <div className="p-8 text-center text-muted-foreground">
        Loading video processor...
      </div>
    ),
  }
);

export function VideoProcessorWrapper() {
  return <VideoProcessor />;
}
```

### Step 6: Create `src/app/api/videos/route.ts`

```typescript
import { NextRequest, NextResponse } from "next/server";
import { db } from "@src/lib/db";
import { videos, type Video, type NewVideo } from "@src/lib/db/schema/videos";
import { desc } from "drizzle-orm";
import { auth } from "@src/lib/auth";
import { headers } from "next/headers";

export async function GET(): Promise<NextResponse<{ videos: Video[] } | { error: string }>> {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const result = await db
      .select()
      .from(videos)
      .orderBy(desc(videos.createdAt));

    return NextResponse.json({ videos: result });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Failed to list videos";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function POST(
  request: NextRequest
): Promise<NextResponse<{ video: Video } | { error: string }>> {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = (await request.json()) as NewVideo;

    const [video] = await db
      .insert(videos)
      .values({
        fileName: body.fileName,
        format: body.format,
        duration: body.duration,
        width: body.width,
        height: body.height,
        codec: body.codec,
        fileSize: body.fileSize,
        storageKey: body.storageKey,
        status: body.status ?? "pending",
      })
      .returning();

    return NextResponse.json({ video }, { status: 201 });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Failed to create video record";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 7: Create `src/app/api/videos/[id]/route.ts`

```typescript
import { NextRequest, NextResponse } from "next/server";
import { db } from "@src/lib/db";
import { videos, type Video } from "@src/lib/db/schema/videos";
import { eq } from "drizzle-orm";
import { auth } from "@src/lib/auth";
import { headers } from "next/headers";

type RouteParams = { params: Promise<{ id: string }> };

export async function GET(
  _request: NextRequest,
  { params }: RouteParams
): Promise<NextResponse<{ video: Video } | { error: string }>> {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const [video] = await db.select().from(videos).where(eq(videos.id, id));

    if (!video) {
      return NextResponse.json({ error: "Video not found" }, { status: 404 });
    }

    return NextResponse.json({ video });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Failed to get video";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function PATCH(
  request: NextRequest,
  { params }: RouteParams
): Promise<NextResponse<{ video: Video } | { error: string }>> {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const body = (await request.json()) as Partial<Video>;

    const [video] = await db
      .update(videos)
      .set({
        ...(body.status !== undefined && { status: body.status }),
        ...(body.storageKey !== undefined && { storageKey: body.storageKey }),
        ...(body.fileName !== undefined && { fileName: body.fileName }),
        ...(body.format !== undefined && { format: body.format }),
        ...(body.duration !== undefined && { duration: body.duration }),
        ...(body.width !== undefined && { width: body.width }),
        ...(body.height !== undefined && { height: body.height }),
        ...(body.codec !== undefined && { codec: body.codec }),
        ...(body.fileSize !== undefined && { fileSize: body.fileSize }),
        updatedAt: new Date(),
      })
      .where(eq(videos.id, id))
      .returning();

    if (!video) {
      return NextResponse.json({ error: "Video not found" }, { status: 404 });
    }

    return NextResponse.json({ video });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Failed to update video";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function DELETE(
  _request: NextRequest,
  { params }: RouteParams
): Promise<NextResponse<{ success: true } | { error: string }>> {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const [video] = await db
      .delete(videos)
      .where(eq(videos.id, id))
      .returning();

    if (!video) {
      return NextResponse.json({ error: "Video not found" }, { status: 404 });
    }

    return NextResponse.json({ success: true });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Failed to delete video";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 8: Create `src/app/video/page.tsx`

```tsx
import { VideoProcessorWrapper } from "@/components/video/video-processor-wrapper";

export default function VideoPage() {
  return (
    <main className="min-h-screen py-12">
      <div className="mx-auto max-w-3xl px-4">
        <h1 className="mb-8 text-3xl font-bold">Video Processing</h1>
        <VideoProcessorWrapper />
      </div>
    </main>
  );
}
```

## Usage

### Reading Video Metadata

```tsx
"use client";

import { useMediaBunny } from "@src/lib/media-bunny/use-media-bunny";

function MyComponent() {
  const { isLoading, isSupported, getVideoInfo } = useMediaBunny();

  const handleFile = async (file: File) => {
    const info = await getVideoInfo(file);
    console.log(info.duration, info.width, info.height, info.format, info.codec);
  };

  // ...
}
```

### Converting a Video

```tsx
"use client";

import { useMediaBunny } from "@src/lib/media-bunny/use-media-bunny";

function MyComponent() {
  const { convertVideo } = useMediaBunny();

  const handleConvert = async (file: File) => {
    const blob = await convertVideo(
      file,
      { outputFormat: "webm", videoBitrate: 1_500_000 },
      (progress) => console.log(`${Math.round(progress * 100)}%`)
    );
    // blob is the converted video
    const url = URL.createObjectURL(blob);
    window.open(url);
  };

  // ...
}
```

### Saving to Server

```typescript
// 1. Upload blob to storage
const formData = new FormData();
formData.append("file", new File([blob], "video.mp4", { type: "video/mp4" }));

const uploadRes = await fetch("/api/storage/upload", {
  method: "POST",
  body: formData,
});
const { file } = (await uploadRes.json()) as { file: { key: string } };

// 2. Create video record in database
const createRes = await fetch("/api/videos", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    fileName: "video.mp4",
    format: "mp4",
    duration: 30.5,
    width: 1920,
    height: 1080,
    codec: "avc",
    fileSize: blob.size,
    storageKey: file.key,
    status: "completed",
  }),
});
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/videos` | List all videos, ordered by createdAt desc |
| POST | `/api/videos` | Create a new video record (JSON body) |
| GET | `/api/videos/[id]` | Get a single video by ID |
| PATCH | `/api/videos/[id]` | Update video record (status, storageKey, etc.) |
| DELETE | `/api/videos/[id]` | Delete a video record |

## Important Rules

1. **ALL mediabunny imports must be dynamic** (`await import("mediabunny")`) — NEVER use static imports at module level. The library uses the WebCodecs API which is browser-only.
2. **Dynamic import wrapper with `ssr: false` is MANDATORY** for any component that uses mediabunny or the `useMediaBunny` hook.
3. **Always check WebCodecs support** before using: `typeof VideoDecoder !== 'undefined' && typeof VideoEncoder !== 'undefined'`.
4. **Always close VideoSample after use**: call `sample.close()` to free GPU memory.
5. **Add tracks to Output BEFORE calling `start()`** — adding tracks after start will throw.
6. **Match codec to container**: MP4 uses `avc`/`aac`, WebM uses `vp9`/`opus`. Mismatches will fail.
7. **Use `BufferTarget` for files under 100MB**, `StreamTarget` for larger files to avoid memory issues.
8. **Do NOT use `any` type anywhere** — use proper types from `mediabunny` or the shared types file.
9. **Use `useId()` from React** for generating stable IDs (form elements, progress bars, etc.).
10. **Import from `drizzle-orm/pg-core`** for schema definitions (not `drizzle-orm`).
11. **All API routes must use `Promise<params>`** for route parameters (Next.js App Router convention).

## Common Issues

### "VideoDecoder is not defined"

The component is being rendered on the server. Wrap with dynamic import and `ssr: false`:

```tsx
const VideoProcessor = dynamic(
  () => import("@/components/video/video-processor").then((mod) => mod.VideoProcessor),
  { ssr: false }
);
```

### "Cannot use import statement outside a module"

mediabunny uses ESM. Make sure it is dynamically imported inside a `useEffect` or callback, never at the top of a file:

```typescript
// WRONG
import { Input, Output, BlobSource } from "mediabunny";

// CORRECT
const mb = await import("mediabunny");
const source = new mb.BlobSource(file);
```

### Codec/Container Mismatch Errors

Always match codec to container format:

```typescript
// WRONG - vp9 in MP4 container (not widely supported)
{ outputFormat: "mp4", videoCodec: "vp9" }

// CORRECT
{ outputFormat: "mp4", videoCodec: "avc", audioCodec: "aac" }
{ outputFormat: "webm", videoCodec: "vp9", audioCodec: "opus" }
```

### Memory Leaks with Large Videos

For files over 100MB, use `StreamTarget` instead of `BufferTarget`:

```typescript
const mb = await import("mediabunny");
const chunks: Uint8Array[] = [];
const stream = new WritableStream<Uint8Array>({
  write(chunk) {
    chunks.push(chunk);
  },
});
const target = new mb.StreamTarget(stream);
```

Always call `input.dispose()` when done to free demuxer resources.

### Missing Database Migration

After creating the schema, generate and run the migration:

```bash
bunx drizzle-kit generate
bunx drizzle-kit migrate
```
