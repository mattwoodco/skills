---
name: storage-ui
description: File management UI components — dropzone upload, file list with grid/list toggle, file preview modal, and upload progress tracking. Built on the storage skill's API routes.
author: Claude
version: 2.0.0
created: 2025-01-11
updated: 2026-02-13
dependencies: [storage]
---

# Storage UI Skill

React components for file upload, browsing, preview, and management. Connects to the `/api/storage` routes from the `storage` skill.

## Prerequisites

- `storage` skill installed (provides `/api/storage` endpoints)
- shadcn/ui initialized with `button`, `dialog`, `alert-dialog`, `progress` components
- `@phosphor-icons/react` installed (installed by `add-shadcn`)

## Installation

```bash
bunx shadcn@latest add button dialog alert-dialog progress
```

## What Gets Created

```
src/
└── components/
    └── storage/
        ├── storage-provider.tsx   # React context + useStorage hook
        ├── dropzone.tsx           # Drag-and-drop file upload area
        ├── file-list.tsx          # File grid/list with actions
        ├── file-preview.tsx       # Modal file previewer
        └── file-manager.tsx       # Complete file management UI (combines all)
```

## Setup Steps

### Step 1: Create `src/components/storage/storage-provider.tsx`

```tsx
"use client";

import {
  createContext,
  useCallback,
  useContext,
  useId,
  useState,
  type ReactNode,
} from "react";

type StorageFile = {
  key: string;
  name: string;
  size: number;
  contentType: string;
  url: string;
  lastModified: string;
};

type UploadProgress = {
  id: string;
  fileName: string;
  progress: number;
  status: "pending" | "uploading" | "complete" | "error";
  error?: string;
};

type StorageContextValue = {
  files: StorageFile[];
  isLoading: boolean;
  error: string | null;
  uploads: Map<string, UploadProgress>;
  uploadFiles: (files: File[]) => Promise<StorageFile[]>;
  deleteFile: (key: string) => Promise<void>;
  refresh: () => Promise<void>;
  clearError: () => void;
};

const StorageContext = createContext<StorageContextValue | null>(null);

type StorageProviderProps = {
  children: ReactNode;
  apiBase?: string;
};

export function StorageProvider({
  children,
  apiBase = "/api/storage",
}: StorageProviderProps) {
  const [files, setFiles] = useState<StorageFile[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploads, setUploads] = useState<Map<string, UploadProgress>>(new Map());
  const uploadIdPrefix = useId();

  const clearError = useCallback(() => setError(null), []);

  const refresh = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const response = await fetch(apiBase);
      if (!response.ok) throw new Error("Failed to fetch files");
      const data = await response.json();
      setFiles(data.files ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to fetch files");
    } finally {
      setIsLoading(false);
    }
  }, [apiBase]);

  const uploadFiles = useCallback(
    async (filesToUpload: File[]): Promise<StorageFile[]> => {
      const results: StorageFile[] = [];

      for (let i = 0; i < filesToUpload.length; i++) {
        const file = filesToUpload[i];
        const uploadId = `${uploadIdPrefix}-${Date.now()}-${i}`;

        setUploads((prev) => {
          const next = new Map(prev);
          next.set(uploadId, {
            id: uploadId,
            fileName: file.name,
            progress: 0,
            status: "uploading",
          });
          return next;
        });

        try {
          const formData = new FormData();
          formData.append("file", file);

          const response = await fetch(`${apiBase}/upload`, {
            method: "POST",
            body: formData,
          });

          if (!response.ok) {
            const errData = await response.json().catch(() => ({}));
            throw new Error(errData.error || `Failed to upload ${file.name}`);
          }

          const data = await response.json();
          results.push(data.file);

          setUploads((prev) => {
            const next = new Map(prev);
            next.set(uploadId, {
              id: uploadId,
              fileName: file.name,
              progress: 100,
              status: "complete",
            });
            return next;
          });

          setTimeout(() => {
            setUploads((prev) => {
              const next = new Map(prev);
              next.delete(uploadId);
              return next;
            });
          }, 2000);
        } catch (err) {
          const message = err instanceof Error ? err.message : "Upload failed";
          setUploads((prev) => {
            const next = new Map(prev);
            next.set(uploadId, {
              id: uploadId,
              fileName: file.name,
              progress: 0,
              status: "error",
              error: message,
            });
            return next;
          });

          setTimeout(() => {
            setUploads((prev) => {
              const next = new Map(prev);
              next.delete(uploadId);
              return next;
            });
          }, 5000);
        }
      }

      if (results.length > 0) {
        setFiles((prev) => [...results, ...prev]);
      }

      return results;
    },
    [apiBase, uploadIdPrefix]
  );

  const deleteFile = useCallback(
    async (key: string) => {
      setError(null);
      try {
        const response = await fetch(`${apiBase}/delete`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ key }),
        });
        if (!response.ok) throw new Error("Failed to delete file");
        setFiles((prev) => prev.filter((f) => f.key !== key));
      } catch (err) {
        const message = err instanceof Error ? err.message : "Failed to delete";
        setError(message);
        throw err;
      }
    },
    [apiBase]
  );

  return (
    <StorageContext.Provider
      value={{ files, isLoading, error, uploads, uploadFiles, deleteFile, refresh, clearError }}
    >
      {children}
    </StorageContext.Provider>
  );
}

export function useStorage(): StorageContextValue {
  const context = useContext(StorageContext);
  if (!context) throw new Error("useStorage must be used within a StorageProvider");
  return context;
}

export type { StorageFile, UploadProgress };
```

