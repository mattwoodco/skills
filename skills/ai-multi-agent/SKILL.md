---
name: ai-multi-agent
description: Multi-agent orchestration — N AI agents with distinct personas debate sequentially in real-time. Each agent sees prior agents' output, creating adversarial pressure-testing. Use this skill when the user says "add multi-agent", "ai debate", "agent panel", "multi-agent chat", or "adversarial agents".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
updated: 2026-02-18
dependencies: [ai-chat, ai-core]
---

# AI Multi-Agent

Multi-agent orchestration where N AI agents with distinct personas (Product Manager, QA Engineer, Senior Engineer) debate sequentially in real-time. Each agent sees all prior agents' output in its context, creating a chain of adversarial pressure-testing against feature specifications.

The key innovation: agents run SEQUENTIALLY, not in parallel. PM writes the happy path, QA reads PM's output and pokes holes, Engineer reads both and flags constraints. Each subsequent agent gets all prior agents' outputs in its context. This sequential chain is what creates the adversarial pressure-testing.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `ai-core` skill installed (`getModel()` available at `@/lib/ai`)
- `ai-chat` skill installed (provides chat page, `withAuth` from auth dependency)
- shadcn/ui initialized

## Installation

No additional packages required. Uses `streamText` from the `ai` package (already installed by `ai-core`) and `@phosphor-icons/react` (already installed by `ai-chat`).

## What Gets Created

```
src/
├── lib/
│   └── ai/
│       └── agents/
│           ├── types.ts           # AgentConfig, AgentMessage, DebateRound types
│           ├── registry.ts        # Default agent configs (PM, QA, Engineer) + register/get
│           └── prompts.ts         # System prompt builders per agent role
├── app/
│   └── api/
│       └── ai/
│           └── debate/
│               └── route.ts       # POST — runs sequential agent debate, streams via SSE
└── components/
    └── ai/
        └── multi-agent/
            ├── debate-panel.tsx    # Container: triggers debate, renders agent streams
            ├── agent-message.tsx   # Single agent message with Accept/Dismiss buttons
            └── agent-badge.tsx     # Color-coded agent name badge
```

## What Gets Modified

```
src/app/(app)/chat/page.tsx    # Add debate panel as right column
```

## Comment Slots

- **chat/page.tsx**: `// [ai-multi-agent]: add debate panel` — adds debate panel as a right column in the chat layout

## Setup Steps

### Step 1: Create `src/lib/ai/agents/types.ts`

```typescript
export type AgentRole = "pm" | "qa" | "engineer";

export type AgentConfig = {
  id: string;
  name: string;
  role: AgentRole;
  color: string;
  description: string;
  systemPrompt: string;
};

export type AgentMessage = {
  id: string;
  agentId: string;
  role: AgentRole;
  content: string;
  timestamp: string;
  status: "streaming" | "complete" | "accepted" | "dismissed";
};

export type DebateRound = {
  id: string;
  context: string;
  messages: AgentMessage[];
  createdAt: string;
};

export type DebateStreamEvent =
  | { type: "agent-start"; agentId: string; agentName: string; agentRole: AgentRole; color: string }
  | { type: "text-delta"; agentId: string; text: string }
  | { type: "agent-done"; agentId: string }
  | { type: "debate-done" };
```

### Step 2: Create `src/lib/ai/agents/registry.ts`

```typescript
import type { AgentConfig } from "./types";

const agentRegistry = new Map<string, AgentConfig>();

// --- Default agents ---

agentRegistry.set("pm", {
  id: "pm",
  name: "Product Manager",
  role: "pm",
  color: "#3b82f6",
  description: "Focuses on user value, happy path, prioritization, and acceptance criteria.",
  systemPrompt: `You are a Product Manager reviewing a feature specification. Your job is to:
1. Clarify the user value and happy path
2. Prioritize features by impact
3. Identify missing user stories
4. Suggest acceptance criteria

Respond with 2-4 observations. Each observation starts with a tag:
- [REQUIREMENT]: Something that must be in the spec
- [SUGGESTION]: An improvement that would add value
- [QUESTION]: An ambiguity that needs resolution

