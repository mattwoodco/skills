---
name: video-timeline
description: React video player with engagement heatmap timeline and clickable hotspot markers. Use this skill when the user says "add video timeline", "video heatmap", "clip finder ui", "video hotspots", or "engagement timeline".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: [add-shadcn]
---

# Video Timeline Skill

A self-contained video player component with a custom heatmap timeline and clickable hotspot markers. The timeline bar uses a color gradient (gray / amber / green) derived from each hotspot's score. Clicking a marker seeks the video, shows a score-breakdown panel below, and fires a callback. No external video libraries — uses the browser HTML5 `<video>` API directly.

## Prerequisites

- Next.js app with App Router (no `src/` directory)
- `add-shadcn` skill applied

## Installation

No additional packages required. Uses the browser HTML5 video API and `@phosphor-icons/react` (already installed by the `add-shadcn` preset).

## What Gets Created

```
components/
└── video-timeline/
    ├── video-timeline.tsx      # Full component (use client)
    └── use-video-timeline.ts   # Hook for video state
```

## Setup Steps

### Step 1: Create `components/video-timeline/use-video-timeline.ts`

```typescript
import { useState, useCallback, useEffect, type RefObject } from "react";

type UseVideoTimelineReturn = {
  currentTime: number;
  duration: number;
  isPlaying: boolean;
  volume: number;
  play: () => void;
  pause: () => void;
  seek: (time: number) => void;
  setVolume: (volume: number) => void;
};

export function useVideoTimeline(
  videoRef: RefObject<HTMLVideoElement | null>
): UseVideoTimelineReturn {
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [volume, setVolumeState] = useState(1);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    const onTimeUpdate = () => setCurrentTime(video.currentTime);
    const onDurationChange = () => setDuration(video.duration || 0);
    const onPlay = () => setIsPlaying(true);
    const onPause = () => setIsPlaying(false);
    const onVolumeChange = () => setVolumeState(video.volume);

    video.addEventListener("timeupdate", onTimeUpdate);
    video.addEventListener("durationchange", onDurationChange);
    video.addEventListener("loadedmetadata", onDurationChange);
    video.addEventListener("play", onPlay);
    video.addEventListener("pause", onPause);
    video.addEventListener("volumechange", onVolumeChange);

    return () => {
      video.removeEventListener("timeupdate", onTimeUpdate);
      video.removeEventListener("durationchange", onDurationChange);
      video.removeEventListener("loadedmetadata", onDurationChange);
      video.removeEventListener("play", onPlay);
      video.removeEventListener("pause", onPause);
      video.removeEventListener("volumechange", onVolumeChange);
    };
  }, [videoRef]);

  const play = useCallback(() => {
    videoRef.current?.play();
  }, [videoRef]);

  const pause = useCallback(() => {
    videoRef.current?.pause();
  }, [videoRef]);

  const seek = useCallback(
    (time: number) => {
      const video = videoRef.current;
      if (!video) return;
      video.currentTime = Math.min(Math.max(0, time), video.duration || 0);
    },
    [videoRef]
  );

  const setVolume = useCallback(
    (vol: number) => {
      const video = videoRef.current;
      if (!video) return;
      video.volume = Math.min(Math.max(0, vol), 1);
    },
    [videoRef]
  );

  return { currentTime, duration, isPlaying, volume, play, pause, seek, setVolume };
}
```

### Step 2: Create `components/video-timeline/video-timeline.tsx`

