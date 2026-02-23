---
name: ai-rag-vectors
description: Vector embeddings layer — pgvector for Postgres, embedding generation via AI Gateway, recursive text chunking with overlap, cosine similarity search, and automatic indexing of parsed document pages. Use this skill when the user says "setup vectors", "add embeddings", "setup ai-rag-vectors", or "add semantic search".
author: "@mattwoodco"
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
validated: 2026-02-13
dependencies: [db, ai-core, ai-rag-ingest, docker]
---

# AI RAG Vectors

Vector embedding layer that chunks parsed PDF pages, generates embeddings via AI Gateway, stores them in pgvector, and provides cosine similarity search for RAG retrieval.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `db` skill installed (Drizzle ORM + Postgres)
- `ai-core` skill installed (`getModel()` at `@src/lib/ai`)
- `ai-rag-ingest` skill installed (`document` + `documentPage` tables in `@/db/schema/rag`)
- Docker running with PostgreSQL

## Installation

```bash
bun add ai
```

> `ai` is likely already installed from `ai-core`. No additional packages needed — pgvector is a Postgres extension, and embeddings use the AI SDK `embed`/`embedMany` functions.

## Docker Update

Update your `docker-compose.yml` to use the pgvector image instead of plain Postgres:

Find this:

```yaml
  db:
    image: postgres:17-alpine
```

Replace with:

```yaml
  db:
    image: pgvector/pgvector:pg17
```

After updating, recreate the container:

```bash
docker compose down db && docker compose up -d db
```

## What Gets Created

```
src/
├── db/
│   └── schema/
│       └── rag.ts                          # Add documentChunk table (extend existing)
├── lib/
│   └── rag/
│       ├── chunker.ts                      # Recursive text splitter
│       ├── embeddings.ts                   # embed/embedMany wrappers + indexDocument()
│       └── search.ts                       # searchChunks() semantic search
└── app/
    └── api/
        └── rag/
            ├── documents/
            │   └── [documentId]/
            │       └── index/
            │           └── route.ts        # POST trigger indexing
            └── search/
                └── route.ts                # POST semantic search
```

## Database

After applying this skill, enable the pgvector extension and push the schema:

```bash
# Enable pgvector extension (run once)
docker exec -it postgres psql -U postgres -d app -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Push schema
bunx drizzle-kit push
```

Then create the HNSW index for fast cosine similarity search:

```bash
docker exec -it postgres psql -U postgres -d app -c "CREATE INDEX IF NOT EXISTS document_chunk_embedding_idx ON document_chunk USING hnsw (embedding vector_cosine_ops);"
```

## Setup Steps

### Step 1: Extend `src/db/schema/rag.ts`

Add the `documentChunk` table and the custom vector column type to the existing RAG schema file.

Add these imports at the top:

```typescript
import { customType } from "drizzle-orm/pg-core";
```

Add this after the existing `documentPage` table:

```typescript
const vector = customType<{ data: number[]; dpiType: string }>({
  dataType() {
    return "vector(768)";
  },
  toDriver(value: number[]): string {
    return `[${value.join(",")}]`;
  },
  fromDriver(value: unknown): number[] {
    if (typeof value === "string") {
      return value
        .replace(/[\[\]]/g, "")
        .split(",")
        .map(Number);
    }
    return value as number[];
  },
});

export const documentChunk = pgTable("document_chunk", {
  id: uuid("id").defaultRandom().primaryKey(),
  documentId: uuid("document_id")
    .notNull()
    .references(() => document.id, { onDelete: "cascade" }),
  pageNumber: integer("page_number").notNull(),
  chunkIndex: integer("chunk_index").notNull(),
  textContent: text("text_content").notNull(),
  embedding: vector("embedding"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});
```

### Step 2: Create `src/lib/rag/chunker.ts`

