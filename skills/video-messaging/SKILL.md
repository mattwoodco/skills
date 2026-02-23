---
name: video-messaging
description: Async video messaging — record screen + camera, upload to MUX, auto-transcribe, AI-summarize, and view in threaded conversations. Use this skill when the user says "add video messages", "setup video messaging", "async video", "video threads", "loom clone", or "video-messaging".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [stream-mux, video-player, db, auth, queue, storage]
---

# Video Messaging

Asynchronous video messaging with browser-based recording (screen + camera + audio), MUX-hosted playback, automatic transcription, AI-generated summaries, and threaded conversations. Think Loom-style video messages with rich post-processing.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `stream-mux` skill applied (MUX upload + asset management)
- `video-player` skill applied (MUX Player React components)
- `db` skill applied (Drizzle ORM + Postgres)
- `auth` skill applied (better-auth for user sessions)
- `queue` skill applied (Inngest for background transcription + AI summary jobs)
- `storage` skill applied (for supplementary file storage)

## Installation

No additional packages required. This skill uses:

- `MediaRecorder` browser API (built into all modern browsers)
- `navigator.mediaDevices.getDisplayMedia` for screen capture
- `navigator.mediaDevices.getUserMedia` for camera + audio
- `@mux/mux-node` (from `stream-mux` dependency)
- `@mux/mux-player-react` (from `video-player` dependency)

## What Gets Created

```
src/
├── lib/
│   ├── video/
│   │   ├── video-message.ts       # Server: CRUD for video messages
│   │   ├── use-recorder.ts        # Client hook: screen + camera recording
│   │   └── types-messaging.ts     # VideoMessage, VideoThread types
│   └── db/
│       └── schema/
│           └── video-messages.ts   # Drizzle schema: video_messages table
├── components/
│   └── video/
│       ├── video-recorder.tsx     # Record UI with camera preview + controls
│       ├── video-message-card.tsx # Message card with summary + transcript
│       └── video-thread.tsx       # Threaded conversation of video messages
└── app/
    └── api/
        └── video/
            └── messages/
                ├── route.ts       # POST create, GET list
                └── [id]/
                    └── route.ts   # GET message with details, GET replies
```

## Setup Steps

### Step 1: Create `src/lib/video/types-messaging.ts`

```typescript
export type VideoMessageStatus =
  | "recording"
  | "uploading"
  | "processing"
  | "transcribing"
  | "ready"
  | "errored";

export type VideoMessage = {
  id: string;
  userId: string;
  title: string;
  muxAssetId: string | null;
  muxPlaybackId: string | null;
  transcriptId: string | null;
  meetingNoteId: string | null;
  parentId: string | null;
  duration: number | null;
  status: VideoMessageStatus;
  createdAt: Date;
};

export type VideoMessageWithDetails = VideoMessage & {
  transcript: string | null;
  summary: string | null;
  actionItems: string[] | null;
  senderName: string | null;
  senderEmail: string | null;
  senderImage: string | null;
  replyCount: number;
};

export type VideoThread = {
  message: VideoMessageWithDetails;
  replies: VideoMessageWithDetails[];
};

export type RecorderOptions = {
  screen: boolean;
  camera: boolean;
  audio: boolean;
};

export type RecorderState = {
  isRecording: boolean;
  isPaused: boolean;
  duration: number;
  previewStream: MediaStream | null;
  cameraStream: MediaStream | null;
  recordedBlob: Blob | null;
  error: string | null;
};
```

### Step 2: Create `src/lib/video/use-recorder.ts`

