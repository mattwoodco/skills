---
name: cms
description: Simple CMS with posts, pages, categories, Tiptap rich text editor, and media management. Built on better-auth, drizzle, and storage skills. Use this skill when the user says "setup cms", "add cms", "content management", or "blog system".
author: "@mattwoodco"
version: 2.0.1
created: 2026-01-11
updated: 2026-02-13
validated: 2026-02-13
dependencies: [env-config, docker, auth, storage, storage-ui, add-shadcn]
---

# Content Management System

A lightweight CMS built on your existing stack: drizzle for the database, better-auth for authentication, the storage skill for file uploads, and Tiptap for rich text editing. Provides an admin UI at `/admin/content` for managing posts, pages, categories, and media.

## Quick Start

```bash
# 1. Install CMS dependencies
bun add @tiptap/react @tiptap/pm @tiptap/starter-kit @tiptap/extension-image @tiptap/extension-link @tiptap/extension-placeholder react-hook-form @hookform/resolvers @tailwindcss/typography

# 2. Install shadcn components
bunx shadcn@latest add table badge input textarea label separator tabs card select

# 3. Push schema to database
bunx drizzle-kit push

# 4. Start dev server and open admin
bun dev
open http://localhost:3000/admin/content
```

## What Gets Created

### Database Schema

1. **`src/db/schema/cms.ts`** — Drizzle schema for posts, pages, categories, and join tables

### API Routes

1. **`src/app/api/cms/posts/route.ts`** — List and create posts
2. **`src/app/api/cms/posts/[id]/route.ts`** — Get, update, delete a post
3. **`src/app/api/cms/pages/route.ts`** — List and create pages
4. **`src/app/api/cms/pages/[id]/route.ts`** — Get, update, delete a page
5. **`src/app/api/cms/categories/route.ts`** — List, create, update, delete categories

### Components

1. **`src/components/cms/tiptap-editor.tsx`** — Rich text editor with toolbar
2. **`src/components/cms/media-picker.tsx`** — Image/video picker dialog using storage
3. **`src/components/cms/post-form.tsx`** — Post create/edit form
4. **`src/components/cms/page-form.tsx`** — Page create/edit form

### Admin Pages

1. **`src/app/admin/content/layout.tsx`** — Admin sidebar layout
2. **`src/app/admin/content/page.tsx`** — Content dashboard
3. **`src/app/admin/content/posts/page.tsx`** — Posts list
4. **`src/app/admin/content/posts/new/page.tsx`** — Create post
5. **`src/app/admin/content/posts/[id]/page.tsx`** — Edit post
6. **`src/app/admin/content/pages/page.tsx`** — Pages list
7. **`src/app/admin/content/pages/new/page.tsx`** — Create page
8. **`src/app/admin/content/pages/[id]/page.tsx`** — Edit page
9. **`src/app/admin/content/categories/page.tsx`** — Categories management
10. **`src/app/admin/content/media/page.tsx`** — Media management (wraps storage-ui)

### Modified Files

- **`src/db/index.ts`** — Add CMS schema import

## Prerequisites

Before using this skill:

1. **auth skill** completed — Provides `lib/auth-guard.ts` (`withAuth`, `withAdmin`), `db/index.ts`, `db/schema/auth.ts`, drizzle setup
2. **storage skill** completed — Provides `lib/storage/` and `/api/storage` endpoints
3. **storage-ui skill** completed — Provides `components/storage/` UI components
4. **shadcn/ui initialized** — With base components installed

## Project Structure Note

This skill uses `src/` prefix paths (standard Next.js with `--src-dir`).

**If your project uses `--no-src-dir`:**

- Replace `src/lib/` with `lib/`
- Replace `src/app/` with `app/`
- Replace `src/components/` with `components/`
- Replace `src/db/` with `db/`

## Installation

```bash
# Tiptap editor
bun add @tiptap/react @tiptap/pm @tiptap/starter-kit @tiptap/extension-image @tiptap/extension-link @tiptap/extension-placeholder

# Form handling
bun add react-hook-form @hookform/resolvers

# Tailwind typography (for prose styles in editor)
bun add @tailwindcss/typography

# shadcn components needed by CMS admin
bunx shadcn@latest add table badge input textarea label separator tabs card select
```

## Setup Steps

### 1. Create CMS Database Schema (`src/db/schema/cms.ts`)

```typescript
import {
  pgTable,
  text,
  timestamp,
  jsonb,
  primaryKey,
} from "drizzle-orm/pg-core";
import { relations } from "drizzle-orm";
import { user } from "./auth";

export const categories = pgTable("cms_categories", {
  id: text("id")
    .primaryKey()
    .$defaultFn(() => crypto.randomUUID()),
  name: text("name").notNull(),
  slug: text("slug").notNull().unique(),
  description: text("description"),
  createdAt: timestamp("created_at").notNull().defaultNow(),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});

export const posts = pgTable("cms_posts", {
  id: text("id")
    .primaryKey()
    .$defaultFn(() => crypto.randomUUID()),
  title: text("title").notNull(),
  slug: text("slug").notNull().unique(),
  content: jsonb("content"),
  excerpt: text("excerpt"),
  featuredMediaUrl: text("featured_media_url"),
  featuredMediaKey: text("featured_media_key"),
  featuredMediaType: text("featured_media_type"),
  status: text("status").notNull().default("draft"),
  authorId: text("author_id")
    .notNull()
    .references(() => user.id),
  publishedAt: timestamp("published_at"),
  createdAt: timestamp("created_at").notNull().defaultNow(),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});

export const pages = pgTable("cms_pages", {
  id: text("id")
    .primaryKey()
    .$defaultFn(() => crypto.randomUUID()),
  title: text("title").notNull(),
  slug: text("slug").notNull().unique(),
  content: jsonb("content"),
  metaTitle: text("meta_title"),
  metaDescription: text("meta_description"),
  metaImageUrl: text("meta_image_url"),
  metaImageKey: text("meta_image_key"),
  status: text("status").notNull().default("draft"),
  createdAt: timestamp("created_at").notNull().defaultNow(),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});

export const postsToCategories = pgTable(
  "cms_posts_to_categories",
  {
    postId: text("post_id")
      .notNull()
      .references(() => posts.id, { onDelete: "cascade" }),
    categoryId: text("category_id")
      .notNull()
      .references(() => categories.id, { onDelete: "cascade" }),
  },
  (t) => [primaryKey({ columns: [t.postId, t.categoryId] })]
);

export const postsRelations = relations(posts, ({ one, many }) => ({
  author: one(user, { fields: [posts.authorId], references: [user.id] }),
  postCategories: many(postsToCategories),
}));

export const categoriesRelations = relations(categories, ({ many }) => ({
  categoryPosts: many(postsToCategories),
}));

export const postsToCategoriesRelations = relations(
  postsToCategories,
  ({ one }) => ({
    post: one(posts, {
      fields: [postsToCategories.postId],
      references: [posts.id],
    }),
    category: one(categories, {
      fields: [postsToCategories.categoryId],
      references: [categories.id],
    }),
  })
);
```

### 2. Update Database Client (`src/db/index.ts`)

Add the CMS schema import alongside the existing auth schema:

```typescript
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as authSchema from "./schema/auth";
import * as cmsSchema from "./schema/cms";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error("DATABASE_URL is not set");

export const client = postgres(connectionString, { prepare: false });
export const db = drizzle(client, {
  schema: { ...authSchema, ...cmsSchema },
});
```

### 3. Add Tailwind Typography Plugin

