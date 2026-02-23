---
name: workflow
description: Durable AI agent infrastructure — sets up Workflow DevKit with resilient workflows, streaming, and an extensible DurableAgent chat endpoint. Use this skill when the user says "add workflow", "setup workflow", "add durable agents", or "setup durable AI".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-13
updated: 2026-02-13
dependencies: [create-next]
---

# Workflow DevKit

Durable AI agent infrastructure using [Workflow DevKit](https://useworkflow.dev). Workflows and steps survive crashes, redeploys, and infrastructure failures. Every LLM call and tool invocation is persisted, retried on failure, and observable via a local dashboard.

## Prerequisites

- Next.js app with `src/` directory and App Router
- Node.js 18+
- An AI provider API key (e.g. `OPENAI_API_KEY`)

## Installation

```bash
bun add workflow @workflow/ai ai
```

## Configuration

### Step 1: Update `next.config.ts`

Wrap your Next.js config with `withWorkflow()` to enable the `"use workflow"` and `"use step"` directives.

Find this:

```typescript
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
```

Replace with:

```typescript
import { withWorkflow } from "workflow/next";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
```

Then find the bottom of the file where the config is exported. Find:

```typescript
export default nextConfig;
```

Replace with:

```typescript
export default withWorkflow(nextConfig);
```

### Step 2: Add TypeScript plugin (optional but recommended)

In `tsconfig.json`, add the workflow plugin for IntelliSense on directives.

Find:

```json
"compilerOptions": {
```

Add after the opening brace of `compilerOptions`:

```json
    "plugins": [{ "name": "workflow" }],
```

### Step 3: Update middleware (if you have one)

If your project has a `middleware.ts`, update the matcher to exclude workflow internal routes.

Find the `matcher` config array and add `"/((?!.well-known/workflow).*)` to exclude workflow paths. If no middleware exists, skip this step.

## What Gets Created

```
src/
├── workflows/
│   └── chat/
│       ├── workflow.ts          # DurableAgent chat workflow
│       └── tools.ts             # Durable tool definitions (with comment slots)
├── app/
│   └── api/
│       └── ai/
│           └── chat/
│               ├── route.ts     # POST — start workflow, stream response
│               └── [runId]/
│                   └── stream/
│                       └── route.ts  # GET — reconnect to existing run
└── lib/
    └── workflow-model.ts        # Model configuration helper
```

## Setup Steps

### Step 4: Create `src/lib/workflow-model.ts`

DurableAgent accepts either a gateway model string (e.g. `"openai/gpt-4o-mini"`) or a factory function returning a provider model. We use the string approach which works with both the Vercel AI Gateway and direct provider keys.

```typescript
export function getWorkflowModel() {
  return "openai/gpt-4o-mini";
}
```

### Step 5: Create `src/workflows/chat/tools.ts`

Durable tools are step functions that automatically retry on failure. Each tool gets full Node.js access inside `"use step"`.

```typescript
import { z } from "zod";
import { tool } from "ai";

// --- BASE TOOLS ---

export const getWeather = tool({
  description: "Get the current weather for a location",
  inputSchema: z.object({
    location: z.string().describe("City name or coordinates"),
  }),
  execute: async ({ location }) => {
    "use step";
    // Replace with a real weather API call
    return {
      location,
      temperature: 72,
      condition: "sunny",
      humidity: 45,
    };
  },
});

// [workflow-tools]: add more durable tools here

// --- TOOL REGISTRY ---
// Downstream skills add tools to this object.

export const allTools = {
  getWeather,
  // [workflow-tools]: register additional tools here
};
```

### Step 6: Create `src/workflows/chat/workflow.ts`

This is the core durable chat workflow. Every LLM call and tool invocation is persisted as a step.

```typescript
import { DurableAgent } from "@workflow/ai/agent";
import type { UIMessageChunk } from "ai";
import { getWritable } from "workflow";
import type { ModelMessage } from "ai";
import { getWorkflowModel } from "@/lib/workflow-model";
import { allTools } from "./tools";

export async function chatWorkflow(messages: ModelMessage[]) {
  "use workflow";

  const writable = getWritable<UIMessageChunk>();

  // --- SYSTEM PROMPT (extensible) ---
  const systemParts: string[] = [
    "You are a helpful assistant. Be concise and clear in your responses.",
  ];
  // [workflow-system]: append additional system prompt context here

  const agent = new DurableAgent({
    model: getWorkflowModel(),
    system: systemParts.join("\n\n"),
    tools: allTools,
  });

  await agent.stream({ messages, writable });
}
```

### Step 7: Create `src/app/api/ai/chat/route.ts`

The API route starts the workflow and returns a streaming response. It also exposes the `runId` so the client can reconnect if the connection drops.

```typescript
import { start } from "workflow/api";
import { type UIMessage, convertToModelMessages, createUIMessageStreamResponse } from "ai";
import { chatWorkflow } from "@/workflows/chat/workflow";

export async function POST(req: Request) {
  const { messages }: { messages: UIMessage[] } = await req.json();

  const modelMessages = await convertToModelMessages(messages);
  const run = await start(chatWorkflow, [modelMessages]);

  return createUIMessageStreamResponse({
    stream: run.readable,
    headers: {
      "x-workflow-run-id": run.runId,
    },
  });
}
```

### Step 8: Create `src/app/api/ai/chat/[runId]/stream/route.ts`

This reconnection endpoint lets clients resume a stream after a network interruption.

```typescript
import { getRun } from "workflow/api";

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ runId: string }> }
) {
  const { runId } = await params;
  const run = await getRun(runId);

  return new Response(run.getReadable(), {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
      "x-workflow-run-id": runId,
    },
  });
}
```

## Environment Variables

Add to `.env.local`. The model string format `"provider/model"` routes through the Vercel AI Gateway when deployed, or directly to the provider locally:

```
OPENAI_API_KEY=sk-...
```

To use a different provider, change the model string in `src/lib/workflow-model.ts`:

- `"openai/gpt-4o-mini"` — OpenAI (requires `OPENAI_API_KEY`)
- `"anthropic/claude-sonnet-4-5-20250929"` — Anthropic (requires `ANTHROPIC_API_KEY`)
- `"bedrock/claude-haiku-4-5-20251001-v1"` — AWS Bedrock

For Vercel AI Gateway in production, set:

```
GATEWAY_API_KEY=...
```

## Usage

### Start the dev server

```bash
bun run dev
```

The Local World activates automatically — workflow data is stored in `.workflow-data/` and steps process synchronously.

### Inspect workflows

```bash
npx workflow web
```

Opens the observability dashboard showing all runs, step traces, retries, and data flow.

```bash
npx workflow inspect runs
```

Lists all workflow runs from the CLI.

### Add `.workflow-data/` to `.gitignore`

```
.workflow-data/
```

### Test with curl

```bash
curl -X POST http://localhost:3000/api/ai/chat \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is the weather in San Francisco?","parts":[{"type":"text","text":"What is the weather in San Francisco?"}],"id":"msg-1"}]}'
```

### Programmatic usage (from other API routes or server code)

```typescript
import { start, getRun } from "workflow/api";
import { chatWorkflow } from "@/workflows/chat/workflow";
import type { ModelMessage } from "ai";

// Fire and forget
const run = await start(chatWorkflow, [messages]);
console.log("Run started:", run.runId);

// Wait for completion
const result = await run.returnValue;

// Stream response
const response = new Response(run.readable);

// Check status later
const existingRun = await getRun(runId);
const status = await existingRun.status; // "running" | "completed" | "failed"
```

### Client-side integration (with @ai-sdk/react)

```typescript
"use client";

import { useChat, DefaultChatTransport } from "@ai-sdk/react";

const transport = new DefaultChatTransport({
  api: "/api/ai/chat",
});

export function Chat() {
  const { messages, sendMessage, input, setInput, status } = useChat({
    transport,
    onResponse(response) {
      const runId = response.headers.get("x-workflow-run-id");
      if (runId) {
        // Store runId for reconnection
        sessionStorage.setItem("active-run-id", runId);
      }
    },
  });

  // ... render messages and input
}
```

### Resumable streams (reconnection after network drop)

```typescript
import { WorkflowChatTransport } from "@workflow/ai/react";

const transport = new WorkflowChatTransport({
  api: "/api/ai/chat",
  prepareReconnectToStreamRequest: ({ api }) => {
    const runId = sessionStorage.getItem("active-run-id");
    return { api: `/api/ai/chat/${runId}/stream` };
  },
});
```

## Adding Custom Workflows

Create new workflows anywhere in `src/workflows/`. Each workflow file uses the `"use workflow"` directive, and each step uses `"use step"`.

```typescript
// src/workflows/order-processing/workflow.ts
import { sleep } from "workflow";

export async function processOrder(orderId: string) {
  "use workflow";

  const order = await fetchOrder(orderId);
  const payment = await chargePayment(order);

  // Sleep without consuming resources
  await sleep("24h");

  await sendFollowUpEmail(order);
  return { orderId, status: "completed" };
}

async function fetchOrder(orderId: string) {
  "use step";
  const res = await fetch(`https://api.example.com/orders/${orderId}`);
  return res.json();
}

