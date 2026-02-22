---
name: ai-tools
description: Tool calling framework with built-in calculator and datetime tools. Renders tool invocations as collapsible cards in the chat UI. Use this skill when the user says "add tools", "tool calling", "calculator", or "add ai tools".
author: "@mattwoodco"
version: 2.0.1
created: 2026-02-13
updated: 2026-02-13
dependencies: [ai-chat]
---

# AI Tools Skill

Adds a tool calling framework to the AI chat system with built-in calculator and datetime tools. Tool invocations render as collapsible cards in the message stream showing tool name, input parameters, and output result.

## Prerequisites

- `ai-chat` skill applied (provides `route.ts` with comment slots, `message.tsx` with part switch)
- `ai-core` skill applied (provides `getModel()`)

## Installation

No additional packages required. Uses `tool()` from `ai` and `z` from `zod`, both already installed by `ai-core` and `ai-chat`.

## What Gets Created

```
src/
├── lib/
│   └── ai/
│       └── tools/
│           ├── calculator.ts    # Safe math evaluator (no eval())
│           ├── datetime.ts      # Date/time with timezone support
│           └── index.ts         # Tool registry — exports allTools
└── components/
    └── ai/
        └── message.tsx          # MODIFIED — add tool-invocation case
```

Plus modification to:
```
src/app/api/ai/chat/route.ts    # MODIFIED — spread allTools into tools object
```

## Comment Slots

- **route.ts**: `// [ai-tools]: spread registered tools here` — where `allTools` is merged into the tools object
- **message.tsx**: `// [ai-tools]: handle tool UI parts` — default case renders `ToolInvocationCard` for tool invocations

## Setup Steps

### Step 1: Create `src/lib/ai/tools/calculator.ts`

```typescript
import { tool } from "ai";
import { z } from "zod";

type Operator = "+" | "-" | "*" | "/" | "^" | "%";

interface NumberNode {
  type: "number";
  value: number;
}

interface BinaryOpNode {
  type: "binary";
  operator: Operator;
  left: ExprNode;
  right: ExprNode;
}

interface UnaryMinusNode {
  type: "unary";
  operand: ExprNode;
}

type ExprNode = NumberNode | BinaryOpNode | UnaryMinusNode;

interface Token {
  type: "number" | "operator" | "lparen" | "rparen";
  value: string;
}

function tokenize(expression: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  const input = expression.replace(/\s+/g, "");

  while (i < input.length) {
    const ch = input[i];

    if (ch >= "0" && ch <= "9" || ch === ".") {
      let num = "";
      while (i < input.length && (input[i] >= "0" && input[i] <= "9" || input[i] === ".")) {
        num += input[i];
        i++;
      }
      tokens.push({ type: "number", value: num });
      continue;
    }

    if ("+-*/%^".includes(ch)) {
      tokens.push({ type: "operator", value: ch });
      i++;
      continue;
    }

    if (ch === "(") {
      tokens.push({ type: "lparen", value: ch });
      i++;
      continue;
    }

    if (ch === ")") {
      tokens.push({ type: "rparen", value: ch });
      i++;
      continue;
    }

    throw new Error(`Unexpected character: ${ch}`);
  }

  return tokens;
}

function parse(tokens: Token[]): ExprNode {
  let pos = 0;

  function peek(): Token | undefined {
    return tokens[pos];
  }

  function consume(): Token {
    const token = tokens[pos];
    pos++;
    return token;
  }

  function parseExpression(): ExprNode {
    return parseAddSub();
  }

  function parseAddSub(): ExprNode {
    let left = parseMulDiv();
    while (peek()?.type === "operator" && (peek()?.value === "+" || peek()?.value === "-")) {
      const op = consume().value as Operator;
      const right = parseMulDiv();
      left = { type: "binary", operator: op, left, right };
    }
    return left;
  }

  function parseMulDiv(): ExprNode {
    let left = parsePower();
    while (peek()?.type === "operator" && (peek()?.value === "*" || peek()?.value === "/" || peek()?.value === "%")) {
      const op = consume().value as Operator;
      const right = parsePower();
      left = { type: "binary", operator: op, left, right };
    }
    return left;
  }

  function parsePower(): ExprNode {
    let left = parseUnary();
    while (peek()?.type === "operator" && peek()?.value === "^") {
      consume();
      const right = parseUnary();
      left = { type: "binary", operator: "^", left, right };
    }
    return left;
  }

  function parseUnary(): ExprNode {
    if (peek()?.type === "operator" && peek()?.value === "-") {
      consume();
      const operand = parsePrimary();
      return { type: "unary", operand };
    }
    return parsePrimary();
  }

  function parsePrimary(): ExprNode {
    const token = peek();

    if (token?.type === "number") {
      consume();
      return { type: "number", value: parseFloat(token.value) };
    }

    if (token?.type === "lparen") {
      consume();
      const expr = parseExpression();
      const closing = consume();
      if (closing?.type !== "rparen") {
        throw new Error("Missing closing parenthesis");
      }
      return expr;
    }

    throw new Error(`Unexpected token: ${token?.value ?? "end of input"}`);
  }

  const result = parseExpression();
  if (pos < tokens.length) {
    throw new Error(`Unexpected token after expression: ${tokens[pos].value}`);
  }
  return result;
}

function evaluate(node: ExprNode): number {
  switch (node.type) {
    case "number":
      return node.value;
    case "unary":
      return -evaluate(node.operand);
    case "binary": {
      const left = evaluate(node.left);
      const right = evaluate(node.right);
      switch (node.operator) {
        case "+": return left + right;
        case "-": return left - right;
        case "*": return left * right;
        case "/": {
          if (right === 0) throw new Error("Division by zero");
          return left / right;
        }
        case "%": {
          if (right === 0) throw new Error("Modulo by zero");
          return left % right;
        }
        case "^": return Math.pow(left, right);
      }
    }
  }
}

function evaluateSafely(expression: string): number {
  const tokens = tokenize(expression);
  const ast = parse(tokens);
  return evaluate(ast);
}

export const calculator = tool({
  description:
    "Evaluate a mathematical expression. Supports +, -, *, /, ^, %, and parentheses. " +
    "Examples: '15 * 4 + 10', '(3 + 5) * 2', '2 ^ 10', '17 % 5'.",
  inputSchema: z.object({
    expression: z
      .string()
      .describe("The mathematical expression to evaluate, e.g. '(3 + 5) * 2'"),
  }),
  execute: async ({ expression }) => {
    try {
      const result = evaluateSafely(expression);
      return { expression, result, success: true as const };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      return { expression, error: message, success: false as const };
    }
  },
});
```

