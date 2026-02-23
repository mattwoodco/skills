---
name: screen-share
description: Screen sharing components for LiveKit video rooms — toggle button, full-width screen share view with PiP camera overlay, and an auto-switching presenter layout. Use this skill when the user says "add screen share", "setup screen sharing", "presenter mode", "screen share view", or "setup screen-share".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [video-room, video-ui]
---

# Screen Share

Screen sharing components that extend the `video-room` and `video-ui` skills with a dedicated toggle button, a full-width screen share view with picture-in-picture camera overlay, and an auto-switching presenter layout that detects when someone is sharing their screen and swaps between grid mode and presenter mode.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `video-room` skill installed (LiveKit client, server SDK, types)
- `video-ui` skill installed (VideoRoomProvider, ParticipantGrid, ControlsBar, ParticipantTile)
- No additional packages needed — uses `livekit-client` and `@livekit/components-react` already installed by `video-room` and `video-ui`

## Installation

No additional packages required. All dependencies are already installed by the `video-room` and `video-ui` skills:

```bash
# Already installed:
# livekit-client
# @livekit/components-react
# @livekit/components-styles
```

## What Gets Created

```
src/
├── components/
│   └── video/
│       ├── screen-share-button.tsx     # Toggle button using localParticipant.setScreenShareEnabled
│       ├── screen-share-view.tsx       # Full-width screen share track + PiP camera overlay
│       └── presenter-layout.tsx        # Auto-switches between grid and presenter mode
└── lib/
    └── video/
        └── use-screen-share.ts         # Hook: isScreenSharing, screenShareTrack, toggleScreenShare, screenShareParticipant
```

## Setup Steps

### Step 1: Create `src/lib/video/use-screen-share.ts`

```typescript
"use client";

import { useState, useCallback, useMemo } from "react";
import {
  useTracks,
  useLocalParticipant,
} from "@livekit/components-react";
import { Track, type RemoteTrackPublication, type LocalTrackPublication } from "livekit-client";
import type { TrackReferenceOrPlaceholder } from "@livekit/components-react";

type ScreenShareParticipantInfo = {
  sid: string;
  identity: string;
  name: string;
  isLocal: boolean;
};

type UseScreenShareReturn = {
  /** Whether anyone in the room is currently sharing their screen */
  isScreenSharing: boolean;
  /** Whether the local participant is the one sharing */
  isLocalScreenSharing: boolean;
  /** The screen share track reference, or null if no one is sharing */
  screenShareTrack: TrackReferenceOrPlaceholder | null;
  /** Information about the participant who is sharing, or null */
  screenShareParticipant: ScreenShareParticipantInfo | null;
  /** Toggle screen sharing for the local participant */
  toggleScreenShare: () => Promise<void>;
  /** All screen share tracks (in case multiple participants share simultaneously) */
  allScreenShareTracks: TrackReferenceOrPlaceholder[];
};

export function useScreenShare(): UseScreenShareReturn {
  const { localParticipant } = useLocalParticipant();
  const [isToggling, setIsToggling] = useState(false);

  const screenShareTracks = useTracks(
    [{ source: Track.Source.ScreenShare, withPlaceholder: false }],
    { onlySubscribed: false }
  );

  const primaryScreenShare = screenShareTracks.length > 0 ? screenShareTracks[0] : null;

  const isScreenSharing = screenShareTracks.length > 0;
  const isLocalScreenSharing = localParticipant.isScreenShareEnabled;

  const screenShareParticipant = useMemo((): ScreenShareParticipantInfo | null => {
    if (!primaryScreenShare) return null;

    const participant = primaryScreenShare.participant;
    return {
      sid: participant.sid,
      identity: participant.identity,
      name: participant.name ?? participant.identity,
      isLocal: participant.sid === localParticipant.sid,
    };
  }, [primaryScreenShare, localParticipant.sid]);

  const toggleScreenShare = useCallback(async () => {
    if (isToggling) return;
    setIsToggling(true);
    try {
      await localParticipant.setScreenShareEnabled(
        !localParticipant.isScreenShareEnabled
      );
    } finally {
      setIsToggling(false);
    }
  }, [localParticipant, isToggling]);

  return {
    isScreenSharing,
    isLocalScreenSharing,
    screenShareTrack: primaryScreenShare,
    screenShareParticipant,
    toggleScreenShare,
    allScreenShareTracks: screenShareTracks,
  };
}
```

### Step 2: Create `src/components/video/screen-share-button.tsx`

