---
name: ai-rag-chat
description: RAG-powered chat interface — retrieves relevant chunks via vector search, streams answers with source citations (page numbers + document titles), and persists conversations. Use this skill when the user says "add RAG chat", "chat with PDFs", "setup ai-rag-chat", or "add document Q&A".
author: "@mattwoodco"
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
validated: 2026-02-13
dependencies: [ai-chat, ai-rag-vectors, auth]
---

# AI RAG Chat

RAG-powered chat that retrieves relevant document chunks via vector search, injects them as context into the system prompt, and streams answers with source citations. Extends the existing `ai-chat` skill's route and UI.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `ai-chat` skill installed (streaming chat at `/api/ai/chat`, UI components)
- `ai-rag-vectors` skill installed (`searchChunks()` at `@/lib/rag/search`)
- shadcn/ui initialized

## Installation

No additional packages needed — uses existing `ai` and `@ai-sdk/react` from `ai-chat`.

## What Gets Created

```
src/
├── app/
│   └── api/
│       └── rag/
│           └── chat/
│               └── route.ts               # POST — RAG streaming chat
└── components/
    └── rag/
        ├── rag-chat.tsx                    # RAG chat UI with useChat
        └── citation-badge.tsx             # Clickable citation badge component
```

## Setup Steps

### Step 1: Create `src/app/api/rag/chat/route.ts`

This is a dedicated RAG chat endpoint. It performs vector search, builds a context-augmented system prompt, and streams the response.

```typescript
import {
  streamText,
  convertToModelMessages,
  type UIMessage,
  type JSONValue,
} from "ai";
import { getModel } from "@/lib/ai";
import { withAuth } from "@/lib/auth-guard";
import { searchChunks } from "@/lib/rag/search";
import { db } from "@/lib/db";
import { chatSession, chatMessage } from "@/lib/db/schema/chat";
import { eq, and } from "drizzle-orm";

type RagChatBody = {
  messages: UIMessage[];
  sessionId?: string;
  documentIds?: string[];
};

type Citation = {
  documentId: string;
  documentTitle: string;
  pageNumber: number;
  chunkText: string;
  similarity: number;
};

export const POST = withAuth(async (request, { user }) => {
  const { messages, sessionId, documentIds }: RagChatBody = await request.json();

  const userId = user.id;

  // --- Resolve or create session ---
  let activeSessionId = sessionId;

  if (activeSessionId) {
    const existing = await db
      .select({ id: chatSession.id })
      .from(chatSession)
      .where(
        and(eq(chatSession.id, activeSessionId), eq(chatSession.userId, userId))
      )
      .limit(1);

    if (existing.length === 0) {
      return new Response(JSON.stringify({ error: "Session not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }
  } else {
    const firstUserMessage = messages.find((m) => m.role === "user");
    const title =
      firstUserMessage?.parts
        .filter(
          (p): p is Extract<typeof p, { type: "text" }> => p.type === "text"
        )
        .map((p) => p.text)
        .join(" ")
        .slice(0, 100) || "New RAG Chat";

    const [created] = await db
      .insert(chatSession)
      .values({ userId, title })
      .returning({ id: chatSession.id });
    activeSessionId = created.id;
  }

  // --- Extract latest user query for RAG retrieval ---
  const lastUserMessage = messages.at(-1);
  const userQuery = lastUserMessage?.parts
    .filter(
      (p): p is Extract<typeof p, { type: "text" }> => p.type === "text"
    )
    .map((p) => p.text)
    .join(" ");

  // --- Perform vector search ---
  let citations: Citation[] = [];
  let contextBlock = "";

  if (userQuery) {
    const searchResults = await searchChunks({
      query: userQuery,
      documentIds,
      userId,
      limit: 8,
    });

    citations = searchResults.map((r) => ({
      documentId: r.documentId,
      documentTitle: r.documentTitle,
      pageNumber: r.pageNumber,
      chunkText: r.textContent,
      similarity: r.similarity,
    }));

    if (citations.length > 0) {
      const contextParts = citations.map(
        (c, i) =>
          `[Source ${i + 1}] "${c.documentTitle}" — Page ${c.pageNumber}:\n${c.chunkText}`
      );
      contextBlock = contextParts.join("\n\n---\n\n");
    }
  }

  // --- Build system prompt with RAG context ---
  const systemParts: string[] = [
    "You are a helpful assistant that answers questions based on the provided document context.",
    "When answering, cite your sources using [Source N] notation matching the context below.",
    "If the context doesn't contain relevant information, say so honestly.",
    "Be concise, accurate, and helpful.",
  ];

  if (contextBlock) {
    systemParts.push(
      "## Document Context\n\n" + contextBlock
    );
  } else {
    systemParts.push(
      "No document context was found for this query. Answer based on your general knowledge and let the user know you couldn't find relevant document sections."
    );
  }

  // --- Persist user message ---
  if (lastUserMessage && lastUserMessage.role === "user") {
    await db.insert(chatMessage).values({
      sessionId: activeSessionId,
      role: "user",
      parts: lastUserMessage.parts,
    });
  }

  // --- Convert and stream ---
  const modelMessages = await convertToModelMessages(messages);

  const result = streamText({
    model: getModel(),
    system: systemParts.join("\n\n"),
    messages: modelMessages,
    async onFinish({ text }) {
      await db.insert(chatMessage).values({
        sessionId: activeSessionId,
        role: "assistant",
        parts: [{ type: "text", text }],
      });

      await db
        .update(chatSession)
        .set({ updatedAt: new Date() })
        .where(eq(chatSession.id, activeSessionId));
    },
  });

  const response = result.toUIMessageStreamResponse();

  // Append metadata headers
  response.headers.set("X-Session-Id", activeSessionId);
  response.headers.set(
    "X-Rag-Citations",
    encodeURIComponent(JSON.stringify(citations))
  );

  return response;
});
```