Be specific and actionable. Reference the spec text directly.`,
});

agentRegistry.set("qa", {
  id: "qa",
  name: "QA Engineer",
  role: "qa",
  color: "#ef4444",
  description: "Focuses on edge cases, error states, race conditions, and accessibility gaps.",
  systemPrompt: `You are a QA Engineer reviewing a feature specification. Your job is to:
1. Find edge cases the PM missed
2. Identify error states and failure modes
3. Flag race conditions and concurrency issues
4. Check accessibility and internationalization gaps
5. Challenge assumptions with "what if" scenarios

You've read the PM's observations below. Build on them — don't repeat.
Respond with 2-4 observations. Each starts with a tag:
- [EDGE_CASE]: A scenario not covered by the spec
- [ERROR_STATE]: What happens when something fails
- [CONCERN]: A potential problem with the current approach
- [QUESTION]: Something that needs clarification`,
});

agentRegistry.set("engineer", {
  id: "engineer",
  name: "Engineer",
  role: "engineer",
  color: "#22c55e",
  description: "Focuses on technical constraints, implementation approaches, complexity estimates, and dependencies.",
  systemPrompt: `You are a Senior Engineer reviewing a feature specification. Your job is to:
1. Flag technical constraints and feasibility issues
2. Suggest implementation approaches
3. Estimate complexity (S/M/L/XL)
4. Identify dependencies on other systems
5. Note performance implications

You've read both PM and QA observations. Build on them.
Respond with 2-4 observations. Each starts with a tag:
- [CONSTRAINT]: A technical limitation to consider
- [APPROACH]: A recommended implementation strategy
- [COMPLEXITY]: Size estimate with justification
- [DEPENDENCY]: An external system this depends on`,
});

// --- Public API ---

export function getAgent(id: string): AgentConfig | undefined {
  return agentRegistry.get(id);
}

export function getAllAgents(): AgentConfig[] {
  return Array.from(agentRegistry.values());
}

export function registerAgent(config: AgentConfig): void {
  agentRegistry.set(config.id, config);
}
```

### Step 3: Create `src/lib/ai/agents/prompts.ts`

```typescript
import type { AgentConfig } from "./types";

type PriorOutput = {
  agentName: string;
  content: string;
};

/**
 * Builds the full system prompt for an agent, injecting prior agents' outputs
 * so each subsequent agent can reference and build upon earlier observations.
 */
export function buildAgentPrompt(
  agent: AgentConfig,
  priorOutputs: PriorOutput[]
): string {
  if (priorOutputs.length === 0) {
    return agent.systemPrompt.replace("{prior_context}", "");
  }

  const priorContext = priorOutputs
    .map(
      (output) =>
        `--- ${output.agentName}'s observations ---\n${output.content}`
    )
    .join("\n\n");

  const contextBlock = `\n\nPrior observations from other reviewers:\n\n${priorContext}`;

  // If the system prompt contains {prior_context}, replace it.
  // Otherwise, append the context block at the end.
  if (agent.systemPrompt.includes("{prior_context}")) {
    return agent.systemPrompt.replace("{prior_context}", contextBlock);
  }

  return `${agent.systemPrompt}${contextBlock}`;
}
```

### Step 4: Create `src/app/api/ai/debate/route.ts`

```typescript
import { streamText } from "ai";
import { getModel } from "@/lib/ai";
import { withAuth } from "@/lib/auth-guard";
import { getAllAgents } from "@/lib/ai/agents/registry";
import { buildAgentPrompt } from "@/lib/ai/agents/prompts";
import type { DebateStreamEvent } from "@/lib/ai/agents/types";

