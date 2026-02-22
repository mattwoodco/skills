---
name: rss
description: Setup RSS, Atom, and JSON Feed generation for Next.js with Payload CMS integration. Use this skill when the user says "setup rss", "add rss feed", "setup atom feed", "add feed", "rss integration", or "syndication feeds".
author: "@mattwoodco"
version: 1.1.0
created: 2026-01-12
validated: 2026-02-17
dependencies: [cms, env-config]
---

# RSS Feed Integration

Sets up RSS 2.0, Atom, and JSON Feed generation for Next.js App Router with Payload CMS integration, SEO-optimized feed discovery, and content team-friendly debug tools.

## Quick Start

```bash
# 1. Install feed generation package
bun add feedsmith

# 2. Start dev server
bun dev

# 3. Test feeds
open http://localhost:3000/feed.xml
open http://localhost:3000/feed.atom
open http://localhost:3000/feed.json

# 4. Debug page
open http://localhost:3000/debug/rss
```

## What Gets Created

### Route Handlers

1. **`src/app/feed.xml/route.ts`** - RSS 2.0 feed (most compatible)
2. **`src/app/feed.atom/route.ts`** - Atom feed (better semantics)
3. **`src/app/feed.json/route.ts`** - JSON Feed (modern, easy parsing)

### Library Files

4. **`src/lib/rss/generate.ts`** - Feed generation utilities
5. **`src/lib/rss/types.ts`** - TypeScript types for feed items
6. **`src/lib/rss/fetch-content.ts`** - CMS content fetching

### Debug & Testing

7. **`src/app/debug/rss/page.tsx`** - Feed preview and validation
8. **`e2e/specs/rss.spec.ts`** - Playwright validation tests

## Installation

```bash
bun add feedsmith
```

## Environment Variables

Add to `.env.local`:

```env
# Site Configuration (required for absolute URLs)
NEXT_PUBLIC_APP_URL=http://localhost:3000

# Feed Metadata
NEXT_PUBLIC_SITE_NAME="Your Site Name"
NEXT_PUBLIC_SITE_DESCRIPTION="Your site description"
```

Add to `src/env.ts`:

```typescript
client: {
  NEXT_PUBLIC_APP_URL: z.string().url(),
  NEXT_PUBLIC_SITE_NAME: z.string().optional(),
  NEXT_PUBLIC_SITE_DESCRIPTION: z.string().optional(),
}
```

## Prerequisites

### TypeScript Path Alias

Add `@payload-config` to `tsconfig.json` paths (required for Payload CMS imports):

```json
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./src/*"],
      "@payload-config": ["./src/payload.config.ts"]
    }
  },
  "exclude": ["node_modules", "e2e"]
}
```

## Setup Steps

### 1. Create Feed Types (`src/lib/rss/types.ts`)

```typescript
export type FeedItem = {
  id: string;
  title: string;
  slug: string;
  description: string;
  content?: string;
  publishedAt: Date;
  updatedAt?: Date;
  author?: {
    name: string;
    email?: string;
  };
  categories?: string[];
  featuredImage?: {
    url: string;
    alt?: string;
  };
};

export type FeedConfig = {
  title: string;
  description: string;
  siteUrl: string;
  feedUrl: string;
  language?: string;
  copyright?: string;
  managingEditor?: string;
  webMaster?: string;
  ttl?: number;
  image?: {
    url: string;
    title: string;
    link: string;
  };
};
```

### 2. Create Content Fetcher (`src/lib/rss/fetch-content.ts`)

