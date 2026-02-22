---
name: ai-rag-app
description: RAG application page — split-pane layout combining PDF upload, document list, RAG chat, and PDF viewer with citation-driven navigation. Click a citation to highlight the source text in the PDF viewer. Use this skill when the user says "setup RAG app", "add document chat page", "setup ai-rag-app", or "create PDF chat interface".
author: "@mattwoodco"
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
validated: 2026-02-13
dependencies: [ai-rag-ingest, ai-rag-vectors, ai-rag-chat, ai-rag-viewer, auth]
---

# AI RAG App

Full RAG application page with split-pane layout. Left side: document list + RAG chat. Right side: PDF viewer with highlighted citations. Upload PDFs, process them, ask questions, and see exact source sections highlighted in the rendered PDF.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `ai-rag-ingest` skill installed (upload + parsing)
- `ai-rag-vectors` skill installed (embeddings + search)
- `ai-rag-chat` skill installed (RAG chat component + API)
- `ai-rag-viewer` skill installed (PDF viewer component)
- `auth` skill installed (protected routes)
- shadcn/ui initialized

## Installation

```bash
bunx shadcn@latest add tabs badge progress separator
```

## What Gets Created

```
src/
├── app/
│   └── (app)/
│       └── rag/
│           └── page.tsx                    # Main RAG application page
└── components/
    └── rag/
        ├── document-list.tsx              # Document list with upload + status
        ├── document-upload.tsx            # Upload form with drag-and-drop
        └── rag-layout.tsx                 # Split-pane layout orchestrator
```

## Setup Steps

### Step 1: Create `src/components/rag/document-upload.tsx`

```tsx
"use client";

import { useState, useRef, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { UploadSimple, File, CircleNotch } from "@phosphor-icons/react";

type DocumentUploadProps = {
  onUploadComplete: (documentId: string) => void;
};

export function DocumentUpload({ onUploadComplete }: DocumentUploadProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState("");

  const uploadFile = useCallback(
    async (file: File) => {
      if (!file.name.toLowerCase().endsWith(".pdf")) {
        return;
      }

      setIsUploading(true);
      setUploadProgress("Uploading...");

      try {
        // 1. Upload
        const formData = new FormData();
        formData.append("file", file);

        const uploadRes = await fetch("/api/rag/documents", {
          method: "POST",
          body: formData,
        });

        if (!uploadRes.ok) {
          const err = (await uploadRes.json()) as { error?: string };
          throw new Error(err.error ?? "Upload failed");
        }

        const doc = (await uploadRes.json()) as { id: string };
        setUploadProgress("Processing PDF...");

        // 2. Process
        const processRes = await fetch(
          `/api/rag/documents/${doc.id}/process`,
          { method: "POST" }
        );

        if (!processRes.ok) {
          throw new Error("Processing failed");
        }

        setUploadProgress("Generating embeddings...");

        // 3. Index
        const indexRes = await fetch(
          `/api/rag/documents/${doc.id}/index`,
          { method: "POST" }
        );

        if (!indexRes.ok) {
          throw new Error("Indexing failed");
        }

        onUploadComplete(doc.id);
      } catch {
        // Upload error handled by progress reset
      } finally {
        setIsUploading(false);
        setUploadProgress("");
      }
    },
    [onUploadComplete]
  );

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setIsDragging(false);

      const file = e.dataTransfer.files[0];
      if (file) uploadFile(file);
    },
    [uploadFile]
  );

  const handleFileSelect = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) uploadFile(file);
      // Reset input
      if (fileInputRef.current) {
        fileInputRef.current.value = "";
      }
    },
    [uploadFile]
  );

  return (
    // biome-ignore lint/a11y/noStaticElementInteractions: drop zone requires drag event handlers on div
    <div
      onDragOver={(e) => {
        e.preventDefault();
        setIsDragging(true);
      }}
      onDragLeave={() => setIsDragging(false)}
      onDrop={handleDrop}
      className={`rounded-lg border-2 border-dashed p-6 text-center transition-colors ${
        isDragging
          ? "border-primary bg-primary/5"
          : "border-muted-foreground/25"
      }`}
    >
      {isUploading ? (
        <div className="flex flex-col items-center gap-2">
          <CircleNotch className="h-8 w-8 animate-spin text-primary" />
          <p className="text-sm text-muted-foreground">{uploadProgress}</p>
        </div>
      ) : (
        <div className="flex flex-col items-center gap-2">
          <UploadSimple className="h-8 w-8 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            Drag & drop a PDF here, or
          </p>
          <Button
            variant="outline"
            size="sm"
            onClick={() => fileInputRef.current?.click()}
          >
            <File className="mr-2 h-4 w-4" />
            Browse Files
          </Button>
          <input
            ref={fileInputRef}
            type="file"
            accept=".pdf"
            onChange={handleFileSelect}
            className="hidden"
          />
        </div>
      )}
    </div>
  );
}
```

### Step 2: Create `src/components/rag/document-list.tsx`

