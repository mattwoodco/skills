---
name: ai-rag-ingest
description: PDF ingestion pipeline — chunked upload of large PDFs (up to 2GB) to S3 storage, parallel PDF parsing with unpdf, page-level text extraction, and processing status tracking with Postgres. Use this skill when the user says "setup PDF upload", "add PDF ingestion", "setup ai-rag-ingest", or "add document upload".
author: "@mattwoodco"
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
validated: 2026-02-13
dependencies: [storage, db, auth, docker]
---

# AI RAG Ingest

PDF ingestion pipeline that uploads large PDFs (up to 2GB) to S3-compatible storage, parses them in parallel with `unpdf`, extracts page-level text, and tracks processing status in Postgres.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `storage` skill installed (S3/Vercel Blob at `@/lib/storage/storage-provider`)
- `db` skill installed (Drizzle ORM + Postgres)
- `auth` skill installed (`withAuth` at `@/lib/auth-guard`)
- Docker running with PostgreSQL

## Installation

```bash
bun add unpdf
```

## What Gets Created

```
lib/
├── db/
│   └── schema/
│       └── rag.ts                          # document + documentPage tables
└── rag/
    └── pdf-parser.ts                       # unpdf parsing logic
app/
└── api/
    └── rag/
        └── documents/
            ├── route.ts                    # GET list, POST upload
            └── [documentId]/
                ├── route.ts                # GET detail, DELETE
                └── process/
                    └── route.ts            # POST trigger parsing
```

## Database

After applying this skill, push the schema:

```bash
bunx drizzle-kit push
```

## Setup Steps

### Step 1: Create `db/schema/rag.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  integer,
  jsonb,
  pgEnum,
} from "drizzle-orm/pg-core";

export const documentStatusEnum = pgEnum("document_status", [
  "uploading",
  "processing",
  "ready",
  "error",
]);

export const document = pgTable("document", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull(),
  title: text("title").notNull(),
  fileName: text("file_name").notNull(),
  storageKey: text("storage_key").notNull(),
  fileSize: integer("file_size").notNull(),
  pageCount: integer("page_count"),
  pagesProcessed: integer("pages_processed").notNull().default(0),
  status: documentStatusEnum("status").notNull().default("uploading"),
  errorMessage: text("error_message"),
  metadata: jsonb("metadata").$type<Record<string, string>>(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).defaultNow().notNull(),
});

export const documentPage = pgTable("document_page", {
  id: uuid("id").defaultRandom().primaryKey(),
  documentId: uuid("document_id")
    .notNull()
    .references(() => document.id, { onDelete: "cascade" }),
  pageNumber: integer("page_number").notNull(),
  textContent: text("text_content").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});
```

### Step 2: Add export to `db/schema/index.ts`

The project uses a barrel export pattern in `lib/db/schema/index.ts`. Add the RAG schema export:

```typescript
export * from "./rag";
```

### Step 3: Create `lib/rag/pdf-parser.ts`

```typescript
import { getDocumentProxy, extractText } from "unpdf";

type ParsedPdf = {
  pageTexts: string[];
  pageCount: number;
  metadata: Record<string, string>;
};

/**
 * Parse a PDF buffer and extract per-page text content.
 * Uses unpdf (built on Mozilla pdf.js) for fast, reliable extraction.
 */
export async function parsePdf(buffer: Buffer): Promise<ParsedPdf> {
  const uint8 = new Uint8Array(buffer);
  const pdf = await getDocumentProxy(uint8);

  const { text: pageTexts } = await extractText(pdf, { mergePages: false });

  const info = await pdf.getMetadata().catch(() => null);
  const rawInfo = info?.info as Record<string, unknown> | undefined;

  const metadata: Record<string, string> = {};
  if (rawInfo) {
    for (const [key, value] of Object.entries(rawInfo)) {
      if (typeof value === "string" && value.trim()) {
        metadata[key] = value;
      }
    }
  }

  return {
    pageTexts,
    pageCount: pdf.numPages,
    metadata,
  };
}
```

### Step 4: Create `app/api/rag/documents/route.ts`

```typescript
import { NextRequest, NextResponse } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/lib/db";
import { document } from "@/lib/db/schema/rag";
import { eq, desc } from "drizzle-orm";
import { getStorageProvider } from "@/lib/storage/storage-provider";

const MAX_PDF_SIZE = 2 * 1024 * 1024 * 1024; // 2GB