Add to your `src/app/globals.css` (after the existing `@import "tailwindcss";`):

```css
@plugin "@tailwindcss/typography";
```

### 4. Create Posts API Routes

**`src/app/api/cms/posts/route.ts`**:

```typescript
import { NextRequest, NextResponse } from "next/server";
import { withAdmin } from "@/lib/auth-guard";
import { db } from "@/lib/db";
import { posts, postsToCategories, categories } from "@/lib/db/schema/cms";
import { desc, eq, ilike, sql, and, inArray } from "drizzle-orm";

export const GET = withAdmin(async (request) => {
  const url = request.nextUrl;
  const page = Math.max(1, Number(url.searchParams.get("page") ?? "1"));
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get("limit") ?? "20")));
  const status = url.searchParams.get("status");
  const search = url.searchParams.get("search");
  const offset = (page - 1) * limit;

  const conditions = [];
  if (status) conditions.push(eq(posts.status, status));
  if (search) conditions.push(ilike(posts.title, `%${search}%`));

  const where = conditions.length > 0 ? and(...conditions) : undefined;

  const [items, countResult] = await Promise.all([
    db
      .select()
      .from(posts)
      .where(where)
      .orderBy(desc(posts.createdAt))
      .limit(limit)
      .offset(offset),
    db
      .select({ count: sql<number>`count(*)` })
      .from(posts)
      .where(where),
  ]);

  return NextResponse.json({
    posts: items,
    total: Number(countResult[0].count),
    page,
    limit,
  });
});

export const POST = withAdmin(async (request, { user }) => {
  const body = await request.json();
  const { title, slug, content, excerpt, featuredMediaUrl, featuredMediaKey, featuredMediaType, status, categoryIds, publishedAt } = body;

  if (!title || !slug) {
    return NextResponse.json({ error: "Title and slug are required" }, { status: 400 });
  }

  const [post] = await db
    .insert(posts)
    .values({
      title,
      slug,
      content: content ?? null,
      excerpt: excerpt ?? null,
      featuredMediaUrl: featuredMediaUrl ?? null,
      featuredMediaKey: featuredMediaKey ?? null,
      featuredMediaType: featuredMediaType ?? null,
      status: status ?? "draft",
      authorId: user.id,
      publishedAt: publishedAt ? new Date(publishedAt) : null,
    })
    .returning();

  if (categoryIds?.length > 0) {
    await db.insert(postsToCategories).values(
      categoryIds.map((categoryId: string) => ({
        postId: post.id,
        categoryId,
      }))
    );
  }

  return NextResponse.json({ post }, { status: 201 });
});
```

**`src/app/api/cms/posts/[id]/route.ts`**:

**Note:** For routes with dynamic params like `[id]`, use `getServerSession()` directly instead of `withAdmin`, because `withAdmin` returns `(request) => ...` and does not forward Next.js route context.

```typescript
import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { posts, postsToCategories } from "@/lib/db/schema/cms";
import { eq } from "drizzle-orm";
import { getServerSession } from "@/lib/auth-guard";

type RouteParams = { params: Promise<{ id: string }> };

export async function GET(request: NextRequest, { params }: RouteParams) {
  const session = await getServerSession();
  if (!session || (session.user as { role?: string }).role !== "admin") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { id } = await params;

  const post = await db.query.posts.findFirst({
    where: eq(posts.id, id),
    with: {
      postCategories: {
        with: { category: true },
      },
    },
  });

  if (!post) {
    return NextResponse.json({ error: "Post not found" }, { status: 404 });
  }

  return NextResponse.json({ post });
}

export async function PATCH(request: NextRequest, { params }: RouteParams) {
  const session = await getServerSession();
  if (!session || (session.user as { role?: string }).role !== "admin") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { id } = await params;
  const body = await request.json();
  const { title, slug, content, excerpt, featuredMediaUrl, featuredMediaKey, featuredMediaType, status, categoryIds, publishedAt } = body;

  const updateData: Record<string, unknown> = { updatedAt: new Date() };
  if (title !== undefined) updateData.title = title;
  if (slug !== undefined) updateData.slug = slug;
  if (content !== undefined) updateData.content = content;
  if (excerpt !== undefined) updateData.excerpt = excerpt;
  if (featuredMediaUrl !== undefined) updateData.featuredMediaUrl = featuredMediaUrl;
  if (featuredMediaKey !== undefined) updateData.featuredMediaKey = featuredMediaKey;
  if (featuredMediaType !== undefined) updateData.featuredMediaType = featuredMediaType;
  if (status !== undefined) updateData.status = status;
  if (publishedAt !== undefined) updateData.publishedAt = publishedAt ? new Date(publishedAt) : null;

  const [updated] = await db
    .update(posts)
    .set(updateData)
    .where(eq(posts.id, id))
    .returning();

  if (!updated) {
    return NextResponse.json({ error: "Post not found" }, { status: 404 });
  }

  if (categoryIds !== undefined) {
    await db.delete(postsToCategories).where(eq(postsToCategories.postId, id));
    if (categoryIds.length > 0) {
      await db.insert(postsToCategories).values(
        categoryIds.map((categoryId: string) => ({
          postId: id,
          categoryId,
        }))
      );
    }
  }

  return NextResponse.json({ post: updated });
}

export async function DELETE(request: NextRequest, { params }: RouteParams) {
  const session = await getServerSession();
  if (!session || (session.user as { role?: string }).role !== "admin") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { id } = await params;

  const [deleted] = await db
    .delete(posts)
    .where(eq(posts.id, id))
    .returning();

  if (!deleted) {
    return NextResponse.json({ error: "Post not found" }, { status: 404 });
  }

  return NextResponse.json({ success: true });
}
```

### 5. Create Pages API Routes

**`src/app/api/cms/pages/route.ts`**:

```typescript
import { NextRequest, NextResponse } from "next/server";
import { withAdmin } from "@/lib/auth-guard";
import { db } from "@/lib/db";
import { pages } from "@/lib/db/schema/cms";
import { desc, eq, ilike, sql, and } from "drizzle-orm";

export const GET = withAdmin(async (request) => {
  const url = request.nextUrl;
  const page = Math.max(1, Number(url.searchParams.get("page") ?? "1"));
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get("limit") ?? "20")));
  const status = url.searchParams.get("status");
  const search = url.searchParams.get("search");
  const offset = (page - 1) * limit;

  const conditions = [];
  if (status) conditions.push(eq(pages.status, status));
  if (search) conditions.push(ilike(pages.title, `%${search}%`));

  const where = conditions.length > 0 ? and(...conditions) : undefined;

  const [items, countResult] = await Promise.all([
    db
      .select()
      .from(pages)
      .where(where)
      .orderBy(desc(pages.createdAt))
      .limit(limit)
      .offset(offset),
    db
      .select({ count: sql<number>`count(*)` })
      .from(pages)
      .where(where),
  ]);

  return NextResponse.json({
    pages: items,
    total: Number(countResult[0].count),
    page,
    limit,
  });
});

export const POST = withAdmin(async (request) => {
  const body = await request.json();
  const { title, slug, content, metaTitle, metaDescription, metaImageUrl, metaImageKey, status } = body;

  if (!title || !slug) {
    return NextResponse.json({ error: "Title and slug are required" }, { status: 400 });
  }

  const [created] = await db
    .insert(pages)
    .values({
      title,
      slug,
      content: content ?? null,
      metaTitle: metaTitle ?? null,
      metaDescription: metaDescription ?? null,
      metaImageUrl: metaImageUrl ?? null,
      metaImageKey: metaImageKey ?? null,
      status: status ?? "draft",
    })
    .returning();

  return NextResponse.json({ page: created }, { status: 201 });
});
```

