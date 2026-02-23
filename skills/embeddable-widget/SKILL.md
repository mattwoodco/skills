---
name: embeddable-widget
description: Embeddable chat widget — iframe-based chat scoped by businessId, a widget.js loader script, appearance configuration API, and public (no-auth) customer-facing routes. Use this skill when the user says "add widget", "embeddable chat", "setup widget", "iframe chat", or "setup embeddable-widget".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-14
updated: 2026-02-14
dependencies: [ai-chat, auth, docker]
---

# Embeddable Widget

Embeddable chat widget that business owners drop into their websites via a `<script>` tag. The script injects an `<iframe>` pointing to `/widget/[businessId]`, which renders a minimal chat interface scoped to that business. No authentication required for end customers — the widget is public, isolated by `businessId`.

Business owners configure widget appearance (colors, greeting, position) from an authenticated admin API.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `ai-chat` skill installed (streaming chat route, message components)
- `auth` skill installed (`withAuth` at `@/lib/auth-guard`, Drizzle DB at `@/db`)
- `docker` skill installed (PostgreSQL running)
- shadcn/ui initialized

## Installation

No additional packages required. Uses existing `ai` and `@ai-sdk/react` from `ai-chat`.

## What Gets Created

```
src/
├── db/
│   └── schema/
│       └── widget.ts                          # widgetConfig table
├── app/
│   ├── api/
│   │   └── widget/
│   │       ├── route.ts                       # GET/POST — list/create widget configs (auth)
│   │       ├── [businessId]/
│   │       │   ├── route.ts                   # GET/PATCH — get/update config (auth)
│   │       │   └── chat/
│   │       │       └── route.ts               # POST — public streaming chat (no auth)
│   │       └── embed.js/
│   │           └── route.ts                   # GET — serves the widget loader script
│   └── widget/
│       └── [businessId]/
│           └── page.tsx                       # Public widget chat UI (rendered in iframe)
└── components/
    └── widget/
        ├── widget-chat.tsx                    # Minimal chat UI for the iframe
        └── widget-message.tsx                 # Compact message renderer
```

## Database

After applying this skill, push the schema:

```bash
bunx drizzle-kit push
```

## Setup Steps

### Step 1: Create `src/db/schema/widget.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  jsonb,
} from "drizzle-orm/pg-core";

type WidgetAppearance = {
  primaryColor: string;
  greeting: string;
  position: "bottom-right" | "bottom-left";
  avatarUrl?: string;
  title: string;
};

export const widgetConfig = pgTable("widget_config", {
  id: uuid("id").defaultRandom().primaryKey(),
  businessId: text("business_id").notNull().unique(),
  ownerId: text("owner_id").notNull(),
  name: text("name").notNull(),
  appearance: jsonb("appearance")
    .$type<WidgetAppearance>()
    .notNull()
    .default({
      primaryColor: "#2563eb",
      greeting: "Hi! How can I help you today?",
      position: "bottom-right",
      title: "Chat with us",
    }),
  systemPrompt: text("system_prompt")
    .notNull()
    .default("You are a helpful customer support assistant. Be friendly, concise, and helpful."),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).defaultNow().notNull(),
});

export type WidgetConfig = typeof widgetConfig.$inferSelect;
export type NewWidgetConfig = typeof widgetConfig.$inferInsert;
export type { WidgetAppearance };
```

### Step 2: Add export to `src/db/schema/index.ts`

Find the last `export * from` line and add:

```typescript
export * from "./widget";
```

### Step 3: Create `src/app/api/widget/route.ts`

```typescript
import { NextResponse } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/db";
import { widgetConfig } from "@/db/schema/widget";
import { eq, desc } from "drizzle-orm";
import { randomUUID } from "crypto";

/** GET /api/widget — list widget configs for the current user */
export const GET = withAuth(async (_request, { user }) => {
  const configs = await db
    .select()
    .from(widgetConfig)
    .where(eq(widgetConfig.ownerId, user.id))
    .orderBy(desc(widgetConfig.createdAt));

  return NextResponse.json(configs);
});

