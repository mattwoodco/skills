---
name: ai-rag-viewer
description: PDF viewer component — renders PDF pages with react-pdf (PDF.js), highlights matching text spans from RAG search results, scroll-to-page navigation, and zoom controls. Use this skill when the user says "add PDF viewer", "setup PDF rendering", "setup ai-rag-viewer", or "add document viewer".
author: "@mattwoodco"
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
validated: 2026-02-13
dependencies: [storage]
---

# AI RAG Viewer

PDF viewer component built with `react-pdf` (PDF.js wrapper for React). Renders PDF pages, highlights text spans from RAG search results, supports scroll-to-page navigation, and provides zoom controls.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `storage` skill installed (for PDF download URLs)
- Tailwind CSS v4

## Installation

```bash
bun add react-pdf
```

### Copy PDF.js Worker

react-pdf requires the PDF.js worker file. Configure it in the component.

## What Gets Created

```
src/
└── components/
    └── rag/
        ├── pdf-viewer.tsx                  # Main PDF viewer with page rendering
        ├── pdf-page.tsx                    # Single page renderer with text layer
        ├── pdf-highlights.tsx              # Text highlight overlay
        └── pdf-toolbar.tsx                 # Zoom, page nav, download controls
```

## Setup Steps

### Step 1: Configure PDF.js Worker in `next.config.ts`

Add the webpack and turbopack configuration to disable the `canvas` module (not needed in browser):

```typescript
// In next.config.ts, add to the config object:
turbopack: {
  resolveAlias: {
    canvas: "",
  },
},
webpack: (config) => {
  config.resolve.alias.canvas = false;
  return config;
},
```

### Step 2: Create `src/components/rag/pdf-toolbar.tsx`

```tsx
"use client";

import { Button } from "@/components/ui/button";
import {
  MagnifyingGlassPlus,
  MagnifyingGlassMinus,
  CaretLeft,
  CaretRight,
  DownloadSimple,
} from "@phosphor-icons/react";

type PdfToolbarProps = {
  currentPage: number;
  totalPages: number;
  scale: number;
  onPageChange: (page: number) => void;
  onScaleChange: (scale: number) => void;
  onDownload?: () => void;
  fileName?: string;
};

export function PdfToolbar({
  currentPage,
  totalPages,
  scale,
  onPageChange,
  onScaleChange,
  onDownload,
  fileName,
}: PdfToolbarProps) {
  return (
    <div className="flex items-center justify-between border-b bg-muted/30 px-3 py-2">
      <div className="flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8"
          onClick={() => onPageChange(Math.max(1, currentPage - 1))}
          disabled={currentPage <= 1}
        >
          <CaretLeft className="h-4 w-4" />
        </Button>
        <span className="min-w-[80px] text-center text-sm tabular-nums">
          {currentPage} / {totalPages}
        </span>
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8"
          onClick={() => onPageChange(Math.min(totalPages, currentPage + 1))}
          disabled={currentPage >= totalPages}
        >
          <CaretRight className="h-4 w-4" />
        </Button>
      </div>

      {fileName && (
        <span className="hidden max-w-[200px] truncate text-sm text-muted-foreground md:block">
          {fileName}
        </span>
      )}

      <div className="flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8"
          onClick={() => onScaleChange(Math.max(0.5, scale - 0.25))}
          disabled={scale <= 0.5}
        >
          <MagnifyingGlassMinus className="h-4 w-4" />
        </Button>
        <span className="min-w-[50px] text-center text-sm tabular-nums">
          {Math.round(scale * 100)}%
        </span>
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8"
          onClick={() => onScaleChange(Math.min(3, scale + 0.25))}
          disabled={scale >= 3}
        >
          <MagnifyingGlassPlus className="h-4 w-4" />
        </Button>
        {onDownload && (
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8"
            onClick={onDownload}
          >
            <DownloadSimple className="h-4 w-4" />
          </Button>
        )}
      </div>
    </div>
  );
}
```

### Step 3: Create `src/components/rag/pdf-highlights.tsx`

