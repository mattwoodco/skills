---
name: video-ui
description: LiveKit video UI components — room provider, participant grid, speaker view, controls bar, prejoin screen, and participant tile using @livekit/components-react and shadcn/ui. Use this skill when the user says "add video UI", "video components", "setup video-ui", "video call UI", or "participant grid".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [video-room, add-shadcn]
---

# Video UI

A complete set of video conferencing UI components built on `@livekit/components-react` and styled with shadcn/ui. Provides a room provider, participant grid, active speaker spotlight, media controls, device selection prejoin screen, and individual participant tiles.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `video-room` skill installed (LiveKit server SDK, token API, types)
- `add-shadcn` skill installed (Button, Card components available)
- shadcn/ui components: `button`, `card`, `select`, `avatar`

## Installation

```bash
bun add @livekit/components-react @livekit/components-styles
bunx shadcn@latest add button card select avatar
```

## What Gets Created

```
src/
└── components/
    └── video/
        ├── video-room-provider.tsx     # LiveKitRoom wrapper, fetches token from /api/video/token
        ├── participant-grid.tsx        # Grid layout using useParticipants + useTracks
        ├── speaker-view.tsx            # Active speaker spotlight using useSpeakingParticipants
        ├── controls-bar.tsx            # Mute / camera / screen share / leave buttons
        ├── prejoin-screen.tsx          # Device selection + camera preview before joining
        └── participant-tile.tsx        # Single participant video track + name overlay + speaking indicator
```

## Setup Steps

### Step 1: Create `src/components/video/video-room-provider.tsx`

```tsx
"use client";

import { useState, useEffect, useCallback, type ReactNode } from "react";
import { LiveKitRoom } from "@livekit/components-react";
import "@livekit/components-styles/prefabs.css";
import type { TokenResponse } from "@/lib/video/types";

type VideoRoomProviderProps = {
  roomName: string;
  participantName?: string;
  children: ReactNode;
  onConnected?: () => void;
  onDisconnected?: () => void;
  onError?: (error: Error) => void;
};

export function VideoRoomProvider({
  roomName,
  participantName,
  children,
  onConnected,
  onDisconnected,
  onError,
}: VideoRoomProviderProps) {
  const [token, setToken] = useState<string | null>(null);
  const [url, setUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  const fetchToken = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const res = await fetch("/api/video/token", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ roomName, participantName }),
      });

      if (!res.ok) {
        const body = await res.json().catch(() => ({ error: "Failed to get token" }));
        throw new Error((body as { error: string }).error);
      }

      const data: TokenResponse = await res.json();
      setToken(data.token);
      setUrl(data.url);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Failed to connect";
      setError(message);
      onError?.(err instanceof Error ? err : new Error(message));
    } finally {
      setIsLoading(false);
    }
  }, [roomName, participantName, onError]);

  useEffect(() => {
    fetchToken();
  }, [fetchToken]);

  if (isLoading) {
    return (
      <div className="flex h-full items-center justify-center">
        <div className="flex items-center gap-2 text-muted-foreground">
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
          <span>Connecting to room...</span>
        </div>
      </div>
    );
  }

  if (error || !token || !url) {
    return (
      <div className="flex h-full items-center justify-center">
        <div className="text-center">
          <p className="text-destructive font-medium">Failed to join room</p>
          <p className="text-muted-foreground text-sm mt-1">{error ?? "Unknown error"}</p>
          <button
            type="button"
            onClick={fetchToken}
            className="mt-4 rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground hover:bg-primary/90"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  return (
    <LiveKitRoom
      token={token}
      serverUrl={url}
      connect={true}
      onConnected={onConnected}
      onDisconnected={onDisconnected}
      onError={(err) => onError?.(err)}
      data-lk-theme="default"
      className="h-full w-full"
    >
      {children}
    </LiveKitRoom>
  );
}
```

### Step 2: Create `src/components/video/participant-tile.tsx`

