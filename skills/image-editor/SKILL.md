---
name: image-editor
description: Canvas image editor with Konva.js — crop, resize, rotate, filters, brush masking, and layer compositing. Runs entirely client-side. Use this skill when the user says "add image editor", "setup canvas editor", "add konva", "image editing", or "photo editor".
author: "@mattwoodco"
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
dependencies: [add-shadcn]
---

# Image Editor (Konva.js)

Client-side image editor built with [Konva.js](https://konvajs.org) via `react-konva`. Non-destructive editing with crop, resize, rotate, flip, brightness/contrast/saturation filters, and brush-based masking for AI inpainting workflows. Exports flattened PNG/JPEG for downstream processing.

## Prerequisites

- Next.js app with App Router (no `src/` directory)
- `add-shadcn` skill applied (for UI components)

## Installation

```bash
bun add konva react-konva
bunx shadcn@latest add dialog slider label button separator scroll-area
```

## What Gets Created

```
lib/
└── image-editor/
    ├── types.ts                    # EditorState, Layer, Transform, FilterValues
    ├── filters.ts                  # Filter application helpers
    └── use-editor.ts               # React hook: load image, apply transforms, export
components/
└── image-editor/
    ├── editor-canvas.tsx           # Konva Stage with image rendering and transform handles
    ├── toolbar.tsx                 # Crop, resize, rotate, flip, filter controls
    ├── filter-panel.tsx            # Brightness, contrast, saturation, blur sliders
    ├── mask-tool.tsx               # Brush-based masking for inpainting regions
    └── editor-dialog.tsx           # Dialog wrapper that opens the editor
```

## Setup Steps

### Step 1: Create `lib/image-editor/types.ts`

```typescript
export type FilterValues = {
  brightness: number;
  contrast: number;
  saturation: number;
  blur: number;
};

export const DEFAULT_FILTERS: FilterValues = {
  brightness: 0,
  contrast: 0,
  saturation: 0,
  blur: 0,
};

export type Transform = {
  rotation: number;
  flipX: boolean;
  flipY: boolean;
  crop: {
    x: number;
    y: number;
    width: number;
    height: number;
  } | null;
};

export const DEFAULT_TRANSFORM: Transform = {
  rotation: 0,
  flipX: false,
  flipY: false,
  crop: null,
};

export type EditorState = {
  imageUrl: string;
  naturalWidth: number;
  naturalHeight: number;
  filters: FilterValues;
  transform: Transform;
  maskLines: MaskLine[];
  isDirty: boolean;
};

export type MaskLine = {
  points: number[];
  strokeWidth: number;
};

export type ExportOptions = {
  format: "png" | "jpeg";
  quality: number;
  maxWidth?: number;
  maxHeight?: number;
};
```

### Step 2: Create `lib/image-editor/filters.ts`

```typescript
import Konva from "konva";
import type { Filter } from "konva/lib/Node";
import type { FilterValues } from "./types";

export function applyFilters(
  node: Konva.Image,
  filters: FilterValues
): void {
  const activeFilters: Filter[] = [];

  if (filters.brightness !== 0) {
    activeFilters.push(Konva.Filters.Brighten);
    node.brightness(filters.brightness);
  }

  if (filters.contrast !== 0) {
    activeFilters.push(Konva.Filters.Contrast);
    node.contrast(filters.contrast * 100);
  }

  if (filters.blur > 0) {
    activeFilters.push(Konva.Filters.Blur);
    node.blurRadius(filters.blur * 10);
  }

  if (filters.saturation !== 0) {
    activeFilters.push(Konva.Filters.HSL);
    node.saturation(filters.saturation);
  }

  node.filters(activeFilters);
  node.cache();
}
```

### Step 3: Create `lib/image-editor/use-editor.ts`

```typescript
"use client";

import { useState, useCallback, useRef } from "react";
import type Konva from "konva";
import type { EditorState, FilterValues, MaskLine, ExportOptions } from "./types";
import { DEFAULT_FILTERS, DEFAULT_TRANSFORM } from "./types";

export function useEditor(imageUrl: string) {
  const stageRef = useRef<Konva.Stage>(null);
  const [state, setState] = useState<EditorState>({
    imageUrl,
    naturalWidth: 0,
    naturalHeight: 0,
    filters: DEFAULT_FILTERS,
    transform: DEFAULT_TRANSFORM,
    maskLines: [],
    isDirty: false,
  });

  const setNaturalSize = useCallback((width: number, height: number) => {
    setState((prev) => ({ ...prev, naturalWidth: width, naturalHeight: height }));
  }, []);

  const updateFilters = useCallback((filters: Partial<FilterValues>) => {
    setState((prev) => ({
      ...prev,
      filters: { ...prev.filters, ...filters },
      isDirty: true,
    }));
  }, []);

  const rotate = useCallback((degrees: number) => {
    setState((prev) => ({
      ...prev,
      transform: {
        ...prev.transform,
        rotation: (prev.transform.rotation + degrees) % 360,
      },
      isDirty: true,
    }));
  }, []);

  const flipHorizontal = useCallback(() => {
    setState((prev) => ({
      ...prev,
      transform: { ...prev.transform, flipX: !prev.transform.flipX },
      isDirty: true,
    }));
  }, []);

  const flipVertical = useCallback(() => {
    setState((prev) => ({
      ...prev,
      transform: { ...prev.transform, flipY: !prev.transform.flipY },
      isDirty: true,
    }));
  }, []);

  const addMaskLine = useCallback((line: MaskLine) => {
    setState((prev) => ({
      ...prev,
      maskLines: [...prev.maskLines, line],
      isDirty: true,
    }));
  }, []);

  const clearMask = useCallback(() => {
    setState((prev) => ({ ...prev, maskLines: [], isDirty: true }));
  }, []);

  const reset = useCallback(() => {
    setState((prev) => ({
      ...prev,
      filters: DEFAULT_FILTERS,
      transform: DEFAULT_TRANSFORM,
      maskLines: [],
      isDirty: false,
    }));
  }, []);

  const exportImage = useCallback(
    (options: ExportOptions = { format: "png", quality: 0.92 }): string | null => {
      const stage = stageRef.current;
      if (!stage) return null;

      return stage.toDataURL({
        mimeType: options.format === "jpeg" ? "image/jpeg" : "image/png",
        quality: options.quality,
        pixelRatio: 1,
      });
    },
    []
  );

  const exportMask = useCallback((): string | null => {
    const stage = stageRef.current;
    if (!stage) return null;

    // Find the mask layer and export just that
    const maskLayer = stage.findOne(".mask-layer");
    if (!maskLayer) return null;

    return maskLayer.toDataURL({
      mimeType: "image/png",
      pixelRatio: 1,
    });
  }, []);

  return {
    state,
    stageRef,
    setNaturalSize,
    updateFilters,
    rotate,
    flipHorizontal,
    flipVertical,
    addMaskLine,
    clearMask,
    reset,
    exportImage,
    exportMask,
  };
}
```

### Step 4: Create `components/image-editor/editor-canvas.tsx`

```typescript
"use client";

import { useEffect, useState, useRef, useCallback, useId, memo } from "react";
import { Stage, Layer, Image as KonvaImage, Line } from "react-konva";
import type Konva from "konva";
import { applyFilters } from "@/lib/image-editor/filters";
import type { EditorState, MaskLine } from "@/lib/image-editor/types";

type EditorCanvasProps = {
  state: EditorState;
  stageRef: React.RefObject<Konva.Stage | null>;
  onNaturalSize: (width: number, height: number) => void;
  onAddMaskLine: (line: MaskLine) => void;
  maskMode: boolean;
  brushSize: number;
  containerWidth: number;
  containerHeight: number;
};

export const EditorCanvas = memo(function EditorCanvas({
  state,
  stageRef,
  onNaturalSize,
  onAddMaskLine,
  maskMode,
  brushSize,
  containerWidth,
  containerHeight,
}: EditorCanvasProps) {
  const maskLineListId = useId();
  const [image, setImage] = useState<HTMLImageElement | null>(null);
  const imageRef = useRef<Konva.Image>(null);
  const isDrawing = useRef(false);
  const currentLine = useRef<number[]>([]);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    const img = new window.Image();
    img.crossOrigin = "anonymous";
    img.onload = () => {
      setImage(img);
      onNaturalSize(img.naturalWidth, img.naturalHeight);
    };
    img.src = state.imageUrl;
  }, [state.imageUrl, onNaturalSize]);

  useEffect(() => {
    if (imageRef.current && image) {
      applyFilters(imageRef.current, state.filters);
    }
  }, [state.filters, image]);

  // Calculate display dimensions to fit container
  const scale = image
    ? Math.min(containerWidth / image.naturalWidth, containerHeight / image.naturalHeight, 1)
    : 1;
  const displayWidth = image ? image.naturalWidth * scale : containerWidth;
  const displayHeight = image ? image.naturalHeight * scale : containerHeight;

  const handleMouseDown = useCallback(
    (e: Konva.KonvaEventObject<MouseEvent>) => {
      if (!maskMode) return;
      isDrawing.current = true;
      const pos = e.target.getStage()?.getPointerPosition();
      if (pos) {
        currentLine.current = [pos.x, pos.y];
      }
    },
    [maskMode]
  );

  const handleMouseMove = useCallback(
    (e: Konva.KonvaEventObject<MouseEvent>) => {
      if (!isDrawing.current || !maskMode) return;
      const pos = e.target.getStage()?.getPointerPosition();
      if (!pos) return;

      if (rafRef.current !== null) return;
      rafRef.current = requestAnimationFrame(() => {
        rafRef.current = null;
        currentLine.current = [...currentLine.current, pos.x, pos.y];
        stageRef.current?.batchDraw();
      });
    },
    [maskMode, stageRef]
  );

  const handleMouseUp = useCallback(() => {
    if (!isDrawing.current) return;
    isDrawing.current = false;
    if (currentLine.current.length > 0) {
      onAddMaskLine({
        points: currentLine.current,
        strokeWidth: brushSize,
      });
      currentLine.current = [];
    }
  }, [onAddMaskLine, brushSize]);

  return (
    <Stage
      ref={stageRef}
      width={displayWidth}
      height={displayHeight}
      scaleX={state.transform.flipX ? -scale : scale}
      scaleY={state.transform.flipY ? -scale : scale}
      offsetX={state.transform.flipX ? displayWidth / scale : 0}
      offsetY={state.transform.flipY ? displayHeight / scale : 0}
      rotation={state.transform.rotation}
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      style={{ cursor: maskMode ? "crosshair" : "default" }}
    >
      <Layer>
        {image && (
          <KonvaImage
            ref={imageRef}
            image={image}
            width={image.naturalWidth}
            height={image.naturalHeight}
          />
        )}
      </Layer>
      <Layer name="mask-layer">
        {state.maskLines.map((line, lineIdx) => (
          <Line
            key={`${maskLineListId}-${lineIdx}-${line.points.length}`}
            points={line.points}
            stroke="rgba(255, 0, 0, 0.5)"
            strokeWidth={line.strokeWidth}
            lineCap="round"
            lineJoin="round"
            globalCompositeOperation="source-over"
          />
        ))}
      </Layer>
    </Stage>
  );
});
```

### Step 5: Create `components/image-editor/toolbar.tsx`

```typescript
"use client";

import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { ArrowClockwise, ArrowCounterClockwise, ArrowsLeftRight, ArrowsDownUp, ArrowUUpLeft, DownloadSimple } from "@phosphor-icons/react";

type ToolbarProps = {
  onRotateLeft: () => void;
  onRotateRight: () => void;
  onFlipH: () => void;
  onFlipV: () => void;
  onReset: () => void;
  onExport: () => void;
  isDirty: boolean;
};

export function Toolbar({
  onRotateLeft,
  onRotateRight,
  onFlipH,
  onFlipV,
  onReset,
  onExport,
  isDirty,
}: ToolbarProps) {
  return (
    <div className="flex items-center gap-1 rounded-lg border bg-background p-1">
      <Button variant="ghost" size="icon" onClick={onRotateLeft} title="Rotate left">
        <ArrowCounterClockwise className="h-4 w-4" />
      </Button>
      <Button variant="ghost" size="icon" onClick={onRotateRight} title="Rotate right">
        <ArrowClockwise className="h-4 w-4" />
      </Button>
      <Separator orientation="vertical" className="mx-1 h-6" />
      <Button variant="ghost" size="icon" onClick={onFlipH} title="Flip horizontal">
        <ArrowsLeftRight className="h-4 w-4" />
      </Button>
      <Button variant="ghost" size="icon" onClick={onFlipV} title="Flip vertical">
        <ArrowsDownUp className="h-4 w-4" />
      </Button>
      <Separator orientation="vertical" className="mx-1 h-6" />
      <Button variant="ghost" size="icon" onClick={onReset} disabled={!isDirty} title="Reset">
        <ArrowUUpLeft className="h-4 w-4" />
      </Button>
      <Button variant="ghost" size="icon" onClick={onExport} title="Export">
        <DownloadSimple className="h-4 w-4" />
      </Button>
    </div>
  );
}
```

### Step 6: Create `components/image-editor/filter-panel.tsx`

```typescript
"use client";

import { Label } from "@/components/ui/label";
import { Slider } from "@/components/ui/slider";
import type { FilterValues } from "@/lib/image-editor/types";

type FilterPanelProps = {
  filters: FilterValues;
  onUpdate: (filters: Partial<FilterValues>) => void;
};

const FILTER_CONFIG = [
  { key: "brightness" as const, label: "Brightness", min: -1, max: 1, step: 0.01 },
  { key: "contrast" as const, label: "Contrast", min: -1, max: 1, step: 0.01 },
  { key: "saturation" as const, label: "Saturation", min: -2, max: 2, step: 0.01 },
  { key: "blur" as const, label: "Blur", min: 0, max: 2, step: 0.01 },
];

export function FilterPanel({ filters, onUpdate }: FilterPanelProps) {
  return (
    <div className="space-y-4 p-4">
      <h3 className="text-sm font-medium">Adjustments</h3>
      {FILTER_CONFIG.map((config) => (
        <div key={config.key} className="space-y-2">
          <div className="flex items-center justify-between">
            <Label className="text-xs">{config.label}</Label>
            <span className="text-xs text-muted-foreground">
              {filters[config.key].toFixed(2)}
            </span>
          </div>
          <Slider
            min={config.min}
            max={config.max}
            step={config.step}
            value={[filters[config.key]]}
            onValueChange={(val) => {
              const num = Array.isArray(val) ? val[0] : val;
              onUpdate({ [config.key]: num });
            }}
          />
        </div>
      ))}
    </div>
  );
}
```

### Step 7: Create `components/image-editor/mask-tool.tsx`

```typescript
"use client";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Slider } from "@/components/ui/slider";
import { PaintBrush, Eraser } from "@phosphor-icons/react";

type MaskToolProps = {
  maskMode: boolean;
  brushSize: number;
  onToggleMask: () => void;
  onBrushSizeChange: (size: number) => void;
  onClearMask: () => void;
  hasMask: boolean;
};

export function MaskTool({
  maskMode,
  brushSize,
  onToggleMask,
  onBrushSizeChange,
  onClearMask,
  hasMask,
}: MaskToolProps) {
  return (
    <div className="space-y-4 p-4">
      <h3 className="text-sm font-medium">Mask Tool</h3>
      <p className="text-xs text-muted-foreground">
        Paint regions for AI inpainting. Masked areas will be regenerated.
      </p>
      <div className="flex gap-2">
        <Button
          variant={maskMode ? "default" : "outline"}
          size="sm"
          onClick={onToggleMask}
          className="flex-1"
        >
          <PaintBrush className="mr-2 h-4 w-4" />
          {maskMode ? "Drawing" : "Draw Mask"}
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={onClearMask}
          disabled={!hasMask}
        >
          <Eraser className="mr-2 h-4 w-4" />
          Clear
        </Button>
      </div>
      {maskMode && (
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <Label className="text-xs">Brush Size</Label>
            <span className="text-xs text-muted-foreground">{brushSize}px</span>
          </div>
          <Slider
            min={5}
            max={100}
            step={1}
            value={[brushSize]}
            onValueChange={(val) => {
              const num = Array.isArray(val) ? val[0] : val;
              onBrushSizeChange(num);
            }}
          />
        </div>
      )}
    </div>
  );
}
```

### Step 8: Create `components/image-editor/editor-dialog.tsx`

```typescript
"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import dynamic from "next/dynamic";
import { useEditor } from "@/lib/image-editor/use-editor";
import { Toolbar } from "./toolbar";

const EditorCanvas = dynamic(
  () => import("./editor-canvas").then((m) => ({ default: m.EditorCanvas })),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-full items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-primary border-t-transparent" />
      </div>
    ),
  },
);
import { FilterPanel } from "./filter-panel";
import { MaskTool } from "./mask-tool";

type EditorDialogProps = {
  imageUrl: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (dataUrl: string) => void;
  onExportMask?: (maskDataUrl: string) => void;
};

export function EditorDialog({
  imageUrl,
  open,
  onOpenChange,
  onSave,
  onExportMask,
}: EditorDialogProps) {
  const editor = useEditor(imageUrl);
  const [maskMode, setMaskMode] = useState(false);
  const [brushSize, setBrushSize] = useState(20);
  const containerRef = useRef<HTMLDivElement>(null);
  const [containerSize, setContainerSize] = useState({ width: 800, height: 600 });

  useEffect(() => {
    if (!containerRef.current) return;
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (entry) {
        setContainerSize({
          width: entry.contentRect.width,
          height: entry.contentRect.height,
        });
      }
    });
    observer.observe(containerRef.current);
    return () => observer.disconnect();
  }, []);

  const handleExport = useCallback(() => {
    const dataUrl = editor.exportImage({ format: "png", quality: 0.92 });
    if (dataUrl) {
      onSave(dataUrl);
      onOpenChange(false);
    }
  }, [editor, onSave, onOpenChange]);

  const handleExportMask = useCallback(() => {
    const maskDataUrl = editor.exportMask();
    if (maskDataUrl && onExportMask) {
      onExportMask(maskDataUrl);
    }
  }, [editor, onExportMask]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-[95vw] h-[90vh] flex flex-col p-0">
        <DialogHeader className="px-6 pt-6 pb-2">
          <DialogTitle>Image Editor</DialogTitle>
        </DialogHeader>

        <div className="flex items-center justify-center px-6">
          <Toolbar
            onRotateLeft={() => editor.rotate(-90)}
            onRotateRight={() => editor.rotate(90)}
            onFlipH={editor.flipHorizontal}
            onFlipV={editor.flipVertical}
            onReset={editor.reset}
            onExport={handleExport}
            isDirty={editor.state.isDirty}
          />
        </div>

        <div className="flex flex-1 min-h-0 px-6 pb-6 gap-4">
          {/* Canvas area */}
          <div ref={containerRef} className="flex-1 flex items-center justify-center bg-muted/30 rounded-lg overflow-hidden">
            <EditorCanvas
              state={editor.state}
              stageRef={editor.stageRef}
              onNaturalSize={editor.setNaturalSize}
              onAddMaskLine={editor.addMaskLine}
              maskMode={maskMode}
              brushSize={brushSize}
              containerWidth={containerSize.width}
              containerHeight={containerSize.height}
            />
          </div>

          {/* Side panel */}
          <ScrollArea className="w-64 shrink-0 rounded-lg border">
            <FilterPanel
              filters={editor.state.filters}
              onUpdate={editor.updateFilters}
            />
            <Separator />
            <MaskTool
              maskMode={maskMode}
              brushSize={brushSize}
              onToggleMask={() => setMaskMode((prev) => !prev)}
              onBrushSizeChange={setBrushSize}
              onClearMask={editor.clearMask}
              hasMask={editor.state.maskLines.length > 0}
            />
            {editor.state.maskLines.length > 0 && onExportMask && (
              <div className="p-4">
                <Button variant="outline" size="sm" onClick={handleExportMask} className="w-full">
                  Export Mask
                </Button>
              </div>
            )}
          </ScrollArea>
        </div>
      </DialogContent>
    </Dialog>
  );
}
```

## Usage

### Open the editor

```tsx
"use client";

import { useState } from "react";
import { EditorDialog } from "@/components/image-editor/editor-dialog";
import { Button } from "@/components/ui/button";

export function ImageWithEditor({ imageUrl }: { imageUrl: string }) {
  const [open, setOpen] = useState(false);

  return (
    <>
      <img src={imageUrl} alt="Preview" className="rounded-lg" />
      <Button onClick={() => setOpen(true)}>Edit</Button>
      <EditorDialog
        imageUrl={imageUrl}
        open={open}
        onOpenChange={setOpen}
        onSave={(dataUrl) => {
          // Upload the edited image
          console.log("Saved:", dataUrl.slice(0, 50));
        }}
        onExportMask={(maskDataUrl) => {
          // Use mask for inpainting
          console.log("Mask:", maskDataUrl.slice(0, 50));
        }}
      />
    </>
  );
}
```

## Acceptance Criteria

- EditorDialog opens with the source image rendered on a Konva canvas
- Rotate 90 degrees left/right works
- Flip horizontal/vertical works
- Brightness, contrast, saturation, blur sliders apply in real-time
- Brush mask tool paints red overlay regions
- Export produces a valid PNG data URL
- Export mask produces a separate mask image
- Reset clears all transforms and filters
- Canvas scales to fit container on window resize
- `tsc` passes with no errors
- Build succeeds