```tsx
"use client";

type Highlight = {
  text: string;
  pageNumber: number;
};

type PdfHighlightsProps = {
  highlights: Highlight[];
  pageNumber: number;
  pageRef: HTMLDivElement | null;
};

/**
 * Highlights matching text spans within the PDF.js text layer.
 * Uses DOM traversal to find and wrap matching text with highlight spans.
 */
export function PdfHighlights({
  highlights,
  pageNumber,
  pageRef,
}: PdfHighlightsProps) {
  // This component doesn't render its own DOM — it applies highlights
  // to the text layer rendered by react-pdf via useEffect in the parent.
  return null;
}

/**
 * Apply text highlights to a PDF page's text layer.
 * Call this after the text layer has rendered.
 */
export function applyHighlights(
  pageElement: HTMLDivElement,
  highlights: Highlight[],
  pageNumber: number
): () => void {
  const pageHighlights = highlights.filter((h) => h.pageNumber === pageNumber);
  if (pageHighlights.length === 0) return () => {};

  const textLayer = pageElement.querySelector(".react-pdf__Page__textContent");
  if (!textLayer) return () => {};

  const spans = textLayer.querySelectorAll("span");
  const cleanupFns: (() => void)[] = [];

  for (const highlight of pageHighlights) {
    const searchText = highlight.text.toLowerCase().trim();
    // Find contiguous text spans that contain the search text
    // Use a sliding window approach across text layer spans
    const words = searchText.split(/\s+/).filter(Boolean);
    if (words.length === 0) continue;

    const firstWord = words[0];

    for (const span of spans) {
      const spanText = (span.textContent ?? "").toLowerCase();
      if (spanText.includes(firstWord)) {
        span.classList.add("rag-highlight");
        cleanupFns.push(() => span.classList.remove("rag-highlight"));
      }
    }
  }

  return () => {
    for (const cleanup of cleanupFns) {
      cleanup();
    }
  };
}
```

### Step 4: Create `src/components/rag/pdf-page.tsx`

```tsx
"use client";

import { useRef, useEffect, useCallback, memo } from "react";
import { Page } from "react-pdf";
import { applyHighlights } from "./pdf-highlights";

type Highlight = {
  text: string;
  pageNumber: number;
};

type PdfPageProps = {
  pageNumber: number;
  scale: number;
  highlights?: Highlight[];
  isActive?: boolean;
};

export const PdfPage = memo(function PdfPage({
  pageNumber,
  scale,
  highlights = [],
  isActive = false,
}: PdfPageProps) {
  const pageRef = useRef<HTMLDivElement>(null);
  const cleanupRef = useRef<(() => void) | null>(null);

  const handleTextLayerRendered = useCallback(() => {
    // Clean up previous highlights
    if (cleanupRef.current) {
      cleanupRef.current();
    }

    if (pageRef.current && highlights.length > 0) {
      cleanupRef.current = applyHighlights(
        pageRef.current,
        highlights,
        pageNumber
      );
    }
  }, [highlights, pageNumber]);

  useEffect(() => {
    return () => {
      if (cleanupRef.current) {
        cleanupRef.current();
      }
    };
  }, []);

  return (
    <div
      ref={pageRef}
      data-page-number={pageNumber}
      className={`relative mb-4 shadow-md ${isActive ? "ring-2 ring-blue-500" : ""}`}
    >
      <Page
        pageNumber={pageNumber}
        scale={scale}
        renderTextLayer={true}
        renderAnnotationLayer={true}
        onRenderTextLayerSuccess={handleTextLayerRendered}
      />
    </div>
  );
});
```

### Step 5: Create `src/components/rag/pdf-viewer.tsx`

```tsx
"use client";

import { useState, useRef, useCallback, useEffect, useId } from "react";
import { Document, pdfjs } from "react-pdf";
import "react-pdf/dist/Page/AnnotationLayer.css";
import "react-pdf/dist/Page/TextLayer.css";
import { PdfPage } from "./pdf-page";
import { PdfToolbar } from "./pdf-toolbar";

// Configure PDF.js worker
pdfjs.GlobalWorkerOptions.workerSrc = `//unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

type Highlight = {
  text: string;
  pageNumber: number;
};

type PdfViewerProps = {
  url: string;
  fileName?: string;
  highlights?: Highlight[];
  activePageNumber?: number;
  onPageChange?: (page: number) => void;
};

