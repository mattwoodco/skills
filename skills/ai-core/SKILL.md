---
name: ai-core
description: Foundation AI layer — configures AI Gateway provider and exports getModel() for all downstream AI skills. Use this skill when the user says "setup AI", "add AI", "configure AI gateway", or "setup ai-core".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-13
updated: 2026-02-13
dependencies: [env-config]
---

# AI Core

Foundation layer that configures [Vercel AI Gateway](https://gateway.ai.vercel.com/) as the unified provider for 200+ models and exports a single `getModel()` function consumed by all downstream AI skills.

## Prerequisites

- Next.js app with `src/` directory and App Router
- Environment configuration (`env-config` skill) with `src/env.ts`

## Installation

```bash
bun add ai @ai-sdk/gateway
```

## Environment Variables

Add to `.env.local`:

```env
# AI Gateway
AI_GATEWAY_API_KEY=your-gateway-api-key-here
AI_GATEWAY_MODEL=google/gemini-2.5-flash-lite
```

### Load from 1Password

If `AI_GATEWAY_API_KEY` is empty or a placeholder in `.env.local`, load it from 1Password:

```bash
# Check if already set
grep -q "AI_GATEWAY_API_KEY=your-" .env.local 2>/dev/null && echo "Key is placeholder — load from 1Password"

# Load from 1Password (uses env-from-1password skill)
op item get "Dev Environment" --account=my.1password.com --fields label=notesPlain | tr -d '"' > /tmp/op-env.txt
grep "AI_GATEWAY_API_KEY" /tmp/op-env.txt >> .env.local && rm /tmp/op-env.txt
```

Or use the `/env-from-1password` skill to load all keys at once — it writes `AI_GATEWAY_API_KEY` (and other service keys) to `.env.local`.

### Update `src/env.ts`

Add the AI Gateway variables to your environment schema:

#### Modify `src/env.ts`

Add to the `server` object:

```typescript
  server: {
    // ... existing variables
    AI_GATEWAY_API_KEY: z.string().optional(),
    AI_GATEWAY_MODEL: z.string().default("google/gemini-2.5-flash-lite"),
  },
```

Add to the `runtimeEnv` object:

```typescript
  runtimeEnv: {
    // ... existing variables
    AI_GATEWAY_API_KEY: process.env.AI_GATEWAY_API_KEY,
    AI_GATEWAY_MODEL: process.env.AI_GATEWAY_MODEL,
  },
```

## What Gets Created

```
src/
└── lib/
    └── ai.ts          # gateway() provider, getModel()
```

## Setup Steps

### Step 1: Create `src/lib/ai.ts`

```typescript
import { gateway } from "@ai-sdk/gateway";

/**
 * Returns an AI model via AI Gateway.
 *
 * Uses the `AI_GATEWAY_MODEL` env var as the default model.
 * Downstream skills can override by passing a specific modelId
 * (e.g., `getModel("anthropic/claude-sonnet-4")` for reasoning).
 *
 * @param modelId - Optional model identifier in "provider/model" format.
 *                  Defaults to `AI_GATEWAY_MODEL` env var, then `google/gemini-2.5-flash-lite`.
 * @returns A model object compatible with AI SDK's `streamText`, `generateText`, etc.
 */
export function getModel(modelId?: string) {
  return gateway(
    modelId ?? process.env.AI_GATEWAY_MODEL ?? "google/gemini-2.5-flash-lite"
  );
}

/**
 * Returns an embedding model via AI Gateway.
 *
 * @param modelId - Optional embedding model identifier.
 *                  Defaults to `openai/text-embedding-3-small`.
 * @returns An embedding model compatible with AI SDK's `embed()` and `embedMany()`.
 */
export function getEmbeddingModel(modelId?: string) {
  return gateway.textEmbeddingModel(
    modelId ?? "openai/text-embedding-3-small"
  );
}
```

## Usage

```typescript
import { getModel } from "@/lib/ai";
import { streamText, generateText } from "ai";

// Use default model (google/gemini-2.5-flash-lite)
const result = await streamText({
  model: getModel(),
  prompt: "Hello, world!",
});

// Override with a specific model
const reasoning = await generateText({
  model: getModel("anthropic/claude-sonnet-4"),
  prompt: "Explain quantum entanglement step by step.",
});

// Generate embeddings
import { getEmbeddingModel } from "@/lib/ai";
import { embed } from "ai";

const { embedding } = await embed({
  model: getEmbeddingModel(),
  value: "Some text to embed",
});
```

## Available Models via AI Gateway

| Model | Input Cost | Output Cost | Best For |
|-------|-----------|-------------|----------|
| `google/gemini-2.5-flash-lite` | $0.10/M | $0.40/M | Default dev/test, tools, memory |
| `anthropic/claude-sonnet-4` | $3.00/M | $15.00/M | Reasoning, artifacts, quality |
| `openai/gpt-4o-mini` | $0.07/M | $0.30/M | Fast responses alternative |

## Ollama (Local)

To run models locally via Ollama instead of AI Gateway, swap the provider in `src/lib/ai.ts`:

```bash
bun add @ai-sdk/ollama
ollama pull qwen3:8b
```

```typescript
import { ollama } from "@ai-sdk/ollama";

export function getModel() {
  return ollama("qwen3:8b");
}
```

> **`qwen3:8b` is the Ollama model** — best-in-class tool calling at 8B, strong markdown output, and the standard choice for local agentic apps in 2026. No env vars or API keys needed.

For local dev without an AI Gateway account, set `OLLAMA_BASE_URL` in `.env.local` and conditionally switch providers:

```typescript
import { gateway } from "@ai-sdk/gateway";
import { ollama } from "@ai-sdk/ollama";

export function getModel(modelId?: string) {
  if (process.env.OLLAMA_BASE_URL) {
    return ollama("qwen3:8b");
  }
  return gateway(
    modelId ?? process.env.AI_GATEWAY_MODEL ?? "google/gemini-2.5-flash-lite"
  );
}
```

Add to `.env.local` to enable Ollama:

```env
OLLAMA_BASE_URL=http://localhost:11434
```

## Acceptance Criteria

- `tsc` passes with no errors
- `getModel()` returns a valid model object usable with `streamText()` / `generateText()`
- `getModel("anthropic/claude-sonnet-4")` returns a different model than the default
- `getEmbeddingModel()` returns a valid embedding model usable with `embed()`
- `bun run build` succeeds