### Step 2: Create `src/components/storage/dropzone.tsx`

```tsx
"use client";

import { useCallback, useId, useState, type DragEvent } from "react";
import { cn } from "@src/lib/utils";
import { UploadSimple, File, CircleNotch, WarningCircle } from "@phosphor-icons/react";

type AcceptCategory = "images" | "audio" | "video" | "pdf" | "text" | "archives";

const MIME_MAP: Record<AcceptCategory, string[]> = {
  images: ["image/jpeg", "image/png", "image/gif", "image/webp", "image/svg+xml"],
  audio: ["audio/mpeg", "audio/wav", "audio/ogg", "audio/mp4"],
  video: ["video/mp4", "video/webm", "video/quicktime"],
  pdf: ["application/pdf"],
  text: ["text/plain", "text/csv", "application/json"],
  archives: ["application/zip", "application/gzip", "application/x-tar"],
};

const LABELS: Record<AcceptCategory, string> = {
  images: "Images (JPEG, PNG, GIF, WebP, SVG)",
  audio: "Audio (MP3, WAV, OGG)",
  video: "Video (MP4, WebM, MOV)",
  pdf: "PDF",
  text: "Text (TXT, CSV, JSON)",
  archives: "Archives (ZIP, TAR, GZ)",
};

type DropzoneProps = {
  onFilesSelected: (files: File[]) => void;
  accept?: AcceptCategory[];
  multiple?: boolean;
  disabled?: boolean;
  isUploading?: boolean;
  maxSize?: number;
  className?: string;
};

export function Dropzone({
  onFilesSelected,
  accept = ["images", "audio", "video", "pdf", "text", "archives"],
  multiple = true,
  disabled = false,
  isUploading = false,
  maxSize,
  className,
}: DropzoneProps) {
  const inputId = useId();
  const [isDragOver, setIsDragOver] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const acceptedMimeTypes = accept.flatMap((cat) => MIME_MAP[cat]);
  const acceptString = acceptedMimeTypes.join(",");
  const acceptedLabels = accept.map((cat) => LABELS[cat]);

  const validateFiles = useCallback(
    (files: File[]): { valid: File[]; errors: string[] } => {
      const valid: File[] = [];
      const errors: string[] = [];
      for (const file of files) {
        if (acceptedMimeTypes.length > 0 && !acceptedMimeTypes.includes(file.type)) {
          errors.push(`"${file.name}" is not an accepted file type`);
          continue;
        }
        if (maxSize && file.size > maxSize) {
          errors.push(`"${file.name}" exceeds ${(maxSize / 1024 / 1024).toFixed(0)}MB limit`);
          continue;
        }
        valid.push(file);
      }
      return { valid, errors };
    },
    [acceptedMimeTypes, maxSize]
  );

  const handleFiles = useCallback(
    (fileList: FileList | null) => {
      if (!fileList || fileList.length === 0) return;
      setError(null);
      const { valid, errors } = validateFiles(Array.from(fileList));
      if (errors.length > 0) setError(errors.join(". "));
      if (valid.length > 0) onFilesSelected(multiple ? valid : [valid[0]]);
    },
    [validateFiles, onFilesSelected, multiple]
  );

  const handleDrop = useCallback(
    (e: DragEvent<HTMLDivElement>) => {
      e.preventDefault();
      e.stopPropagation();
      setIsDragOver(false);
      if (!disabled && !isUploading) handleFiles(e.dataTransfer.files);
    },
    [disabled, isUploading, handleFiles]
  );

  const isDisabled = disabled || isUploading;

  return (
    <div className={cn("w-full", className)}>
      <div
        onDragEnter={(e) => { e.preventDefault(); setIsDragOver(true); }}
        onDragLeave={(e) => { e.preventDefault(); setIsDragOver(false); }}
        onDragOver={(e) => e.preventDefault()}
        onDrop={handleDrop}
        className={cn(
          "relative rounded-lg border-2 border-dashed transition-colors duration-200",
          "flex flex-col items-center justify-center gap-4 p-8 min-h-[200px] cursor-pointer",
          isDisabled
            ? "cursor-not-allowed border-muted bg-muted/50 opacity-60"
            : isDragOver
              ? "border-primary bg-primary/5"
              : "border-muted-foreground/25 hover:border-primary/50 hover:bg-muted/50"
        )}
      >
        <input
          id={inputId}
          type="file"
          accept={acceptString}
          multiple={multiple}
          disabled={isDisabled}
          onChange={(e) => handleFiles(e.target.files)}
          className="absolute inset-0 h-full w-full cursor-pointer opacity-0 disabled:cursor-not-allowed"
          aria-label="File upload"
        />
        <div className="flex flex-col items-center gap-2 text-center">
          {isUploading ? (
            <CircleNotch className="h-10 w-10 animate-spin text-primary" />
          ) : isDragOver ? (
            <File className="h-10 w-10 text-primary" />
          ) : (
            <UploadSimple className="h-10 w-10 text-muted-foreground" />
          )}
          <p className="text-sm font-medium">
            {isUploading ? "Uploading..." : isDragOver ? "Drop files here" : "Drag and drop files here"}
          </p>
          <p className="text-xs text-muted-foreground">
            {isUploading ? "Please wait" : `or click to browse ${multiple ? "files" : "a file"}`}
          </p>
        </div>
        {!isUploading && acceptedLabels.length > 0 && (
          <p className="text-xs text-muted-foreground">{acceptedLabels.join(" · ")}</p>
        )}
        {maxSize && !isUploading && (
          <p className="text-xs text-muted-foreground">Max: {(maxSize / 1024 / 1024).toFixed(0)}MB</p>
        )}
      </div>
      {error && (
        <div className="mt-3 flex items-start gap-2 rounded-md bg-destructive/10 p-3 text-sm text-destructive">
          <WarningCircle className="mt-0.5 h-4 w-4 shrink-0" />
          <p>{error}</p>
        </div>
      )}
    </div>
  );
}

export type { AcceptCategory, DropzoneProps };
```