**`src/app/api/cms/pages/[id]/route.ts`**:

```typescript
import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { pages } from "@/lib/db/schema/cms";
import { eq } from "drizzle-orm";
import { getServerSession } from "@/lib/auth-guard";

type RouteParams = { params: Promise<{ id: string }> };

export async function GET(request: NextRequest, { params }: RouteParams) {
  const session = await getServerSession();
  if (!session || (session.user as { role?: string }).role !== "admin") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { id } = await params;
  const [page] = await db.select().from(pages).where(eq(pages.id, id));

  if (!page) {
    return NextResponse.json({ error: "Page not found" }, { status: 404 });
  }

  return NextResponse.json({ page });
}

export async function PATCH(request: NextRequest, { params }: RouteParams) {
  const session = await getServerSession();
  if (!session || (session.user as { role?: string }).role !== "admin") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { id } = await params;
  const body = await request.json();
  const { title, slug, content, metaTitle, metaDescription, metaImageUrl, metaImageKey, status } = body;

  const updateData: Record<string, unknown> = { updatedAt: new Date() };
  if (title !== undefined) updateData.title = title;
  if (slug !== undefined) updateData.slug = slug;
  if (content !== undefined) updateData.content = content;
  if (metaTitle !== undefined) updateData.metaTitle = metaTitle;
  if (metaDescription !== undefined) updateData.metaDescription = metaDescription;
  if (metaImageUrl !== undefined) updateData.metaImageUrl = metaImageUrl;
  if (metaImageKey !== undefined) updateData.metaImageKey = metaImageKey;
  if (status !== undefined) updateData.status = status;

  const [updated] = await db
    .update(pages)
    .set(updateData)
    .where(eq(pages.id, id))
    .returning();

  if (!updated) {
    return NextResponse.json({ error: "Page not found" }, { status: 404 });
  }

  return NextResponse.json({ page: updated });
}

export async function DELETE(request: NextRequest, { params }: RouteParams) {
  const session = await getServerSession();
  if (!session || (session.user as { role?: string }).role !== "admin") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { id } = await params;
  const [deleted] = await db
    .delete(pages)
    .where(eq(pages.id, id))
    .returning();

  if (!deleted) {
    return NextResponse.json({ error: "Page not found" }, { status: 404 });
  }

  return NextResponse.json({ success: true });
}
```

### 6. Create Categories API Route

**`src/app/api/cms/categories/route.ts`**:

```typescript
import { NextRequest, NextResponse } from "next/server";
import { withAdmin } from "@/lib/auth-guard";
import { db } from "@/lib/db";
import { categories } from "@/lib/db/schema/cms";
import { eq, asc } from "drizzle-orm";

export const GET = withAdmin(async () => {
  const items = await db
    .select()
    .from(categories)
    .orderBy(asc(categories.name));

  return NextResponse.json({ categories: items });
});

export const POST = withAdmin(async (request) => {
  const body = await request.json();
  const { name, slug, description } = body;

  if (!name || !slug) {
    return NextResponse.json({ error: "Name and slug are required" }, { status: 400 });
  }

  const [created] = await db
    .insert(categories)
    .values({
      name,
      slug,
      description: description ?? null,
    })
    .returning();

  return NextResponse.json({ category: created }, { status: 201 });
});

export const PATCH = withAdmin(async (request) => {
  const body = await request.json();
  const { id, name, slug, description } = body;

  if (!id) {
    return NextResponse.json({ error: "ID is required" }, { status: 400 });
  }

  const updateData: Record<string, unknown> = { updatedAt: new Date() };
  if (name !== undefined) updateData.name = name;
  if (slug !== undefined) updateData.slug = slug;
  if (description !== undefined) updateData.description = description;

  const [updated] = await db
    .update(categories)
    .set(updateData)
    .where(eq(categories.id, id))
    .returning();

  if (!updated) {
    return NextResponse.json({ error: "Category not found" }, { status: 404 });
  }

  return NextResponse.json({ category: updated });
});

export const DELETE = withAdmin(async (request) => {
  const body = await request.json();
  const { id } = body;

  if (!id) {
    return NextResponse.json({ error: "ID is required" }, { status: 400 });
  }

  await db.delete(categories).where(eq(categories.id, id));
  return NextResponse.json({ success: true });
});
```

### 7. Create Tiptap Editor Component (`src/components/cms/tiptap-editor.tsx`)

