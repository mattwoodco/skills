---
name: ai-memory
description: Cross-session memory with context injection. Persists user preferences and facts to Postgres, auto-injects relevant memories into the system prompt, and exposes save/recall tools. Use this skill when the user says "add memory", "remember things", "persistent context", or "cross-session memory".
author: "@mattwoodco"
version: 2.0.1
created: 2026-02-13
updated: 2026-02-13
dependencies: [ai-chat, ai-tools]
---

# AI Memory Skill

Persists user preferences and facts across chat sessions. Memories are stored in Postgres via Drizzle, auto-injected into the system prompt as context, and exposed as `saveMemory` and `recallMemory` tools the AI can invoke.

## Prerequisites

- `ai-chat` skill applied (provides `route.ts` with comment slots, DB setup with Drizzle)
- `ai-tools` skill applied (provides tool registration pattern in `route.ts`)
- `ai-core` skill applied (provides `getModel()`)
- PostgreSQL running (via Docker from the `docker` skill)

## Installation

No additional packages required. Uses `drizzle-orm` (already installed by `ai-chat`) and `tool`/`z` from `ai`/`zod` (already installed by `ai-core`).

## Environment Variables

No additional environment variables required. Uses the existing `DATABASE_URL` from the `docker` skill.

## What Gets Created

```
src/
├── db/
│   └── schema/
│       └── memory.ts              # memory table (userId, key, value, category)
├── lib/
│   └── ai/
│       ├── memory.ts              # getRelevantMemories() + saveMemoryRecord() helpers
│       └── tools/
│           └── memory.ts          # saveMemory + recallMemory tool definitions
```

Plus modifications to:

```
src/app/api/ai/chat/route.ts      # MODIFIED — inject memories + spread memory tools
src/db/schema/index.ts             # MODIFIED — re-export memory schema
```

## Comment Slots

- **route.ts**: `// [ai-memory]: append memory context here` — injects relevant memories into the system prompt
- **route.ts**: `// [ai-memory]: add saveMemory, recallMemory` — spreads memory tools into the tools object

## Setup Steps

### Step 1: Create `src/db/schema/memory.ts`

```typescript
import { pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

export const memory = pgTable("memory", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull(),
  key: text("key").notNull(),
  value: text("value").notNull(),
  category: text("category").notNull().default("general"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).defaultNow().notNull(),
});

export type Memory = typeof memory.$inferSelect;
export type NewMemory = typeof memory.$inferInsert;
```

### Step 2: Modify `src/db/schema/index.ts`

Add the memory schema export to the barrel file.

Find this in `src/db/schema/index.ts`:

```typescript
export * from "./chat";
```

Replace with:

```typescript
export * from "./chat";
export * from "./memory";
```

### Step 3: Create `src/lib/ai/memory.ts`

```typescript
import { eq, and, ilike, or, desc } from "drizzle-orm";
import { db } from "@/db";
import { memory, type Memory } from "@/db/schema/memory";

interface MemoryRecord {
  key: string;
  value: string;
  category: string;
}

export async function getRelevantMemories(
  userId: string,
  query: string,
): Promise<MemoryRecord[]> {
  const words = query
    .toLowerCase()
    .split(/\s+/)
    .filter((w) => w.length > 2);

  if (words.length === 0) {
    const recentMemories = await db
      .select()
      .from(memory)
      .where(eq(memory.userId, userId))
      .orderBy(desc(memory.updatedAt))
      .limit(10);

    return recentMemories.map((m) => ({
      key: m.key,
      value: m.value,
      category: m.category,
    }));
  }

  const searchConditions = words.map((word) =>
    or(
      ilike(memory.key, `%${word}%`),
      ilike(memory.value, `%${word}%`),
      ilike(memory.category, `%${word}%`),
    ),
  );

  const results = await db
    .select()
    .from(memory)
    .where(
      and(
        eq(memory.userId, userId),
        or(...searchConditions),
      ),
    )
    .orderBy(desc(memory.updatedAt))
    .limit(20);

  return results.map((m) => ({
    key: m.key,
    value: m.value,
    category: m.category,
  }));
}

export async function saveMemoryRecord(
  userId: string,
  key: string,
  value: string,
  category: string = "general",
): Promise<Memory> {
  const existing = await db
    .select()
    .from(memory)
    .where(
      and(
        eq(memory.userId, userId),
        eq(memory.key, key),
      ),
    )
    .limit(1);

  if (existing.length > 0) {
    const [updated] = await db
      .update(memory)
      .set({
        value,
        category,
        updatedAt: new Date(),
      })
      .where(eq(memory.id, existing[0].id))
      .returning();

    return updated;
  }

  const [created] = await db
    .insert(memory)
    .values({
      userId,
      key,
      value,
      category,
    })
    .returning();

  return created;
}

export async function deleteMemoryRecord(
  userId: string,
  key: string,
): Promise<boolean> {
  const result = await db
    .delete(memory)
    .where(
      and(
        eq(memory.userId, userId),
        eq(memory.key, key),
      ),
    )
    .returning();

  return result.length > 0;
}

export async function listMemories(
  userId: string,
  category?: string,
): Promise<MemoryRecord[]> {
  const conditions = [eq(memory.userId, userId)];
  if (category) {
    conditions.push(eq(memory.category, category));
  }

  const results = await db
    .select()
    .from(memory)
    .where(and(...conditions))
    .orderBy(desc(memory.updatedAt))
    .limit(50);

  return results.map((m) => ({
    key: m.key,
    value: m.value,
    category: m.category,
  }));
}
```