```typescript
import { getPayload } from "payload";
import config from "@payload-config";
import type { FeedItem } from "./types";

/**
 * Fetch published posts from Payload CMS
 * Falls back to empty array if Payload is not configured
 */
export async function fetchFeedItems(limit = 50): Promise<FeedItem[]> {
  try {
    const payload = await getPayload({ config });

    const posts = await payload.find({
      collection: "posts",
      where: {
        status: { equals: "published" },
      },
      sort: "-publishedAt",
      limit,
      depth: 2,
    });

    return posts.docs.map((post) => ({
      id: String(post.id),
      title: post.title,
      slug: post.slug,
      description: post.excerpt ?? "",
      content: extractTextFromLexical(post.content),
      publishedAt: new Date(post.publishedAt ?? post.createdAt),
      updatedAt: new Date(post.updatedAt),
      author:
        typeof post.author !== "string" && typeof post.author !== "number" && post.author
          ? {
              name: post.author.name ?? post.author.email,
              email: post.author.email,
            }
          : undefined,
      categories:
        post.categories?.map((cat: string | number | { name: string }) =>
          typeof cat === "string" || typeof cat === "number" ? String(cat) : cat.name
        ) ?? [],
      featuredImage:
        typeof post.featuredImage !== "string" && typeof post.featuredImage !== "number" && post.featuredImage
          ? {
              url: post.featuredImage.url ?? "",
              alt: post.featuredImage.alt,
            }
          : undefined,
    }));
  } catch {
    // Payload not configured or collection doesn't exist
    console.warn("RSS: Could not fetch from Payload CMS, returning empty feed");
    return [];
  }
}

/**
 * Extract plain text from Lexical rich text content
 */
function extractTextFromLexical(content: unknown): string {
  if (!content || typeof content !== "object") return "";

  const root = content as { root?: { children?: unknown[] } };
  if (!root.root?.children) return "";

  function extractText(nodes: unknown[]): string {
    return nodes
      .map((node) => {
        const n = node as { text?: string; children?: unknown[] };
        if (n.text) return n.text;
        if (n.children) return extractText(n.children);
        return "";
      })
      .join(" ");
  }

  return extractText(root.root.children).trim();
}
```

### 3. Create Feed Generator (`src/lib/rss/generate.ts`)

```typescript
import {
  generateRssFeed,
  generateAtomFeed,
  generateJsonFeed,
} from "feedsmith";
import type { FeedItem, FeedConfig } from "./types";
import { env } from "@/env";

const DEFAULT_CONFIG: FeedConfig = {
  title: env.NEXT_PUBLIC_SITE_NAME ?? "My Site",
  description: env.NEXT_PUBLIC_SITE_DESCRIPTION ?? "Latest updates from our site",
  siteUrl: env.NEXT_PUBLIC_APP_URL,
  feedUrl: `${env.NEXT_PUBLIC_APP_URL}/feed.xml`,
  language: "en-US",
  copyright: `Copyright ${new Date().getFullYear()}`,
  ttl: 60,
};

/**
 * Generate RSS 2.0 feed
 */
export function generateRss(items: FeedItem[], config?: Partial<FeedConfig>): string {
  const feedConfig = { ...DEFAULT_CONFIG, ...config };
  const siteUrl = feedConfig.siteUrl;

  return generateRssFeed({
    title: feedConfig.title,
    link: siteUrl,
    description: feedConfig.description,
    language: feedConfig.language,
    copyright: feedConfig.copyright,
    managingEditor: feedConfig.managingEditor,
    webMaster: feedConfig.webMaster,
    pubDate: new Date(),
    lastBuildDate: new Date(),
    ttl: feedConfig.ttl,
    image: feedConfig.image,
    items: items.map((item) => ({
      title: item.title,
      link: `${siteUrl}/blog/${item.slug}`,
      description: item.description,
      author: item.author?.email
        ? `${item.author.email} (${item.author.name})`
        : item.author?.name,
      guid: `${siteUrl}/blog/${item.slug}`,
      pubDate: item.publishedAt,
      categories: item.categories?.map((name) => ({ name })),
      enclosure: item.featuredImage?.url
        ? {
            url: item.featuredImage.url.startsWith("http")
              ? item.featuredImage.url
              : `${siteUrl}${item.featuredImage.url}`,
            type: "image/jpeg",
            length: 0,
          }
        : undefined,
    })),
  });
}

/**
 * Generate Atom feed
 */
export function generateAtom(items: FeedItem[], config?: Partial<FeedConfig>): string {
  const feedConfig = { ...DEFAULT_CONFIG, ...config };
  const siteUrl = feedConfig.siteUrl;

  return generateAtomFeed({
    id: `${siteUrl}/feed.atom`,
    title: feedConfig.title,
    subtitle: feedConfig.description,
    updated: new Date(),
    links: [
      { href: siteUrl },
      { href: `${siteUrl}/feed.atom`, rel: "self", type: "application/atom+xml" },
    ],
    rights: feedConfig.copyright,
    entries: items.map((item) => ({
      id: `${siteUrl}/blog/${item.slug}`,
      title: item.title,
      updated: item.updatedAt ?? item.publishedAt,
      published: item.publishedAt,
      summary: item.description,
      content: item.content,
      links: [{ href: `${siteUrl}/blog/${item.slug}` }],
      authors: item.author
        ? [{ name: item.author.name, email: item.author.email }]
        : [],
      categories: item.categories?.map((term) => ({ term })),
    })),
  });
}

/**
 * Generate JSON Feed
 */
export function generateJson(items: FeedItem[], config?: Partial<FeedConfig>): string {
  const feedConfig = { ...DEFAULT_CONFIG, ...config };
  const siteUrl = feedConfig.siteUrl;

  return generateJsonFeed({
    title: feedConfig.title,
    home_page_url: siteUrl,
    feed_url: `${siteUrl}/feed.json`,
    description: feedConfig.description,
    language: feedConfig.language,
    items: items.map((item) => ({
      id: `${siteUrl}/blog/${item.slug}`,
      url: `${siteUrl}/blog/${item.slug}`,
      title: item.title,
      content_text: item.description,
      content_html: item.content,
      date_published: item.publishedAt,
      date_modified: item.updatedAt,
      authors: item.author ? [{ name: item.author.name }] : [],
      tags: item.categories,
      image: item.featuredImage?.url?.startsWith("http")
        ? item.featuredImage.url
        : item.featuredImage?.url
          ? `${siteUrl}${item.featuredImage.url}`
          : undefined,
    })),
  });
}
```

