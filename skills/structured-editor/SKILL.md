---
name: structured-editor
description: Section-based document editor — documents composed of named, typed sections that render as collapsible React components with inline editing, status badges, and annotation support. Use this skill when the user says "add structured editor", "section editor", "spec editor", "document builder", or "structured document".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
updated: 2026-02-18
dependencies: [add-shadcn, db, auth]
---

# Structured Editor

Section-based document editor where documents are composed of named, typed sections (Summary, User Stories, Acceptance Criteria, Edge Cases, Error States, Dependencies, Open Questions) that render as collapsible React components with inline editing, status badges, and annotation support.

A document is a collection of typed sections. Each section has: title, type, content (JSON), status, and sort order. Annotations are comments attached to sections from users or AI agents.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `add-shadcn` skill installed (shadcn/ui components available)
- `db` skill installed (Drizzle ORM at `@/lib/db`, Postgres running)
- `auth` skill installed (`withAuth` available at `@/lib/auth-guard`)

## Installation

```bash
bunx shadcn@latest add collapsible badge dropdown-menu textarea
```

## What Gets Created

```
src/
├── lib/
│   └── db/
│       └── schema/
│           └── document.ts                # specDocument, specSection, specAnnotation tables
├── app/
│   └── api/
│       └── documents/
│           ├── route.ts                   # GET (list), POST (create)
│           ├── [documentId]/
│           │   ├── route.ts               # GET, PATCH, DELETE
│           │   └── sections/
│           │       ├── route.ts           # GET (list sections), POST (add section)
│           │       └── [sectionId]/
│           │           ├── route.ts       # PATCH, DELETE section
│           │           └── annotations/
│           │               └── route.ts   # GET, POST annotations
└── components/
    └── editor/
        ├── document-editor.tsx            # Main editor — renders all sections
        ├── section-card.tsx               # Single section: collapse, edit, status, annotations
        ├── section-content.tsx            # Content renderer by section type
        ├── section-toolbar.tsx            # Status badge, annotation count, actions
        ├── annotation-list.tsx            # Inline annotation thread on a section
        └── add-section-button.tsx         # Button to add new section with type picker
```

## What Gets Modified

```
src/
└── lib/
    └── db/
        └── schema/
            └── index.ts                   # Add document schema export
```

## Database

After applying this skill, push the schema to create the `spec_document`, `spec_section`, and `spec_annotation` tables:

```bash
bunx drizzle-kit push
```

## Section Types and Content Shapes

Each section type has a specific content JSON shape:

| Type | Content Shape |
|------|--------------|
| `summary` | `{ text: string }` |
| `user_stories` | `{ items: Array<{ id: string; persona: string; action: string; benefit: string }> }` |
| `acceptance_criteria` | `{ items: Array<{ id: string; criterion: string; checked: boolean }> }` |
| `edge_cases` | `{ items: Array<{ id: string; scenario: string; expectedBehavior: string }> }` |
| `error_states` | `{ items: Array<{ id: string; trigger: string; userMessage: string; recovery: string }> }` |
| `dependencies` | `{ items: Array<{ id: string; name: string; type: "api" \| "service" \| "feature" \| "data"; status: "ready" \| "in_progress" \| "blocked" }> }` |
| `open_questions` | `{ items: Array<{ id: string; question: string; answer: string \| null; resolved: boolean }> }` |
| `custom` | `{ text: string }` |

## Setup Steps

### Step 1: Create `src/lib/db/schema/document.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  json,
  integer,
  boolean,
} from "drizzle-orm/pg-core";

// --- Section content types ---

type SummaryContent = { text: string };

type UserStoryItem = {
  id: string;
  persona: string;
  action: string;
  benefit: string;
};
type UserStoriesContent = { items: UserStoryItem[] };

type AcceptanceCriterionItem = {
  id: string;
  criterion: string;
  checked: boolean;
};
type AcceptanceCriteriaContent = { items: AcceptanceCriterionItem[] };

type EdgeCaseItem = {
  id: string;
  scenario: string;
  expectedBehavior: string;
};
type EdgeCasesContent = { items: EdgeCaseItem[] };

type ErrorStateItem = {
  id: string;
  trigger: string;
  userMessage: string;
  recovery: string;
};
type ErrorStatesContent = { items: ErrorStateItem[] };

type DependencyItem = {
  id: string;
  name: string;
  type: "api" | "service" | "feature" | "data";
  status: "ready" | "in_progress" | "blocked";
};
type DependenciesContent = { items: DependencyItem[] };

type OpenQuestionItem = {
  id: string;
  question: string;
  answer: string | null;
  resolved: boolean;
};
type OpenQuestionsContent = { items: OpenQuestionItem[] };

type CustomContent = { text: string };

export type SectionContent =
  | SummaryContent
  | UserStoriesContent
  | AcceptanceCriteriaContent
  | EdgeCasesContent
  | ErrorStatesContent
  | DependenciesContent
  | OpenQuestionsContent
  | CustomContent;

export type SectionType =
  | "summary"
  | "user_stories"
  | "acceptance_criteria"
  | "edge_cases"
  | "error_states"
  | "dependencies"
  | "open_questions"
  | "custom";

export type SectionStatus = "draft" | "reviewed" | "approved";
export type DocumentStatus = "draft" | "review" | "approved" | "archived";

export {
  type SummaryContent,
  type UserStoriesContent,
  type UserStoryItem,
  type AcceptanceCriteriaContent,
  type AcceptanceCriterionItem,
  type EdgeCasesContent,
  type EdgeCaseItem,
  type ErrorStatesContent,
  type ErrorStateItem,
  type DependenciesContent,
  type DependencyItem,
  type OpenQuestionsContent,
  type OpenQuestionItem,
  type CustomContent,
};

// --- Tables ---

export const specDocument = pgTable("spec_document", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull(),
  title: text("title").notNull(),
  description: text("description"),
  status: text("status", {
    enum: ["draft", "review", "approved", "archived"],
  })
    .notNull()
    .default("draft"),
  createdAt: timestamp("created_at", { withTimezone: true })
    .defaultNow()
    .notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .defaultNow()
    .notNull(),
});

export const specSection = pgTable("spec_section", {
  id: uuid("id").defaultRandom().primaryKey(),
  documentId: uuid("document_id")
    .notNull()
    .references(() => specDocument.id, { onDelete: "cascade" }),
  type: text("type", {
    enum: [
      "summary",
      "user_stories",
      "acceptance_criteria",
      "edge_cases",
      "error_states",
      "dependencies",
      "open_questions",
      "custom",
    ],
  }).notNull(),
  title: text("title").notNull(),
  content: json("content").$type<SectionContent>().notNull().default({ text: "" }),
  status: text("status", {
    enum: ["draft", "reviewed", "approved"],
  })
    .notNull()
    .default("draft"),
  sortOrder: integer("sort_order").notNull().default(0),
  collapsed: boolean("collapsed").notNull().default(false),
  createdAt: timestamp("created_at", { withTimezone: true })
    .defaultNow()
    .notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .defaultNow()
    .notNull(),
});

export const specAnnotation = pgTable("spec_annotation", {
  id: uuid("id").defaultRandom().primaryKey(),
  sectionId: uuid("section_id")
    .notNull()
    .references(() => specSection.id, { onDelete: "cascade" }),
  authorId: text("author_id"),
  authorName: text("author_name").notNull(),
  authorRole: text("author_role").default("user"),
  content: text("content").notNull(),
  color: text("color"),
  createdAt: timestamp("created_at", { withTimezone: true })
    .defaultNow()
    .notNull(),
});
```

### Step 2: Add document schema to barrel export

Add the document schema export to `src/lib/db/schema/index.ts`:

```typescript
export * from "./document";
```

### Step 3: Create `src/app/api/documents/route.ts`

```typescript
import { NextResponse } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/lib/db";
import { specDocument } from "@/lib/db/schema/document";
import { eq, desc } from "drizzle-orm";

type DocumentListItem = {
  id: string;
  title: string;
  description: string | null;
  status: string;
  createdAt: Date;
  updatedAt: Date;
};

/** GET /api/documents — list all documents for the current user */
export const GET = withAuth(async (_request, { user }) => {
  const documents = await db
    .select({
      id: specDocument.id,
      title: specDocument.title,
      description: specDocument.description,
      status: specDocument.status,
      createdAt: specDocument.createdAt,
      updatedAt: specDocument.updatedAt,
    })
    .from(specDocument)
    .where(eq(specDocument.userId, user.id))
    .orderBy(desc(specDocument.updatedAt));

  return NextResponse.json<DocumentListItem[]>(documents);
});