### Step 4: Create `src/lib/ai/tools/memory.ts`

```typescript
import { tool } from "ai";
import { z } from "zod";
import {
  saveMemoryRecord,
  getRelevantMemories,
  deleteMemoryRecord,
  listMemories,
} from "@/lib/ai/memory";

interface SaveMemoryResult {
  key: string;
  value: string;
  category: string;
  success: true;
}

interface RecallMemoryResult {
  query: string;
  memories: { key: string; value: string; category: string }[];
  count: number;
  success: true;
}

interface DeleteMemoryResult {
  key: string;
  deleted: boolean;
  success: true;
}

interface ListMemoriesResult {
  category: string | undefined;
  memories: { key: string; value: string; category: string }[];
  count: number;
  success: true;
}

export function createMemoryTools(userId: string) {
  const saveMemory = tool({
    description:
      "Save a fact, preference, or piece of information about the user for future reference. " +
      "Use this when the user shares personal info, preferences, or anything worth remembering across sessions. " +
      "The key should be a short, descriptive label. The value is the actual information. " +
      "Categories: 'personal' (name, location), 'preference' (likes, dislikes), 'work' (job, projects), 'general' (other).",
    inputSchema: z.object({
      key: z
        .string()
        .describe("Short descriptive label for this memory, e.g. 'name', 'favorite_color', 'job_title'"),
      value: z
        .string()
        .describe("The information to remember, e.g. 'Matt', 'blue', 'software engineer'"),
      category: z
        .enum(["personal", "preference", "work", "general"])
        .default("general")
        .describe("Category for organizing memories"),
    }),
    execute: async ({ key, value, category }): Promise<SaveMemoryResult> => {
      await saveMemoryRecord(userId, key, value, category);
      return { key, value, category, success: true };
    },
  });

  const recallMemory = tool({
    description:
      "Search the user's saved memories for relevant information. " +
      "Use this when the user asks about something they previously told you, " +
      "or when you need context about their preferences, personal info, or past conversations.",
    inputSchema: z.object({
      query: z
        .string()
        .describe("Search query to find relevant memories, e.g. 'name', 'favorite', 'work'"),
    }),
    execute: async ({ query }): Promise<RecallMemoryResult> => {
      const memories = await getRelevantMemories(userId, query);
      return {
        query,
        memories,
        count: memories.length,
        success: true,
      };
    },
  });

  const forgetMemory = tool({
    description:
      "Delete a specific memory by its key. Use this when the user asks you to forget something " +
      "or when information is no longer accurate.",
    inputSchema: z.object({
      key: z
        .string()
        .describe("The key of the memory to delete, e.g. 'name', 'favorite_color'"),
    }),
    execute: async ({ key }): Promise<DeleteMemoryResult> => {
      const deleted = await deleteMemoryRecord(userId, key);
      return { key, deleted, success: true };
    },
  });

  const listAllMemories = tool({
    description:
      "List all saved memories for the user, optionally filtered by category. " +
      "Use this when the user asks 'what do you remember about me' or wants to see all stored information.",
    inputSchema: z.object({
      category: z
        .enum(["personal", "preference", "work", "general"])
        .optional()
        .describe("Optional category filter"),
    }),
    execute: async ({ category }): Promise<ListMemoriesResult> => {
      const memories = await listMemories(userId, category);
      return {
        category,
        memories,
        count: memories.length,
        success: true,
      };
    },
  });

  return {
    saveMemory,
    recallMemory,
    forgetMemory,
    listAllMemories,
  } as const;
}
```