```typescript
"use client";

import { useRef, useState, useCallback, useId } from "react";
import {
  Play,
  Pause,
  SpeakerHigh,
  SpeakerX,
  ArrowsOut,
} from "@phosphor-icons/react";
import { useVideoTimeline } from "./use-video-timeline";
import { cn } from "@src/lib/utils";

export type VideoHotspot = {
  id: string;
  timestamp: number; // seconds
  score: number; // 0-1
  label: string;
  axes: {
    emotionalPeak: number;
    infoDensity: number;
    surprise: number;
    standAlone: number;
  };
};

type VideoTimelineProps = {
  src: string;
  hotspots: VideoHotspot[];
  onHotspotClick?: (hotspot: VideoHotspot) => void;
  onTimeUpdate?: (currentTime: number, duration: number) => void;
  className?: string;
};

function formatTime(seconds: number): string {
  if (!isFinite(seconds)) return "0:00";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function scoreToColor(score: number): string {
  if (score >= 0.6) return "#22c55e"; // green-500
  if (score >= 0.3) return "#f59e0b"; // amber-500
  return "#6b7280"; // gray-500
}

function scoreToLabel(score: number): string {
  if (score >= 0.6) return "High";
  if (score >= 0.3) return "Medium";
  return "Low";
}

type AxisBarProps = {
  label: string;
  value: number;
};

function AxisBar({ label, value }: AxisBarProps) {
  return (
    <div className="flex flex-col gap-1">
      <div className="flex justify-between text-xs text-muted-foreground">
        <span>{label}</span>
        <span>{Math.round(value * 100)}%</span>
      </div>
      <div className="h-1.5 bg-muted rounded-full overflow-hidden">
        <div
          className="h-full rounded-full bg-primary transition-all duration-300"
          style={{ width: `${value * 100}%` }}
        />
      </div>
    </div>
  );
}

export function VideoTimeline({
  src,
  hotspots,
  onHotspotClick,
  onTimeUpdate,
  className,
}: VideoTimelineProps) {
  const markerId = useId();
  const videoRef = useRef<HTMLVideoElement>(null);
  const timelineRef = useRef<HTMLDivElement>(null);
  const [selectedHotspot, setSelectedHotspot] = useState<VideoHotspot | null>(null);
  const [isMuted, setIsMuted] = useState(false);

  const { currentTime, duration, isPlaying, volume, play, pause, seek, setVolume } =
    useVideoTimeline(videoRef);

  const handleTimeUpdate = useCallback(() => {
    if (onTimeUpdate && videoRef.current) {
      onTimeUpdate(videoRef.current.currentTime, videoRef.current.duration || 0);
    }
  }, [onTimeUpdate]);

  const handleTimelineClick = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      const rect = timelineRef.current?.getBoundingClientRect();
      if (!rect || duration === 0) return;
      const ratio = Math.min(Math.max((e.clientX - rect.left) / rect.width, 0), 1);
      seek(ratio * duration);
    },
    [duration, seek]
  );

  const handleHotspotClick = useCallback(
    (hotspot: VideoHotspot) => {
      seek(hotspot.timestamp);
      setSelectedHotspot((prev) => (prev?.id === hotspot.id ? null : hotspot));
      onHotspotClick?.(hotspot);
    },
    [seek, onHotspotClick]
  );

  const toggleMute = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;
    video.muted = !video.muted;
    setIsMuted(video.muted);
  }, []);

  const handleFullscreen = useCallback(() => {
    videoRef.current?.requestFullscreen?.();
  }, []);

  const progressPercent = duration > 0 ? (currentTime / duration) * 100 : 0;

  return (
    <div className={cn("flex flex-col gap-0 bg-card border border-border rounded-xl overflow-hidden", className)}>
      {/* Video element */}
      <video
        ref={videoRef}
        src={src}
        className="w-full aspect-video bg-black"
        preload="metadata"
        onTimeUpdate={handleTimeUpdate}
        playsInline
      />

      {/* Custom controls */}
      <div className="flex items-center gap-3 px-4 py-2 bg-card border-t border-border">
        <button
          type="button"
          onClick={isPlaying ? pause : play}
          className="text-foreground hover:text-primary transition-colors"
          aria-label={isPlaying ? "Pause" : "Play"}
        >
          {isPlaying ? <Pause size={20} weight="fill" /> : <Play size={20} weight="fill" />}
        </button>

        <span className="text-xs text-muted-foreground tabular-nums min-w-[80px]">
          {formatTime(currentTime)} / {formatTime(duration)}
        </span>

        <button
          type="button"
          onClick={toggleMute}
          className="text-foreground hover:text-primary transition-colors"
          aria-label={isMuted ? "Unmute" : "Mute"}
        >
          {isMuted || volume === 0 ? (
            <SpeakerX size={18} />
          ) : (
            <SpeakerHigh size={18} />
          )}
        </button>

        <input
          type="range"
          min={0}
          max={1}
          step={0.05}
          value={isMuted ? 0 : volume}
          onChange={(e) => setVolume(parseFloat(e.target.value))}
          className="w-20 accent-primary"
          aria-label="Volume"
        />

        <button
          type="button"
          onClick={handleFullscreen}
          className="ml-auto text-foreground hover:text-primary transition-colors"
          aria-label="Fullscreen"
        >
          <ArrowsOut size={18} />
        </button>
      </div>

      {/* Timeline bar + hotspot markers */}
      <div className="relative px-4 pb-2 pt-6 bg-card">
        {/* Hotspot markers — positioned above the bar */}
        {hotspots.map((hotspot) => {
          const leftPercent =
            duration > 0 ? (hotspot.timestamp / duration) * 100 : 0;
          const color = scoreToColor(hotspot.score);
          const isSelected = selectedHotspot?.id === hotspot.id;

          return (
            <div
              key={`${markerId}-${hotspot.id}`}
              className="absolute top-0 -translate-x-1/2"
              style={{ left: `calc(${leftPercent}% + 1rem)` }}
            >
              <div className="relative group">
                <button
                  type="button"
                  onClick={() => handleHotspotClick(hotspot)}
                  className={cn(
                    "flex items-center justify-center rounded-full w-5 h-5 text-white text-[10px] font-bold shadow transition-transform hover:scale-125",
                    isSelected && "ring-2 ring-offset-1 ring-primary scale-125"
                  )}
                  style={{ backgroundColor: color }}
                  aria-label={`${hotspot.label} — score ${Math.round(hotspot.score * 100)}%`}
                >
                  {Math.round(hotspot.score * 10)}
                </button>

                {/* Hover tooltip */}
                <div className="absolute bottom-full mb-2 left-1/2 -translate-x-1/2 hidden group-hover:flex flex-col gap-1 bg-popover border border-border rounded-lg p-2 shadow-lg w-44 z-50 pointer-events-none">
                  <p className="text-xs font-semibold text-foreground truncate">{hotspot.label}</p>
                  <p className="text-xs text-muted-foreground">Score: {Math.round(hotspot.score * 100)}%</p>
                  <div className="flex flex-col gap-0.5 mt-1">
                    <p className="text-[10px] text-muted-foreground">Emotional: {Math.round(hotspot.axes.emotionalPeak * 100)}%</p>
                    <p className="text-[10px] text-muted-foreground">Info: {Math.round(hotspot.axes.infoDensity * 100)}%</p>
                    <p className="text-[10px] text-muted-foreground">Surprise: {Math.round(hotspot.axes.surprise * 100)}%</p>
                    <p className="text-[10px] text-muted-foreground">Standalone: {Math.round(hotspot.axes.standAlone * 100)}%</p>
                  </div>
                </div>
              </div>
            </div>
          );
        })}

        {/* Heatmap timeline bar */}
        <div
          ref={timelineRef}
          className="relative h-2 rounded-full overflow-hidden cursor-pointer bg-muted"
          onClick={handleTimelineClick}
          role="slider"
          aria-label="Seek"
          aria-valuenow={Math.round(progressPercent)}
          aria-valuemin={0}
          aria-valuemax={100}
        >
          {/* Score color segments */}
          {hotspots.length > 0 && duration > 0 && (
            <div className="absolute inset-0 flex">
              {hotspots
                .slice()
                .sort((a, b) => a.timestamp - b.timestamp)
                .map((hotspot, i, sorted) => {
                  const segKey = `${markerId}-seg-${hotspot.id}`;
                  const startPercent = (hotspot.timestamp / duration) * 100;
                  const nextTimestamp = sorted[i + 1]?.timestamp ?? duration;
                  const widthPercent = ((nextTimestamp - hotspot.timestamp) / duration) * 100;
                  return (
                    <div
                      key={segKey}
                      className="absolute top-0 h-full opacity-60"
                      style={{
                        left: `${startPercent}%`,
                        width: `${widthPercent}%`,
                        backgroundColor: scoreToColor(hotspot.score),
                      }}
                    />
                  );
                })}
            </div>
          )}

          {/* Playhead */}
          <div
            className="absolute top-0 h-full bg-primary/80 pointer-events-none transition-none"
            style={{ width: `${progressPercent}%` }}
          />
        </div>
      </div>

      {/* Selected hotspot detail panel */}
      {selectedHotspot && (
        <div className="border-t border-border px-4 py-4 bg-muted/50 flex flex-col gap-3">
          <div className="flex items-start justify-between gap-2">
            <div className="flex flex-col gap-0.5">
              <p className="text-sm font-semibold text-foreground">{selectedHotspot.label}</p>
              <p className="text-xs text-muted-foreground">
                {formatTime(selectedHotspot.timestamp)} &middot;{" "}
                <span style={{ color: scoreToColor(selectedHotspot.score) }}>
                  {scoreToLabel(selectedHotspot.score)} score ({Math.round(selectedHotspot.score * 100)}%)
                </span>
              </p>
            </div>
            <button
              type="button"
              onClick={() => onHotspotClick?.(selectedHotspot)}
              className="shrink-0 text-xs font-medium px-3 py-1.5 rounded-md bg-primary text-primary-foreground hover:bg-primary/90 transition-colors"
            >
              Export Clip
            </button>
          </div>

          <div className="grid grid-cols-2 gap-x-6 gap-y-2">
            <AxisBar label="Emotional Peak" value={selectedHotspot.axes.emotionalPeak} />
            <AxisBar label="Info Density" value={selectedHotspot.axes.infoDensity} />
            <AxisBar label="Surprise" value={selectedHotspot.axes.surprise} />
            <AxisBar label="Standalone" value={selectedHotspot.axes.standAlone} />
          </div>
        </div>
      )}
    </div>
  );
}
```