```tsx
"use client";

import { useRef, useEffect } from "react";
import type { TrackReferenceOrPlaceholder } from "@livekit/components-react";
import { Card } from "@/components/ui/card";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";

type ParticipantTileProps = {
  trackRef: TrackReferenceOrPlaceholder;
  className?: string;
};

function getInitials(name: string): string {
  return name
    .split(" ")
    .map((part) => part.charAt(0))
    .join("")
    .toUpperCase()
    .slice(0, 2);
}

export function ParticipantTile({ trackRef, className }: ParticipantTileProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const participant = trackRef.participant;
  const publication = trackRef.publication;
  const track = publication?.track;
  const isSpeaking = participant.isSpeaking;
  const displayName = participant.name ?? participant.identity;

  useEffect(() => {
    if (!videoRef.current || !track) return;
    track.attach(videoRef.current);
    return () => {
      track.detach(videoRef.current!);
    };
  }, [track]);

  const hasVideo = track && !publication?.isMuted;

  return (
    <Card
      className={`relative overflow-hidden bg-muted ${
        isSpeaking ? "ring-2 ring-primary" : ""
      } ${className ?? ""}`}
    >
      {hasVideo ? (
        <video
          ref={videoRef}
          autoPlay
          playsInline
          muted
          className="h-full w-full object-cover"
        />
      ) : (
        <div className="flex h-full w-full items-center justify-center bg-muted">
          <Avatar className="h-16 w-16">
            <AvatarFallback className="text-lg">
              {getInitials(displayName)}
            </AvatarFallback>
          </Avatar>
        </div>
      )}

      {/* Name overlay */}
      <div className="absolute bottom-0 left-0 right-0 bg-black/50 px-3 py-1.5">
        <div className="flex items-center gap-2">
          {isSpeaking && (
            <span className="h-2 w-2 shrink-0 rounded-full bg-green-400 animate-pulse" />
          )}
          <span className="truncate text-sm font-medium text-white">
            {displayName}
          </span>
        </div>
      </div>
    </Card>
  );
}
```

### Step 3: Create `src/components/video/participant-grid.tsx`

```tsx
"use client";

import { useId } from "react";
import { useTracks } from "@livekit/components-react";
import { Track } from "livekit-client";
import { ParticipantTile } from "@/components/video/participant-tile";

type ParticipantGridProps = {
  className?: string;
};

function getGridCols(count: number): string {
  if (count <= 1) return "grid-cols-1";
  if (count <= 4) return "grid-cols-2";
  if (count <= 9) return "grid-cols-3";
  return "grid-cols-4";
}

export function ParticipantGrid({ className }: ParticipantGridProps) {
  const gridId = useId();

  const trackRefs = useTracks(
    [
      { source: Track.Source.Camera, withPlaceholder: true },
      { source: Track.Source.ScreenShare, withPlaceholder: false },
    ],
    { onlySubscribed: false }
  );

  if (trackRefs.length === 0) {
    return (
      <div className="flex h-full items-center justify-center text-muted-foreground">
        <p>Waiting for participants...</p>
      </div>
    );
  }

  const gridCols = getGridCols(trackRefs.length);

  return (
    <div
      className={`grid gap-2 p-2 ${gridCols} auto-rows-fr ${className ?? ""}`}
    >
      {trackRefs.map((trackRef) => (
        <ParticipantTile
          key={`${gridId}-${trackRef.participant.sid}-${trackRef.source}`}
          trackRef={trackRef}
          className="aspect-video"
        />
      ))}
    </div>
  );
}
```

### Step 4: Create `src/components/video/speaker-view.tsx`

```tsx
"use client";

import { useId } from "react";
import { useTracks } from "@livekit/components-react";
import { Track } from "livekit-client";
import { ParticipantTile } from "@/components/video/participant-tile";

type SpeakerViewProps = {
  className?: string;
};

export function SpeakerView({ className }: SpeakerViewProps) {
  const speakerId = useId();

  const trackRefs = useTracks(
    [{ source: Track.Source.Camera, withPlaceholder: true }],
    { onlySubscribed: false }
  );

  if (trackRefs.length === 0) {
    return (
      <div className="flex h-full items-center justify-center text-muted-foreground">
        <p>Waiting for participants...</p>
      </div>
    );
  }

  // Sort so that speaking participants appear first
  const sorted = [...trackRefs].sort((a, b) => {
    if (a.participant.isSpeaking && !b.participant.isSpeaking) return -1;
    if (!a.participant.isSpeaking && b.participant.isSpeaking) return 1;
    return 0;
  });

  const activeSpeaker = sorted[0];
  const others = sorted.slice(1);

  return (
    <div className={`flex h-full flex-col gap-2 p-2 ${className ?? ""}`}>
      {/* Active speaker spotlight */}
      <div className="flex-1 min-h-0">
        <ParticipantTile
          key={`${speakerId}-spotlight-${activeSpeaker.participant.sid}`}
          trackRef={activeSpeaker}
          className="h-full w-full"
        />
      </div>

      {/* Thumbnail strip */}
      {others.length > 0 && (
        <div className="flex h-28 shrink-0 gap-2 overflow-x-auto">
          {others.map((trackRef) => (
            <ParticipantTile
              key={`${speakerId}-thumb-${trackRef.participant.sid}`}
              trackRef={trackRef}
              className="aspect-video h-full w-auto shrink-0"
            />
          ))}
        </div>
      )}
    </div>
  );
}
```