```tsx
"use client";

import { Button } from "@/components/ui/button";
import { useScreenShare } from "@/lib/video/use-screen-share";

type ScreenShareButtonProps = {
  className?: string;
  variant?: "default" | "secondary" | "destructive" | "outline" | "ghost" | "link";
  size?: "default" | "sm" | "lg" | "icon";
};

export function ScreenShareButton({
  className,
  variant,
  size = "sm",
}: ScreenShareButtonProps) {
  const { isLocalScreenSharing, toggleScreenShare } = useScreenShare();

  const resolvedVariant = variant ?? (isLocalScreenSharing ? "default" : "secondary");

  return (
    <Button
      variant={resolvedVariant}
      size={size}
      onClick={toggleScreenShare}
      className={className}
      title={isLocalScreenSharing ? "Stop sharing screen" : "Share your screen"}
    >
      <ScreenShareIcon className="mr-2 h-4 w-4" />
      {isLocalScreenSharing ? "Stop Sharing" : "Share Screen"}
    </Button>
  );
}

function ScreenShareIcon({ className }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
    >
      <path d="M13 3H4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-3" />
      <path d="M8 21h8" />
      <path d="M12 17v4" />
      <path d="m17 8 5-5" />
      <path d="M17 3h5v5" />
    </svg>
  );
}
```

### Step 3: Create `src/components/video/screen-share-view.tsx`

```tsx
"use client";

import { useRef, useEffect, useId } from "react";
import { useTracks, useLocalParticipant } from "@livekit/components-react";
import { Track } from "livekit-client";
import type { TrackReferenceOrPlaceholder } from "@livekit/components-react";
import { Card } from "@/components/ui/card";

type ScreenShareViewProps = {
  /** The screen share track to render. If omitted, auto-detects from room. */
  screenShareTrackRef?: TrackReferenceOrPlaceholder | null;
  /** Whether to show the PiP camera overlay */
  showPiP?: boolean;
  className?: string;
};

export function ScreenShareView({
  screenShareTrackRef,
  showPiP = true,
  className,
}: ScreenShareViewProps) {
  const pipId = useId();
  const screenVideoRef = useRef<HTMLVideoElement>(null);
  const pipVideoRef = useRef<HTMLVideoElement>(null);
  const { localParticipant } = useLocalParticipant();

  // Auto-detect screen share if not provided
  const screenShareTracks = useTracks(
    [{ source: Track.Source.ScreenShare, withPlaceholder: false }],
    { onlySubscribed: false }
  );

  const activeScreenShare = screenShareTrackRef ?? (screenShareTracks.length > 0 ? screenShareTracks[0] : null);

  // Get camera tracks for PiP overlay
  const cameraTracks = useTracks(
    [{ source: Track.Source.Camera, withPlaceholder: false }],
    { onlySubscribed: false }
  );

  // Find the screen share presenter's camera track for PiP
  const presenterCameraTrack = activeScreenShare
    ? cameraTracks.find(
        (t) => t.participant.sid === activeScreenShare.participant.sid
      )
    : null;

  // Attach screen share video
  useEffect(() => {
    const videoEl = screenVideoRef.current;
    const track = activeScreenShare?.publication?.track;
    if (!videoEl || !track) return;

    track.attach(videoEl);
    return () => {
      track.detach(videoEl);
    };
  }, [activeScreenShare]);

  // Attach PiP camera video
  useEffect(() => {
    const videoEl = pipVideoRef.current;
    const track = presenterCameraTrack?.publication?.track;
    if (!videoEl || !track) return;

    track.attach(videoEl);
    return () => {
      track.detach(videoEl);
    };
  }, [presenterCameraTrack]);

  if (!activeScreenShare) {
    return null;
  }

  const presenterName =
    activeScreenShare.participant.name ?? activeScreenShare.participant.identity;
  const isLocalShare =
    activeScreenShare.participant.sid === localParticipant.sid;

  return (
    <div className={`relative h-full w-full bg-black ${className ?? ""}`}>
      {/* Full-width screen share */}
      <video
        ref={screenVideoRef}
        autoPlay
        playsInline
        muted={isLocalShare}
        className="h-full w-full object-contain"
      />

      {/* Presenter label */}
      <div className="absolute top-3 left-3 rounded-md bg-black/60 px-3 py-1.5">
        <span className="text-sm font-medium text-white">
          {isLocalShare ? "You are sharing" : `${presenterName}'s screen`}
        </span>
      </div>

      {/* PiP camera overlay */}
      {showPiP && presenterCameraTrack && (
        <Card
          key={`${pipId}-pip`}
          className="absolute bottom-4 right-4 h-32 w-44 overflow-hidden shadow-lg"
        >
          <video
            ref={pipVideoRef}
            autoPlay
            playsInline
            muted
            className="h-full w-full object-cover"
          />
          <div className="absolute bottom-0 left-0 right-0 bg-black/50 px-2 py-1">
            <span className="text-xs text-white">{presenterName}</span>
          </div>
        </Card>
      )}
    </div>
  );
}
```

### Step 4: Create `src/components/video/presenter-layout.tsx`

```tsx
"use client";

