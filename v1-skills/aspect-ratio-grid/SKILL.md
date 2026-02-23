---
name: aspect-ratio-grid
description: Display the same image across multiple social platform aspect ratios with per-platform download and crop-vs-outpaint comparison. Use this skill when the user says "show platform formats", "aspect ratio grid", "multi-format preview", "reformat results", or "platform image grid".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: [platform-specs, add-shadcn]
---

# Aspect Ratio Grid Skill

Responsive grid that renders the same image in every social platform format. Each card shows the platform label, pixel dimensions, live status (pending / generating / done / error), a draggable before/after comparison slider, safe zone overlay, and per-platform download + regenerate actions.

## Prerequisites

- Next.js App Router (no `src/` directory)
- `@src/lib/platform-specs` — exports `getPlatform(id)` and `PlatformId` (from the `platform-specs` skill)
- shadcn/ui with Switch and Button components
- `@phosphor-icons/react`

## Installation

No new packages required. Install shadcn components if not already present:

```bash
bunx shadcn@latest add switch button
bun add @phosphor-icons/react
```

## What Gets Created

```
components/aspect-ratio-grid/aspect-ratio-grid.tsx
components/aspect-ratio-grid/aspect-ratio-card.tsx
```

## Setup Steps

### Step 1: Create `components/aspect-ratio-grid/aspect-ratio-card.tsx`