```tsx
"use client";

import { useId, useEffect, useState, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Trash, FileText, CircleNotch } from "@phosphor-icons/react";

type DocumentItem = {
  id: string;
  title: string;
  fileName: string;
  fileSize: number;
  pageCount: number | null;
  pagesProcessed: number;
  status: "uploading" | "processing" | "ready" | "error";
  createdAt: string;
};

type DocumentListProps = {
  selectedDocumentId: string | null;
  onSelectDocument: (doc: DocumentItem) => void;
  refreshKey?: number;
};

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024)
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

const statusColors: Record<string, string> = {
  uploading: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
  processing: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200",
  ready: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
  error: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
};

export function DocumentList({
  selectedDocumentId,
  onSelectDocument,
  refreshKey,
}: DocumentListProps) {
  const listId = useId();
  const [documents, setDocuments] = useState<DocumentItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const loadDocuments = useCallback(async () => {
    try {
      const res = await fetch("/api/rag/documents");
      if (!res.ok) return;
      const data = (await res.json()) as DocumentItem[];
      setDocuments(data);
    } catch {
      // Silently fail
    } finally {
      setIsLoading(false);
    }
  }, []);

  // biome-ignore lint/correctness/useExhaustiveDependencies: refreshKey triggers reload
  useEffect(() => {
    loadDocuments();
  }, [loadDocuments, refreshKey]);

  const handleDelete = useCallback(
    async (e: React.MouseEvent, documentId: string) => {
      e.stopPropagation();
      try {
        const res = await fetch(`/api/rag/documents/${documentId}`, {
          method: "DELETE",
        });
        if (!res.ok) return;
        setDocuments((prev) => prev.filter((d) => d.id !== documentId));
      } catch {
        // Silently fail
      }
    },
    []
  );

  if (isLoading) {
    return (
      <div className="flex items-center justify-center p-4">
        <CircleNotch className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (documents.length === 0) {
    return (
      <p className="p-4 text-center text-sm text-muted-foreground">
        No documents uploaded yet.
      </p>
    );
  }

  return (
    <ul className="space-y-1 p-2">
      {documents.map((doc) => (
        <li key={`${listId}-${doc.id}`}>
          <button
            type="button"
            onClick={() => onSelectDocument(doc)}
            className={`group flex w-full items-start gap-3 rounded-md px-3 py-2 text-left transition-colors hover:bg-accent ${
              selectedDocumentId === doc.id ? "bg-accent" : ""
            }`}
          >
            <FileText className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">{doc.title}</p>
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                <span>{formatFileSize(doc.fileSize)}</span>
                {doc.pageCount && <span>{doc.pageCount} pages</span>}
                <Badge
                  variant="secondary"
                  className={`text-[10px] ${statusColors[doc.status] ?? ""}`}
                >
                  {doc.status}
                </Badge>
              </div>
            </div>
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6 shrink-0 opacity-0 transition-opacity group-hover:opacity-100"
              onClick={(e) => handleDelete(e, doc.id)}
            >
              <Trash className="h-3 w-3 text-destructive" />
            </Button>
          </button>
        </li>
      ))}
    </ul>
  );
}
```

### Step 3: Create `src/components/rag/rag-layout.tsx`

This is the main orchestrator that ties everything together.

