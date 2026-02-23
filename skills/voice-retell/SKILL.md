---
name: voice-retell
description: Browser voice calling via Retell AI — WebRTC voice mode toggle in chat, web call token API, transcript bridging to chat messages, and mute/unmute controls. Use this skill when the user says "add voice", "voice calling", "setup retell", "add voice mode", or "setup voice-retell".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-14
updated: 2026-02-14
dependencies: [ai-chat, auth, env-config]
---

# Voice Retell

Browser-based voice calling powered by Retell AI. Adds a "Switch to voice" toggle inside the chat UI that connects via WebRTC, streams real-time audio to/from a Retell voice agent, and bridges call transcripts back into the same chat session for unified history.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `ai-chat` skill installed (chat UI at `src/components/ai/chat.tsx`, sessions API)
- `auth` skill installed (`withAuth` at `@src/lib/auth-guard`)
- `env-config` skill installed (`src/env.ts`)
- shadcn/ui initialized

## Installation

```bash
bun add retell-client-js-sdk
```

## Environment Variables

Add to `.env.local`:

```env
# Retell AI
RETELL_API_KEY=your-retell-api-key-here
RETELL_AGENT_ID=your-retell-agent-id-here
```

### Update `src/env.ts`

Add to the `server` object:

```typescript
  server: {
    // ... existing variables
    RETELL_API_KEY: z.string(),
    RETELL_AGENT_ID: z.string(),
  },
```

Add to the `runtimeEnv` object:

```typescript
  runtimeEnv: {
    // ... existing variables
    RETELL_API_KEY: process.env.RETELL_API_KEY,
    RETELL_AGENT_ID: process.env.RETELL_AGENT_ID,
  },
```

## What Gets Created

```
src/
├── app/
│   └── api/
│       └── ai/
│           └── voice/
│               └── route.ts                   # POST — create web call, return access token
├── lib/
│   └── voice/
│       └── retell.ts                          # Server-side Retell API helper
└── components/
    └── ai/
        ├── voice-toggle.tsx                   # Mic button that starts/stops voice mode
        └── voice-overlay.tsx                  # Active call overlay with status + mute
```

## What Gets Modified

```
src/
└── components/
    └── ai/
        └── chat.tsx                           # Add VoiceToggle to input area
```

## Setup Steps

### Step 1: Create `src/lib/voice/retell.ts`

```typescript
type CreateWebCallResponse = {
  call_type: "web_call";
  access_token: string;
  call_id: string;
  call_status: string;
};

type CreateWebCallOptions = {
  agentId: string;
  metadata?: Record<string, string>;
  dynamicVariables?: Record<string, string>;
};

/**
 * Create a Retell web call and return the access token.
 * Must be called server-side — uses RETELL_API_KEY.
 */
export async function createWebCall(
  options: CreateWebCallOptions
): Promise<CreateWebCallResponse> {
  const apiKey = process.env.RETELL_API_KEY;
  if (!apiKey) throw new Error("RETELL_API_KEY is not set");

  const response = await fetch("https://api.retellai.com/v2/create-web-call", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      agent_id: options.agentId,
      ...(options.metadata && { metadata: options.metadata }),
      ...(options.dynamicVariables && {
        retell_llm_dynamic_variables: options.dynamicVariables,
      }),
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Retell API error ${response.status}: ${errorText}`);
  }

  return response.json() as Promise<CreateWebCallResponse>;
}
```

### Step 2: Create `src/app/api/ai/voice/route.ts`

```typescript
import { NextResponse } from "next/server";
import { withAuth } from "@src/lib/auth-guard";
import { createWebCall } from "@src/lib/voice/retell";
import { db } from "@/db";
import { chatSession, chatMessage } from "@/db/schema/chat";
import { eq, and } from "drizzle-orm";

type VoiceCallBody = {
  sessionId?: string;
};

/** POST /api/ai/voice — create a Retell web call token */
export const POST = withAuth(async (request, { user }) => {
  const body: VoiceCallBody = await request.json();

  const agentId = process.env.RETELL_AGENT_ID;
  if (!agentId) {
    return NextResponse.json(
      { error: "RETELL_AGENT_ID is not configured" },
      { status: 500 }
    );
  }

  // Resolve or create a chat session for transcript bridging
  let activeSessionId = body.sessionId;

  if (activeSessionId) {
    const existing = await db
      .select({ id: chatSession.id })
      .from(chatSession)
      .where(
        and(
          eq(chatSession.id, activeSessionId),
          eq(chatSession.userId, user.id)
        )
      )
      .limit(1);

    if (existing.length === 0) {
      return NextResponse.json(
        { error: "Session not found" },
        { status: 404 }
      );
    }
  } else {
    const [created] = await db
      .insert(chatSession)
      .values({ userId: user.id, title: "Voice Call" })
      .returning({ id: chatSession.id });
    activeSessionId = created.id;
  }

  try {
    const call = await createWebCall({
      agentId,
      metadata: {
        userId: user.id,
        sessionId: activeSessionId,
      },
    });

    return NextResponse.json({
      accessToken: call.access_token,
      callId: call.call_id,
      sessionId: activeSessionId,
    });
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Failed to create call",
      },
      { status: 500 }
    );
  }
});
```

### Step 3: Create `src/components/ai/voice-overlay.tsx`

```tsx
"use client";