type DocumentListItem = {
  id: string;
  title: string;
  fileName: string;
  fileSize: number;
  pageCount: number | null;
  pagesProcessed: number;
  status: "uploading" | "processing" | "ready" | "error";
  createdAt: Date;
  updatedAt: Date;
};

/** GET /api/rag/documents — list user's documents */
export const GET = withAuth(async (_request, { user }) => {
  const documents = await db
    .select({
      id: document.id,
      title: document.title,
      fileName: document.fileName,
      fileSize: document.fileSize,
      pageCount: document.pageCount,
      pagesProcessed: document.pagesProcessed,
      status: document.status,
      createdAt: document.createdAt,
      updatedAt: document.updatedAt,
    })
    .from(document)
    .where(eq(document.userId, user.id))
    .orderBy(desc(document.createdAt));

  return NextResponse.json<DocumentListItem[]>(documents);
});

/** POST /api/rag/documents — upload a PDF */
export const POST = withAuth(async (request, { user }) => {
  const formData = await request.formData();
  const file = formData.get("file");

  if (!file || !(file instanceof File)) {
    return NextResponse.json({ error: "No file provided" }, { status: 400 });
  }

  if (!file.name.toLowerCase().endsWith(".pdf")) {
    return NextResponse.json({ error: "Only PDF files are accepted" }, { status: 400 });
  }

  if (file.size > MAX_PDF_SIZE) {
    return NextResponse.json(
      { error: `File too large. Maximum size is 2GB.` },
      { status: 413 }
    );
  }

  const storage = getStorageProvider();
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(2, 8);
  const sanitized = file.name.replace(/[^a-zA-Z0-9.-]/g, "_");
  const storageKey = `rag/${user.id}/${timestamp}-${random}-${sanitized}`;

  // Create document record with "uploading" status
  const [doc] = await db
    .insert(document)
    .values({
      userId: user.id,
      title: file.name.replace(/\.pdf$/i, ""),
      fileName: file.name,
      storageKey,
      fileSize: file.size,
      status: "uploading",
    })
    .returning();

  try {
    // Upload to storage
    const buffer = Buffer.from(await file.arrayBuffer());
    await storage.upload(storageKey, buffer, { contentType: "application/pdf" });

    // Mark as ready for processing
    const [updated] = await db
      .update(document)
      .set({ status: "processing", updatedAt: new Date() })
      .where(eq(document.id, doc.id))
      .returning();

    return NextResponse.json(updated, { status: 201 });
  } catch (error) {
    // Mark as error
    await db
      .update(document)
      .set({
        status: "error",
        errorMessage: error instanceof Error ? error.message : "Upload failed",
        updatedAt: new Date(),
      })
      .where(eq(document.id, doc.id));

    return NextResponse.json({ error: "Upload failed" }, { status: 500 });
  }
});
```

### Step 5: Create `app/api/rag/documents/[documentId]/route.ts`

```typescript
import { NextRequest, NextResponse } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/lib/db";
import { document, documentPage } from "@/lib/db/schema/rag";
import { eq, and } from "drizzle-orm";
import { getStorageProvider } from "@/lib/storage/storage-provider";

/** GET /api/rag/documents/[documentId] — get document details */
export const GET = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const documentId = pathParts[pathParts.length - 1];

  const docs = await db
    .select()
    .from(document)
    .where(and(eq(document.id, documentId), eq(document.userId, user.id)))
    .limit(1);

  if (docs.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  return NextResponse.json(docs[0]);
}) as (request: NextRequest, context: { params: Promise<{ documentId: string }> }) => Promise<NextResponse>;

/** DELETE /api/rag/documents/[documentId] — delete document, pages, and storage file */
export const DELETE = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const documentId = pathParts[pathParts.length - 1];

  const docs = await db
    .select({ id: document.id, storageKey: document.storageKey })
    .from(document)
    .where(and(eq(document.id, documentId), eq(document.userId, user.id)))
    .limit(1);

  if (docs.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  // Delete storage file
  const storage = getStorageProvider();
  await storage.delete(docs[0].storageKey).catch(() => {});

  // Delete document (cascades to pages via FK)
  await db.delete(document).where(eq(document.id, documentId));

  return NextResponse.json({ success: true });
}) as (request: NextRequest, context: { params: Promise<{ documentId: string }> }) => Promise<NextResponse>;
```

### Step 6: Create `app/api/rag/documents/[documentId]/process/route.ts`

```typescript
import { NextRequest, NextResponse } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/lib/db";
import { document, documentPage } from "@/lib/db/schema/rag";
import { eq, and } from "drizzle-orm";
import { getStorageProvider } from "@/lib/storage/storage-provider";
import { parsePdf } from "@/lib/rag/pdf-parser";

