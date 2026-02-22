---
name: analytics
description: Setup Vercel Analytics for Next.js applications with custom event tracking. Use this skill when the user says "setup analytics", "add analytics", "setup vercel analytics", "track events", or "add tracking".
author: "@mattwoodco"
version: 1.1.0
created: 2026-01-12
updated: 2026-02-17
validated: 2026-02-17
dependencies: [setup-vercel]
---

# Vercel Analytics Setup

Complete setup for Vercel Analytics in Next.js applications with custom event tracking for both client and server.

## What Gets Created

| Skill File | Target Project Path | Description |
|------------|---------------------|-------------|
| (embedded) | `src/app/layout.tsx` | Analytics component added |
| (embedded) | `src/components/*.tsx` | Event tracking examples |

## Installation

```bash
bun add @vercel/analytics
```

## Setup

Add the Analytics component to your root layout:

```tsx
// app/layout.tsx
import { Analytics } from "@vercel/analytics/next";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html>
      <body>
        {children}
        <Analytics />
      </body>
    </html>
  );
}
```

## Enable in Dashboard

1. Go to Vercel Dashboard
2. Select your Project
3. Navigate to Analytics tab
4. Click Enable

Analytics auto-detects after your next deployment.

## Custom Events (Client)

```tsx
import { track } from "@vercel/analytics";

// Basic event
track("Signup");

// Event with data
track("Purchase", {
  product: "shirt",
  price: 25,
});
```

## Custom Events (Server)

Use in Server Actions or Route Handlers:

```tsx
import { track } from "@vercel/analytics/server";

// In Server Action or Route Handler
await track("FormSubmit", { type: "contact" });
```

## Analytics Component Props

| Prop | Type | Description |
|------|------|-------------|
| `mode` | `'auto' \| 'production' \| 'development'` | When to track. Default: `'auto'` |
| `debug` | `boolean` | Log events to console |
| `beforeSend` | `(event) => event \| null` | Modify/filter events |

## beforeSend Example

Filter or modify events before sending:

```tsx
<Analytics
  beforeSend={(event) => {
    // Redact sensitive paths
    if (event.url.includes("/private")) {
      return { ...event, url: "/private/[redacted]" };
    }
    // Skip tracking entirely
    if (event.url.includes("/admin")) {
      return null;
    }
    return event;
  }}
/>
```

## Event Tracking Limits

| Constraint | Limit |
|------------|-------|
| Event name | max 255 chars |
| Property key | max 255 chars |
| Property value | max 255 chars |
| Nested objects | Not supported |
| Value types | `string \| number \| boolean \| null` |
| Custom events | Pro/Enterprise plans only |

## Verification

### Local Development

In development mode, Analytics loads but does NOT send requests to Vercel servers. Instead:

1. **Check Network Tab**: Look for `va.vercel-scripts.com/v1/script.debug.js` loading successfully
2. **Check Console**: You should see these debug messages:
   - `[Vercel Web Analytics] Debug mode is enabled by default in development. No requests will be sent to the server.`
   - `[Vercel Web Analytics] Running queued event pageview {"route":"/","path":"/"}`
   - `[Vercel Web Analytics] [pageview] http://localhost:3000/ {...}`

The console messages confirm Analytics is properly initialized and tracking pageviews, even though data isn't sent in dev mode.

### Production Verification

After deployment to Vercel:

1. **Check Network Tab**: Look for requests to:
   - `/_vercel/insights/view` (pageviews)
   - `/_vercel/insights/event` (custom events)
   - Or `va.vercel-scripts.com` endpoints
2. **Check Vercel Dashboard**: Navigate to your project's Analytics tab to see incoming data

### Common Issues

| Issue | Solution |
|-------|----------|
| No network requests in dev | Expected behavior - debug mode logs to console only |
| No console messages | Verify `<Analytics />` is in root layout and page refreshed |
| Script fails to load | Check for ad blockers or network issues |
| No data in dashboard | Ensure Analytics is enabled in Vercel Dashboard and site is deployed |

### Programmatic Verification (Playwright/Testing)

```typescript
// Check Analytics script loaded
const analyticsScript = await page.waitForResponse(
  (response) => response.url().includes("va.vercel-scripts.com") && response.status() === 200
);

// Check console for Analytics messages (development)
page.on("console", (msg) => {
  if (msg.text().includes("[Vercel Web Analytics]")) {
    console.log("Analytics initialized:", msg.text());
  }
});
```

## Usage Examples

### Track Button Clicks

```tsx
"use client";

import { track } from "@vercel/analytics";

export function CTAButton() {
  return (
    <button
      onClick={() => {
        track("CTA Clicked", { location: "hero" });
      }}
    >
      Get Started
    </button>
  );
}
```

### Track Form Submissions

```tsx
"use client";

import { track } from "@vercel/analytics";

export function ContactForm() {
  async function handleSubmit(formData: FormData) {
    track("Form Submitted", {
      type: "contact",
      hasMessage: Boolean(formData.get("message")),
    });
    // Submit form...
  }

  return <form action={handleSubmit}>{/* fields */}</form>;
}
```

### Track Server-Side Events

```tsx
// app/api/checkout/route.ts
import { track } from "@vercel/analytics/server";
import { NextResponse } from "next/server";

export async function POST(request: Request) {
  const { items, total } = await request.json();

  await track("Checkout Started", {
    itemCount: items.length,
    total,
  });

  // Process checkout...
  return NextResponse.json({ success: true });
}
```

### Track with Server Actions

```tsx
// app/actions.ts
"use server";

import { track } from "@vercel/analytics/server";

export async function subscribeToNewsletter(email: string) {
  await track("Newsletter Signup", { source: "footer" });
  // Save to database...
}
```

## Setup Checklist

- [ ] `@vercel/analytics` installed
- [ ] `<Analytics />` component added to root layout
- [ ] Analytics enabled in Vercel Dashboard
- [ ] Deployed to Vercel
- [ ] Verified requests in Network tab