### 4. Create RSS Route Handler (`src/app/feed.xml/route.ts`)

```typescript
import { generateRssFeed } from "feedsmith";

export const dynamic = "force-dynamic";

// Use process.env directly to avoid @/env validation blocking
const getSiteUrl = () => process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";
const getSiteName = () => process.env.NEXT_PUBLIC_SITE_NAME ?? "My Site";
const getSiteDescription = () => process.env.NEXT_PUBLIC_SITE_DESCRIPTION ?? "Latest updates";

export async function GET(): Promise<Response> {
  // Dynamic import to avoid blocking if Payload isn't ready
  let items: Array<{ title: string; slug: string; description: string; publishedAt: Date; author?: { name: string; email?: string }; categories?: string[] }> = [];

  try {
    const { getPayload } = await import("payload");
    const config = await import("@payload-config").then((m) => m.default);
    const payload = await getPayload({ config });

    const posts = await payload.find({
      collection: "posts",
      where: { status: { equals: "published" } },
      sort: "-publishedAt",
      limit: 50,
    });

    items = posts.docs.map((post) => ({
      title: post.title,
      slug: post.slug,
      description: post.excerpt ?? "",
      publishedAt: new Date(post.publishedAt ?? post.createdAt),
      author: typeof post.author !== "string" && post.author
        ? { name: post.author.name ?? post.author.email, email: post.author.email }
        : undefined,
      categories: post.categories?.map((cat: string | { name: string }) =>
        typeof cat === "string" ? cat : cat.name
      ),
    }));
  } catch {
    console.warn("RSS: Payload not available, returning empty feed");
  }

  const siteUrl = getSiteUrl();

  const rss = generateRssFeed({
    title: getSiteName(),
    link: siteUrl,
    description: getSiteDescription(),
    language: "en-US",
    copyright: `Copyright ${new Date().getFullYear()}`,
    pubDate: new Date(),
    lastBuildDate: new Date(),
    ttl: 60,
    items: items.map((item) => ({
      title: item.title,
      link: `${siteUrl}/blog/${item.slug}`,
      description: item.description,
      author: item.author?.email ? `${item.author.email} (${item.author.name})` : item.author?.name,
      // IMPORTANT: guid must be an object, not a string
      guid: { value: `${siteUrl}/blog/${item.slug}`, isPermaLink: true },
      pubDate: item.publishedAt,
      categories: item.categories?.map((name) => ({ name })),
    })),
  });

  return new Response(rss, {
    headers: {
      "Content-Type": "application/rss+xml; charset=utf-8",
      "Cache-Control": "public, max-age=3600, s-maxage=3600",
    },
  });
}
```