### Step 3: Create `src/components/storage/file-list.tsx`

```tsx
"use client";

import { useId, useState, memo } from "react";
import { cn } from "@src/lib/utils";
import {
  File, ImageSquare, VideoCamera, MusicNote, FileText,
  FileArchive, DownloadSimple, Trash, Eye,
  CircleNotch, SquaresFour, ListBullets, WarningCircle,
} from "@phosphor-icons/react";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel,
  AlertDialogContent, AlertDialogDescription, AlertDialogFooter,
  AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import type { StorageFile } from "./storage-provider";

function getFileIcon(contentType: string) {
  if (contentType.startsWith("image/")) return ImageSquare;
  if (contentType.startsWith("video/")) return VideoCamera;
  if (contentType.startsWith("audio/")) return MusicNote;
  if (contentType === "application/pdf") return FileText;
  if (contentType.startsWith("text/") || contentType === "application/json") return FileText;
  if (["application/zip", "application/gzip", "application/x-tar"].includes(contentType)) return FileArchive;
  return File;
}

function formatSize(bytes: number): string {
  if (bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${parseFloat((bytes / Math.pow(1024, i)).toFixed(1))} ${units[i]}`;
}

type FileItemProps = {
  file: StorageFile;
  layout: "grid" | "list";
  onPreview: (file: StorageFile) => void;
  onDelete: (file: StorageFile) => void;
  isDeleting: boolean;
};