```typescript
"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import type { RecorderOptions, RecorderState } from "@src/lib/video/types-messaging";

type UseRecorderReturn = RecorderState & {
  startRecording: (options: RecorderOptions) => Promise<void>;
  stopRecording: () => void;
  pauseRecording: () => void;
  resumeRecording: () => void;
  resetRecording: () => void;
};

function useRecorder(): UseRecorderReturn {
  const [isRecording, setIsRecording] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [duration, setDuration] = useState(0);
  const [previewStream, setPreviewStream] = useState<MediaStream | null>(null);
  const [cameraStream, setCameraStream] = useState<MediaStream | null>(null);
  const [recordedBlob, setRecordedBlob] = useState<Blob | null>(null);
  const [error, setError] = useState<string | null>(null);

  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const startTimeRef = useRef<number>(0);
  const pausedDurationRef = useRef<number>(0);

  // Clean up timer on unmount
  useEffect(() => {
    return () => {
      if (timerRef.current) {
        clearInterval(timerRef.current);
      }
    };
  }, []);

  const stopAllTracks = useCallback((stream: MediaStream | null) => {
    if (stream) {
      for (const track of stream.getTracks()) {
        track.stop();
      }
    }
  }, []);

  const startTimer = useCallback(() => {
    startTimeRef.current = Date.now() - pausedDurationRef.current * 1000;
    timerRef.current = setInterval(() => {
      const elapsed = (Date.now() - startTimeRef.current) / 1000;
      setDuration(Math.floor(elapsed));
    }, 100);
  }, []);

  const stopTimer = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const startRecording = useCallback(
    async (options: RecorderOptions) => {
      setError(null);
      setRecordedBlob(null);
      chunksRef.current = [];
      pausedDurationRef.current = 0;

      try {
        const tracks: MediaStreamTrack[] = [];
        let screenStream: MediaStream | null = null;
        let camStream: MediaStream | null = null;

        // Get screen capture if requested
        if (options.screen) {
          screenStream = await navigator.mediaDevices.getDisplayMedia({
            video: {
              width: { ideal: 1920 },
              height: { ideal: 1080 },
              frameRate: { ideal: 30 },
            },
            audio: options.audio,
          });
          for (const track of screenStream.getVideoTracks()) {
            tracks.push(track);
          }
          // Use screen audio if available
          if (options.audio) {
            for (const track of screenStream.getAudioTracks()) {
              tracks.push(track);
            }
          }
        }

        // Get camera + microphone if requested
        if (options.camera || (options.audio && !options.screen)) {
          const constraints: MediaStreamConstraints = {};
          if (options.camera) {
            constraints.video = {
              width: { ideal: 640 },
              height: { ideal: 480 },
              facingMode: "user",
            };
          }
          if (options.audio && !screenStream?.getAudioTracks().length) {
            constraints.audio = {
              echoCancellation: true,
              noiseSuppression: true,
            };
          }

          camStream = await navigator.mediaDevices.getUserMedia(constraints);
          setCameraStream(camStream);

          // If we have screen capture, only add audio from camera (not video)
          if (options.screen) {
            if (options.audio) {
              for (const track of camStream.getAudioTracks()) {
                tracks.push(track);
              }
            }
          } else {
            for (const track of camStream.getTracks()) {
              tracks.push(track);
            }
          }
        }

        if (tracks.length === 0) {
          throw new Error("No media tracks available. Enable screen, camera, or audio.");
        }

        const combinedStream = new MediaStream(tracks);
        setPreviewStream(combinedStream);

        // Determine best MIME type
        const mimeType = MediaRecorder.isTypeSupported("video/webm;codecs=vp9,opus")
          ? "video/webm;codecs=vp9,opus"
          : MediaRecorder.isTypeSupported("video/webm;codecs=vp8,opus")
            ? "video/webm;codecs=vp8,opus"
            : "video/webm";

        const recorder = new MediaRecorder(combinedStream, {
          mimeType,
          videoBitsPerSecond: 2_500_000,
        });

        recorder.ondataavailable = (event) => {
          if (event.data.size > 0) {
            chunksRef.current.push(event.data);
          }
        };

        recorder.onstop = () => {
          const blob = new Blob(chunksRef.current, { type: mimeType });
          setRecordedBlob(blob);
          setIsRecording(false);
          setIsPaused(false);
          stopTimer();

          // Stop all tracks
          stopAllTracks(combinedStream);
          stopAllTracks(camStream);
          setPreviewStream(null);
          setCameraStream(null);
        };

        recorder.onerror = () => {
          setError("Recording failed unexpectedly");
          setIsRecording(false);
          stopTimer();
          stopAllTracks(combinedStream);
          stopAllTracks(camStream);
        };

        // Listen for screen share stop
        if (screenStream) {
          for (const track of screenStream.getVideoTracks()) {
            track.addEventListener("ended", () => {
              if (mediaRecorderRef.current?.state === "recording") {
                mediaRecorderRef.current.stop();
              }
            });
          }
        }

        mediaRecorderRef.current = recorder;
        recorder.start(1000); // Collect data every second
        setIsRecording(true);
        startTimer();
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "Failed to start recording";
        setError(message);
        setIsRecording(false);
      }
    },
    [startTimer, stopTimer, stopAllTracks]
  );

  const stopRecording = useCallback(() => {
    if (
      mediaRecorderRef.current &&
      mediaRecorderRef.current.state !== "inactive"
    ) {
      mediaRecorderRef.current.stop();
    }
  }, []);

  const pauseRecording = useCallback(() => {
    if (
      mediaRecorderRef.current &&
      mediaRecorderRef.current.state === "recording"
    ) {
      mediaRecorderRef.current.pause();
      setIsPaused(true);
      pausedDurationRef.current = duration;
      stopTimer();
    }
  }, [duration, stopTimer]);

  const resumeRecording = useCallback(() => {
    if (
      mediaRecorderRef.current &&
      mediaRecorderRef.current.state === "paused"
    ) {
      mediaRecorderRef.current.resume();
      setIsPaused(false);
      startTimer();
    }
  }, [startTimer]);

  const resetRecording = useCallback(() => {
    stopRecording();
    setRecordedBlob(null);
    setDuration(0);
    setError(null);
    chunksRef.current = [];
    pausedDurationRef.current = 0;
  }, [stopRecording]);

  return {
    isRecording,
    isPaused,
    duration,
    previewStream,
    cameraStream,
    recordedBlob,
    error,
    startRecording,
    stopRecording,
    pauseRecording,
    resumeRecording,
    resetRecording,
  };
}

export { useRecorder };
export type { UseRecorderReturn };
```

### Step 3: Create `src/lib/video/video-message.ts`