export const POST = withAuth(async (request, { user: _user }) => {
  const { context }: { context: string } = await request.json();

  if (!context?.trim()) {
    return Response.json({ error: "Context is required" }, { status: 400 });
  }

  const agents = getAllAgents();
  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    async start(controller) {
      const send = (event: DebateStreamEvent) => {
        controller.enqueue(
          encoder.encode(`data: ${JSON.stringify(event)}\n\n`)
        );
      };

      const priorOutputs: Array<{ agentName: string; content: string }> = [];

      for (const agent of agents) {
        send({
          type: "agent-start",
          agentId: agent.id,
          agentName: agent.name,
          agentRole: agent.role,
          color: agent.color,
        });

        const systemPrompt = buildAgentPrompt(agent, priorOutputs);

        const result = streamText({
          model: getModel(),
          system: systemPrompt,
          messages: [{ role: "user", content: context }],
        });

        let fullText = "";
        for await (const chunk of result.textStream) {
          fullText += chunk;
          send({ type: "text-delta", agentId: agent.id, text: chunk });
        }

        priorOutputs.push({ agentName: agent.name, content: fullText });
        send({ type: "agent-done", agentId: agent.id });
      }

      send({ type: "debate-done" });
      controller.close();
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
});
```

### Step 5: Create `src/components/ai/multi-agent/agent-badge.tsx`

```tsx
import type { AgentRole } from "@/lib/ai/agents/types";

type AgentBadgeProps = {
  name: string;
  color: string;
  role: AgentRole;
};

export function AgentBadge({ name, color, role }: AgentBadgeProps) {
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium text-white"
      style={{ backgroundColor: color }}
    >
      <span className="h-1.5 w-1.5 rounded-full bg-white/60" />
      {name}
      <span className="text-white/70">({role.toUpperCase()})</span>
    </span>
  );
}
```

### Step 6: Create `src/components/ai/multi-agent/agent-message.tsx`

```tsx
"use client";

import { memo } from "react";
import { Check, X } from "@phosphor-icons/react";
import { AgentBadge } from "@/components/ai/multi-agent/agent-badge";
import { Loader } from "@/components/ai/loader";
import type { AgentRole } from "@/lib/ai/agents/types";

type AgentMessageProps = {
  agentId: string;
  agentName: string;
  color: string;
  role: AgentRole;
  content: string;
  status: "streaming" | "complete" | "accepted" | "dismissed";
  onAccept: (agentId: string, content: string, role: AgentRole) => void;
  onDismiss: (agentId: string) => void;
};

const TAG_COLORS: Record<string, string> = {
  REQUIREMENT: "bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300",
  SUGGESTION: "bg-purple-100 text-purple-700 dark:bg-purple-900/40 dark:text-purple-300",
  QUESTION: "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300",
  EDGE_CASE: "bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300",
  ERROR_STATE: "bg-orange-100 text-orange-700 dark:bg-orange-900/40 dark:text-orange-300",
  CONCERN: "bg-rose-100 text-rose-700 dark:bg-rose-900/40 dark:text-rose-300",
  CONSTRAINT: "bg-slate-100 text-slate-700 dark:bg-slate-900/40 dark:text-slate-300",
  APPROACH: "bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300",
  COMPLEXITY: "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/40 dark:text-yellow-300",
  DEPENDENCY: "bg-indigo-100 text-indigo-700 dark:bg-indigo-900/40 dark:text-indigo-300",
};

function highlightTags(text: string) {
  // Match tags like [CONCERN], [SUGGESTION], etc.
  const tagRegex = /\[([A-Z_]+)\]/g;
  const parts: Array<{ type: "text"; value: string } | { type: "tag"; value: string }> = [];
  let lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = tagRegex.exec(text)) !== null) {
    if (match.index > lastIndex) {
      parts.push({ type: "text", value: text.slice(lastIndex, match.index) });
    }
    parts.push({ type: "tag", value: match[1] });
    lastIndex = match.index + match[0].length;
  }

  if (lastIndex < text.length) {
    parts.push({ type: "text", value: text.slice(lastIndex) });
  }

  return parts;
}