```tsx
"use client";

import { memo } from "react";
import { useEditor, EditorContent, type JSONContent } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import Image from "@tiptap/extension-image";
import Link from "@tiptap/extension-link";
import Placeholder from "@tiptap/extension-placeholder";
import { cn } from "@/lib/utils";
import {
  TextB,
  TextItalic,
  TextStrikethrough,
  TextHOne,
  TextHTwo,
  TextHThree,
  ListBullets,
  ListNumbers,
  Quotes,
  Code,
  ImageSquare,
  LinkSimple,
  ArrowUUpLeft,
  ArrowUUpRight,
} from "@phosphor-icons/react";

type ToolbarButtonProps = {
  onClick: () => void;
  isActive?: boolean;
  disabled?: boolean;
  children: React.ReactNode;
  title: string;
};

const ToolbarButton = memo(function ToolbarButton({ onClick, isActive, disabled, children, title }: ToolbarButtonProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={title}
      className={cn(
        "rounded p-1.5 transition-colors hover:bg-zinc-100",
        isActive && "bg-zinc-200 text-zinc-900",
        disabled && "cursor-not-allowed opacity-40"
      )}
    >
      {children}
    </button>
  );
});

type TiptapEditorProps = {
  content: JSONContent | null;
  onChange: (content: JSONContent) => void;
  onInsertImage?: () => void;
  placeholder?: string;
};

export function TiptapEditor({
  content,
  onChange,
  onInsertImage,
  placeholder = "Write your content...",
}: TiptapEditorProps) {
  const editor = useEditor({
    extensions: [
      StarterKit,
      Image.configure({ inline: false }),
      Link.configure({ openOnClick: false }),
      Placeholder.configure({ placeholder }),
    ],
    content: content ?? undefined,
    onUpdate: ({ editor: e }) => {
      onChange(e.getJSON());
    },
  });

  if (!editor) return null;

  const addLink = () => {
    const url = window.prompt("Enter URL:");
    if (url) {
      editor.chain().focus().setLink({ href: url }).run();
    }
  };

  return (
    <div className="rounded-lg border">
      <div className="flex flex-wrap gap-0.5 border-b p-1.5">
        <ToolbarButton
          onClick={() => editor.chain().focus().toggleBold().run()}
          isActive={editor.isActive("bold")}
          title="Bold"
        >
          <TextB className="h-4 w-4" />
        </ToolbarButton>
        <ToolbarButton
          onClick={() => editor.chain().focus().toggleItalic().run()}
          isActive={editor.isActive("italic")}
          title="Italic"
        >
          <TextItalic className="h-4 w-4" />
        </ToolbarButton>
        <ToolbarButton
          onClick={() => editor.chain().focus().toggleStrike().run()}
          isActive={editor.isActive("strike")}
          title="Strikethrough"
        >
          <TextStrikethrough className="h-4 w-4" />
        </ToolbarButton>

        <div className="mx-1 w-px bg-zinc-200" />

        <ToolbarButton
          onClick={() => editor.chain().focus().toggleHeading({ level: 1 }).run()}
          isActive={editor.isActive("heading", { level: 1 })}
          title="Heading 1"
        >
          <TextHOne className="h-4 w-4" />
        </ToolbarButton>
        <ToolbarButton
          onClick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()}
          isActive={editor.isActive("heading", { level: 2 })}
          title="Heading 2"
        >
          <TextHTwo className="h-4 w-4" />
        </ToolbarButton>
        <ToolbarButton
          onClick={() => editor.chain().focus().toggleHeading({ level: 3 }).run()}
          isActive={editor.isActive("heading", { level: 3 })}
          title="Heading 3"
        >
          <TextHThree className="h-4 w-4" />
        </ToolbarButton>

        <div className="mx-1 w-px bg-zinc-200" />

        <ToolbarButton
          onClick={() => editor.chain().focus().toggleBulletList().run()}
          isActive={editor.isActive("bulletList")}
          title="Bullet List"
        >
          <ListBullets className="h-4 w-4" />
        </ToolbarButton>
        <ToolbarButton
          onClick={() => editor.chain().focus().toggleOrderedList().run()}
          isActive={editor.isActive("orderedList")}
          title="Ordered List"
        >
          <ListNumbers className="h-4 w-4" />
        </ToolbarButton>
        <ToolbarButton
          onClick={() => editor.chain().focus().toggleBlockquote().run()}
          isActive={editor.isActive("blockquote")}
          title="Blockquote"
        >
          <Quotes className="h-4 w-4" />
        </ToolbarButton>
        <ToolbarButton
          onClick={() => editor.chain().focus().toggleCodeBlock().run()}
          isActive={editor.isActive("codeBlock")}
          title="Code Block"
        >
          <Code className="h-4 w-4" />
        </ToolbarButton>

        <div className="mx-1 w-px bg-zinc-200" />

        <ToolbarButton onClick={addLink} isActive={editor.isActive("link")} title="Insert Link">
          <LinkSimple className="h-4 w-4" />
        </ToolbarButton>
        {onInsertImage && (
          <ToolbarButton onClick={onInsertImage} title="Insert Image">
            <ImageSquare className="h-4 w-4" />
          </ToolbarButton>
        )}

        <div className="mx-1 w-px bg-zinc-200" />

        <ToolbarButton
          onClick={() => editor.chain().focus().undo().run()}
          disabled={!editor.can().undo()}
          title="Undo"
        >
          <ArrowUUpLeft className="h-4 w-4" />
        </ToolbarButton>
        <ToolbarButton
          onClick={() => editor.chain().focus().redo().run()}
          disabled={!editor.can().redo()}
          title="Redo"
        >
          <ArrowUUpRight className="h-4 w-4" />
        </ToolbarButton>
      </div>

      <EditorContent
        editor={editor}
        className="prose prose-zinc max-w-none p-4 [&_.ProseMirror]:min-h-[200px] [&_.ProseMirror]:outline-none [&_.ProseMirror_p.is-editor-empty:first-child::before]:text-zinc-400 [&_.ProseMirror_p.is-editor-empty:first-child::before]:content-[attr(data-placeholder)] [&_.ProseMirror_p.is-editor-empty:first-child::before]:float-left [&_.ProseMirror_p.is-editor-empty:first-child::before]:pointer-events-none [&_.ProseMirror_p.is-editor-empty:first-child::before]:h-0"
      />
    </div>
  );
}

export function insertImageIntoEditor(
  editorRef: { current: ReturnType<typeof useEditor> | null },
  url: string
) {
  editorRef.current?.chain().focus().setImage({ src: url }).run();
}
```

### 8. Create Media Picker Component (`src/components/cms/media-picker.tsx`)

```tsx
"use client";

import { useCallback, useEffect, useId, useState } from "react";
import { cn } from "@/lib/utils";
import { ImageSquare, VideoCamera, Check, CircleNotch, UploadSimple } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

type MediaFile = {
  key: string;
  name: string;
  size: number;
  contentType: string;
  url: string;
};

type MediaPickerProps = {
  open: boolean;
  onClose: () => void;
  onSelect: (file: MediaFile) => void;
  accept?: ("images" | "video")[];
};

export function MediaPicker({
  open,
  onClose,
  onSelect,
  accept = ["images", "video"],
}: MediaPickerProps) {
  const listId = useId();
  const [files, setFiles] = useState<MediaFile[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);

  const fetchFiles = useCallback(async () => {
    setIsLoading(true);
    try {
      const response = await fetch("/api/storage");
      if (response.ok) {
        const data = await response.json();
        const allFiles: MediaFile[] = data.files ?? [];
        const filtered = allFiles.filter((f) => {
          if (accept.includes("images") && f.contentType.startsWith("image/")) return true;
          if (accept.includes("video") && f.contentType.startsWith("video/")) return true;
          return false;
        });
        setFiles(filtered);
      }
    } finally {
      setIsLoading(false);
    }
  }, [accept]);

  useEffect(() => {
    if (open) {
      fetchFiles();
      setSelected(null);
    }
  }, [open, fetchFiles]);

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const fileList = e.target.files;
    if (!fileList || fileList.length === 0) return;

    setIsUploading(true);
    try {
      const formData = new FormData();
      formData.append("file", fileList[0]);
      const response = await fetch("/api/storage/upload", {
        method: "POST",
        body: formData,
      });
      if (response.ok) {
        await fetchFiles();
      }
    } finally {
      setIsUploading(false);
      e.target.value = "";
    }
  };

  const handleConfirm = () => {
    const file = files.find((f) => f.key === selected);
    if (file) {
      onSelect(file);
      onClose();
    }
  };

  const acceptMimes = [
    ...(accept.includes("images") ? ["image/*"] : []),
    ...(accept.includes("video") ? ["video/*"] : []),
  ].join(",");

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-3xl max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>Select Media</DialogTitle>
        </DialogHeader>

        <div className="flex items-center gap-2 pb-4">
          <Button variant="outline" size="sm" asChild className="relative">
            <label>
              <UploadSimple className="mr-2 h-4 w-4" />
              {isUploading ? "Uploading..." : "Upload New"}
              <input
                type="file"
                accept={acceptMimes}
                onChange={handleUpload}
                disabled={isUploading}
                className="absolute inset-0 cursor-pointer opacity-0"
              />
            </label>
          </Button>
        </div>

        <div className="flex-1 overflow-y-auto">
          {isLoading ? (
            <div className="flex items-center justify-center py-12">
              <CircleNotch className="h-6 w-6 animate-spin text-zinc-400" />
            </div>
          ) : files.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-12 text-zinc-400">
              <ImageSquare className="h-8 w-8 mb-2" />
              <p className="text-sm">No media files found</p>
            </div>
          ) : (
            <div className="grid grid-cols-3 gap-3 sm:grid-cols-4">
              {files.map((file) => {
                const isImage = file.contentType.startsWith("image/");
                return (
                  <button
                    key={`${listId}-${file.key}`}
                    type="button"
                    onClick={() => setSelected(file.key)}
                    className={cn(
                      "relative aspect-square overflow-hidden rounded-lg border-2 transition-colors",
                      selected === file.key
                        ? "border-blue-500 ring-2 ring-blue-200"
                        : "border-transparent hover:border-zinc-300"
                    )}
                  >
                    {isImage ? (
                      <img
                        src={file.url}
                        alt={file.name}
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <div className="flex h-full w-full flex-col items-center justify-center bg-zinc-100">
                        <VideoCamera className="h-8 w-8 text-zinc-400" />
                        <span className="mt-1 truncate px-2 text-xs text-zinc-500">
                          {file.name}
                        </span>
                      </div>
                    )}
                    {selected === file.key && (
                      <div className="absolute inset-0 flex items-center justify-center bg-blue-500/20">
                        <Check className="h-6 w-6 text-blue-600" />
                      </div>
                    )}
                  </button>
                );
              })}
            </div>
          )}
        </div>

        <div className="flex justify-end gap-2 border-t pt-4">
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={handleConfirm} disabled={!selected}>
            Select
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
```

