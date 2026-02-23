---
name: audio-room
description: Audio-only room with LiveKit — circular avatar grid, speaking indicators, raise hand queue. Twitter Spaces / Clubhouse style. Use this skill when the user says "add audio room", "audio chat", "voice room", "spaces", "clubhouse", or "audio-only room".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [video-room, add-shadcn]
---

# Audio Room (LiveKit)

Audio-only room experience using [LiveKit](https://livekit.io). Participants appear as circular avatars in a grid layout with real-time speaking indicators (pulsing rings), raise hand queue, mute/deafen controls, and no video tracks published. Designed to feel like Twitter Spaces or Clubhouse.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `video-room` skill applied (provides `livekit-client`, `@livekit/components-react`, LiveKit token server, and room connection infrastructure)
- `add-shadcn` skill applied (provides `Button`, `Badge`, `Card`, `Avatar`, `Tooltip` components)

## Installation

No additional packages required. Uses `livekit-client` and `@livekit/components-react` from the `video-room` skill.

## Environment Variables

Uses the same LiveKit environment variables from the `video-room` skill:

```env
LIVEKIT_API_KEY=your_api_key
LIVEKIT_API_SECRET=your_api_secret
NEXT_PUBLIC_LIVEKIT_URL=wss://your-project.livekit.cloud
```

## What Gets Created

```
src/
├── components/
│   └── video/
│       ├── audio-room.tsx             # Audio-only room layout — circular avatar grid
│       ├── audio-controls.tsx         # Mute, deafen, raise hand, leave controls
│       └── speaking-indicator.tsx     # Pulsing ring animation for speaking state
└── lib/
    └── video/
        └── use-audio-room.ts         # Hook: join room with audio-only config, speaking state
```

## Setup Steps

### Step 1: Create `src/lib/video/use-audio-room.ts`

```typescript
"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Room,
  RoomEvent,
  Track,
  type RemoteParticipant,
  type LocalParticipant,
  type Participant,
  type RoomOptions,
  type AudioCaptureOptions,
  ConnectionState,
} from "livekit-client";

type AudioParticipant = {
  identity: string;
  name: string;
  isSpeaking: boolean;
  isMuted: boolean;
  isLocal: boolean;
  audioLevel: number;
  metadata: string | undefined;
};

type RaiseHandEntry = {
  identity: string;
  name: string;
  raisedAt: number;
};

type UseAudioRoomOptions = {
  token: string;
  serverUrl: string;
  onDisconnected?: () => void;
};

type UseAudioRoomReturn = {
  room: Room | null;
  participants: AudioParticipant[];
  isConnected: boolean;
  isConnecting: boolean;
  isMuted: boolean;
  isDeafened: boolean;
  handRaised: boolean;
  raiseHandQueue: RaiseHandEntry[];
  toggleMute: () => Promise<void>;
  toggleDeafen: () => void;
  toggleRaiseHand: () => void;
  disconnect: () => void;
};

const RAISE_HAND_EVENT = "raise-hand";
const LOWER_HAND_EVENT = "lower-hand";

function participantToAudio(
  participant: Participant,
  isLocal: boolean
): AudioParticipant {
  const audioPublication = participant.getTrackPublications().find(
    (pub) => pub.track?.kind === Track.Kind.Audio
  );

  return {
    identity: participant.identity,
    name: participant.name ?? participant.identity,
    isSpeaking: participant.isSpeaking,
    isMuted: audioPublication?.isMuted ?? true,
    isLocal,
    audioLevel: participant.audioLevel,
    metadata: participant.metadata,
  };
}

export function useAudioRoom({
  token,
  serverUrl,
  onDisconnected,
}: UseAudioRoomOptions): UseAudioRoomReturn {
  const [room, setRoom] = useState<Room | null>(null);
  const [participants, setParticipants] = useState<AudioParticipant[]>([]);
  const [isConnected, setIsConnected] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [isMuted, setIsMuted] = useState(false);
  const [isDeafened, setIsDeafened] = useState(false);
  const [handRaised, setHandRaised] = useState(false);
  const [raiseHandQueue, setRaiseHandQueue] = useState<RaiseHandEntry[]>([]);

  const updateParticipants = useCallback((currentRoom: Room) => {
    const local = participantToAudio(currentRoom.localParticipant, true);
    const remotes = Array.from(currentRoom.remoteParticipants.values()).map(
      (p) => participantToAudio(p, false)
    );
    setParticipants([local, ...remotes]);
  }, []);

  useEffect(() => {
    if (!token || !serverUrl) return;

    const roomOptions: RoomOptions = {
      audioCaptureDefaults: {
        autoGainControl: true,
        echoCancellation: true,
        noiseSuppression: true,
      } satisfies AudioCaptureOptions,

      adaptiveStream: false,
    };

    const newRoom = new Room(roomOptions);
    setRoom(newRoom);
    setIsConnecting(true);

    const handleParticipantChange = () => updateParticipants(newRoom);

    const handleActiveSpeakersChanged = (speakers: Participant[]) => {
      void speakers;
      updateParticipants(newRoom);
    };

    const handleDisconnected = () => {
      setIsConnected(false);
      setIsConnecting(false);
      setParticipants([]);
      setRaiseHandQueue([]);
      onDisconnected?.();
    };

    const handleDataReceived = (
      payload: Uint8Array,
      participant?: RemoteParticipant
    ) => {
      const decoder = new TextDecoder();
      const message = decoder.decode(payload);

      if (message === RAISE_HAND_EVENT && participant) {
        setRaiseHandQueue((prev) => {
          if (prev.some((entry) => entry.identity === participant.identity)) {
            return prev;
          }
          return [
            ...prev,
            {
              identity: participant.identity,
              name: participant.name ?? participant.identity,
              raisedAt: Date.now(),
            },
          ];
        });
      }

      if (message === LOWER_HAND_EVENT && participant) {
        setRaiseHandQueue((prev) =>
          prev.filter((entry) => entry.identity !== participant.identity)
        );
      }
    };

    newRoom.on(RoomEvent.ParticipantConnected, handleParticipantChange);
    newRoom.on(RoomEvent.ParticipantDisconnected, handleParticipantChange);
    newRoom.on(RoomEvent.TrackSubscribed, handleParticipantChange);
    newRoom.on(RoomEvent.TrackUnsubscribed, handleParticipantChange);
    newRoom.on(RoomEvent.TrackMuted, handleParticipantChange);
    newRoom.on(RoomEvent.TrackUnmuted, handleParticipantChange);
    newRoom.on(RoomEvent.ActiveSpeakersChanged, handleActiveSpeakersChanged);
    newRoom.on(RoomEvent.Disconnected, handleDisconnected);
    newRoom.on(RoomEvent.DataReceived, handleDataReceived);

    newRoom
      .connect(serverUrl, token)
      .then(() => {
        setIsConnected(true);
        setIsConnecting(false);
        // Publish audio only — no video
        return newRoom.localParticipant.setMicrophoneEnabled(true);
      })
      .then(() => {
        updateParticipants(newRoom);
      })
      .catch((err: unknown) => {
        console.error("Failed to connect to audio room:", err);
        setIsConnecting(false);
      });

    return () => {
      newRoom.off(RoomEvent.ParticipantConnected, handleParticipantChange);
      newRoom.off(RoomEvent.ParticipantDisconnected, handleParticipantChange);
      newRoom.off(RoomEvent.TrackSubscribed, handleParticipantChange);
      newRoom.off(RoomEvent.TrackUnsubscribed, handleParticipantChange);
      newRoom.off(RoomEvent.TrackMuted, handleParticipantChange);
      newRoom.off(RoomEvent.TrackUnmuted, handleParticipantChange);
      newRoom.off(RoomEvent.ActiveSpeakersChanged, handleActiveSpeakersChanged);
      newRoom.off(RoomEvent.Disconnected, handleDisconnected);
      newRoom.off(RoomEvent.DataReceived, handleDataReceived);

      if (newRoom.state !== ConnectionState.Disconnected) {
        newRoom.disconnect();
      }
    };
  }, [token, serverUrl, updateParticipants, onDisconnected]);

  const toggleMute = useCallback(async () => {
    if (!room) return;
    const newMuted = !isMuted;
    await room.localParticipant.setMicrophoneEnabled(!newMuted);
    setIsMuted(newMuted);
  }, [room, isMuted]);

  const toggleDeafen = useCallback(() => {
    if (!room) return;
    const newDeafened = !isDeafened;
    setIsDeafened(newDeafened);

    // Enable/disable all remote audio track publications using RemoteParticipant's typed map
    room.remoteParticipants.forEach((participant) => {
      participant.audioTrackPublications.forEach((pub) => {
        pub.setEnabled(!newDeafened);
      });
    });
  }, [room, isDeafened]);

  const toggleRaiseHand = useCallback(() => {
    if (!room) return;
    const newRaised = !handRaised;
    setHandRaised(newRaised);

    const encoder = new TextEncoder();
    const data = encoder.encode(newRaised ? RAISE_HAND_EVENT : LOWER_HAND_EVENT);
    room.localParticipant.publishData(data, { reliable: true });

    // Update local queue
    if (newRaised) {
      setRaiseHandQueue((prev) => [
        ...prev,
        {
          identity: room.localParticipant.identity,
          name: room.localParticipant.name ?? room.localParticipant.identity,
          raisedAt: Date.now(),
        },
      ]);
    } else {
      setRaiseHandQueue((prev) =>
        prev.filter(
          (entry) => entry.identity !== room.localParticipant.identity
        )
      );
    }
  }, [room, handRaised]);

  const disconnect = useCallback(() => {
    if (!room) return;
    room.disconnect();
    setIsConnected(false);
    setParticipants([]);
    setRaiseHandQueue([]);
    setHandRaised(false);
    setIsMuted(false);
    setIsDeafened(false);
  }, [room]);

  return {
    room,
    participants,
    isConnected,
    isConnecting,
    isMuted,
    isDeafened,
    handRaised,
    raiseHandQueue,
    toggleMute,
    toggleDeafen,
    toggleRaiseHand,
    disconnect,
  };
}
```

### Step 2: Create `src/components/video/speaking-indicator.tsx`

```typescript
"use client";

type SpeakingIndicatorProps = {
  isSpeaking: boolean;
  size?: number;
  color?: string;
  children: React.ReactNode;
};

export function SpeakingIndicator({
  isSpeaking,
  size = 80,
  color = "hsl(var(--primary))",
  children,
}: SpeakingIndicatorProps) {
  return (
    <div
      className="relative flex items-center justify-center"
      style={{ width: size, height: size }}
    >
      {/* Outer pulsing ring — visible when speaking */}
      <div
        className="absolute inset-0 rounded-full transition-all duration-200"
        style={{
          border: `3px solid ${color}`,
          opacity: isSpeaking ? 1 : 0,
          transform: isSpeaking ? "scale(1.15)" : "scale(1)",
          animation: isSpeaking ? "speaking-pulse 1.5s ease-in-out infinite" : "none",
        }}
      />
      {/* Middle ring glow */}
      <div
        className="absolute inset-0 rounded-full transition-all duration-200"
        style={{
          border: `2px solid ${color}`,
          opacity: isSpeaking ? 0.5 : 0,
          transform: isSpeaking ? "scale(1.08)" : "scale(1)",
          animation: isSpeaking
            ? "speaking-pulse 1.5s ease-in-out infinite 0.2s"
            : "none",
        }}
      />
      {/* Content (avatar) */}
      <div
        className="relative z-10 overflow-hidden rounded-full"
        style={{ width: size, height: size }}
      >
        {children}
      </div>
      {/* Inject keyframes */}
      <style>{`
        @keyframes speaking-pulse {
          0%, 100% {
            transform: scale(1.08);
            opacity: 0.6;
          }
          50% {
            transform: scale(1.18);
            opacity: 1;
          }
        }
      `}</style>
    </div>
  );
}
```

### Step 3: Create `src/components/video/audio-controls.tsx`

```typescript
"use client";

import { Button } from "@/components/ui/button";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { Badge } from "@/components/ui/badge";

type AudioControlsProps = {
  isMuted: boolean;
  isDeafened: boolean;
  handRaised: boolean;
  raiseHandCount: number;
  onToggleMute: () => void;
  onToggleDeafen: () => void;
  onToggleRaiseHand: () => void;
  onLeave: () => void;
};

function MicIcon({ muted }: { muted: boolean }) {
  if (muted) {
    return (
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="20"
        height="20"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <line x1="1" y1="1" x2="23" y2="23" />
        <path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6" />
        <path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2c0 .76-.13 1.49-.36 2.18" />
        <line x1="12" y1="19" x2="12" y2="23" />
        <line x1="8" y1="23" x2="16" y2="23" />
      </svg>
    );
  }
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z" />
      <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
      <line x1="12" y1="19" x2="12" y2="23" />
      <line x1="8" y1="23" x2="16" y2="23" />
    </svg>
  );
}

function HeadphonesIcon({ deafened }: { deafened: boolean }) {
  if (deafened) {
    return (
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="20"
        height="20"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M3 18v-6a9 9 0 0 1 18 0v6" />
        <path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z" />
        <line x1="1" y1="1" x2="23" y2="23" />
      </svg>
    );
  }
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M3 18v-6a9 9 0 0 1 18 0v6" />
      <path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z" />
    </svg>
  );
}

function HandIcon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M18 11V6a2 2 0 0 0-4 0v1" />
      <path d="M14 10V4a2 2 0 0 0-4 0v2" />
      <path d="M10 10.5V6a2 2 0 0 0-4 0v8" />
      <path d="M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15" />
    </svg>
  );
}

function PhoneOffIcon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.42 19.42 0 0 1-3.33-2.67m-2.67-3.34a19.79 19.79 0 0 1-3.07-8.63A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91" />
      <line x1="23" y1="1" x2="1" y2="23" />
    </svg>
  );
}

export function AudioControls({
  isMuted,
  isDeafened,
  handRaised,
  raiseHandCount,
  onToggleMute,
  onToggleDeafen,
  onToggleRaiseHand,
  onLeave,
}: AudioControlsProps) {
  return (
    <TooltipProvider delayDuration={300}>
      <div className="flex items-center justify-center gap-3 rounded-full bg-card/80 px-6 py-3 shadow-lg backdrop-blur-sm border">
        {/* Mute */}
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant={isMuted ? "destructive" : "secondary"}
              size="icon"
              className="h-12 w-12 rounded-full"
              onClick={onToggleMute}
            >
              <MicIcon muted={isMuted} />
            </Button>
          </TooltipTrigger>
          <TooltipContent>
            {isMuted ? "Unmute" : "Mute"}
          </TooltipContent>
        </Tooltip>

        {/* Deafen */}
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant={isDeafened ? "destructive" : "secondary"}
              size="icon"
              className="h-12 w-12 rounded-full"
              onClick={onToggleDeafen}
            >
              <HeadphonesIcon deafened={isDeafened} />
            </Button>
          </TooltipTrigger>
          <TooltipContent>
            {isDeafened ? "Undeafen" : "Deafen"}
          </TooltipContent>
        </Tooltip>

        {/* Raise Hand */}
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant={handRaised ? "default" : "secondary"}
              size="icon"
              className="relative h-12 w-12 rounded-full"
              onClick={onToggleRaiseHand}
            >
              <HandIcon />
              {raiseHandCount > 0 && (
                <Badge
                  variant="destructive"
                  className="absolute -right-1 -top-1 flex h-5 w-5 items-center justify-center rounded-full p-0 text-xs"
                >
                  {raiseHandCount}
                </Badge>
              )}
            </Button>
          </TooltipTrigger>
          <TooltipContent>
            {handRaised ? "Lower hand" : "Raise hand"}
          </TooltipContent>
        </Tooltip>

        {/* Leave */}
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant="destructive"
              size="icon"
              className="h-12 w-12 rounded-full"
              onClick={onLeave}
            >
              <PhoneOffIcon />
            </Button>
          </TooltipTrigger>
          <TooltipContent>Leave room</TooltipContent>
        </Tooltip>
      </div>
    </TooltipProvider>
  );
}
```

### Step 4: Create `src/components/video/audio-room.tsx`

```typescript
"use client";

import { useId } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { SpeakingIndicator } from "@/components/video/speaking-indicator";
import { AudioControls } from "@/components/video/audio-controls";
import { useAudioRoom } from "@src/lib/video/use-audio-room";

type AudioRoomProps = {
  token: string;
  serverUrl: string;
  roomName: string;
  onDisconnected?: () => void;
};

type AvatarCircleProps = {
  name: string;
  isMuted: boolean;
  isSpeaking: boolean;
  isLocal: boolean;
  handRaised: boolean;
};

function getInitials(name: string): string {
  return name
    .split(" ")
    .map((part) => part.charAt(0))
    .join("")
    .toUpperCase()
    .slice(0, 2);
}

function getAvatarColor(name: string): string {
  const colors = [
    "bg-red-500",
    "bg-orange-500",
    "bg-amber-500",
    "bg-emerald-500",
    "bg-cyan-500",
    "bg-blue-500",
    "bg-violet-500",
    "bg-pink-500",
  ];
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = name.charCodeAt(i) + ((hash << 5) - hash);
  }
  return colors[Math.abs(hash) % colors.length];
}

function AvatarCircle({
  name,
  isMuted,
  isSpeaking,
  isLocal,
  handRaised,
}: AvatarCircleProps) {
  const initials = getInitials(name);
  const colorClass = getAvatarColor(name);

  return (
    <div className="flex flex-col items-center gap-2">
      <SpeakingIndicator isSpeaking={isSpeaking} size={80}>
        <div
          className={`flex h-full w-full items-center justify-center text-xl font-bold text-white ${colorClass}`}
        >
          {initials}
        </div>
      </SpeakingIndicator>

      <div className="flex items-center gap-1">
        <span className="max-w-[100px] truncate text-sm font-medium">
          {name}
          {isLocal && (
            <span className="text-muted-foreground"> (you)</span>
          )}
        </span>
      </div>

      <div className="flex items-center gap-1">
        {isMuted && (
          <Badge variant="secondary" className="text-xs px-1.5 py-0">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="12"
              height="12"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="mr-0.5"
            >
              <line x1="1" y1="1" x2="23" y2="23" />
              <path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6" />
              <path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2c0 .76-.13 1.49-.36 2.18" />
            </svg>
            Muted
          </Badge>
        )}
        {handRaised && (
          <Badge variant="default" className="text-xs px-1.5 py-0 animate-bounce">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="12"
              height="12"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="mr-0.5"
            >
              <path d="M18 11V6a2 2 0 0 0-4 0v1" />
              <path d="M14 10V4a2 2 0 0 0-4 0v2" />
              <path d="M10 10.5V6a2 2 0 0 0-4 0v8" />
              <path d="M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15" />
            </svg>
            Hand
          </Badge>
        )}
      </div>
    </div>
  );
}

export function AudioRoom({
  token,
  serverUrl,
  roomName,
  onDisconnected,
}: AudioRoomProps) {
  const participantKeyPrefix = useId();

  const {
    participants,
    isConnected,
    isConnecting,
    isMuted,
    isDeafened,
    handRaised,
    raiseHandQueue,
    toggleMute,
    toggleDeafen,
    toggleRaiseHand,
    disconnect,
  } = useAudioRoom({ token, serverUrl, onDisconnected });

  if (isConnecting) {
    return (
      <div className="flex h-96 items-center justify-center">
        <div className="flex flex-col items-center gap-3">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-muted border-t-primary" />
          <p className="text-sm text-muted-foreground">
            Joining audio room...
          </p>
        </div>
      </div>
    );
  }

  if (!isConnected) {
    return (
      <div className="flex h-96 items-center justify-center">
        <p className="text-muted-foreground">Disconnected from room.</p>
      </div>
    );
  }

  const raisedIdentities = new Set(
    raiseHandQueue.map((entry) => entry.identity)
  );

  return (
    <div className="flex flex-col items-center gap-6">
      {/* Room Header */}
      <Card className="w-full max-w-2xl">
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <CardTitle className="text-lg">{roomName}</CardTitle>
            <div className="flex items-center gap-2">
              <Badge variant="outline" className="gap-1">
                <span className="h-2 w-2 rounded-full bg-green-500 animate-pulse" />
                {participants.length}{" "}
                {participants.length === 1 ? "listener" : "listeners"}
              </Badge>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          {/* Circular Avatar Grid */}
          <div className="flex flex-wrap justify-center gap-6 py-4">
            {participants.map((participant) => (
              <AvatarCircle
                key={`${participantKeyPrefix}-${participant.identity}`}
                name={participant.name}
                isMuted={participant.isMuted}
                isSpeaking={participant.isSpeaking}
                isLocal={participant.isLocal}
                handRaised={raisedIdentities.has(participant.identity)}
              />
            ))}
          </div>

          {/* Raise Hand Queue */}
          {raiseHandQueue.length > 0 && (
            <div className="mt-4 rounded-lg border bg-muted/50 p-3">
              <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Raised Hands
              </p>
              <div className="flex flex-wrap gap-2">
                {raiseHandQueue.map((entry) => (
                  <Badge
                    key={`${participantKeyPrefix}-hand-${entry.identity}`}
                    variant="secondary"
                    className="gap-1"
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      width="12"
                      height="12"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    >
                      <path d="M18 11V6a2 2 0 0 0-4 0v1" />
                      <path d="M14 10V4a2 2 0 0 0-4 0v2" />
                      <path d="M10 10.5V6a2 2 0 0 0-4 0v8" />
                      <path d="M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15" />
                    </svg>
                    {entry.name}
                  </Badge>
                ))}
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Controls Bar — fixed at bottom */}
      <div className="fixed bottom-6 left-1/2 z-50 -translate-x-1/2">
        <AudioControls
          isMuted={isMuted}
          isDeafened={isDeafened}
          handRaised={handRaised}
          raiseHandCount={raiseHandQueue.length}
          onToggleMute={() => void toggleMute()}
          onToggleDeafen={toggleDeafen}
          onToggleRaiseHand={toggleRaiseHand}
          onLeave={disconnect}
        />
      </div>
    </div>
  );
}
```

## Usage

### Basic audio room page

```tsx
import { AudioRoom } from "@/components/video/audio-room";

export default async function AudioRoomPage({
  params,
}: {
  params: Promise<{ roomId: string }>;
}) {
  const { roomId } = await params;

  // Fetch token from your LiveKit token endpoint (provided by video-room skill)
  const tokenRes = await fetch(
    `${process.env.NEXT_PUBLIC_APP_URL}/api/video/token?room=${roomId}&identity=user-123`,
    { cache: "no-store" }
  );
  const { token } = (await tokenRes.json()) as { token: string };

  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-6 pb-24">
      <AudioRoom
        token={token}
        serverUrl={process.env.NEXT_PUBLIC_LIVEKIT_URL ?? ""}
        roomName={`Audio Room: ${roomId}`}
      />
    </main>
  );
}
```

### Client-side connection with join button

```tsx
"use client";

import { useState, useCallback } from "react";
import { AudioRoom } from "@/components/video/audio-room";
import { Button } from "@/components/ui/button";

export function AudioRoomLobby({ roomId }: { roomId: string }) {
  const [token, setToken] = useState<string | null>(null);
  const [isJoining, setIsJoining] = useState(false);

  const handleJoin = useCallback(async () => {
    setIsJoining(true);
    try {
      const res = await fetch(`/api/video/token?room=${roomId}`);
      const data = (await res.json()) as { token: string };
      setToken(data.token);
    } catch (err) {
      console.error("Failed to get token:", err);
    } finally {
      setIsJoining(false);
    }
  }, [roomId]);

  if (!token) {
    return (
      <div className="flex flex-col items-center gap-4">
        <h2 className="text-xl font-semibold">Join Audio Room</h2>
        <Button onClick={handleJoin} disabled={isJoining} size="lg">
          {isJoining ? (
            <span className="flex items-center gap-2">
              <span className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
              Connecting...
            </span>
          ) : (
            "Join Room"
          )}
        </Button>
      </div>
    );
  }

  return (
    <AudioRoom
      token={token}
      serverUrl={process.env.NEXT_PUBLIC_LIVEKIT_URL ?? ""}
      roomName={`Room: ${roomId}`}
      onDisconnected={() => setToken(null)}
    />
  );
}
```

## Acceptance Criteria

- [ ] Audio room connects to LiveKit with audio-only (no video published)
- [ ] Participants appear as circular avatars in a grid layout
- [ ] Speaking indicator (pulsing ring) activates when a participant is speaking
- [ ] Mute/unmute toggles local microphone
- [ ] Deafen stops playback of all remote audio tracks
- [ ] Raise hand sends data message to all participants and appears in queue
- [ ] Lower hand removes participant from the raise hand queue
- [ ] Leave button disconnects from the room
- [ ] Participant join/leave updates the avatar grid in real-time
- [ ] `useId` used for generating keys in participant lists
- [ ] No `any` casts anywhere
- [ ] `tsc` passes with no errors
- [ ] Build succeeds

## Troubleshooting

### "Permission denied" for microphone

**Symptoms**: Room connects but no audio is published.

**Cause**: Browser microphone permission not granted.

**Fix**: Check browser permissions. The `setMicrophoneEnabled(true)` call will prompt the user. Ensure the page is served over HTTPS (or localhost).

### Participants not showing speaking indicators

**Symptoms**: Audio works but no pulsing rings appear.

**Cause**: The `ActiveSpeakersChanged` event might not be firing.

**Fix**: Ensure the LiveKit server has audio level observation enabled (it is by default on LiveKit Cloud). The speaking detection threshold is managed server-side.

### Raise hand not visible to other participants

**Symptoms**: Local user sees their hand raised but others don't.

**Cause**: `publishData` requires `reliable: true` for guaranteed delivery.

**Fix**: Verify the `publishData` call uses `{ reliable: true }`. Check that the `DataReceived` event handler is correctly parsing the payload.

### Echo or feedback loops

**Symptoms**: Users hear themselves or excessive echo.

**Cause**: Echo cancellation not enabled in audio capture options.

**Fix**: The hook enables `echoCancellation`, `noiseSuppression`, and `autoGainControl` by default. Ensure participants use headphones or that the browser supports AEC.