### Step 5: Create `src/components/video/controls-bar.tsx`

```tsx
"use client";

import {
  useLocalParticipant,
  useRoomContext,
} from "@livekit/components-react";
import { Track } from "livekit-client";
import { Button } from "@/components/ui/button";

type ControlsBarProps = {
  onLeave?: () => void;
  className?: string;
  showScreenShare?: boolean;
};

export function ControlsBar({
  onLeave,
  className,
  showScreenShare = true,
}: ControlsBarProps) {
  const { localParticipant } = useLocalParticipant();
  const room = useRoomContext();

  const isMicEnabled = localParticipant.isMicrophoneEnabled;
  const isCameraEnabled = localParticipant.isCameraEnabled;
  const isScreenShareEnabled = localParticipant.isScreenShareEnabled;

  const handleToggleMic = async () => {
    await localParticipant.setMicrophoneEnabled(!isMicEnabled);
  };

  const handleToggleCamera = async () => {
    await localParticipant.setCameraEnabled(!isCameraEnabled);
  };

  const handleToggleScreenShare = async () => {
    await localParticipant.setScreenShareEnabled(!isScreenShareEnabled);
  };

  const handleLeave = () => {
    room.disconnect();
    onLeave?.();
  };

  return (
    <div
      className={`flex items-center justify-center gap-3 border-t bg-background px-4 py-3 ${className ?? ""}`}
    >
      {/* Microphone toggle */}
      <Button
        variant={isMicEnabled ? "secondary" : "destructive"}
        size="sm"
        onClick={handleToggleMic}
        title={isMicEnabled ? "Mute microphone" : "Unmute microphone"}
      >
        {isMicEnabled ? (
          <MicOnIcon className="mr-2 h-4 w-4" />
        ) : (
          <MicOffIcon className="mr-2 h-4 w-4" />
        )}
        {isMicEnabled ? "Mute" : "Unmute"}
      </Button>

      {/* Camera toggle */}
      <Button
        variant={isCameraEnabled ? "secondary" : "destructive"}
        size="sm"
        onClick={handleToggleCamera}
        title={isCameraEnabled ? "Turn off camera" : "Turn on camera"}
      >
        {isCameraEnabled ? (
          <CameraOnIcon className="mr-2 h-4 w-4" />
        ) : (
          <CameraOffIcon className="mr-2 h-4 w-4" />
        )}
        {isCameraEnabled ? "Camera Off" : "Camera On"}
      </Button>

      {/* Screen share toggle */}
      {showScreenShare && (
        <Button
          variant={isScreenShareEnabled ? "default" : "secondary"}
          size="sm"
          onClick={handleToggleScreenShare}
          title={isScreenShareEnabled ? "Stop sharing" : "Share screen"}
        >
          <ScreenShareIcon className="mr-2 h-4 w-4" />
          {isScreenShareEnabled ? "Stop Share" : "Share Screen"}
        </Button>
      )}

      {/* Leave button */}
      <Button
        variant="destructive"
        size="sm"
        onClick={handleLeave}
        title="Leave room"
      >
        <LeaveIcon className="mr-2 h-4 w-4" />
        Leave
      </Button>
    </div>
  );
}

// --- Inline SVG icons (no external dependency needed) ---

function MicOnIcon({ className }: { className?: string }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" className={className}>
      <path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z" />
      <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
      <line x1="12" x2="12" y1="19" y2="22" />
    </svg>
  );
}

function MicOffIcon({ className }: { className?: string }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" className={className}>
      <line x1="2" x2="22" y1="2" y2="22" />
      <path d="M18.89 13.23A7.12 7.12 0 0 0 19 12v-2" />
      <path d="M5 10v2a7 7 0 0 0 12 5.29" />
      <path d="M15 9.34V5a3 3 0 0 0-5.68-1.33" />
      <path d="M9 9v3a3 3 0 0 0 5.12 2.12" />
      <line x1="12" x2="12" y1="19" y2="22" />
    </svg>
  );
}

function CameraOnIcon({ className }: { className?: string }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" className={className}>
      <path d="m16 13 5.223 3.482a.5.5 0 0 0 .777-.416V7.87a.5.5 0 0 0-.752-.432L16 10.5" />
      <rect x="2" y="6" width="14" height="12" rx="2" />
    </svg>
  );
}

function CameraOffIcon({ className }: { className?: string }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" className={className}>
      <line x1="2" x2="22" y1="2" y2="22" />
      <path d="M21 17.09V7.87a.5.5 0 0 0-.752-.432L16 10.5" />
      <path d="M14 14.24V18a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h1.05" />
    </svg>
  );
}

function ScreenShareIcon({ className }: { className?: string }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" className={className}>
      <path d="M13 3H4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-3" />
      <path d="M8 21h8" />
      <path d="M12 17v4" />
      <path d="m17 8 5-5" />
      <path d="M17 3h5v5" />
    </svg>
  );
}

function LeaveIcon({ className }: { className?: string }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" className={className}>
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <polyline points="16 17 21 12 16 7" />
      <line x1="21" x2="9" y1="12" y2="12" />
    </svg>
  );
}
```