```tsx
"use client";

import { useState, useCallback } from "react";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Separator } from "@/components/ui/separator";
import { DocumentUpload } from "./document-upload";
import { DocumentList } from "./document-list";
import { RagChat } from "./rag-chat";
import { PdfViewer } from "./pdf-viewer";

type Citation = {
  documentId: string;
  documentTitle: string;
  pageNumber: number;
  chunkText: string;
  similarity: number;
};

type SelectedDocument = {
  id: string;
  title: string;
  fileName: string;
  storageKey?: string;
};

export function RagLayout() {
  const [selectedDocument, setSelectedDocument] =
    useState<SelectedDocument | null>(null);
  const [chatSessionId, setChatSessionId] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [activeTab, setActiveTab] = useState("chat");

  // PDF viewer state
  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [highlights, setHighlights] = useState<
    { text: string; pageNumber: number }[]
  >([]);
  const [activePage, setActivePage] = useState<number | undefined>();

  const handleSelectDocument = useCallback(
    async (doc: { id: string; title: string; fileName: string }) => {
      setSelectedDocument(doc);
      setChatSessionId(null); // Reset chat for new document
      setHighlights([]);
      setActivePage(undefined);

      // Get download URL for the PDF viewer
      try {
        const res = await fetch(`/api/rag/documents/${doc.id}`);
        if (res.ok) {
          const detail = (await res.json()) as { storageKey: string };
          const storageKey = encodeURIComponent(detail.storageKey);
          setPdfUrl(`/api/storage/download/${storageKey}`);
        }
      } catch {
        setPdfUrl(null);
      }
    },
    []
  );

  const handleUploadComplete = useCallback(
    (_documentId: string) => {
      setRefreshKey((prev) => prev + 1);
    },
    []
  );

  const handleCitationClick = useCallback(
    (citation: Citation) => {
      // Update highlights and navigate in PDF viewer
      setHighlights((prev) => {
        // Add new highlight, avoiding duplicates
        const exists = prev.some(
          (h) =>
            h.pageNumber === citation.pageNumber &&
            h.text === citation.chunkText
        );
        if (exists) return prev;
        return [
          ...prev,
          { text: citation.chunkText, pageNumber: citation.pageNumber },
        ];
      });
      setActivePage(citation.pageNumber);
    },
    []
  );

  return (
    <div className="flex h-full">
      {/* Left panel: Documents + Chat */}
      <div className="flex w-[480px] shrink-0 flex-col border-r">
        <Tabs
          value={activeTab}
          onValueChange={setActiveTab}
          className="flex h-full flex-col"
        >
          <div className="border-b px-3 pt-2">
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="documents">Documents</TabsTrigger>
              <TabsTrigger value="chat">Chat</TabsTrigger>
            </TabsList>
          </div>

          <TabsContent value="documents" className="flex-1 overflow-y-auto m-0">
            <div className="p-3">
              <DocumentUpload onUploadComplete={handleUploadComplete} />
            </div>
            <Separator />
            <DocumentList
              selectedDocumentId={selectedDocument?.id ?? null}
              onSelectDocument={handleSelectDocument}
              refreshKey={refreshKey}
            />
          </TabsContent>

          <TabsContent value="chat" className="flex-1 overflow-hidden m-0">
            {selectedDocument ? (
              <RagChat
                key={selectedDocument.id}
                documentIds={[selectedDocument.id]}
                sessionId={chatSessionId}
                onSessionCreated={setChatSessionId}
                onCitationClick={handleCitationClick}
              />
            ) : (
              <div className="flex h-full items-center justify-center p-4 text-center text-muted-foreground">
                <p>Select a document from the Documents tab to start chatting.</p>
              </div>
            )}
          </TabsContent>
        </Tabs>
      </div>

      {/* Right panel: PDF Viewer */}
      <div className="flex-1">
        {pdfUrl ? (
          <PdfViewer
            url={pdfUrl}
            fileName={selectedDocument?.fileName}
            highlights={highlights}
            activePageNumber={activePage}
          />
        ) : (
          <div className="flex h-full items-center justify-center text-muted-foreground">
            <div className="text-center">
              <p className="text-lg font-medium">No document selected</p>
              <p className="text-sm">
                Upload and select a document to view it here.
              </p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
```

### Step 4: Create `src/app/(app)/rag/page.tsx`

The PdfViewer uses PDF.js which requires browser APIs (DOMMatrix). Use a dynamic import with `ssr: false` in a client component to prevent SSR failures during build.

```tsx
"use client";

import dynamic from "next/dynamic";

const RagLayout = dynamic(
  () =>
    import("@/components/rag/rag-layout").then((m) => ({
      default: m.RagLayout,
    })),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-full items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-primary border-t-transparent" />
      </div>
    ),
  },
);

export default function RagPage() {
  return (
    <div className="h-[calc(100vh-4rem)]">
      <RagLayout />
    </div>
  );
}
```

## Usage

1. Navigate to `/rag` in your app (must be signed in).
2. Switch to the **Documents** tab and drag & drop a PDF (or click Browse Files).
3. The PDF is uploaded, parsed, and indexed automatically (upload → process → index).
4. Select the document from the list — it renders in the right-side PDF viewer.
5. Switch to the **Chat** tab and ask questions about the document.
6. The assistant answers with `[Source N]` citations. Citation badges appear below the response.
7. Click a citation badge — the PDF viewer scrolls to the cited page and highlights the matching text.

## Complete Pipeline Flow

```
┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│   Upload PDF │ → │  Parse Pages │ → │ Chunk + Embed│ → │  Ready for   │
│  (S3 storage)│   │   (unpdf)    │   │  (pgvector)  │   │    Chat!     │
└──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘
                                                                │
                        ┌────────────────────────────────────────┘
                        ▼
                 ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
                 │  User Query  │ → │Vector Search │ → │  Stream AI   │
                 │              │   │(cosine sim.) │   │  + Citations  │
                 └──────────────┘   └──────────────┘   └──────────────┘
                                                                │
                        ┌────────────────────────────────────────┘
                        ▼
                 ┌──────────────────────────────┐
                 │  Click Citation → PDF Viewer  │
                 │  scrolls + highlights source  │
                 └──────────────────────────────┘
```

## Acceptance Criteria

- Drag-and-drop PDF upload works with progress states (uploading → processing → indexing)
- Document list shows all uploaded documents with status badges
- Selecting a document loads it in the PDF viewer
- Chat responds with RAG-augmented answers referencing `[Source N]` citations
- Citation badges display document title and page number
- Clicking a citation scrolls the PDF viewer to the correct page
- Matching text is highlighted with yellow background in the PDF text layer
- Delete removes the document, pages, chunks, and storage file
- Only authenticated users can access the page
- `tsc` passes with no errors
- `bun run build` succeeds