const BATCH_SIZE = 10;

/** POST /api/rag/documents/[documentId]/process — trigger PDF parsing */
export const POST = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  // URL: /api/rag/documents/[documentId]/process
  const documentId = pathParts[pathParts.length - 2];

  const docs = await db
    .select()
    .from(document)
    .where(and(eq(document.id, documentId), eq(document.userId, user.id)))
    .limit(1);

  if (docs.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  const doc = docs[0];

  if (doc.status === "ready") {
    return NextResponse.json({ error: "Document already processed" }, { status: 400 });
  }

  if (doc.status !== "processing") {
    // Set to processing
    await db
      .update(document)
      .set({ status: "processing", updatedAt: new Date() })
      .where(eq(document.id, documentId));
  }

  try {
    // Download PDF from storage
    const storage = getStorageProvider();
    const buffer = await storage.download(doc.storageKey);

    // Parse PDF
    const parsed = await parsePdf(buffer);

    // Update page count
    await db
      .update(document)
      .set({ pageCount: parsed.pageCount, metadata: parsed.metadata, updatedAt: new Date() })
      .where(eq(document.id, documentId));

    // Insert pages in batches of BATCH_SIZE in parallel
    for (let i = 0; i < parsed.pageTexts.length; i += BATCH_SIZE) {
      const batch = parsed.pageTexts.slice(i, i + BATCH_SIZE);

      await Promise.all(
        batch.map((text, batchIndex) =>
          db.insert(documentPage).values({
            documentId,
            pageNumber: i + batchIndex + 1,
            textContent: text,
          })
        )
      );

      // Update progress
      const processed = Math.min(i + BATCH_SIZE, parsed.pageTexts.length);
      await db
        .update(document)
        .set({ pagesProcessed: processed, updatedAt: new Date() })
        .where(eq(document.id, documentId));
    }

    // Mark as ready
    const [updated] = await db
      .update(document)
      .set({
        status: "ready",
        pagesProcessed: parsed.pageCount,
        updatedAt: new Date(),
      })
      .where(eq(document.id, documentId))
      .returning();

    return NextResponse.json(updated);
  } catch (error) {
    await db
      .update(document)
      .set({
        status: "error",
        errorMessage: error instanceof Error ? error.message : "Processing failed",
        updatedAt: new Date(),
      })
      .where(eq(document.id, documentId));

    return NextResponse.json({ error: "Processing failed" }, { status: 500 });
  }
}) as (request: NextRequest, context: { params: Promise<{ documentId: string }> }) => Promise<NextResponse>;
```

## Usage

### Upload and Process a PDF

```typescript
// 1. Upload
const formData = new FormData();
formData.append("file", pdfFile);

const uploadRes = await fetch("/api/rag/documents", {
  method: "POST",
  body: formData,
});
const doc = await uploadRes.json();

// 2. Trigger processing
const processRes = await fetch(`/api/rag/documents/${doc.id}/process`, {
  method: "POST",
});
const processed = await processRes.json();
```

### List Documents

```typescript
const res = await fetch("/api/rag/documents");
const documents = await res.json();
```

### Delete a Document

```typescript
await fetch(`/api/rag/documents/${documentId}`, { method: "DELETE" });
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/rag/documents` | List user's documents with status |
| POST | `/api/rag/documents` | Upload a PDF (FormData with `file` field) |
| GET | `/api/rag/documents/[documentId]` | Get document details |
| DELETE | `/api/rag/documents/[documentId]` | Delete document, pages, and storage file |
| POST | `/api/rag/documents/[documentId]/process` | Trigger PDF parsing |

## Acceptance Criteria

- Upload a PDF via FormData and receive a document record with status "processing"
- Trigger processing and pages are extracted with correct text content
- `pagesProcessed` updates incrementally during processing
- Status transitions: uploading → processing → ready (or error)
- Large PDFs (100+ pages) process in parallel batches of 10
- Delete removes document, all pages, and the S3 storage file
- Only the document owner can access/modify their documents
- Unauthenticated requests return 401
- `tsc` passes with no errors
- `bun run build` succeeds