import { useId } from "react";
import { useTracks } from "@livekit/components-react";
import { Track } from "livekit-client";
import { ScreenShareView } from "@/components/video/screen-share-view";
import { ParticipantGrid } from "@/components/video/participant-grid";
import { ParticipantTile } from "@/components/video/participant-tile";

type PresenterLayoutProps = {
  className?: string;
};

export function PresenterLayout({ className }: PresenterLayoutProps) {
  const sidebarId = useId();

  const screenShareTracks = useTracks(
    [{ source: Track.Source.ScreenShare, withPlaceholder: false }],
    { onlySubscribed: false }
  );

  const cameraTracks = useTracks(
    [{ source: Track.Source.Camera, withPlaceholder: true }],
    { onlySubscribed: false }
  );

  const hasScreenShare = screenShareTracks.length > 0;

  // No screen share: render standard participant grid
  if (!hasScreenShare) {
    return <ParticipantGrid className={className} />;
  }

  const primaryScreenShare = screenShareTracks[0];

  return (
    <div className={`flex h-full gap-2 p-2 ${className ?? ""}`}>
      {/* Main area: screen share */}
      <div className="flex-1 min-w-0">
        <ScreenShareView
          screenShareTrackRef={primaryScreenShare}
          showPiP={true}
          className="h-full rounded-lg overflow-hidden"
        />
      </div>

      {/* Sidebar: camera feeds */}
      <div className="flex w-48 shrink-0 flex-col gap-2 overflow-y-auto">
        {cameraTracks.map((trackRef) => (
          <ParticipantTile
            key={`${sidebarId}-${trackRef.participant.sid}-${trackRef.source}`}
            trackRef={trackRef}
            className="aspect-video w-full shrink-0"
          />
        ))}
      </div>
    </div>
  );
}
```

## Usage

### Presenter Layout (Auto-Switching)

The `PresenterLayout` component automatically detects screen shares and switches between grid and presenter mode:

```tsx
// src/app/video/[roomName]/page.tsx
"use client";

import { useState, use } from "react";
import { VideoRoomProvider } from "@/components/video/video-room-provider";
import { PresenterLayout } from "@/components/video/presenter-layout";
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
          <PresenterLayout className="h-full" />
        </div>
        <ControlsBar onLeave={() => setJoined(false)} />
      </VideoRoomProvider>
    </div>
  );
}
```

### Standalone Screen Share Button

Replace or supplement the screen share button in `ControlsBar`:

```tsx
"use client";

import { ScreenShareButton } from "@/components/video/screen-share-button";

function CustomControls() {
  return (
    <div className="flex gap-2 p-4">
      <ScreenShareButton size="lg" />
    </div>
  );
}
```

### Screen Share View with Custom PiP

```tsx
"use client";

import { ScreenShareView } from "@/components/video/screen-share-view";
import { useScreenShare } from "@/lib/video/use-screen-share";

function FullScreenPresentation() {
  const { isScreenSharing, screenShareTrack } = useScreenShare();

  if (!isScreenSharing) {
    return <p className="text-muted-foreground">No one is sharing their screen.</p>;
  }

  return (
    <div className="h-screen w-screen">
      <ScreenShareView
        screenShareTrackRef={screenShareTrack}
        showPiP={true}
      />
    </div>
  );
}
```

### Using the `useScreenShare` Hook Directly

```tsx
"use client";

import { useScreenShare } from "@/lib/video/use-screen-share";