### 5. Create Atom Route Handler (`src/app/feed.atom/route.ts`)

```typescript
import { generateAtomFeed } from "feedsmith";

export const dynamic = "force-dynamic";

export async function GET(): Promise<Response> {
  const siteUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";

  let items: Array<{ title: string; slug: string; description: string; publishedAt: Date; author?: { name: string; email?: string }; categories?: string[] }> = [];

  try {
    const { getPayload } = await import("payload");
    const config = await import("@payload-config").then((m) => m.default);
    const payload = await getPayload({ config });

    const posts = await payload.find({
      collection: "posts",
      where: { status: { equals: "published" } },
      sort: "-publishedAt",
      limit: 50,
    });

    items = posts.docs.map((post) => ({
      title: post.title,
      slug: post.slug,
      description: post.excerpt ?? "",
      publishedAt: new Date(post.publishedAt ?? post.createdAt),
      author: typeof post.author !== "string" && typeof post.author !== "number" && post.author
        ? { name: post.author.name ?? post.author.email, email: post.author.email }
        : undefined,
      categories: post.categories?.map((cat: string | number | { name: string }) =>
        typeof cat === "string" || typeof cat === "number" ? String(cat) : cat.name
      ),
    }));
  } catch {
    console.warn("RSS: Payload not available, returning empty feed");
  }

  const atom = generateAtomFeed({
    id: `${siteUrl}/feed.atom`,
    title: process.env.NEXT_PUBLIC_SITE_NAME ?? "My Site",
    subtitle: process.env.NEXT_PUBLIC_SITE_DESCRIPTION ?? "Latest updates",
    updated: new Date(),
    links: [
      { href: siteUrl },
      { href: `${siteUrl}/feed.atom`, rel: "self", type: "application/atom+xml" },
    ],
    rights: `Copyright ${new Date().getFullYear()}`,
    entries: items.map((item) => ({
      id: `${siteUrl}/blog/${item.slug}`,
      title: item.title,
      updated: item.publishedAt,
      published: item.publishedAt,
      summary: item.description,
      links: [{ href: `${siteUrl}/blog/${item.slug}` }],
      authors: item.author ? [{ name: item.author.name, email: item.author.email }] : [],
      categories: item.categories?.map((term) => ({ term })),
    })),
  });

  return new Response(atom, {
    headers: {
      "Content-Type": "application/atom+xml; charset=utf-8",
      "Cache-Control": "public, max-age=3600, s-maxage=3600",
    },
  });
}
```

### 6. Create JSON Feed Route Handler (`src/app/feed.json/route.ts`)

```typescript
import { generateJsonFeed } from "feedsmith";

export const dynamic = "force-dynamic";

export async function GET(): Promise<Response> {
  const siteUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";

  let items: Array<{ title: string; slug: string; description: string; publishedAt: Date; author?: { name: string }; categories?: string[] }> = [];

  try {
    const { getPayload } = await import("payload");
    const config = await import("@payload-config").then((m) => m.default);
    const payload = await getPayload({ config });

    const posts = await payload.find({
      collection: "posts",
      where: { status: { equals: "published" } },
      sort: "-publishedAt",
      limit: 50,
    });

    items = posts.docs.map((post) => ({
      title: post.title,
      slug: post.slug,
      description: post.excerpt ?? "",
      publishedAt: new Date(post.publishedAt ?? post.createdAt),
      author: typeof post.author !== "string" && typeof post.author !== "number" && post.author
        ? { name: post.author.name ?? post.author.email }
        : undefined,
      categories: post.categories?.map((cat: string | number | { name: string }) =>
        typeof cat === "string" || typeof cat === "number" ? String(cat) : cat.name
      ),
    }));
  } catch {
    console.warn("RSS: Payload not available, returning empty feed");
  }

  const feed = generateJsonFeed({
    title: process.env.NEXT_PUBLIC_SITE_NAME ?? "My Site",
    home_page_url: siteUrl,
    feed_url: `${siteUrl}/feed.json`,
    description: process.env.NEXT_PUBLIC_SITE_DESCRIPTION ?? "Latest updates",
    language: "en-US",
    items: items.map((item) => ({
      id: `${siteUrl}/blog/${item.slug}`,
      url: `${siteUrl}/blog/${item.slug}`,
      title: item.title,
      content_text: item.description,
      date_published: item.publishedAt,
      authors: item.author ? [{ name: item.author.name }] : [],
      tags: item.categories,
    })),
  });

  // IMPORTANT: generateJsonFeed returns object, must stringify
  const feedString = typeof feed === "string" ? feed : JSON.stringify(feed, null, 2);

  return new Response(feedString, {
    headers: {
      "Content-Type": "application/feed+json; charset=utf-8",
      "Cache-Control": "public, max-age=3600, s-maxage=3600",
    },
  });
}
```