type CreateWidgetBody = {
  name: string;
  systemPrompt?: string;
  appearance?: {
    primaryColor?: string;
    greeting?: string;
    position?: "bottom-right" | "bottom-left";
    avatarUrl?: string;
    title?: string;
  };
};

/** POST /api/widget — create a new widget config */
export const POST = withAuth(async (request, { user }) => {
  const body: CreateWidgetBody = await request.json();

  if (!body.name || typeof body.name !== "string" || !body.name.trim()) {
    return NextResponse.json(
      { error: "Name is required" },
      { status: 400 }
    );
  }

  const businessId = randomUUID().replace(/-/g, "").slice(0, 12);

  const defaultAppearance = {
    primaryColor: "#2563eb",
    greeting: "Hi! How can I help you today?",
    position: "bottom-right" as const,
    title: "Chat with us",
  };

  const [config] = await db
    .insert(widgetConfig)
    .values({
      businessId,
      ownerId: user.id,
      name: body.name.trim(),
      systemPrompt: body.systemPrompt ?? undefined,
      appearance: body.appearance
        ? { ...defaultAppearance, ...body.appearance }
        : defaultAppearance,
    })
    .returning();

  return NextResponse.json(config, { status: 201 });
});
```

### Step 4: Create `src/app/api/widget/[businessId]/route.ts`

```typescript
import { NextRequest, NextResponse } from "next/server";
import { withAuth } from "@/lib/auth-guard";
import { db } from "@/db";
import { widgetConfig, type WidgetAppearance } from "@/db/schema/widget";
import { eq, and } from "drizzle-orm";

type RouteContext = { params: Promise<{ businessId: string }> };

/** GET /api/widget/[businessId] — get widget config (authenticated, owner only) */
export const GET = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const businessId = pathParts[pathParts.length - 1];

  const configs = await db
    .select()
    .from(widgetConfig)
    .where(
      and(
        eq(widgetConfig.businessId, businessId),
        eq(widgetConfig.ownerId, user.id)
      )
    )
    .limit(1);

  if (configs.length === 0) {
    return NextResponse.json({ error: "Widget not found" }, { status: 404 });
  }

  return NextResponse.json(configs[0]);
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;

type UpdateWidgetBody = {
  name?: string;
  systemPrompt?: string;
  appearance?: Partial<WidgetAppearance>;
};

/** PATCH /api/widget/[businessId] — update widget config (authenticated, owner only) */
export const PATCH = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const businessId = pathParts[pathParts.length - 1];

  const body: UpdateWidgetBody = await request.json();

  const existing = await db
    .select()
    .from(widgetConfig)
    .where(
      and(
        eq(widgetConfig.businessId, businessId),
        eq(widgetConfig.ownerId, user.id)
      )
    )
    .limit(1);

  if (existing.length === 0) {
    return NextResponse.json({ error: "Widget not found" }, { status: 404 });
  }

  const currentAppearance = existing[0].appearance as WidgetAppearance;

  const [updated] = await db
    .update(widgetConfig)
    .set({
      ...(body.name !== undefined && { name: body.name }),
      ...(body.systemPrompt !== undefined && {
        systemPrompt: body.systemPrompt,
      }),
      ...(body.appearance !== undefined && {
        appearance: { ...currentAppearance, ...body.appearance },
      }),
      updatedAt: new Date(),
    })
    .where(
      and(
        eq(widgetConfig.businessId, businessId),
        eq(widgetConfig.ownerId, user.id)
      )
    )
    .returning();

  return NextResponse.json(updated);
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;
```

### Step 5: Create `src/app/api/widget/[businessId]/chat/route.ts`

This is the **public** (no auth) streaming chat endpoint scoped by businessId.

```typescript
import {
  streamText,
  convertToModelMessages,
  type UIMessage,
} from "ai";
import { getModel } from "@/lib/ai";
import { db } from "@/db";
import { widgetConfig } from "@/db/schema/widget";
import { eq } from "drizzle-orm";
import { NextRequest } from "next/server";