import { useCallback } from "react";
import { Microphone, MicrophoneSlash, Phone, X } from "@phosphor-icons/react";

type VoiceOverlayProps = {
  isConnected: boolean;
  isAgentTalking: boolean;
  isMuted: boolean;
  onMuteToggle: () => void;
  onEndCall: () => void;
  transcript: string | null;
};

export function VoiceOverlay({
  isConnected,
  isAgentTalking,
  isMuted,
  onMuteToggle,
  onEndCall,
  transcript,
}: VoiceOverlayProps) {
  if (!isConnected) return null;

  return (
    <div className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-background/95 backdrop-blur-sm">
      {/* Pulsing indicator */}
      <div className="relative mb-8">
        <div
          className={`h-24 w-24 rounded-full ${
            isAgentTalking
              ? "animate-pulse bg-primary/20"
              : "bg-muted"
          } flex items-center justify-center`}
        >
          <Phone
            className={`h-10 w-10 ${
              isAgentTalking ? "text-primary" : "text-muted-foreground"
            }`}
          />
        </div>
        {isAgentTalking && (
          <div className="absolute inset-0 animate-ping rounded-full bg-primary/10" />
        )}
      </div>

      {/* Status */}
      <p className="mb-2 text-sm font-medium">
        {isAgentTalking ? "Agent is speaking..." : "Listening..."}
      </p>

      {/* Live transcript */}
      {transcript && (
        <p className="mb-8 max-w-md px-4 text-center text-sm text-muted-foreground">
          {transcript}
        </p>
      )}

      {/* Controls */}
      <div className="flex gap-4">
        <button
          type="button"
          onClick={onMuteToggle}
          className={`flex h-14 w-14 items-center justify-center rounded-full transition-colors ${
            isMuted
              ? "bg-destructive/10 text-destructive"
              : "bg-muted hover:bg-muted/80"
          }`}
          title={isMuted ? "Unmute" : "Mute"}
        >
          {isMuted ? (
            <MicrophoneSlash className="h-6 w-6" />
          ) : (
            <Microphone className="h-6 w-6" />
          )}
        </button>

        <button
          type="button"
          onClick={onEndCall}
          className="flex h-14 w-14 items-center justify-center rounded-full bg-destructive text-destructive-foreground transition-colors hover:bg-destructive/90"
          title="End call"
        >
          <X className="h-6 w-6" />
        </button>
      </div>
    </div>
  );
}
```

### Step 4: Create `src/components/ai/voice-toggle.tsx`

```tsx
"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import { RetellWebClient } from "retell-client-js-sdk";
import { Microphone } from "@phosphor-icons/react";
import { VoiceOverlay } from "./voice-overlay";

type TranscriptUpdate = {
  transcript?: Array<{
    role: string;
    content: string;
  }>;
};

type VoiceToggleProps = {
  sessionId: string | null;
  onSessionCreated?: (sessionId: string) => void;
  onTranscriptUpdate?: (role: "user" | "assistant", text: string) => void;
};

