---
name: pdf-viewer
description: PDF renderer with page navigation, zoom, and programmatic highlight — the core of DEBRIEF's citation UX. Use this skill when the user says "add pdf viewer", "pdf rendering", "pdf highlights", "view pdf", or "citation viewer".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: [add-shadcn]
---

# PDF Viewer Skill

Renders PDFs with page navigation, zoom controls, and programmatic highlight overlays. Designed as the citation UX backbone: highlights are positioned as percentage-based overlays on the page canvas, and an imperative ref API lets parent components scroll to any highlight by ID.

## Prerequisites

- Next.js app with App Router (no `src/` directory)
- `add-shadcn` skill applied

## Installation

```bash
bun add react-pdf pdfjs-dist
```

## What Gets Created

```
components/
└── pdf-viewer/
    ├── pdf-viewer.tsx          # Main component (use client, react-pdf)
    ├── pdf-viewer-wrapper.tsx  # SSR-safe wrapper with dynamic import + ssr:false
    └── use-pdf-viewer.ts       # Hook for highlight state management
```

Plus a required modification to `next.config.ts`.

## Setup Steps

### Step 1: Update `next.config.ts`

Add `pdfjs-dist` to `transpilePackages` so Next.js compiles the ESM worker correctly.

Find this in `next.config.ts`:

```typescript
const nextConfig: NextConfig = {
```

Replace with:

```typescript
const nextConfig: NextConfig = {
  transpilePackages: ["pdfjs-dist"],
```

### Step 2: Create `components/pdf-viewer/use-pdf-viewer.ts`

```typescript
import { useState, useCallback } from "react";

export type PdfHighlight = {
  id: string;
  page: number; // 1-indexed
  top: number; // percentage 0-100
  left: number; // percentage 0-100
  width: number; // percentage 0-100
  height: number; // percentage 0-100
  color?: string; // default "rgba(255, 235, 59, 0.4)"
};

export type PdfViewerHandle = {
  scrollToHighlight: (id: string) => void;
  goToPage: (page: number) => void;
};

type UsePdfViewerOptions = {
  initialPage?: number;
  initialZoom?: number;
};

type UsePdfViewerReturn = {
  currentPage: number;
  zoom: number;
  highlights: PdfHighlight[];
  activeHighlightId: string | undefined;
  totalPages: number;
  setTotalPages: (n: number) => void;
  goToPage: (page: number) => void;
  nextPage: () => void;
  prevPage: () => void;
  zoomIn: () => void;
  zoomOut: () => void;
  resetZoom: () => void;
  addHighlight: (highlight: PdfHighlight) => void;
  removeHighlight: (id: string) => void;
  clearHighlights: () => void;
  setActiveHighlightId: (id: string | undefined) => void;
};

const ZOOM_STEP = 0.25;
const ZOOM_MIN = 0.5;
const ZOOM_MAX = 2.0;

export function usePdfViewer(options: UsePdfViewerOptions = {}): UsePdfViewerReturn {
  const { initialPage = 1, initialZoom = 1.0 } = options;

  const [currentPage, setCurrentPage] = useState(initialPage);
  const [totalPages, setTotalPages] = useState(0);
  const [zoom, setZoom] = useState(initialZoom);
  const [highlights, setHighlights] = useState<PdfHighlight[]>([]);
  const [activeHighlightId, setActiveHighlightId] = useState<string | undefined>(undefined);

  const goToPage = useCallback(
    (page: number) => {
      if (totalPages === 0) return;
      setCurrentPage(Math.min(Math.max(1, page), totalPages));
    },
    [totalPages]
  );

  const nextPage = useCallback(() => {
    setCurrentPage((prev) => Math.min(prev + 1, totalPages));
  }, [totalPages]);

  const prevPage = useCallback(() => {
    setCurrentPage((prev) => Math.max(prev - 1, 1));
  }, []);

  const zoomIn = useCallback(() => {
    setZoom((prev) => Math.min(parseFloat((prev + ZOOM_STEP).toFixed(2)), ZOOM_MAX));
  }, []);

  const zoomOut = useCallback(() => {
    setZoom((prev) => Math.max(parseFloat((prev - ZOOM_STEP).toFixed(2)), ZOOM_MIN));
  }, []);

  const resetZoom = useCallback(() => {
    setZoom(1.0);
  }, []);

  const addHighlight = useCallback((highlight: PdfHighlight) => {
    setHighlights((prev) => {
      const exists = prev.some((h) => h.id === highlight.id);
      if (exists) return prev;
      return [...prev, highlight];
    });
  }, []);

  const removeHighlight = useCallback((id: string) => {
    setHighlights((prev) => prev.filter((h) => h.id !== id));
  }, []);

  const clearHighlights = useCallback(() => {
    setHighlights([]);
  }, []);

  return {
    currentPage,
    zoom,
    highlights,
    activeHighlightId,
    totalPages,
    setTotalPages,
    goToPage,
    nextPage,
    prevPage,
    zoomIn,
    zoomOut,
    resetZoom,
    addHighlight,
    removeHighlight,
    clearHighlights,
    setActiveHighlightId,
  };
}
```