export const AgentMessage = memo(function AgentMessage({
  agentId,
  agentName,
  color,
  role,
  content,
  status,
  onAccept,
  onDismiss,
}: AgentMessageProps) {
  const highlighted = highlightTags(content);

  return (
    <div
      className={`rounded-lg border p-4 transition-opacity ${
        status === "dismissed" ? "opacity-40" : "opacity-100"
      }`}
      style={{ borderLeftColor: color, borderLeftWidth: "3px" }}
    >
      <div className="mb-2 flex items-center justify-between">
        <AgentBadge name={agentName} color={color} role={role} />

        <div className="flex items-center gap-1">
          {status === "streaming" && <Loader className="mr-2" />}

          {status === "accepted" && (
            <span className="inline-flex items-center gap-1 rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700 dark:bg-green-900/40 dark:text-green-300">
              <Check className="h-3 w-3" />
              Accepted
            </span>
          )}

          {status === "complete" && (
            <>
              <button
                type="button"
                onClick={() => onAccept(agentId, content, role)}
                className="inline-flex items-center gap-1 rounded-md bg-green-100 px-2 py-1 text-xs font-medium text-green-700 transition-colors hover:bg-green-200 dark:bg-green-900/40 dark:text-green-300 dark:hover:bg-green-900/60"
              >
                <Check className="h-3 w-3" />
                Accept
              </button>
              <button
                type="button"
                onClick={() => onDismiss(agentId)}
                className="inline-flex items-center gap-1 rounded-md bg-muted px-2 py-1 text-xs font-medium text-muted-foreground transition-colors hover:bg-muted/80"
              >
                <X className="h-3 w-3" />
                Dismiss
              </button>
            </>
          )}
        </div>
      </div>

      <div className="whitespace-pre-wrap text-sm leading-relaxed">
        {highlighted.map((part, idx) => {
          const partKey = `${agentId}-part-${part.type}-${idx}`;
          if (part.type === "tag") {
            const colorClass = TAG_COLORS[part.value] ?? "bg-gray-100 text-gray-700";
            return (
              <span
                key={partKey}
                className={`inline-block rounded px-1.5 py-0.5 text-xs font-semibold ${colorClass}`}
              >
                {part.value}
              </span>
            );
          }
          return <span key={partKey}>{part.value}</span>;
        })}

        {status === "streaming" && (
          <span className="ml-1 inline-block h-4 w-1 animate-pulse bg-foreground/50" />
        )}
      </div>
    </div>
  );
});
```

### Step 7: Create `src/components/ai/multi-agent/debate-panel.tsx`

```tsx
"use client";

import { useState, useCallback, useId, useRef } from "react";
import { Lightning, ArrowClockwise } from "@phosphor-icons/react";
import { AgentMessage } from "@/components/ai/multi-agent/agent-message";
import { Loader } from "@/components/ai/loader";
import type {
  AgentRole,
  AgentMessage as AgentMessageType,
  DebateStreamEvent,
} from "@/lib/ai/agents/types";

type DebatePanelProps = {
  context: string;
  onAcceptObservation: (text: string, agentRole: string) => void;
};

type AgentState = {
  agentId: string;
  agentName: string;
  color: string;
  role: AgentRole;
  content: string;
  status: AgentMessageType["status"];
};