const FileItem = memo(function FileItem({ file, layout, onPreview, onDelete, isDeleting }: FileItemProps) {
  const Icon = getFileIcon(file.contentType);
  const canPreview =
    file.contentType.startsWith("image/") ||
    file.contentType.startsWith("video/") ||
    file.contentType.startsWith("audio/") ||
    file.contentType === "application/pdf" ||
    file.contentType.startsWith("text/");

  if (layout === "grid") {
    return (
      <div className={cn(
        "group relative flex flex-col items-center rounded-lg border bg-card p-4 transition-colors hover:bg-accent/50",
        isDeleting && "pointer-events-none opacity-50"
      )}>
        <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-lg bg-muted">
          <Icon className="h-6 w-6 text-muted-foreground" />
        </div>
        <p className="w-full truncate text-center text-sm font-medium">{file.name}</p>
        <p className="text-xs text-muted-foreground">{formatSize(file.size)}</p>
        <div className="mt-3 flex gap-1 opacity-0 transition-opacity group-hover:opacity-100">
          {canPreview && (
            <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => onPreview(file)} title="Preview">
              <Eye className="h-4 w-4" />
            </Button>
          )}
          <a href={file.url} download={file.name} title="Download" className={cn(buttonVariants({ variant: "ghost", size: "icon" }), "h-8 w-8")}>
            <DownloadSimple className="h-4 w-4" />
          </a>
          <AlertDialog>
            <AlertDialogTrigger
              render={<Button variant="ghost" size="icon" className="h-8 w-8 text-destructive hover:text-destructive" title="Delete" />}
            >
              {isDeleting ? <CircleNotch className="h-4 w-4 animate-spin" /> : <Trash className="h-4 w-4" />}
            </AlertDialogTrigger>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>Delete file?</AlertDialogTitle>
                <AlertDialogDescription>
                  Are you sure you want to delete &quot;{file.name}&quot;? This cannot be undone.
                </AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel>Cancel</AlertDialogCancel>
                <AlertDialogAction onClick={() => onDelete(file)} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
                  Delete
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        </div>
      </div>
    );
  }

  return (
    <div className={cn(
      "group flex items-center gap-4 rounded-lg border bg-card p-3 transition-colors hover:bg-accent/50",
      isDeleting && "pointer-events-none opacity-50"
    )}>
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-muted">
        <Icon className="h-5 w-5 text-muted-foreground" />
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium">{file.name}</p>
        <p className="text-xs text-muted-foreground">{formatSize(file.size)}</p>
      </div>
      <div className="flex shrink-0 gap-1 opacity-0 transition-opacity group-hover:opacity-100 sm:opacity-100">
        {canPreview && (
          <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => onPreview(file)} title="Preview">
            <Eye className="h-4 w-4" />
          </Button>
        )}
        <a href={file.url} download={file.name} title="Download" className={cn(buttonVariants({ variant: "ghost", size: "icon" }), "h-8 w-8")}>
          <DownloadSimple className="h-4 w-4" />
        </a>
        <AlertDialog>
          <AlertDialogTrigger
            render={<Button variant="ghost" size="icon" className="h-8 w-8 text-destructive hover:text-destructive" title="Delete" />}
          >
            {isDeleting ? <CircleNotch className="h-4 w-4 animate-spin" /> : <Trash className="h-4 w-4" />}
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete file?</AlertDialogTitle>
              <AlertDialogDescription>
                Are you sure you want to delete &quot;{file.name}&quot;? This cannot be undone.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction onClick={() => onDelete(file)} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
                Delete
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </div>
    </div>
  );
});