```typescript
"use client";

import { useId, useRef, useState } from "react";
import { DownloadSimple, ArrowsClockwise } from "@phosphor-icons/react";
import type { PlatformId } from "@src/lib/platform-specs";
import { getPlatform } from "@src/lib/platform-specs";

export type ImageVariant = {
  platformId: PlatformId;
  url: string;
  originalUrl?: string;
  status: "pending" | "generating" | "done" | "error";
  error?: string;
};

type AspectRatioCardProps = {
  variant: ImageVariant;
  showComparison: boolean;
  onDownload?: (variant: ImageVariant) => void;
  onRegenerate?: (platformId: PlatformId) => void;
};

export function AspectRatioCard({
  variant,
  showComparison,
  onDownload,
  onRegenerate,
}: AspectRatioCardProps) {
  const spec = getPlatform(variant.platformId);
  const sliderContainerId = useId();
  const containerRef = useRef<HTMLDivElement>(null);
  const [sliderX, setSliderX] = useState(50); // percentage

  const canCompare =
    showComparison &&
    variant.status === "done" &&
    Boolean(variant.originalUrl);

  function updateSlider(clientX: number) {
    if (!containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    const pct = Math.min(
      100,
      Math.max(0, ((clientX - rect.left) / rect.width) * 100)
    );
    setSliderX(pct);
  }

  function handleMouseMove(e: React.MouseEvent<HTMLDivElement>) {
    if (!canCompare) return;
    updateSlider(e.clientX);
  }

  function handleTouchMove(e: React.TouchEvent<HTMLDivElement>) {
    if (!canCompare) return;
    const touch = e.touches[0];
    if (touch) updateSlider(touch.clientX);
  }

  const safeZoneStyle: React.CSSProperties | undefined =
    spec.safeZone && variant.status === "done"
      ? {
          position: "absolute",
          insetTop: `${(spec.safeZone.top / spec.height) * 100}%`,
          insetBottom: `${(spec.safeZone.bottom / spec.height) * 100}%`,
          insetLeft: `${(spec.safeZone.left / spec.width) * 100}%`,
          insetRight: `${(spec.safeZone.right / spec.width) * 100}%`,
          border: "1.5px dashed rgba(255,255,255,0.6)",
          borderRadius: 2,
          pointerEvents: "none",
        }
      : undefined;

  return (
    <div className="flex flex-col gap-2 rounded-lg border border-border bg-card p-3">
      {/* Header */}
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs font-semibold text-foreground">
          {spec.label}
        </span>
        <span className="rounded-full bg-muted px-2 py-0.5 text-[10px] text-muted-foreground">
          {spec.width}&times;{spec.height}
        </span>
      </div>

      {/* Image container */}
      <div
        id={sliderContainerId}
        ref={containerRef}
        className="relative overflow-hidden rounded"
        style={{ aspectRatio: `${spec.width}/${spec.height}` }}
        onMouseMove={handleMouseMove}
        onTouchMove={handleTouchMove}
      >
        {variant.status === "pending" && (
          <div className="flex h-full w-full items-center justify-center bg-muted">
            <span className="text-xs text-muted-foreground">{spec.label}</span>
          </div>
        )}

        {variant.status === "generating" && (
          <div className="h-full w-full animate-pulse bg-muted" />
        )}

        {variant.status === "done" && (
          <>
            {canCompare && variant.originalUrl ? (
              <>
                {/* Original image clipped to left side */}
                <img
                  src={variant.originalUrl}
                  alt={`${spec.label} original`}
                  className="absolute inset-0 h-full w-full object-cover"
                  style={{
                    clipPath: `polygon(0 0, ${sliderX}% 0, ${sliderX}% 100%, 0 100%)`,
                  }}
                />
                {/* Generated image clipped to right side */}
                <img
                  src={variant.url}
                  alt={spec.label}
                  className="absolute inset-0 h-full w-full object-cover"
                  style={{
                    clipPath: `polygon(${sliderX}% 0, 100% 0, 100% 100%, ${sliderX}% 100%)`,
                  }}
                />
                {/* Divider line */}
                <div
                  className="absolute inset-y-0 w-px bg-white shadow-md"
                  style={{ left: `${sliderX}%`, transform: "translateX(-50%)" }}
                />
              </>
            ) : (
              <img
                src={variant.url}
                alt={spec.label}
                className="h-full w-full object-cover"
              />
            )}

            {/* Safe zone overlay */}
            {safeZoneStyle && <div style={safeZoneStyle} />}
          </>
        )}

        {variant.status === "error" && (
          <div className="flex h-full w-full flex-col items-center justify-center gap-2 rounded border border-destructive/40 bg-destructive/10 p-2">
            <span className="text-center text-[10px] text-destructive">
              {variant.error ?? "Generation failed"}
            </span>
            {onRegenerate && (
              <button
                type="button"
                onClick={() => onRegenerate(variant.platformId)}
                className="rounded bg-destructive px-2 py-1 text-[10px] font-medium text-destructive-foreground hover:bg-destructive/90"
              >
                Retry
              </button>
            )}
          </div>
        )}
      </div>

      {/* Footer actions */}
      <div className="flex items-center justify-end gap-1">
        {variant.status === "done" && (
          <a
            href={variant.url}
            download
            onClick={() => onDownload?.(variant)}
            className="inline-flex h-7 w-7 items-center justify-center rounded hover:bg-muted"
            aria-label={`Download ${spec.label}`}
          >
            <DownloadSimple size={15} className="text-muted-foreground" />
          </a>
        )}
        {onRegenerate && variant.status !== "generating" && (
          <button
            type="button"
            onClick={() => onRegenerate(variant.platformId)}
            className="inline-flex h-7 w-7 items-center justify-center rounded hover:bg-muted"
            aria-label={`Regenerate ${spec.label}`}
          >
            <ArrowsClockwise size={15} className="text-muted-foreground" />
          </button>
        )}
      </div>
    </div>
  );
}
```

### Step 2: Create `components/aspect-ratio-grid/aspect-ratio-grid.tsx`