### Step 5: Modify `src/app/api/ai/chat/route.ts`

Add the memory imports at the top of the file.

Find this in `src/app/api/ai/chat/route.ts`:

```typescript
import { getModel } from "@/lib/ai";
import { allTools } from "@/lib/ai/tools";
```

Replace with:

```typescript
import { getModel } from "@/lib/ai";
import { allTools } from "@/lib/ai/tools";
import { getRelevantMemories } from "@/lib/ai/memory";
import { createMemoryTools } from "@/lib/ai/tools/memory";
```

Inject relevant memories into the system prompt.

Find this in `src/app/api/ai/chat/route.ts`:

```typescript
  const systemParts: string[] = [
    "You are a helpful assistant. Be concise and clear in your responses.",
  ];
  // [ai-memory]: append memory context here
```

Replace with:

```typescript
  const systemParts: string[] = [
    "You are a helpful assistant. Be concise and clear in your responses.",
  ];
  // [ai-memory]: append memory context here
  const lastMsg = messages.at(-1);
  const lastMessageText = lastMsg?.parts
    .filter((p): p is Extract<typeof p, { type: "text" }> => p.type === "text")
    .map((p) => p.text)
    .join(" ") ?? "";
  const memories = await getRelevantMemories(userId, lastMessageText);
  if (memories.length > 0) {
    systemParts.push(
      "## User Memory\nHere are things you remember about this user from previous conversations:\n" +
        memories.map((m) => `- **${m.key}** (${m.category}): ${m.value}`).join("\n"),
    );
  }
```

Spread the memory tools into the tools object.

Find this in `src/app/api/ai/chat/route.ts`:

```typescript
  // [ai-tools]: spread registered tools here
  Object.assign(tools, allTools);
```

Replace with:

```typescript
  // [ai-tools]: spread registered tools here
  Object.assign(tools, allTools);
  // [ai-memory]: add saveMemory, recallMemory
  const memoryTools = createMemoryTools(userId);
  Object.assign(tools, memoryTools);
```

## Post-Setup

After applying this skill, push the database schema to create the `memory` table:

```bash
bunx drizzle-kit push
```

## Usage

### Automatic Memory Injection

Every chat request automatically queries for relevant memories based on the user's latest message. Matching memories are injected into the system prompt so the AI has context without the user needing to repeat themselves.

### AI-Initiated Memory Saving

The AI will proactively save memories when users share personal information:

```
User: My name is Matt and I work at Acme Corp.
AI: Nice to meet you, Matt! I've saved that information.
    [saveMemory tool: key="name", value="Matt", category="personal"]
    [saveMemory tool: key="employer", value="Acme Corp", category="work"]
```

### Recall Across Sessions

```
[New session]
User: What's my name?
AI: [recallMemory tool: query="name"]
    Your name is Matt! You also work at Acme Corp.
```

### Listing All Memories

```
User: What do you remember about me?
AI: [listAllMemories tool]
    Here's everything I remember:
    - name (personal): Matt
    - employer (work): Acme Corp
    - favorite_color (preference): blue
```

### Forgetting

```
User: Forget my favorite color.
AI: [forgetMemory tool: key="favorite_color"]
    Done! I've forgotten your favorite color.
```

## Acceptance Criteria

- Tell the AI "my name is Matt" -- `saveMemory` tool invoked, memory persisted to DB
- Start a new session -- ask "what's my name" -- AI recalls "Matt" from memory (via system prompt injection or `recallMemory` tool)
- Ask "what do you remember about me" -- `listAllMemories` tool returns all saved facts
- Tell the AI "forget my name" -- `forgetMemory` tool invoked, memory deleted
- Memories persist across sessions (verified by checking different session IDs)
- Memory context appears in the system prompt (visible in server logs during development)
- `bunx drizzle-kit push` creates the `memory` table without errors
- Duplicate keys update the existing value rather than creating duplicates