export function DebatePanel({ context, onAcceptObservation }: DebatePanelProps) {
  const listId = useId();
  const [agents, setAgents] = useState<Record<string, AgentState>>({});
  const [agentOrder, setAgentOrder] = useState<string[]>([]);
  const [debateStatus, setDebateStatus] = useState<
    "idle" | "running" | "complete"
  >("idle");
  const abortRef = useRef<AbortController | null>(null);

  const startDebate = useCallback(async () => {
    if (!context.trim()) return;

    // Abort any previous debate
    if (abortRef.current) {
      abortRef.current.abort();
    }

    const controller = new AbortController();
    abortRef.current = controller;

    setAgents({});
    setAgentOrder([]);
    setDebateStatus("running");

    try {
      const response = await fetch("/api/ai/debate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ context }),
        signal: controller.signal,
      });

      if (!response.ok || !response.body) {
        setDebateStatus("idle");
        return;
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });

        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";

        for (const line of lines) {
          if (!line.startsWith("data: ")) continue;
          const json = line.slice(6).trim();
          if (!json) continue;

          const event = JSON.parse(json) as DebateStreamEvent;

          switch (event.type) {
            case "agent-start":
              setAgents((prev) => ({
                ...prev,
                [event.agentId]: {
                  agentId: event.agentId,
                  agentName: event.agentName,
                  color: event.color,
                  role: event.agentRole,
                  content: "",
                  status: "streaming",
                },
              }));
              setAgentOrder((prev) =>
                prev.includes(event.agentId)
                  ? prev
                  : [...prev, event.agentId]
              );
              break;

            case "text-delta":
              setAgents((prev) => {
                const existing = prev[event.agentId];
                if (!existing) return prev;
                return {
                  ...prev,
                  [event.agentId]: {
                    ...existing,
                    content: existing.content + event.text,
                  },
                };
              });
              break;

            case "agent-done":
              setAgents((prev) => {
                const existing = prev[event.agentId];
                if (!existing) return prev;
                return {
                  ...prev,
                  [event.agentId]: {
                    ...existing,
                    status: "complete",
                  },
                };
              });
              break;

            case "debate-done":
              setDebateStatus("complete");
              break;
          }
        }
      }
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        return;
      }
      setDebateStatus("idle");
    }
  }, [context]);

  const handleAccept = useCallback(
    (agentId: string, content: string, role: AgentRole) => {
      setAgents((prev) => {
        const existing = prev[agentId];
        if (!existing) return prev;
        return {
          ...prev,
          [agentId]: { ...existing, status: "accepted" },
        };
      });
      onAcceptObservation(content, role);
    },
    [onAcceptObservation]
  );

  const handleDismiss = useCallback((agentId: string) => {
    setAgents((prev) => {
      const existing = prev[agentId];
      if (!existing) return prev;
      return {
        ...prev,
        [agentId]: { ...existing, status: "dismissed" },
      };
    });
  }, []);

  return (
    <div className="flex h-full flex-col border-l bg-muted/10">
      <div className="flex items-center justify-between border-b px-4 py-3">
        <h2 className="text-sm font-semibold">Agent Debate</h2>

        {debateStatus === "idle" && (
          <button
            type="button"
            onClick={startDebate}
            disabled={!context.trim()}
            className="inline-flex items-center gap-1.5 rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-50"
          >
            <Lightning className="h-3.5 w-3.5" />
            Start Debate
          </button>
        )}

        {debateStatus === "running" && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <Loader />
            <span>Debate in progress...</span>
          </div>
        )}

        {debateStatus === "complete" && (
          <button
            type="button"
            onClick={startDebate}
            disabled={!context.trim()}
            className="inline-flex items-center gap-1.5 rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-50"
          >
            <ArrowClockwise className="h-3.5 w-3.5" />
            New Round
          </button>
        )}
      </div>

      <div className="flex-1 space-y-4 overflow-y-auto p-4">
        {debateStatus === "idle" && agentOrder.length === 0 && (
          <div className="flex h-full items-center justify-center">
            <p className="text-center text-sm text-muted-foreground">
              Paste or type spec text in the chat, then click
              <br />
              <strong>Start Debate</strong> to begin agent review.
            </p>
          </div>
        )}

        {agentOrder.map((agentId) => {
          const agent = agents[agentId];
          if (!agent) return null;

          return (
            <AgentMessage
              key={`${listId}-${agentId}`}
              agentId={agent.agentId}
              agentName={agent.agentName}
              color={agent.color}
              role={agent.role}
              content={agent.content}
              status={agent.status}
              onAccept={handleAccept}
              onDismiss={handleDismiss}
            />
          );
        })}

        {debateStatus === "complete" && (
          <div className="rounded-lg border border-dashed p-3 text-center text-xs text-muted-foreground">
            Debate complete. Accept or dismiss observations above, then click{" "}
            <strong>New Round</strong> to re-run with updated context.
          </div>
        )}
      </div>
    </div>
  );
}
```

### Step 8: Modify `src/app/(app)/chat/page.tsx`

Add the debate panel as a right column in the chat layout.

Find this in `src/app/(app)/chat/page.tsx`:

```typescript
import { Chat } from "@/components/ai/chat";
import { ChatSidebar } from "@/components/ai/chat-sidebar";
```

Replace with:

```typescript
import { Chat } from "@/components/ai/chat";
import { ChatSidebar } from "@/components/ai/chat-sidebar";
import { DebatePanel } from "@/components/ai/multi-agent/debate-panel";
```

Then add state for debate context. Find this in `src/app/(app)/chat/page.tsx`:

```typescript
  const [refreshKey, setRefreshKey] = useState(0);
```

Replace with:

```typescript
  const [refreshKey, setRefreshKey] = useState(0);
  const [debateContext, setDebateContext] = useState("");