### 9. Create Post Form Component (`src/components/cms/post-form.tsx`)

```tsx
"use client";

import { useState, useCallback, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { CircleNotch } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { TiptapEditor } from "./tiptap-editor";
import { MediaPicker } from "./media-picker";
import type { JSONContent } from "@tiptap/react";

const postSchema = z.object({
  title: z.string().min(1, "Title is required"),
  slug: z.string().min(1, "Slug is required"),
  excerpt: z.string().optional(),
  status: z.enum(["draft", "published"]),
});

type PostFormValues = z.infer<typeof postSchema>;

type Category = {
  id: string;
  name: string;
  slug: string;
};

type PostData = {
  id?: string;
  title: string;
  slug: string;
  content: JSONContent | null;
  excerpt: string | null;
  featuredMediaUrl: string | null;
  featuredMediaKey: string | null;
  featuredMediaType: string | null;
  status: string;
  publishedAt: string | null;
  postCategories?: Array<{ category: Category }>;
};

type PostFormProps = {
  post?: PostData;
  isEdit?: boolean;
};

function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

export function PostForm({ post, isEdit }: PostFormProps) {
  const router = useRouter();
  const [content, setContent] = useState<JSONContent | null>(post?.content ?? null);
  const [featuredMedia, setFeaturedMedia] = useState<{
    url: string | null;
    key: string | null;
    type: string | null;
  }>({
    url: post?.featuredMediaUrl ?? null,
    key: post?.featuredMediaKey ?? null,
    type: post?.featuredMediaType ?? null,
  });
  const [mediaPickerOpen, setMediaPickerOpen] = useState(false);
  const [mediaPickerTarget, setMediaPickerTarget] = useState<"featured" | "editor">("featured");
  const [allCategories, setAllCategories] = useState<Category[]>([]);
  const [selectedCategoryIds, setSelectedCategoryIds] = useState<string[]>(
    post?.postCategories?.map((pc) => pc.category.id) ?? []
  );
  const [isSubmitting, setIsSubmitting] = useState(false);

  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors },
  } = useForm<PostFormValues>({
    resolver: zodResolver(postSchema),
    defaultValues: {
      title: post?.title ?? "",
      slug: post?.slug ?? "",
      excerpt: post?.excerpt ?? "",
      status: (post?.status as "draft" | "published") ?? "draft",
    },
  });

  const title = watch("title");

  useEffect(() => {
    if (!isEdit && title) {
      setValue("slug", slugify(title));
    }
  }, [title, isEdit, setValue]);

  useEffect(() => {
    fetch("/api/cms/categories")
      .then((r) => r.json())
      .then((data) => setAllCategories(data.categories ?? []))
      .catch(() => {});
  }, []);

  const onSubmit = async (values: PostFormValues) => {
    setIsSubmitting(true);
    try {
      const payload = {
        ...values,
        content,
        featuredMediaUrl: featuredMedia.url,
        featuredMediaKey: featuredMedia.key,
        featuredMediaType: featuredMedia.type,
        categoryIds: selectedCategoryIds,
        publishedAt: values.status === "published" ? new Date().toISOString() : null,
      };

      const url = isEdit ? `/api/cms/posts/${post?.id}` : "/api/cms/posts";
      const method = isEdit ? "PATCH" : "POST";

      const response = await fetch(url, {
        method,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (response.ok) {
        router.push("/admin/content/posts");
        router.refresh();
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const openMediaPicker = useCallback((target: "featured" | "editor") => {
    setMediaPickerTarget(target);
    setMediaPickerOpen(true);
  }, []);

  const handleMediaSelect = useCallback(
    (file: { url: string; key: string; contentType: string }) => {
      if (mediaPickerTarget === "featured") {
        setFeaturedMedia({
          url: file.url,
          key: file.key,
          type: file.contentType.startsWith("video/") ? "video" : "image",
        });
      }
      // For editor image insertion, the TiptapEditor handles it via onInsertImage
    },
    [mediaPickerTarget]
  );

  const toggleCategory = (categoryId: string) => {
    setSelectedCategoryIds((prev) =>
      prev.includes(categoryId)
        ? prev.filter((id) => id !== categoryId)
        : [...prev, categoryId]
    );
  };

  return (
    <>
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
        <div className="grid gap-6 lg:grid-cols-[1fr_300px]">
          {/* Main content */}
          <div className="space-y-6">
            <div className="space-y-2">
              <Label htmlFor="title">Title</Label>
              <Input id="title" {...register("title")} placeholder="Post title" />
              {errors.title && <p className="text-sm text-red-500">{errors.title.message}</p>}
            </div>

            <div className="space-y-2">
              <Label htmlFor="slug">Slug</Label>
              <Input id="slug" {...register("slug")} placeholder="post-slug" />
              {errors.slug && <p className="text-sm text-red-500">{errors.slug.message}</p>}
            </div>

            <div className="space-y-2">
              <Label>Content</Label>
              <TiptapEditor
                content={content}
                onChange={setContent}
                onInsertImage={() => openMediaPicker("editor")}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="excerpt">Excerpt</Label>
              <Textarea id="excerpt" {...register("excerpt")} placeholder="Brief description..." rows={3} />
            </div>
          </div>

          {/* Sidebar */}
          <div className="space-y-6">
            <div className="space-y-2">
              <Label>Status</Label>
              <Select
                defaultValue={post?.status ?? "draft"}
                onValueChange={(value) => setValue("status", value as "draft" | "published")}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="draft">Draft</SelectItem>
                  <SelectItem value="published">Published</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Featured Media</Label>
              {featuredMedia.url ? (
                <div className="relative rounded-lg border overflow-hidden">
                  {featuredMedia.type === "video" ? (
                    <video src={featuredMedia.url} controls className="w-full" />
                  ) : (
                    <img src={featuredMedia.url} alt="Featured" className="w-full object-cover" />
                  )}
                  <div className="flex gap-2 p-2">
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => openMediaPicker("featured")}
                    >
                      Change
                    </Button>
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => setFeaturedMedia({ url: null, key: null, type: null })}
                    >
                      Remove
                    </Button>
                  </div>
                </div>
              ) : (
                <Button
                  type="button"
                  variant="outline"
                  className="w-full"
                  onClick={() => openMediaPicker("featured")}
                >
                  Select Featured Media
                </Button>
              )}
            </div>

            {allCategories.length > 0 && (
              <div className="space-y-2">
                <Label>Categories</Label>
                <div className="space-y-1 rounded-lg border p-3 max-h-[200px] overflow-y-auto">
                  {allCategories.map((cat) => (
                    <label key={cat.id} className="flex items-center gap-2 text-sm cursor-pointer">
                      <input
                        type="checkbox"
                        checked={selectedCategoryIds.includes(cat.id)}
                        onChange={() => toggleCategory(cat.id)}
                        className="rounded"
                      />
                      {cat.name}
                    </label>
                  ))}
                </div>
              </div>
            )}

            <Button type="submit" className="w-full" disabled={isSubmitting}>
              {isSubmitting && <CircleNotch className="mr-2 h-4 w-4 animate-spin" />}
              {isEdit ? "Update Post" : "Create Post"}
            </Button>
          </div>
        </div>
      </form>

      <MediaPicker
        open={mediaPickerOpen}
        onClose={() => setMediaPickerOpen(false)}
        onSelect={handleMediaSelect}
      />
    </>
  );
}
```