### Step 2: Create `src/lib/ai/tools/datetime.ts`

```typescript
import { tool } from "ai";
import { z } from "zod";

interface DateTimeSuccess {
  timezone: string;
  iso: string;
  formatted: string;
  date: string;
  time: string;
  dayOfWeek: string;
  utcOffset: string;
  success: true;
}

interface DateTimeError {
  timezone: string;
  error: string;
  success: false;
}

type DateTimeResult = DateTimeSuccess | DateTimeError;

function getDateTimeInTimezone(timezone: string): DateTimeResult {
  try {
    const now = new Date();

    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      year: "numeric",
      month: "long",
      day: "numeric",
      weekday: "long",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: true,
      timeZoneName: "short",
    });

    const dateFormatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });

    const timeFormatter = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: true,
    });

    const dayFormatter = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      weekday: "long",
    });

    const offsetFormatter = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      timeZoneName: "longOffset",
    });

    const offsetParts = offsetFormatter.formatToParts(now);
    const offsetPart = offsetParts.find((p) => p.type === "timeZoneName");
    const utcOffset = offsetPart?.value ?? "Unknown";

    return {
      timezone,
      iso: now.toISOString(),
      formatted: formatter.format(now),
      date: dateFormatter.format(now),
      time: timeFormatter.format(now),
      dayOfWeek: dayFormatter.format(now),
      utcOffset,
      success: true,
    };
  } catch {
    return {
      timezone,
      error: `Invalid timezone: "${timezone}". Use IANA format like "America/New_York" or "Asia/Tokyo".`,
      success: false,
    };
  }
}

export const datetime = tool({
  description:
    "Get the current date and time in a specified timezone. " +
    'Use IANA timezone names like "America/New_York", "Europe/London", "Asia/Tokyo". ' +
    'Defaults to "UTC" if no timezone is specified.',
  inputSchema: z.object({
    timezone: z
      .string()
      .default("UTC")
      .describe('IANA timezone name, e.g. "America/New_York", "Asia/Tokyo"'),
  }),
  execute: async ({ timezone }) => {
    return getDateTimeInTimezone(timezone);
  },
});
```

### Step 3: Create `src/lib/ai/tools/index.ts`

```typescript
import { calculator } from "./calculator";
import { datetime } from "./datetime";

export const allTools = {
  calculator,
  datetime,
} as const;

export { calculator } from "./calculator";
export { datetime } from "./datetime";
```

### Step 4: Modify `src/app/api/ai/chat/route.ts`

Find this in `src/app/api/ai/chat/route.ts`:

```typescript
  const tools: ToolSet = {};
  // [ai-tools]: spread registered tools here
```

Replace with:

```typescript
  const tools: ToolSet = {};
  // [ai-tools]: spread registered tools here
  Object.assign(tools, allTools);
```

Then add the import at the top of the file.

Find this in `src/app/api/ai/chat/route.ts`:

```typescript
import {
  streamText,
  convertToModelMessages,
  type UIMessage,
  type ToolSet,
  type JSONValue,
} from "ai";
import { getModel } from "@/lib/ai";
```

Replace with:

```typescript
import {
  streamText,
  convertToModelMessages,
  type UIMessage,
  type ToolSet,
  type JSONValue,
} from "ai";
import { getModel } from "@/lib/ai";
import { allTools } from "@/lib/ai/tools";
```

### Step 5: Modify `src/components/ai/message.tsx`

