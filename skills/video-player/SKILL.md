---
name: video-player
description: MUX Player React components — responsive video player, chapter navigation, captions toggle, thumbnail hover previews, and video cards. Use this skill when the user says "add video player", "setup mux player", "video components", "add player", or "video-player".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [stream-mux, add-shadcn]
---

# Video Player

MUX Player React components with shadcn/ui styling. Includes a responsive player wrapper, chapter navigation sidebar, caption controls, thumbnail hover previews, and video list cards. All components are designed for the App Router with "use client" directives where hooks are used.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `stream-mux` skill applied (MUX backend infrastructure)
- `add-shadcn` skill applied (design system with Tailwind v4)
- shadcn/ui components: `card`, `button`, `badge`, `scroll-area`, `dropdown-menu`, `toggle`

## Installation

```bash
bun add @mux/mux-player-react
bunx shadcn@latest add card button badge scroll-area dropdown-menu toggle
```

## What Gets Created

```
src/
└── components/
    └── video/
        ├── mux-player.tsx             # MUX Player React wrapper
        ├── video-chapters.tsx         # Chapter navigation sidebar
        ├── video-captions-toggle.tsx  # Caption on/off + language selector
        ├── video-thumbnail-hover.tsx  # Thumbnail preview strip on hover
        └── video-card.tsx             # Video card for lists
```

## Setup Steps

### Step 1: Create `src/components/video/mux-player.tsx`

```tsx
"use client";

import { useRef, useCallback } from "react";
import MuxPlayerElement from "@mux/mux-player-react";
import type { MuxPlayerRefAttributes } from "@mux/mux-player-react";
import { cn } from "@src/lib/utils";

type MuxPlayerProps = {
  playbackId: string;
  title?: string;
  autoPlay?: boolean;
  muted?: boolean;
  accentColor?: string;
  thumbnailTime?: number;
  signedToken?: string;
  startTime?: number;
  className?: string;
  onTimeUpdate?: (currentTime: number) => void;
  onEnded?: () => void;
  onError?: (error: Error) => void;
};

type MuxPlayerRef = {
  seekTo: (time: number) => void;
  play: () => void;
  pause: () => void;
  getCurrentTime: () => number;
};

function MuxPlayer({
  playbackId,
  title,
  autoPlay = false,
  muted = false,
  accentColor,
  thumbnailTime,
  signedToken,
  startTime,
  className,
  onTimeUpdate,
  onEnded,
  onError,
}: MuxPlayerProps) {
  const playerRef = useRef<MuxPlayerRefAttributes>(null);

  const handleTimeUpdate = useCallback(() => {
    if (onTimeUpdate && playerRef.current) {
      onTimeUpdate(playerRef.current.currentTime);
    }
  }, [onTimeUpdate]);

  const handleError = useCallback(
    (event: Event) => {
      if (onError) {
        const message =
          event instanceof ErrorEvent
            ? event.message
            : "Video playback error";
        onError(new Error(message));
      }
    },
    [onError]
  );

  return (
    <div
      className={cn(
        "relative w-full overflow-hidden rounded-lg bg-black",
        "aspect-video",
        className
      )}
    >
      <MuxPlayerElement
        ref={playerRef}
        playbackId={playbackId}
        metadata={{
          video_title: title ?? "",
        }}
        autoPlay={autoPlay ? "muted" : undefined}
        muted={muted}
        accentColor={accentColor}
        thumbnailTime={thumbnailTime}
        tokens={signedToken ? { playback: signedToken } : undefined}
        startTime={startTime}
        streamType="on-demand"
        onTimeUpdate={handleTimeUpdate}
        onEnded={onEnded}
        onError={handleError}
        style={{
          width: "100%",
          height: "100%",
          "--media-object-fit": "contain",
        }}
      />
    </div>
  );
}

export { MuxPlayer };
export type { MuxPlayerProps, MuxPlayerRef };
```

### Step 2: Create `src/components/video/video-chapters.tsx`