### 10. Create Page Form Component (`src/components/cms/page-form.tsx`)

```tsx
"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { CircleNotch } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { TiptapEditor } from "./tiptap-editor";
import { MediaPicker } from "./media-picker";
import type { JSONContent } from "@tiptap/react";

const pageSchema = z.object({
  title: z.string().min(1, "Title is required"),
  slug: z.string().min(1, "Slug is required"),
  metaTitle: z.string().optional(),
  metaDescription: z.string().optional(),
  status: z.enum(["draft", "published"]),
});

type PageFormValues = z.infer<typeof pageSchema>;

type PageData = {
  id?: string;
  title: string;
  slug: string;
  content: JSONContent | null;
  metaTitle: string | null;
  metaDescription: string | null;
  metaImageUrl: string | null;
  metaImageKey: string | null;
  status: string;
};

type PageFormProps = {
  page?: PageData;
  isEdit?: boolean;
};

function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

export function PageForm({ page, isEdit }: PageFormProps) {
  const router = useRouter();
  const [content, setContent] = useState<JSONContent | null>(page?.content ?? null);
  const [metaImage, setMetaImage] = useState<{
    url: string | null;
    key: string | null;
  }>({
    url: page?.metaImageUrl ?? null,
    key: page?.metaImageKey ?? null,
  });
  const [mediaPickerOpen, setMediaPickerOpen] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors },
  } = useForm<PageFormValues>({
    resolver: zodResolver(pageSchema),
    defaultValues: {
      title: page?.title ?? "",
      slug: page?.slug ?? "",
      metaTitle: page?.metaTitle ?? "",
      metaDescription: page?.metaDescription ?? "",
      status: (page?.status as "draft" | "published") ?? "draft",
    },
  });

  const title = watch("title");

  useEffect(() => {
    if (!isEdit && title) {
      setValue("slug", slugify(title));
    }
  }, [title, isEdit, setValue]);

  const onSubmit = async (values: PageFormValues) => {
    setIsSubmitting(true);
    try {
      const payload = {
        ...values,
        content,
        metaImageUrl: metaImage.url,
        metaImageKey: metaImage.key,
      };

      const url = isEdit ? `/api/cms/pages/${page?.id}` : "/api/cms/pages";
      const method = isEdit ? "PATCH" : "POST";

      const response = await fetch(url, {
        method,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (response.ok) {
        router.push("/admin/content/pages");
        router.refresh();
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <>
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
        <div className="grid gap-6 lg:grid-cols-[1fr_300px]">
          <div className="space-y-6">
            <div className="space-y-2">
              <Label htmlFor="title">Title</Label>
              <Input id="title" {...register("title")} placeholder="Page title" />
              {errors.title && <p className="text-sm text-red-500">{errors.title.message}</p>}
            </div>

            <div className="space-y-2">
              <Label htmlFor="slug">Slug</Label>
              <Input id="slug" {...register("slug")} placeholder="page-slug" />
              {errors.slug && <p className="text-sm text-red-500">{errors.slug.message}</p>}
            </div>

            <div className="space-y-2">
              <Label>Content</Label>
              <TiptapEditor content={content} onChange={setContent} />
            </div>
          </div>

          <div className="space-y-6">
            <div className="space-y-2">
              <Label>Status</Label>
              <Select
                defaultValue={page?.status ?? "draft"}
                onValueChange={(value) => setValue("status", value as "draft" | "published")}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="draft">Draft</SelectItem>
                  <SelectItem value="published">Published</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label htmlFor="metaTitle">Meta Title</Label>
              <Input id="metaTitle" {...register("metaTitle")} placeholder="SEO title" />
            </div>

            <div className="space-y-2">
              <Label htmlFor="metaDescription">Meta Description</Label>
              <Textarea id="metaDescription" {...register("metaDescription")} placeholder="SEO description" rows={3} />
            </div>

            <div className="space-y-2">
              <Label>Meta Image</Label>
              {metaImage.url ? (
                <div className="rounded-lg border overflow-hidden">
                  <img src={metaImage.url} alt="Meta" className="w-full object-cover" />
                  <div className="flex gap-2 p-2">
                    <Button type="button" variant="outline" size="sm" onClick={() => setMediaPickerOpen(true)}>
                      Change
                    </Button>
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => setMetaImage({ url: null, key: null })}
                    >
                      Remove
                    </Button>
                  </div>
                </div>
              ) : (
                <Button type="button" variant="outline" className="w-full" onClick={() => setMediaPickerOpen(true)}>
                  Select Meta Image
                </Button>
              )}
            </div>

            <Button type="submit" className="w-full" disabled={isSubmitting}>
              {isSubmitting && <CircleNotch className="mr-2 h-4 w-4 animate-spin" />}
              {isEdit ? "Update Page" : "Create Page"}
            </Button>
          </div>
        </div>
      </form>

      <MediaPicker
        open={mediaPickerOpen}
        onClose={() => setMediaPickerOpen(false)}
        onSelect={(file) => setMetaImage({ url: file.url, key: file.key })}
        accept={["images"]}
      />
    </>
  );
}
```

### 11. Create Admin Content Layout (`src/app/admin/content/layout.tsx`)

```tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { FileText, File, Tag, ImageSquare, SquaresFour } from "@phosphor-icons/react";

const navItems = [
  { href: "/admin/content", label: "Dashboard", icon: SquaresFour, exact: true },
  { href: "/admin/content/posts", label: "Posts", icon: FileText },
  { href: "/admin/content/pages", label: "Pages", icon: File },
  { href: "/admin/content/categories", label: "Categories", icon: Tag },
  { href: "/admin/content/media", label: "Media", icon: ImageSquare },
];

export default function AdminContentLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();

  return (
    <div className="min-h-screen bg-zinc-50">
      <div className="flex">
        <aside className="sticky top-0 h-screen w-64 border-r bg-white p-4">
          <h2 className="mb-6 text-lg font-bold px-3">Content</h2>
          <nav className="space-y-1">
            {navItems.map((item) => {
              const isActive = item.exact
                ? pathname === item.href
                : pathname.startsWith(item.href);
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    "flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors",
                    isActive
                      ? "bg-zinc-100 font-medium text-zinc-900"
                      : "text-zinc-600 hover:bg-zinc-50 hover:text-zinc-900"
                  )}
                >
                  <item.icon className="h-4 w-4" />
                  {item.label}
                </Link>
              );
            })}
          </nav>
        </aside>

        <main className="flex-1 p-8">{children}</main>
      </div>
    </div>
  );
}
```

### 12. Create Admin Dashboard (`src/app/admin/content/page.tsx`)