### Step 3: Create `components/pdf-viewer/pdf-viewer.tsx`

```typescript
"use client";

import {
  useState,
  useEffect,
  useRef,
  useImperativeHandle,
  forwardRef,
  useCallback,
  useId,
} from "react";
import { Document, Page, pdfjs } from "react-pdf";
import { MagnifyingGlassMinus, MagnifyingGlassPlus, ArrowLeft, ArrowRight } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import type { PdfHighlight, PdfViewerHandle } from "./use-pdf-viewer";

import "react-pdf/dist/Page/AnnotationLayer.css";
import "react-pdf/dist/Page/TextLayer.css";

pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  "pdfjs-dist/build/pdf.worker.min.mjs",
  import.meta.url
).toString();

type PdfViewerProps = {
  url: string;
  highlights?: PdfHighlight[];
  activeHighlightId?: string;
  onPageChange?: (page: number) => void;
  className?: string;
};

const ZOOM_STEP = 0.25;
const ZOOM_MIN = 0.5;
const ZOOM_MAX = 2.0;
const BASE_PAGE_WIDTH = 800;

export const PdfViewer = forwardRef<PdfViewerHandle, PdfViewerProps>(
  function PdfViewer(
    { url, highlights = [], activeHighlightId, onPageChange, className },
    ref
  ) {
    const listId = useId();
    const [totalPages, setTotalPages] = useState(0);
    const [currentPage, setCurrentPage] = useState(1);
    const [zoom, setZoom] = useState(1.0);
    const containerRef = useRef<HTMLDivElement>(null);
    const highlightRefs = useRef<Map<string, HTMLDivElement>>(new Map());

    const goToPage = useCallback(
      (page: number) => {
        const clamped = Math.min(Math.max(1, page), totalPages || 1);
        setCurrentPage(clamped);
        onPageChange?.(clamped);
      },
      [totalPages, onPageChange]
    );

    const scrollToHighlight = useCallback((id: string) => {
      const el = highlightRefs.current.get(id);
      if (el) {
        el.scrollIntoView({ behavior: "smooth", block: "center" });
      }
    }, []);

    useImperativeHandle(ref, () => ({ scrollToHighlight, goToPage }), [
      scrollToHighlight,
      goToPage,
    ]);

    useEffect(() => {
      if (activeHighlightId) {
        const highlight = highlights.find((h) => h.id === activeHighlightId);
        if (highlight && highlight.page !== currentPage) {
          goToPage(highlight.page);
        }
        const tryScroll = () => {
          const el = highlightRefs.current.get(activeHighlightId);
          if (el) {
            el.scrollIntoView({ behavior: "smooth", block: "center" });
          }
        };
        const timer = setTimeout(tryScroll, 150);
        return () => clearTimeout(timer);
      }
    }, [activeHighlightId, highlights, currentPage, goToPage]);

    const pageHighlights = highlights.filter((h) => h.page === currentPage);

    const zoomIn = () =>
      setZoom((prev) => Math.min(parseFloat((prev + ZOOM_STEP).toFixed(2)), ZOOM_MAX));
    const zoomOut = () =>
      setZoom((prev) => Math.max(parseFloat((prev - ZOOM_STEP).toFixed(2)), ZOOM_MIN));
    const resetZoom = () => setZoom(1.0);

    return (
      <div className={cn("flex flex-col bg-muted rounded-lg overflow-hidden", className)}>
        {/* Page canvas area */}
        <div
          ref={containerRef}
          className="flex-1 overflow-auto flex justify-center p-4 min-h-0"
        >
          <div className="relative inline-block">
            <Document
              file={url}
              onLoadSuccess={({ numPages }) => setTotalPages(numPages)}
              loading={
                <div className="flex items-center justify-center w-[800px] h-[1000px] bg-card border border-border rounded">
                  <span className="text-muted-foreground text-sm">Loading PDF...</span>
                </div>
              }
              error={
                <div className="flex items-center justify-center w-[800px] h-[1000px] bg-card border border-border rounded">
                  <span className="text-destructive text-sm">Failed to load PDF.</span>
                </div>
              }
            >
              <Page
                pageNumber={currentPage}
                width={BASE_PAGE_WIDTH * zoom}
                renderTextLayer
                renderAnnotationLayer
              />
            </Document>

            {/* Highlight overlays */}
            {pageHighlights.map((highlight) => {
              const key = `${listId}-${highlight.id}`;
              const isActive = highlight.id === activeHighlightId;
              return (
                <div
                  key={key}
                  ref={(el) => {
                    if (el) {
                      highlightRefs.current.set(highlight.id, el);
                    } else {
                      highlightRefs.current.delete(highlight.id);
                    }
                  }}
                  style={{
                    position: "absolute",
                    top: `${highlight.top}%`,
                    left: `${highlight.left}%`,
                    width: `${highlight.width}%`,
                    height: `${highlight.height}%`,
                    backgroundColor: highlight.color ?? "rgba(255, 235, 59, 0.4)",
                    border: isActive ? "2px solid rgba(255, 193, 7, 0.9)" : "none",
                    borderRadius: 2,
                    pointerEvents: "none",
                    zIndex: 10,
                    transition: "border 0.15s ease",
                  }}
                  aria-label={`Highlight ${highlight.id}`}
                />
              );
            })}
          </div>
        </div>

        {/* Bottom controls */}
        <div className="flex items-center justify-between gap-2 px-4 py-2 border-t border-border bg-card shrink-0">
          {/* Page navigation */}
          <div className="flex items-center gap-2">
            <Button
              type="button"
              variant="outline"
              size="icon"
              onClick={() => goToPage(currentPage - 1)}
              disabled={currentPage <= 1}
              aria-label="Previous page"
            >
              <ArrowLeft size={16} />
            </Button>
            <span className="text-sm text-foreground min-w-[80px] text-center">
              Page {currentPage} of {totalPages || "—"}
            </span>
            <Button
              type="button"
              variant="outline"
              size="icon"
              onClick={() => goToPage(currentPage + 1)}
              disabled={currentPage >= totalPages}
              aria-label="Next page"
            >
              <ArrowRight size={16} />
            </Button>
          </div>

          {/* Zoom controls */}
          <div className="flex items-center gap-2">
            <Button
              type="button"
              variant="outline"
              size="icon"
              onClick={zoomOut}
              disabled={zoom <= ZOOM_MIN}
              aria-label="Zoom out"
            >
              <MagnifyingGlassMinus size={16} />
            </Button>
            <button
              type="button"
              onClick={resetZoom}
              className="text-sm text-muted-foreground hover:text-foreground transition-colors min-w-[52px] text-center cursor-pointer"
              aria-label="Reset zoom"
            >
              {Math.round(zoom * 100)}%
            </button>
            <Button
              type="button"
              variant="outline"
              size="icon"
              onClick={zoomIn}
              disabled={zoom >= ZOOM_MAX}
              aria-label="Zoom in"
            >
              <MagnifyingGlassPlus size={16} />
            </Button>
          </div>
        </div>
      </div>
    );
  }
);
```