### 7. Add Feed Discovery to Layout

Update `src/app/layout.tsx`:

```typescript
import type { Metadata } from "next";
import { env } from "@/env";

export const metadata: Metadata = {
  // ... existing metadata
  alternates: {
    types: {
      "application/rss+xml": `${env.NEXT_PUBLIC_APP_URL}/feed.xml`,
      "application/atom+xml": `${env.NEXT_PUBLIC_APP_URL}/feed.atom`,
      "application/feed+json": `${env.NEXT_PUBLIC_APP_URL}/feed.json`,
    },
  },
};
```

### 8. Create Debug Page (`src/app/debug/rss/page.tsx`)

```tsx
import { Suspense } from "react";
import { fetchFeedItems } from "@/lib/rss/fetch-content";
import { generateRss, generateAtom, generateJson } from "@/lib/rss/generate";
import { env } from "@/env";

export const dynamic = "force-dynamic";

async function FeedDebugContent() {
  const items = await fetchFeedItems(10);
  const rssPreview = generateRss(items.slice(0, 3));
  const atomPreview = generateAtom(items.slice(0, 3));
  const jsonPreview = generateJson(items.slice(0, 3));

  return (
    <div className="space-y-8">
      {/* Feed URLs */}
      <section className="rounded-lg border p-6">
        <h2 className="mb-4 font-semibold text-xl">Feed URLs</h2>
        <div className="space-y-2">
          <FeedLink
            label="RSS 2.0"
            href="/feed.xml"
            type="application/rss+xml"
          />
          <FeedLink
            label="Atom"
            href="/feed.atom"
            type="application/atom+xml"
          />
          <FeedLink
            label="JSON Feed"
            href="/feed.json"
            type="application/feed+json"
          />
        </div>
      </section>

      {/* Stats */}
      <section className="rounded-lg border p-6">
        <h2 className="mb-4 font-semibold text-xl">Feed Statistics</h2>
        <dl className="grid grid-cols-2 gap-4 md:grid-cols-4">
          <Stat label="Total Items" value={items.length} />
          <Stat
            label="Latest Post"
            value={
              items[0]
                ? new Date(items[0].publishedAt).toLocaleDateString()
                : "N/A"
            }
          />
          <Stat
            label="With Images"
            value={items.filter((i) => i.featuredImage).length}
          />
          <Stat
            label="With Authors"
            value={items.filter((i) => i.author).length}
          />
        </dl>
      </section>

      {/* Items Preview */}
      <section className="rounded-lg border p-6">
        <h2 className="mb-4 font-semibold text-xl">Recent Items</h2>
        {items.length === 0 ? (
          <p className="text-muted-foreground">
            No published posts found. Create posts in Payload CMS with status
            &quot;published&quot;.
          </p>
        ) : (
          <div className="space-y-4">
            {items.slice(0, 5).map((item) => (
              <div key={item.id} className="border-b pb-4 last:border-0">
                <h3 className="font-medium">{item.title}</h3>
                <p className="mt-1 text-muted-foreground text-sm">
                  {item.description.slice(0, 150)}
                  {item.description.length > 150 ? "..." : ""}
                </p>
                <div className="mt-2 flex gap-4 text-muted-foreground text-xs">
                  <span>
                    {new Date(item.publishedAt).toLocaleDateString()}
                  </span>
                  {item.author && <span>by {item.author.name}</span>}
                  {item.categories && item.categories.length > 0 && (
                    <span>{item.categories.join(", ")}</span>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* RSS Preview */}
      <FeedPreview title="RSS 2.0 Preview" content={rssPreview} language="xml" />

      {/* Atom Preview */}
      <FeedPreview title="Atom Preview" content={atomPreview} language="xml" />

      {/* JSON Feed Preview */}
      <FeedPreview
        title="JSON Feed Preview"
        content={jsonPreview}
        language="json"
      />

      {/* Validation Links */}
      <section className="rounded-lg border p-6">
        <h2 className="mb-4 font-semibold text-xl">Validate Feeds</h2>
        <div className="flex flex-wrap gap-4">
          <a
            href={`https://validator.w3.org/feed/check.cgi?url=${encodeURIComponent(`${env.NEXT_PUBLIC_APP_URL}/feed.xml`)}`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-blue-600 hover:underline"
          >
            W3C RSS Validator
          </a>
          <a
            href={`https://validator.w3.org/feed/check.cgi?url=${encodeURIComponent(`${env.NEXT_PUBLIC_APP_URL}/feed.atom`)}`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-blue-600 hover:underline"
          >
            W3C Atom Validator
          </a>
        </div>
      </section>
    </div>
  );
}