```tsx
"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { FileText, File, Tag, ImageSquare } from "@phosphor-icons/react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

type Stats = {
  posts: number;
  pages: number;
  categories: number;
};

export default function ContentDashboard() {
  const [stats, setStats] = useState<Stats>({ posts: 0, pages: 0, categories: 0 });

  useEffect(() => {
    Promise.all([
      fetch("/api/cms/posts?limit=1").then((r) => r.json()),
      fetch("/api/cms/pages?limit=1").then((r) => r.json()),
      fetch("/api/cms/categories").then((r) => r.json()),
    ]).then(([postsData, pagesData, categoriesData]) => {
      setStats({
        posts: postsData.total ?? 0,
        pages: pagesData.total ?? 0,
        categories: categoriesData.categories?.length ?? 0,
      });
    });
  }, []);

  const cards = [
    { label: "Posts", value: stats.posts, icon: FileText, href: "/admin/content/posts" },
    { label: "Pages", value: stats.pages, icon: File, href: "/admin/content/pages" },
    { label: "Categories", value: stats.categories, icon: Tag, href: "/admin/content/categories" },
    { label: "Media", value: null, icon: ImageSquare, href: "/admin/content/media" },
  ];

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Content Dashboard</h1>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {cards.map((card) => (
          <Link key={card.href} href={card.href}>
            <Card className="transition-colors hover:bg-zinc-50">
              <CardHeader className="flex flex-row items-center justify-between pb-2">
                <CardTitle className="text-sm font-medium text-zinc-500">{card.label}</CardTitle>
                <card.icon className="h-4 w-4 text-zinc-400" />
              </CardHeader>
              <CardContent>
                <p className="text-2xl font-bold">{card.value ?? "Manage"}</p>
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>
    </div>
  );
}
```

### 13. Create Posts List Page (`src/app/admin/content/posts/page.tsx`)

```tsx
"use client";

import { useEffect, useId, useState } from "react";
import Link from "next/link";
import { Plus, CircleNotch, Trash, PencilSimple } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

type Post = {
  id: string;
  title: string;
  slug: string;
  status: string;
  createdAt: string;
};

export default function PostsListPage() {
  const rowKeyPrefix = useId();
  const [posts, setPosts] = useState<Post[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    fetch("/api/cms/posts?limit=50")
      .then((r) => r.json())
      .then((data) => setPosts(data.posts ?? []))
      .finally(() => setIsLoading(false));
  }, []);

  const handleDelete = async (id: string) => {
    if (!confirm("Delete this post?")) return;
    await fetch(`/api/cms/posts/${id}`, { method: "DELETE" });
    setPosts((prev) => prev.filter((p) => p.id !== id));
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Posts</h1>
        <Button asChild>
          <Link href="/admin/content/posts/new">
            <Plus className="mr-2 h-4 w-4" />
            New Post
          </Link>
        </Button>
      </div>

      {isLoading ? (
        <div className="flex justify-center py-12">
          <CircleNotch className="h-6 w-6 animate-spin" />
        </div>
      ) : posts.length === 0 ? (
        <p className="text-center text-zinc-400 py-12">No posts yet</p>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Title</TableHead>
              <TableHead>Slug</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Created</TableHead>
              <TableHead className="w-[100px]">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {posts.map((post) => (
              <TableRow key={`${rowKeyPrefix}-${post.id}`}>
                <TableCell className="font-medium">{post.title}</TableCell>
                <TableCell className="text-zinc-500">{post.slug}</TableCell>
                <TableCell>
                  <Badge variant={post.status === "published" ? "default" : "secondary"}>
                    {post.status}
                  </Badge>
                </TableCell>
                <TableCell className="text-zinc-500">
                  {new Date(post.createdAt).toLocaleDateString()}
                </TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <Button variant="ghost" size="icon" asChild className="h-8 w-8">
                      <Link href={`/admin/content/posts/${post.id}`}>
                        <PencilSimple className="h-4 w-4" />
                      </Link>
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-red-500"
                      onClick={() => handleDelete(post.id)}
                    >
                      <Trash className="h-4 w-4" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </div>
  );
}
```

### 14. Create New Post Page (`src/app/admin/content/posts/new/page.tsx`)

```tsx
import { PostForm } from "@/components/cms/post-form";

export default function NewPostPage() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Create Post</h1>
      <PostForm />
    </div>
  );
}
```

### 15. Create Edit Post Page (`src/app/admin/content/posts/[id]/page.tsx`)

```tsx
"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { CircleNotch } from "@phosphor-icons/react";
import { PostForm } from "@/components/cms/post-form";

export default function EditPostPage() {
  const params = useParams<{ id: string }>();
  const [post, setPost] = useState<Parameters<typeof PostForm>[0]["post"]>();
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch(`/api/cms/posts/${params.id}`)
      .then((r) => {
        if (!r.ok) throw new Error("Post not found");
        return r.json();
      })
      .then((data) => setPost(data.post))
      .catch((err) => setError(err.message))
      .finally(() => setIsLoading(false));
  }, [params.id]);

  if (isLoading) {
    return (
      <div className="flex justify-center py-12">
        <CircleNotch className="h-6 w-6 animate-spin" />
      </div>
    );
  }

  if (error || !post) {
    return <p className="text-center text-red-500 py-12">{error ?? "Post not found"}</p>;
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Edit Post</h1>
      <PostForm post={post} isEdit />
    </div>
  );
}
```

### 16. Create Pages List (`src/app/admin/content/pages/page.tsx`)

```tsx
"use client";

import { useEffect, useId, useState } from "react";
import Link from "next/link";
import { Plus, CircleNotch, Trash, PencilSimple } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

type PageItem = {
  id: string;
  title: string;
  slug: string;
  status: string;
  createdAt: string;
};

export default function PagesListPage() {
  const rowKeyPrefix = useId();
  const [pageItems, setPageItems] = useState<PageItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    fetch("/api/cms/pages?limit=50")
      .then((r) => r.json())
      .then((data) => setPageItems(data.pages ?? []))
      .finally(() => setIsLoading(false));
  }, []);

  const handleDelete = async (id: string) => {
    if (!confirm("Delete this page?")) return;
    await fetch(`/api/cms/pages/${id}`, { method: "DELETE" });
    setPageItems((prev) => prev.filter((p) => p.id !== id));
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Pages</h1>
        <Button asChild>
          <Link href="/admin/content/pages/new">
            <Plus className="mr-2 h-4 w-4" />
            New Page
          </Link>
        </Button>
      </div>

      {isLoading ? (
        <div className="flex justify-center py-12">
          <CircleNotch className="h-6 w-6 animate-spin" />
        </div>
      ) : pageItems.length === 0 ? (
        <p className="text-center text-zinc-400 py-12">No pages yet</p>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Title</TableHead>
              <TableHead>Slug</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Created</TableHead>
              <TableHead className="w-[100px]">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {pageItems.map((item) => (
              <TableRow key={`${rowKeyPrefix}-${item.id}`}>
                <TableCell className="font-medium">{item.title}</TableCell>
                <TableCell className="text-zinc-500">{item.slug}</TableCell>
                <TableCell>
                  <Badge variant={item.status === "published" ? "default" : "secondary"}>
                    {item.status}
                  </Badge>
                </TableCell>
                <TableCell className="text-zinc-500">
                  {new Date(item.createdAt).toLocaleDateString()}
                </TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <Button variant="ghost" size="icon" asChild className="h-8 w-8">
                      <Link href={`/admin/content/pages/${item.id}`}>
                        <PencilSimple className="h-4 w-4" />
                      </Link>
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-red-500"
                      onClick={() => handleDelete(item.id)}
                    >
                      <Trash className="h-4 w-4" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </div>
  );
}
```

### 17. Create New/Edit Page Pages

**`src/app/admin/content/pages/new/page.tsx`**:

```tsx
import { PageForm } from "@/components/cms/page-form";

export default function NewPagePage() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Create Page</h1>
      <PageForm />
    </div>
  );
}
```

**`src/app/admin/content/pages/[id]/page.tsx`**:

```tsx
"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { CircleNotch } from "@phosphor-icons/react";
import { PageForm } from "@/components/cms/page-form";

export default function EditPagePage() {
  const params = useParams<{ id: string }>();
  const [page, setPage] = useState<Parameters<typeof PageForm>[0]["page"]>();
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch(`/api/cms/pages/${params.id}`)
      .then((r) => {
        if (!r.ok) throw new Error("Page not found");
        return r.json();
      })
      .then((data) => setPage(data.page))
      .catch((err) => setError(err.message))
      .finally(() => setIsLoading(false));
  }, [params.id]);

  if (isLoading) {
    return (
      <div className="flex justify-center py-12">
        <CircleNotch className="h-6 w-6 animate-spin" />
      </div>
    );
  }

  if (error || !page) {
    return <p className="text-center text-red-500 py-12">{error ?? "Page not found"}</p>;
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Edit Page</h1>
      <PageForm page={page} isEdit />
    </div>
  );
}
```

### 18. Create Categories Page (`src/app/admin/content/categories/page.tsx`)

```tsx
"use client";

import { useEffect, useId, useState } from "react";
import { Plus, CircleNotch, Trash, PencilSimple, Check, X } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

type Category = {
  id: string;
  name: string;
  slug: string;
  description: string | null;
};

function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

export default function CategoriesPage() {
  const rowKeyPrefix = useId();
  const [items, setItems] = useState<Category[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState("");
  const [editSlug, setEditSlug] = useState("");
  const [newName, setNewName] = useState("");
  const [newSlug, setNewSlug] = useState("");
  const [isAdding, setIsAdding] = useState(false);

  useEffect(() => {
    fetch("/api/cms/categories")
      .then((r) => r.json())
      .then((data) => setItems(data.categories ?? []))
      .finally(() => setIsLoading(false));
  }, []);

  const handleAdd = async () => {
    if (!newName.trim()) return;
    const slug = newSlug.trim() || slugify(newName);
    const response = await fetch("/api/cms/categories", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: newName.trim(), slug }),
    });
    if (response.ok) {
      const data = await response.json();
      setItems((prev) => [...prev, data.category]);
      setNewName("");
      setNewSlug("");
      setIsAdding(false);
    }
  };

  const handleUpdate = async (id: string) => {
    const response = await fetch("/api/cms/categories", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, name: editName, slug: editSlug }),
    });
    if (response.ok) {
      const data = await response.json();
      setItems((prev) => prev.map((c) => (c.id === id ? data.category : c)));
      setEditingId(null);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm("Delete this category?")) return;
    await fetch("/api/cms/categories", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    });
    setItems((prev) => prev.filter((c) => c.id !== id));
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Categories</h1>
        <Button onClick={() => setIsAdding(true)} disabled={isAdding}>
          <Plus className="mr-2 h-4 w-4" />
          Add Category
        </Button>
      </div>

      {isLoading ? (
        <div className="flex justify-center py-12">
          <CircleNotch className="h-6 w-6 animate-spin" />
        </div>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Slug</TableHead>
              <TableHead className="w-[100px]">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isAdding && (
              <TableRow>
                <TableCell>
                  <Input
                    value={newName}
                    onChange={(e) => {
                      setNewName(e.target.value);
                      setNewSlug(slugify(e.target.value));
                    }}
                    placeholder="Category name"
                    autoFocus
                  />
                </TableCell>
                <TableCell>
                  <Input value={newSlug} onChange={(e) => setNewSlug(e.target.value)} placeholder="slug" />
                </TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <Button variant="ghost" size="icon" className="h-8 w-8" onClick={handleAdd}>
                      <Check className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => setIsAdding(false)}>
                      <X className="h-4 w-4" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            )}
            {items.map((cat) => (
              <TableRow key={`${rowKeyPrefix}-${cat.id}`}>
                <TableCell>
                  {editingId === cat.id ? (
                    <Input value={editName} onChange={(e) => setEditName(e.target.value)} />
                  ) : (
                    cat.name
                  )}
                </TableCell>
                <TableCell>
                  {editingId === cat.id ? (
                    <Input value={editSlug} onChange={(e) => setEditSlug(e.target.value)} />
                  ) : (
                    <span className="text-zinc-500">{cat.slug}</span>
                  )}
                </TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {editingId === cat.id ? (
                      <>
                        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => handleUpdate(cat.id)}>
                          <Check className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => setEditingId(null)}>
                          <X className="h-4 w-4" />
                        </Button>
                      </>
                    ) : (
                      <>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8"
                          onClick={() => {
                            setEditingId(cat.id);
                            setEditName(cat.name);
                            setEditSlug(cat.slug);
                          }}
                        >
                          <PencilSimple className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8 text-red-500"
                          onClick={() => handleDelete(cat.id)}
                        >
                          <Trash className="h-4 w-4" />
                        </Button>
                      </>
                    )}
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </div>
  );
}
```

### 19. Create Media Management Page (`src/app/admin/content/media/page.tsx`)

This page wraps the existing storage-ui `FileManager` component:

```tsx
import { StorageProvider } from "@/components/storage/storage-provider";
import { FileManager } from "@/components/storage/file-manager";

export default function MediaPage() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Media Library</h1>
      <StorageProvider>
        <FileManager accept={["images", "video"]} />
      </StorageProvider>
    </div>
  );
}
```

### 20. Update Proxy for CMS Admin Routes

The auth skill's `proxy.ts` should already protect `/admin` routes. Verify that `/admin` is in the `protectedRoutes` and `adminRoutes` arrays:

```typescript
const protectedRoutes = ["/dashboard", "/settings", "/admin", "/account"];
const adminRoutes = ["/admin"];
```

If `/admin` is already listed (it is in the default auth skill), no changes needed.

## Database Migration

After creating all files, push the schema to your database:

```bash
# Push schema changes
bunx drizzle-kit push

# Or generate and run a migration
bunx drizzle-kit generate
bunx drizzle-kit migrate
```

## Testing

1. Start the dev server: `bun dev`
2. Sign in as an admin user at `/sign-in`
3. Navigate to `/admin/content`
4. Create a category at `/admin/content/categories`
5. Create a post at `/admin/content/posts/new`
6. Upload media at `/admin/content/media`
7. Create a page at `/admin/content/pages/new`
8. Verify posts list, page list, edit flows

## Troubleshooting

### Admin pages redirect to sign-in

The proxy requires authentication and admin role. Make sure your user has `role: "admin"` in the database.

### Tiptap editor not rendering

Ensure all Tiptap packages are installed. The editor is client-side only (`"use client"` directive required).

### Media picker shows no files

Verify the storage skill is set up and `/api/storage` returns files. Check that Docker storage service is running.

### Database errors on post/page creation

Run `bunx drizzle-kit push` to sync the CMS schema to your database.

### Categories not loading in post form

The post form fetches categories from `/api/cms/categories`. Verify the API route exists and returns data.

## Acceptance Criteria

- [ ] CMS database schema created with posts, pages, categories tables
- [ ] CRUD API routes for posts, pages, categories (admin-protected)
- [ ] Tiptap rich text editor with toolbar (bold, italic, headings, lists, images, links)
- [ ] Media picker integrated with storage skill
- [ ] Post form with title, slug, content, excerpt, featured media, categories, status
- [ ] Page form with title, slug, content, meta fields, status
- [ ] Admin layout with sidebar navigation
- [ ] Content dashboard with stats
- [ ] Posts and pages list with edit/delete actions
- [ ] Categories inline management
- [ ] Media library page using storage-ui