```typescript
"use client";

import { useId, useState } from "react";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { cn } from "@src/lib/utils";
import {
  AspectRatioCard,
  type ImageVariant,
} from "./aspect-ratio-card";
import type { PlatformId } from "@src/lib/platform-specs";

type AspectRatioGridProps = {
  variants: ImageVariant[];
  onDownload?: (variant: ImageVariant) => void;
  onDownloadAll?: () => void;
  onRegenerate?: (platformId: PlatformId) => void;
  showComparison?: boolean;
  className?: string;
};

export function AspectRatioGrid({
  variants,
  onDownload,
  onDownloadAll,
  onRegenerate,
  showComparison = false,
  className,
}: AspectRatioGridProps) {
  const listId = useId();
  const switchId = useId();
  const [comparisonActive, setComparisonActive] = useState(false);

  const effectiveComparison = showComparison && comparisonActive;

  return (
    <div className={cn("flex flex-col gap-4", className)}>
      {/* Top bar */}
      <div className="flex items-center justify-between gap-4">
        {showComparison && (
          <div className="flex items-center gap-2">
            <Switch
              id={switchId}
              checked={comparisonActive}
              onCheckedChange={setComparisonActive}
            />
            <Label htmlFor={switchId} className="text-sm text-muted-foreground">
              Compare
            </Label>
          </div>
        )}
        {!showComparison && <div />}
        {onDownloadAll && (
          <Button variant="outline" size="sm" onClick={onDownloadAll}>
            Download All as ZIP
          </Button>
        )}
      </div>

      {/* Grid */}
      <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
        {variants.map((variant) => (
          <AspectRatioCard
            key={`${listId}-${variant.platformId}`}
            variant={variant}
            showComparison={effectiveComparison}
            onDownload={onDownload}
            onRegenerate={onRegenerate}
          />
        ))}
      </div>
    </div>
  );
}
```

## Usage

```typescript
import { AspectRatioGrid } from "@/components/aspect-ratio-grid/aspect-ratio-grid";
import { downloadAsZip } from "@src/lib/zip-download/client";

const variants = [
  {
    platformId: "instagram-square",
    url: "https://cdn.example.com/ig-square.jpg",
    originalUrl: "https://cdn.example.com/original.jpg",
    status: "done",
  },
  {
    platformId: "instagram-story",
    url: "",
    status: "generating",
  },
  {
    platformId: "twitter-post",
    url: "",
    status: "pending",
  },
];

export default function ReformatsPage() {
  async function handleDownloadAll() {
    const done = variants.filter((v) => v.status === "done");
    await downloadAsZip(
      done.map((v) => ({ url: v.url, filename: `${v.platformId}.jpg` })),
      "platform-exports"
    );
  }

  return (
    <AspectRatioGrid
      variants={variants}
      showComparison
      onDownloadAll={handleDownloadAll}
      onRegenerate={(platformId) => console.log("regenerate", platformId)}
    />
  );
}
```

## Platform Spec Contract

The `platform-specs` skill must export:

```typescript
export type PlatformSpec = {
  id: PlatformId;
  label: string;
  width: number;
  height: number;
  safeZone?: {
    top: number;
    bottom: number;
    left: number;
    right: number;
  };
};

export function getPlatform(id: PlatformId): PlatformSpec;
```

Safe zone values are in pixels and are converted to percentages inside `AspectRatioCard` for responsive overlay positioning.

## Acceptance Criteria

- Grid renders 2 / 3 / 4 columns at `sm` / `md` / `lg` breakpoints
- "pending" cards show platform label on a muted background
- "generating" cards show an animated pulse shimmer
- "done" cards render the image with `object-cover`
- "error" cards show a red border, error message, and Retry button that calls `onRegenerate`
- When `showComparison` is false, the Compare toggle is not rendered
- When Compare toggle is on and `originalUrl` is present, dragging or hovering the card moves a clip-path divider between original and generated images
- Safe zone dashed border is rendered as an absolute inset overlay when `spec.safeZone` is defined and status is "done"
- "Download All as ZIP" button is rendered only when `onDownloadAll` is provided
- Each card key is stable and not based on array index
- `tsc` passes with no errors
- Build succeeds (`bun run build`)