```

Then add the debate panel and an input area for spec context. Find this in `src/app/(app)/chat/page.tsx`:

```typescript
      <main className="flex-1">
        <Chat
          key={activeSessionId ?? "new"}
          sessionId={activeSessionId}
          onSessionCreated={handleSessionCreated}
        />
      </main>
    </div>
```

Replace with:

```typescript
      <main className="flex-1">
        <Chat
          key={activeSessionId ?? "new"}
          sessionId={activeSessionId}
          onSessionCreated={handleSessionCreated}
        />
      </main>

      {/* [ai-multi-agent]: add debate panel */}
      <aside className="w-[420px] shrink-0">
        <div className="flex h-full flex-col">
          <div className="border-b border-l px-4 py-2">
            <textarea
              value={debateContext}
              onChange={(e) => setDebateContext(e.target.value)}
              placeholder="Paste spec text for agent debate..."
              className="w-full resize-none rounded-md border bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
              rows={3}
            />
          </div>
          <DebatePanel
            context={debateContext}
            onAcceptObservation={(text, role) => {
              console.log(`Accepted from ${role}:`, text);
            }}
          />
        </div>
      </aside>
    </div>
```

## Usage

### Triggering a Debate

1. Navigate to `/chat` in your app.
2. Paste or type your feature specification text into the debate context textarea on the right panel.
3. Click **Start Debate**. The PM agent streams first, then QA reads PM's output and responds, then Engineer reads both and responds.

### Accepting or Dismissing Observations

- Click **Accept** on an observation to mark it as accepted. The `onAcceptObservation` callback fires with the full observation text and the agent's role.
- Click **Dismiss** to dim the observation and de-prioritize it.

### Running Another Round

After a debate completes, update the spec context (incorporating accepted observations) and click **New Round** to re-trigger the sequential debate with the updated text.

### Registering Custom Agents

```typescript
import { registerAgent } from "@/lib/ai/agents/registry";

registerAgent({
  id: "security",
  name: "Security Reviewer",
  role: "engineer", // Uses engineer role type
  color: "#a855f7",
  description: "Focuses on security vulnerabilities, auth gaps, and data exposure.",
  systemPrompt: `You are a Security Engineer reviewing a feature specification. Your job is to:
1. Identify authentication and authorization gaps
2. Flag data exposure and PII risks
3. Check for injection vectors and input validation
4. Review third-party dependency risks

Respond with 2-4 observations. Each starts with a tag:
- [VULNERABILITY]: A security weakness
- [RISK]: A potential data exposure
- [MITIGATION]: A recommended security control
- [QUESTION]: Something that needs security clarification

{prior_context}`,
});
```

### Customizing Agent Prompts

Each agent's `systemPrompt` field in the registry can be updated directly:

```typescript
import { getAgent, registerAgent } from "@/lib/ai/agents/registry";

const pm = getAgent("pm");
if (pm) {
  registerAgent({
    ...pm,
    systemPrompt: `${pm.systemPrompt}\n\nAdditional context: Focus on mobile-first user stories.`,
  });
}
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/ai/debate` | Run a sequential multi-agent debate, streaming via SSE |

### Request Body

```json
{
  "context": "Your feature specification text here..."
}
```

### SSE Event Types

| Event Type | Fields | Description |
|------------|--------|-------------|
| `agent-start` | `agentId`, `agentName`, `agentRole`, `color` | Signals a new agent is about to stream |
| `text-delta` | `agentId`, `text` | Incremental text chunk from the current agent |
| `agent-done` | `agentId` | Signals the current agent has finished |
| `debate-done` | _(none)_ | All agents have completed the debate round |

## Acceptance Criteria

- Click "Start Debate" with spec text -- PM agent streams first, then QA, then Engineer
- Each agent's response appears in its color-coded lane (blue for PM, red for QA, green for Engineer)
- QA agent's response references PM's observations
- Engineer agent's response references both PM and QA
- Click "Accept" on an observation -- status changes to "accepted", callback fires
- Click "Dismiss" -- observation dims
- "New Round" button re-triggers debate with updated context
- Agents are configurable via registry
- Custom agents can be registered via `registerAgent()`
- `tsc` passes with no errors
- `bun run build` succeeds
