---
name: ai-artifacts
description: Rich artifact panel for AI chat — code, HTML, Mermaid diagrams, tables, and markdown render in a resizable side panel. Use this skill when the user says "add artifacts", "add code preview", "add side panel", "artifact panel", or "rich output".
author: "@mattwoodco"
version: 1.1.0
created: 2026-02-13
updated: 2026-02-18
dependencies: [ai-tools]
---

# AI Artifacts

Experience layer that lets the AI create rich artifacts (syntax-highlighted code, sandboxed HTML, Mermaid diagrams, markdown, and tables) rendered in a resizable side panel alongside the chat.

Artifacts are created via tool calls (`createArtifact`, `updateArtifact`) and stored in React state scoped to the current session. Clicking an artifact reference in a chat message opens the panel and scrolls to that artifact.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `ai-core` skill installed (provides `getModel()`)
- `ai-chat` skill installed (provides chat UI, route pipeline, message renderer)
- `ai-tools` skill installed (provides tool calling framework and `tool-invocation` rendering)

## Installation

```bash
bun add mermaid
```

## What Gets Created

```
src/
├── lib/
│   └── ai/
│       └── tools/
│           └── artifact.ts            # createArtifact + updateArtifact tool definitions
└── components/
    └── ai/
        ├── artifact-panel.tsx         # Resizable right-side panel with artifact list
        └── artifact-renderers.tsx     # Renderers: code, HTML iframe, Mermaid, markdown, table
```

## What Gets Modified

```
src/
├── app/
│   └── (app)/
│       └── chat/
│           └── page.tsx               # Split layout — chat left, artifact panel right
└── components/
    └── ai/
        └── message.tsx                # Artifact refs as clickable cards inside tool-invocation case
```

## Setup Steps

### Step 1: Create `src/lib/ai/tools/artifact.ts`

```typescript
import { tool } from "ai";
import { z } from "zod";

export const artifactTypeSchema = z.enum([
  "code",
  "html",
  "mermaid",
  "table",
  "markdown",
]);

export type ArtifactType = z.infer<typeof artifactTypeSchema>;

export type Artifact = {
  id: string;
  type: ArtifactType;
  title: string;
  content: string;
  language?: string;
  versions: string[];
  createdAt: Date;
};

export const createArtifact = tool({
  description:
    "Create a rich artifact (code, HTML page, Mermaid diagram, table, or markdown document) that renders in the side panel. Use this for any substantial content the user might want to copy, preview, or iterate on.",
  inputSchema: z.object({
    type: artifactTypeSchema.describe(
      "The artifact type: 'code' for source code with syntax highlighting, 'html' for rendered HTML pages, 'mermaid' for diagrams, 'table' for structured data, 'markdown' for formatted documents"
    ),
    title: z
      .string()
      .describe("A short descriptive title for the artifact"),
    content: z
      .string()
      .describe("The full content of the artifact"),
    language: z
      .string()
      .optional()
      .describe(
        "Programming language for syntax highlighting (only used when type is 'code'). Examples: 'typescript', 'python', 'rust', 'sql'"
      ),
  }),
  execute: async ({ type, title, content, language }) => {
    const id = crypto.randomUUID();
    return {
      id,
      type,
      title,
      content,
      language,
      _artifact: true,
    };
  },
});

export const updateArtifact = tool({
  description:
    "Update an existing artifact with new content. Creates a new version so the user can see the change. Use this when the user asks to modify, fix, or improve an existing artifact.",
  inputSchema: z.object({
    id: z
      .string()
      .describe("The ID of the artifact to update"),
    content: z
      .string()
      .describe("The complete updated content (replaces the previous version)"),
    title: z
      .string()
      .optional()
      .describe("Optional new title for the artifact"),
  }),
  execute: async ({ id, content, title }) => {
    return {
      id,
      content,
      title,
      _artifact: true,
      _update: true,
    };
  },
});

export const artifactTools = {
  createArtifact,
  updateArtifact,
} as const;
```

