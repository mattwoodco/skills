---
name: knowledge-sync
description: External knowledge sync — fetches data from an external REST API, maps items to RAG documents, ingests and indexes them via the RAG pipeline, with on-demand and scheduled sync. Use this skill when the user says "sync knowledge", "import knowledge base", "setup knowledge-sync", "external data ingestion", or "connect knowledge API".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-14
updated: 2026-02-14
dependencies: [ai-rag-ingest, ai-rag-vectors, auth, docker]
---

# Knowledge Sync

Fetches knowledge items from an external REST API, maps them into the RAG document pipeline, and indexes them for vector search. Supports on-demand sync via API call and tracks sync history with per-item status.

Designed to bridge an existing knowledge base (e.g. a voice agent's knowledge items) with the RAG-powered chat assistant so both systems draw from the same source of truth.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `ai-rag-ingest` skill installed (`document` + `documentPage` tables in `@/db/schema/rag`)
- `ai-rag-vectors` skill installed (`indexDocument()` at `@/lib/rag/embeddings`)
- `auth` skill installed (`withAuth` at `@/lib/auth-guard`)
- `docker` skill installed (PostgreSQL running)

## Installation

No additional packages required. Uses existing `drizzle-orm` and `ai` packages.

## Environment Variables

Add to `.env.local`:

```env
# Knowledge Sync
KNOWLEDGE_API_URL=https://api.example.com/v1/knowledge
KNOWLEDGE_API_KEY=your-api-key-here
```

### Update `src/env.ts`

Add to the `server` object:

```typescript
  server: {
    // ... existing variables
    KNOWLEDGE_API_URL: z.string().url(),
    KNOWLEDGE_API_KEY: z.string(),
  },
```

Add to the `runtimeEnv` object:

```typescript
  runtimeEnv: {
    // ... existing variables
    KNOWLEDGE_API_URL: process.env.KNOWLEDGE_API_URL,
    KNOWLEDGE_API_KEY: process.env.KNOWLEDGE_API_KEY,
  },
```

## What Gets Created

```
src/
├── db/
│   └── schema/
│       └── knowledge-sync.ts                  # syncJob + syncItem tables
├── lib/
│   └── knowledge/
│       ├── fetcher.ts                         # Fetch items from external API
│       ├── mapper.ts                          # Map external items → RAG documents
│       └── sync.ts                            # Orchestrate fetch → ingest → index
└── app/
    └── api/
        └── knowledge/
            ├── sync/
            │   └── route.ts                   # POST — trigger sync, GET — list sync jobs
            └── sources/
                └── route.ts                   # GET — list synced knowledge sources
```

## Database

After applying this skill, push the schema:

```bash
bunx drizzle-kit push
```

## Setup Steps

### Step 1: Create `src/db/schema/knowledge-sync.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  integer,
  pgEnum,
} from "drizzle-orm/pg-core";

export const syncStatusEnum = pgEnum("sync_status", [
  "pending",
  "running",
  "completed",
  "failed",
]);

export const syncItemStatusEnum = pgEnum("sync_item_status", [
  "pending",
  "ingested",
  "indexed",
  "error",
]);