## Usage

```tsx
"use client";

import { VideoTimeline } from "@/components/video-timeline/video-timeline";
import type { VideoHotspot } from "@/components/video-timeline/video-timeline";

const DEMO_HOTSPOTS: VideoHotspot[] = [
  {
    id: "hotspot-1",
    timestamp: 12,
    score: 0.85,
    label: "Product reveal moment",
    axes: { emotionalPeak: 0.9, infoDensity: 0.7, surprise: 0.85, standAlone: 0.8 },
  },
  {
    id: "hotspot-2",
    timestamp: 45,
    score: 0.45,
    label: "Feature explanation",
    axes: { emotionalPeak: 0.3, infoDensity: 0.8, surprise: 0.2, standAlone: 0.5 },
  },
  {
    id: "hotspot-3",
    timestamp: 78,
    score: 0.72,
    label: "Surprising statistic",
    axes: { emotionalPeak: 0.6, infoDensity: 0.75, surprise: 0.9, standAlone: 0.65 },
  },
];

export default function VideoPage() {
  return (
    <main className="max-w-3xl mx-auto p-8">
      <h1 className="text-2xl font-bold text-foreground mb-6">Video Analysis</h1>
      <VideoTimeline
        src="/demo.mp4"
        hotspots={DEMO_HOTSPOTS}
        onHotspotClick={(hotspot) => console.log("export clip:", hotspot)}
        onTimeUpdate={(t, d) => console.log(t, "/", d)}
        className="w-full"
      />
    </main>
  );
}
```

## Acceptance Criteria

- Component renders with a video `src` and hotspot array without console errors
- Clicking a hotspot marker seeks the video to that timestamp and fires `onHotspotClick`
- Clicking the timeline bar seeks the video proportionally based on click position
- Heatmap segments are colored gray (score < 0.3), amber (0.3–0.6), or green (> 0.6)
- Hovering a hotspot marker shows a tooltip with label and 4-axis breakdown
- Clicking a hotspot toggles the detail panel; clicking the same hotspot again closes it
- "Export Clip" button in the detail panel fires `onHotspotClick` with the selected hotspot
- Play/pause, volume, and fullscreen controls work correctly
- `tsc` passes with no errors
- Build succeeds
