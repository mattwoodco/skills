---
name: ai-captions
description: Live closed captions for video rooms — floating caption overlay with speaker labels, configurable font size, position, and opacity. Powered by Deepgram transcription via LiveKit data channels. Use this skill when the user says "add captions", "setup closed captions", "add subtitles", "live captions", or "setup ai-captions".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [transcription, video-room, video-ui]
---

# AI Captions

Live closed captions for video rooms, powered by Deepgram transcription delivered via LiveKit data channels. Displays a floating caption bar at the bottom (or top) of the video with the current speaker's name and spoken text. Includes a settings panel for font size, position, background opacity, and language. Captions fade out after a configurable silence duration.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `transcription` skill installed (Deepgram transcription + data channel types)
- `video-room` skill installed (LiveKit room infrastructure)
- `video-ui` skill installed (video layout components)
- shadcn/ui initialized

## Installation

No new packages required. Uses packages already installed by dependencies:

- `@deepgram/sdk` (from transcription)
- `livekit-client` (from video-room)

## What Gets Created

```
src/
├── lib/
│   └── video/
│       ├── captions.ts                   # Caption formatting utilities
│       └── use-captions.ts               # "use client" hook for caption display state
└── components/
    └── video/
        ├── caption-overlay.tsx           # Floating caption bar for video
        └── caption-settings.tsx          # Settings panel (font size, position, opacity)
```

## Setup Steps

### Step 1: Create `src/lib/video/captions.ts`

```typescript
/**
 * Caption formatting and display utilities.
 * Pure functions with no side effects — safe for server or client use.
 */

/** Maximum characters to display in a single caption line */
const MAX_CAPTION_LENGTH = 120;

/** Minimum display duration in milliseconds */
const MIN_DISPLAY_MS = 2000;

/** Milliseconds per word for calculating display duration */
const MS_PER_WORD = 300;

/** Maximum display duration in milliseconds */
const MAX_DISPLAY_MS = 10000;

/**
 * Truncate caption text to a maximum length, preserving whole words.
 * If the text exceeds the limit, it truncates at the last space before the limit
 * and appends an ellipsis.
 */
export function truncateToMaxLength(text: string, maxLength = MAX_CAPTION_LENGTH): string {
  if (text.length <= maxLength) return text;

  const truncated = text.slice(0, maxLength);
  const lastSpace = truncated.lastIndexOf(" ");

  if (lastSpace > maxLength * 0.5) {
    return `${truncated.slice(0, lastSpace)}...`;
  }

  return `${truncated}...`;
}

/**
 * Format a speaker label for display in captions.
 * Shortens long names and adds a colon separator.
 *
 * @param speakerName - The speaker's display name
 * @param maxLength - Maximum length for the speaker label (default 20)
 */
export function formatSpeakerLabel(speakerName: string, maxLength = 20): string {
  if (!speakerName || speakerName.trim().length === 0) {
    return "";
  }

  const trimmed = speakerName.trim();

  if (trimmed.length <= maxLength) {
    return `${trimmed}:`;
  }

  // Try to use first name only
  const firstName = trimmed.split(" ")[0];
  if (firstName.length <= maxLength) {
    return `${firstName}:`;
  }

  return `${firstName.slice(0, maxLength)}...:`;
}

/**
 * Calculate how long a caption should be displayed based on word count.
 * Longer captions stay on screen longer to give users time to read.
 *
 * @param text - The caption text
 * @returns Display duration in milliseconds
 */
export function calculateDisplayDuration(text: string): number {
  const wordCount = text.split(/\s+/).filter(Boolean).length;
  const calculated = wordCount * MS_PER_WORD;
  return Math.min(Math.max(calculated, MIN_DISPLAY_MS), MAX_DISPLAY_MS);
}

export type CaptionFontSize = "small" | "medium" | "large";

export type CaptionPosition = "top" | "bottom";

export type CaptionSettings = {
  fontSize: CaptionFontSize;
  position: CaptionPosition;
  backgroundOpacity: number;
  enabled: boolean;
};

export const DEFAULT_CAPTION_SETTINGS: CaptionSettings = {
  fontSize: "medium",
  position: "bottom",
  backgroundOpacity: 0.75,
  enabled: true,
};

/**
 * Map font size setting to Tailwind CSS class.
 */
export function getFontSizeClass(size: CaptionFontSize): string {
  switch (size) {
    case "small":
      return "text-sm";
    case "medium":
      return "text-base";
    case "large":
      return "text-lg";
  }
}

/**
 * Map position setting to Tailwind CSS positioning classes.
 */
export function getPositionClasses(position: CaptionPosition): string {
  switch (position) {
    case "top":
      return "top-4 left-1/2 -translate-x-1/2";
    case "bottom":
      return "bottom-4 left-1/2 -translate-x-1/2";
  }
}
```