### Step 2: Create `src/components/rag/citation-badge.tsx`

```tsx
"use client";

import { memo } from "react";

type CitationBadgeProps = {
  sourceIndex: number;
  documentTitle: string;
  pageNumber: number;
  onClick?: () => void;
};

export const CitationBadge = memo(function CitationBadge({
  sourceIndex,
  documentTitle,
  pageNumber,
  onClick,
}: CitationBadgeProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="inline-flex items-center gap-1 rounded-md bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20 transition-colors hover:bg-blue-100 dark:bg-blue-950 dark:text-blue-300 dark:ring-blue-400/30 dark:hover:bg-blue-900"
      title={`${documentTitle} — Page ${pageNumber}`}
    >
      <span>[{sourceIndex}]</span>
      <span className="max-w-[120px] truncate">{documentTitle}</span>
      <span className="text-blue-500">p.{pageNumber}</span>
    </button>
  );
});
```

### Step 3: Create `src/components/rag/rag-chat.tsx`

```tsx
"use client";

import { useChat } from "@ai-sdk/react";
import { DefaultChatTransport, type UIMessage } from "ai";
import { useId, useRef, useEffect, useCallback, useState, useMemo, memo } from "react";
import { ChatContainer } from "@/components/ai/chat-container";
import { PromptInput } from "@/components/ai/prompt-input";
import { Loader } from "@/components/ai/loader";
import { Message } from "@/components/ai/message";
import { Markdown } from "@/components/ai/markdown";
import { CitationBadge } from "./citation-badge";

type Citation = {
  documentId: string;
  documentTitle: string;
  pageNumber: number;
  chunkText: string;
  similarity: number;
};

type RagChatProps = {
  documentIds?: string[];
  sessionId: string | null;
  onSessionCreated?: (sessionId: string) => void;
  onCitationClick?: (citation: Citation) => void;
};

export function RagChat({
  documentIds,
  sessionId,
  onSessionCreated,
  onCitationClick,
}: RagChatProps) {
  const messageListId = useId();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [input, setInput] = useState("");
  const [citations, setCitations] = useState<Citation[]>([]);

  // Refs to hold latest callbacks without causing transport recreation
  const onSessionCreatedRef = useRef(onSessionCreated);
  onSessionCreatedRef.current = onSessionCreated;
  const sessionIdRef = useRef(sessionId);
  sessionIdRef.current = sessionId;

  const transport = useMemo(
    () =>
      new DefaultChatTransport({
        api: "/api/rag/chat",
        body: { sessionId, documentIds },
        fetch: async (input, init) => {
          const response = await globalThis.fetch(input, init);

          // Extract session ID from headers
          const newSessionId = response.headers.get("X-Session-Id");
          if (newSessionId && !sessionIdRef.current && onSessionCreatedRef.current) {
            onSessionCreatedRef.current(newSessionId);
          }

          // Extract citations from headers
          const citationsHeader = response.headers.get("X-Rag-Citations");
          if (citationsHeader) {
            try {
              const parsed: Citation[] = JSON.parse(
                decodeURIComponent(citationsHeader)
              );
              setCitations(parsed);
            } catch {
              // Ignore parse errors
            }
          }

          return response;
        },
      }),
    [sessionId, documentIds]
  );

  const { messages, sendMessage, status } = useChat({
    transport,
  });

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
    <div className="flex h-full flex-col">
      <ChatContainer ref={scrollRef} className="flex-1 overflow-y-auto p-4">
        {messages.length === 0 && (
          <div className="flex h-full items-center justify-center text-muted-foreground">
            <p>Ask a question about your documents...</p>
          </div>
        )}
        {messages.map((message) => (
          <RagMessage
            key={`${messageListId}-${message.id}`}
            message={message}
            citations={citations}
            onCitationClick={onCitationClick}
          />
        ))}
        {isSubmitting && (
          <div className="flex justify-start p-2">
            <Loader />
          </div>
        )}
      </ChatContainer>

      {/* Citation badges for the latest response */}
      {citations.length > 0 && messages.at(-1)?.role === "assistant" && (
        <div className="flex flex-wrap gap-2 border-t px-4 py-2">
          {citations.map((citation, idx) => (
            <CitationBadge
              key={`${messageListId}-citation-${citation.documentId}-${citation.pageNumber}-${idx}`}
              sourceIndex={idx + 1}
              documentTitle={citation.documentTitle}
              pageNumber={citation.pageNumber}
              onClick={() => onCitationClick?.(citation)}
            />
          ))}
        </div>
      )}

      <div className="border-t p-4">
        <PromptInput
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          onSubmit={handleSend}
          disabled={isStreaming || isSubmitting}
          placeholder="Ask about your documents..."
        />
      </div>
    </div>
  );
}

type RagMessageProps = {
  message: UIMessage;
  citations: Citation[];
  onCitationClick?: (citation: Citation) => void;
};

const RagMessage = memo(function RagMessage({ message, citations, onCitationClick }: RagMessageProps) {
  const isUser = message.role === "user";
  const partId = useId();

  return (
    <Message
      role={message.role}
      className={isUser ? "justify-end" : "justify-start"}
    >
      <div
        className={
          isUser
            ? "rounded-2xl bg-primary px-4 py-2 text-primary-foreground"
            : "max-w-none prose dark:prose-invert"
        }
      >
        {message.parts.map((part, index) => {
          const key = `${partId}-${part.type}-${index}`;

          switch (part.type) {
            case "text":
              return <Markdown key={key}>{part.text}</Markdown>;
            default:
              return null;
          }
        })}
      </div>
    </Message>
  );
});
```