### Step 2: Create `src/components/ai/artifact-renderers.tsx`

```tsx
"use client";

import { useEffect, useRef, useState } from "react";
import dynamic from "next/dynamic";
import { CodeBlock } from "@/components/ai/code-block";
import { Markdown } from "@/components/ai/markdown";

type ArtifactType = "code" | "html" | "mermaid" | "table" | "markdown";

type RendererProps = {
  content: string;
  language?: string;
};

function CodeRenderer({ content, language }: RendererProps) {
  return (
    <div className="overflow-auto rounded-lg border">
      <CodeBlock code={content} language={language ?? "text"} />
    </div>
  );
}

function HtmlRenderer({ content }: RendererProps) {
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [height, setHeight] = useState(400);

  useEffect(() => {
    const iframe = iframeRef.current;
    if (!iframe) return;

    const doc = iframe.contentDocument;
    if (!doc) return;

    doc.open();
    doc.write(content);
    doc.close();

    const resizeObserver = new ResizeObserver(() => {
      const body = doc.body;
      if (body) {
        setHeight(Math.min(body.scrollHeight + 20, 800));
      }
    });

    if (doc.body) {
      resizeObserver.observe(doc.body);
    }

    return () => resizeObserver.disconnect();
  }, [content]);

  return (
    <iframe
      ref={iframeRef}
      title="HTML Preview"
      sandbox="allow-scripts allow-same-origin"
      className="w-full rounded-lg border bg-white"
      style={{ height }}
    />
  );
}

function MermaidRenderer({ content }: RendererProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [svg, setSvg] = useState<string>("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function renderDiagram() {
      try {
        const mermaid = (await import("mermaid")).default;
        mermaid.initialize({
          startOnLoad: false,
          theme: "default",
          securityLevel: "loose",
        });
        const id = `mermaid-${crypto.randomUUID()}`;
        const { svg: rendered } = await mermaid.render(id, content);
        if (!cancelled) {
          setSvg(rendered);
          setError(null);
        }
      } catch (err) {
        if (!cancelled) {
          setError(
            err instanceof Error ? err.message : "Failed to render diagram"
          );
        }
      }
    }

    renderDiagram();
    return () => {
      cancelled = true;
    };
  }, [content]);

  if (error) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
        <p className="font-medium">Mermaid rendering error</p>
        <p className="mt-1">{error}</p>
        <pre className="mt-2 overflow-auto rounded bg-red-100 p-2 text-xs">
          {content}
        </pre>
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      className="flex items-center justify-center overflow-auto rounded-lg border bg-white p-4"
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}

type TableRow = Record<string, string | number | boolean>;

function TableRenderer({ content }: RendererProps) {
  let data: { headers: string[]; rows: TableRow[] };

  try {
    const parsed: unknown = JSON.parse(content);
    if (
      typeof parsed === "object" &&
      parsed !== null &&
      "headers" in parsed &&
      "rows" in parsed
    ) {
      const obj = parsed as { headers: string[]; rows: TableRow[] };
      data = { headers: obj.headers, rows: obj.rows };
    } else if (Array.isArray(parsed) && parsed.length > 0) {
      const rows = parsed as TableRow[];
      const headers = Object.keys(rows[0]);
      data = { headers, rows };
    } else {
      throw new Error("Invalid table format");
    }
  } catch {
    return (
      <div className="rounded-lg border border-yellow-200 bg-yellow-50 p-4 text-sm text-yellow-700">
        <p className="font-medium">Could not parse table data</p>
        <pre className="mt-2 overflow-auto rounded bg-yellow-100 p-2 text-xs">
          {content}
        </pre>
      </div>
    );
  }

  return (
    <div className="overflow-auto rounded-lg border">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b bg-muted/50">
            {data.headers.map((header) => (
              <th
                key={header}
                className="px-4 py-2 text-left font-medium"
              >
                {header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {data.rows.map((row) => {
            const rowKey = data.headers
              .map((h) => String(row[h] ?? ""))
              .join("-");
            return (
              <tr key={rowKey} className="border-b last:border-0">
                {data.headers.map((header) => (
                  <td key={`${rowKey}-${header}`} className="px-4 py-2">
                    {String(row[header] ?? "")}
                  </td>
                ))}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function MarkdownRenderer({ content }: RendererProps) {
  return (
    <div className="prose prose-sm dark:prose-invert max-w-none rounded-lg border p-4">
      <Markdown>{content}</Markdown>
    </div>
  );
}

// Lazy-load MermaidRenderer — it imports the heavy `mermaid` library
const LazyMermaidRenderer = dynamic(
  () => Promise.resolve({ default: MermaidRenderer }),
  { ssr: false, loading: () => <div className="p-4 text-sm text-muted-foreground">Loading diagram...</div> }
);

const renderers: Record<
  ArtifactType,
  React.ComponentType<RendererProps>
> = {
  code: CodeRenderer,
  html: HtmlRenderer,
  mermaid: LazyMermaidRenderer,
  table: TableRenderer,
  markdown: MarkdownRenderer,
};

type ArtifactContentProps = {
  type: ArtifactType;
  content: string;
  language?: string;
};

export function ArtifactContent({
  type,
  content,
  language,
}: ArtifactContentProps) {
  const Renderer = renderers[type] ?? CodeRenderer;
  return <Renderer content={content} language={language} />;
}
```

