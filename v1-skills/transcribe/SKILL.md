---
name: transcribe
description: Audio/video transcription via OpenAI Whisper — returns full text and timestamped segments. Use this skill when the user says "add transcription", "transcribe audio", "transcribe video", "whisper api", or "speech to text".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: [storage, env-config]
---

# Transcribe

Server-side audio and video transcription using the [OpenAI Whisper API](https://platform.openai.com/docs/guides/speech-to-text). Accepts an uploaded audio or video file, validates format and size, calls `audio.transcriptions.create` with `verbose_json` to get word- and segment-level timestamps, and returns structured JSON.

## Prerequisites

- Next.js app with App Router (no `src/` directory)
- `env-config` skill applied (for typed env vars)
- `auth` skill applied (better-auth session check)

## Installation

```bash
bun add openai
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
    └── transcribe/
        └── route.ts      # POST /api/transcribe — multipart/form-data handler
lib/
└── transcribe/
    └── index.ts          # Types, constants, isSupported(), formatTimestamp()
```

## Setup Steps

### Step 1: Create `lib/transcribe/index.ts`

```typescript
export interface TranscriptSegment {
  id: number;
  start: number;
  end: number;
  text: string;
  confidence: number;
}

export interface TranscriptWord {
  word: string;
  start: number;
  end: number;
}

export interface TranscribeResult {
  text: string;
  language: string;
  duration: number;
  segments: TranscriptSegment[];
  words: TranscriptWord[];
}

/** MIME types accepted by OpenAI Whisper */
export const SUPPORTED_FORMATS: string[] = [
  "audio/mpeg",        // .mp3
  "audio/mp4",         // .m4a
  "audio/wav",         // .wav
  "audio/wave",        // .wav (alternate)
  "audio/x-wav",       // .wav (alternate)
  "audio/webm",        // .webm audio
  "audio/ogg",         // .ogg
  "video/mp4",         // .mp4
  "video/webm",        // .webm video
  "video/quicktime",   // .mov
  "video/x-m4v",       // .m4v
  "application/octet-stream", // fallback for unnamed files
];

/** 25 MB — OpenAI Whisper hard limit */
export const MAX_FILE_SIZE: number = 25 * 1024 * 1024;

/**
 * Returns true when the file's MIME type is in SUPPORTED_FORMATS.
 * Files with type "application/octet-stream" are allowed through
 * and validated server-side by OpenAI.
 */
export function isSupported(file: File): boolean {
  return SUPPORTED_FORMATS.includes(file.type);
}

/**
 * Format a duration in seconds to "MM:SS".
 *
 * @example formatTimestamp(75.3) // "01:15"
 * @example formatTimestamp(3661) // "61:01"
 */
export function formatTimestamp(seconds: number): string {
  const totalSeconds = Math.floor(seconds);
  const minutes = Math.floor(totalSeconds / 60);
  const secs = totalSeconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
}
```

### Step 2: Create `app/api/transcribe/route.ts`

```typescript
import { type NextRequest, NextResponse } from "next/server";
import { headers } from "next/headers";
import OpenAI from "openai";
import { auth } from "@/lib/auth";
import {
  SUPPORTED_FORMATS,
  MAX_FILE_SIZE,
  isSupported,
  type TranscribeResult,
  type TranscriptSegment,
  type TranscriptWord,
} from "@/lib/transcribe";

// OpenAI verbose_json response shape (partial — only fields we use)
interface WhisperSegment {
  id: number;
  start: number;
  end: number;
  text: string;
  avg_logprob?: number;
}

interface WhisperWord {
  word: string;
  start: number;
  end: number;
}

interface WhisperVerboseResponse {
  text: string;
  language: string;
  duration: number;
  segments?: WhisperSegment[];
  words?: WhisperWord[];
}

export async function POST(
  request: NextRequest
): Promise<NextResponse<TranscribeResult | { error: string }>> {
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

  const fileField = formData.get("file");
  const languageField = formData.get("language");
  const promptField = formData.get("prompt");

  // Validate file presence
  if (!fileField || !(fileField instanceof File)) {
    return NextResponse.json({ error: "file is required" }, { status: 400 });
  }

  const file = fileField;

  // Validate file size (25 MB OpenAI limit)
  if (file.size > MAX_FILE_SIZE) {
    return NextResponse.json(
      {
        error: `File size ${(file.size / 1024 / 1024).toFixed(1)} MB exceeds the 25 MB limit`,
      },
      { status: 413 }
    );
  }

  // Validate MIME type
  if (!isSupported(file)) {
    return NextResponse.json(
      {
        error: `Unsupported file format "${file.type}". Supported formats: ${SUPPORTED_FORMATS.filter((f) => !f.includes("octet")).join(", ")}`,
      },
      { status: 400 }
    );
  }

  const language = typeof languageField === "string" && languageField.trim() !== ""
    ? languageField.trim()
    : "en";

  const prompt = typeof promptField === "string" && promptField.trim() !== ""
    ? promptField.trim()
    : undefined;

  const client = new OpenAI();

  let whisperResponse: WhisperVerboseResponse;
  try {
    // Cast needed because the TS overloads for response_format are strict
    const raw = await client.audio.transcriptions.create({
      model: "whisper-1",
      file,
      language,
      prompt,
      response_format: "verbose_json",
      timestamp_granularities: ["segment", "word"],
    } as Parameters<typeof client.audio.transcriptions.create>[0]);

    whisperResponse = raw as unknown as WhisperVerboseResponse;
  } catch (err) {
    const message = err instanceof Error ? err.message : "Transcription failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }

  // Normalise segments
  const segments: TranscriptSegment[] = (whisperResponse.segments ?? []).map(
    (seg): TranscriptSegment => ({
      id: seg.id,
      start: seg.start,
      end: seg.end,
      text: seg.text.trim(),
      // avg_logprob is in natural log space; convert to a 0-1 confidence proxy
      confidence:
        seg.avg_logprob !== undefined
          ? Math.min(1, Math.max(0, Math.exp(seg.avg_logprob)))
          : 1,
    })
  );

  // Normalise words
  const words: TranscriptWord[] = (whisperResponse.words ?? []).map(
    (w): TranscriptWord => ({
      word: w.word,
      start: w.start,
      end: w.end,
    })
  );

  const result: TranscribeResult = {
    text: whisperResponse.text,
    language: whisperResponse.language,
    duration: whisperResponse.duration,
    segments,
    words,
  };

  return NextResponse.json(result);
}
```

## Usage

### Client-side (file input)

```typescript
const form = new FormData();
form.append("file", audioFile); // File from <input type="file" />
form.append("language", "en");
form.append("prompt", "This is a podcast about technology.");

const response = await fetch("/api/transcribe", {
  method: "POST",
  body: form,
});

if (!response.ok) {
  const { error } = await response.json();
  console.error(error);
} else {
  const result = await response.json();
  // {
  //   text: "Hello world...",
  //   language: "en",
  //   duration: 42.5,
  //   segments: [{ id: 0, start: 0.0, end: 2.4, text: "Hello world", confidence: 0.98 }],
  //   words: [{ word: "Hello", start: 0.0, end: 0.5 }]
  // }
}
```

### Utility helpers

```typescript
import { isSupported, formatTimestamp, MAX_FILE_SIZE } from "@/lib/transcribe";

// Validate before uploading
if (!isSupported(file)) {
  alert("Unsupported format");
}
if (file.size > MAX_FILE_SIZE) {
  alert("File too large — max 25 MB");
}

// Format segment timestamps for display
segments.forEach((seg) => {
  console.log(`[${formatTimestamp(seg.start)} → ${formatTimestamp(seg.end)}] ${seg.text}`);
  // [00:00 → 00:02] Hello world
});
```

## Acceptance Criteria

- POST `/api/transcribe` with a valid audio file returns `{ text, segments, duration, language, words }`
- Returns 401 when called without a valid session
- Returns 400 when `file` field is missing
- Returns 400 when the file MIME type is not in `SUPPORTED_FORMATS`
- Returns 413 when the file exceeds 25 MB
- Each segment in the response contains `id`, `start`, `end`, `text`, and `confidence`
- Each word in the response contains `word`, `start`, and `end`
- `formatTimestamp(75)` returns `"01:15"`
- `isSupported` returns `false` for `"text/plain"` and `true` for `"audio/mpeg"`
- `tsc` passes with no errors
- Build succeeds