### Step 2: Create `src/lib/video/use-captions.ts`

```typescript
"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import type { TranscriptSegment } from "./types-transcription";
import {
  truncateToMaxLength,
  formatSpeakerLabel,
  calculateDisplayDuration,
  DEFAULT_CAPTION_SETTINGS,
  type CaptionSettings,
  type CaptionFontSize,
  type CaptionPosition,
} from "./captions";

type CaptionEntry = {
  speaker: string;
  text: string;
  timestamp: number;
  displayUntil: number;
};

type UseCaptionsOptions = {
  /** Map of speaker IDs to display names */
  speakerNames?: Record<number, string>;
  /** Initial settings override */
  initialSettings?: Partial<CaptionSettings>;
};

type TranscriptMessage = {
  type: "transcript";
  segment: TranscriptSegment;
  isFinal: boolean;
};

/**
 * Hook that subscribes to transcription data channel messages,
 * buffers recent segments, and manages caption display timing.
 *
 * Returns the current caption to display, active state, and settings controls.
 */
export function useCaptions(
  onDataReceived?: (handler: (payload: Uint8Array) => void) => () => void,
  options: UseCaptionsOptions = {}
) {
  const { speakerNames = {}, initialSettings } = options;

  const [settings, setSettings] = useState<CaptionSettings>({
    ...DEFAULT_CAPTION_SETTINGS,
    ...initialSettings,
  });

  const [currentCaption, setCurrentCaption] = useState<CaptionEntry | null>(null);
  const [isActive, setIsActive] = useState(false);
  const fadeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const decoderRef = useRef(new TextDecoder());

  // Clear fade timer on unmount
  useEffect(() => {
    return () => {
      if (fadeTimerRef.current) {
        clearTimeout(fadeTimerRef.current);
      }
    };
  }, []);

  const showCaption = useCallback(
    (segment: TranscriptSegment) => {
      if (!settings.enabled) return;

      // Clear existing fade timer
      if (fadeTimerRef.current) {
        clearTimeout(fadeTimerRef.current);
      }

      const speakerName = speakerNames[segment.speaker] ?? `Speaker ${segment.speaker + 1}`;
      const displayText = truncateToMaxLength(segment.text);
      const displayDuration = calculateDisplayDuration(segment.text);

      const entry: CaptionEntry = {
        speaker: formatSpeakerLabel(speakerName),
        text: displayText,
        timestamp: Date.now(),
        displayUntil: Date.now() + displayDuration,
      };

      setCurrentCaption(entry);
      setIsActive(true);

      // Set timer to fade out
      fadeTimerRef.current = setTimeout(() => {
        setCurrentCaption(null);
        setIsActive(false);
        fadeTimerRef.current = null;
      }, displayDuration);
    },
    [settings.enabled, speakerNames]
  );

  const handleMessage = useCallback(
    (payload: Uint8Array) => {
      try {
        const text = decoderRef.current.decode(payload);
        const message = JSON.parse(text) as TranscriptMessage;

        if (message.type !== "transcript") return;

        // Show both interim and final results for responsive captions
        showCaption(message.segment);
      } catch {
        // Ignore malformed messages
      }
    },
    [showCaption]
  );

  // Subscribe to data channel
  useEffect(() => {
    if (!onDataReceived) return;
    const unsubscribe = onDataReceived(handleMessage);
    return unsubscribe;
  }, [onDataReceived, handleMessage]);

  const updateSettings = useCallback((updates: Partial<CaptionSettings>) => {
    setSettings((prev) => ({ ...prev, ...updates }));
  }, []);

  const setFontSize = useCallback((fontSize: CaptionFontSize) => {
    setSettings((prev) => ({ ...prev, fontSize }));
  }, []);

  const setPosition = useCallback((position: CaptionPosition) => {
    setSettings((prev) => ({ ...prev, position }));
  }, []);

  const setBackgroundOpacity = useCallback((backgroundOpacity: number) => {
    setSettings((prev) => ({
      ...prev,
      backgroundOpacity: Math.max(0, Math.min(1, backgroundOpacity)),
    }));
  }, []);

  const toggleEnabled = useCallback(() => {
    setSettings((prev) => {
      const enabled = !prev.enabled;
      if (!enabled) {
        // Clear current caption when disabling
        setCurrentCaption(null);
        setIsActive(false);
        if (fadeTimerRef.current) {
          clearTimeout(fadeTimerRef.current);
          fadeTimerRef.current = null;
        }
      }
      return { ...prev, enabled };
    });
  }, []);

  return {
    /** The current caption to display, or null if none */
    currentCaption,
    /** Whether a caption is currently being shown */
    isActive,
    /** Current caption settings */
    settings,
    /** Update one or more settings */
    updateSettings,
    /** Set font size */
    setFontSize,
    /** Set caption position */
    setPosition,
    /** Set background opacity (0-1) */
    setBackgroundOpacity,
    /** Toggle captions on/off */
    toggleEnabled,
  };
}
```