export const syncJob = pgTable("sync_job", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull(),
  status: syncStatusEnum("status").notNull().default("pending"),
  totalItems: integer("total_items").notNull().default(0),
  processedItems: integer("processed_items").notNull().default(0),
  failedItems: integer("failed_items").notNull().default(0),
  errorMessage: text("error_message"),
  startedAt: timestamp("started_at", { withTimezone: true }),
  completedAt: timestamp("completed_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});

export const syncItem = pgTable("sync_item", {
  id: uuid("id").defaultRandom().primaryKey(),
  syncJobId: uuid("sync_job_id")
    .notNull()
    .references(() => syncJob.id, { onDelete: "cascade" }),
  externalId: text("external_id").notNull(),
  title: text("title").notNull(),
  documentId: uuid("document_id"),
  status: syncItemStatusEnum("status").notNull().default("pending"),
  errorMessage: text("error_message"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).defaultNow().notNull(),
});

export type SyncJob = typeof syncJob.$inferSelect;
export type SyncItem = typeof syncItem.$inferSelect;
```

### Step 2: Add export to `src/db/schema/index.ts`

Find the last `export * from` line and add:

```typescript
export * from "./knowledge-sync";
```

### Step 3: Create `src/lib/knowledge/fetcher.ts`

```typescript
type ExternalKnowledgeItem = {
  id: string;
  title: string;
  content: string;
  category?: string;
  updatedAt?: string;
};

type FetchKnowledgeResult = {
  items: ExternalKnowledgeItem[];
  total: number;
};

/**
 * Fetch knowledge items from the external API.
 *
 * Adjust the response parsing to match your API's shape.
 * This implementation expects: { items: [...], total: number }
 */
export async function fetchKnowledgeItems(): Promise<FetchKnowledgeResult> {
  const apiUrl = process.env.KNOWLEDGE_API_URL;
  const apiKey = process.env.KNOWLEDGE_API_KEY;

  if (!apiUrl || !apiKey) {
    throw new Error("KNOWLEDGE_API_URL and KNOWLEDGE_API_KEY must be set");
  }

  const response = await fetch(apiUrl, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Knowledge API error ${response.status}: ${errorText}`
    );
  }

  const data = (await response.json()) as FetchKnowledgeResult;

  return {
    items: data.items,
    total: data.total,
  };
}

export type { ExternalKnowledgeItem };
```

### Step 4: Create `src/lib/knowledge/mapper.ts`

```typescript
import type { ExternalKnowledgeItem } from "./fetcher";

type MappedDocument = {
  externalId: string;
  title: string;
  pageTexts: string[];
  metadata: Record<string, string>;
};

/**
 * Map an external knowledge item into the shape expected by the RAG pipeline.
 *
 * Each item becomes a single "document" with one "page" containing the full text.
 * For longer content, this splits into multiple pages of ~4000 chars to improve
 * chunking and retrieval quality.
 */
export function mapToDocument(item: ExternalKnowledgeItem): MappedDocument {
  const MAX_PAGE_SIZE = 4000;
  const content = item.content.trim();

  // Split long content into pages
  const pageTexts: string[] = [];

  if (content.length <= MAX_PAGE_SIZE) {
    pageTexts.push(content);
  } else {
    // Split on paragraph boundaries
    const paragraphs = content.split(/\n\n+/);
    let currentPage = "";

    for (const paragraph of paragraphs) {
      if (currentPage.length + paragraph.length + 2 > MAX_PAGE_SIZE && currentPage) {
        pageTexts.push(currentPage.trim());
        currentPage = paragraph;
      } else {
        currentPage = currentPage ? `${currentPage}\n\n${paragraph}` : paragraph;
      }
    }

    if (currentPage.trim()) {
      pageTexts.push(currentPage.trim());
    }
  }

  const metadata: Record<string, string> = {
    source: "knowledge-sync",
    externalId: item.id,
  };

  if (item.category) {
    metadata.category = item.category;
  }

  if (item.updatedAt) {
    metadata.externalUpdatedAt = item.updatedAt;
  }

  return {
    externalId: item.id,
    title: item.title,
    pageTexts,
    metadata,
  };
}
```

### Step 5: Create `src/lib/knowledge/sync.ts`

```typescript
import { eq } from "drizzle-orm";
import { db } from "@/db";
import { document, documentPage } from "@/db/schema/rag";
import { syncJob, syncItem } from "@/db/schema/knowledge-sync";
import { indexDocument } from "@/lib/rag/embeddings";
import { fetchKnowledgeItems } from "./fetcher";
import { mapToDocument } from "./mapper";

/**
 * Run a full knowledge sync:
 * 1. Fetch items from external API
 * 2. Map each to a RAG document
 * 3. Insert document + pages into Postgres
 * 4. Generate embeddings and index
 * 5. Track status per item
 */
export async function runKnowledgeSync(userId: string): Promise<string> {
  // Create sync job
  const [job] = await db
    .insert(syncJob)
    .values({
      userId,
      status: "running",
      startedAt: new Date(),
    })
    .returning();

  try {
    // Fetch external items
    const { items } = await fetchKnowledgeItems();

    await db
      .update(syncJob)
      .set({ totalItems: items.length })
      .where(eq(syncJob.id, job.id));

    let processedCount = 0;
    let failedCount = 0;

    for (const externalItem of items) {
      const mapped = mapToDocument(externalItem);

      // Create sync item record
      const [itemRecord] = await db
        .insert(syncItem)
        .values({
          syncJobId: job.id,
          externalId: mapped.externalId,
          title: mapped.title,
          status: "pending",
        })
        .returning();

      try {
        // Create the RAG document
        const [doc] = await db
          .insert(document)
          .values({
            userId,
            title: mapped.title,
            fileName: `knowledge-${mapped.externalId}.txt`,
            storageKey: `knowledge-sync/${mapped.externalId}`,
            fileSize: mapped.pageTexts.join("").length,
            pageCount: mapped.pageTexts.length,
            pagesProcessed: mapped.pageTexts.length,
            status: "ready",
            metadata: mapped.metadata,
          })
          .returning();

        // Insert pages
        for (let pageIdx = 0; pageIdx < mapped.pageTexts.length; pageIdx++) {
          await db.insert(documentPage).values({
            documentId: doc.id,
            pageNumber: pageIdx + 1,
            textContent: mapped.pageTexts[pageIdx],
          });
        }

        // Update sync item with document reference
        await db
          .update(syncItem)
          .set({
            documentId: doc.id,
            status: "ingested",
            updatedAt: new Date(),
          })
          .where(eq(syncItem.id, itemRecord.id));

        // Index for vector search
        await indexDocument(doc.id);

        await db
          .update(syncItem)
          .set({ status: "indexed", updatedAt: new Date() })
          .where(eq(syncItem.id, itemRecord.id));

        processedCount++;
      } catch (itemError) {
        failedCount++;
        await db
          .update(syncItem)
          .set({
            status: "error",
            errorMessage:
              itemError instanceof Error
                ? itemError.message
                : "Processing failed",
            updatedAt: new Date(),
          })
          .where(eq(syncItem.id, itemRecord.id));
      }

      // Update job progress
      await db
        .update(syncJob)
        .set({
          processedItems: processedCount + failedCount,
          failedItems: failedCount,
        })
        .where(eq(syncJob.id, job.id));
    }

    // Mark job completed
    await db
      .update(syncJob)
      .set({
        status: "completed",
        processedItems: processedCount + failedCount,
        failedItems: failedCount,
        completedAt: new Date(),
      })
      .where(eq(syncJob.id, job.id));

    return job.id;
  } catch (error) {
    await db
      .update(syncJob)
      .set({
        status: "failed",
        errorMessage:
          error instanceof Error ? error.message : "Sync failed",
        completedAt: new Date(),
      })
      .where(eq(syncJob.id, job.id));

    return job.id;
  }
}
```

### Step 6: Create `src/app/api/knowledge/sync/route.ts`

```typescript
import { NextResponse } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/db";
import { syncJob, syncItem } from "@/db/schema/knowledge-sync";
import { eq, desc } from "drizzle-orm";
import { runKnowledgeSync } from "@/lib/knowledge/sync";

/** GET /api/knowledge/sync — list sync jobs for the current user */
export const GET = withAuth(async (_request, { user }) => {
  const jobs = await db
    .select()
    .from(syncJob)
    .where(eq(syncJob.userId, user.id))
    .orderBy(desc(syncJob.createdAt))
    .limit(20);

  return NextResponse.json(jobs);
});

/** POST /api/knowledge/sync — trigger a knowledge sync */
export const POST = withAuth(async (_request, { user }) => {
  // Check if there's already a running sync
  const running = await db
    .select({ id: syncJob.id })
    .from(syncJob)
    .where(eq(syncJob.userId, user.id))
    .orderBy(desc(syncJob.createdAt))
    .limit(1);

  if (running.length > 0) {
    const latestJob = await db
      .select()
      .from(syncJob)
      .where(eq(syncJob.id, running[0].id))
      .limit(1);

    if (latestJob[0]?.status === "running") {
      return NextResponse.json(
        { error: "A sync is already in progress", jobId: latestJob[0].id },
        { status: 409 }
      );
    }
  }

  // Run sync (this runs inline — for production, consider a background job)
  const jobId = await runKnowledgeSync(user.id);

  const [job] = await db
    .select()
    .from(syncJob)
    .where(eq(syncJob.id, jobId))
    .limit(1);

  return NextResponse.json(job, { status: 201 });
});
```

### Step 7: Create `src/app/api/knowledge/sources/route.ts`

```typescript
import { NextResponse } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/db";
import { document } from "@/db/schema/rag";
import { eq, desc, sql } from "drizzle-orm";

type KnowledgeSource = {
  id: string;
  title: string;
  pageCount: number | null;
  status: string;
  category: string | null;
  externalId: string | null;
  createdAt: Date;
};

/** GET /api/knowledge/sources — list synced knowledge documents */
export const GET = withAuth(async (_request, { user }) => {
  const docs = await db
    .select({
      id: document.id,
      title: document.title,
      pageCount: document.pageCount,
      status: document.status,
      metadata: document.metadata,
      createdAt: document.createdAt,
    })
    .from(document)
    .where(eq(document.userId, user.id))
    .orderBy(desc(document.createdAt));

  const sources: KnowledgeSource[] = docs
    .filter((d) => {
      const meta = d.metadata as Record<string, string> | null;
      return meta?.source === "knowledge-sync";
    })
    .map((d) => {
      const meta = d.metadata as Record<string, string> | null;
      return {
        id: d.id,
        title: d.title,
        pageCount: d.pageCount,
        status: d.status,
        category: meta?.category ?? null,
        externalId: meta?.externalId ?? null,
        createdAt: d.createdAt,
      };
    });

  return NextResponse.json(sources);
});
```

## Usage

### Trigger a Sync

```typescript
const res = await fetch("/api/knowledge/sync", { method: "POST" });
const job = await res.json();
// job = { id, status: "completed", totalItems: 15, processedItems: 15, failedItems: 0 }
```

### Check Sync History

```typescript
const res = await fetch("/api/knowledge/sync");
const jobs = await res.json();
// jobs[0] = { id, status, totalItems, processedItems, failedItems, startedAt, completedAt }
```

### List Synced Sources

```typescript
const res = await fetch("/api/knowledge/sources");
const sources = await res.json();
// sources[0] = { id, title, pageCount, status, category, externalId }
```

### Customizing the External API Shape

Edit `src/lib/knowledge/fetcher.ts` to match your API:

```typescript
// Example: API returns { data: [...], count: number }
const data = await response.json();
return {
  items: data.data.map((item) => ({
    id: item.knowledge_id,
    title: item.name,
    content: item.body,
    category: item.type,
    updatedAt: item.modified_at,
  })),
  total: data.count,
};
```

### Customizing the Document Mapping

Edit `src/lib/knowledge/mapper.ts` to adjust how items become RAG documents:

```typescript
// Example: add custom metadata fields
metadata.businessId = item.businessId;
metadata.language = item.language ?? "en";
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/knowledge/sync` | Trigger a knowledge sync from external API |
| GET | `/api/knowledge/sync` | List sync job history |
| GET | `/api/knowledge/sources` | List documents created by knowledge sync |

## Acceptance Criteria

- Trigger a sync and external knowledge items are fetched from the configured API
- Each item creates a `document` + `documentPage` records in the RAG schema
- Each document is automatically indexed (vector embeddings generated)
- Sync job tracks progress: totalItems, processedItems, failedItems
- Individual item errors don't fail the entire sync (partial success)
- Sync status transitions: pending → running → completed (or failed)
- Duplicate sync requests while running return 409
- Synced documents are queryable via the existing RAG search endpoints
- `KNOWLEDGE_API_URL` and `KNOWLEDGE_API_KEY` are never exposed to the client
- Unauthenticated requests return 401
- `tsc` passes with no errors
- `bun run build` succeeds