function ScreenShareStatus() {
  const {
    isScreenSharing,
    isLocalScreenSharing,
    screenShareParticipant,
    toggleScreenShare,
    allScreenShareTracks,
  } = useScreenShare();

  return (
    <div className="space-y-2">
      <p>Screen sharing: {isScreenSharing ? "Yes" : "No"}</p>
      {screenShareParticipant && (
        <p>
          Shared by: {screenShareParticipant.name}
          {screenShareParticipant.isLocal ? " (you)" : ""}
        </p>
      )}
      <p>Total screen shares: {allScreenShareTracks.length}</p>
      <button onClick={toggleScreenShare}>
        {isLocalScreenSharing ? "Stop Sharing" : "Start Sharing"}
      </button>
    </div>
  );
}
```

## Component Reference

| Component | Purpose | Key Props |
|-----------|---------|-----------|
| `ScreenShareButton` | Toggle button for local screen share | `className`, `variant`, `size` |
| `ScreenShareView` | Full-width screen share with PiP camera overlay | `screenShareTrackRef`, `showPiP`, `className` |
| `PresenterLayout` | Auto-switches between grid and presenter mode | `className` |

## Hook Reference

### `useScreenShare()`

| Return Value | Type | Description |
|--------------|------|-------------|
| `isScreenSharing` | `boolean` | Whether anyone is screen sharing |
| `isLocalScreenSharing` | `boolean` | Whether the local participant is sharing |
| `screenShareTrack` | `TrackReferenceOrPlaceholder \| null` | The primary screen share track |
| `screenShareParticipant` | `ScreenShareParticipantInfo \| null` | Info about who is sharing |
| `toggleScreenShare` | `() => Promise<void>` | Toggle local screen sharing |
| `allScreenShareTracks` | `TrackReferenceOrPlaceholder[]` | All active screen share tracks |

## Acceptance Criteria

- [ ] `ScreenShareButton` toggles screen sharing on/off for the local participant
- [ ] `ScreenShareButton` shows "Stop Sharing" when actively sharing
- [ ] `ScreenShareView` renders the screen share track full-width
- [ ] `ScreenShareView` shows the presenter's camera as a PiP overlay in the bottom-right
- [ ] `ScreenShareView` labels the share with the presenter's name
- [ ] `ScreenShareView` shows "You are sharing" when the local user is the presenter
- [ ] `PresenterLayout` renders `ParticipantGrid` when no one is screen sharing
- [ ] `PresenterLayout` switches to presenter mode (screen share + sidebar) when someone shares
- [ ] `PresenterLayout` sidebar shows all camera feeds
- [ ] `useScreenShare` correctly reports `isScreenSharing` and `screenShareParticipant`
- [ ] `useScreenShare.toggleScreenShare` toggles the local screen share
- [ ] All components use shadcn/ui Button, Card where appropriate
- [ ] No usage of `any` type anywhere in the code
- [ ] All components with hooks use `"use client"` directive
- [ ] `useId` is used for generating keys in lists
- [ ] `tsc` passes with no errors
- [ ] `bun run build` succeeds

## Troubleshooting

### Screen share prompt does not appear

**Symptoms**: Clicking the share button does nothing.

**Cause**: The browser may block the `getDisplayMedia` call if it is not triggered by a user gesture, or permissions may be denied.

**Fix**:

1. Ensure the screen share toggle is called directly from a click handler (not from an async chain without user gesture)
2. Check browser permissions in system settings (macOS: System Settings > Privacy & Security > Screen Recording)
3. On macOS, the browser must have screen recording permission

### PiP overlay not showing

**Symptoms**: The screen share renders but the camera PiP is missing.

**Cause**: The presenter's camera may be off, or the camera track is not published.

**Fix**: The PiP overlay only appears when the screen share presenter also has an active camera track. If the presenter turns off their camera, the PiP will not render.

### Multiple simultaneous screen shares

**Symptoms**: Only one screen share is visible even though multiple participants are sharing.

**Cause**: `PresenterLayout` and `ScreenShareView` show only the primary (first) screen share by default.

**Fix**: Use the `allScreenShareTracks` array from `useScreenShare()` to render multiple screen shares if needed. Build a custom layout that iterates over all tracks.

### Layout flickers when screen share starts/stops

**Symptoms**: The layout briefly shows an empty state when transitioning between grid and presenter mode.

**Cause**: Track events may fire slightly before or after the component re-renders.

**Fix**: This is typically a single-frame flicker and resolves automatically. If it is persistent, wrap the `PresenterLayout` in a `React.Suspense` boundary or add a CSS transition on the container.

### Screen share video is black

**Symptoms**: The screen share element renders but shows a black rectangle.

**Cause**: The track may not be attached to the video element, or the track source is paused.

**Fix**:

1. Verify the track is being attached in the `useEffect` (check console for errors)
2. Ensure the screen share source window/tab is not minimized
3. Some browsers pause screen share tracks when the shared tab is not visible
