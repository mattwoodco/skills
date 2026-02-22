---
name: add-seo
description: Setup comprehensive SEO for a Next.js project using built-in metadata APIs. Use when user says "setup seo", "add seo", "configure metadata", "add sitemap", "add open graph", or "improve seo".
author: "@mattwoodco"
version: 1.1.0
created: 2026-02-13
updated: 2026-02-13
validated: 2026-02-13 (Next.js 16.1.6, Biome 2.2.0)
dependencies: [create-next]
---

# Add SEO

Adds comprehensive SEO to a Next.js project using **zero external dependencies**. Uses Next.js built-in metadata API, file conventions, and `next/og` for dynamic Open Graph images.

## What Gets Created

| File | Purpose |
|------|---------|
| `lib/metadata.ts` | Shared metadata defaults and `createMetadata` helper |
| `app/sitemap.ts` | Dynamic sitemap (auto-served at `/sitemap.xml`) |
| `app/robots.ts` | Robots.txt config (auto-served at `/robots.txt`) |
| `app/opengraph-image.tsx` | Dynamic OG image generation |
| `lib/structured-data.tsx` | Reusable JSON-LD component |

## Prerequisites

- Next.js 15+ project (App Router)
- TypeScript configured

## Installation

No packages required. Everything uses Next.js built-in APIs.

Optionally, for type-safe JSON-LD schemas:

```bash
bun add -D schema-dts
```

## Setup Steps

### 1. Create Shared Metadata Defaults

Create `lib/metadata.ts`:

```ts
import type { Metadata } from "next";

const SITE_NAME = "My App";
const SITE_DESCRIPTION = "A Next.js application";
const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "https://example.com";

export const siteConfig = {
  name: SITE_NAME,
  description: SITE_DESCRIPTION,
  url: SITE_URL,
} as const;

export const sharedMetadata: Metadata = {
  metadataBase: new URL(siteConfig.url),
  title: {
    default: siteConfig.name,
    template: `%s | ${siteConfig.name}`,
  },
  description: siteConfig.description,
  applicationName: siteConfig.name,
  authors: [{ name: siteConfig.name }],
  formatDetection: {
    telephone: false,
  },
  openGraph: {
    type: "website",
    siteName: siteConfig.name,
    title: {
      default: siteConfig.name,
      template: `%s | ${siteConfig.name}`,
    },
    description: siteConfig.description,
    url: siteConfig.url,
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: {
      default: siteConfig.name,
      template: `%s | ${siteConfig.name}`,
    },
    description: siteConfig.description,
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
};

export function createMetadata({
  title,
  description,
  path = "",
  image,
}: {
  title?: string;
  description?: string;
  path?: string;
  image?: string;
}): Metadata {
  const url = `${siteConfig.url}${path}`;

  return {
    title,
    description,
    alternates: {
      canonical: url,
    },
    openGraph: {
      title,
      description,
      url,
      ...(image && {
        images: [{ url: image, width: 1200, height: 630, alt: title }],
      }),
    },
    twitter: {
      title,
      description,
      ...(image && { images: [image] }),
    },
  };
}
```

### 2. Update Root Layout

Update `app/layout.tsx` to use shared metadata:

```tsx
import type { Viewport } from "next";
import { sharedMetadata } from "@/lib/metadata";

export const metadata = sharedMetadata;

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#000000" },
  ],
};
```

**Note:** `themeColor` must be in the `viewport` export, not `metadata`.

### 3. Create Sitemap

Create `app/sitemap.ts`:

```ts
import type { MetadataRoute } from "next";
import { siteConfig } from "@/lib/metadata";

export default function sitemap(): MetadataRoute.Sitemap {
  const routes = ["", "/about"].map((route) => ({
    url: `${siteConfig.url}${route}`,
    lastModified: new Date(),
    changeFrequency: "weekly" as const,
    priority: route === "" ? 1 : 0.8,
  }));

  return routes;
}
```

For large sites with dynamic content, use `generateSitemaps` for sitemap index:

```ts
import type { MetadataRoute } from "next";
import { siteConfig } from "@/lib/metadata";

export async function generateSitemaps() {
  // Return an array of sitemap IDs
  return [{ id: "pages" }, { id: "posts" }];
}

export default async function sitemap(props: {
  id: Promise<string>;
}): Promise<MetadataRoute.Sitemap> {
  const id = await props.id;

  if (id === "pages") {
    return [
      {
        url: siteConfig.url,
        lastModified: new Date(),
        changeFrequency: "weekly",
        priority: 1,
      },
    ];
  }

  // Fetch dynamic content for other sitemap segments
  // const posts = await getPosts()
  return [];
}
```

### 4. Create Robots.txt

Create `app/robots.ts`:

```ts
import type { MetadataRoute } from "next";
import { siteConfig } from "@/lib/metadata";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        disallow: ["/api/", "/private/"],
      },
    ],
    sitemap: `${siteConfig.url}/sitemap.xml`,
    host: siteConfig.url,
  };
}
```

### 5. Create Dynamic OG Image

Create `app/opengraph-image.tsx`:

```tsx
import { ImageResponse } from "next/og";

export const alt = "My App";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OGImage() {
  return new ImageResponse(
    <div
      style={{
        fontSize: 64,
        background: "linear-gradient(135deg, #000000 0%, #333333 100%)",
        color: "white",
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: 48,
      }}
    >
      <div style={{ fontSize: 72, fontWeight: "bold", marginBottom: 16 }}>
        My App
      </div>
      <div style={{ fontSize: 32, opacity: 0.8 }}>A Next.js application</div>
    </div>,
    { ...size },
  );
}
```

For dynamic per-page OG images, create `app/[slug]/opengraph-image.tsx`:

```tsx
import { ImageResponse } from "next/og";

export const alt = "Post";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OGImage(props: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await props.params;

  return new ImageResponse(
    <div
      style={{
        fontSize: 48,
        background: "#000",
        color: "white",
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      {slug.replace(/-/g, " ")}
    </div>,
    { ...size },
  );
}
```

### 6. Create JSON-LD Component

Create `lib/structured-data.tsx`:

```tsx
type JsonLdProps = {
  data: Record<string, unknown>;
};

export function JsonLd({ data }: JsonLdProps) {
  return (
    <script
      type="application/ld+json"
      // biome-ignore lint/security/noDangerouslySetInnerHtml: JSON-LD requires dangerouslySetInnerHTML — XSS mitigated by escaping < chars
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(data).replace(/</g, "\\u003c"),
      }}
    />
  );
}
```

The `.replace(/</g, "\\u003c")` prevents XSS injection via HTML tags in JSON-LD payloads.

## Usage Examples

### Per-Page Metadata (Static)

```tsx
// app/about/page.tsx
import { createMetadata } from "@/lib/metadata";

export const metadata = createMetadata({
  title: "About",
  description: "Learn more about our team and mission.",
  path: "/about",
});

export default function AboutPage() {
  return <h1>About</h1>;
}
```

### Per-Page Metadata (Dynamic)

```tsx
// app/posts/[slug]/page.tsx
import type { Metadata } from "next";
import { createMetadata, siteConfig } from "@/lib/metadata";
import { JsonLd } from "@/lib/structured-data";

type Props = {
  params: Promise<{ slug: string }>;
};

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  // const post = await getPost(slug)
  return createMetadata({
    title: slug.replace(/-/g, " "),
    description: `Read about ${slug.replace(/-/g, " ")}`,
    path: `/posts/${slug}`,
    image: `${siteConfig.url}/posts/${slug}/opengraph-image`,
  });
}

export default async function PostPage({ params }: Props) {
  const { slug } = await params;
  // const post = await getPost(slug)

  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "Article",
    headline: slug.replace(/-/g, " "),
    author: { "@type": "Person", name: "Author" },
    datePublished: new Date().toISOString(),
  };

  return (
    <article>
      <JsonLd data={jsonLd} />
      <h1>{slug.replace(/-/g, " ")}</h1>
    </article>
  );
}
```

### Organization JSON-LD (Root Layout)

```tsx
// app/layout.tsx
import { JsonLd } from "@/lib/structured-data";
import { siteConfig } from "@/lib/metadata";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <JsonLd
          data={{
            "@context": "https://schema.org",
            "@type": "Organization",
            name: siteConfig.name,
            url: siteConfig.url,
          }}
        />
        {children}
      </body>
    </html>
  );
}
```

## Environment Variables

Add `NEXT_PUBLIC_SITE_URL` to your `.env.local`:

```
NEXT_PUBLIC_SITE_URL=https://yourdomain.com
```

The metadata helper falls back to `https://example.com` during development.

## How Metadata Merging Works

Next.js merges metadata **top-down**: root layout → nested layouts → page.

- Scalar fields (like `title`) are replaced by the deepest definition.
- Object fields (like `openGraph`) are **shallow-merged** — a child defining `openGraph` entirely replaces the parent's `openGraph`.
- The `createMetadata` helper only sets the fields you pass, so unset fields inherit from `sharedMetadata` in the root layout.
- The `title.template` from the root layout (e.g. `%s | My App`) automatically wraps child page titles.

## Testing Checklist

- [ ] `bun run build` completes without errors
- [ ] No TypeScript errors
- [ ] `/sitemap.xml` returns valid XML
- [ ] `/robots.txt` returns valid robots directives
- [ ] `/opengraph-image` returns a PNG image
- [ ] Page titles follow the template pattern (`Page | My App`)
- [ ] `<meta>` tags render correctly (check View Source)
- [ ] JSON-LD renders as valid `<script type="application/ld+json">`
- [ ] OG tags work in social media debuggers (Facebook Sharing Debugger, Twitter Card Validator)

## Troubleshooting

### OG image not updating on social media

Social platforms aggressively cache OG images. Use their debug tools to refresh:
- Facebook: [Sharing Debugger](https://developers.facebook.com/tools/debug/)
- Twitter/X: [Card Validator](https://cards-dev.twitter.com/validator)

### `metadataBase` warning in development

Set `NEXT_PUBLIC_SITE_URL` in `.env.local`. Without `metadataBase`, Next.js warns about relative OG image URLs.

### `params` TypeScript errors in Next.js 16

All `params` and `searchParams` are now `Promise` types. Use `await params` instead of accessing them directly.

### Metadata not appearing in View Source

Next.js 15.2+ streams metadata for dynamically rendered pages. Metadata appears in `<body>` (appended after load). For SSG pages, metadata is in `<head>` as expected. Both are fine for SEO — Google renders JavaScript.