### Step 3: Create `src/components/ai/artifact-panel.tsx`

```tsx
"use client";

import { useState, useId, useCallback, useRef, useEffect } from "react";
import { ArtifactContent } from "./artifact-renderers";

type ArtifactType = "code" | "html" | "mermaid" | "table" | "markdown";

type Artifact = {
  id: string;
  type: ArtifactType;
  title: string;
  content: string;
  language?: string;
  versions: string[];
  createdAt: Date;
};

type ArtifactPanelProps = {
  artifacts: Artifact[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  onClose: () => void;
  isOpen: boolean;
};

const TYPE_ICONS: Record<ArtifactType, string> = {
  code: "{}",
  html: "<>",
  mermaid: "diamond",
  table: "grid",
  markdown: "doc",
};

const TYPE_LABELS: Record<ArtifactType, string> = {
  code: "Code",
  html: "HTML",
  mermaid: "Diagram",
  table: "Table",
  markdown: "Document",
};

function TypeBadge({ type }: { type: ArtifactType }) {
  return (
    <span className="inline-flex items-center rounded-md bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">
      {TYPE_LABELS[type]}
    </span>
  );
}

function CopyButton({ content }: { content: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(async () => {
    await navigator.clipboard.writeText(content);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, [content]);

  return (
    <button
      type="button"
      onClick={handleCopy}
      className="inline-flex items-center gap-1 rounded-md border px-2 py-1 text-xs text-muted-foreground transition-colors hover:bg-muted"
    >
      {copied ? "Copied" : "Copy"}
    </button>
  );
}

export function ArtifactPanel({
  artifacts,
  selectedId,
  onSelect,
  onClose,
  isOpen,
}: ArtifactPanelProps) {
  const listId = useId();
  const panelRef = useRef<HTMLDivElement>(null);
  const [panelWidth, setPanelWidth] = useState(480);
  const isResizing = useRef(false);

  const selectedArtifact = artifacts.find((a) => a.id === selectedId);

  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      isResizing.current = true;

      const startX = e.clientX;
      const startWidth = panelWidth;

      function onMouseMove(moveEvent: MouseEvent) {
        if (!isResizing.current) return;
        const delta = startX - moveEvent.clientX;
        const newWidth = Math.max(320, Math.min(startWidth + delta, 800));
        setPanelWidth(newWidth);
      }

      function onMouseUp() {
        isResizing.current = false;
        document.removeEventListener("mousemove", onMouseMove);
        document.removeEventListener("mouseup", onMouseUp);
      }

      document.addEventListener("mousemove", onMouseMove);
      document.addEventListener("mouseup", onMouseUp);
    },
    [panelWidth]
  );

  useEffect(() => {
    if (selectedId && panelRef.current) {
      const el = panelRef.current.querySelector(
        `[data-artifact-id="${selectedId}"]`
      );
      if (el) {
        el.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    }
  }, [selectedId]);

  if (!isOpen || artifacts.length === 0) return null;

  return (
    <div
      ref={panelRef}
      className="relative flex h-full flex-col border-l bg-background"
      style={{ width: panelWidth }}
    >
      {/* Resize handle */}
      <div
        role="separator"
        aria-orientation="vertical"
        aria-label="Resize artifact panel"
        aria-valuenow={panelWidth}
        aria-valuemin={320}
        aria-valuemax={800}
        onMouseDown={handleMouseDown}
        className="absolute top-0 left-0 z-10 h-full w-1 cursor-col-resize hover:bg-primary/20 active:bg-primary/30"
      />

      {/* Header */}
      <div className="flex items-center justify-between border-b px-4 py-3">
        <div className="flex items-center gap-2">
          <h2 className="text-sm font-semibold">Artifacts</h2>
          <span className="rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
            {artifacts.length}
          </span>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="rounded-md p-1 text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          aria-label="Close panel"
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
            aria-hidden="true"
          >
            <path d="M18 6 6 18" />
            <path d="m6 6 12 12" />
          </svg>
        </button>
      </div>

      {/* Artifact tabs */}
      <div className="flex gap-1 overflow-x-auto border-b px-2 py-2">
        {artifacts.map((artifact) => (
          <button
            key={`${listId}-tab-${artifact.id}`}
            type="button"
            onClick={() => onSelect(artifact.id)}
            className={`shrink-0 rounded-md px-3 py-1.5 text-xs font-medium transition-colors ${
              selectedId === artifact.id
                ? "bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-muted"
            }`}
          >
            {artifact.title}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-auto p-4">
        {selectedArtifact ? (
          <div data-artifact-id={selectedArtifact.id}>
            <div className="mb-3 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <h3 className="font-medium">
                  {selectedArtifact.title}
                </h3>
                <TypeBadge type={selectedArtifact.type} />
                {selectedArtifact.language && (
                  <span className="text-xs text-muted-foreground">
                    {selectedArtifact.language}
                  </span>
                )}
              </div>
              <div className="flex items-center gap-2">
                {selectedArtifact.versions.length > 1 && (
                  <span className="text-xs text-muted-foreground">
                    v{selectedArtifact.versions.length}
                  </span>
                )}
                <CopyButton content={selectedArtifact.content} />
              </div>
            </div>
            <ArtifactContent
              type={selectedArtifact.type}
              content={selectedArtifact.content}
              language={selectedArtifact.language}
            />
          </div>
        ) : (
          <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
            Select an artifact to preview
          </div>
        )}
      </div>
    </div>
  );
}

export type { Artifact, ArtifactType };
```