function FeedLink({
  label,
  href,
  type,
}: {
  label: string;
  href: string;
  type: string;
}) {
  return (
    <div className="flex items-center justify-between rounded bg-muted/50 p-3">
      <div>
        <span className="font-medium">{label}</span>
        <span className="ml-2 text-muted-foreground text-sm">({type})</span>
      </div>
      <div className="flex gap-2">
        <a
          href={href}
          target="_blank"
          rel="noopener noreferrer"
          className="text-blue-600 hover:underline"
        >
          View
        </a>
        <button
          type="button"
          onClick={() => {
            navigator.clipboard.writeText(window.location.origin + href);
          }}
          className="text-muted-foreground hover:text-foreground"
        >
          Copy
        </button>
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div>
      <dt className="text-muted-foreground text-sm">{label}</dt>
      <dd className="font-semibold text-2xl">{value}</dd>
    </div>
  );
}

function FeedPreview({
  title,
  content,
  language,
}: {
  title: string;
  content: string;
  language: "xml" | "json";
}) {
  const formatted =
    language === "json" ? JSON.stringify(JSON.parse(content), null, 2) : content;

  return (
    <section className="rounded-lg border p-6">
      <h2 className="mb-4 font-semibold text-xl">{title}</h2>
      <pre className="max-h-96 overflow-auto rounded bg-muted p-4 font-mono text-xs">
        {formatted.slice(0, 3000)}
        {formatted.length > 3000 ? "\n... (truncated)" : ""}
      </pre>
    </section>
  );
}

export default function RssDebugPage() {
  return (
    <div className="container mx-auto max-w-4xl py-8">
      <header className="mb-8">
        <h1 className="font-bold text-3xl">RSS Feed Debug</h1>
        <p className="mt-2 text-muted-foreground">
          Preview and validate your RSS, Atom, and JSON feeds
        </p>
      </header>

      <Suspense
        fallback={
          <div className="flex items-center justify-center py-12">
            <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
          </div>
        }
      >
        <FeedDebugContent />
      </Suspense>
    </div>
  );
}
```

## Elysia API Alternative

For projects using Elysia for API routes, add RSS endpoints:

```typescript
// In src/app/api/[[...slugs]]/route.ts
import { Elysia } from "elysia";
import { generateRss, generateAtom, generateJson } from "@/lib/rss/generate";
import { fetchFeedItems } from "@/lib/rss/fetch-content";

const app = new Elysia({ prefix: "/api" })
  // ... existing routes

  .get("/rss", async ({ set }) => {
    const items = await fetchFeedItems(50);
    set.headers["Content-Type"] = "application/rss+xml; charset=utf-8";
    return generateRss(items);
  })

  .get("/atom", async ({ set }) => {
    const items = await fetchFeedItems(50);
    set.headers["Content-Type"] = "application/atom+xml; charset=utf-8";
    return generateAtom(items);
  })

  .get("/feed.json", async ({ set }) => {
    const items = await fetchFeedItems(50);
    set.headers["Content-Type"] = "application/feed+json; charset=utf-8";
    return generateJson(items);
  });
```

## SEO Best Practices

### 1. Feed Discovery Meta Tags

Already configured in layout metadata. This allows browsers and feed readers to auto-discover your feeds.

### 2. Sitemap Integration

Add feed URLs to your sitemap for better crawling:

```typescript
// src/app/sitemap.ts
import type { MetadataRoute } from "next";
import { env } from "@/env";