### Step 3: Create `src/components/video/caption-overlay.tsx`

```tsx
"use client";

import { cn } from "@src/lib/utils";
import {
  getFontSizeClass,
  getPositionClasses,
  type CaptionSettings,
} from "@src/lib/video/captions";

type CaptionEntry = {
  speaker: string;
  text: string;
  timestamp: number;
  displayUntil: number;
};

type CaptionOverlayProps = {
  caption: CaptionEntry | null;
  isActive: boolean;
  settings: CaptionSettings;
  className?: string;
};

/**
 * Floating caption bar that displays live transcription captions
 * overlaid on the video. Positioned at the top or bottom of the container.
 *
 * Must be placed inside a `position: relative` container (the video area).
 */
export function CaptionOverlay({
  caption,
  isActive,
  settings,
  className,
}: CaptionOverlayProps) {
  if (!settings.enabled || !isActive || !caption) {
    return null;
  }

  return (
    <div
      className={cn(
        "pointer-events-none absolute z-40 max-w-[90%] transition-opacity duration-300",
        getPositionClasses(settings.position),
        isActive ? "opacity-100" : "opacity-0",
        className
      )}
    >
      <div
        className="rounded-lg px-4 py-2 shadow-lg"
        style={{
          backgroundColor: `rgba(0, 0, 0, ${settings.backgroundOpacity})`,
        }}
      >
        <p
          className={cn(
            "text-center text-white leading-relaxed",
            getFontSizeClass(settings.fontSize)
          )}
        >
          {caption.speaker && (
            <span className="mr-1.5 font-semibold text-blue-300">
              {caption.speaker}
            </span>
          )}
          <span>{caption.text}</span>
        </p>
      </div>
    </div>
  );
}
```

### Step 4: Create `src/components/video/caption-settings.tsx`