### Step 4: Modify `src/components/ai/message.tsx`

Inside the existing `tool-invocation` case (added by ai-tools), add a check for artifact results. The artifact reference renders as a clickable card that opens the artifact panel.

Find this in `src/components/ai/message.tsx`:

```typescript
          case "tool-invocation": {
            return (
              <ToolInvocationCard
                key={`${partId}-${index}`}
                part={part}
              />
            );
          }
```

Replace with:

```typescript
          case "tool-invocation": {
            // [ai-artifacts]: render artifact refs as clickable cards
            if (
              part.state === "output-available" &&
              part.output &&
              typeof part.output === "object" &&
              "_artifact" in part.output
            ) {
              const artifactResult = part.output as {
                id: string;
                type: string;
                title: string;
                _update?: boolean;
              };
              return (
                <ArtifactCard
                  key={`${partId}-${index}`}
                  id={artifactResult.id}
                  type={artifactResult.type}
                  title={artifactResult.title}
                  isUpdate={!!artifactResult._update}
                  onClick={onArtifactClick}
                />
              );
            }
            return (
              <ToolInvocationCard
                key={`${partId}-${index}`}
                part={part}
              />
            );
          }
```

Then add the `ArtifactCard` component and the `onArtifactClick` prop. Add these imports and the component at the bottom of the file:

Find this in `src/components/ai/message.tsx`:

```typescript
import { useId } from "react";
```

Replace with:

```typescript
import { useId, useCallback, memo } from "react";
```

Add the `ArtifactCard` component above the default export (or above the `MessageParts` component):

Find this in `src/components/ai/message.tsx`:

```typescript
function MessageParts({ parts }: { parts: UIMessage["parts"] }) {
```

Replace with:

```typescript
type ArtifactCardProps = {
  id: string;
  type: string;
  title: string;
  isUpdate: boolean;
  onClick?: (id: string) => void;
};

const TYPE_LABELS: Record<string, string> = {
  code: "Code",
  html: "HTML Preview",
  mermaid: "Diagram",
  table: "Table",
  markdown: "Document",
};

const ArtifactCard = memo(function ArtifactCard({ id, type, title, isUpdate, onClick }: ArtifactCardProps) {
  return (
    <button
      type="button"
      onClick={() => onClick?.(id)}
      className="flex w-full items-center gap-3 rounded-lg border bg-muted/50 px-4 py-3 text-left transition-colors hover:bg-muted"
    >
      <div className="flex h-8 w-8 items-center justify-center rounded-md bg-primary/10 text-xs font-bold text-primary">
        {type === "code" ? "{}" : type === "html" ? "<>" : type === "mermaid" ? "M" : type === "table" ? "#" : "D"}
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">{title}</p>
        <p className="text-xs text-muted-foreground">
          {isUpdate ? "Updated" : "Created"} {TYPE_LABELS[type] ?? type}
        </p>
      </div>
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
        className="shrink-0 text-muted-foreground"
        aria-hidden="true"
      >
        <path d="m9 18 6-6-6-6" />
      </svg>
    </button>
  );
});

function MessageParts({ parts }: { parts: UIMessage["parts"] }) {
```

Also update the `MessageParts` component signature to accept and pass `onArtifactClick`:

Find this in `src/components/ai/message.tsx`:

```typescript
function MessageParts({ parts }: { parts: UIMessage["parts"] }) {
  const partId = useId();
```

Replace with:

```typescript
function MessageParts({ parts, onArtifactClick }: { parts: UIMessage["parts"]; onArtifactClick?: (id: string) => void }) {
  const partId = useId();
```

And update the parent component that renders `MessageParts` to pass the prop through:

Find this in `src/components/ai/message.tsx`:

```typescript
        <MessageParts parts={message.parts} />
```

Replace with:

```typescript
        <MessageParts parts={message.parts} onArtifactClick={onArtifactClick} />
```

### Step 5: Modify `src/app/(app)/chat/page.tsx`

Restructure the chat page into a split layout with the chat on the left and the artifact panel on the right. The panel opens when an artifact is created or clicked.

Find this in `src/app/(app)/chat/page.tsx`:

```tsx
"use client";

import { useState, useCallback } from "react";
import { Chat } from "@/components/ai/chat";
import { ChatSidebar } from "@/components/ai/chat-sidebar";
```

Replace with:

```tsx
"use client";

import { useState, useCallback, useRef } from "react";
import { Chat } from "@/components/ai/chat";
import { ChatSidebar } from "@/components/ai/chat-sidebar";
import { ArtifactPanel, type Artifact, type ArtifactType } from "@/components/ai/artifact-panel";
```

Find the return statement that renders the chat layout. Look for:

```tsx
      <div className="flex h-full">
        <ChatSidebar
          currentSessionId={sessionId}
          onSelectSession={handleSelectSession}
          onNewChat={handleNewChat}
        />
        <div className="flex-1">
          <Chat
            sessionId={sessionId}
            onSessionCreated={handleSessionCreated}
          />
        </div>
      </div>
```