type FileListProps = {
  files: StorageFile[];
  isLoading?: boolean;
  error?: string | null;
  onPreview?: (file: StorageFile) => void;
  onDelete?: (file: StorageFile) => Promise<void>;
  deletingKeys?: Set<string>;
  className?: string;
};

export function FileList({
  files,
  isLoading = false,
  error = null,
  onPreview,
  onDelete,
  deletingKeys = new Set(),
  className,
}: FileListProps) {
  const listId = useId();
  const [layout, setLayout] = useState<"grid" | "list">("grid");

  if (isLoading) {
    return (
      <div className={cn("flex flex-col items-center justify-center py-12", className)}>
        <CircleNotch className="h-8 w-8 animate-spin text-muted-foreground" />
        <p className="mt-4 text-sm text-muted-foreground">Loading files...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className={cn("flex flex-col items-center justify-center rounded-lg border border-destructive/50 bg-destructive/10 py-12", className)}>
        <WarningCircle className="h-8 w-8 text-destructive" />
        <p className="mt-4 text-sm font-medium text-destructive">Error loading files</p>
        <p className="mt-1 text-sm text-muted-foreground">{error}</p>
      </div>
    );
  }

  if (files.length === 0) {
    return (
      <div className={cn("flex flex-col items-center justify-center rounded-lg border border-dashed py-12", className)}>
        <File className="h-8 w-8 text-muted-foreground" />
        <p className="mt-4 text-sm text-muted-foreground">No files uploaded yet</p>
      </div>
    );
  }

  return (
    <div className={cn("space-y-4", className)}>
      <div className="flex items-center justify-between">
        <p className="text-sm text-muted-foreground">{files.length} {files.length === 1 ? "file" : "files"}</p>
        <div className="flex gap-1">
          <Button variant={layout === "grid" ? "secondary" : "ghost"} size="icon" className="h-8 w-8" onClick={() => setLayout("grid")}>
            <SquaresFour className="h-4 w-4" />
          </Button>
          <Button variant={layout === "list" ? "secondary" : "ghost"} size="icon" className="h-8 w-8" onClick={() => setLayout("list")}>
            <ListBullets className="h-4 w-4" />
          </Button>
        </div>
      </div>
      <div className={cn(
        layout === "grid"
          ? "grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5"
          : "flex flex-col gap-2"
      )}>
        {files.map((file) => (
          <FileItem
            key={`${listId}-${file.key}`}
            file={file}
            layout={layout}
            onPreview={(f) => onPreview?.(f)}
            onDelete={(f) => onDelete?.(f)}
            isDeleting={deletingKeys.has(file.key)}
          />
        ))}
      </div>
    </div>
  );
}
```

### Step 4: Create `src/components/storage/file-preview.tsx`

```tsx
"use client";

import { useEffect, useState } from "react";
import { cn } from "@src/lib/utils";
import { CircleNotch, WarningCircle, DownloadSimple, MusicNote } from "@phosphor-icons/react";
import { buttonVariants } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import type { StorageFile } from "./storage-provider";

type FilePreviewProps = {
  file: StorageFile | null;
  isOpen: boolean;
  onClose: () => void;
};