export default function sitemap(): MetadataRoute.Sitemap {
  const baseUrl = env.NEXT_PUBLIC_APP_URL;

  return [
    // ... other pages
    {
      url: `${baseUrl}/feed.xml`,
      changeFrequency: "hourly",
      priority: 0.3,
    },
  ];
}
```

### 3. robots.txt

Allow feed crawling:

```typescript
// src/app/robots.ts
import type { MetadataRoute } from "next";
import { env } from "@/env";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: ["/", "/feed.xml", "/feed.atom", "/feed.json"],
    },
    sitemap: `${env.NEXT_PUBLIC_APP_URL}/sitemap.xml`,
  };
}
```

### 4. Cache Headers

Route handlers include proper cache headers:
- `Cache-Control: public, max-age=3600, s-maxage=3600` for 1-hour caching
- Vercel Edge Cache automatically respected

### 5. Canonical URLs

Each feed item includes proper canonical URLs (`guid` in RSS, `id` in Atom).

## Playwright Testing

Create `e2e/specs/rss.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";

test.describe("RSS Feeds", () => {
  test("RSS 2.0 feed returns valid XML", async ({ request }) => {
    const response = await request.get("/feed.xml");

    expect(response.ok()).toBeTruthy();
    expect(response.headers()["content-type"]).toContain("application/rss+xml");

    const body = await response.text();
    expect(body).toContain('<?xml version="1.0"');
    expect(body).toContain("<rss");
    expect(body).toContain("<channel>");
  });

  test("Atom feed returns valid XML", async ({ request }) => {
    const response = await request.get("/feed.atom");

    expect(response.ok()).toBeTruthy();
    expect(response.headers()["content-type"]).toContain("application/atom+xml");

    const body = await response.text();
    expect(body).toContain('<?xml version="1.0"');
    expect(body).toContain("<feed");
  });

  test("JSON Feed returns valid JSON", async ({ request }) => {
    const response = await request.get("/feed.json");

    expect(response.ok()).toBeTruthy();
    expect(response.headers()["content-type"]).toContain("application/feed+json");

    const body = await response.json();
    expect(body.title).toBeTruthy();
    expect(Array.isArray(body.items)).toBeTruthy();
  });

  test("Debug page loads", async ({ page }) => {
    await page.goto("/debug/rss");

    await expect(page.getByRole("heading", { name: /RSS Feed Debug/i })).toBeVisible();
    await expect(page.getByText("Feed URLs")).toBeVisible();
  });

  test("Feed discovery meta tags present", async ({ page }) => {
    await page.goto("/");

    const rssLink = page.locator('link[type="application/rss+xml"]');
    const atomLink = page.locator('link[type="application/atom+xml"]');

    await expect(rssLink).toHaveAttribute("href", /feed\.xml/);
    await expect(atomLink).toHaveAttribute("href", /feed\.atom/);
  });
});
```

## Acceptance Criteria

- [x] RSS 2.0 feed accessible at `/feed.xml`
- [x] Atom feed accessible at `/feed.atom`
- [x] JSON Feed accessible at `/feed.json`
- [x] Feeds populate from Payload CMS posts
- [x] Feed discovery meta tags in layout
- [x] Proper Content-Type headers
- [x] Cache headers for CDN optimization
- [x] Debug page for content team validation
- [x] Playwright tests pass
- [x] W3C Feed Validator compliant

## Testing

1. Start the dev server: `bun dev`
2. Navigate to `http://localhost:3000/feed.xml`
3. Check XML structure is valid
4. Navigate to `http://localhost:3000/debug/rss`
5. Verify feed statistics and preview
6. Run Playwright tests: `bunx playwright test e2e/specs/rss.spec.ts`
7. Validate at W3C: https://validator.w3.org/feed/

## Troubleshooting

### Empty feeds

Check that:
1. Posts collection exists in Payload CMS
2. Posts have `status: "published"`
3. Posts have `publishedAt` date set

### Feed not updating

1. Check `revalidate` setting in route handlers
2. Clear Vercel cache if deployed
3. Check ISR revalidation in Next.js

### Invalid XML errors