## Usage

### In a Page

```tsx
"use client";

import { useState } from "react";
import { RagChat } from "@/components/rag/rag-chat";

export default function RagChatPage() {
  const [sessionId, setSessionId] = useState<string | null>(null);

  return (
    <div className="h-[calc(100vh-4rem)]">
      <RagChat
        sessionId={sessionId}
        onSessionCreated={setSessionId}
        documentIds={["doc-uuid-1"]} // optional: scope to specific docs
        onCitationClick={(citation) => {
          console.log("Navigate to:", citation.documentTitle, "page", citation.pageNumber);
        }}
      />
    </div>
  );
}
```

### API Usage

```typescript
// RAG chat (with document scope)
const res = await fetch("/api/rag/chat", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    messages: [{ role: "user", parts: [{ type: "text", text: "Summarize the key findings" }] }],
    documentIds: ["doc-uuid-1"],
  }),
});
// Streaming response with X-Session-Id and X-Rag-Citations headers
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/rag/chat` | RAG streaming chat `{ messages, sessionId?, documentIds? }` |

## Acceptance Criteria

- RAG chat retrieves relevant chunks and includes them in the system prompt
- Assistant responses reference sources with `[Source N]` notation
- `X-Rag-Citations` header contains citation metadata (documentId, pageNumber, similarity)
- Citation badges render below the assistant response
- Clicking a citation badge triggers `onCitationClick` callback
- Chat sessions persist in the same `chatSession` / `chatMessage` tables
- Scoped search via `documentIds` limits results to specific documents
- Unauthenticated requests return 401
- `tsc` passes with no errors
- `bun run build` succeeds