Replace with:

```tsx
      <div className="flex h-full">
        <ChatSidebar
          currentSessionId={sessionId}
          onSelectSession={handleSelectSessionWithClear}
          onNewChat={handleNewChatWithClear}
        />
        <div className="flex-1 min-w-0">
          <Chat
            sessionId={sessionId}
            onSessionCreated={handleSessionCreated}
            onArtifactCreated={handleArtifactCreated}
            onArtifactClick={handleArtifactClick}
          />
        </div>
        {/* [ai-artifacts]: side panel */}
        <ArtifactPanel
          artifacts={artifacts}
          selectedId={selectedArtifactId}
          onSelect={handleArtifactClick}
          onClose={() => setArtifactPanelOpen(false)}
          isOpen={artifactPanelOpen}
        />
        {/* [ai-tasks]: add panel tabs here */}
      </div>
```

Add the artifact state management inside the component, before the return. Find:

```tsx
  const [sessionId, setSessionId] = useState<string | undefined>();
```

Replace with:

```tsx
  const [sessionId, setSessionId] = useState<string | undefined>();

  // [ai-artifacts]: artifact state
  const [artifacts, setArtifacts] = useState<Artifact[]>([]);
  const [selectedArtifactId, setSelectedArtifactId] = useState<string | null>(null);
  const [artifactPanelOpen, setArtifactPanelOpen] = useState(false);

  const handleArtifactCreated = useCallback(
    (artifact: {
      id: string;
      type: ArtifactType;
      title: string;
      content: string;
      language?: string;
      _update?: boolean;
    }) => {
      if (artifact._update) {
        setArtifacts((prev) =>
          prev.map((a) =>
            a.id === artifact.id
              ? {
                  ...a,
                  content: artifact.content,
                  title: artifact.title ?? a.title,
                  versions: [...a.versions, artifact.content],
                }
              : a
          )
        );
      } else {
        const newArtifact: Artifact = {
          id: artifact.id,
          type: artifact.type,
          title: artifact.title,
          content: artifact.content,
          language: artifact.language,
          versions: [artifact.content],
          createdAt: new Date(),
        };
        setArtifacts((prev) => [...prev, newArtifact]);
      }
      setSelectedArtifactId(artifact.id);
      setArtifactPanelOpen(true);
    },
    []
  );

  const handleArtifactClick = useCallback((id: string) => {
    setSelectedArtifactId(id);
    setArtifactPanelOpen(true);
  }, []);

  // [ai-artifacts]: clear artifacts on session change
  const originalHandleNewChat = handleNewChat;
  const handleNewChatWithClear = useCallback(() => {
    setArtifacts([]);
    setSelectedArtifactId(null);
    setArtifactPanelOpen(false);
    originalHandleNewChat();
  }, [originalHandleNewChat]);

  const originalHandleSelectSession = handleSelectSession;
  const handleSelectSessionWithClear = useCallback(
    (id: string) => {
      setArtifacts([]);
      setSelectedArtifactId(null);
      setArtifactPanelOpen(false);
      originalHandleSelectSession(id);
    },
    [originalHandleSelectSession]
  );
```

### Step 6: Modify `src/app/api/ai/chat/route.ts`

Register the artifact tools in the route pipeline.

Find this in `src/app/api/ai/chat/route.ts`:

```typescript
  const tools: ToolSet = {};
  // [ai-tools]: spread registered tools here
```

Replace with:

```typescript
  const tools: ToolSet = {};
  // [ai-tools]: spread registered tools here
  // [ai-artifacts]: add createArtifact, updateArtifact
  Object.assign(tools, artifactTools);
```

Add the import at the top of the file. Find:

```typescript
import { allTools } from "@/lib/ai/tools";
```

Replace with:

```typescript
import { allTools } from "@/lib/ai/tools";
import { artifactTools } from "@/lib/ai/tools/artifact";
```

