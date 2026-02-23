---
name: ai-chat
description: Communication layer — streaming chat UI with Postgres persistence, session management, and composable route/renderer architecture for downstream AI skills. Use this skill when the user says "add chat", "setup AI chat", "add streaming chat", or "setup ai-chat".
author: "@mattwoodco"
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
dependencies: [ai-core, auth, docker, db]
---

# AI Chat

Complete streaming chat with Postgres persistence, session management, and a composable architecture that downstream skills (ai-tools, ai-reasoning, ai-memory, ai-artifacts, ai-tasks, ai-generative-ui) extend via clearly marked comment slots.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `ai-core` skill installed (`getModel()` available at `@src/lib/ai`)
- `auth` skill installed (`withAuth` available at `@src/lib/auth-guard`, Drizzle DB at `@src/lib/db`)
- `docker` skill installed (PostgreSQL running)
- shadcn/ui initialized

## Installation

```bash
bun add @ai-sdk/react @phosphor-icons/react
```

## What Gets Created

```
src/
├── lib/
│   └── db/
│       └── schema/
│           └── chat.ts                      # chatSession + chatMessage tables
├── app/
│   ├── api/
│   │   └── ai/
│   │       ├── chat/
│   │       │   └── route.ts                 # POST — streaming chat (with comment slots)
│   │       └── sessions/
│   │           ├── route.ts                 # GET/POST — list/create sessions
│   │           └── [sessionId]/
│   │               └── route.ts             # GET/PATCH/DELETE — session CRUD
│   └── (app)/
│       └── chat/
│           ├── page.tsx                     # Chat page (protected route)
│           └── loading.tsx                  # Loading state
└── components/
    └── ai/
        ├── chat.tsx                         # Chat UI with useChat + DefaultChatTransport
        ├── chat-container.tsx               # Scrollable message list container
        ├── chat-sidebar.tsx                 # Session history sidebar
        ├── code-block.tsx                   # Code display with language class
        ├── loader.tsx                       # Bouncing dots loading indicator
        ├── markdown.tsx                     # Prose wrapper for markdown content
        ├── message.tsx                      # Message layout + renderer (with comment slots)
        └── prompt-input.tsx                 # Textarea + send button input
```

## Database

After applying this skill, push the schema to create the `chat_session` and `chat_message` tables:

```bash
bunx drizzle-kit push
```

## Setup Steps

### Step 1: Create `src/lib/db/schema/chat.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  json,
} from "drizzle-orm/pg-core";

export const chatSession = pgTable("chat_session", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull(),
  title: text("title").notNull().default("New Chat"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).defaultNow().notNull(),
});

export const chatMessage = pgTable("chat_message", {
  id: uuid("id").defaultRandom().primaryKey(),
  sessionId: uuid("session_id")
    .notNull()
    .references(() => chatSession.id, { onDelete: "cascade" }),
  role: text("role", { enum: ["user", "assistant", "system"] }).notNull(),
  parts: json("parts").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});
```

### Step 2: Add chat schema to barrel export

Add the chat schema export to `src/lib/db/schema/index.ts`:

```typescript
export * from "./chat";
```

### Step 3: Create `src/app/api/ai/chat/route.ts`

This is the core streaming endpoint. It includes clearly commented insertion points for downstream skills.

```typescript
import { streamText, convertToModelMessages, type UIMessage, type ToolSet, type JSONValue } from "ai";
import { getModel } from "@src/lib/ai";
import { withAuth } from "@src/lib/auth-guard";
import { db } from "@src/lib/db";
import { chatSession, chatMessage } from "@src/lib/db/schema/chat";
import { eq, and } from "drizzle-orm";

