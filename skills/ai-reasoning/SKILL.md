---
name: ai-reasoning
description: Extended thinking display with collapsible UI. Adds a reasoning toggle that switches to Claude for chain-of-thought, rendered as a collapsible accordion. Use this skill when the user says "add reasoning", "extended thinking", "chain of thought", or "thinking mode".
author: "@mattwoodco"
version: 2.0.1
created: 2026-02-13
updated: 2026-02-13
dependencies: [ai-chat]
---

# AI Reasoning Skill

Enables extended thinking (chain-of-thought) display with a collapsible accordion UI. When reasoning is toggled on, the model switches to `anthropic/claude-sonnet-4` with thinking enabled, and the reasoning trace renders as a collapsed "Thinking..." block above the response.

## Prerequisites

- `ai-chat` skill applied (provides `route.ts` with comment slots, `message.tsx` with part switch, `chat.tsx` with input area)
- `ai-core` skill applied (provides `getModel()`)

## Installation

No additional packages required. Uses `providerOptions` from the `ai` package (already installed by `ai-core`).

## What Gets Created

```
src/
└── components/
    └── ai/
        └── reasoning.tsx          # Collapsible reasoning accordion component
```

Plus modifications to:
```
src/app/api/ai/chat/route.ts      # MODIFIED — add providerOptions for thinking
src/components/ai/message.tsx      # MODIFIED — add reasoning case
src/components/ai/chat.tsx         # MODIFIED — add reasoning toggle + pass flag
```

## Comment Slots

- **route.ts**: `// [ai-reasoning]: add anthropic.thinking config here` — injects `providerOptions` for extended thinking
- **message.tsx**: `// [ai-reasoning]: add case "reasoning" here` — adds `ReasoningBlock` rendering in the part switch

## Setup Steps

### Step 1: Create `src/components/ai/reasoning.tsx`

```typescript
"use client";

import { memo, useState } from "react";
import { CaretDown, CaretRight, Brain } from "@phosphor-icons/react";

interface ReasoningBlockProps {
  reasoning: string;
}

export const ReasoningBlock = memo(function ReasoningBlock({ reasoning }: ReasoningBlockProps) {
  const [isExpanded, setIsExpanded] = useState(false);

  const tokenEstimate = Math.ceil(reasoning.length / 4);

  return (
    <div className="my-2 rounded-lg border border-amber-200 bg-amber-50 text-sm dark:border-amber-900 dark:bg-amber-950/30">
      <button
        type="button"
        onClick={() => setIsExpanded((prev) => !prev)}
        className="flex w-full items-center gap-2 px-3 py-2 text-left hover:bg-amber-100/80 dark:hover:bg-amber-950/50 transition-colors"
      >
        <Brain className="h-4 w-4 text-amber-600 dark:text-amber-400" />
        <span className="font-medium text-amber-800 dark:text-amber-300">Thinking...</span>
        <span className="ml-auto rounded-full bg-amber-200 px-2 py-0.5 text-xs font-medium text-amber-700 dark:bg-amber-900 dark:text-amber-300">
          ~{tokenEstimate.toLocaleString()} tokens
        </span>
        {isExpanded ? (
          <CaretDown className="h-4 w-4 text-amber-600 dark:text-amber-400" />
        ) : (
          <CaretRight className="h-4 w-4 text-amber-600 dark:text-amber-400" />
        )}
      </button>
      {isExpanded && (
        <div className="border-t border-amber-200 px-3 py-2 dark:border-amber-900">
          <pre className="whitespace-pre-wrap text-xs text-amber-900 dark:text-amber-200 leading-relaxed">
            {reasoning}
          </pre>
        </div>
      )}
    </div>
  );
});
```

### Step 2: Modify `src/app/api/ai/chat/route.ts`

Add the reasoning toggle logic at the `// [ai-reasoning]` comment slot.

First, update the request body destructuring.

Find this in `src/app/api/ai/chat/route.ts`:

```typescript
  const {
    messages,
    sessionId,
  }: { messages: UIMessage[]; sessionId?: string } = await request.json();
```

Replace with:

```typescript
  const {
    messages,
    sessionId,
    reasoning,
  }: { messages: UIMessage[]; sessionId?: string; reasoning?: boolean } = await request.json();
```

Then add the provider options configuration.

Find this in `src/app/api/ai/chat/route.ts`:

```typescript
  let providerOptions: Record<string, Record<string, JSONValue>> | undefined;
  // [ai-reasoning]: add anthropic.thinking config here
```

Replace with:

```typescript
  let providerOptions: Record<string, Record<string, JSONValue>> | undefined;
  // [ai-reasoning]: add anthropic.thinking config here
  if (reasoning) {
    providerOptions = {
      anthropic: {
        thinking: { type: "enabled", budgetTokens: 5000 },
      },
    };
  }
```