export function VoiceToggle({
  sessionId,
  onSessionCreated,
  onTranscriptUpdate,
}: VoiceToggleProps) {
  const [isConnected, setIsConnected] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [isAgentTalking, setIsAgentTalking] = useState(false);
  const [isMuted, setIsMuted] = useState(false);
  const [transcript, setTranscript] = useState<string | null>(null);
  const retellRef = useRef<RetellWebClient | null>(null);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (retellRef.current) {
        retellRef.current.stopCall();
      }
    };
  }, []);

  const startCall = useCallback(async () => {
    setIsConnecting(true);

    try {
      // Request a web call token from our API
      const res = await fetch("/api/ai/voice", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sessionId }),
      });

      if (!res.ok) {
        const error = await res.json();
        throw new Error(error.error ?? "Failed to start call");
      }

      const data: { accessToken: string; callId: string; sessionId: string } =
        await res.json();

      // Notify parent of session creation
      if (!sessionId && onSessionCreated) {
        onSessionCreated(data.sessionId);
      }

      // Initialize Retell client
      const retell = new RetellWebClient();
      retellRef.current = retell;

      // Register event handlers
      retell.on("call_started", () => {
        setIsConnected(true);
        setIsConnecting(false);
      });

      retell.on("call_ended", () => {
        setIsConnected(false);
        setIsConnecting(false);
        setIsAgentTalking(false);
        setTranscript(null);
        retellRef.current = null;
      });

      retell.on("agent_start_talking", () => {
        setIsAgentTalking(true);
      });

      retell.on("agent_stop_talking", () => {
        setIsAgentTalking(false);
      });

      retell.on("update", (update: TranscriptUpdate) => {
        if (update.transcript && update.transcript.length > 0) {
          const latest = update.transcript[update.transcript.length - 1];
          setTranscript(latest.content);
          if (onTranscriptUpdate) {
            const role = latest.role === "agent" ? "assistant" : "user";
            onTranscriptUpdate(role as "user" | "assistant", latest.content);
          }
        }
      });

      retell.on("error", (error: Error) => {
        console.error("Retell error:", error);
        setIsConnected(false);
        setIsConnecting(false);
        retellRef.current = null;
      });

      // Start the call
      await retell.startCall({
        accessToken: data.accessToken,
        sampleRate: 24000,
      });
    } catch (error) {
      console.error("Failed to start voice call:", error);
      setIsConnecting(false);
    }
  }, [sessionId, onSessionCreated, onTranscriptUpdate]);

  const endCall = useCallback(() => {
    if (retellRef.current) {
      retellRef.current.stopCall();
    }
    setIsConnected(false);
    setIsAgentTalking(false);
    setTranscript(null);
    retellRef.current = null;
  }, []);

  const toggleMute = useCallback(() => {
    if (!retellRef.current) return;
    if (isMuted) {
      retellRef.current.unmute();
    } else {
      retellRef.current.mute();
    }
    setIsMuted((prev) => !prev);
  }, [isMuted]);

  return (
    <>
      {/* Voice mode button */}
      <button
        type="button"
        onClick={isConnected ? endCall : startCall}
        disabled={isConnecting}
        className={`inline-flex items-center justify-center rounded-lg p-2 transition-colors ${
          isConnected
            ? "bg-destructive text-destructive-foreground"
            : isConnecting
              ? "animate-pulse bg-primary/50 text-primary-foreground"
              : "bg-muted hover:bg-muted/80 text-muted-foreground"
        }`}
        title={isConnected ? "End voice call" : "Start voice call"}
      >
        <Microphone className="h-5 w-5" />
      </button>

      {/* Full-screen overlay during active call */}
      <VoiceOverlay
        isConnected={isConnected}
        isAgentTalking={isAgentTalking}
        isMuted={isMuted}
        onMuteToggle={toggleMute}
        onEndCall={endCall}
        transcript={transcript}
      />
    </>
  );
}
```

### Step 5: Modify `src/components/ai/chat.tsx`

Add the VoiceToggle component to the chat input area.

Find this in `src/components/ai/chat.tsx`:

```typescript
import { ChatContainer } from "@/components/ai/chat-container";
import { PromptInput } from "@/components/ai/prompt-input";
import { Loader } from "@/components/ai/loader";
import { MessageBubble } from "@/components/ai/message";
```

Replace with:

```typescript
import { ChatContainer } from "@/components/ai/chat-container";
import { PromptInput } from "@/components/ai/prompt-input";
import { Loader } from "@/components/ai/loader";
import { MessageBubble } from "@/components/ai/message";
import { VoiceToggle } from "@/components/ai/voice-toggle";
```

Find this in `src/components/ai/chat.tsx`:

```tsx
      <div className="border-t p-4">
        <PromptInput
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          onSubmit={handleSend}
          disabled={isStreaming || isSubmitting}
          placeholder="Type a message..."
        />
      </div>
```

Replace with:

```tsx
      <div className="border-t p-4">
        <div className="relative flex items-end gap-2">
          <div className="flex-1">
            <PromptInput
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              onSubmit={handleSend}
              disabled={isStreaming || isSubmitting}
              placeholder="Type a message..."
            />
          </div>
          <VoiceToggle
            sessionId={sessionId}
            onSessionCreated={_onSessionCreated}
          />
        </div>
      </div>
```

## Usage

### Starting a Voice Call

Click the microphone button in the chat input area. The app will:

1. Request a web call token from `/api/ai/voice`
2. Connect to Retell via WebRTC
3. Show a full-screen voice overlay with status indicators
4. Bridge the transcript into the chat session

### During a Call

- **Mute/Unmute**: Click the microphone icon in the overlay
- **End call**: Click the X button
- **Live transcript**: Shows the latest utterance in real-time

### Programmatic Usage

```typescript
// Create a web call token
const res = await fetch("/api/ai/voice", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ sessionId: "existing-session-id" }),
});
const { accessToken, callId, sessionId } = await res.json();
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/ai/voice` | Create a Retell web call `{ sessionId? }` → `{ accessToken, callId, sessionId }` |

## Acceptance Criteria

- Click the microphone button and a Retell web call connects via WebRTC
- Voice overlay appears with pulsing indicator during agent speech
- Mute/unmute toggles the microphone
- Ending the call returns to the text chat view
- The call is scoped to the current chat session (or creates one)
- Live transcript updates appear in the overlay
- `RETELL_API_KEY` and `RETELL_AGENT_ID` are never exposed to the client
- Unauthenticated requests to `/api/ai/voice` return 401
- `tsc` passes with no errors
- `bun run build` succeeds