```typescript
import { db } from "@src/lib/db";
import { videoMessages } from "@src/lib/db/schema";
import { eq, desc, and, isNull, sql } from "drizzle-orm";
import { createUploadUrl } from "@src/lib/video/mux-vod";
import { inngest } from "@src/lib/queue/client";
import type { VideoMessage, VideoMessageWithDetails } from "@src/lib/video/types-messaging";

/**
 * Create a new video message, get a MUX upload URL, and return both.
 */
export async function createVideoMessage(
  userId: string,
  title: string,
  parentId?: string
): Promise<{ message: VideoMessage; uploadUrl: string }> {
  // Get a MUX direct upload URL
  const upload = await createUploadUrl();

  // Create the video message record
  const [record] = await db
    .insert(videoMessages)
    .values({
      userId,
      title,
      muxUploadId: upload.id,
      parentId: parentId ?? null,
      status: "uploading",
    })
    .returning();

  const message: VideoMessage = {
    id: record.id,
    userId: record.userId,
    title: record.title,
    muxAssetId: record.muxAssetId,
    muxPlaybackId: record.muxPlaybackId,
    transcriptId: record.transcriptId,
    meetingNoteId: record.meetingNoteId,
    parentId: record.parentId,
    duration: record.duration ? Number(record.duration) : null,
    status: record.status as VideoMessage["status"],
    createdAt: record.createdAt,
  };

  return { message, uploadUrl: upload.url };
}

/**
 * Called after MUX webhook confirms the asset is ready.
 * Triggers background transcription + AI summary generation.
 */
export async function onVideoMessageReady(
  muxAssetId: string,
  muxPlaybackId: string,
  duration: number | null
): Promise<void> {
  // Find the video message by MUX asset ID or upload ID
  const [record] = await db
    .select()
    .from(videoMessages)
    .where(eq(videoMessages.muxAssetId, muxAssetId))
    .limit(1);

  if (!record) return;

  // Update the record with playback info
  await db
    .update(videoMessages)
    .set({
      muxPlaybackId: muxPlaybackId,
      duration: duration ? String(duration) : null,
      status: "transcribing",
      updatedAt: new Date(),
    })
    .where(eq(videoMessages.id, record.id));

  // Trigger background transcription + AI summary via Inngest
  await inngest.send({
    name: "job/video-message-process",
    data: {
      jobId: record.id,
      userId: record.userId,
      videoMessageId: record.id,
      muxAssetId,
      muxPlaybackId,
    },
  });
}

/**
 * Get all top-level video messages for a user (no parent).
 */
export async function getVideoMessages(
  userId: string
): Promise<VideoMessageWithDetails[]> {
  const records = await db
    .select()
    .from(videoMessages)
    .where(
      and(
        eq(videoMessages.userId, userId),
        isNull(videoMessages.parentId)
      )
    )
    .orderBy(desc(videoMessages.createdAt));

  return records.map(mapToVideoMessageWithDetails);
}

/**
 * Get a single video message with its details.
 */
export async function getVideoMessage(
  messageId: string
): Promise<VideoMessageWithDetails | null> {
  const [record] = await db
    .select()
    .from(videoMessages)
    .where(eq(videoMessages.id, messageId))
    .limit(1);

  if (!record) return null;
  return mapToVideoMessageWithDetails(record);
}

/**
 * Get replies to a video message.
 */
export async function getVideoMessageReplies(
  parentId: string
): Promise<VideoMessageWithDetails[]> {
  const records = await db
    .select()
    .from(videoMessages)
    .where(eq(videoMessages.parentId, parentId))
    .orderBy(videoMessages.createdAt);

  return records.map(mapToVideoMessageWithDetails);
}

type VideoMessageRecord = typeof videoMessages.$inferSelect;

function mapToVideoMessageWithDetails(
  record: VideoMessageRecord
): VideoMessageWithDetails {
  const transcript =
    record.transcript && typeof record.transcript === "string"
      ? record.transcript
      : null;
  const summaryData = record.summary as {
    text?: string;
    actionItems?: string[];
  } | null;

  return {
    id: record.id,
    userId: record.userId,
    title: record.title,
    muxAssetId: record.muxAssetId,
    muxPlaybackId: record.muxPlaybackId,
    transcriptId: record.transcriptId,
    meetingNoteId: record.meetingNoteId,
    parentId: record.parentId,
    duration: record.duration ? Number(record.duration) : null,
    status: record.status as VideoMessage["status"],
    createdAt: record.createdAt,
    transcript,
    summary: summaryData?.text ?? null,
    actionItems: summaryData?.actionItems ?? null,
    senderName: null, // Populated by API route via join
    senderEmail: null,
    senderImage: null,
    replyCount: 0, // Populated by API route via subquery
  };
}
```

### Step 4: Create `src/lib/db/schema/video-messages.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  jsonb,
  pgEnum,
} from "drizzle-orm/pg-core";

export const videoMessageStatusEnum = pgEnum("video_message_status", [
  "recording",
  "uploading",
  "processing",
  "transcribing",
  "ready",
  "errored",
]);

export const videoMessages = pgTable("video_messages", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull(),
  title: text("title").notNull().default("Untitled"),
  muxAssetId: text("mux_asset_id"),
  muxPlaybackId: text("mux_playback_id"),
  muxUploadId: text("mux_upload_id"),
  transcriptId: text("transcript_id"),
  meetingNoteId: text("meeting_note_id"),
  parentId: uuid("parent_id"),
  status: videoMessageStatusEnum("status").notNull().default("recording"),
  duration: text("duration"),
  transcript: text("transcript"),
  summary: jsonb("summary"),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export type VideoMessageRecord = typeof videoMessages.$inferSelect;
export type NewVideoMessageRecord = typeof videoMessages.$inferInsert;
```

### Step 5: Add export to `src/lib/db/schema/index.ts`

Find the existing exports and add:

```typescript
export * from "./video-messages";
```

### Step 6: Create `src/components/video/video-recorder.tsx`

```tsx
"use client";

import { useState, useCallback, useRef, useEffect, useId } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { cn } from "@src/lib/utils";
import { useRecorder } from "@src/lib/video/use-recorder";

type VideoRecorderProps = {
  onSend: (blob: Blob, duration: number, title: string) => Promise<void>;
  onCancel?: () => void;
  defaultTitle?: string;
  className?: string;
};

function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
}

function RecordIcon() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
      <circle cx="12" cy="12" r="8" />
    </svg>
  );
}