Then update the `streamText` call to use the reasoning model when reasoning is enabled.

Find this in `src/app/api/ai/chat/route.ts`:

```typescript
  const result = streamText({
    model: getModel(),
```

Replace with:

```typescript
  const result = streamText({
    model: reasoning ? getModel("anthropic/claude-sonnet-4") : getModel(),
```

### Step 3: Modify `src/components/ai/message.tsx`

Add the reasoning case to the part renderer.

Find this in `src/components/ai/message.tsx`:

```typescript
          // [ai-reasoning]: add case "reasoning" here

          // [ai-tools]: add cases "tool-invocation" and "tool-result" here
```

Replace with:

```typescript
          // [ai-reasoning]: add case "reasoning" here
          case "reasoning":
            return (
              <ReasoningBlock
                key={key}
                reasoning={part.text}
              />
            );

          // [ai-tools]: add cases "tool-invocation" and "tool-result" here
```

Then add the import for the `ReasoningBlock` component.

Find this in `src/components/ai/message.tsx` (after existing imports):

```typescript
import { Markdown } from "@/components/ai/markdown";
```

Replace with:

```typescript
import { Markdown } from "@/components/ai/markdown";
import { ReasoningBlock } from "@/components/ai/reasoning";
```

### Step 4: Modify `src/components/ai/chat.tsx`

Add a reasoning toggle button to the chat input area. The toggle sends a `reasoning` flag with each message.

Add the `Brain` icon import. Find this in `src/components/ai/chat.tsx`:

```typescript
import { ChatContainer } from "@/components/ai/chat-container";
```

Replace with:

```typescript
import { Brain } from "@phosphor-icons/react";
import { ChatContainer } from "@/components/ai/chat-container";
```

Add state for the reasoning toggle. Find this in `src/components/ai/chat.tsx`:

```typescript
  const [input, setInput] = useState("");
  const [isLoadingHistory, setIsLoadingHistory] = useState(false);
```

Replace with:

```typescript
  const [input, setInput] = useState("");
  const [reasoningEnabled, setReasoningEnabled] = useState(false);
  const [isLoadingHistory, setIsLoadingHistory] = useState(false);
```

Include reasoning in the transport body. Find this in `src/components/ai/chat.tsx`:

```typescript
  const transport = useMemo(
    () =>
      new DefaultChatTransport({
        api: "/api/ai/chat",
        body: { sessionId },
      }),
    [sessionId]
  );
```

Replace with:

```typescript
  const transport = useMemo(
    () =>
      new DefaultChatTransport({
        api: "/api/ai/chat",
        body: { sessionId, reasoning: reasoningEnabled },
      }),
    [sessionId, reasoningEnabled]
  );
```

Add the reasoning toggle button in the input area, next to the send button.

Find this in `src/components/ai/chat.tsx`:

```typescript
            <PromptInput
```

Replace with:

```typescript
            <div className="flex items-center gap-2 mb-2">
              <button
                type="button"
                onClick={() => setReasoningEnabled((prev) => !prev)}
                className={`flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium transition-colors ${
                  reasoningEnabled
                    ? "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300"
                    : "bg-muted text-muted-foreground hover:bg-muted/80"
                }`}
              >
                <Brain className="h-3.5 w-3.5" />
                {reasoningEnabled ? "Reasoning on" : "Reasoning off"}
              </button>
            </div>
            <PromptInput
```

## Usage

### Toggling Reasoning

Click the "Reasoning off" button above the chat input to enable extended thinking. The button turns amber when active. When reasoning is enabled:

1. The model switches from the default (Gemini Flash Lite) to `anthropic/claude-sonnet-4`
2. The API sends `providerOptions.anthropic.thinking` with a 5,000-token budget
3. The model's chain-of-thought appears as a collapsed "Thinking..." block above the response

### Example Flow

```
[Reasoning: ON]
User: What is the probability that at least 2 people in a group of 23 share the same birthday?

AI:
  [Thinking... ~1,200 tokens] (collapsed)
  The probability is approximately 50.7%. This is the famous Birthday Problem...
```

### Adjusting Token Budget

To change the reasoning token budget, edit the `budgetTokens` value in `route.ts`:

```typescript
providerOptions.anthropic = {
  thinking: { type: "enabled", budgetTokens: 10000 }, // Increase for longer reasoning
};
```

## Acceptance Criteria

- Toggle reasoning on -- ask a complex question -- collapsible "Thinking..." block appears above the response
- Toggle reasoning off -- normal response, no thinking block
- Reasoning block is collapsed by default, expands on click to show chain-of-thought text
- Token count badge shows estimated reasoning token usage
- When reasoning is on, the model switches to `anthropic/claude-sonnet-4`
- When reasoning is off, the model uses the default from `getModel()`
- Toggle button visually indicates active/inactive state (amber when on)