### Step 6: Create `src/components/video/prejoin-screen.tsx`

```tsx
"use client";

import { useState, useRef, useEffect, useCallback, useId } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

type PrejoinScreenProps = {
  roomName: string;
  onJoin: (settings: JoinSettings) => void;
  className?: string;
};

type JoinSettings = {
  audioDeviceId: string | undefined;
  videoDeviceId: string | undefined;
  audioEnabled: boolean;
  videoEnabled: boolean;
};

type MediaDeviceOption = {
  deviceId: string;
  label: string;
};

export function PrejoinScreen({ roomName, onJoin, className }: PrejoinScreenProps) {
  const audioSelectId = useId();
  const videoSelectId = useId();
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  const [audioDevices, setAudioDevices] = useState<MediaDeviceOption[]>([]);
  const [videoDevices, setVideoDevices] = useState<MediaDeviceOption[]>([]);
  const [selectedAudioId, setSelectedAudioId] = useState<string | undefined>(undefined);
  const [selectedVideoId, setSelectedVideoId] = useState<string | undefined>(undefined);
  const [audioEnabled, setAudioEnabled] = useState(true);
  const [videoEnabled, setVideoEnabled] = useState(true);
  const [isLoadingDevices, setIsLoadingDevices] = useState(true);

  const enumerateDevices = useCallback(async () => {
    setIsLoadingDevices(true);
    try {
      // Request permissions first so device labels are available
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: true,
        video: true,
      });

      const devices = await navigator.mediaDevices.enumerateDevices();

      const audioInputs = devices
        .filter((d) => d.kind === "audioinput" && d.deviceId)
        .map((d) => ({ deviceId: d.deviceId, label: d.label || "Microphone" }));

      const videoInputs = devices
        .filter((d) => d.kind === "videoinput" && d.deviceId)
        .map((d) => ({ deviceId: d.deviceId, label: d.label || "Camera" }));

      setAudioDevices(audioInputs);
      setVideoDevices(videoInputs);

      if (audioInputs.length > 0 && !selectedAudioId) {
        setSelectedAudioId(audioInputs[0].deviceId);
      }
      if (videoInputs.length > 0 && !selectedVideoId) {
        setSelectedVideoId(videoInputs[0].deviceId);
      }

      // Stop the initial permission stream
      stream.getTracks().forEach((t) => t.stop());
    } catch {
      // Permissions denied or no devices
    } finally {
      setIsLoadingDevices(false);
    }
  }, [selectedAudioId, selectedVideoId]);

  // Enumerate devices on mount
  useEffect(() => {
    enumerateDevices();
  }, [enumerateDevices]);

  // Start camera preview
  useEffect(() => {
    if (!videoEnabled || !selectedVideoId) {
      if (streamRef.current) {
        streamRef.current.getTracks().forEach((t) => t.stop());
        streamRef.current = null;
      }
      return;
    }

    let cancelled = false;

    const startPreview = async () => {
      try {
        // Stop previous stream
        if (streamRef.current) {
          streamRef.current.getTracks().forEach((t) => t.stop());
        }

        const stream = await navigator.mediaDevices.getUserMedia({
          video: { deviceId: { exact: selectedVideoId } },
        });

        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }

        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
        }
      } catch {
        // Camera unavailable
      }
    };

    startPreview();

    return () => {
      cancelled = true;
      if (streamRef.current) {
        streamRef.current.getTracks().forEach((t) => t.stop());
        streamRef.current = null;
      }
    };
  }, [videoEnabled, selectedVideoId]);

  const handleJoin = () => {
    // Stop preview stream before joining
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }

    onJoin({
      audioDeviceId: selectedAudioId,
      videoDeviceId: selectedVideoId,
      audioEnabled,
      videoEnabled,
    });
  };

  return (
    <div className={`flex h-full items-center justify-center p-4 ${className ?? ""}`}>
      <Card className="w-full max-w-lg">
        <CardHeader>
          <CardTitle>Join Room: {roomName}</CardTitle>
        </CardHeader>

        <CardContent className="space-y-6">
          {/* Camera preview */}
          <div className="relative aspect-video overflow-hidden rounded-lg bg-muted">
            {videoEnabled ? (
              <video
                ref={videoRef}
                autoPlay
                playsInline
                muted
                className="h-full w-full object-cover mirror"
                style={{ transform: "scaleX(-1)" }}
              />
            ) : (
              <div className="flex h-full items-center justify-center text-muted-foreground">
                <p>Camera off</p>
              </div>
            )}
          </div>

          {/* Device selectors */}
          {isLoadingDevices ? (
            <div className="flex items-center justify-center py-4 text-muted-foreground text-sm">
              <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent mr-2" />
              Loading devices...
            </div>
          ) : (
            <div className="space-y-4">
              {/* Microphone selector */}
              <div className="space-y-2">
                <label htmlFor={audioSelectId} className="text-sm font-medium">
                  Microphone
                </label>
                <div className="flex items-center gap-2">
                  <Select
                    value={selectedAudioId}
                    onValueChange={setSelectedAudioId}
                  >
                    <SelectTrigger id={audioSelectId} className="flex-1">
                      <SelectValue placeholder="Select microphone" />
                    </SelectTrigger>
                    <SelectContent>
                      {audioDevices.map((device) => (
                        <SelectItem
                          key={`${audioSelectId}-${device.deviceId}`}
                          value={device.deviceId}
                        >
                          {device.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Button
                    variant={audioEnabled ? "secondary" : "destructive"}
                    size="sm"
                    onClick={() => setAudioEnabled((prev) => !prev)}
                  >
                    {audioEnabled ? "On" : "Off"}
                  </Button>
                </div>
              </div>

              {/* Camera selector */}
              <div className="space-y-2">
                <label htmlFor={videoSelectId} className="text-sm font-medium">
                  Camera
                </label>
                <div className="flex items-center gap-2">
                  <Select
                    value={selectedVideoId}
                    onValueChange={setSelectedVideoId}
                  >
                    <SelectTrigger id={videoSelectId} className="flex-1">
                      <SelectValue placeholder="Select camera" />
                    </SelectTrigger>
                    <SelectContent>
                      {videoDevices.map((device) => (
                        <SelectItem
                          key={`${videoSelectId}-${device.deviceId}`}
                          value={device.deviceId}
                        >
                          {device.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Button
                    variant={videoEnabled ? "secondary" : "destructive"}
                    size="sm"
                    onClick={() => setVideoEnabled((prev) => !prev)}
                  >
                    {videoEnabled ? "On" : "Off"}
                  </Button>
                </div>
              </div>
            </div>
          )}
        </CardContent>

        <CardFooter>
          <Button onClick={handleJoin} className="w-full" size="lg">
            Join Room
          </Button>
        </CardFooter>
      </Card>
    </div>
  );
}
```