```tsx
"use client";

import { useState, useId } from "react";
import { cn } from "@src/lib/utils";
import { ScrollArea } from "@/components/ui/scroll-area";

type Chapter = {
  title: string;
  startTime: number;
};

type VideoChaptersProps = {
  chapters: Chapter[];
  currentTime?: number;
  onChapterClick: (startTime: number) => void;
  className?: string;
};

function formatTimestamp(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

function getCurrentChapterIndex(
  chapters: Chapter[],
  currentTime: number
): number {
  let activeIndex = 0;
  for (let i = 0; i < chapters.length; i++) {
    if (currentTime >= chapters[i].startTime) {
      activeIndex = i;
    }
  }
  return activeIndex;
}

function VideoChapters({
  chapters,
  currentTime = 0,
  onChapterClick,
  className,
}: VideoChaptersProps) {
  const listId = useId();
  const activeIndex = getCurrentChapterIndex(chapters, currentTime);

  return (
    <ScrollArea
      className={cn(
        "w-full rounded-lg border bg-card",
        className
      )}
    >
      <div className="p-2">
        <h3 className="mb-2 px-2 text-sm font-semibold text-muted-foreground">
          Chapters
        </h3>
        <ul className="space-y-0.5">
          {chapters.map((chapter, index) => (
            <li key={`${listId}-${chapter.startTime}`}>
              <button
                type="button"
                onClick={() => onChapterClick(chapter.startTime)}
                className={cn(
                  "flex w-full items-center gap-3 rounded-md px-2 py-2 text-left text-sm transition-colors",
                  "hover:bg-accent hover:text-accent-foreground",
                  index === activeIndex &&
                    "bg-accent text-accent-foreground font-medium"
                )}
              >
                <span className="shrink-0 font-mono text-xs text-muted-foreground">
                  {formatTimestamp(chapter.startTime)}
                </span>
                <span className="truncate">{chapter.title}</span>
              </button>
            </li>
          ))}
        </ul>
      </div>
    </ScrollArea>
  );
}

export { VideoChapters };
export type { VideoChaptersProps, Chapter };
```

### Step 3: Create `src/components/video/video-captions-toggle.tsx`

```tsx
"use client";

import { useCallback, useId } from "react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@src/lib/utils";

type CaptionTrack = {
  language: string;
  label: string;
};

type VideoCaptionsToggleProps = {
  tracks: CaptionTrack[];
  activeTrack: string | null;
  onToggle: (enabled: boolean) => void;
  onSelectTrack: (language: string) => void;
  className?: string;
};

function CaptionsIcon({ enabled }: { enabled: boolean }) {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={cn(enabled ? "text-foreground" : "text-muted-foreground")}
    >
      <rect x="2" y="4" width="20" height="16" rx="2" />
      <path d="M7 12h4" />
      <path d="M13 12h4" />
      <path d="M7 16h10" />
    </svg>
  );
}

function VideoCaptionsToggle({
  tracks,
  activeTrack,
  onToggle,
  onSelectTrack,
  className,
}: VideoCaptionsToggleProps) {
  const menuId = useId();
  const isEnabled = activeTrack !== null;

  const handleToggle = useCallback(() => {
    onToggle(!isEnabled);
  }, [isEnabled, onToggle]);

  if (tracks.length === 0) {
    return null;
  }

  if (tracks.length === 1) {
    return (
      <Button
        variant={isEnabled ? "default" : "outline"}
        size="sm"
        onClick={handleToggle}
        className={cn("gap-2", className)}
        aria-label={isEnabled ? "Disable captions" : "Enable captions"}
      >
        <CaptionsIcon enabled={isEnabled} />
        <span className="text-xs">CC</span>
      </Button>
    );
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant={isEnabled ? "default" : "outline"}
          size="sm"
          className={cn("gap-2", className)}
          aria-label="Caption settings"
        >
          <CaptionsIcon enabled={isEnabled} />
          <span className="text-xs">CC</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem
          onClick={() => onToggle(false)}
          className={cn(!isEnabled && "font-medium")}
        >
          Off
        </DropdownMenuItem>
        {tracks.map((track) => (
          <DropdownMenuItem
            key={`${menuId}-${track.language}`}
            onClick={() => onSelectTrack(track.language)}
            className={cn(
              activeTrack === track.language && "font-medium"
            )}
          >
            {track.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

export { VideoCaptionsToggle };
export type { VideoCaptionsToggleProps, CaptionTrack };
```

### Step 4: Create `src/components/video/video-thumbnail-hover.tsx`