Find this in `src/components/ai/message.tsx`:

```typescript
          // [ai-tools]: handle tool UI parts in default case

          default:
```

Replace with:

```typescript
          default: {
            // [ai-tools]: handle tool UI parts
            if (isToolUIPart(part)) {
              return (
                <ToolInvocationCard
                  key={`${partId}-${part.toolCallId}`}
                  toolName={getToolName(part)}
                  state={part.state}
                  args={part.input as Record<string, unknown> ?? {}}
                  result={part.state === "output-available" ? part.output : undefined}
                />
              );
            }
            return null;
          }
```

Then add the `ToolInvocationCard` component and its imports to the same file.

Find this in `src/components/ai/message.tsx`:

```typescript
import { useId } from "react";
```

Replace with:

```typescript
import { useId, useState } from "react";
import { isToolUIPart, getToolName, type UIMessage } from "ai";
import { CaretDown, CaretRight, CircleNotch, Wrench } from "@phosphor-icons/react";
```

Add the `ToolInvocationCard` component definition before the `MessageParts` component.

Find this in `src/components/ai/message.tsx`:

```typescript
function MessageParts({ parts }: { parts: UIMessage["parts"] }) {
```

Replace with:

```typescript
interface ToolInvocationCardProps {
  toolName: string;
  state: string;
  args: Record<string, unknown>;
  result?: unknown;
}

function ToolInvocationCard({ toolName, state, args, result }: ToolInvocationCardProps) {
  const [isExpanded, setIsExpanded] = useState(false);

  return (
    <div className="my-2 rounded-lg border bg-muted/50 text-sm">
      <button
        type="button"
        onClick={() => setIsExpanded((prev) => !prev)}
        className="flex w-full items-center gap-2 px-3 py-2 text-left hover:bg-muted/80 transition-colors"
      >
        {state === "output-available" || state === "output-error" || state === "output-denied" ? (
          <Wrench className="h-4 w-4 text-muted-foreground" />
        ) : (
          <CircleNotch className="h-4 w-4 animate-spin text-muted-foreground" />
        )}
        <span className="font-medium">{toolName}</span>
        <span className="ml-auto text-xs text-muted-foreground">
          {state === "output-available" ? "Completed" : state === "output-error" ? "Error" : state === "output-denied" ? "Denied" : "Running..."}
        </span>
        {isExpanded ? (
          <CaretDown className="h-4 w-4 text-muted-foreground" />
        ) : (
          <CaretRight className="h-4 w-4 text-muted-foreground" />
        )}
      </button>
      {isExpanded && (
        <div className="border-t px-3 py-2 space-y-2">
          <div>
            <p className="text-xs font-medium text-muted-foreground mb-1">Input</p>
            <pre className="text-xs bg-background rounded p-2 overflow-x-auto whitespace-pre-wrap">
              {JSON.stringify(args, null, 2)}
            </pre>
          </div>
          {state === "output-available" && result != null && (
            <div>
              <p className="text-xs font-medium text-muted-foreground mb-1">Output</p>
              <pre className="text-xs bg-background rounded p-2 overflow-x-auto whitespace-pre-wrap">
                {typeof result === "string" ? result : JSON.stringify(result, null, 2)}
              </pre>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function MessageParts({ parts }: { parts: UIMessage["parts"] }) {
```

## Usage

Once applied, the AI can use tools automatically. Simply ask questions that require computation or date/time information:

```
User: What is 15 * 4 + 10?
AI: [calculator tool invoked] The result of 15 * 4 + 10 is 70.

User: What time is it in Tokyo?
AI: [datetime tool invoked] It's currently 3:45 PM on Thursday, February 13, 2026 in Tokyo (JST, UTC+9).
```

### Adding Custom Tools

To register additional tools, create a new file in `src/lib/ai/tools/` and add it to the barrel export:

```typescript
// src/lib/ai/tools/my-tool.ts
import { tool } from "ai";
import { z } from "zod";

export const myTool = tool({
  description: "What this tool does",
  inputSchema: z.object({
    input: z.string().describe("The input parameter"),
  }),
  execute: async ({ input }) => {
    return { result: `Processed: ${input}` };
  },
});
```

Then add it to `src/lib/ai/tools/index.ts`:

```typescript
import { calculator } from "./calculator";
import { datetime } from "./datetime";
import { myTool } from "./my-tool";

export const allTools = {
  calculator,
  datetime,
  myTool,
} as const;
```

No changes to `route.ts` needed -- `allTools` is already spread into the tools object.

## Acceptance Criteria

- Ask "what is 15 * 4 + 10" -- calculator tool invoked, result "70" displayed inline
- Ask "what time is it in Tokyo" -- datetime tool invoked, correct time shown
- Tool cards are collapsible (collapsed by default, expandable to see input/output)
- `maxSteps: 5` allows multi-step tool chains (ask a question requiring multiple tool calls)
- Tool cards show a loading spinner while the tool is executing
- Tool cards show "Completed" badge with the result after execution
- No `eval()` used anywhere -- calculator uses a safe recursive descent parser