## Usage

### Basic Video Call Page

```tsx
// src/app/video/[roomName]/page.tsx
"use client";

import { useState, use } from "react";
import { VideoRoomProvider } from "@/components/video/video-room-provider";
import { ParticipantGrid } from "@/components/video/participant-grid";
import { ControlsBar } from "@/components/video/controls-bar";
import { PrejoinScreen } from "@/components/video/prejoin-screen";

type PageProps = {
  params: Promise<{ roomName: string }>;
};

export default function VideoRoomPage({ params }: PageProps) {
  const { roomName } = use(params);
  const [joined, setJoined] = useState(false);

  if (!joined) {
    return (
      <PrejoinScreen
        roomName={roomName}
        onJoin={() => setJoined(true)}
      />
    );
  }

  return (
    <div className="flex h-screen flex-col">
      <VideoRoomProvider roomName={roomName}>
        <div className="flex-1 min-h-0">
          <ParticipantGrid className="h-full" />
        </div>
        <ControlsBar onLeave={() => setJoined(false)} />
      </VideoRoomProvider>
    </div>
  );
}
```

### Speaker View Layout

```tsx
"use client";

import { VideoRoomProvider } from "@/components/video/video-room-provider";
import { SpeakerView } from "@/components/video/speaker-view";
import { ControlsBar } from "@/components/video/controls-bar";

function MeetingRoom({ roomName }: { roomName: string }) {
  return (
    <div className="flex h-screen flex-col">
      <VideoRoomProvider roomName={roomName}>
        <div className="flex-1 min-h-0">
          <SpeakerView className="h-full" />
        </div>
        <ControlsBar />
      </VideoRoomProvider>
    </div>
  );
}
```