```typescript
type Chunk = {
  text: string;
  pageNumber: number;
  chunkIndex: number;
};

const CHUNK_SIZE = 2000; // ~512 tokens
const CHUNK_OVERLAP = 200;

const SEPARATORS = ["\n\n", "\n", ". ", " ", ""];

/**
 * Recursive text splitter that respects paragraph/sentence boundaries.
 * Splits on the largest separator that produces chunks within the size limit.
 */
function splitText(text: string, separators: string[]): string[] {
  if (text.length <= CHUNK_SIZE) {
    return [text];
  }

  const separator = separators[0];
  const nextSeparators = separators.slice(1);

  if (separator === "") {
    // Last resort: hard split by character count
    const chunks: string[] = [];
    for (let i = 0; i < text.length; i += CHUNK_SIZE - CHUNK_OVERLAP) {
      chunks.push(text.slice(i, i + CHUNK_SIZE));
    }
    return chunks;
  }

  const parts = text.split(separator);
  const chunks: string[] = [];
  let current = "";

  for (const part of parts) {
    const candidate = current ? current + separator + part : part;

    if (candidate.length > CHUNK_SIZE) {
      if (current) {
        chunks.push(current);
      }

      if (part.length > CHUNK_SIZE) {
        // Part itself is too large — recurse with finer separators
        const subChunks = splitText(part, nextSeparators);
        chunks.push(...subChunks);
        current = "";
      } else {
        current = part;
      }
    } else {
      current = candidate;
    }
  }

  if (current.trim()) {
    chunks.push(current);
  }

  return chunks;
}

/**
 * Add overlap between adjacent chunks for context continuity.
 */
function addOverlap(chunks: string[]): string[] {
  if (chunks.length <= 1) return chunks;

  const result: string[] = [chunks[0]];

  for (let i = 1; i < chunks.length; i++) {
    const prevChunk = chunks[i - 1];
    const overlap = prevChunk.slice(-CHUNK_OVERLAP);
    result.push(overlap + chunks[i]);
  }

  return result;
}

/**
 * Chunk an array of page texts into overlapping chunks with metadata.
 * @param pageTexts - Array of text strings, one per page (1-indexed page numbers)
 * @returns Array of chunks with page number and chunk index
 */
export function chunkPages(pageTexts: string[]): Chunk[] {
  const allChunks: Chunk[] = [];

  for (let pageIdx = 0; pageIdx < pageTexts.length; pageIdx++) {
    const pageText = pageTexts[pageIdx].trim();
    if (!pageText) continue;

    const rawChunks = splitText(pageText, SEPARATORS);
    const overlappedChunks = addOverlap(rawChunks);

    for (let chunkIdx = 0; chunkIdx < overlappedChunks.length; chunkIdx++) {
      const text = overlappedChunks[chunkIdx].trim();
      if (!text) continue;

      allChunks.push({
        text,
        pageNumber: pageIdx + 1,
        chunkIndex: chunkIdx,
      });
    }
  }

  return allChunks;
}
```

### Step 3: Create `src/lib/rag/embeddings.ts`