```tsx
"use client";

import { useState, useCallback, useRef, useMemo } from "react";
import { cn } from "@src/lib/utils";

type VideoThumbnailHoverProps = {
  playbackId: string;
  duration: number;
  thumbnailCount?: number;
  onSeek?: (time: number) => void;
  className?: string;
};

function formatTimestamp(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

function VideoThumbnailHover({
  playbackId,
  duration,
  thumbnailCount = 10,
  onSeek,
  className,
}: VideoThumbnailHoverProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [hoverPosition, setHoverPosition] = useState<number | null>(null);
  const [hoverTime, setHoverTime] = useState(0);

  const thumbnailUrl = useMemo(() => {
    if (hoverPosition === null) return null;
    const time = Math.floor(hoverPosition * duration);
    return `https://image.mux.com/${playbackId}/thumbnail.jpg?time=${time}&width=160&height=90`;
  }, [playbackId, duration, hoverPosition]);

  const handleMouseMove = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      if (!containerRef.current) return;
      const rect = containerRef.current.getBoundingClientRect();
      const position = (e.clientX - rect.left) / rect.width;
      const clampedPosition = Math.max(0, Math.min(1, position));
      setHoverPosition(clampedPosition);
      setHoverTime(clampedPosition * duration);
    },
    [duration]
  );

  const handleMouseLeave = useCallback(() => {
    setHoverPosition(null);
  }, []);

  const handleClick = useCallback(() => {
    if (onSeek && hoverPosition !== null) {
      onSeek(hoverPosition * duration);
    }
  }, [onSeek, hoverPosition, duration]);

  return (
    <div
      ref={containerRef}
      className={cn(
        "group relative h-8 w-full cursor-pointer rounded bg-muted",
        className
      )}
      onMouseMove={handleMouseMove}
      onMouseLeave={handleMouseLeave}
      onClick={handleClick}
      role="slider"
      aria-label="Video timeline"
      aria-valuemin={0}
      aria-valuemax={duration}
      aria-valuenow={hoverTime}
      tabIndex={0}
    >
      {/* Progress track */}
      <div className="absolute inset-0 rounded bg-muted" />

      {/* Hover indicator */}
      {hoverPosition !== null && (
        <>
          {/* Vertical line */}
          <div
            className="absolute top-0 h-full w-0.5 bg-foreground/50"
            style={{ left: `${hoverPosition * 100}%` }}
          />

          {/* Thumbnail preview */}
          <div
            className="absolute bottom-full mb-2 -translate-x-1/2"
            style={{
              left: `${Math.max(10, Math.min(90, hoverPosition * 100))}%`,
            }}
          >
            <div className="overflow-hidden rounded-md border bg-background shadow-lg">
              {thumbnailUrl && (
                <img
                  src={thumbnailUrl}
                  alt={`Preview at ${formatTimestamp(hoverTime)}`}
                  width={160}
                  height={90}
                  className="block"
                  loading="eager"
                />
              )}
              <div className="px-2 py-1 text-center text-xs font-mono text-muted-foreground">
                {formatTimestamp(hoverTime)}
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

export { VideoThumbnailHover };
export type { VideoThumbnailHoverProps };
```

### Step 5: Create `src/components/video/video-card.tsx`

```tsx
"use client";

import { useState, useCallback, useId } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { cn } from "@src/lib/utils";

type VideoCardProps = {
  playbackId: string;
  title: string;
  duration: number | null;
  thumbnailTime?: number;
  status?: "preparing" | "ready" | "errored" | "deleted";
  onClick?: () => void;
  onPlay?: () => void;
  className?: string;
};

function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);

  if (hours > 0) {
    return `${hours}:${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
  }
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

function PlayIcon() {
  return (
    <svg
      width="48"
      height="48"
      viewBox="0 0 48 48"
      fill="currentColor"
      className="drop-shadow-lg"
    >
      <circle cx="24" cy="24" r="24" fillOpacity="0.7" />
      <polygon points="18,14 36,24 18,34" fill="white" />
    </svg>
  );
}

function VideoCard({
  playbackId,
  title,
  duration,
  thumbnailTime = 0,
  status = "ready",
  onClick,
  onPlay,
  className,
}: VideoCardProps) {
  const cardId = useId();
  const [imageError, setImageError] = useState(false);

  const thumbnailUrl = playbackId
    ? `https://image.mux.com/${playbackId}/thumbnail.jpg?width=640&height=360&time=${thumbnailTime}`
    : null;

  const handleClick = useCallback(() => {
    if (onClick) {
      onClick();
    }
  }, [onClick]);

  const handlePlayClick = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      if (onPlay) {
        onPlay();
      } else if (onClick) {
        onClick();
      }
    },
    [onPlay, onClick]
  );

  const handleImageError = useCallback(() => {
    setImageError(true);
  }, []);

  const isPlayable = status === "ready" && playbackId;

  return (
    <Card
      className={cn(
        "group cursor-pointer overflow-hidden transition-shadow hover:shadow-md",
        !isPlayable && "opacity-60",
        className
      )}
      onClick={handleClick}
      role="button"
      tabIndex={0}
      aria-label={`${title}${duration ? ` - ${formatDuration(duration)}` : ""}`}
    >
      {/* Thumbnail */}
      <div className="relative aspect-video w-full overflow-hidden bg-muted">
        {thumbnailUrl && !imageError ? (
          <img
            src={thumbnailUrl}
            alt={title}
            className="h-full w-full object-cover transition-transform group-hover:scale-105"
            loading="lazy"
            onError={handleImageError}
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center bg-muted">
            <svg
              width="48"
              height="48"
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

        {/* Play button overlay */}
        {isPlayable && (
          <button
            type="button"
            className="absolute inset-0 flex items-center justify-center text-white opacity-0 transition-opacity group-hover:opacity-100"
            onClick={handlePlayClick}
            aria-label={`Play ${title}`}
          >
            <PlayIcon />
          </button>
        )}

        {/* Duration badge */}
        {duration !== null && duration > 0 && (
          <Badge
            variant="secondary"
            className="absolute bottom-2 right-2 bg-black/70 text-white font-mono text-xs"
          >
            {formatDuration(duration)}
          </Badge>
        )}

        {/* Status badge for non-ready assets */}
        {status !== "ready" && (
          <Badge
            variant={status === "errored" ? "destructive" : "secondary"}
            className="absolute top-2 left-2"
          >
            {status === "preparing" ? "Processing..." : status}
          </Badge>
        )}
      </div>

      {/* Title */}
      <CardContent className="p-3">
        <h3 className="text-sm font-medium leading-tight line-clamp-2">
          {title}
        </h3>
      </CardContent>
    </Card>
  );
}

export { VideoCard };
export type { VideoCardProps };
```

## Usage

### Basic Player

```tsx
"use client";

import { MuxPlayer } from "@/components/video/mux-player";

function VideoPage() {
  return (
    <MuxPlayer
      playbackId="DS00Spx1CV902MCtPj5WknGlR102V5HFkDe"
      title="My Video"
      accentColor="#10b981"
    />
  );
}
```

### Player with Chapters

```tsx
"use client";

import { useState, useCallback, useRef } from "react";
import { MuxPlayer } from "@/components/video/mux-player";
import { VideoChapters } from "@/components/video/video-chapters";
import type { Chapter } from "@/components/video/video-chapters";

const chapters: Chapter[] = [
  { title: "Introduction", startTime: 0 },
  { title: "Getting Started", startTime: 60 },
  { title: "Advanced Topics", startTime: 300 },
  { title: "Conclusion", startTime: 600 },
];

function VideoWithChapters() {
  const [currentTime, setCurrentTime] = useState(0);

  const handleChapterClick = useCallback((startTime: number) => {
    // In production, wire this to the player's seekTo method
    console.log("Seek to:", startTime);
  }, []);

  return (
    <div className="flex gap-4">
      <div className="flex-1">
        <MuxPlayer
          playbackId="DS00Spx1CV902MCtPj5WknGlR102V5HFkDe"
          title="Tutorial"
          onTimeUpdate={setCurrentTime}
        />
      </div>
      <VideoChapters
        chapters={chapters}
        currentTime={currentTime}
        onChapterClick={handleChapterClick}
        className="w-64 h-[400px]"
      />
    </div>
  );
}
```

### Video Card Grid

```tsx
"use client";

import { useId } from "react";
import { VideoCard } from "@/components/video/video-card";

type Video = {
  id: string;
  playbackId: string;
  title: string;
  duration: number | null;
  status: "preparing" | "ready" | "errored" | "deleted";
};

function VideoGrid({ videos }: { videos: Video[] }) {
  const gridId = useId();

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {videos.map((video) => (
        <VideoCard
          key={`${gridId}-${video.id}`}
          playbackId={video.playbackId}
          title={video.title}
          duration={video.duration}
          status={video.status}
          onClick={() => console.log("Navigate to:", video.id)}
          onPlay={() => console.log("Play:", video.id)}
        />
      ))}
    </div>
  );
}
```

### Captions Toggle

```tsx
"use client";

import { useState, useCallback } from "react";
import { MuxPlayer } from "@/components/video/mux-player";
import { VideoCaptionsToggle } from "@/components/video/video-captions-toggle";
import type { CaptionTrack } from "@/components/video/video-captions-toggle";

const captionTracks: CaptionTrack[] = [
  { language: "en", label: "English" },
  { language: "es", label: "Spanish" },
];

function VideoWithCaptions() {
  const [activeTrack, setActiveTrack] = useState<string | null>(null);

  const handleToggle = useCallback((enabled: boolean) => {
    setActiveTrack(enabled ? "en" : null);
  }, []);

  const handleSelectTrack = useCallback((language: string) => {
    setActiveTrack(language);
  }, []);

  return (
    <div className="space-y-2">
      <MuxPlayer
        playbackId="DS00Spx1CV902MCtPj5WknGlR102V5HFkDe"
        title="Captioned Video"
      />
      <div className="flex justify-end">
        <VideoCaptionsToggle
          tracks={captionTracks}
          activeTrack={activeTrack}
          onToggle={handleToggle}
          onSelectTrack={handleSelectTrack}
        />
      </div>
    </div>
  );
}
```

### Thumbnail Hover Preview

```tsx
"use client";

import { useCallback } from "react";
import { VideoThumbnailHover } from "@/components/video/video-thumbnail-hover";

function TimelinePreview() {
  const handleSeek = useCallback((time: number) => {
    console.log("Seek to:", time);
  }, []);

  return (
    <VideoThumbnailHover
      playbackId="DS00Spx1CV902MCtPj5WknGlR102V5HFkDe"
      duration={600}
      onSeek={handleSeek}
    />
  );
}
```

## Acceptance Criteria

- [ ] `bun add @mux/mux-player-react` installs without errors
- [ ] `MuxPlayer` renders a responsive video player with the correct playback ID
- [ ] `MuxPlayer` supports `autoPlay`, `muted`, `accentColor`, `thumbnailTime` props
- [ ] `MuxPlayer` supports signed playback URLs via `signedToken`
- [ ] `VideoChapters` renders a scrollable chapter list
- [ ] `VideoChapters` highlights the currently active chapter based on `currentTime`
- [ ] Clicking a chapter fires `onChapterClick` with the correct `startTime`
- [ ] `VideoCaptionsToggle` renders a single toggle for one caption track
- [ ] `VideoCaptionsToggle` renders a dropdown menu for multiple caption tracks
- [ ] `VideoThumbnailHover` shows a MUX thumbnail preview on hover
- [ ] `VideoCard` displays thumbnail, title, duration badge
- [ ] `VideoCard` shows a play button overlay on hover
- [ ] `VideoCard` shows status badge for non-ready assets
- [ ] All components use `useId` for React list keys
- [ ] All components use `"use client"` directive
- [ ] All components use shadcn/ui primitives (Card, Button, Badge, etc.)
- [ ] Styling uses Tailwind v4 utility classes
- [ ] No usage of `any` type anywhere in the code
- [ ] `tsc` passes with no errors
- [ ] `bun run build` succeeds

## Troubleshooting

### MUX Player not rendering

**Symptoms**: The player area is blank or shows a black rectangle.

**Cause**: Invalid `playbackId` or the asset is not yet in "ready" status.

**Fix**: Verify the playback ID is correct and the asset status is "ready" in MUX. Use the `stream-mux` skill's `/api/mux/assets/[id]` endpoint to check status.

### Thumbnails not loading

**Symptoms**: Video cards show a placeholder icon instead of thumbnails.

**Cause**: The MUX thumbnail URL requires a valid playback ID. Assets in "preparing" status do not have thumbnails yet.

**Fix**: Only show thumbnails for assets with `status === "ready"` and a non-empty `playbackId`. The `VideoCard` component handles this gracefully with a fallback.

### Player accent color not matching theme

**Symptoms**: Player controls use a different color than your shadcn theme.

**Cause**: MUX Player uses its own theming system separate from Tailwind/shadcn.

**Fix**: Pass the `accentColor` prop to `MuxPlayer` with your theme's primary color hex value. You can extract it from your CSS custom properties:

```tsx
<MuxPlayer
  playbackId="..."
  accentColor="hsl(var(--primary))"
/>
```

### Chapter sidebar not scrolling

**Symptoms**: Chapter list overflows its container.

**Cause**: The `VideoChapters` component needs an explicit height to enable scrolling via `ScrollArea`.

**Fix**: Set a height on the component: `<VideoChapters className="h-[400px]" ... />`

### "use client" missing errors

**Symptoms**: Build error about hooks being used in a Server Component.

**Cause**: All video player components use hooks and must be rendered client-side.

**Fix**: All components in this skill include `"use client"` at the top. If you wrap them in a parent component, that parent must also have `"use client"`.