async function chargePayment(order: { id: string; amount: number }) {
  "use step";
  // Retries automatically up to 3 times on failure
  return { chargeId: "ch_123", amount: order.amount };
}

async function sendFollowUpEmail(order: { id: string }) {
  "use step";
  // Send email via your provider
  return { sent: true };
}
```

Wire it to an API route:

```typescript
// src/app/api/orders/process/route.ts
import { start } from "workflow/api";
import { processOrder } from "@/workflows/order-processing/workflow";

export async function POST(req: Request) {
  const { orderId } = await req.json();
  const run = await start(processOrder, [orderId]);
  return Response.json({ runId: run.runId, status: "started" });
}
```

## Comment Slot Reference

Downstream skills extend the workflow by inserting code at these marked positions:

### In `tools.ts`

| Comment Slot | Purpose |
|---|---|
| `// [workflow-tools]: add more durable tools here` | Define new tool functions |
| `// [workflow-tools]: register additional tools here` | Add tools to the `allTools` registry |

### In `workflow.ts`

| Comment Slot | Purpose |
|---|---|
| `// [workflow-system]: append additional system prompt context here` | Inject system prompt context |

## Key Concepts

| Concept | Description |
|---|---|
| `"use workflow"` | Marks a function as a durable workflow (sandboxed, deterministic) |
| `"use step"` | Marks a function as a step (full Node.js, auto-retry, persisted) |
| `start()` | Enqueues a workflow and returns a `Run` object immediately |
| `getRun()` | Retrieves an existing run by ID for status checks or reconnection |
| `getWritable()` | Gets a persistent writable stream from within a step |
| `sleep()` | Pauses workflow without consuming resources |
| `DurableAgent` | Wraps AI SDK agent with durable LLM calls and tool invocations |
| Local World | Dev mode — filesystem storage in `.workflow-data/`, synchronous processing |
| Vercel World | Production — managed storage, queuing, scaling (zero config on Vercel) |

## Deployment

### Local Development

No configuration needed. The Local World activates automatically.

### Vercel

Deploy as normal — the Vercel World activates automatically:

```bash
vercel deploy
```

### Self-Hosted (Postgres)

```bash
bun add @workflow-worlds/postgres
```

Set environment variables:

```
WORKFLOW_TARGET_WORLD=@workflow-worlds/postgres
DATABASE_URL=postgres://...
```

## Acceptance Criteria

- `bun run build` succeeds with no errors
- `tsc` passes with no type errors
- POST to `/api/ai/chat` returns a streaming response
- The `x-workflow-run-id` header is present on chat responses
- `npx workflow web` opens the observability dashboard
- `.workflow-data/` is created during local development
- Tools defined with `"use step"` appear in the workflow dashboard as discrete steps
- GET to `/api/ai/chat/[runId]/stream` reconnects to an existing run