```typescript
import { embed, embedMany } from "ai";
import { gateway } from "@ai-sdk/gateway";
import { db } from "@src/lib/db";
import { documentPage, documentChunk, document } from "@src/lib/db/schema/rag";
import { eq } from "drizzle-orm";
import { chunkPages } from "./chunker";

const EMBEDDING_MODEL = "google/text-embedding-004";
const EMBED_BATCH_SIZE = 50;

function getEmbeddingModel() {
  return gateway.textEmbeddingModel(EMBEDDING_MODEL);
}

/**
 * Generate a single embedding vector for a text string.
 */
export async function embedText(text: string): Promise<number[]> {
  const { embedding } = await embed({
    model: getEmbeddingModel(),
    value: text,
  });
  return embedding;
}

/**
 * Generate embeddings for multiple text strings in batch.
 */
export async function embedTexts(texts: string[]): Promise<number[][]> {
  const { embeddings } = await embedMany({
    model: getEmbeddingModel(),
    values: texts,
  });
  return embeddings;
}

/**
 * Index a document: chunk all pages, generate embeddings, and store in documentChunk table.
 * Call this after ai-rag-ingest has processed the document (status = "ready").
 */
export async function indexDocument(documentId: string): Promise<number> {
  // Fetch all pages for the document
  const pages = await db
    .select({
      pageNumber: documentPage.pageNumber,
      textContent: documentPage.textContent,
    })
    .from(documentPage)
    .where(eq(documentPage.documentId, documentId))
    .orderBy(documentPage.pageNumber);

  if (pages.length === 0) {
    throw new Error("No pages found for document. Process the PDF first.");
  }

  // Build page text array (pages are 1-indexed, array is 0-indexed)
  const pageTexts = pages.map((p) => p.textContent);

  // Chunk the pages
  const chunks = chunkPages(pageTexts);

  if (chunks.length === 0) {
    return 0;
  }

  // Delete existing chunks for this document (re-indexing)
  await db.delete(documentChunk).where(eq(documentChunk.documentId, documentId));

  // Generate embeddings and insert in batches
  let totalInserted = 0;

  for (let i = 0; i < chunks.length; i += EMBED_BATCH_SIZE) {
    const batch = chunks.slice(i, i + EMBED_BATCH_SIZE);
    const texts = batch.map((c) => c.text);

    const embeddings = await embedTexts(texts);

    const values = batch.map((chunk, idx) => ({
      documentId,
      pageNumber: chunk.pageNumber,
      chunkIndex: chunk.chunkIndex,
      textContent: chunk.text,
      embedding: embeddings[idx],
    }));

    await db.insert(documentChunk).values(values);
    totalInserted += values.length;
  }

  // Update document metadata
  await db
    .update(document)
    .set({ updatedAt: new Date() })
    .where(eq(document.id, documentId));

  return totalInserted;
}
```

### Step 4: Create `src/lib/rag/search.ts`

```typescript
import { sql, and, inArray } from "drizzle-orm";
import { db } from "@src/lib/db";
import { documentChunk, document } from "@src/lib/db/schema/rag";
import { embedText } from "./embeddings";

type SearchResult = {
  chunkId: string;
  documentId: string;
  documentTitle: string;
  pageNumber: number;
  chunkIndex: number;
  textContent: string;
  similarity: number;
};

type SearchOptions = {
  query: string;
  documentIds?: string[];
  limit?: number;
  userId?: string;
};

/**
 * Semantic search across document chunks using cosine similarity.
 * Returns ranked results with chunk text, page number, and similarity score.
 */
export async function searchChunks(options: SearchOptions): Promise<SearchResult[]> {
  const { query, documentIds, limit = 10, userId } = options;

  // Embed the query
  const queryEmbedding = await embedText(query);
  const vectorStr = `[${queryEmbedding.join(",")}]`;

  // Build conditions
  const conditions = [];

  if (documentIds && documentIds.length > 0) {
    conditions.push(inArray(documentChunk.documentId, documentIds));
  }

  if (userId) {
    conditions.push(sql`${documentChunk.documentId} IN (
      SELECT ${document.id} FROM ${document} WHERE ${document.userId} = ${userId}
    )`);
  }

  const whereClause =
    conditions.length > 0
      ? sql`WHERE ${and(...conditions)}`
      : sql``;

  const results = await db.execute(sql`
    SELECT
      dc.id AS chunk_id,
      dc.document_id,
      d.title AS document_title,
      dc.page_number,
      dc.chunk_index,
      dc.text_content,
      1 - (dc.embedding <=> ${vectorStr}::vector) AS similarity
    FROM document_chunk dc
    JOIN document d ON d.id = dc.document_id
    ${whereClause}
    ORDER BY dc.embedding <=> ${vectorStr}::vector ASC
    LIMIT ${limit}
  `);

  return (results as unknown as Record<string, unknown>[]).map((row) => ({
    chunkId: String(row.chunk_id),
    documentId: String(row.document_id),
    documentTitle: String(row.document_title),
    pageNumber: Number(row.page_number),
    chunkIndex: Number(row.chunk_index),
    textContent: String(row.text_content),
    similarity: Number(row.similarity),
  }));
}
```