export function FilePreview({ file, isOpen, onClose }: FilePreviewProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [textContent, setTextContent] = useState<string | null>(null);

  useEffect(() => {
    if (!file || !isOpen) {
      setTextContent(null);
      setError(null);
      return;
    }

    const isText =
      file.contentType.startsWith("text/") ||
      file.contentType === "application/json";

    if (!isText) return;

    setIsLoading(true);
    setError(null);

    fetch(file.url)
      .then(async (res) => {
        if (!res.ok) throw new Error("Failed to load");
        setTextContent(await res.text());
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load"))
      .finally(() => setIsLoading(false));
  }, [file, isOpen]);

  const renderPreview = () => {
    if (!file) return null;

    if (isLoading) {
      return (
        <div className="flex flex-col items-center justify-center py-16">
          <CircleNotch className="h-8 w-8 animate-spin text-muted-foreground" />
          <p className="mt-4 text-sm text-muted-foreground">Loading preview...</p>
        </div>
      );
    }

    if (error) {
      return (
        <div className="flex flex-col items-center justify-center py-16">
          <WarningCircle className="h-8 w-8 text-destructive" />
          <p className="mt-4 text-sm text-destructive">{error}</p>
        </div>
      );
    }

    if (file.contentType.startsWith("image/")) {
      return (
        <div className="flex items-center justify-center">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={file.url} alt={file.name} className="max-h-[70vh] max-w-full rounded-lg object-contain" />
        </div>
      );
    }

    if (file.contentType.startsWith("video/")) {
      return (
        <video src={file.url} controls className="max-h-[70vh] max-w-full rounded-lg">
          Your browser does not support video playback.
        </video>
      );
    }

    if (file.contentType.startsWith("audio/")) {
      return (
        <div className="flex flex-col items-center gap-8 py-8">
          <div className="flex h-24 w-24 items-center justify-center rounded-full bg-muted">
            <MusicNote className="h-12 w-12 text-muted-foreground" />
          </div>
          <audio src={file.url} controls className="w-full max-w-md">
            Your browser does not support audio playback.
          </audio>
        </div>
      );
    }

    if (file.contentType === "application/pdf") {
      return <iframe src={file.url} title={file.name} className="h-[70vh] w-full rounded-lg border" />;
    }

    if (textContent !== null) {
      return (
        <div className="max-h-[70vh] overflow-auto rounded-lg border bg-muted/50 p-4">
          <pre className="whitespace-pre-wrap break-words font-mono text-sm">{textContent}</pre>
        </div>
      );
    }

    return (
      <div className="flex flex-col items-center justify-center py-16">
        <p className="text-sm text-muted-foreground">Preview not available</p>
        <a href={file.url} download={file.name} className={cn(buttonVariants({ variant: "outline" }), "mt-4")}>
            <DownloadSimple className="mr-2 h-4 w-4" />Download
        </a>
      </div>
    );
  };

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className={cn("max-h-[90vh] max-w-4xl overflow-hidden flex flex-col")}>
        <DialogHeader className="flex-shrink-0">
          <div className="flex items-center justify-between pr-8">
            <DialogTitle className="truncate pr-4">{file?.name ?? "Preview"}</DialogTitle>
            {file && (
              <a href={file.url} download={file.name} className={cn(buttonVariants({ variant: "outline", size: "sm" }))}>
                <DownloadSimple className="mr-2 h-4 w-4" />Download
              </a>
            )}
          </div>
        </DialogHeader>
        <div className="flex-1 overflow-auto">{renderPreview()}</div>
      </DialogContent>
    </Dialog>
  );
}
```

### Step 5: Create `src/components/storage/file-manager.tsx`

```tsx
"use client";

import { useCallback, useEffect, useId, useState, memo } from "react";
import { cn } from "@src/lib/utils";
import { ArrowClockwise, CircleNotch, WarningCircle, X } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { useStorage, type StorageFile, type UploadProgress } from "./storage-provider";
import { Dropzone, type AcceptCategory } from "./dropzone";
import { FileList } from "./file-list";
import { FilePreview } from "./file-preview";

const UploadProgressItem = memo(function UploadProgressItem({ upload }: { upload: UploadProgress }) {
  const colors = {
    pending: "text-muted-foreground",
    uploading: "text-primary",
    complete: "text-green-600 dark:text-green-500",
    error: "text-destructive",
  };

  return (
    <div className="flex flex-col gap-2 rounded-lg border bg-card p-3">
      <div className="flex items-center justify-between gap-2">
        <p className="truncate text-sm font-medium">{upload.fileName}</p>
        <span className={cn("text-xs", colors[upload.status])}>
          {upload.status === "error" ? upload.error ?? "Failed" : upload.status}
        </span>
      </div>
      {(upload.status === "pending" || upload.status === "uploading") && (
        <Progress value={upload.progress} className="h-1.5" />
      )}
    </div>
  );
});

type FileManagerProps = {
  accept?: AcceptCategory[];
  maxFileSize?: number;
  multiple?: boolean;
  className?: string;
  onUpload?: (files: StorageFile[]) => void;
  onDelete?: (file: StorageFile) => void;
};

export function FileManager({
  accept,
  maxFileSize,
  multiple = true,
  className,
  onUpload,
  onDelete,
}: FileManagerProps) {
  const progressListId = useId();
  const { files, isLoading, error, uploads, uploadFiles, deleteFile, refresh, clearError } = useStorage();
  const [previewFile, setPreviewFile] = useState<StorageFile | null>(null);
  const [deletingKeys, setDeletingKeys] = useState<Set<string>>(new Set());
  const [isRefreshing, setIsRefreshing] = useState(false);

  useEffect(() => { refresh(); }, [refresh]);

  const handleFilesSelected = useCallback(
    async (selectedFiles: File[]) => {
      const uploaded = await uploadFiles(selectedFiles);
      if (uploaded.length > 0) onUpload?.(uploaded);
    },
    [uploadFiles, onUpload]
  );

  const handleDelete = useCallback(
    async (file: StorageFile) => {
      setDeletingKeys((prev) => new Set(prev).add(file.key));
      try {
        await deleteFile(file.key);
        onDelete?.(file);
      } finally {
        setDeletingKeys((prev) => {
          const next = new Set(prev);
          next.delete(file.key);
          return next;
        });
      }
    },
    [deleteFile, onDelete]
  );

  const handleRefresh = useCallback(async () => {
    setIsRefreshing(true);
    try { await refresh(); } finally { setIsRefreshing(false); }
  }, [refresh]);

  const isUploading = uploads.size > 0;
  const uploadsArray = Array.from(uploads.values());

  return (
    <div className={cn("space-y-6", className)}>
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold">File Manager</h2>
        <Button variant="outline" size="sm" onClick={handleRefresh} disabled={isRefreshing || isLoading}>
          {isRefreshing ? <CircleNotch className="mr-2 h-4 w-4 animate-spin" /> : <ArrowClockwise className="mr-2 h-4 w-4" />}
          Refresh
        </Button>
      </div>

      {error && (
        <div className="flex items-start gap-3 rounded-lg border border-destructive/50 bg-destructive/10 p-4">
          <WarningCircle className="mt-0.5 h-5 w-5 shrink-0 text-destructive" />
          <div className="flex-1">
            <p className="font-medium text-destructive">Error</p>
            <p className="mt-1 text-sm text-muted-foreground">{error}</p>
          </div>
          <Button variant="ghost" size="icon" className="h-8 w-8 shrink-0" onClick={clearError}>
            <X className="h-4 w-4" />
          </Button>
        </div>
      )}

      <Dropzone
        onFilesSelected={handleFilesSelected}
        accept={accept}
        multiple={multiple}
        maxSize={maxFileSize}
        isUploading={isUploading}
      />

      {uploadsArray.length > 0 && (
        <div className="space-y-2">
          <p className="text-sm font-medium">Uploading {uploadsArray.length} {uploadsArray.length === 1 ? "file" : "files"}</p>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {uploadsArray.map((upload) => (
              <UploadProgressItem key={`${progressListId}-${upload.id}`} upload={upload} />
            ))}
          </div>
        </div>
      )}

      <FileList
        files={files}
        isLoading={isLoading}
        error={error}
        onPreview={setPreviewFile}
        onDelete={handleDelete}
        deletingKeys={deletingKeys}
      />

      <FilePreview file={previewFile} isOpen={!!previewFile} onClose={() => setPreviewFile(null)} />
    </div>
  );
}
```

## Usage

```tsx
// app/files/page.tsx
import { StorageProvider } from "@/components/storage/storage-provider";
import { FileManager } from "@/components/storage/file-manager";

export default function FilesPage() {
  return (
    <StorageProvider>
      <div className="container mx-auto py-8">
        <FileManager
          accept={["images", "pdf"]}
          maxFileSize={10 * 1024 * 1024}
          onUpload={(files) => console.log("Uploaded:", files)}
        />
      </div>
    </StorageProvider>
  );
}
```