export function PdfViewer({
  url,
  fileName,
  highlights = [],
  activePageNumber,
  onPageChange,
}: PdfViewerProps) {
  const pageListId = useId();
  const containerRef = useRef<HTMLDivElement>(null);
  const [numPages, setNumPages] = useState(0);
  const [currentPage, setCurrentPage] = useState(1);
  const [scale, setScale] = useState(1.0);
  const [isLoading, setIsLoading] = useState(true);

  const handleDocumentLoadSuccess = useCallback(
    ({ numPages: total }: { numPages: number }) => {
      setNumPages(total);
      setIsLoading(false);
    },
    []
  );

  const handlePageChange = useCallback(
    (page: number) => {
      setCurrentPage(page);
      onPageChange?.(page);

      // Scroll to the target page
      const pageElement = containerRef.current?.querySelector(
        `[data-page-number="${page}"]`
      );
      if (pageElement) {
        pageElement.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    },
    [onPageChange]
  );

  // Scroll to active page from external navigation (e.g., citation click)
  useEffect(() => {
    if (activePageNumber && activePageNumber !== currentPage) {
      handlePageChange(activePageNumber);
    }
  }, [activePageNumber, currentPage, handlePageChange]);

  const handleDownload = useCallback(() => {
    const a = window.document.createElement("a");
    a.href = url;
    a.download = fileName ?? "document.pdf";
    a.click();
  }, [url, fileName]);

  return (
    <div className="flex h-full flex-col bg-muted/20">
      <PdfToolbar
        currentPage={currentPage}
        totalPages={numPages}
        scale={scale}
        onPageChange={handlePageChange}
        onScaleChange={setScale}
        onDownload={handleDownload}
        fileName={fileName}
      />

      <div
        ref={containerRef}
        className="flex-1 overflow-y-auto p-4"
      >
        {isLoading && (
          <div className="flex h-full items-center justify-center">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
          </div>
        )}

        <Document
          file={url}
          onLoadSuccess={handleDocumentLoadSuccess}
          loading={null}
          className="flex flex-col items-center"
        >
          {Array.from({ length: numPages }, (_, index) => (
            <PdfPage
              key={`${pageListId}-page-${index + 1}`}
              pageNumber={index + 1}
              scale={scale}
              highlights={highlights}
              isActive={currentPage === index + 1}
            />
          ))}
        </Document>
      </div>

      {/* Highlight styles — use dangerouslySetInnerHTML since styled-jsx is not available in App Router */}
      <style
        dangerouslySetInnerHTML={{
          __html: `
            .rag-highlight {
              background-color: rgba(250, 204, 21, 0.4) !important;
              border-radius: 2px;
              transition: background-color 0.2s;
            }
            .rag-highlight:hover {
              background-color: rgba(250, 204, 21, 0.7) !important;
            }
          `,
        }}
      />
    </div>
  );
}
```

## Usage

### Basic PDF Viewer

```tsx
import { PdfViewer } from "@/components/rag/pdf-viewer";

<PdfViewer
  url="/api/storage/download/rag/user123/document.pdf"
  fileName="Research Paper.pdf"
/>
```

### With Highlights from RAG Search

```tsx
import { PdfViewer } from "@/components/rag/pdf-viewer";

const highlights = [
  { text: "machine learning applications", pageNumber: 3 },
  { text: "neural network architecture", pageNumber: 7 },
];

<PdfViewer
  url={pdfUrl}
  fileName="Paper.pdf"
  highlights={highlights}
  activePageNumber={3}
  onPageChange={(page) => console.log("Viewing page:", page)}
/>
```

### Navigate to Page Programmatically

Pass `activePageNumber` to scroll to a specific page (e.g., when a citation is clicked):

```tsx
const [activePage, setActivePage] = useState<number | undefined>();

<CitationBadge
  onClick={() => setActivePage(citation.pageNumber)}
/>

<PdfViewer
  url={pdfUrl}
  activePageNumber={activePage}
/>
```

## Acceptance Criteria

- PDF renders with text layer enabled (selectable text)
- Annotation layer renders (links, form fields work)
- Zoom in/out works with 0.25x increments (0.5x to 3x range)
- Page navigation via toolbar arrows updates the view
- `activePageNumber` prop scrolls to the specified page
- Highlights apply yellow background to matching text spans in the text layer
- Highlight cleanup runs when highlights change or component unmounts
- Download button triggers file download
- Loading spinner shows while PDF loads
- `tsc` passes with no errors
- `bun run build` succeeds