```tsx
"use client";

import { useId } from "react";
import { cn } from "@src/lib/utils";
import type {
  CaptionSettings,
  CaptionFontSize,
  CaptionPosition,
} from "@src/lib/video/captions";

type CaptionSettingsProps = {
  settings: CaptionSettings;
  onFontSizeChange: (size: CaptionFontSize) => void;
  onPositionChange: (position: CaptionPosition) => void;
  onOpacityChange: (opacity: number) => void;
  onToggleEnabled: () => void;
  className?: string;
};

const FONT_SIZE_OPTIONS: Array<{ value: CaptionFontSize; label: string }> = [
  { value: "small", label: "Small" },
  { value: "medium", label: "Medium" },
  { value: "large", label: "Large" },
];

const POSITION_OPTIONS: Array<{ value: CaptionPosition; label: string }> = [
  { value: "top", label: "Top" },
  { value: "bottom", label: "Bottom" },
];

export function CaptionSettingsPanel({
  settings,
  onFontSizeChange,
  onPositionChange,
  onOpacityChange,
  onToggleEnabled,
  className,
}: CaptionSettingsProps) {
  const fontSizeGroupId = useId();
  const positionGroupId = useId();
  const opacityId = useId();
  const enabledId = useId();

  return (
    <div className={cn("flex flex-col gap-4 rounded-lg border bg-card p-4", className)}>
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Caption Settings</h3>
        <label htmlFor={enabledId} className="flex items-center gap-2 text-sm">
          <input
            id={enabledId}
            type="checkbox"
            checked={settings.enabled}
            onChange={onToggleEnabled}
            className="h-4 w-4 rounded border-border"
          />
          Enabled
        </label>
      </div>

      {/* Font Size */}
      <fieldset className="flex flex-col gap-1.5">
        <legend className="text-xs font-medium text-muted-foreground">Font Size</legend>
        <div className="flex gap-1">
          {FONT_SIZE_OPTIONS.map((option) => (
            <button
              key={`${fontSizeGroupId}-${option.value}`}
              type="button"
              onClick={() => onFontSizeChange(option.value)}
              className={cn(
                "flex-1 rounded-md px-3 py-1.5 text-xs font-medium transition-colors",
                settings.fontSize === option.value
                  ? "bg-primary text-primary-foreground"
                  : "bg-muted text-muted-foreground hover:bg-muted/80"
              )}
            >
              {option.label}
            </button>
          ))}
        </div>
      </fieldset>

      {/* Position */}
      <fieldset className="flex flex-col gap-1.5">
        <legend className="text-xs font-medium text-muted-foreground">Position</legend>
        <div className="flex gap-1">
          {POSITION_OPTIONS.map((option) => (
            <button
              key={`${positionGroupId}-${option.value}`}
              type="button"
              onClick={() => onPositionChange(option.value)}
              className={cn(
                "flex-1 rounded-md px-3 py-1.5 text-xs font-medium transition-colors",
                settings.position === option.value
                  ? "bg-primary text-primary-foreground"
                  : "bg-muted text-muted-foreground hover:bg-muted/80"
              )}
            >
              {option.label}
            </button>
          ))}
        </div>
      </fieldset>

      {/* Background Opacity */}
      <fieldset className="flex flex-col gap-1.5">
        <legend className="text-xs font-medium text-muted-foreground">
          Background Opacity: {Math.round(settings.backgroundOpacity * 100)}%
        </legend>
        <input
          id={opacityId}
          type="range"
          min="0"
          max="100"
          step="5"
          value={Math.round(settings.backgroundOpacity * 100)}
          onChange={(e) => onOpacityChange(Number(e.target.value) / 100)}
          className="w-full accent-primary"
        />
        <div className="flex justify-between text-xs text-muted-foreground">
          <span>Transparent</span>
          <span>Opaque</span>
        </div>
      </fieldset>

      {/* Preview */}
      <div className="flex flex-col gap-1.5">
        <span className="text-xs font-medium text-muted-foreground">Preview</span>
        <div className="relative flex items-center justify-center rounded-lg bg-zinc-800 p-8">
          <div
            className="rounded-lg px-4 py-2"
            style={{
              backgroundColor: `rgba(0, 0, 0, ${settings.backgroundOpacity})`,
            }}
          >
            <p
              className={cn(
                "text-center text-white",
                settings.fontSize === "small" && "text-sm",
                settings.fontSize === "medium" && "text-base",
                settings.fontSize === "large" && "text-lg"
              )}
            >
              <span className="mr-1.5 font-semibold text-blue-300">Speaker 1:</span>
              <span>This is a preview of the captions.</span>
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
```

## Usage

### Add Captions to a Video Room

```tsx
"use client";

import { useCaptions } from "@src/lib/video/use-captions";
import { CaptionOverlay } from "@/components/video/caption-overlay";
import { CaptionSettingsPanel } from "@/components/video/caption-settings";

export function VideoRoomWithCaptions() {
  // In a real implementation, onDataReceived comes from your LiveKit data channel hook
  const {
    currentCaption,
    isActive,
    settings,
    setFontSize,
    setPosition,
    setBackgroundOpacity,
    toggleEnabled,
  } = useCaptions(undefined, {
    speakerNames: { 0: "Alice", 1: "Bob" },
  });

  return (
    <div className="flex gap-4">
      {/* Video area — must be position: relative */}
      <div className="relative flex-1 aspect-video bg-black rounded-lg overflow-hidden">
        {/* Video tracks rendered here */}

        <CaptionOverlay
          caption={currentCaption}
          isActive={isActive}
          settings={settings}
        />
      </div>

      {/* Settings sidebar */}
      <aside className="w-72">
        <CaptionSettingsPanel
          settings={settings}
          onFontSizeChange={setFontSize}
          onPositionChange={setPosition}
          onOpacityChange={setBackgroundOpacity}
          onToggleEnabled={toggleEnabled}
        />
      </aside>
    </div>
  );
}
```