function StopIcon() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
      <rect x="6" y="6" width="12" height="12" rx="2" />
    </svg>
  );
}

function PauseIcon() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
      <rect x="6" y="5" width="4" height="14" rx="1" />
      <rect x="14" y="5" width="4" height="14" rx="1" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
      <polygon points="6,4 20,12 6,20" />
    </svg>
  );
}

function VideoRecorder({
  onSend,
  onCancel,
  defaultTitle = "Video Message",
  className,
}: VideoRecorderProps) {
  const recorderId = useId();
  const screenPreviewRef = useRef<HTMLVideoElement>(null);
  const cameraPreviewRef = useRef<HTMLVideoElement>(null);
  const recordedPreviewRef = useRef<HTMLVideoElement>(null);
  const [isSending, setIsSending] = useState(false);
  const [title, setTitle] = useState(defaultTitle);
  const [recordMode, setRecordMode] = useState<"screen" | "camera" | "both">(
    "screen"
  );

  const {
    isRecording,
    isPaused,
    duration,
    previewStream,
    cameraStream,
    recordedBlob,
    error,
    startRecording,
    stopRecording,
    pauseRecording,
    resumeRecording,
    resetRecording,
  } = useRecorder();

  // Attach preview streams to video elements
  useEffect(() => {
    if (screenPreviewRef.current && previewStream) {
      screenPreviewRef.current.srcObject = previewStream;
    }
  }, [previewStream]);

  useEffect(() => {
    if (cameraPreviewRef.current && cameraStream) {
      cameraPreviewRef.current.srcObject = cameraStream;
    }
  }, [cameraStream]);

  // Show recorded blob in preview
  useEffect(() => {
    if (recordedPreviewRef.current && recordedBlob) {
      recordedPreviewRef.current.src = URL.createObjectURL(recordedBlob);
    }
    return () => {
      if (recordedPreviewRef.current?.src) {
        URL.revokeObjectURL(recordedPreviewRef.current.src);
      }
    };
  }, [recordedBlob]);

  const handleStartRecording = useCallback(async () => {
    const options = {
      screen: recordMode === "screen" || recordMode === "both",
      camera: recordMode === "camera" || recordMode === "both",
      audio: true,
    };
    await startRecording(options);
  }, [recordMode, startRecording]);

  const handleSend = useCallback(async () => {
    if (!recordedBlob) return;
    setIsSending(true);
    try {
      await onSend(recordedBlob, duration, title);
      resetRecording();
    } catch (err) {
      console.error("Failed to send video message:", err);
    } finally {
      setIsSending(false);
    }
  }, [recordedBlob, duration, title, onSend, resetRecording]);

  const handleReRecord = useCallback(() => {
    resetRecording();
  }, [resetRecording]);

  // State: recorded blob available — show preview + send/re-record
  if (recordedBlob) {
    return (
      <Card className={cn("overflow-hidden", className)}>
        <CardContent className="p-4 space-y-4">
          {/* Recorded video preview */}
          <div className="relative aspect-video w-full overflow-hidden rounded-lg bg-black">
            <video
              ref={recordedPreviewRef}
              controls
              className="h-full w-full"
              playsInline
            />
            <Badge
              variant="secondary"
              className="absolute top-2 right-2 bg-black/70 text-white font-mono"
            >
              {formatDuration(duration)}
            </Badge>
          </div>

          {/* Title input */}
          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Add a title..."
            className="w-full rounded-md border bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            aria-label="Video message title"
          />

          {/* Action buttons */}
          <div className="flex gap-2">
            <Button
              variant="outline"
              onClick={handleReRecord}
              disabled={isSending}
              className="flex-1"
            >
              Re-record
            </Button>
            <Button
              onClick={handleSend}
              disabled={isSending}
              className="flex-1"
            >
              {isSending ? (
                <span className="flex items-center gap-2">
                  <span className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
                  Sending...
                </span>
              ) : (
                "Send"
              )}
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }

  // State: recording or idle
  return (
    <Card className={cn("overflow-hidden", className)}>
      <CardContent className="p-4 space-y-4">
        {/* Preview area */}
        <div className="relative aspect-video w-full overflow-hidden rounded-lg bg-muted">
          {previewStream ? (
            <>
              <video
                ref={screenPreviewRef}
                autoPlay
                muted
                playsInline
                className="h-full w-full object-contain"
              />

              {/* Camera PiP overlay */}
              {cameraStream && (
                <div className="absolute bottom-3 right-3 h-24 w-32 overflow-hidden rounded-full border-2 border-white shadow-lg">
                  <video
                    ref={cameraPreviewRef}
                    autoPlay
                    muted
                    playsInline
                    className="h-full w-full object-cover"
                  />
                </div>
              )}

              {/* Recording indicator */}
              <div className="absolute top-3 left-3 flex items-center gap-2">
                <div
                  className={cn(
                    "h-3 w-3 rounded-full",
                    isPaused
                      ? "bg-yellow-500"
                      : "bg-red-500 animate-pulse"
                  )}
                />
                <Badge
                  variant="secondary"
                  className="bg-black/70 text-white font-mono"
                >
                  {formatDuration(duration)}
                </Badge>
              </div>
            </>
          ) : (
            <div className="flex h-full w-full flex-col items-center justify-center gap-4 text-muted-foreground">
              <svg
                width="48"
                height="48"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
              >
                <path d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14" />
                <rect x="1" y="6" width="14" height="12" rx="2" />
              </svg>
              <span className="text-sm">Ready to record</span>
            </div>
          )}
        </div>

        {/* Record mode selector (only shown when not recording) */}
        {!isRecording && (
          <div className="flex gap-2">
            {(["screen", "camera", "both"] as const).map((mode) => (
              <Button
                key={`${recorderId}-${mode}`}
                variant={recordMode === mode ? "default" : "outline"}
                size="sm"
                onClick={() => setRecordMode(mode)}
                className="flex-1 capitalize"
              >
                {mode === "both" ? "Screen + Camera" : mode}
              </Button>
            ))}
          </div>
        )}

        {/* Controls */}
        <div className="flex items-center justify-center gap-3">
          {!isRecording ? (
            <Button
              size="lg"
              variant="destructive"
              onClick={handleStartRecording}
              className="gap-2 rounded-full px-6"
            >
              <RecordIcon />
              Record
            </Button>
          ) : (
            <>
              {/* Pause/Resume */}
              <Button
                size="icon"
                variant="outline"
                onClick={isPaused ? resumeRecording : pauseRecording}
                aria-label={isPaused ? "Resume" : "Pause"}
              >
                {isPaused ? <PlayIcon /> : <PauseIcon />}
              </Button>

              {/* Stop */}
              <Button
                size="lg"
                variant="destructive"
                onClick={stopRecording}
                className="gap-2 rounded-full px-6"
              >
                <StopIcon />
                Stop
              </Button>
            </>
          )}

          {/* Cancel */}
          {onCancel && !isRecording && (
            <Button variant="ghost" onClick={onCancel}>
              Cancel
            </Button>
          )}
        </div>

        {/* Error display */}
        {error && (
          <p className="text-sm text-destructive text-center">{error}</p>
        )}
      </CardContent>
    </Card>
  );
}

export { VideoRecorder };
export type { VideoRecorderProps };
```

### Step 7: Create `src/components/video/video-message-card.tsx`

```tsx
"use client";

import { useState, useCallback, useId } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@src/lib/utils";
import type { VideoMessageWithDetails } from "@src/lib/video/types-messaging";

type VideoMessageCardProps = {
  message: VideoMessageWithDetails;
  onPlay?: (playbackId: string) => void;
  onReply?: (messageId: string) => void;
  className?: string;
};

function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

function formatRelativeTime(date: Date): string {
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return "just now";
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString();
}

function VideoMessageCard({
  message,
  onPlay,
  onReply,
  className,
}: VideoMessageCardProps) {
  const cardId = useId();
  const [isExpanded, setIsExpanded] = useState(false);

  const thumbnailUrl = message.muxPlaybackId
    ? `https://image.mux.com/${message.muxPlaybackId}/thumbnail.jpg?width=320&height=180&time=2`
    : null;

  const handlePlay = useCallback(() => {
    if (onPlay && message.muxPlaybackId) {
      onPlay(message.muxPlaybackId);
    }
  }, [onPlay, message.muxPlaybackId]);

  const handleReply = useCallback(() => {
    if (onReply) {
      onReply(message.id);
    }
  }, [onReply, message.id]);

  const toggleExpanded = useCallback(() => {
    setIsExpanded((prev) => !prev);
  }, []);

  const isPlayable = message.status === "ready" && message.muxPlaybackId;

  return (
    <Card className={cn("overflow-hidden", className)}>
      <CardContent className="p-0">
        <div className="flex gap-3 p-3">
          {/* Thumbnail */}
          <div className="relative shrink-0 w-40 overflow-hidden rounded-md bg-muted">
            <div className="aspect-video">
              {thumbnailUrl ? (
                <img
                  src={thumbnailUrl}
                  alt={message.title}
                  className="h-full w-full object-cover"
                  loading="lazy"
                />
              ) : (
                <div className="flex h-full w-full items-center justify-center">
                  <svg
                    width="32"
                    height="32"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="1"
                    className="text-muted-foreground"
                  >
                    <rect x="2" y="4" width="20" height="16" rx="2" />
                    <polygon points="10,8 16,12 10,16" fill="currentColor" />
                  </svg>
                </div>
              )}

              {/* Play overlay */}
              {isPlayable && (
                <button
                  type="button"
                  onClick={handlePlay}
                  className="absolute inset-0 flex items-center justify-center text-white opacity-0 transition-opacity hover:opacity-100 bg-black/30"
                  aria-label={`Play ${message.title}`}
                >
                  <svg
                    width="32"
                    height="32"
                    viewBox="0 0 32 32"
                    fill="currentColor"
                  >
                    <circle cx="16" cy="16" r="16" fillOpacity="0.7" />
                    <polygon points="12,9 24,16 12,23" fill="white" />
                  </svg>
                </button>
              )}

              {/* Duration badge */}
              {message.duration !== null && message.duration > 0 && (
                <Badge
                  variant="secondary"
                  className="absolute bottom-1 right-1 bg-black/70 text-white text-xs font-mono"
                >
                  {formatDuration(message.duration)}
                </Badge>
              )}
            </div>
          </div>

          {/* Content */}
          <div className="flex min-w-0 flex-1 flex-col justify-between">
            <div>
              {/* Header: sender + time */}
              <div className="flex items-center gap-2 mb-1">
                {message.senderImage ? (
                  <img
                    src={message.senderImage}
                    alt={message.senderName ?? ""}
                    className="h-5 w-5 rounded-full"
                  />
                ) : (
                  <div className="flex h-5 w-5 items-center justify-center rounded-full bg-primary text-primary-foreground text-xs">
                    {(message.senderName ?? "?")[0].toUpperCase()}
                  </div>
                )}
                <span className="text-xs font-medium truncate">
                  {message.senderName ?? message.senderEmail ?? "Unknown"}
                </span>
                <span className="text-xs text-muted-foreground">
                  {formatRelativeTime(message.createdAt)}
                </span>
              </div>

              {/* Title */}
              <h4 className="text-sm font-medium leading-tight mb-1 line-clamp-1">
                {message.title}
              </h4>

              {/* AI Summary */}
              {message.summary && (
                <p className="text-xs text-muted-foreground line-clamp-2">
                  {message.summary}
                </p>
              )}

              {/* Status badge for non-ready messages */}
              {message.status !== "ready" && (
                <Badge
                  variant={
                    message.status === "errored" ? "destructive" : "secondary"
                  }
                  className="mt-1"
                >
                  {message.status === "transcribing"
                    ? "Transcribing..."
                    : message.status === "processing"
                      ? "Processing..."
                      : message.status === "uploading"
                        ? "Uploading..."
                        : message.status}
                </Badge>
              )}
            </div>

            {/* Actions */}
            <div className="flex items-center gap-2 mt-2">
              {message.summary && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={toggleExpanded}
                  className="h-7 text-xs"
                >
                  {isExpanded ? "Hide details" : "Show details"}
                </Button>
              )}
              {onReply && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={handleReply}
                  className="h-7 text-xs"
                >
                  Reply
                  {message.replyCount > 0 && ` (${message.replyCount})`}
                </Button>
              )}
            </div>
          </div>
        </div>

        {/* Expanded details: transcript + action items */}
        {isExpanded && (
          <div className="border-t px-3 py-3 space-y-3">
            {/* Action items */}
            {message.actionItems && message.actionItems.length > 0 && (
              <div>
                <h5 className="text-xs font-semibold text-muted-foreground mb-1">
                  Action Items
                </h5>
                <ul className="space-y-1">
                  {message.actionItems.map((item, idx) => (
                    <li
                      key={`${cardId}-action-${item.slice(0, 20)}`}
                      className="flex items-start gap-2 text-xs"
                    >
                      <span className="mt-0.5 h-3 w-3 shrink-0 rounded border" />
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            {/* Transcript */}
            {message.transcript && (
              <div>
                <h5 className="text-xs font-semibold text-muted-foreground mb-1">
                  Transcript
                </h5>
                <p className="text-xs text-muted-foreground whitespace-pre-wrap leading-relaxed max-h-48 overflow-y-auto">
                  {message.transcript}
                </p>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

export { VideoMessageCard };
export type { VideoMessageCardProps };
```

### Step 8: Create `src/components/video/video-thread.tsx`

```tsx
"use client";

import { useState, useCallback, useId } from "react";
import { Button } from "@/components/ui/button";
import { cn } from "@src/lib/utils";
import { VideoMessageCard } from "@/components/video/video-message-card";
import { VideoRecorder } from "@/components/video/video-recorder";
import type { VideoMessageWithDetails } from "@src/lib/video/types-messaging";

type VideoThreadProps = {
  message: VideoMessageWithDetails;
  replies: VideoMessageWithDetails[];
  onPlay?: (playbackId: string) => void;
  onSendReply?: (
    parentId: string,
    blob: Blob,
    duration: number,
    title: string
  ) => Promise<void>;
  className?: string;
};

function VideoThread({
  message,
  replies,
  onPlay,
  onSendReply,
  className,
}: VideoThreadProps) {
  const threadId = useId();
  const [isReplying, setIsReplying] = useState(false);

  const handleReply = useCallback(() => {
    setIsReplying(true);
  }, []);

  const handleCancelReply = useCallback(() => {
    setIsReplying(false);
  }, []);

  const handleSendReply = useCallback(
    async (blob: Blob, duration: number, title: string) => {
      if (onSendReply) {
        await onSendReply(message.id, blob, duration, title);
      }
      setIsReplying(false);
    },
    [message.id, onSendReply]
  );

  return (
    <div className={cn("space-y-3", className)}>
      {/* Original message */}
      <VideoMessageCard
        message={message}
        onPlay={onPlay}
        onReply={onSendReply ? handleReply : undefined}
      />

      {/* Replies */}
      {replies.length > 0 && (
        <div className="ml-6 space-y-2 border-l-2 border-muted pl-4">
          {replies.map((reply) => (
            <VideoMessageCard
              key={`${threadId}-reply-${reply.id}`}
              message={reply}
              onPlay={onPlay}
            />
          ))}
        </div>
      )}

      {/* Reply recorder */}
      {isReplying && (
        <div className="ml-6 border-l-2 border-primary pl-4">
          <VideoRecorder
            onSend={handleSendReply}
            onCancel={handleCancelReply}
            defaultTitle={`Re: ${message.title}`}
          />
        </div>
      )}

      {/* Reply button (when not actively replying) */}
      {!isReplying && onSendReply && (
        <div className="ml-6">
          <Button
            variant="ghost"
            size="sm"
            onClick={handleReply}
            className="text-xs text-muted-foreground"
          >
            Reply with video
          </Button>
        </div>
      )}
    </div>
  );
}

export { VideoThread };
export type { VideoThreadProps };
```

### Step 9: Create `src/app/api/video/messages/route.ts`

```typescript
import { NextResponse } from "next/server";
import { auth } from "@src/lib/auth";
import { headers } from "next/headers";
import {
  createVideoMessage,
  getVideoMessages,
} from "@src/lib/video/video-message";
import type { VideoMessage, VideoMessageWithDetails } from "@src/lib/video/types-messaging";

type CreateResponse = {
  message: VideoMessage;
  uploadUrl: string;
};

type ListResponse = {
  messages: VideoMessageWithDetails[];
};

/** POST /api/video/messages — Create a video message and get upload URL */
export async function POST(
  request: Request
): Promise<NextResponse<CreateResponse | { error: string }>> {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json().catch(() => ({}));
    const { title, parentId } = body as {
      title?: string;
      parentId?: string;
    };

    const result = await createVideoMessage(
      session.user.id,
      title ?? "Video Message",
      parentId
    );

    return NextResponse.json(result, { status: 201 });
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Failed to create video message";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

/** GET /api/video/messages — List video messages for the authenticated user */
export async function GET(): Promise<
  NextResponse<ListResponse | { error: string }>
> {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const messages = await getVideoMessages(session.user.id);
    return NextResponse.json({ messages });
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Failed to list video messages";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

### Step 10: Create `src/app/api/video/messages/[id]/route.ts`

```typescript
import { NextResponse } from "next/server";
import { auth } from "@src/lib/auth";
import { headers } from "next/headers";
import {
  getVideoMessage,
  getVideoMessageReplies,
} from "@src/lib/video/video-message";
import type { VideoMessageWithDetails } from "@src/lib/video/types-messaging";

type RouteParams = { params: Promise<{ id: string }> };

type MessageResponse = {
  message: VideoMessageWithDetails;
};

type RepliesResponse = {
  replies: VideoMessageWithDetails[];
};

/** GET /api/video/messages/[id] — Get a video message with details */
export async function GET(
  request: Request,
  { params }: RouteParams
): Promise<NextResponse<MessageResponse | RepliesResponse | { error: string }>> {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const url = new URL(request.url);
  const includeReplies = url.searchParams.get("replies") === "true";

  try {
    if (includeReplies) {
      const replies = await getVideoMessageReplies(id);
      return NextResponse.json({ replies });
    }

    const message = await getVideoMessage(id);
    if (!message) {
      return NextResponse.json(
        { error: "Video message not found" },
        { status: 404 }
      );
    }

    // Verify ownership
    if (message.userId !== session.user.id) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    return NextResponse.json({ message });
  } catch (err) {
    const errorMessage =
      err instanceof Error ? err.message : "Failed to get video message";
    return NextResponse.json({ error: errorMessage }, { status: 500 });
  }
}
```

### Step 11: Push database schema

```bash
bunx drizzle-kit push
```

## Usage

### Record and Send a Video Message

```tsx
"use client";

import { useCallback } from "react";
import { VideoRecorder } from "@/components/video/video-recorder";

function RecordPage() {
  const handleSend = useCallback(
    async (blob: Blob, duration: number, title: string) => {
      // 1. Create message and get upload URL
      const res = await fetch("/api/video/messages", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title }),
      });
      const { uploadUrl } = await res.json();

      // 2. Upload the video blob directly to MUX
      await fetch(uploadUrl, {
        method: "PUT",
        body: blob,
      });

      // 3. MUX webhook will process the video automatically:
      //    - Asset becomes "ready"
      //    - Transcription runs
      //    - AI summary generates
    },
    []
  );

  return (
    <div className="mx-auto max-w-2xl p-4">
      <h1 className="mb-4 text-xl font-semibold">Record a Video Message</h1>
      <VideoRecorder onSend={handleSend} />
    </div>
  );
}
```

### Display Video Messages with Threads

```tsx
"use client";

import { useEffect, useState, useId } from "react";
import { VideoThread } from "@/components/video/video-thread";
import type { VideoMessageWithDetails } from "@src/lib/video/types-messaging";

type ThreadData = {
  message: VideoMessageWithDetails;
  replies: VideoMessageWithDetails[];
};

function MessagesPage() {
  const listId = useId();
  const [threads, setThreads] = useState<ThreadData[]>([]);

  useEffect(() => {
    async function loadMessages() {
      const res = await fetch("/api/video/messages");
      const { messages } = await res.json();

      // Load replies for each message
      const threadsData: ThreadData[] = await Promise.all(
        messages.map(async (msg: VideoMessageWithDetails) => {
          const repliesRes = await fetch(
            `/api/video/messages/${msg.id}?replies=true`
          );
          const { replies } = await repliesRes.json();
          return { message: msg, replies };
        })
      );

      setThreads(threadsData);
    }
    loadMessages();
  }, []);

  return (
    <div className="mx-auto max-w-2xl space-y-6 p-4">
      <h1 className="text-xl font-semibold">Video Messages</h1>
      {threads.map((thread) => (
        <VideoThread
          key={`${listId}-${thread.message.id}`}
          message={thread.message}
          replies={thread.replies}
          onPlay={(playbackId) => {
            window.open(
              `https://stream.mux.com/${playbackId}.m3u8`,
              "_blank"
            );
          }}
          onSendReply={async (parentId, blob, duration, title) => {
            const res = await fetch("/api/video/messages", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ title, parentId }),
            });
            const { uploadUrl } = await res.json();
            await fetch(uploadUrl, { method: "PUT", body: blob });
          }}
        />
      ))}
    </div>
  );
}
```

### Server-Side: Process Video After Upload

The `video-message.ts` module triggers an Inngest job (`job/video-message-process`) after MUX confirms the asset is ready. Register this function in your Inngest serve endpoint:

```typescript
// src/lib/queue/functions/video-message-process.ts
import { inngest } from "@src/lib/queue/client";
import { db } from "@src/lib/db";
import { videoMessages } from "@src/lib/db/schema";
import { eq } from "drizzle-orm";

export const videoMessageProcess = inngest.createFunction(
  {
    id: "video-message-process",
    retries: 3,
  },
  { event: "job/video-message-process" },
  async ({ event, step }) => {
    const { videoMessageId, muxPlaybackId } = event.data;

    // Step 1: Transcribe the video
    const transcript = await step.run("transcribe", async () => {
      // Call your transcription service here
      // e.g., using the transcription skill
      return "Transcription placeholder — wire to your transcription provider.";
    });

    // Step 2: Generate AI summary
    const summary = await step.run("summarize", async () => {
      // Call your AI summary service here
      // e.g., using the ai-meeting-notes skill
      return {
        text: "Summary placeholder — wire to your AI provider.",
        actionItems: ["Follow up on discussion points"],
      };
    });

    // Step 3: Update the video message record
    await step.run("update-record", async () => {
      await db
        .update(videoMessages)
        .set({
          transcript,
          summary,
          status: "ready",
          updatedAt: new Date(),
        })
        .where(eq(videoMessages.id, videoMessageId));
    });

    return { videoMessageId, status: "ready" };
  }
);
```

Add to `src/app/api/inngest/route.ts`:

```typescript
import { videoMessageProcess } from "@src/lib/queue/functions/video-message-process";

export const { GET, POST, PUT } = serve({
  client: inngest,
  functions: [
    // ... existing functions
    videoMessageProcess,
  ],
});
```

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/video/messages` | Yes | Create video message, get MUX upload URL |
| GET | `/api/video/messages` | Yes | List user's video messages (top-level only) |
| GET | `/api/video/messages/[id]` | Yes | Get message with transcript + summary |
| GET | `/api/video/messages/[id]?replies=true` | Yes | Get replies to a message |

## Acceptance Criteria

- [ ] `useRecorder()` hook starts screen + camera recording via MediaRecorder API
- [ ] `useRecorder()` returns a Blob on stop with correct MIME type
- [ ] `useRecorder()` supports pause/resume during recording
- [ ] `useRecorder()` tracks recording duration in real-time
- [ ] `VideoRecorder` shows camera preview as picture-in-picture overlay
- [ ] `VideoRecorder` shows recording indicator + timer
- [ ] `VideoRecorder` shows preview after recording with re-record/send options
- [ ] `VideoRecorder` shows loading spinner on the send button while uploading
- [ ] `VideoMessageCard` displays thumbnail, AI summary, duration, sender info
- [ ] `VideoMessageCard` expands to show transcript + action items
- [ ] `VideoThread` renders original message + indented replies
- [ ] `VideoThread` opens inline recorder for reply
- [ ] `POST /api/video/messages` creates record and returns MUX upload URL
- [ ] `GET /api/video/messages` lists user's messages
- [ ] `GET /api/video/messages/[id]` returns message with details
- [ ] `GET /api/video/messages/[id]?replies=true` returns replies
- [ ] After MUX webhook fires, background job transcribes + summarizes
- [ ] `video_messages` table exists with correct Drizzle schema
- [ ] All components use `useId` for React list keys
- [ ] All components use `"use client"` directive
- [ ] All components use shadcn/ui primitives
- [ ] No usage of `any` type anywhere in the code
- [ ] `tsc` passes with no errors
- [ ] `bun run build` succeeds

## Troubleshooting

### Screen recording permission denied

**Symptoms**: `startRecording()` fails with "Permission denied" error.

**Cause**: User denied the screen sharing prompt, or the browser does not support `getDisplayMedia`.

**Fix**: Ensure the app is served over HTTPS (or localhost). Check that the browser supports the Screen Capture API. Safari requires user interaction to trigger `getDisplayMedia`. Show a clear message asking the user to allow screen sharing.

### Camera preview not showing

**Symptoms**: The PiP camera overlay is blank or missing.

**Cause**: Camera permission denied, or the `cameraStream` is not being attached to the video element.

**Fix**: Check browser camera permissions. The `use-recorder` hook sets `cameraStream` separately from `previewStream`. Ensure the camera video element ref is correctly attached in `VideoRecorder`.

### Recorded video has no audio

**Symptoms**: Playback of the recorded blob has video but no audio.

**Cause**: When recording screen + camera, audio tracks may not be combined correctly. Some browsers do not include system audio in `getDisplayMedia`.

**Fix**: The recorder prioritizes screen audio when available, then falls back to microphone audio. For system audio capture, users must check the "Share audio" box in the browser's screen sharing dialog. If only camera mode is selected, microphone audio is always included.

### Upload fails after recording

**Symptoms**: The PUT request to the MUX upload URL returns an error.

**Cause**: The MUX upload URL may have expired (24-hour TTL), or the file exceeds the size limit.

**Fix**: Request a fresh upload URL immediately before uploading. MUX direct uploads support files up to 100GB. Ensure the video blob is sent as the raw request body (not FormData).

### Video message stuck in "transcribing" status

**Symptoms**: The message shows "Transcribing..." indefinitely.

**Cause**: The Inngest background job failed or the transcription/AI service is not configured.

**Fix**:

1. Check the Inngest Dev Server dashboard at `http://localhost:3000/api/inngest` for failed runs
2. Verify the `videoMessageProcess` function is registered in the serve endpoint
3. Check that your transcription and AI services are configured and accessible
4. The placeholder implementation returns stub data — wire it to your actual providers

### "use client" missing in parent component

**Symptoms**: Build error about hooks in Server Components.

**Cause**: `VideoRecorder`, `VideoMessageCard`, and `VideoThread` all use `"use client"`. If you wrap them in a page component that uses hooks, that component must also be a Client Component.

**Fix**: Add `"use client"` to the top of any page or layout component that directly uses these components with React hooks like `useState` or `useEffect`.