type WidgetChatBody = {
  messages: UIMessage[];
};

/** POST /api/widget/[businessId]/chat — public streaming chat (no auth required) */
export async function POST(request: NextRequest) {
  const pathParts = request.nextUrl.pathname.split("/");
  // URL: /api/widget/[businessId]/chat
  const businessId = pathParts[pathParts.length - 2];

  // Look up widget config
  const configs = await db
    .select()
    .from(widgetConfig)
    .where(eq(widgetConfig.businessId, businessId))
    .limit(1);

  if (configs.length === 0) {
    return new Response(
      JSON.stringify({ error: "Widget not found" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  const config = configs[0];
  const { messages }: WidgetChatBody = await request.json();

  // Build system prompt from widget config
  const systemParts: string[] = [config.systemPrompt];

  // [ai-rag-chat]: append RAG context here for knowledge-base-aware widgets

  const modelMessages = await convertToModelMessages(messages);

  const result = streamText({
    model: getModel(),
    system: systemParts.join("\n\n"),
    messages: modelMessages,
  });

  return result.toUIMessageStreamResponse();
}
```

### Step 6: Create `src/app/api/widget/embed.js/route.ts`

This serves the embeddable JavaScript loader that website owners include via a `<script>` tag.

```typescript
import { NextRequest, NextResponse } from "next/server";

/** GET /api/widget/embed.js — serves the widget loader script */
export function GET(request: NextRequest) {
  const origin = request.nextUrl.origin;

  const script = `
(function() {
  if (window.__chatWidgetLoaded) return;
  window.__chatWidgetLoaded = true;

  var script = document.currentScript;
  var businessId = script.getAttribute("data-business-id");
  if (!businessId) {
    console.error("[ChatWidget] Missing data-business-id attribute");
    return;
  }

  var position = script.getAttribute("data-position") || "bottom-right";
  var isRight = position === "bottom-right";

  // Create toggle button
  var btn = document.createElement("button");
  btn.id = "__chat-widget-toggle";
  btn.setAttribute("aria-label", "Open chat");
  btn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>';
  Object.assign(btn.style, {
    position: "fixed",
    bottom: "20px",
    [isRight ? "right" : "left"]: "20px",
    width: "56px",
    height: "56px",
    borderRadius: "28px",
    border: "none",
    background: "#2563eb",
    color: "#fff",
    cursor: "pointer",
    boxShadow: "0 4px 12px rgba(0,0,0,0.15)",
    zIndex: "2147483647",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    transition: "transform 0.2s ease",
  });

  // Create iframe container
  var container = document.createElement("div");
  container.id = "__chat-widget-container";
  Object.assign(container.style, {
    position: "fixed",
    bottom: "88px",
    [isRight ? "right" : "left"]: "20px",
    width: "380px",
    height: "520px",
    maxHeight: "calc(100vh - 120px)",
    borderRadius: "16px",
    overflow: "hidden",
    boxShadow: "0 8px 32px rgba(0,0,0,0.12)",
    zIndex: "2147483646",
    display: "none",
    border: "1px solid rgba(0,0,0,0.08)",
  });

  var iframe = document.createElement("iframe");
  iframe.src = "${origin}/widget/" + encodeURIComponent(businessId);
  iframe.setAttribute("title", "Chat Widget");
  Object.assign(iframe.style, {
    width: "100%",
    height: "100%",
    border: "none",
  });

  container.appendChild(iframe);
  document.body.appendChild(container);
  document.body.appendChild(btn);

  var isOpen = false;
  btn.addEventListener("click", function() {
    isOpen = !isOpen;
    container.style.display = isOpen ? "block" : "none";
    btn.style.transform = isOpen ? "scale(0.9)" : "scale(1)";
    btn.setAttribute("aria-label", isOpen ? "Close chat" : "Open chat");
    btn.innerHTML = isOpen
      ? '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>'
      : '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>';
  });
})();
`.trim();

  return new NextResponse(script, {
    headers: {
      "Content-Type": "application/javascript",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
```

### Step 7: Create `src/components/widget/widget-message.tsx`

```tsx
"use client";

import { useId } from "react";
import type { UIMessage } from "ai";
import { Markdown } from "@/components/ai/markdown";

type WidgetMessageProps = {
  message: UIMessage;
  primaryColor: string;
};

export function WidgetMessage({ message, primaryColor }: WidgetMessageProps) {
  const isUser = message.role === "user";
  const partId = useId();

  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"} mb-3`}>
      <div
        className={
          isUser
            ? "max-w-[80%] rounded-2xl px-3 py-2 text-sm text-white"
            : "max-w-[80%] rounded-2xl bg-muted px-3 py-2 text-sm"
        }
        style={isUser ? { backgroundColor: primaryColor } : undefined}
      >
        {message.parts.map((part, index) => {
          const key = `${partId}-${part.type}-${index}`;
          switch (part.type) {
            case "text":
              return (
                <div key={key} className="prose prose-sm dark:prose-invert max-w-none">
                  <Markdown>{part.text}</Markdown>
                </div>
              );
            default:
              return null;
          }
        })}
      </div>
    </div>
  );
}
```

### Step 8: Create `src/components/widget/widget-chat.tsx`

```tsx
"use client";

import { useChat } from "@ai-sdk/react";
import { DefaultChatTransport } from "ai";
import { useId, useRef, useEffect, useCallback, useState, useMemo } from "react";
import { WidgetMessage } from "./widget-message";

type WidgetAppearance = {
  primaryColor: string;
  greeting: string;
  position: "bottom-right" | "bottom-left";
  avatarUrl?: string;
  title: string;
};

type WidgetChatProps = {
  businessId: string;
  appearance: WidgetAppearance;
};

export function WidgetChat({ businessId, appearance }: WidgetChatProps) {
  const messageListId = useId();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [input, setInput] = useState("");

  const transport = useMemo(
    () =>
      new DefaultChatTransport({
        api: `/api/widget/${businessId}/chat`,
      }),
    [businessId]
  );

  const { messages, sendMessage, status } = useChat({ transport });

  // Auto-scroll
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  const handleSend = useCallback(() => {
    if (!input.trim()) return;
    sendMessage({ text: input });
    setInput("");
  }, [input, sendMessage]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        handleSend();
      }
    },
    [handleSend]
  );

  const isStreaming = status === "streaming";
  const isSubmitting = status === "submitted";

  return (
    <div className="flex h-full flex-col bg-background">
      {/* Header */}
      <div
        className="flex items-center gap-3 px-4 py-3 text-white"
        style={{ backgroundColor: appearance.primaryColor }}
      >
        {appearance.avatarUrl && (
          <img
            src={appearance.avatarUrl}
            alt=""
            className="h-8 w-8 rounded-full object-cover"
          />
        )}
        <div>
          <p className="text-sm font-semibold">{appearance.title}</p>
        </div>
      </div>

      {/* Messages */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto p-4">
        {messages.length === 0 && (
          <div className="mb-3 flex justify-start">
            <div className="max-w-[80%] rounded-2xl bg-muted px-3 py-2 text-sm">
              {appearance.greeting}
            </div>
          </div>
        )}
        {messages.map((message) => (
          <WidgetMessage
            key={`${messageListId}-${message.id}`}
            message={message}
            primaryColor={appearance.primaryColor}
          />
        ))}
        {isSubmitting && (
          <div className="flex justify-start mb-3">
            <div className="rounded-2xl bg-muted px-3 py-2">
              <span className="flex gap-1">
                <span className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/40" style={{ animationDelay: "0ms" }} />
                <span className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/40" style={{ animationDelay: "150ms" }} />
                <span className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/40" style={{ animationDelay: "300ms" }} />
              </span>
            </div>
          </div>
        )}
      </div>

      {/* Input */}
      <div className="border-t p-3">
        <div className="flex gap-2">
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            disabled={isStreaming || isSubmitting}
            placeholder="Type a message..."
            className="flex-1 rounded-full border bg-background px-4 py-2 text-sm outline-none focus:ring-2 focus:ring-ring disabled:opacity-50"
          />
          <button
            type="button"
            onClick={handleSend}
            disabled={isStreaming || isSubmitting || !input.trim()}
            className="inline-flex h-9 w-9 items-center justify-center rounded-full text-white transition-colors disabled:opacity-50"
            style={{ backgroundColor: appearance.primaryColor }}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <path d="m5 12 7-7 7 7" />
              <path d="M12 19V5" />
            </svg>
          </button>
        </div>
      </div>
    </div>
  );
}
```

### Step 9: Create `src/app/widget/[businessId]/page.tsx`

```tsx
import { db } from "@/db";
import { widgetConfig, type WidgetAppearance } from "@/db/schema/widget";
import { eq } from "drizzle-orm";
import { notFound } from "next/navigation";
import { WidgetChat } from "@/components/widget/widget-chat";

type PageProps = {
  params: Promise<{ businessId: string }>;
};

export default async function WidgetPage({ params }: PageProps) {
  const { businessId } = await params;

  const configs = await db
    .select({
      businessId: widgetConfig.businessId,
      appearance: widgetConfig.appearance,
    })
    .from(widgetConfig)
    .where(eq(widgetConfig.businessId, businessId))
    .limit(1);

  if (configs.length === 0) {
    notFound();
  }

  const config = configs[0];
  const appearance = config.appearance as WidgetAppearance;

  return (
    <html lang="en">
      <body style={{ margin: 0, padding: 0, height: "100vh" }}>
        <WidgetChat
          businessId={businessId}
          appearance={appearance}
        />
      </body>
    </html>
  );
}
```

## Usage

### For Business Owners (Authenticated)

#### Create a widget

```typescript
const res = await fetch("/api/widget", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    name: "My Store Chat",
    systemPrompt: "You are a helpful assistant for My Store. Answer questions about our products.",
    appearance: {
      primaryColor: "#16a34a",
      greeting: "Welcome to My Store! How can I help?",
      title: "My Store Support",
    },
  }),
});
const widget = await res.json();
// widget.businessId = "a1b2c3d4e5f6"
```

#### Embed on a website

Add this script tag to any HTML page:

```html
<script
  src="https://your-app.com/api/widget/embed.js"
  data-business-id="a1b2c3d4e5f6"
  data-position="bottom-right"
  defer
></script>
```

#### Update appearance

```typescript
await fetch(`/api/widget/${businessId}`, {
  method: "PATCH",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    appearance: { primaryColor: "#dc2626", greeting: "Hello!" },
  }),
});
```

### For End Customers (Public, No Auth)

Customers interact with the widget by clicking the floating chat button. Messages stream via `/api/widget/[businessId]/chat`. No login required.

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/widget` | Yes | List owner's widget configs |
| POST | `/api/widget` | Yes | Create a new widget config |
| GET | `/api/widget/[businessId]` | Yes | Get widget config (owner only) |
| PATCH | `/api/widget/[businessId]` | Yes | Update widget config (owner only) |
| POST | `/api/widget/[businessId]/chat` | No | Public streaming chat |
| GET | `/api/widget/embed.js` | No | Widget loader script |

## Comment Slot Reference

### In `src/app/api/widget/[businessId]/chat/route.ts`

| Comment Slot | Used By | Purpose |
|---|---|---|
| `// [ai-rag-chat]: append RAG context here` | knowledge-sync | Inject business knowledge into widget responses |

## Acceptance Criteria

- Create a widget config and receive a `businessId`
- Load `/widget/[businessId]` in a browser and see the chat UI with configured appearance
- Send a message and receive a streamed AI response
- Include `<script src="/api/widget/embed.js" data-business-id="...">` on an external page — floating button appears, opens/closes iframe
- Widget iframe is fully isolated (no CSS/JS conflicts)
- Only the widget owner can view/edit the config (authenticated endpoints)
- Public chat endpoint works without authentication
- Invalid `businessId` returns 404
- `tsc` passes with no errors
- `bun run build` succeeds