Also append artifact instructions to the system prompt. Find:

```typescript
  const systemParts: string[] = [
    "You are a helpful assistant.",
  ];
```

Replace with:

```typescript
  const systemParts: string[] = [
    "You are a helpful assistant.",
  ];
  // [ai-artifacts]: artifact instructions
  systemParts.push(
    `## Artifacts

When the user asks for code, HTML pages, diagrams, tables, or formatted documents, use the createArtifact tool to render them in the side panel. Choose the appropriate type:

- "code": Source code with syntax highlighting. Always include the language parameter.
- "html": Complete HTML pages with inline CSS/JS. The content must be a full valid HTML document.
- "mermaid": Mermaid diagram syntax (flowcharts, sequence diagrams, etc.).
- "table": JSON data as {"headers": [...], "rows": [{...}, ...]} or as an array of objects.
- "markdown": Rich formatted documents.

Use updateArtifact to modify an existing artifact when the user asks for changes. Always reference the artifact's ID.

Keep your text response brief when creating artifacts — the artifact speaks for itself.`
  );
```

## Usage

Once installed, the AI can create artifacts via tool calls during chat:

- **Code**: "Write a Python function that calculates fibonacci numbers"
- **HTML**: "Create an HTML page with a CSS animation"
- **Mermaid**: "Draw a flowchart of a user authentication process"
- **Table**: "Show a comparison table of JavaScript frameworks"
- **Markdown**: "Write a project README"

The artifact appears in the resizable right panel. Users can:

- Click artifact cards in chat messages to focus the panel
- Copy artifact content with the copy button
- Resize the panel by dragging its left edge
- Close the panel with the X button
- View version history when artifacts are updated

### Handling Artifacts in the Chat Component

The `Chat` component needs to detect artifact tool results and notify the page. In `src/components/ai/chat.tsx`, watch for tool results that contain `_artifact: true` and call `onArtifactCreated`:

```tsx
// In the Chat component props
type ChatProps = {
  sessionId?: string;
  onSessionCreated?: (sessionId: string) => void;
  onArtifactCreated?: (artifact: {
    id: string;
    type: string;
    title: string;
    content: string;
    language?: string;
    _update?: boolean;
  }) => void;
  onArtifactClick?: (id: string) => void;
};

// Inside the Chat component, add a ref to track notified artifact IDs and an effect:
const notifiedArtifactIds = useRef(new Set<string>());

useEffect(() => {
  if (!onArtifactCreated) return;
  for (const msg of messages) {
    for (const part of msg.parts) {
      if (
        part.type === "tool-invocation" &&
        part.state === "output-available" &&
        part.output &&
        typeof part.output === "object" &&
        "_artifact" in part.output
      ) {
        const result = part.output as {
          id: string;
          type: string;
          title: string;
          content: string;
          language?: string;
          _update?: boolean;
        };
        // Deduplicate — only notify once per artifact ID (or per update)
        const dedupeKey = result._update ? `update-${result.id}-${result.content.length}` : result.id;
        if (!notifiedArtifactIds.current.has(dedupeKey)) {
          notifiedArtifactIds.current.add(dedupeKey);
          onArtifactCreated(result);
        }
      }
    }
  }
}, [messages, onArtifactCreated]);
```

## Acceptance Criteria

- Ask "write a Python fibonacci function" -- artifact panel opens with syntax-highlighted code
- Ask "draw a flowchart of a login process" -- Mermaid diagram renders in the panel
- Ask "create an HTML page with a bouncing ball animation" -- sandboxed iframe renders the page
- Ask "show a comparison table of React vs Vue vs Svelte" -- table renders with headers and rows
- Ask "update the code to add error handling" -- artifact version updates in-place, version counter increments
- Panel is resizable by dragging the left edge
- Panel closes when the X button is clicked
- Clicking an artifact card in chat opens the panel and scrolls to that artifact
- Copy button copies artifact content to clipboard