### Prejoin with Custom Settings

```tsx
"use client";

import { PrejoinScreen } from "@/components/video/prejoin-screen";

function Lobby({ roomName }: { roomName: string }) {
  const handleJoin = (settings: {
    audioDeviceId: string | undefined;
    videoDeviceId: string | undefined;
    audioEnabled: boolean;
    videoEnabled: boolean;
  }) => {
    console.log("Joining with settings:", settings);
    // Navigate to room or set joined state
  };

  return <PrejoinScreen roomName={roomName} onJoin={handleJoin} />;
}
```

## Component Reference

| Component | Purpose | Key Props |
|-----------|---------|-----------|
| `VideoRoomProvider` | Wraps children in LiveKitRoom with auto token fetch | `roomName`, `participantName`, `onConnected`, `onDisconnected`, `onError` |
| `ParticipantGrid` | Renders all participants in an adaptive grid | `className` |
| `SpeakerView` | Active speaker spotlight with thumbnail strip | `className` |
| `ControlsBar` | Media control buttons (mic, camera, screen share, leave) | `onLeave`, `showScreenShare`, `className` |
| `PrejoinScreen` | Device selection and camera preview before joining | `roomName`, `onJoin`, `className` |
| `ParticipantTile` | Single participant with video, name overlay, speaking indicator | `trackRef`, `className` |

## Acceptance Criteria

- [ ] `VideoRoomProvider` fetches a token from `/api/video/token` and connects to LiveKit
- [ ] `ParticipantGrid` renders all participants in a responsive grid
- [ ] `SpeakerView` shows the active speaker in a spotlight with others as thumbnails
- [ ] `ControlsBar` toggles microphone, camera, and screen share correctly
- [ ] `PrejoinScreen` enumerates devices and shows a camera preview
- [ ] `PrejoinScreen` allows selecting different audio/video devices
- [ ] `ParticipantTile` shows a speaking indicator when the participant is speaking
- [ ] `ParticipantTile` shows an avatar fallback when video is off
- [ ] All components use shadcn/ui Button, Card, Select, Avatar
- [ ] `@livekit/components-styles/prefabs.css` is imported in the provider
- [ ] No usage of `any` type anywhere in the code
- [ ] All components with hooks use `"use client"` directive
- [ ] `useId` is used for generating keys in lists
- [ ] `tsc` passes with no errors
- [ ] `bun run build` succeeds

## Troubleshooting

### "LiveKitRoom" errors about missing context

**Symptoms**: `useLocalParticipant` or `useTracks` throws "must be used within LiveKitRoom".

**Cause**: Component is not wrapped in `VideoRoomProvider` or `LiveKitRoom`.

**Fix**: Ensure all video UI components are rendered as children of `VideoRoomProvider`.

### Camera preview is mirrored

**Symptoms**: Text appears backwards in the prejoin camera preview.

**Cause**: The preview video is CSS-mirrored with `transform: scaleX(-1)` for a natural selfie view. This is intentional and matches the behavior of Zoom, Google Meet, etc.

### Device list is empty

**Symptoms**: No devices appear in the `PrejoinScreen` dropdowns.

**Cause**: Browser permissions for camera/microphone were denied, or the page is not served over HTTPS.

**Fix**:

1. Check browser permissions in the address bar
2. For local development, `localhost` is treated as secure
3. For deployment, ensure the site is served over HTTPS

### Grid layout looks wrong

**Symptoms**: Participant tiles are very small or overlap.

**Cause**: The parent container does not have a defined height.

**Fix**: Ensure the parent of `ParticipantGrid` has `h-full` or an explicit height. The grid uses `auto-rows-fr` which requires a sized container.

### Token fetch fails with 401

**Symptoms**: `VideoRoomProvider` shows "Failed to join room" with a 401 error.

**Cause**: The user is not authenticated.

**Fix**: Ensure the user is signed in via better-auth before rendering `VideoRoomProvider`. The `/api/video/token` route requires authentication.