### Step 4: Create `components/pdf-viewer/pdf-viewer-wrapper.tsx`

```typescript
"use client";

import dynamic from "next/dynamic";
import type { ComponentProps } from "react";
import type { PdfViewerHandle } from "./use-pdf-viewer";

const PdfViewerClient = dynamic(
  () => import("./pdf-viewer").then((m) => m.PdfViewer),
  {
    ssr: false,
    loading: () => (
      <div className="flex items-center justify-center h-64 bg-muted rounded-lg">
        <span className="text-muted-foreground text-sm">Loading viewer...</span>
      </div>
    ),
  }
);

type PdfViewerWrapperProps = ComponentProps<typeof PdfViewerClient> & {
  ref?: React.Ref<PdfViewerHandle>;
};

export function PdfViewerWrapper({ ref, ...props }: PdfViewerWrapperProps) {
  return <PdfViewerClient ref={ref} {...props} />;
}
```

## Usage

```tsx
"use client";

import { useRef } from "react";
import { PdfViewerWrapper } from "@/components/pdf-viewer/pdf-viewer-wrapper";
import { usePdfViewer } from "@/components/pdf-viewer/use-pdf-viewer";
import type { PdfViewerHandle } from "@/components/pdf-viewer/use-pdf-viewer";

const DEMO_HIGHLIGHTS = [
  {
    id: "highlight-1",
    page: 1,
    top: 20,
    left: 10,
    width: 80,
    height: 5,
  },
  {
    id: "highlight-2",
    page: 1,
    top: 40,
    left: 10,
    width: 60,
    height: 5,
    color: "rgba(144, 238, 144, 0.5)",
  },
];

export function CitationViewer() {
  const viewerRef = useRef<PdfViewerHandle>(null);
  const { highlights, activeHighlightId, setActiveHighlightId } = usePdfViewer();

  const handleActivate = (id: string) => {
    setActiveHighlightId(id);
    viewerRef.current?.scrollToHighlight(id);
  };

  return (
    <div className="flex gap-4 h-screen p-4">
      <div className="flex-1">
        <PdfViewerWrapper
          ref={viewerRef}
          url="/sample.pdf"
          highlights={DEMO_HIGHLIGHTS}
          activeHighlightId={activeHighlightId}
          onPageChange={(page) => console.log("page:", page)}
          className="h-full"
        />
      </div>
      <div className="w-64 flex flex-col gap-2">
        {DEMO_HIGHLIGHTS.map((h) => (
          <button
            key={h.id}
            type="button"
            onClick={() => handleActivate(h.id)}
            className="text-left px-3 py-2 rounded border border-border hover:bg-accent text-sm"
          >
            Jump to {h.id}
          </button>
        ))}
      </div>
    </div>
  );
}
```

## Acceptance Criteria

- `PdfViewerWrapper` renders without SSR errors (dynamic import with `ssr: false`)
- Page navigation increments and decrements `currentPage` correctly, clamped to 1–totalPages
- Zoom controls step by 0.25x, clamped to 0.5x–2.0x; click percentage label resets to 1.0x
- Highlight overlays render as absolutely-positioned divs on the page at the correct percentage-based coordinates
- `activeHighlightId` change auto-navigates to the correct page and scrolls the highlight into view
- Calling `ref.scrollToHighlight(id)` scrolls the container to the highlighted region
- Calling `ref.goToPage(n)` navigates to the specified page
- `usePdfViewer` hook correctly manages highlights array — add, remove, clear all work
- `tsc` passes with no errors
- Build succeeds