1. Ensure content doesn't contain unescaped XML characters
2. Check `extractTextFromLexical` handles your content structure
3. Validate with W3C before deploying

### Route handler timeouts

If feed routes timeout or hang:

1. **Avoid `@/env` import in route handlers** - The t3-env validation can block if DATABASE_URL or other required vars aren't ready. Use `process.env` directly with fallbacks:
   ```typescript
   // ❌ Don't use - can block on env validation
   import { env } from "@/env";
   const siteUrl = env.NEXT_PUBLIC_APP_URL;

   // ✅ Use direct access with fallback
   const siteUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";
   ```

2. **Use dynamic imports for Payload** - Prevents blocking if database isn't available:
   ```typescript
   const { getPayload } = await import("payload");
   const config = await import("@payload-config").then((m) => m.default);
   ```

### Feedsmith type errors

**RSS guid format**: The `guid` field requires an object, not a string:
```typescript
// ❌ Incorrect - TypeScript error
guid: `${siteUrl}/blog/${item.slug}`,

// ✅ Correct - object format
guid: {
  value: `${siteUrl}/blog/${item.slug}`,
  isPermaLink: true,
},
```

**Atom content is a plain string**: feedsmith's Atom `Entry.content` is typed as `Text` (alias for `string`), not an object:
```typescript
// ❌ Incorrect - TypeScript error
content: { type: "html", value: item.content }

// ✅ Correct - pass string directly
content: item.content,
```

**JSON Feed dates must be Date objects**: `generateJsonFeed` types `date_published`/`date_modified` as `Date`, not ISO strings:
```typescript
// ❌ Incorrect - TypeScript error
date_published: item.publishedAt.toISOString(),

// ✅ Correct - pass Date object (feedsmith handles serialization)
date_published: item.publishedAt,
```

**JSON Feed returns object**: `generateJsonFeed` returns an object, not a string. Stringify it:
```typescript
const feed = generateJsonFeed({ ... });

// ❌ Incorrect - returns [object Object]
return new Response(feed as string, { ... });

// ✅ Correct - stringify the object
const feedString = typeof feed === "string" ? feed : JSON.stringify(feed, null, 2);
return new Response(feedString, { ... });
```

**JSON Feed `version` is not a valid property**: feedsmith's `Json.Feed<TDate>` type does not include a `version` field — the library adds it automatically:
```typescript
// ❌ Incorrect - TypeScript error "version does not exist in type Feed<Date>"
const feed = generateJsonFeed({ version: "https://jsonfeed.org/version/1.1", title: ... });

// ✅ Correct - omit version, feedsmith adds it
const feed = generateJsonFeed({ title: ... });
```

### Payload CMS id type

Payload returns `id` as a number, but feed items need strings:
```typescript
// ❌ Type error - number vs string
id: post.id,

// ✅ Convert to string
id: String(post.id),
```

### Playwright test errors

If Playwright tests fail with tsconfig errors, exclude the e2e folder:
```json
// tsconfig.json
{
  "exclude": ["node_modules", "e2e"]
}
```

For auth-protected debug pages, use empty storage state:
```typescript
test.use({ storageState: { cookies: [], origins: [] } });
```

**Strict mode violations**: When text appears multiple times, use exact matching:
```typescript
// ❌ Fails if "RSS 2.0" appears in "RSS 2.0" and "RSS 2.0 Preview"
await expect(page.getByText("RSS 2.0")).toBeVisible();

// ✅ Matches only exact text
await expect(page.getByText("RSS 2.0", { exact: true })).toBeVisible();
```

**Client-side loading**: Debug page uses client-side fetching. Add longer timeouts:
```typescript
await expect(page.getByText("Feed URLs")).toBeVisible({ timeout: 15000 });
```

## Resources

- [RSS 2.0 Specification](https://www.rssboard.org/rss-specification)
- [Atom Syndication Format](https://datatracker.ietf.org/doc/html/rfc4287)
- [JSON Feed Specification](https://www.jsonfeed.org/version/1.1/)
- [Feedsmith Documentation](https://github.com/macieklamberski/feedsmith)
- [Google Best Practices for Feeds](https://developers.google.com/search/blog/2014/10/best-practices-for-xml-sitemaps-rssatom)
- [W3C Feed Validator](https://validator.w3.org/feed/)
