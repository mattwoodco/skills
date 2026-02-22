---
name: transcription
description: Real-time and batch speech-to-text via Deepgram — live transcript overlay for video rooms, post-meeting full transcript with search, speaker labels, and Postgres persistence. Use this skill when the user says "add transcription", "setup speech to text", "add captions", "transcribe audio", or "setup transcription".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [video-room, db, env-config]
---

# Transcription

Real-time and batch speech-to-text powered by [Deepgram](https://deepgram.com). Provides live streaming transcription for video rooms via Deepgram's WebSocket API, batch transcription for recorded audio, a scrolling real-time transcript panel with speaker labels, and a full post-meeting transcript viewer with search and speaker filtering. All transcripts are persisted to Postgres via Drizzle.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `video-room` skill installed (LiveKit room infrastructure)
- `db` skill installed (Drizzle ORM with PostgreSQL)
- `env-config` skill installed (`src/env.ts`)
- shadcn/ui initialized

## Installation

```bash
bun add @deepgram/sdk
```

## Environment Variables

Add to `.env.local`:

```env
# Deepgram
DEEPGRAM_API_KEY=your-deepgram-api-key-here
```

### Update `src/env.ts`

Add to the `server` object:

```typescript
  server: {
    // ... existing variables
    DEEPGRAM_API_KEY: z.string().min(1),
  },
```

Add to the `runtimeEnv` object:

```typescript
  runtimeEnv: {
    // ... existing variables
    DEEPGRAM_API_KEY: process.env.DEEPGRAM_API_KEY,
  },
```

## What Gets Created

```
src/
├── lib/
│   ├── video/
│   │   ├── transcription.ts              # Server-side Deepgram client, batch + streaming
│   │   ├── types-transcription.ts        # TranscriptSegment, Transcript, Speaker types
│   │   └── use-transcription.ts          # "use client" hook for live transcript state
│   └── db/
│       └── schema/
│           └── transcripts.ts            # Drizzle: transcripts + transcript_segments tables
├── components/
│   └── video/
│       ├── live-transcript.tsx           # Scrolling real-time transcript panel
│       └── transcript-viewer.tsx         # Post-meeting full transcript with search
└── app/
    └── api/
        └── video/
            └── transcripts/
                ├── route.ts              # GET list / POST start transcription
                └── [id]/
                    └── route.ts          # GET full transcript with segments
```

## Database

After applying this skill, push the schema to create the `transcripts` and `transcript_segments` tables:

```bash
bunx drizzle-kit push
```

## Setup Steps

### Step 1: Create `src/lib/video/types-transcription.ts`

```typescript
export type Speaker = {
  id: number;
  name: string;
};

export type TranscriptSegment = {
  speaker: number;
  text: string;
  startTime: number;
  endTime: number;
  confidence: number;
};

export type Transcript = {
  id: string;
  roomName: string;
  segments: TranscriptSegment[];
  speakers: Speaker[];
  duration: number;
  createdAt: Date;
};

export type LiveTranscriptEvent = {
  type: "transcript";
  segment: TranscriptSegment;
  isFinal: boolean;
};

export type TranscriptionStatus = "idle" | "connecting" | "transcribing" | "error" | "stopped";
```

### Step 2: Create `src/lib/video/transcription.ts`

```typescript
import { createClient, LiveTranscriptionEvents } from "@deepgram/sdk";
import type { TranscriptSegment, Speaker } from "./types-transcription";

/**
 * Create a configured Deepgram client.
 * Must be called server-side only — uses DEEPGRAM_API_KEY.
 */
export function createDeepgramClient() {
  const apiKey = process.env.DEEPGRAM_API_KEY;
  if (!apiKey) {
    throw new Error("DEEPGRAM_API_KEY is not set");
  }
  return createClient(apiKey);
}

/**
 * Transcribe an audio buffer using Deepgram's batch (pre-recorded) API.
 * Supports speaker diarization and punctuation.
 *
 * @param audioBuffer - Raw audio data (WAV, MP3, OGG, etc.)
 * @param mimetype - MIME type of the audio (e.g., "audio/wav")
 * @returns Transcript segments with speaker labels and timestamps.
 */
export async function transcribeAudio(
  audioBuffer: Buffer,
  mimetype = "audio/wav"
): Promise<{ segments: TranscriptSegment[]; speakers: Speaker[]; duration: number }> {
  const client = createDeepgramClient();

  const { result } = await client.listen.prerecorded.transcribeFile(audioBuffer, {
    model: "nova-3",
    smart_format: true,
    diarize: true,
    punctuate: true,
    utterances: true,
    mime_type: mimetype,
  });

  const segments: TranscriptSegment[] = [];
  const speakerSet = new Set<number>();

  const utterances = result?.results?.utterances ?? [];
  for (const utterance of utterances) {
    const speakerId = utterance.speaker ?? 0;
    speakerSet.add(speakerId);

    segments.push({
      speaker: speakerId,
      text: utterance.transcript,
      startTime: utterance.start,
      endTime: utterance.end,
      confidence: utterance.confidence,
    });
  }

  const speakers: Speaker[] = Array.from(speakerSet).map((id) => ({
    id,
    name: `Speaker ${id + 1}`,
  }));

  const duration = result?.metadata?.duration ?? 0;

  return { segments, speakers, duration };
}

type LiveTranscriptionCallbacks = {
  onSegment: (segment: TranscriptSegment, isFinal: boolean) => void;
  onError: (error: Error) => void;
  onClose: () => void;
};

type LiveTranscriptionHandle = {
  send: (audioData: Buffer) => void;
  close: () => void;
};

/**
 * Create a live (streaming) transcription session via Deepgram's WebSocket API.
 * Accumulates transcript segments with speaker labels and timestamps in real time.
 *
 * @param roomName - The video room name (used for logging/context).
 * @param callbacks - Handlers for transcript segments, errors, and close events.
 * @returns A handle with `send(audioData)` to push audio chunks and `close()` to end the session.
 */
export function createLiveTranscription(
  roomName: string,
  callbacks: LiveTranscriptionCallbacks
): LiveTranscriptionHandle {
  const client = createDeepgramClient();

  const connection = client.listen.live({
    model: "nova-3",
    smart_format: true,
    diarize: true,
    punctuate: true,
    interim_results: true,
    utterance_end_ms: 1000,
    encoding: "linear16",
    sample_rate: 16000,
    channels: 1,
  });

  connection.on(LiveTranscriptionEvents.Open, () => {
    console.log(`[transcription] Live session opened for room: ${roomName}`);
  });

  connection.on(LiveTranscriptionEvents.Transcript, (data) => {
    const alternatives = data.channel?.alternatives;
    if (!alternatives || alternatives.length === 0) return;

    const alternative = alternatives[0];
    const transcript = alternative.transcript;
    if (!transcript || transcript.trim().length === 0) return;

    const isFinal = data.is_final === true;
    const speakerId = data.channel?.alternatives?.[0]?.words?.[0]?.speaker ?? 0;
    const words = alternative.words ?? [];

    const startTime = words.length > 0 ? (words[0].start ?? 0) : 0;
    const lastWord = words.length > 0 ? words[words.length - 1] : undefined;
    const endTime = lastWord?.end ?? startTime;

    const segment: TranscriptSegment = {
      speaker: speakerId,
      text: transcript,
      startTime,
      endTime,
      confidence: alternative.confidence ?? 0,
    };

    callbacks.onSegment(segment, isFinal);
  });

  connection.on(LiveTranscriptionEvents.Error, (error) => {
    console.error(`[transcription] Error for room ${roomName}:`, error);
    callbacks.onError(error instanceof Error ? error : new Error(String(error)));
  });

  connection.on(LiveTranscriptionEvents.Close, () => {
    console.log(`[transcription] Live session closed for room: ${roomName}`);
    callbacks.onClose();
  });

  return {
    send(audioData: Buffer) {
      connection.send(audioData.buffer.slice(audioData.byteOffset, audioData.byteOffset + audioData.byteLength));
    },
    close() {
      connection.requestClose();
    },
  };
}
```

### Step 3: Create `src/lib/video/use-transcription.ts`

```typescript
"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import type { TranscriptSegment, TranscriptionStatus } from "./types-transcription";

type UseTranscriptionOptions = {
  /** The LiveKit data channel topic to subscribe to for transcript events */
  dataTopic?: string;
};

type TranscriptMessage = {
  type: "transcript";
  segment: TranscriptSegment;
  isFinal: boolean;
};

/**
 * Hook that subscribes to the LiveKit data channel for live transcript segments.
 * Maintains a running transcript state with both interim and final segments.
 *
 * @param dataChannel - A reference to the LiveKit room data receiver (e.g., from useDataChannel)
 * @param options - Optional configuration (dataTopic defaults to "transcription")
 */
export function useTranscription(
  onDataReceived?: (handler: (payload: Uint8Array) => void) => () => void,
  options: UseTranscriptionOptions = {}
) {
  const { dataTopic: _dataTopic = "transcription" } = options;
  const [segments, setSegments] = useState<TranscriptSegment[]>([]);
  const [interimSegment, setInterimSegment] = useState<TranscriptSegment | null>(null);
  const [isTranscribing, setIsTranscribing] = useState(false);
  const [status, setStatus] = useState<TranscriptionStatus>("idle");
  const decoderRef = useRef(new TextDecoder());

  const handleMessage = useCallback((payload: Uint8Array) => {
    try {
      const text = decoderRef.current.decode(payload);
      const message = JSON.parse(text) as TranscriptMessage;

      if (message.type !== "transcript") return;

      setIsTranscribing(true);
      setStatus("transcribing");

      if (message.isFinal) {
        setSegments((prev) => [...prev, message.segment]);
        setInterimSegment(null);
      } else {
        setInterimSegment(message.segment);
      }
    } catch {
      // Ignore malformed messages
    }
  }, []);

  useEffect(() => {
    if (!onDataReceived) return;
    const unsubscribe = onDataReceived(handleMessage);
    return unsubscribe;
  }, [onDataReceived, handleMessage]);

  const clearTranscript = useCallback(() => {
    setSegments([]);
    setInterimSegment(null);
    setIsTranscribing(false);
    setStatus("idle");
  }, []);

  const transcript = interimSegment
    ? [...segments, interimSegment]
    : segments;

  return {
    /** All transcript segments (final + current interim) */
    transcript,
    /** Only finalized segments */
    segments,
    /** The current interim (non-final) segment, or null */
    interimSegment,
    /** Whether transcription is actively receiving data */
    isTranscribing,
    /** Current transcription status */
    status,
    /** Clear the accumulated transcript */
    clearTranscript,
  };
}
```

### Step 4: Create `src/components/video/live-transcript.tsx`

```tsx
"use client";

import { useRef, useEffect, useId, useMemo } from "react";
import { cn } from "@/lib/utils";
import type { TranscriptSegment } from "@/lib/video/types-transcription";

/** Color palette for speaker labels */
const SPEAKER_COLORS = [
  "text-blue-500",
  "text-emerald-500",
  "text-violet-500",
  "text-amber-500",
  "text-rose-500",
  "text-cyan-500",
  "text-pink-500",
  "text-lime-500",
] as const;

function getSpeakerColor(speakerId: number): string {
  return SPEAKER_COLORS[speakerId % SPEAKER_COLORS.length];
}

function formatTimestamp(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

type SpeakerNameMap = Record<number, string>;

type LiveTranscriptProps = {
  segments: TranscriptSegment[];
  interimSegment?: TranscriptSegment | null;
  speakerNames?: SpeakerNameMap;
  className?: string;
  maxHeight?: string;
};

export function LiveTranscript({
  segments,
  interimSegment,
  speakerNames,
  className,
  maxHeight = "400px",
}: LiveTranscriptProps) {
  const segmentId = useId();
  const scrollRef = useRef<HTMLDivElement>(null);
  const isAutoScrollRef = useRef(true);

  const allSegments = useMemo(() => {
    if (interimSegment) {
      return [...segments, interimSegment];
    }
    return segments;
  }, [segments, interimSegment]);

  // Auto-scroll to bottom when new segments arrive
  useEffect(() => {
    if (isAutoScrollRef.current && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [allSegments]);

  // Detect manual scroll to pause auto-scroll
  const handleScroll = () => {
    if (!scrollRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = scrollRef.current;
    const isAtBottom = scrollHeight - scrollTop - clientHeight < 40;
    isAutoScrollRef.current = isAtBottom;
  };

  const getSpeakerLabel = (speakerId: number): string => {
    if (speakerNames && speakerNames[speakerId]) {
      return speakerNames[speakerId];
    }
    return `Speaker ${speakerId + 1}`;
  };

  return (
    <div
      ref={scrollRef}
      onScroll={handleScroll}
      className={cn(
        "overflow-y-auto rounded-lg border bg-muted/30 p-4",
        className
      )}
      style={{ maxHeight }}
    >
      {allSegments.length === 0 ? (
        <p className="text-center text-sm text-muted-foreground">
          Waiting for transcription...
        </p>
      ) : (
        <div className="space-y-2">
          {allSegments.map((segment, index) => {
            const isInterim =
              interimSegment !== null &&
              interimSegment !== undefined &&
              index === allSegments.length - 1;

            return (
              <div
                key={`${segmentId}-${segment.startTime}-${segment.speaker}-${index}`}
                className={cn(
                  "flex gap-2 text-sm",
                  isInterim && "opacity-60"
                )}
              >
                <span className="shrink-0 font-mono text-xs text-muted-foreground pt-0.5">
                  {formatTimestamp(segment.startTime)}
                </span>
                <span
                  className={cn(
                    "shrink-0 font-semibold",
                    getSpeakerColor(segment.speaker)
                  )}
                >
                  {getSpeakerLabel(segment.speaker)}:
                </span>
                <span className="text-foreground">{segment.text}</span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
```

### Step 5: Create `src/components/video/transcript-viewer.tsx`

```tsx
"use client";

import { useState, useMemo, useCallback, useId } from "react";
import { cn } from "@/lib/utils";
import type { TranscriptSegment, Speaker } from "@/lib/video/types-transcription";

const SPEAKER_COLORS = [
  "text-blue-500",
  "text-emerald-500",
  "text-violet-500",
  "text-amber-500",
  "text-rose-500",
  "text-cyan-500",
  "text-pink-500",
  "text-lime-500",
] as const;

const SPEAKER_BG_COLORS = [
  "bg-blue-500/10",
  "bg-emerald-500/10",
  "bg-violet-500/10",
  "bg-amber-500/10",
  "bg-rose-500/10",
  "bg-cyan-500/10",
  "bg-pink-500/10",
  "bg-lime-500/10",
] as const;

function getSpeakerColor(speakerId: number): string {
  return SPEAKER_COLORS[speakerId % SPEAKER_COLORS.length];
}

function getSpeakerBgColor(speakerId: number): string {
  return SPEAKER_BG_COLORS[speakerId % SPEAKER_BG_COLORS.length];
}

function formatTimestamp(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);
  if (hours > 0) {
    return `${hours}h ${mins}m ${secs}s`;
  }
  return `${mins}m ${secs}s`;
}

type TranscriptViewerProps = {
  segments: TranscriptSegment[];
  speakers: Speaker[];
  duration: number;
  onSeek?: (timeInSeconds: number) => void;
  className?: string;
};

export function TranscriptViewer({
  segments,
  speakers,
  duration,
  onSeek,
  className,
}: TranscriptViewerProps) {
  const segmentId = useId();
  const speakerFilterId = useId();
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedSpeakers, setSelectedSpeakers] = useState<Set<number>>(
    () => new Set(speakers.map((s) => s.id))
  );

  const toggleSpeaker = useCallback((speakerId: number) => {
    setSelectedSpeakers((prev) => {
      const next = new Set(prev);
      if (next.has(speakerId)) {
        // Don't allow deselecting all speakers
        if (next.size > 1) {
          next.delete(speakerId);
        }
      } else {
        next.add(speakerId);
      }
      return next;
    });
  }, []);

  const selectAllSpeakers = useCallback(() => {
    setSelectedSpeakers(new Set(speakers.map((s) => s.id)));
  }, [speakers]);

  const filteredSegments = useMemo(() => {
    return segments.filter((segment) => {
      // Filter by speaker
      if (!selectedSpeakers.has(segment.speaker)) return false;

      // Filter by search query
      if (searchQuery.trim()) {
        return segment.text.toLowerCase().includes(searchQuery.toLowerCase());
      }

      return true;
    });
  }, [segments, selectedSpeakers, searchQuery]);

  const highlightText = useCallback(
    (text: string): React.ReactNode => {
      if (!searchQuery.trim()) return text;

      const regex = new RegExp(`(${searchQuery.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "gi");
      const parts = text.split(regex);

      return parts.map((part, partIndex) => {
        const isMatch = part.toLowerCase() === searchQuery.toLowerCase();
        return isMatch ? (
          <mark
            key={`${part}-${partIndex}`}
            className="rounded bg-yellow-200 px-0.5 dark:bg-yellow-800"
          >
            {part}
          </mark>
        ) : (
          part
        );
      });
    },
    [searchQuery]
  );

  const getSpeakerName = useCallback(
    (speakerId: number): string => {
      const speaker = speakers.find((s) => s.id === speakerId);
      return speaker?.name ?? `Speaker ${speakerId + 1}`;
    },
    [speakers]
  );

  return (
    <div className={cn("flex flex-col gap-4", className)}>
      {/* Header with stats */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4 text-sm text-muted-foreground">
          <span>{segments.length} segments</span>
          <span>{speakers.length} speakers</span>
          <span>{formatDuration(duration)}</span>
        </div>
      </div>

      {/* Search */}
      <div>
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Search transcript..."
          className="w-full rounded-lg border bg-background px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
        />
      </div>

      {/* Speaker filter pills */}
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs font-medium text-muted-foreground">Speakers:</span>
        {speakers.map((speaker) => {
          const isSelected = selectedSpeakers.has(speaker.id);
          return (
            <button
              key={`${speakerFilterId}-speaker-${speaker.id}`}
              type="button"
              onClick={() => toggleSpeaker(speaker.id)}
              className={cn(
                "rounded-full px-3 py-1 text-xs font-medium transition-colors",
                isSelected
                  ? cn(getSpeakerBgColor(speaker.id), getSpeakerColor(speaker.id))
                  : "bg-muted text-muted-foreground opacity-50"
              )}
            >
              {speaker.name}
            </button>
          );
        })}
        {selectedSpeakers.size < speakers.length && (
          <button
            type="button"
            onClick={selectAllSpeakers}
            className="text-xs text-primary hover:underline"
          >
            Show all
          </button>
        )}
      </div>

      {/* Segment list */}
      <div className="space-y-1 overflow-y-auto">
        {filteredSegments.length === 0 ? (
          <p className="py-8 text-center text-sm text-muted-foreground">
            {searchQuery ? "No matching segments found." : "No transcript segments."}
          </p>
        ) : (
          filteredSegments.map((segment, index) => (
            <div
              key={`${segmentId}-${segment.startTime}-${segment.speaker}-${index}`}
              className="group flex gap-3 rounded-md px-2 py-1.5 hover:bg-muted/50"
            >
              <button
                type="button"
                onClick={() => onSeek?.(segment.startTime)}
                className="shrink-0 font-mono text-xs text-primary hover:underline pt-0.5"
                title={`Seek to ${formatTimestamp(segment.startTime)}`}
              >
                {formatTimestamp(segment.startTime)}
              </button>
              <span
                className={cn(
                  "shrink-0 text-sm font-semibold",
                  getSpeakerColor(segment.speaker)
                )}
              >
                {getSpeakerName(segment.speaker)}:
              </span>
              <span className="text-sm text-foreground">
                {highlightText(segment.text)}
              </span>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
```

### Step 6: Create `src/lib/db/schema/transcripts.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  jsonb,
  real,
  integer,
} from "drizzle-orm/pg-core";

export const transcripts = pgTable("transcripts", {
  id: uuid("id").defaultRandom().primaryKey(),
  roomName: text("room_name").notNull(),
  segments: jsonb("segments")
    .notNull()
    .$type<
      Array<{
        speaker: number;
        text: string;
        startTime: number;
        endTime: number;
        confidence: number;
      }>
    >(),
  speakers: jsonb("speakers")
    .notNull()
    .$type<Array<{ id: number; name: string }>>(),
  duration: real("duration").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});

export const transcriptSegments = pgTable("transcript_segments", {
  id: uuid("id").defaultRandom().primaryKey(),
  transcriptId: uuid("transcript_id")
    .notNull()
    .references(() => transcripts.id, { onDelete: "cascade" }),
  speaker: integer("speaker").notNull(),
  text: text("text").notNull(),
  startTime: real("start_time").notNull(),
  endTime: real("end_time").notNull(),
  confidence: real("confidence").notNull().default(0),
});
```

Add the transcript schema export to `src/lib/db/schema/index.ts`:

```typescript
export * from "./transcripts";
```

### Step 7: Create `src/app/api/video/transcripts/route.ts`

```typescript
import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { transcripts, transcriptSegments } from "@/lib/db/schema/transcripts";
import { desc, eq } from "drizzle-orm";
import { transcribeAudio } from "@/lib/video/transcription";

type StartTranscriptionBody = {
  roomName: string;
  audioUrl?: string;
};

/** GET /api/video/transcripts — list all transcripts, optionally filtered by roomName */
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const roomName = searchParams.get("roomName");

  const query = db
    .select({
      id: transcripts.id,
      roomName: transcripts.roomName,
      speakers: transcripts.speakers,
      duration: transcripts.duration,
      createdAt: transcripts.createdAt,
    })
    .from(transcripts)
    .orderBy(desc(transcripts.createdAt));

  const results = roomName
    ? await query.where(eq(transcripts.roomName, roomName))
    : await query;

  return NextResponse.json(results);
}

/** POST /api/video/transcripts — start/create a transcription for a room */
export async function POST(request: Request) {
  const body: StartTranscriptionBody = await request.json();

  if (!body.roomName) {
    return NextResponse.json(
      { error: "roomName is required" },
      { status: 400 }
    );
  }

  // If an audioUrl is provided, run batch transcription
  if (body.audioUrl) {
    try {
      const audioResponse = await fetch(body.audioUrl);
      if (!audioResponse.ok) {
        return NextResponse.json(
          { error: "Failed to fetch audio from URL" },
          { status: 400 }
        );
      }

      const arrayBuffer = await audioResponse.arrayBuffer();
      const audioBuffer = Buffer.from(arrayBuffer);

      const contentType = audioResponse.headers.get("content-type") ?? "audio/wav";
      const { segments, speakers, duration } = await transcribeAudio(audioBuffer, contentType);

      // Persist the transcript
      const [transcript] = await db
        .insert(transcripts)
        .values({
          roomName: body.roomName,
          segments,
          speakers,
          duration,
        })
        .returning();

      // Persist individual segments for efficient querying
      if (segments.length > 0) {
        await db.insert(transcriptSegments).values(
          segments.map((seg) => ({
            transcriptId: transcript.id,
            speaker: seg.speaker,
            text: seg.text,
            startTime: seg.startTime,
            endTime: seg.endTime,
            confidence: seg.confidence,
          }))
        );
      }

      return NextResponse.json(transcript, { status: 201 });
    } catch (error) {
      return NextResponse.json(
        {
          error: error instanceof Error ? error.message : "Transcription failed",
        },
        { status: 500 }
      );
    }
  }

  // For live transcription, create an empty transcript record to be populated in real-time
  const [transcript] = await db
    .insert(transcripts)
    .values({
      roomName: body.roomName,
      segments: [],
      speakers: [],
      duration: 0,
    })
    .returning();

  return NextResponse.json(
    {
      ...transcript,
      message: "Transcript record created. Use the live transcription WebSocket to populate.",
    },
    { status: 201 }
  );
}
```

### Step 8: Create `src/app/api/video/transcripts/[id]/route.ts`

```typescript
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { db } from "@/lib/db";
import { transcripts, transcriptSegments } from "@/lib/db/schema/transcripts";
import { eq, asc } from "drizzle-orm";

type RouteContext = { params: Promise<{ id: string }> };

/** GET /api/video/transcripts/[id] — get a full transcript with segments */
export async function GET(
  _request: NextRequest,
  context: RouteContext
) {
  const { id } = await context.params;

  const result = await db
    .select()
    .from(transcripts)
    .where(eq(transcripts.id, id))
    .limit(1);

  if (result.length === 0) {
    return NextResponse.json(
      { error: "Transcript not found" },
      { status: 404 }
    );
  }

  const transcript = result[0];

  // Fetch individual segments (for more granular data)
  const segments = await db
    .select({
      id: transcriptSegments.id,
      speaker: transcriptSegments.speaker,
      text: transcriptSegments.text,
      startTime: transcriptSegments.startTime,
      endTime: transcriptSegments.endTime,
      confidence: transcriptSegments.confidence,
    })
    .from(transcriptSegments)
    .where(eq(transcriptSegments.transcriptId, id))
    .orderBy(asc(transcriptSegments.startTime));

  return NextResponse.json({
    ...transcript,
    segmentDetails: segments,
  });
}
```

## Usage

### Live Transcription in a Video Room

```tsx
"use client";

import { useTranscription } from "@/lib/video/use-transcription";
import { LiveTranscript } from "@/components/video/live-transcript";

export function VideoRoomWithTranscript() {
  // In a real implementation, onDataReceived comes from your LiveKit data channel hook
  const {
    transcript,
    segments,
    interimSegment,
    isTranscribing,
  } = useTranscription();

  return (
    <div className="flex gap-4">
      <div className="flex-1">
        {/* Video grid */}
      </div>
      <aside className="w-80">
        <LiveTranscript
          segments={segments}
          interimSegment={interimSegment}
          speakerNames={{ 0: "Alice", 1: "Bob" }}
        />
      </aside>
    </div>
  );
}
```

### Post-Meeting Transcript Viewer

```tsx
"use client";

import { useEffect, useState } from "react";
import { TranscriptViewer } from "@/components/video/transcript-viewer";
import type { TranscriptSegment, Speaker } from "@/lib/video/types-transcription";

type TranscriptData = {
  segments: TranscriptSegment[];
  speakers: Speaker[];
  duration: number;
};

export function MeetingTranscript({ transcriptId }: { transcriptId: string }) {
  const [data, setData] = useState<TranscriptData | null>(null);

  useEffect(() => {
    fetch(`/api/video/transcripts/${transcriptId}`)
      .then((res) => res.json())
      .then((d: TranscriptData) => setData(d));
  }, [transcriptId]);

  if (!data) return <div>Loading...</div>;

  return (
    <TranscriptViewer
      segments={data.segments}
      speakers={data.speakers}
      duration={data.duration}
      onSeek={(time) => console.log("Seek to", time)}
    />
  );
}
```

### Batch Transcription via API

```typescript
// Create a batch transcription from a recording URL
const res = await fetch("/api/video/transcripts", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    roomName: "meeting-2026-02-18",
    audioUrl: "https://storage.example.com/recordings/meeting.wav",
  }),
});
const transcript = await res.json();

// Get the full transcript
const detail = await fetch(`/api/video/transcripts/${transcript.id}`);
const fullTranscript = await detail.json();
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/video/transcripts` | List transcripts (optional `?roomName=` filter) |
| POST | `/api/video/transcripts` | Create transcription `{ roomName, audioUrl? }` |
| GET | `/api/video/transcripts/[id]` | Get full transcript with segment details |

## Acceptance Criteria

- `@deepgram/sdk` is installed and the client initializes with `DEEPGRAM_API_KEY`
- `transcribeAudio()` returns segments with speaker labels, timestamps, and confidence scores
- `createLiveTranscription()` opens a Deepgram WebSocket and emits segments in real time
- `useTranscription` hook maintains running transcript state with interim and final segments
- `LiveTranscript` component auto-scrolls and shows color-coded speaker labels
- `TranscriptViewer` supports search, speaker filtering, and clickable timestamps
- `transcripts` and `transcript_segments` tables are created via `bunx drizzle-kit push`
- GET `/api/video/transcripts` returns a list of transcripts
- POST `/api/video/transcripts` with `audioUrl` runs batch transcription and persists results
- GET `/api/video/transcripts/[id]` returns the full transcript with segment details
- No usage of `any` type anywhere in transcription code
- `tsc` passes with no errors
- `bun run build` succeeds

## Troubleshooting

### "DEEPGRAM_API_KEY is not set"

**Cause**: The environment variable is missing or empty.

**Fix**: Add `DEEPGRAM_API_KEY=your-key` to `.env.local` and restart the dev server. Get a key from [Deepgram Console](https://console.deepgram.com/).

### WebSocket connection fails

**Cause**: Firewall or network issue blocking WebSocket connections to Deepgram.

**Fix**: Ensure outbound WebSocket connections to `wss://api.deepgram.com` are allowed. If behind a corporate proxy, configure the proxy to allow WebSocket upgrades.

### Empty transcript / no segments

**Cause**: Audio encoding mismatch. The live transcription expects linear16 PCM at 16kHz mono.

**Fix**: Ensure the audio being sent to `connection.send()` matches the configured encoding. For batch transcription, the `mimetype` parameter must match the actual audio format.

### Speaker diarization missing

**Cause**: Deepgram's diarization requires sufficient audio context and multiple distinct voices.

**Fix**: Diarization works best with at least 30 seconds of audio containing clearly distinct speakers. Short clips or single-speaker audio may not produce speaker labels.