export const POST = withAuth(async (request, { user }) => {
  const {
    messages,
    sessionId,
  }: { messages: UIMessage[]; sessionId?: string } = await request.json();

  const userId = user.id;

  // --- Resolve or create session ---
  let activeSessionId = sessionId;

  if (activeSessionId) {
    const existing = await db
      .select({ id: chatSession.id })
      .from(chatSession)
      .where(
        and(
          eq(chatSession.id, activeSessionId),
          eq(chatSession.userId, userId)
        )
      )
      .limit(1);

    if (existing.length === 0) {
      return new Response(
        JSON.stringify({ error: "Session not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }
  } else {
    const firstUserMessage = messages.find((m) => m.role === "user");
    const title =
      firstUserMessage?.parts
        .filter((p): p is Extract<typeof p, { type: "text" }> => p.type === "text")
        .map((p) => p.text)
        .join(" ")
        .slice(0, 100) || "New Chat";

    const [created] = await db
      .insert(chatSession)
      .values({ userId, title })
      .returning({ id: chatSession.id });
    activeSessionId = created.id;
  }

  // --- SYSTEM PROMPT (ai-chat base, ai-memory appends) ---
  const systemParts: string[] = [
    "You are a helpful assistant. Be concise and clear in your responses.",
  ];
  // [ai-memory]: append memory context here

  // --- TOOLS (ai-tools registers, ai-artifacts/tasks/memory/gen-ui add tools) ---
  const tools: ToolSet = {};
  // [ai-tools]: spread registered tools here
  // [ai-artifacts]: add createArtifact, updateArtifact
  // [ai-tasks]: add createTask, updateTask, listTasks
  // [ai-memory]: add saveMemory, recallMemory

  // --- PROVIDER OPTIONS (ai-reasoning adds thinking config) ---
  let providerOptions: Record<string, Record<string, JSONValue>> | undefined;
  // [ai-reasoning]: add anthropic.thinking config here

  // --- Persist the latest user message ---
  const lastUserMessage = messages.at(-1);
  if (lastUserMessage && lastUserMessage.role === "user") {
    await db.insert(chatMessage).values({
      sessionId: activeSessionId,
      role: "user",
      parts: lastUserMessage.parts,
    });
  }

  // --- Convert UIMessages to ModelMessages for streamText ---
  const modelMessages = await convertToModelMessages(messages);

  // --- Stream the response ---
  const result = streamText({
    model: getModel(),
    system: systemParts.join("\n\n"),
    messages: modelMessages,
    ...(Object.keys(tools).length > 0 && { tools, maxSteps: 5 }),
    ...(providerOptions !== undefined && { providerOptions }),
    async onFinish({ text }) {
      // Persist the assistant's response
      await db.insert(chatMessage).values({
        sessionId: activeSessionId,
        role: "assistant",
        parts: [{ type: "text", text }],
      });

      // Update session timestamp
      await db
        .update(chatSession)
        .set({ updatedAt: new Date() })
        .where(eq(chatSession.id, activeSessionId));
    },
  });

  const response = result.toUIMessageStreamResponse();

  // Append session ID header so client can track the session
  response.headers.set("X-Session-Id", activeSessionId);

  return response;
});
```

### Step 4: Create `src/app/api/ai/sessions/route.ts`

```typescript
import { NextResponse } from "next/server";
import { withAuth } from "@src/lib/auth-guard";
import { db } from "@src/lib/db";
import { chatSession } from "@src/lib/db/schema/chat";
import { eq, desc } from "drizzle-orm";

type SessionListItem = {
  id: string;
  title: string;
  createdAt: Date;
  updatedAt: Date;
};

/** GET /api/ai/sessions — list all sessions for the current user */
export const GET = withAuth(async (_request, { user }) => {
  const sessions = await db
    .select({
      id: chatSession.id,
      title: chatSession.title,
      createdAt: chatSession.createdAt,
      updatedAt: chatSession.updatedAt,
    })
    .from(chatSession)
    .where(eq(chatSession.userId, user.id))
    .orderBy(desc(chatSession.updatedAt));

  return NextResponse.json<SessionListItem[]>(sessions);
});

type CreateSessionBody = { title?: string };

/** POST /api/ai/sessions — create a new session */
export const POST = withAuth(async (request, { user }) => {
  const body: CreateSessionBody = await request.json();

  const [session] = await db
    .insert(chatSession)
    .values({
      userId: user.id,
      title: body.title ?? "New Chat",
    })
    .returning();

  return NextResponse.json(session, { status: 201 });
});
```

### Step 5: Create `src/app/api/ai/sessions/[sessionId]/route.ts`

```typescript
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { withAuth } from "@src/lib/auth-guard";
import { db } from "@src/lib/db";
import { chatSession, chatMessage } from "@src/lib/db/schema/chat";
import { eq, and, asc } from "drizzle-orm";

type RouteContext = { params: Promise<{ sessionId: string }> };

/** GET /api/ai/sessions/[sessionId] — get session with messages */
export const GET = withAuth(async (request: NextRequest, { user }) => {
  // Parse sessionId from URL since withAuth wraps the route context
  const pathParts = request.nextUrl.pathname.split("/");
  const resolvedSessionId = pathParts[pathParts.length - 1];

  const sessions = await db
    .select()
    .from(chatSession)
    .where(
      and(
        eq(chatSession.id, resolvedSessionId),
        eq(chatSession.userId, user.id)
      )
    )
    .limit(1);

  if (sessions.length === 0) {
    return NextResponse.json({ error: "Session not found" }, { status: 404 });
  }

  const messages = await db
    .select({
      id: chatMessage.id,
      role: chatMessage.role,
      parts: chatMessage.parts,
      createdAt: chatMessage.createdAt,
    })
    .from(chatMessage)
    .where(eq(chatMessage.sessionId, resolvedSessionId))
    .orderBy(asc(chatMessage.createdAt));

  return NextResponse.json({
    session: sessions[0],
    messages,
  });
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;

type UpdateSessionBody = { title?: string };

/** PATCH /api/ai/sessions/[sessionId] — update session title */
export const PATCH = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const sessionId = pathParts[pathParts.length - 1];

  const body: UpdateSessionBody = await request.json();

  const result = await db
    .update(chatSession)
    .set({
      ...(body.title !== undefined && { title: body.title }),
      updatedAt: new Date(),
    })
    .where(
      and(
        eq(chatSession.id, sessionId),
        eq(chatSession.userId, user.id)
      )
    )
    .returning();

  if (result.length === 0) {
    return NextResponse.json({ error: "Session not found" }, { status: 404 });
  }

  return NextResponse.json(result[0]);
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;

/** DELETE /api/ai/sessions/[sessionId] — delete session and all messages */
export const DELETE = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const sessionId = pathParts[pathParts.length - 1];

  const result = await db
    .delete(chatSession)
    .where(
      and(
        eq(chatSession.id, sessionId),
        eq(chatSession.userId, user.id)
      )
    )
    .returning({ id: chatSession.id });

  if (result.length === 0) {
    return NextResponse.json({ error: "Session not found" }, { status: 404 });
  }

  return NextResponse.json({ success: true });
}) as (request: NextRequest, context: RouteContext) => Promise<NextResponse>;
```

### Step 6: Create `src/components/ai/loader.tsx`

```tsx
import { cn } from "@src/lib/utils";

type LoaderProps = {
  className?: string;
};

export function Loader({ className }: LoaderProps) {
  return (
    <div className={cn("flex items-center gap-1", className)}>
      <div className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground [animation-delay:-0.3s]" />
      <div className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground [animation-delay:-0.15s]" />
      <div className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground" />
    </div>
  );
}
```

### Step 7: Create `src/components/ai/markdown.tsx`

```tsx
import type { ReactNode } from "react";

type MarkdownProps = {
  children: ReactNode;
};

export function Markdown({ children }: MarkdownProps) {
  if (typeof children === "string") {
    return <div className="prose dark:prose-invert max-w-none whitespace-pre-wrap">{children}</div>;
  }
  return <>{children}</>;
}
```

### Step 8: Create `src/components/ai/code-block.tsx`

```tsx
type CodeBlockProps = {
  code: string;
  language?: string;
};

export function CodeBlock({ code, language }: CodeBlockProps) {
  return (
    <pre className="overflow-x-auto rounded-lg bg-zinc-900 p-4 text-sm text-zinc-100">
      <code className={language ? `language-${language}` : undefined}>{code}</code>
    </pre>
  );
}
```

### Step 9: Create `src/components/ai/chat-container.tsx`

```tsx
import { forwardRef } from "react";
import { cn } from "@src/lib/utils";

type ChatContainerProps = React.HTMLAttributes<HTMLDivElement>;

export const ChatContainer = forwardRef<HTMLDivElement, ChatContainerProps>(
  ({ className, children, ...props }, ref) => {
    return (
      <div ref={ref} className={cn("flex flex-col gap-4", className)} {...props}>
        {children}
      </div>
    );
  }
);
ChatContainer.displayName = "ChatContainer";
```

### Step 10: Create `src/components/ai/prompt-input.tsx`

```tsx
"use client";

import { cn } from "@src/lib/utils";

type PromptInputProps = {
  value: string;
  onChange: (e: React.ChangeEvent<HTMLTextAreaElement>) => void;
  onKeyDown?: (e: React.KeyboardEvent<HTMLTextAreaElement>) => void;
  onSubmit?: () => void;
  disabled?: boolean;
  placeholder?: string;
  className?: string;
};

export function PromptInput({
  value,
  onChange,
  onKeyDown,
  onSubmit,
  disabled,
  placeholder,
  className,
}: PromptInputProps) {
  return (
    <div className={cn("flex gap-2", className)}>
      <textarea
        value={value}
        onChange={onChange}
        onKeyDown={onKeyDown}
        disabled={disabled}
        placeholder={placeholder}
        rows={1}
        className="flex-1 resize-none rounded-lg border bg-background px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-ring disabled:opacity-50"
      />
      <button
        type="button"
        onClick={onSubmit}
        disabled={disabled || !value.trim()}
        className="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
      >
        Send
      </button>
    </div>
  );
}
```

### Step 11: Create `src/components/ai/chat.tsx`

```tsx
"use client";

import { useChat } from "@ai-sdk/react";
import { DefaultChatTransport, type UIMessage } from "ai";
import { useId, useRef, useEffect, useCallback, useState, useMemo } from "react";
import { ChatContainer } from "@/components/ai/chat-container";
import { PromptInput } from "@/components/ai/prompt-input";
import { Loader } from "@/components/ai/loader";
import { MessageBubble } from "@/components/ai/message";

type ChatProps = {
  sessionId: string | null;
  onSessionCreated: (sessionId: string) => void;
};

export function Chat({ sessionId, onSessionCreated: _onSessionCreated }: ChatProps) {
  const messageListId = useId();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [input, setInput] = useState("");
  const [isLoadingHistory, setIsLoadingHistory] = useState(false);
  const [loadedMessages, setLoadedMessages] = useState<UIMessage[] | undefined>(undefined);

  const transport = useMemo(
    () =>
      new DefaultChatTransport({
        api: "/api/ai/chat",
        body: { sessionId },
      }),
    [sessionId]
  );

  // Load existing messages when session changes
  useEffect(() => {
    if (!sessionId) {
      setLoadedMessages(undefined);
      return;
    }

    let cancelled = false;
    setIsLoadingHistory(true);

    fetch(`/api/ai/sessions/${sessionId}`)
      .then((res) => {
        if (!res.ok) throw new Error("Failed to load session");
        return res.json();
      })
      .then((data: { messages: Array<{ id: string; role: string; parts: unknown[] }> }) => {
        if (cancelled) return;
        setLoadedMessages(
          data.messages.map((m) => ({
            id: m.id,
            role: m.role as "user" | "assistant",
            content: "",
            parts: m.parts as UIMessage["parts"],
          }))
        );
      })
      .catch(() => {
        if (!cancelled) setLoadedMessages(undefined);
      })
      .finally(() => {
        if (!cancelled) setIsLoadingHistory(false);
      });

    return () => {
      cancelled = true;
    };
  }, [sessionId]);

  const { messages, sendMessage, status } = useChat({
    transport,
    messages: loadedMessages,
  });

  // Auto-scroll to bottom on new messages
  // biome-ignore lint/correctness/useExhaustiveDependencies: scroll on every message change
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

  if (isLoadingHistory) {
    return (
      <div className="flex h-full items-center justify-center">
        <Loader />
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      <ChatContainer ref={scrollRef} className="flex-1 overflow-y-auto p-4">
        {messages.length === 0 && (
          <div className="flex h-full items-center justify-center text-muted-foreground">
            <p>Start a conversation...</p>
          </div>
        )}
        {messages.map((message) => (
          <MessageBubble
            key={`${messageListId}-${message.id}`}
            message={message}
          />
        ))}
        {isSubmitting && (
          <div className="flex justify-start p-2">
            <Loader />
          </div>
        )}
      </ChatContainer>

      <div className="border-t p-4">
        <PromptInput
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          onSubmit={handleSend}
          disabled={isStreaming || isSubmitting}
          placeholder="Type a message..."
        />
      </div>
    </div>
  );
}
```

### Step 12: Create `src/components/ai/message.tsx`

This is the message renderer with a part switch. Downstream skills add cases at the marked comment slots. The `Message` layout component is exported for reuse by downstream skills.

```tsx
"use client";

import { memo, useId } from "react";
import type { ReactNode } from "react";
import type { UIMessage } from "ai";
import { cn } from "@src/lib/utils";
import { Markdown } from "@/components/ai/markdown";

type MessageProps = {
  role: string;
  children: ReactNode;
  className?: string;
};

export function Message({ role, children, className }: MessageProps) {
  return (
    <div className={cn("flex w-full gap-3", role === "user" ? "justify-end" : "justify-start", className)}>
      {children}
    </div>
  );
}

type MessageBubbleProps = {
  message: UIMessage;
};

export const MessageBubble = memo(function MessageBubble({ message }: MessageBubbleProps) {
  const isUser = message.role === "user";

  return (
    <Message role={message.role}>
      <div
        className={
          isUser
            ? "rounded-2xl bg-primary px-4 py-2 text-primary-foreground"
            : "max-w-none prose dark:prose-invert"
        }
      >
        <MessageParts parts={message.parts} />
      </div>
    </Message>
  );
});

type MessagePartsProps = {
  parts: UIMessage["parts"];
};

function MessageParts({ parts }: MessagePartsProps) {
  const partId = useId();

  return (
    <>
      {parts.map((part, index) => {
        const key = `${partId}-${part.type}-${index}`;

        switch (part.type) {
          // --- BASE (ai-chat) ---
          case "text":
            return <Markdown key={key}>{part.text}</Markdown>;

          // [ai-reasoning]: add case "reasoning" here

          // [ai-tools]: add cases "tool-invocation" and "tool-result" here

          default:
            return null;
        }
      })}
    </>
  );
}
```

### Step 13: Create `src/components/ai/chat-sidebar.tsx`

```tsx
"use client";

import { useId, useEffect, useState, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { Loader } from "@/components/ai/loader";
import { Plus, Trash, PencilSimple, Check, X } from "@phosphor-icons/react";

type SessionItem = {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
};

type ChatSidebarProps = {
  activeSessionId: string | null;
  onSelectSession: (sessionId: string) => void;
  onNewChat: () => void;
  refreshKey?: number;
};

export function ChatSidebar({
  activeSessionId,
  onSelectSession,
  onNewChat,
  refreshKey,
}: ChatSidebarProps) {
  const listId = useId();
  const [sessions, setSessions] = useState<SessionItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editTitle, setEditTitle] = useState("");

  const loadSessions = useCallback(async () => {
    try {
      const res = await fetch("/api/ai/sessions");
      if (!res.ok) return;
      const data: SessionItem[] = await res.json();
      setSessions(data);
    } catch {
      // Silently fail — sidebar is non-critical
    } finally {
      setIsLoading(false);
    }
  }, []);

  // biome-ignore lint/correctness/useExhaustiveDependencies: refreshKey triggers reload
  useEffect(() => {
    loadSessions();
  }, [loadSessions, refreshKey]);

  const handleDelete = useCallback(
    async (sessionId: string) => {
      try {
        const res = await fetch(`/api/ai/sessions/${sessionId}`, {
          method: "DELETE",
        });
        if (!res.ok) return;
        setSessions((prev) => prev.filter((s) => s.id !== sessionId));
        if (activeSessionId === sessionId) {
          onNewChat();
        }
      } catch {
        // Silently fail
      }
    },
    [activeSessionId, onNewChat]
  );

  const handleRenameStart = useCallback(
    (session: SessionItem) => {
      setEditingId(session.id);
      setEditTitle(session.title);
    },
    []
  );

  const handleRenameSubmit = useCallback(
    async (sessionId: string) => {
      if (!editTitle.trim()) {
        setEditingId(null);
        return;
      }

      try {
        const res = await fetch(`/api/ai/sessions/${sessionId}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title: editTitle.trim() }),
        });
        if (!res.ok) return;
        setSessions((prev) =>
          prev.map((s) =>
            s.id === sessionId ? { ...s, title: editTitle.trim() } : s
          )
        );
      } catch {
        // Silently fail
      } finally {
        setEditingId(null);
      }
    },
    [editTitle]
  );

  return (
    <aside className="flex h-full w-64 flex-col border-r bg-muted/30">
      <div className="flex items-center justify-between border-b p-3">
        <h2 className="text-sm font-semibold">Chat History</h2>
        <Button variant="ghost" size="icon" onClick={onNewChat} title="New chat">
          <Plus className="h-4 w-4" />
        </Button>
      </div>

      <nav className="flex-1 overflow-y-auto p-2">
        {isLoading && (
          <div className="flex justify-center p-4">
            <Loader />
          </div>
        )}

        {!isLoading && sessions.length === 0 && (
          <p className="p-2 text-xs text-muted-foreground">
            No conversations yet
          </p>
        )}

        <ul className="space-y-1">
          {sessions.map((session) => (
            <li key={`${listId}-${session.id}`}>
              {editingId === session.id ? (
                <div className="flex items-center gap-1 rounded-md p-1">
                  <input
                    type="text"
                    value={editTitle}
                    onChange={(e) => setEditTitle(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") handleRenameSubmit(session.id);
                      if (e.key === "Escape") setEditingId(null);
                    }}
                    className="flex-1 rounded border bg-background px-2 py-1 text-sm"
                    // biome-ignore lint/a11y/noAutofocus: intentional for inline rename
                    autoFocus
                  />
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-6 w-6"
                    onClick={() => handleRenameSubmit(session.id)}
                  >
                    <Check className="h-3 w-3" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-6 w-6"
                    onClick={() => setEditingId(null)}
                  >
                    <X className="h-3 w-3" />
                  </Button>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => onSelectSession(session.id)}
                  className={`group flex w-full items-center justify-between rounded-md px-2 py-1.5 text-left text-sm transition-colors hover:bg-accent ${
                    activeSessionId === session.id
                      ? "bg-accent font-medium"
                      : ""
                  }`}
                >
                  <span className="truncate">{session.title}</span>
                  <span className="flex shrink-0 gap-0.5 opacity-0 transition-opacity group-hover:opacity-100">
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-6 w-6"
                      onClick={(e) => {
                        e.stopPropagation();
                        handleRenameStart(session);
                      }}
                    >
                      <PencilSimple className="h-3 w-3" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-6 w-6 text-destructive"
                      onClick={(e) => {
                        e.stopPropagation();
                        handleDelete(session.id);
                      }}
                    >
                      <Trash className="h-3 w-3" />
                    </Button>
                  </span>
                </button>
              )}
            </li>
          ))}
        </ul>
      </nav>
    </aside>
  );
}
```

### Step 14: Create `src/app/(app)/chat/page.tsx`

```tsx
"use client";

import { useState, useCallback } from "react";
import { Chat } from "@/components/ai/chat";
import { ChatSidebar } from "@/components/ai/chat-sidebar";

export default function ChatPage() {
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  const handleNewChat = useCallback(() => {
    setActiveSessionId(null);
  }, []);

  const handleSessionCreated = useCallback((sessionId: string) => {
    setActiveSessionId(sessionId);
    setRefreshKey((prev) => prev + 1);
  }, []);

  const handleSelectSession = useCallback((sessionId: string) => {
    setActiveSessionId(sessionId);
  }, []);

  return (
    <div className="flex h-[calc(100vh-4rem)]">
      <ChatSidebar
        activeSessionId={activeSessionId}
        onSelectSession={handleSelectSession}
        onNewChat={handleNewChat}
        refreshKey={refreshKey}
      />
      <main className="flex-1">
        <Chat
          key={activeSessionId ?? "new"}
          sessionId={activeSessionId}
          onSessionCreated={handleSessionCreated}
        />
      </main>
    </div>
  );
}
```

### Step 15: Create `src/app/(app)/chat/loading.tsx`

```tsx
import { Loader } from "@/components/ai/loader";

export default function ChatLoading() {
  return (
    <div className="flex h-[calc(100vh-4rem)] items-center justify-center">
      <Loader />
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

2. Navigate to `/chat` in your app (must be signed in via the `auth` skill).

3. Start typing a message. The AI responds with streaming text.

4. Sessions appear in the left sidebar. Click to switch, rename with the pencil icon, or delete with the trash icon.

### Programmatic Usage

```typescript
// List sessions
const res = await fetch("/api/ai/sessions");
const sessions = await res.json();

// Create a session
const res = await fetch("/api/ai/sessions", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ title: "My Custom Chat" }),
});

// Get session with messages
const res = await fetch(`/api/ai/sessions/${sessionId}`);
const { session, messages } = await res.json();

// Delete a session
await fetch(`/api/ai/sessions/${sessionId}`, { method: "DELETE" });
```

## Comment Slot Reference

Downstream skills extend the chat by inserting code at these marked positions:

### In `route.ts`

| Comment Slot | Used By | Purpose |
|---|---|---|
| `// [ai-memory]: append memory context here` | ai-memory | Inject recalled memories into `systemParts[]` |
| `// [ai-tools]: spread registered tools here` | ai-tools | Spread `allTools` into `tools` object |
| `// [ai-artifacts]: add createArtifact, updateArtifact` | ai-artifacts | Add artifact tool definitions |
| `// [ai-tasks]: add createTask, updateTask, listTasks` | ai-tasks | Add task tool definitions |
| `// [ai-memory]: add saveMemory, recallMemory` | ai-memory | Add memory tool definitions |
| `// [ai-reasoning]: add anthropic.thinking config here` | ai-reasoning | Set `providerOptions.anthropic` thinking config |

### In `message.tsx`

| Comment Slot | Used By | Purpose |
|---|---|---|
| `// [ai-reasoning]: add case "reasoning" here` | ai-reasoning | Render `<ReasoningBlock>` for thinking parts |
| `// [ai-tools]: add cases "tool-invocation" and "tool-result" here` | ai-tools | Render tool invocation cards and results |

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/ai/chat` | Stream a chat response (creates session if needed) |
| GET | `/api/ai/sessions` | List all sessions for the current user |
| POST | `/api/ai/sessions` | Create a new session |
| GET | `/api/ai/sessions/[sessionId]` | Get session with messages |
| PATCH | `/api/ai/sessions/[sessionId]` | Update session title |
| DELETE | `/api/ai/sessions/[sessionId]` | Delete session and all messages |

## Acceptance Criteria

- Send a message and receive a streamed response
- Refresh the page and messages persist from Postgres
- Create a new session via the "+" button in the sidebar
- Switch sessions in the sidebar and messages load correctly
- Rename a session via the pencil icon
- Delete a session and confirm it is removed from the sidebar and database
- Unauthenticated requests to `/api/ai/*` return 401
- `X-Session-Id` response header is set on every chat response
- `tsc` passes with no errors
- `bun run build` succeeds