### Caption Overlay Only (Minimal)

```tsx
"use client";

import { useCaptions } from "@src/lib/video/use-captions";
import { CaptionOverlay } from "@/components/video/caption-overlay";

export function MinimalCaptions() {
  const { currentCaption, isActive, settings } = useCaptions();

  return (
    <div className="relative h-full w-full">
      {/* Your video content */}
      <CaptionOverlay
        caption={currentCaption}
        isActive={isActive}
        settings={settings}
      />
    </div>
  );
}
```

### Toggle Captions with a Button

```tsx
"use client";

import { useCaptions } from "@src/lib/video/use-captions";
import { CaptionOverlay } from "@/components/video/caption-overlay";

export function VideoWithCaptionToggle() {
  const { currentCaption, isActive, settings, toggleEnabled } = useCaptions();

  return (
    <div className="relative flex flex-col">
      <div className="relative flex-1">
        {/* Video */}
        <CaptionOverlay
          caption={currentCaption}
          isActive={isActive}
          settings={settings}
        />
      </div>

      <div className="flex items-center gap-2 p-2">
        <button
          type="button"
          onClick={toggleEnabled}
          className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
            settings.enabled
              ? "bg-primary text-primary-foreground"
              : "bg-muted text-muted-foreground"
          }`}
        >
          {settings.enabled ? "CC On" : "CC Off"}
        </button>
      </div>
    </div>
  );
}
```

### Using Caption Utilities Directly

```typescript
import {
  truncateToMaxLength,
  formatSpeakerLabel,
  calculateDisplayDuration,
} from "@src/lib/video/captions";

// Truncate long text
truncateToMaxLength("A very long caption that exceeds the limit...", 50);
// → "A very long caption that exceeds the..."

// Format speaker label
formatSpeakerLabel("Alice Johnson"); // → "Alice Johnson:"
formatSpeakerLabel("A Very Long Name That Exceeds Limit"); // → "A Very Long Name Tha...:"
formatSpeakerLabel(""); // → ""

// Calculate display duration from word count
calculateDisplayDuration("Hello world"); // → 2000 (minimum)
calculateDisplayDuration("A longer sentence with more words to read"); // → 2400
```

## Acceptance Criteria

- `CaptionOverlay` renders a floating caption bar positioned at the bottom of the video container
- Caption bar shows current speaker name (color-coded) and spoken text
- Captions fade out after a duration calculated from word count
- `CaptionSettingsPanel` allows toggling font size (small/medium/large)
- `CaptionSettingsPanel` allows toggling position (top/bottom)
- `CaptionSettingsPanel` allows adjusting background opacity (0-100%)
- Settings panel includes a live preview
- `useCaptions` hook correctly parses transcript data channel messages
- `truncateToMaxLength` preserves whole words when truncating
- `formatSpeakerLabel` handles empty strings, short names, and long names
- `calculateDisplayDuration` returns values between 2s and 10s based on word count
- Captions can be toggled on/off via `toggleEnabled`
- No usage of `any` type anywhere
- `tsc` passes with no errors
- `bun run build` succeeds

## Troubleshooting

### Captions not appearing

**Cause**: The `onDataReceived` callback is not connected to the LiveKit data channel, or captions are disabled.

**Fix**: Ensure the `useCaptions` hook receives a valid `onDataReceived` function from your LiveKit data channel subscription. Verify `settings.enabled` is `true`.

### Captions disappear too quickly

**Cause**: The `calculateDisplayDuration` function bases duration on word count. Very short utterances display for the minimum 2 seconds.

**Fix**: You can customize the display duration by wrapping the hook and overriding the fade timer, or adjust the `MS_PER_WORD` and `MIN_DISPLAY_MS` constants in `captions.ts`.

### Caption overlay not visible over video

**Cause**: The `CaptionOverlay` uses `z-40` which may be below other overlays in your video UI.

**Fix**: Ensure the parent container of `CaptionOverlay` has `position: relative` set. If other elements have higher z-indexes, pass a custom `className` with a higher z-index.

### Speaker names showing as "Speaker 1", "Speaker 2"

**Cause**: The `speakerNames` map was not provided to `useCaptions`.

**Fix**: Pass a `speakerNames` option mapping speaker IDs to display names:

```typescript
const { currentCaption } = useCaptions(onDataReceived, {
  speakerNames: { 0: "Alice", 1: "Bob", 2: "Carol" },
});
```