type CreateDocumentBody = {
  title: string;
  description?: string;
};

/** POST /api/documents — create a new document */
export const POST = withAuth(async (request, { user }) => {
  const body: CreateDocumentBody = await request.json();

  const [document] = await db
    .insert(specDocument)
    .values({
      userId: user.id,
      title: body.title,
      description: body.description ?? null,
    })
    .returning();

  return NextResponse.json(document, { status: 201 });
});
```

### Step 4: Create `src/app/api/documents/[documentId]/route.ts`

```typescript
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/lib/db";
import {
  specDocument,
  specSection,
  specAnnotation,
  type DocumentStatus,
} from "@/lib/db/schema/document";
import { eq, and, asc } from "drizzle-orm";

type RouteContext = { params: Promise<{ documentId: string }> };

/** GET /api/documents/[documentId] — get document with all sections and annotations */
export const GET = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const documentId = pathParts[pathParts.length - 1];

  const documents = await db
    .select()
    .from(specDocument)
    .where(
      and(
        eq(specDocument.id, documentId),
        eq(specDocument.userId, user.id)
      )
    )
    .limit(1);

  if (documents.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  const sections = await db
    .select()
    .from(specSection)
    .where(eq(specSection.documentId, documentId))
    .orderBy(asc(specSection.sortOrder));

  const sectionIds = sections.map((s) => s.id);

  const annotations =
    sectionIds.length > 0
      ? await db
          .select()
          .from(specAnnotation)
          .where(
            eq(
              specAnnotation.sectionId,
              sectionIds[0] // initial fetch — client fetches per-section as needed
            )
          )
      : [];

  // Fetch all annotations for all sections
  const allAnnotations: Record<string, typeof annotations> = {};
  for (const section of sections) {
    const sectionAnnotations = await db
      .select()
      .from(specAnnotation)
      .where(eq(specAnnotation.sectionId, section.id))
      .orderBy(asc(specAnnotation.createdAt));
    allAnnotations[section.id] = sectionAnnotations;
  }

  return NextResponse.json({
    document: documents[0],
    sections,
    annotations: allAnnotations,
  });
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;

type UpdateDocumentBody = {
  title?: string;
  description?: string;
  status?: DocumentStatus;
};

/** PATCH /api/documents/[documentId] — update document */
export const PATCH = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const documentId = pathParts[pathParts.length - 1];

  const body: UpdateDocumentBody = await request.json();

  const result = await db
    .update(specDocument)
    .set({
      ...(body.title !== undefined && { title: body.title }),
      ...(body.description !== undefined && { description: body.description }),
      ...(body.status !== undefined && { status: body.status }),
      updatedAt: new Date(),
    })
    .where(
      and(
        eq(specDocument.id, documentId),
        eq(specDocument.userId, user.id)
      )
    )
    .returning();

  if (result.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  return NextResponse.json(result[0]);
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;

/** DELETE /api/documents/[documentId] — delete document (cascades to sections and annotations) */
export const DELETE = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const documentId = pathParts[pathParts.length - 1];

  const result = await db
    .delete(specDocument)
    .where(
      and(
        eq(specDocument.id, documentId),
        eq(specDocument.userId, user.id)
      )
    )
    .returning({ id: specDocument.id });

  if (result.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  return NextResponse.json({ success: true });
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;
```

### Step 5: Create `src/app/api/documents/[documentId]/sections/route.ts`

```typescript
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/lib/db";
import {
  specDocument,
  specSection,
  type SectionType,
  type SectionContent,
} from "@/lib/db/schema/document";
import { eq, and, asc } from "drizzle-orm";

type RouteContext = { params: Promise<{ documentId: string }> };

/** GET /api/documents/[documentId]/sections — list sections for a document */
export const GET = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  // URL: /api/documents/[documentId]/sections
  const documentId = pathParts[pathParts.length - 2];

  // Verify document ownership
  const documents = await db
    .select({ id: specDocument.id })
    .from(specDocument)
    .where(
      and(
        eq(specDocument.id, documentId),
        eq(specDocument.userId, user.id)
      )
    )
    .limit(1);

  if (documents.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  const sections = await db
    .select()
    .from(specSection)
    .where(eq(specSection.documentId, documentId))
    .orderBy(asc(specSection.sortOrder));

  return NextResponse.json(sections);
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;

type CreateSectionBody = {
  type: SectionType;
  title: string;
  content?: SectionContent;
  sortOrder?: number;
};

/** POST /api/documents/[documentId]/sections — add a section to the document */
export const POST = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const documentId = pathParts[pathParts.length - 2];

  // Verify document ownership
  const documents = await db
    .select({ id: specDocument.id })
    .from(specDocument)
    .where(
      and(
        eq(specDocument.id, documentId),
        eq(specDocument.userId, user.id)
      )
    )
    .limit(1);

  if (documents.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  const body: CreateSectionBody = await request.json();

  const defaultContent = getDefaultContent(body.type);

  const [section] = await db
    .insert(specSection)
    .values({
      documentId,
      type: body.type,
      title: body.title,
      content: body.content ?? defaultContent,
      sortOrder: body.sortOrder ?? 0,
    })
    .returning();

  // Update document timestamp
  await db
    .update(specDocument)
    .set({ updatedAt: new Date() })
    .where(eq(specDocument.id, documentId));

  return NextResponse.json(section, { status: 201 });
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;

function getDefaultContent(type: SectionType): SectionContent {
  switch (type) {
    case "summary":
      return { text: "" };
    case "user_stories":
      return { items: [] };
    case "acceptance_criteria":
      return { items: [] };
    case "edge_cases":
      return { items: [] };
    case "error_states":
      return { items: [] };
    case "dependencies":
      return { items: [] };
    case "open_questions":
      return { items: [] };
    case "custom":
      return { text: "" };
  }
}
```

### Step 6: Create `src/app/api/documents/[documentId]/sections/[sectionId]/route.ts`

```typescript
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/lib/db";
import {
  specDocument,
  specSection,
  type SectionContent,
  type SectionStatus,
} from "@/lib/db/schema/document";
import { eq, and } from "drizzle-orm";

type RouteContext = {
  params: Promise<{ documentId: string; sectionId: string }>;
};

/** Helper to parse documentId and sectionId from the URL path */
function parseIds(pathname: string): {
  documentId: string;
  sectionId: string;
} {
  // URL: /api/documents/[documentId]/sections/[sectionId]
  const parts = pathname.split("/");
  const sectionsIndex = parts.indexOf("sections");
  return {
    documentId: parts[sectionsIndex - 1],
    sectionId: parts[sectionsIndex + 1],
  };
}

type UpdateSectionBody = {
  title?: string;
  content?: SectionContent;
  status?: SectionStatus;
  sortOrder?: number;
  collapsed?: boolean;
};

/** PATCH /api/documents/[documentId]/sections/[sectionId] — update a section */
export const PATCH = withAuth(async (request: NextRequest, { user }) => {
  const { documentId, sectionId } = parseIds(request.nextUrl.pathname);

  // Verify document ownership
  const documents = await db
    .select({ id: specDocument.id })
    .from(specDocument)
    .where(
      and(
        eq(specDocument.id, documentId),
        eq(specDocument.userId, user.id)
      )
    )
    .limit(1);

  if (documents.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  const body: UpdateSectionBody = await request.json();

  const result = await db
    .update(specSection)
    .set({
      ...(body.title !== undefined && { title: body.title }),
      ...(body.content !== undefined && { content: body.content }),
      ...(body.status !== undefined && { status: body.status }),
      ...(body.sortOrder !== undefined && { sortOrder: body.sortOrder }),
      ...(body.collapsed !== undefined && { collapsed: body.collapsed }),
      updatedAt: new Date(),
    })
    .where(
      and(
        eq(specSection.id, sectionId),
        eq(specSection.documentId, documentId)
      )
    )
    .returning();

  if (result.length === 0) {
    return NextResponse.json({ error: "Section not found" }, { status: 404 });
  }

  // Update document timestamp
  await db
    .update(specDocument)
    .set({ updatedAt: new Date() })
    .where(eq(specDocument.id, documentId));

  return NextResponse.json(result[0]);
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;

/** DELETE /api/documents/[documentId]/sections/[sectionId] — delete a section */
export const DELETE = withAuth(async (request: NextRequest, { user }) => {
  const { documentId, sectionId } = parseIds(request.nextUrl.pathname);

  // Verify document ownership
  const documents = await db
    .select({ id: specDocument.id })
    .from(specDocument)
    .where(
      and(
        eq(specDocument.id, documentId),
        eq(specDocument.userId, user.id)
      )
    )
    .limit(1);

  if (documents.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  const result = await db
    .delete(specSection)
    .where(
      and(
        eq(specSection.id, sectionId),
        eq(specSection.documentId, documentId)
      )
    )
    .returning({ id: specSection.id });

  if (result.length === 0) {
    return NextResponse.json({ error: "Section not found" }, { status: 404 });
  }

  // Update document timestamp
  await db
    .update(specDocument)
    .set({ updatedAt: new Date() })
    .where(eq(specDocument.id, documentId));

  return NextResponse.json({ success: true });
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;
```

### Step 7: Create `src/app/api/documents/[documentId]/sections/[sectionId]/annotations/route.ts`

```typescript
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/lib/db";
import {
  specDocument,
  specSection,
  specAnnotation,
} from "@/lib/db/schema/document";
import { eq, and, asc } from "drizzle-orm";

type RouteContext = {
  params: Promise<{ documentId: string; sectionId: string }>;
};

/** Helper to parse documentId and sectionId from the URL path */
function parseIds(pathname: string): {
  documentId: string;
  sectionId: string;
} {
  // URL: /api/documents/[documentId]/sections/[sectionId]/annotations
  const parts = pathname.split("/");
  const sectionsIndex = parts.indexOf("sections");
  return {
    documentId: parts[sectionsIndex - 1],
    sectionId: parts[sectionsIndex + 1],
  };
}

/** GET /api/documents/[documentId]/sections/[sectionId]/annotations — list annotations */
export const GET = withAuth(async (request: NextRequest, { user }) => {
  const { documentId, sectionId } = parseIds(request.nextUrl.pathname);

  // Verify document ownership
  const documents = await db
    .select({ id: specDocument.id })
    .from(specDocument)
    .where(
      and(
        eq(specDocument.id, documentId),
        eq(specDocument.userId, user.id)
      )
    )
    .limit(1);

  if (documents.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  // Verify section belongs to document
  const sections = await db
    .select({ id: specSection.id })
    .from(specSection)
    .where(
      and(
        eq(specSection.id, sectionId),
        eq(specSection.documentId, documentId)
      )
    )
    .limit(1);

  if (sections.length === 0) {
    return NextResponse.json({ error: "Section not found" }, { status: 404 });
  }

  const annotations = await db
    .select()
    .from(specAnnotation)
    .where(eq(specAnnotation.sectionId, sectionId))
    .orderBy(asc(specAnnotation.createdAt));

  return NextResponse.json(annotations);
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;

type CreateAnnotationBody = {
  content: string;
  authorName?: string;
  authorRole?: string;
  color?: string;
};

/** POST /api/documents/[documentId]/sections/[sectionId]/annotations — add annotation */
export const POST = withAuth(async (request: NextRequest, { user }) => {
  const { documentId, sectionId } = parseIds(request.nextUrl.pathname);

  // Verify document ownership
  const documents = await db
    .select({ id: specDocument.id })
    .from(specDocument)
    .where(
      and(
        eq(specDocument.id, documentId),
        eq(specDocument.userId, user.id)
      )
    )
    .limit(1);

  if (documents.length === 0) {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }

  // Verify section belongs to document
  const sections = await db
    .select({ id: specSection.id })
    .from(specSection)
    .where(
      and(
        eq(specSection.id, sectionId),
        eq(specSection.documentId, documentId)
      )
    )
    .limit(1);

  if (sections.length === 0) {
    return NextResponse.json({ error: "Section not found" }, { status: 404 });
  }

  const body: CreateAnnotationBody = await request.json();

  const [annotation] = await db
    .insert(specAnnotation)
    .values({
      sectionId,
      authorId: user.id,
      authorName: body.authorName ?? user.name ?? "Unknown",
      authorRole: body.authorRole ?? "user",
      content: body.content,
      color: body.color ?? null,
    })
    .returning();

  return NextResponse.json(annotation, { status: 201 });
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;
```

### Step 8: Create `src/components/editor/section-toolbar.tsx`

```tsx
"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  PencilSimple,
  Trash,
  ArrowUp,
  ArrowDown,
  ChatCircle,
} from "@phosphor-icons/react";
import type { SectionStatus } from "@/lib/db/schema/document";

type SectionToolbarProps = {
  status: SectionStatus;
  annotationCount: number;
  onStatusCycle: () => void;
  onEdit: () => void;
  onDelete: () => void;
  onMoveUp: () => void;
  onMoveDown: () => void;
  isFirst: boolean;
  isLast: boolean;
};

const statusConfig: Record<
  SectionStatus,
  { label: string; variant: "secondary" | "outline" | "default" }
> = {
  draft: { label: "Draft", variant: "secondary" },
  reviewed: { label: "Reviewed", variant: "outline" },
  approved: { label: "Approved", variant: "default" },
};

const statusOrder: SectionStatus[] = ["draft", "reviewed", "approved"];

export function SectionToolbar({
  status,
  annotationCount,
  onStatusCycle,
  onEdit,
  onDelete,
  onMoveUp,
  onMoveDown,
  isFirst,
  isLast,
}: SectionToolbarProps) {
  const config = statusConfig[status];

  return (
    <div className="flex items-center gap-1">
      <button type="button" onClick={onStatusCycle} className="cursor-pointer">
        <Badge variant={config.variant}>{config.label}</Badge>
      </button>

      {annotationCount > 0 && (
        <Badge variant="outline" className="gap-1">
          <ChatCircle className="h-3 w-3" />
          {annotationCount}
        </Badge>
      )}

      <Button
        variant="ghost"
        size="icon"
        className="h-7 w-7"
        onClick={onMoveUp}
        disabled={isFirst}
        title="Move up"
      >
        <ArrowUp className="h-3.5 w-3.5" />
      </Button>

      <Button
        variant="ghost"
        size="icon"
        className="h-7 w-7"
        onClick={onMoveDown}
        disabled={isLast}
        title="Move down"
      >
        <ArrowDown className="h-3.5 w-3.5" />
      </Button>

      <Button
        variant="ghost"
        size="icon"
        className="h-7 w-7"
        onClick={onEdit}
        title="Edit section"
      >
        <PencilSimple className="h-3.5 w-3.5" />
      </Button>

      <Button
        variant="ghost"
        size="icon"
        className="h-7 w-7 text-destructive"
        onClick={onDelete}
        title="Delete section"
      >
        <Trash className="h-3.5 w-3.5" />
      </Button>
    </div>
  );
}

export function getNextStatus(current: SectionStatus): SectionStatus {
  const currentIndex = statusOrder.indexOf(current);
  return statusOrder[(currentIndex + 1) % statusOrder.length];
}
```

### Step 9: Create `src/components/editor/section-content.tsx`

```tsx
"use client";

import { useId, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Plus, Trash } from "@phosphor-icons/react";
import type {
  SectionType,
  SectionContent as SectionContentType,
  SummaryContent,
  UserStoriesContent,
  UserStoryItem,
  AcceptanceCriteriaContent,
  AcceptanceCriterionItem,
  EdgeCasesContent,
  EdgeCaseItem,
  ErrorStatesContent,
  ErrorStateItem,
  DependenciesContent,
  DependencyItem,
  OpenQuestionsContent,
  OpenQuestionItem,
  CustomContent,
} from "@/lib/db/schema/document";

type SectionContentProps = {
  type: SectionType;
  content: SectionContentType;
  isEditing: boolean;
  onContentChange: (content: SectionContentType) => void;
};

export function SectionContent({
  type,
  content,
  isEditing,
  onContentChange,
}: SectionContentProps) {
  switch (type) {
    case "summary":
      return (
        <SummaryRenderer
          content={content as SummaryContent}
          isEditing={isEditing}
          onChange={onContentChange}
        />
      );
    case "user_stories":
      return (
        <UserStoriesRenderer
          content={content as UserStoriesContent}
          isEditing={isEditing}
          onChange={onContentChange}
        />
      );
    case "acceptance_criteria":
      return (
        <AcceptanceCriteriaRenderer
          content={content as AcceptanceCriteriaContent}
          isEditing={isEditing}
          onChange={onContentChange}
        />
      );
    case "edge_cases":
      return (
        <EdgeCasesRenderer
          content={content as EdgeCasesContent}
          isEditing={isEditing}
          onChange={onContentChange}
        />
      );
    case "error_states":
      return (
        <ErrorStatesRenderer
          content={content as ErrorStatesContent}
          isEditing={isEditing}
          onChange={onContentChange}
        />
      );
    case "dependencies":
      return (
        <DependenciesRenderer
          content={content as DependenciesContent}
          isEditing={isEditing}
          onChange={onContentChange}
        />
      );
    case "open_questions":
      return (
        <OpenQuestionsRenderer
          content={content as OpenQuestionsContent}
          isEditing={isEditing}
          onChange={onContentChange}
        />
      );
    case "custom":
      return (
        <CustomRenderer
          content={content as CustomContent}
          isEditing={isEditing}
          onChange={onContentChange}
        />
      );
  }
}

// --- Summary ---

type SummaryRendererProps = {
  content: SummaryContent;
  isEditing: boolean;
  onChange: (content: SummaryContent) => void;
};

function SummaryRenderer({ content, isEditing, onChange }: SummaryRendererProps) {
  if (isEditing) {
    return (
      <Textarea
        value={content.text}
        onChange={(e) => onChange({ text: e.target.value })}
        placeholder="Enter summary..."
        rows={4}
      />
    );
  }

  return (
    <div className="prose dark:prose-invert max-w-none whitespace-pre-wrap">
      {content.text || <span className="text-muted-foreground">No summary yet.</span>}
    </div>
  );
}

// --- User Stories ---

type UserStoriesRendererProps = {
  content: UserStoriesContent;
  isEditing: boolean;
  onChange: (content: UserStoriesContent) => void;
};

function UserStoriesRenderer({
  content,
  isEditing,
  onChange,
}: UserStoriesRendererProps) {
  const rowId = useId();

  const addItem = useCallback(() => {
    onChange({
      items: [
        ...content.items,
        {
          id: crypto.randomUUID(),
          persona: "",
          action: "",
          benefit: "",
        },
      ],
    });
  }, [content, onChange]);

  const updateItem = useCallback(
    (itemId: string, field: keyof UserStoryItem, value: string) => {
      onChange({
        items: content.items.map((item) =>
          item.id === itemId ? { ...item, [field]: value } : item
        ),
      });
    },
    [content, onChange]
  );

  const removeItem = useCallback(
    (itemId: string) => {
      onChange({
        items: content.items.filter((item) => item.id !== itemId),
      });
    },
    [content, onChange]
  );

  if (!isEditing) {
    if (content.items.length === 0) {
      return <p className="text-muted-foreground">No user stories yet.</p>;
    }

    return (
      <div className="space-y-2">
        {content.items.map((item) => (
          <p key={`${rowId}-${item.id}`} className="text-sm">
            As a <strong>{item.persona || "..."}</strong>, I want{" "}
            <strong>{item.action || "..."}</strong> so that{" "}
            <strong>{item.benefit || "..."}</strong>
          </p>
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b">
            <th className="p-2 text-left font-medium">Persona</th>
            <th className="p-2 text-left font-medium">Action</th>
            <th className="p-2 text-left font-medium">Benefit</th>
            <th className="w-10 p-2" />
          </tr>
        </thead>
        <tbody>
          {content.items.map((item) => (
            <tr key={`${rowId}-edit-${item.id}`} className="border-b">
              <td className="p-1">
                <input
                  type="text"
                  value={item.persona}
                  onChange={(e) =>
                    updateItem(item.id, "persona", e.target.value)
                  }
                  placeholder="user"
                  className="w-full rounded border bg-background px-2 py-1 text-sm"
                />
              </td>
              <td className="p-1">
                <input
                  type="text"
                  value={item.action}
                  onChange={(e) =>
                    updateItem(item.id, "action", e.target.value)
                  }
                  placeholder="to do something"
                  className="w-full rounded border bg-background px-2 py-1 text-sm"
                />
              </td>
              <td className="p-1">
                <input
                  type="text"
                  value={item.benefit}
                  onChange={(e) =>
                    updateItem(item.id, "benefit", e.target.value)
                  }
                  placeholder="I can achieve a goal"
                  className="w-full rounded border bg-background px-2 py-1 text-sm"
                />
              </td>
              <td className="p-1">
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-7 w-7 text-destructive"
                  onClick={() => removeItem(item.id)}
                >
                  <Trash className="h-3.5 w-3.5" />
                </Button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <Button variant="outline" size="sm" onClick={addItem}>
        <Plus className="mr-1 h-3.5 w-3.5" />
        Add story
      </Button>
    </div>
  );
}

// --- Acceptance Criteria ---

type AcceptanceCriteriaRendererProps = {
  content: AcceptanceCriteriaContent;
  isEditing: boolean;
  onChange: (content: AcceptanceCriteriaContent) => void;
};

function AcceptanceCriteriaRenderer({
  content,
  isEditing,
  onChange,
}: AcceptanceCriteriaRendererProps) {
  const itemId = useId();

  const addItem = useCallback(() => {
    onChange({
      items: [
        ...content.items,
        { id: crypto.randomUUID(), criterion: "", checked: false },
      ],
    });
  }, [content, onChange]);

  const toggleItem = useCallback(
    (criterionId: string) => {
      onChange({
        items: content.items.map((item) =>
          item.id === criterionId
            ? { ...item, checked: !item.checked }
            : item
        ),
      });
    },
    [content, onChange]
  );

  const updateItem = useCallback(
    (criterionId: string, value: string) => {
      onChange({
        items: content.items.map((item) =>
          item.id === criterionId ? { ...item, criterion: value } : item
        ),
      });
    },
    [content, onChange]
  );

  const removeItem = useCallback(
    (criterionId: string) => {
      onChange({
        items: content.items.filter((item) => item.id !== criterionId),
      });
    },
    [content, onChange]
  );

  if (!isEditing) {
    if (content.items.length === 0) {
      return (
        <p className="text-muted-foreground">No acceptance criteria yet.</p>
      );
    }

    return (
      <ul className="space-y-1">
        {content.items.map((item) => (
          <li
            key={`${itemId}-${item.id}`}
            className="flex items-center gap-2 text-sm"
          >
            <input
              type="checkbox"
              checked={item.checked}
              onChange={() => toggleItem(item.id)}
              className="h-4 w-4 rounded border"
            />
            <span className={item.checked ? "line-through opacity-60" : ""}>
              {item.criterion || "..."}
            </span>
          </li>
        ))}
      </ul>
    );
  }

  return (
    <div className="space-y-2">
      {content.items.map((item) => (
        <div
          key={`${itemId}-edit-${item.id}`}
          className="flex items-center gap-2"
        >
          <input
            type="checkbox"
            checked={item.checked}
            onChange={() => toggleItem(item.id)}
            className="h-4 w-4 rounded border"
          />
          <input
            type="text"
            value={item.criterion}
            onChange={(e) => updateItem(item.id, e.target.value)}
            placeholder="Criterion..."
            className="flex-1 rounded border bg-background px-2 py-1 text-sm"
          />
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 text-destructive"
            onClick={() => removeItem(item.id)}
          >
            <Trash className="h-3.5 w-3.5" />
          </Button>
        </div>
      ))}
      <Button variant="outline" size="sm" onClick={addItem}>
        <Plus className="mr-1 h-3.5 w-3.5" />
        Add criterion
      </Button>
    </div>
  );
}

// --- Edge Cases ---

type EdgeCasesRendererProps = {
  content: EdgeCasesContent;
  isEditing: boolean;
  onChange: (content: EdgeCasesContent) => void;
};

function EdgeCasesRenderer({
  content,
  isEditing,
  onChange,
}: EdgeCasesRendererProps) {
  const rowId = useId();

  const addItem = useCallback(() => {
    onChange({
      items: [
        ...content.items,
        { id: crypto.randomUUID(), scenario: "", expectedBehavior: "" },
      ],
    });
  }, [content, onChange]);

  const updateItem = useCallback(
    (itemId: string, field: keyof EdgeCaseItem, value: string) => {
      onChange({
        items: content.items.map((item) =>
          item.id === itemId ? { ...item, [field]: value } : item
        ),
      });
    },
    [content, onChange]
  );

  const removeItem = useCallback(
    (itemId: string) => {
      onChange({
        items: content.items.filter((item) => item.id !== itemId),
      });
    },
    [content, onChange]
  );

  if (!isEditing) {
    if (content.items.length === 0) {
      return <p className="text-muted-foreground">No edge cases yet.</p>;
    }

    return (
      <div className="space-y-2">
        {content.items.map((item) => (
          <div
            key={`${rowId}-${item.id}`}
            className="rounded border p-2 text-sm"
          >
            <p>
              <strong>Scenario:</strong> {item.scenario || "..."}
            </p>
            <p>
              <strong>Expected:</strong> {item.expectedBehavior || "..."}
            </p>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {content.items.map((item) => (
        <div
          key={`${rowId}-edit-${item.id}`}
          className="flex gap-2 rounded border p-2"
        >
          <div className="flex-1 space-y-1">
            <input
              type="text"
              value={item.scenario}
              onChange={(e) =>
                updateItem(item.id, "scenario", e.target.value)
              }
              placeholder="Scenario..."
              className="w-full rounded border bg-background px-2 py-1 text-sm"
            />
            <input
              type="text"
              value={item.expectedBehavior}
              onChange={(e) =>
                updateItem(item.id, "expectedBehavior", e.target.value)
              }
              placeholder="Expected behavior..."
              className="w-full rounded border bg-background px-2 py-1 text-sm"
            />
          </div>
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 text-destructive"
            onClick={() => removeItem(item.id)}
          >
            <Trash className="h-3.5 w-3.5" />
          </Button>
        </div>
      ))}
      <Button variant="outline" size="sm" onClick={addItem}>
        <Plus className="mr-1 h-3.5 w-3.5" />
        Add edge case
      </Button>
    </div>
  );
}

// --- Error States ---

type ErrorStatesRendererProps = {
  content: ErrorStatesContent;
  isEditing: boolean;
  onChange: (content: ErrorStatesContent) => void;
};

function ErrorStatesRenderer({
  content,
  isEditing,
  onChange,
}: ErrorStatesRendererProps) {
  const rowId = useId();

  const addItem = useCallback(() => {
    onChange({
      items: [
        ...content.items,
        {
          id: crypto.randomUUID(),
          trigger: "",
          userMessage: "",
          recovery: "",
        },
      ],
    });
  }, [content, onChange]);

  const updateItem = useCallback(
    (itemId: string, field: keyof ErrorStateItem, value: string) => {
      onChange({
        items: content.items.map((item) =>
          item.id === itemId ? { ...item, [field]: value } : item
        ),
      });
    },
    [content, onChange]
  );

  const removeItem = useCallback(
    (itemId: string) => {
      onChange({
        items: content.items.filter((item) => item.id !== itemId),
      });
    },
    [content, onChange]
  );

  if (!isEditing) {
    if (content.items.length === 0) {
      return <p className="text-muted-foreground">No error states yet.</p>;
    }

    return (
      <div className="space-y-2">
        {content.items.map((item) => (
          <div
            key={`${rowId}-${item.id}`}
            className="rounded border p-2 text-sm"
          >
            <p>
              <strong>Trigger:</strong> {item.trigger || "..."}
            </p>
            <p>
              <strong>Message:</strong> {item.userMessage || "..."}
            </p>
            <p>
              <strong>Recovery:</strong> {item.recovery || "..."}
            </p>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {content.items.map((item) => (
        <div
          key={`${rowId}-edit-${item.id}`}
          className="flex gap-2 rounded border p-2"
        >
          <div className="flex-1 space-y-1">
            <input
              type="text"
              value={item.trigger}
              onChange={(e) =>
                updateItem(item.id, "trigger", e.target.value)
              }
              placeholder="Trigger..."
              className="w-full rounded border bg-background px-2 py-1 text-sm"
            />
            <input
              type="text"
              value={item.userMessage}
              onChange={(e) =>
                updateItem(item.id, "userMessage", e.target.value)
              }
              placeholder="User message..."
              className="w-full rounded border bg-background px-2 py-1 text-sm"
            />
            <input
              type="text"
              value={item.recovery}
              onChange={(e) =>
                updateItem(item.id, "recovery", e.target.value)
              }
              placeholder="Recovery path..."
              className="w-full rounded border bg-background px-2 py-1 text-sm"
            />
          </div>
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 text-destructive"
            onClick={() => removeItem(item.id)}
          >
            <Trash className="h-3.5 w-3.5" />
          </Button>
        </div>
      ))}
      <Button variant="outline" size="sm" onClick={addItem}>
        <Plus className="mr-1 h-3.5 w-3.5" />
        Add error state
      </Button>
    </div>
  );
}

// --- Dependencies ---

type DependenciesRendererProps = {
  content: DependenciesContent;
  isEditing: boolean;
  onChange: (content: DependenciesContent) => void;
};

const depTypeOptions = ["api", "service", "feature", "data"] as const;
const depStatusOptions = ["ready", "in_progress", "blocked"] as const;

const depStatusColors: Record<DependencyItem["status"], string> = {
  ready: "default",
  in_progress: "outline",
  blocked: "destructive",
};

function DependenciesRenderer({
  content,
  isEditing,
  onChange,
}: DependenciesRendererProps) {
  const rowId = useId();

  const addItem = useCallback(() => {
    onChange({
      items: [
        ...content.items,
        {
          id: crypto.randomUUID(),
          name: "",
          type: "api",
          status: "ready",
        },
      ],
    });
  }, [content, onChange]);

  const updateItem = useCallback(
    (
      itemId: string,
      field: keyof DependencyItem,
      value: string
    ) => {
      onChange({
        items: content.items.map((item) =>
          item.id === itemId ? { ...item, [field]: value } : item
        ),
      });
    },
    [content, onChange]
  );

  const removeItem = useCallback(
    (itemId: string) => {
      onChange({
        items: content.items.filter((item) => item.id !== itemId),
      });
    },
    [content, onChange]
  );

  if (!isEditing) {
    if (content.items.length === 0) {
      return <p className="text-muted-foreground">No dependencies yet.</p>;
    }

    return (
      <div className="space-y-1">
        {content.items.map((item) => (
          <div
            key={`${rowId}-${item.id}`}
            className="flex items-center gap-2 text-sm"
          >
            <span className="font-medium">{item.name || "..."}</span>
            <Badge variant="outline">{item.type}</Badge>
            <Badge
              variant={
                depStatusColors[item.status] as
                  | "default"
                  | "outline"
                  | "destructive"
              }
            >
              {item.status.replace("_", " ")}
            </Badge>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {content.items.map((item) => (
        <div
          key={`${rowId}-edit-${item.id}`}
          className="flex items-center gap-2"
        >
          <input
            type="text"
            value={item.name}
            onChange={(e) => updateItem(item.id, "name", e.target.value)}
            placeholder="Dependency name..."
            className="flex-1 rounded border bg-background px-2 py-1 text-sm"
          />
          <select
            value={item.type}
            onChange={(e) => updateItem(item.id, "type", e.target.value)}
            className="rounded border bg-background px-2 py-1 text-sm"
          >
            {depTypeOptions.map((opt) => (
              <option key={opt} value={opt}>
                {opt}
              </option>
            ))}
          </select>
          <select
            value={item.status}
            onChange={(e) => updateItem(item.id, "status", e.target.value)}
            className="rounded border bg-background px-2 py-1 text-sm"
          >
            {depStatusOptions.map((opt) => (
              <option key={opt} value={opt}>
                {opt.replace("_", " ")}
              </option>
            ))}
          </select>
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 text-destructive"
            onClick={() => removeItem(item.id)}
          >
            <Trash className="h-3.5 w-3.5" />
          </Button>
        </div>
      ))}
      <Button variant="outline" size="sm" onClick={addItem}>
        <Plus className="mr-1 h-3.5 w-3.5" />
        Add dependency
      </Button>
    </div>
  );
}

// --- Open Questions ---

type OpenQuestionsRendererProps = {
  content: OpenQuestionsContent;
  isEditing: boolean;
  onChange: (content: OpenQuestionsContent) => void;
};

function OpenQuestionsRenderer({
  content,
  isEditing,
  onChange,
}: OpenQuestionsRendererProps) {
  const rowId = useId();

  const addItem = useCallback(() => {
    onChange({
      items: [
        ...content.items,
        {
          id: crypto.randomUUID(),
          question: "",
          answer: null,
          resolved: false,
        },
      ],
    });
  }, [content, onChange]);

  const updateItem = useCallback(
    (
      itemId: string,
      field: keyof OpenQuestionItem,
      value: string | boolean | null
    ) => {
      onChange({
        items: content.items.map((item) =>
          item.id === itemId ? { ...item, [field]: value } : item
        ),
      });
    },
    [content, onChange]
  );

  const removeItem = useCallback(
    (itemId: string) => {
      onChange({
        items: content.items.filter((item) => item.id !== itemId),
      });
    },
    [content, onChange]
  );

  if (!isEditing) {
    if (content.items.length === 0) {
      return <p className="text-muted-foreground">No open questions yet.</p>;
    }

    return (
      <div className="space-y-2">
        {content.items.map((item) => (
          <div
            key={`${rowId}-${item.id}`}
            className="rounded border p-2 text-sm"
          >
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={item.resolved}
                onChange={() =>
                  updateItem(item.id, "resolved", !item.resolved)
                }
                className="h-4 w-4 rounded border"
              />
              <p
                className={
                  item.resolved ? "font-medium line-through opacity-60" : "font-medium"
                }
              >
                {item.question || "..."}
              </p>
            </div>
            {item.answer && (
              <p className="mt-1 pl-6 text-muted-foreground">{item.answer}</p>
            )}
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {content.items.map((item) => (
        <div
          key={`${rowId}-edit-${item.id}`}
          className="flex gap-2 rounded border p-2"
        >
          <input
            type="checkbox"
            checked={item.resolved}
            onChange={() => updateItem(item.id, "resolved", !item.resolved)}
            className="mt-1 h-4 w-4 rounded border"
          />
          <div className="flex-1 space-y-1">
            <input
              type="text"
              value={item.question}
              onChange={(e) =>
                updateItem(item.id, "question", e.target.value)
              }
              placeholder="Question..."
              className="w-full rounded border bg-background px-2 py-1 text-sm"
            />
            <input
              type="text"
              value={item.answer ?? ""}
              onChange={(e) =>
                updateItem(
                  item.id,
                  "answer",
                  e.target.value || null
                )
              }
              placeholder="Answer (optional)..."
              className="w-full rounded border bg-background px-2 py-1 text-sm"
            />
          </div>
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 text-destructive"
            onClick={() => removeItem(item.id)}
          >
            <Trash className="h-3.5 w-3.5" />
          </Button>
        </div>
      ))}
      <Button variant="outline" size="sm" onClick={addItem}>
        <Plus className="mr-1 h-3.5 w-3.5" />
        Add question
      </Button>
    </div>
  );
}

// --- Custom ---

type CustomRendererProps = {
  content: CustomContent;
  isEditing: boolean;
  onChange: (content: CustomContent) => void;
};

function CustomRenderer({ content, isEditing, onChange }: CustomRendererProps) {
  if (isEditing) {
    return (
      <Textarea
        value={content.text}
        onChange={(e) => onChange({ text: e.target.value })}
        placeholder="Enter content..."
        rows={4}
      />
    );
  }

  return (
    <div className="prose dark:prose-invert max-w-none whitespace-pre-wrap">
      {content.text || (
        <span className="text-muted-foreground">No content yet.</span>
      )}
    </div>
  );
}
```

### Step 10: Create `src/components/editor/annotation-list.tsx`

```tsx
"use client";

import { useState, useCallback, useId } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { PaperPlaneTilt } from "@phosphor-icons/react";

type Annotation = {
  id: string;
  sectionId: string;
  authorId: string | null;
  authorName: string;
  authorRole: string | null;
  content: string;
  color: string | null;
  createdAt: string;
};

type AnnotationListProps = {
  documentId: string;
  sectionId: string;
  annotations: Annotation[];
  onAnnotationAdded: (annotation: Annotation) => void;
};

export function AnnotationList({
  documentId,
  sectionId,
  annotations,
  onAnnotationAdded,
}: AnnotationListProps) {
  const listId = useId();
  const [newContent, setNewContent] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = useCallback(async () => {
    if (!newContent.trim() || isSubmitting) return;

    setIsSubmitting(true);
    try {
      const res = await fetch(
        `/api/documents/${documentId}/sections/${sectionId}/annotations`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ content: newContent.trim() }),
        }
      );

      if (!res.ok) return;

      const annotation: Annotation = await res.json();
      onAnnotationAdded(annotation);
      setNewContent("");
    } catch {
      // Silently fail — annotation is non-critical
    } finally {
      setIsSubmitting(false);
    }
  }, [documentId, sectionId, newContent, isSubmitting, onAnnotationAdded]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        handleSubmit();
      }
    },
    [handleSubmit]
  );

  const roleColors: Record<string, string> = {
    user: "bg-blue-500",
    agent: "bg-purple-500",
    reviewer: "bg-amber-500",
  };

  return (
    <div className="mt-3 border-t pt-3">
      <p className="mb-2 text-xs font-medium text-muted-foreground">
        Annotations
      </p>

      {annotations.length > 0 && (
        <div className="space-y-2">
          {annotations.map((annotation) => (
            <div
              key={`${listId}-${annotation.id}`}
              className="flex gap-2 text-sm"
            >
              <div
                className={`mt-1 h-2 w-2 shrink-0 rounded-full ${
                  annotation.color
                    ? ""
                    : roleColors[annotation.authorRole ?? "user"] ??
                      "bg-gray-400"
                }`}
                style={
                  annotation.color
                    ? { backgroundColor: annotation.color }
                    : undefined
                }
              />
              <div className="flex-1">
                <div className="flex items-center gap-1.5">
                  <span className="font-medium">{annotation.authorName}</span>
                  {annotation.authorRole && annotation.authorRole !== "user" && (
                    <Badge variant="outline" className="text-[10px] px-1 py-0">
                      {annotation.authorRole}
                    </Badge>
                  )}
                  <span className="text-xs text-muted-foreground">
                    {new Date(annotation.createdAt).toLocaleString()}
                  </span>
                </div>
                <p className="mt-0.5 whitespace-pre-wrap">
                  {annotation.content}
                </p>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="mt-2 flex gap-2">
        <Textarea
          value={newContent}
          onChange={(e) => setNewContent(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Add annotation... (Cmd+Enter to send)"
          rows={2}
          className="flex-1 text-sm"
        />
        <Button
          variant="ghost"
          size="icon"
          className="mt-auto h-8 w-8"
          onClick={handleSubmit}
          disabled={!newContent.trim() || isSubmitting}
        >
          <PaperPlaneTilt className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}
```

### Step 11: Create `src/components/editor/section-card.tsx`

```tsx
"use client";

import { useState, useCallback } from "react";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { Button } from "@/components/ui/button";
import { CaretRight } from "@phosphor-icons/react";
import { SectionToolbar, getNextStatus } from "@/components/editor/section-toolbar";
import { SectionContent } from "@/components/editor/section-content";
import { AnnotationList } from "@/components/editor/annotation-list";
import type {
  SectionType,
  SectionContent as SectionContentType,
  SectionStatus,
} from "@/lib/db/schema/document";

type Annotation = {
  id: string;
  sectionId: string;
  authorId: string | null;
  authorName: string;
  authorRole: string | null;
  content: string;
  color: string | null;
  createdAt: string;
};

type SectionData = {
  id: string;
  documentId: string;
  type: SectionType;
  title: string;
  content: SectionContentType;
  status: SectionStatus;
  sortOrder: number;
  collapsed: boolean;
};

type SectionCardProps = {
  section: SectionData;
  annotations: Annotation[];
  isEditing: boolean;
  isFirst: boolean;
  isLast: boolean;
  onStartEdit: () => void;
  onCancelEdit: () => void;
  onSave: (updates: Partial<SectionData>) => void;
  onDelete: () => void;
  onMove: (direction: "up" | "down") => void;
  onAnnotationAdded: (annotation: Annotation) => void;
};

const sectionTypeIcons: Record<SectionType, string> = {
  summary: "S",
  user_stories: "US",
  acceptance_criteria: "AC",
  edge_cases: "EC",
  error_states: "ES",
  dependencies: "D",
  open_questions: "Q",
  custom: "C",
};

const sectionTypeLabels: Record<SectionType, string> = {
  summary: "Summary",
  user_stories: "User Stories",
  acceptance_criteria: "Acceptance Criteria",
  edge_cases: "Edge Cases",
  error_states: "Error States",
  dependencies: "Dependencies",
  open_questions: "Open Questions",
  custom: "Custom",
};

export function SectionCard({
  section,
  annotations,
  isEditing,
  isFirst,
  isLast,
  onStartEdit,
  onCancelEdit,
  onSave,
  onDelete,
  onMove,
  onAnnotationAdded,
}: SectionCardProps) {
  const [isOpen, setIsOpen] = useState(!section.collapsed);
  const [editContent, setEditContent] = useState<SectionContentType>(
    section.content
  );
  const [editTitle, setEditTitle] = useState(section.title);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  const handleStatusCycle = useCallback(() => {
    const nextStatus = getNextStatus(section.status);
    onSave({ status: nextStatus });
  }, [section.status, onSave]);

  const handleEdit = useCallback(() => {
    setEditContent(section.content);
    setEditTitle(section.title);
    onStartEdit();
  }, [section.content, section.title, onStartEdit]);

  const handleSave = useCallback(() => {
    onSave({ content: editContent, title: editTitle });
  }, [editContent, editTitle, onSave]);

  const handleCancel = useCallback(() => {
    setEditContent(section.content);
    setEditTitle(section.title);
    onCancelEdit();
  }, [section.content, section.title, onCancelEdit]);

  const handleDelete = useCallback(() => {
    if (showDeleteConfirm) {
      onDelete();
      setShowDeleteConfirm(false);
    } else {
      setShowDeleteConfirm(true);
      // Auto-dismiss confirmation after 3s
      setTimeout(() => setShowDeleteConfirm(false), 3000);
    }
  }, [showDeleteConfirm, onDelete]);

  return (
    <Collapsible open={isOpen} onOpenChange={setIsOpen}>
      <div className="rounded-lg border bg-card">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-2">
          <CollapsibleTrigger asChild>
            <button
              type="button"
              className="flex flex-1 items-center gap-2 text-left"
            >
              <CaretRight
                className={`h-4 w-4 shrink-0 transition-transform ${
                  isOpen ? "rotate-90" : ""
                }`}
              />
              <span className="flex h-6 w-6 items-center justify-center rounded bg-muted text-[10px] font-bold">
                {sectionTypeIcons[section.type]}
              </span>
              {isEditing ? (
                <input
                  type="text"
                  value={editTitle}
                  onChange={(e) => setEditTitle(e.target.value)}
                  onClick={(e) => e.stopPropagation()}
                  className="flex-1 rounded border bg-background px-2 py-0.5 text-sm font-medium"
                />
              ) : (
                <span className="text-sm font-medium">{section.title}</span>
              )}
              <span className="text-xs text-muted-foreground">
                {sectionTypeLabels[section.type]}
              </span>
            </button>
          </CollapsibleTrigger>

          <SectionToolbar
            status={section.status}
            annotationCount={annotations.length}
            onStatusCycle={handleStatusCycle}
            onEdit={handleEdit}
            onDelete={handleDelete}
            onMoveUp={() => onMove("up")}
            onMoveDown={() => onMove("down")}
            isFirst={isFirst}
            isLast={isLast}
          />
        </div>

        {/* Delete confirmation */}
        {showDeleteConfirm && (
          <div className="flex items-center gap-2 border-t bg-destructive/10 px-4 py-2 text-sm">
            <span>Delete this section?</span>
            <Button
              variant="destructive"
              size="sm"
              onClick={handleDelete}
            >
              Confirm
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setShowDeleteConfirm(false)}
            >
              Cancel
            </Button>
          </div>
        )}

        {/* Content */}
        <CollapsibleContent>
          <div className="border-t px-4 py-3">
            <SectionContent
              type={section.type}
              content={isEditing ? editContent : section.content}
              isEditing={isEditing}
              onContentChange={setEditContent}
            />

            {/* Edit mode save/cancel */}
            {isEditing && (
              <div className="mt-3 flex gap-2">
                <Button size="sm" onClick={handleSave}>
                  Save
                </Button>
                <Button variant="ghost" size="sm" onClick={handleCancel}>
                  Cancel
                </Button>
              </div>
            )}

            {/* Annotations */}
            <AnnotationList
              documentId={section.documentId}
              sectionId={section.id}
              annotations={annotations}
              onAnnotationAdded={onAnnotationAdded}
            />
          </div>
        </CollapsibleContent>
      </div>
    </Collapsible>
  );
}
```

### Step 12: Create `src/components/editor/add-section-button.tsx`

```tsx
"use client";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Plus } from "@phosphor-icons/react";
import type { SectionType } from "@/lib/db/schema/document";

type AddSectionButtonProps = {
  onAdd: (type: SectionType, title: string) => void;
};

type SectionOption = {
  type: SectionType;
  label: string;
  description: string;
  icon: string;
};

const sectionOptions: SectionOption[] = [
  {
    type: "summary",
    label: "Summary",
    description: "High-level overview",
    icon: "S",
  },
  {
    type: "user_stories",
    label: "User Stories",
    description: "As a [persona], I want...",
    icon: "US",
  },
  {
    type: "acceptance_criteria",
    label: "Acceptance Criteria",
    description: "Checkable requirements",
    icon: "AC",
  },
  {
    type: "edge_cases",
    label: "Edge Cases",
    description: "Scenario + expected behavior",
    icon: "EC",
  },
  {
    type: "error_states",
    label: "Error States",
    description: "Trigger, message, recovery",
    icon: "ES",
  },
  {
    type: "dependencies",
    label: "Dependencies",
    description: "APIs, services, features, data",
    icon: "D",
  },
  {
    type: "open_questions",
    label: "Open Questions",
    description: "Questions to resolve",
    icon: "Q",
  },
  {
    type: "custom",
    label: "Custom",
    description: "Freeform text section",
    icon: "C",
  },
];

export function AddSectionButton({ onAdd }: AddSectionButtonProps) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" className="w-full border-dashed">
          <Plus className="mr-2 h-4 w-4" />
          Add Section
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="center" className="w-72">
        {sectionOptions.map((option) => (
          <DropdownMenuItem
            key={option.type}
            onClick={() => onAdd(option.type, option.label)}
            className="flex items-center gap-3 py-2"
          >
            <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded bg-muted text-[10px] font-bold">
              {option.icon}
            </span>
            <div>
              <p className="text-sm font-medium">{option.label}</p>
              <p className="text-xs text-muted-foreground">
                {option.description}
              </p>
            </div>
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
```

### Step 13: Create `src/components/editor/document-editor.tsx`

```tsx
"use client";

import { useState, useCallback, useEffect, useId } from "react";
import { Badge } from "@/components/ui/badge";
import { SectionCard } from "@/components/editor/section-card";
import { AddSectionButton } from "@/components/editor/add-section-button";
import type {
  SectionType,
  SectionContent as SectionContentType,
  SectionStatus,
  DocumentStatus,
} from "@/lib/db/schema/document";

type Annotation = {
  id: string;
  sectionId: string;
  authorId: string | null;
  authorName: string;
  authorRole: string | null;
  content: string;
  color: string | null;
  createdAt: string;
};

type SectionData = {
  id: string;
  documentId: string;
  type: SectionType;
  title: string;
  content: SectionContentType;
  status: SectionStatus;
  sortOrder: number;
  collapsed: boolean;
};

type DocumentData = {
  id: string;
  userId: string;
  title: string;
  description: string | null;
  status: DocumentStatus;
  createdAt: string;
  updatedAt: string;
};

type DocumentEditorProps = {
  documentId: string;
};

const docStatusConfig: Record<
  DocumentStatus,
  { label: string; variant: "secondary" | "outline" | "default" | "destructive" }
> = {
  draft: { label: "Draft", variant: "secondary" },
  review: { label: "In Review", variant: "outline" },
  approved: { label: "Approved", variant: "default" },
  archived: { label: "Archived", variant: "destructive" },
};

export function DocumentEditor({ documentId }: DocumentEditorProps) {
  const sectionListId = useId();
  const [document, setDocument] = useState<DocumentData | null>(null);
  const [sections, setSections] = useState<SectionData[]>([]);
  const [annotations, setAnnotations] = useState<
    Record<string, Annotation[]>
  >({});
  const [editingSectionId, setEditingSectionId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [editingTitle, setEditingTitle] = useState(false);
  const [titleValue, setTitleValue] = useState("");

  // Fetch document data
  useEffect(() => {
    let cancelled = false;

    async function fetchDocument() {
      setIsLoading(true);
      try {
        const res = await fetch(`/api/documents/${documentId}`);
        if (!res.ok) throw new Error("Failed to fetch document");

        const data: {
          document: DocumentData;
          sections: SectionData[];
          annotations: Record<string, Annotation[]>;
        } = await res.json();

        if (cancelled) return;

        setDocument(data.document);
        setSections(data.sections);
        setAnnotations(data.annotations);
        setTitleValue(data.document.title);
      } catch {
        // Handle error
      } finally {
        if (!cancelled) setIsLoading(false);
      }
    }

    fetchDocument();

    return () => {
      cancelled = true;
    };
  }, [documentId]);

  // Save document title
  const handleTitleSave = useCallback(async () => {
    if (!titleValue.trim() || !document) return;

    setEditingTitle(false);

    const res = await fetch(`/api/documents/${documentId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: titleValue.trim() }),
    });

    if (res.ok) {
      const updated: DocumentData = await res.json();
      setDocument(updated);
    }
  }, [documentId, titleValue, document]);

  // Add section
  const handleAddSection = useCallback(
    async (type: SectionType, title: string) => {
      const sortOrder = sections.length;

      const res = await fetch(`/api/documents/${documentId}/sections`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type, title, sortOrder }),
      });

      if (res.ok) {
        const section: SectionData = await res.json();
        setSections((prev) => [...prev, section]);
        setAnnotations((prev) => ({ ...prev, [section.id]: [] }));
      }
    },
    [documentId, sections.length]
  );

  // Save section
  const handleSaveSection = useCallback(
    async (sectionId: string, updates: Partial<SectionData>) => {
      const res = await fetch(
        `/api/documents/${documentId}/sections/${sectionId}`,
        {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(updates),
        }
      );

      if (res.ok) {
        const updated: SectionData = await res.json();
        setSections((prev) =>
          prev.map((s) => (s.id === sectionId ? updated : s))
        );
        setEditingSectionId(null);
      }
    },
    [documentId]
  );

  // Delete section
  const handleDeleteSection = useCallback(
    async (sectionId: string) => {
      const res = await fetch(
        `/api/documents/${documentId}/sections/${sectionId}`,
        { method: "DELETE" }
      );

      if (res.ok) {
        setSections((prev) => prev.filter((s) => s.id !== sectionId));
        setAnnotations((prev) => {
          const next = { ...prev };
          delete next[sectionId];
          return next;
        });
      }
    },
    [documentId]
  );

  // Move section
  const handleMoveSection = useCallback(
    async (sectionId: string, direction: "up" | "down") => {
      const index = sections.findIndex((s) => s.id === sectionId);
      if (index === -1) return;

      const swapIndex = direction === "up" ? index - 1 : index + 1;
      if (swapIndex < 0 || swapIndex >= sections.length) return;

      const newSections = [...sections];
      const temp = newSections[index];
      newSections[index] = newSections[swapIndex];
      newSections[swapIndex] = temp;

      // Optimistic update
      setSections(newSections);

      // Persist sort orders
      await Promise.all([
        fetch(
          `/api/documents/${documentId}/sections/${newSections[index].id}`,
          {
            method: "PATCH",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ sortOrder: index }),
          }
        ),
        fetch(
          `/api/documents/${documentId}/sections/${newSections[swapIndex].id}`,
          {
            method: "PATCH",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ sortOrder: swapIndex }),
          }
        ),
      ]);
    },
    [documentId, sections]
  );

  // Add annotation
  const handleAnnotationAdded = useCallback(
    (sectionId: string, annotation: Annotation) => {
      setAnnotations((prev) => ({
        ...prev,
        [sectionId]: [...(prev[sectionId] ?? []), annotation],
      }));
    },
    []
  );

  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center text-muted-foreground">
        Loading document...
      </div>
    );
  }

  if (!document) {
    return (
      <div className="flex h-64 items-center justify-center text-muted-foreground">
        Document not found.
      </div>
    );
  }

  const statusConf = docStatusConfig[document.status as DocumentStatus];

  return (
    <div className="mx-auto max-w-4xl space-y-4 p-6">
      {/* Document header */}
      <div className="flex items-center justify-between">
        <div className="flex-1">
          {editingTitle ? (
            <input
              type="text"
              value={titleValue}
              onChange={(e) => setTitleValue(e.target.value)}
              onBlur={handleTitleSave}
              onKeyDown={(e) => {
                if (e.key === "Enter") handleTitleSave();
                if (e.key === "Escape") {
                  setEditingTitle(false);
                  setTitleValue(document.title);
                }
              }}
              className="w-full rounded border bg-background px-2 py-1 text-2xl font-bold"
              // biome-ignore lint/a11y/noAutofocus: intentional for inline rename
              autoFocus
            />
          ) : (
            <h1
              className="cursor-pointer text-2xl font-bold hover:text-primary"
              onClick={() => setEditingTitle(true)}
              title="Click to edit title"
            >
              {document.title}
            </h1>
          )}
          {document.description && (
            <p className="mt-1 text-sm text-muted-foreground">
              {document.description}
            </p>
          )}
        </div>
        <Badge variant={statusConf.variant}>{statusConf.label}</Badge>
      </div>

      {/* Sections */}
      <div className="space-y-3">
        {sections.map((section, index) => (
          <SectionCard
            key={`${sectionListId}-${section.id}`}
            section={section}
            annotations={annotations[section.id] ?? []}
            isEditing={editingSectionId === section.id}
            isFirst={index === 0}
            isLast={index === sections.length - 1}
            onStartEdit={() => setEditingSectionId(section.id)}
            onCancelEdit={() => setEditingSectionId(null)}
            onSave={(updates) => handleSaveSection(section.id, updates)}
            onDelete={() => handleDeleteSection(section.id)}
            onMove={(dir) => handleMoveSection(section.id, dir)}
            onAnnotationAdded={(annotation) =>
              handleAnnotationAdded(section.id, annotation)
            }
          />
        ))}
      </div>

      {/* Add section */}
      <AddSectionButton onAdd={handleAddSection} />
    </div>
  );
}
```

## Usage

After applying this skill:

1. Push the database schema:

   ```bash
   bunx drizzle-kit push
   ```

2. Use the `<DocumentEditor>` component in any page:

   ```tsx
   import { DocumentEditor } from "@/components/editor/document-editor";

   export default function SpecPage({ params }: { params: { id: string } }) {
     return <DocumentEditor documentId={params.id} />;
   }
   ```

### Create a document with sections

```typescript
// Create a new document
const res = await fetch("/api/documents", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    title: "Login Feature Spec",
    description: "Specification for the login feature",
  }),
});
const doc = await res.json();

// Add a summary section
await fetch(`/api/documents/${doc.id}/sections`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    type: "summary",
    title: "Summary",
    content: { text: "This feature implements user login with email/password." },
    sortOrder: 0,
  }),
});

// Add user stories
await fetch(`/api/documents/${doc.id}/sections`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    type: "user_stories",
    title: "User Stories",
    content: {
      items: [
        {
          id: crypto.randomUUID(),
          persona: "returning user",
          action: "log in with my email and password",
          benefit: "I can access my account",
        },
      ],
    },
    sortOrder: 1,
  }),
});
```

### Edit sections inline

Click the pencil icon on any section to enter edit mode. Content fields become editable inputs. Click "Save" to persist or "Cancel" to discard changes.

### Add annotations

Each section has an annotation thread at the bottom. Type a comment and press Cmd+Enter (or click the send button) to add an annotation. Annotations show author name, role badge, and timestamp.

### Cycle section status

Click the status badge on any section to cycle through: Draft -> Reviewed -> Approved -> Draft.

### Reorder sections

Use the up/down arrow buttons in the section toolbar to reorder sections. Changes persist immediately via API.

### Programmatic API usage

```typescript
// List all documents
const docs = await fetch("/api/documents").then((r) => r.json());

// Get document with sections and annotations
const full = await fetch(`/api/documents/${docId}`).then((r) => r.json());
// full.document, full.sections, full.annotations

// Update document status
await fetch(`/api/documents/${docId}`, {
  method: "PATCH",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ status: "review" }),
});

// Update a section
await fetch(`/api/documents/${docId}/sections/${sectionId}`, {
  method: "PATCH",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    content: { text: "Updated summary text" },
    status: "reviewed",
  }),
});

// Delete a section
await fetch(`/api/documents/${docId}/sections/${sectionId}`, {
  method: "DELETE",
});

// Add an annotation
await fetch(
  `/api/documents/${docId}/sections/${sectionId}/annotations`,
  {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      content: "Looks good, approved.",
      authorRole: "reviewer",
    }),
  }
);
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/documents` | List all documents for the current user |
| POST | `/api/documents` | Create a new document |
| GET | `/api/documents/[documentId]` | Get document with sections and annotations |
| PATCH | `/api/documents/[documentId]` | Update document title/description/status |
| DELETE | `/api/documents/[documentId]` | Delete document (cascades) |
| GET | `/api/documents/[documentId]/sections` | List sections for a document |
| POST | `/api/documents/[documentId]/sections` | Add a section |
| PATCH | `/api/documents/[documentId]/sections/[sectionId]` | Update section |
| DELETE | `/api/documents/[documentId]/sections/[sectionId]` | Delete section |
| GET | `/api/documents/[documentId]/sections/[sectionId]/annotations` | List annotations |
| POST | `/api/documents/[documentId]/sections/[sectionId]/annotations` | Add annotation |

## Acceptance Criteria

- Create a document -> renders with empty section list + "Add Section" button
- Add a "User Stories" section -> renders with persona/action/benefit table
- Add items to user stories -> rows appear with editable fields
- Collapse/expand sections -> content hides/shows with animation
- Change section status -> badge color updates (draft -> reviewed -> approved)
- Add annotation to a section -> appears in annotation thread
- Delete a section -> removed with confirmation
- Document persists across refreshes (Postgres)
- `tsc` passes with no errors
- `bun run build` succeeds