### Step 5: Create `src/app/api/rag/documents/[documentId]/index/route.ts`

```typescript
import { NextRequest, NextResponse } from "next/server";
import { withAuth } from "@src/lib/auth-guard";
import { db } from "@src/lib/db";
import { document } from "@src/lib/db/schema/rag";
import { eq, and } from "drizzle-orm";
import { indexDocument } from "@src/lib/rag/embeddings";

/** POST /api/rag/documents/[documentId]/index — trigger embedding indexing */
export const POST = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  // URL: /api/rag/documents/[documentId]/index
  const documentId = pathParts[pathParts.length - 2];

  const docs = await db
    .select({ id: document.id, status: document.status })
    .from(document)
    .where(and(eq(document.id, documentId), eq(document.userId, user.id)))
    .limit(1);

  if (docs.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  if (docs[0].status !== "ready") {
    return NextResponse.json(
      { error: "Document must be fully processed before indexing. Current status: " + docs[0].status },
      { status: 400 }
    );
  }

  try {
    const chunksIndexed = await indexDocument(documentId);
    return NextResponse.json({ success: true, chunksIndexed });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Indexing failed" },
      { status: 500 }
    );
  }
}) as (request: NextRequest, context: { params: Promise<{ documentId: string }> }) => Promise<NextResponse>;
```

### Step 6: Create `src/app/api/rag/search/route.ts`

```typescript
import { NextResponse } from "next/server";
import { withAuth } from "@src/lib/auth-guard";
import { searchChunks } from "@src/lib/rag/search";

type SearchBody = {
  query: string;
  documentIds?: string[];
  limit?: number;
};

/** POST /api/rag/search — semantic search across user's documents */
export const POST = withAuth(async (request, { user }) => {
  const body: SearchBody = await request.json();

  if (!body.query || typeof body.query !== "string" || !body.query.trim()) {
    return NextResponse.json({ error: "Query is required" }, { status: 400 });
  }

  const results = await searchChunks({
    query: body.query.trim(),
    documentIds: body.documentIds,
    limit: body.limit ?? 10,
    userId: user.id,
  });

  return NextResponse.json({ results });
});
```

## Usage

### Index a Document

```typescript
// After document is processed (status = "ready"):
const res = await fetch(`/api/rag/documents/${documentId}/index`, {
  method: "POST",
});
const { chunksIndexed } = await res.json();
```

### Semantic Search

```typescript
const res = await fetch("/api/rag/search", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    query: "What are the key findings?",
    documentIds: ["doc-uuid-1", "doc-uuid-2"], // optional filter
    limit: 5,
  }),
});
const { results } = await res.json();
// results[0] = { chunkId, documentId, documentTitle, pageNumber, chunkIndex, textContent, similarity }
```

### Programmatic Usage

```typescript
import { indexDocument } from "@src/lib/rag/embeddings";
import { searchChunks } from "@src/lib/rag/search";

// Index
const count = await indexDocument("doc-uuid");

// Search
const results = await searchChunks({
  query: "machine learning applications",
  userId: "user-123",
  limit: 5,
});
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/rag/documents/[documentId]/index` | Generate embeddings for a processed document |
| POST | `/api/rag/search` | Semantic search `{ query, documentIds?, limit? }` |

## Acceptance Criteria

- pgvector extension is enabled in Postgres
- Docker uses `pgvector/pgvector:pg17` image
- Text chunking produces overlapping chunks of ~2000 chars
- Embeddings are generated via AI Gateway using `google/text-embedding-004`
- Chunks are stored in `document_chunk` with 768-dimension vectors
- `searchChunks()` returns ranked results by cosine similarity
- Search filters by `documentIds` and/or `userId`
- HNSW index exists on the embedding column for fast search
- Re-indexing a document replaces existing chunks
- Unauthenticated requests return 401
- `tsc` passes with no errors
- `bun run build` succeeds
