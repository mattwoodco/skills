---
name: ai-tasks
description: Task extraction and management — the AI creates structured tasks from conversation, persisted to Postgres with a task list UI panel. Use this skill when the user says "add tasks", "task management", "todo list", "extract tasks", or "ai tasks".
author: "@mattwoodco"
version: 1.0.1
created: 2026-02-13
updated: 2026-02-13
dependencies: [ai-tools, ai-chat]
---

# AI Tasks

Experience layer that extracts structured tasks from conversation and displays them in a task list panel with checkboxes, priority badges, and status management. Tasks are persisted to Postgres via Drizzle and linked to the authenticated user.

The AI creates, updates, and lists tasks via tool calls (`createTask`, `updateTask`, `listTasks`). The task list panel appears as a tab alongside the artifact panel (if installed) or as a standalone panel.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `ai-core` skill installed (provides `getModel()`)
- `ai-chat` skill installed (provides chat UI, route pipeline, message renderer)
- `ai-tools` skill installed (provides tool calling framework)
- PostgreSQL with Drizzle ORM configured
- Auth skill installed (provides `requireAuth()` and `user` table reference)

## Installation

No additional packages required. Uses `ai`, `zod`, and `drizzle-orm` already installed by prerequisite skills.

## What Gets Created

```
src/
├── db/
│   └── schema/
│       └── task.ts                    # task table schema (Drizzle)
├── lib/
│   └── ai/
│       └── tools/
│           └── task.ts                # createTask, updateTask, listTasks tool definitions
└── components/
    └── ai/
        └── task-list.tsx              # Task list panel with checkboxes and priority badges
```

## What Gets Modified

```
src/
├── app/
│   ├── api/
│   │   └── ai/
│   │       └── chat/
│   │           └── route.ts           # Register task tools + system prompt
│   └── (app)/
│       └── chat/
│           └── page.tsx               # Add task list tab alongside artifacts panel
```

## Comment Slots

- **route.ts**: `// [ai-tasks]: add createTask, updateTask, listTasks` — spreads task tools into the tools object
- **route.ts**: `// [ai-tasks]: task instructions` — appends task management instructions to system prompt
- **chat/page.tsx**: `// [ai-tasks]: add panel tabs here` — adds task list panel alongside artifacts

## Database Migration

After applying this skill, create the `task` table:

```bash
bunx drizzle-kit push
```

## Setup Steps

### Step 1: Create `src/db/schema/task.ts`

```typescript
import { pgTable, text, timestamp, integer } from "drizzle-orm/pg-core";
import { user } from "./auth";

export const task = pgTable("task", {
  id: text("id")
    .primaryKey()
    .$defaultFn(() => crypto.randomUUID()),
  userId: text("user_id")
    .notNull()
    .references(() => user.id, { onDelete: "cascade" }),
  sessionId: text("session_id"),
  title: text("title").notNull(),
  description: text("description"),
  status: text("status", {
    enum: ["todo", "in_progress", "done", "cancelled"],
  })
    .notNull()
    .default("todo"),
  priority: text("priority", {
    enum: ["low", "medium", "high", "urgent"],
  })
    .notNull()
    .default("medium"),
  sortOrder: integer("sort_order").notNull().default(0),
  createdAt: timestamp("created_at").notNull().defaultNow(),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});

export type Task = typeof task.$inferSelect;
export type NewTask = typeof task.$inferInsert;
```

### Step 2: Create `src/lib/ai/tools/task.ts`

```typescript
import { tool } from "ai";
import { z } from "zod";
import { db } from "@/db";
import { task } from "@/db/schema/task";
import { eq, and, desc } from "drizzle-orm";

type TaskResult = {
  id: string;
  title: string;
  description: string | null;
  status: string;
  priority: string;
  createdAt: Date;
  updatedAt: Date;
};

type TaskListResult = {
  tasks: TaskResult[];
  total: number;
};

export function createTaskTools(userId: string, sessionId?: string) {
  const createTask = tool({
    description:
      "Create a new task or to-do item. Use this when the user mentions something they need to do, a goal, an action item, or when they ask you to track tasks.",
    inputSchema: z.object({
      title: z
        .string()
        .describe("Short, actionable title for the task"),
      description: z
        .string()
        .optional()
        .describe(
          "Detailed description with context, acceptance criteria, or notes"
        ),
      priority: z
        .enum(["low", "medium", "high", "urgent"])
        .default("medium")
        .describe(
          "Task priority: low (nice-to-have), medium (normal), high (important), urgent (do now)"
        ),
    }),
    execute: async ({ title, description, priority }): Promise<TaskResult> => {
      const maxOrder = await db
        .select({ sortOrder: task.sortOrder })
        .from(task)
        .where(eq(task.userId, userId))
        .orderBy(desc(task.sortOrder))
        .limit(1);

      const nextOrder =
        maxOrder.length > 0 ? maxOrder[0].sortOrder + 1 : 0;

      const [created] = await db
        .insert(task)
        .values({
          userId,
          sessionId,
          title,
          description: description ?? null,
          priority,
          sortOrder: nextOrder,
        })
        .returning();

      return {
        id: created.id,
        title: created.title,
        description: created.description,
        status: created.status,
        priority: created.priority,
        createdAt: created.createdAt,
        updatedAt: created.updatedAt,
      };
    },
  });

  const updateTask = tool({
    description:
      "Update an existing task's status or details. Use this when the user marks a task as done, changes priority, or modifies task details.",
    inputSchema: z.object({
      id: z.string().describe("The task ID to update"),
      status: z
        .enum(["todo", "in_progress", "done", "cancelled"])
        .optional()
        .describe("New status for the task"),
      priority: z
        .enum(["low", "medium", "high", "urgent"])
        .optional()
        .describe("New priority for the task"),
      title: z
        .string()
        .optional()
        .describe("Updated title"),
      description: z
        .string()
        .optional()
        .describe("Updated description"),
    }),
    execute: async ({
      id,
      status,
      priority,
      title,
      description,
    }): Promise<TaskResult> => {
      const updates: Record<string, unknown> = {
        updatedAt: new Date(),
      };
      if (status !== undefined) updates.status = status;
      if (priority !== undefined) updates.priority = priority;
      if (title !== undefined) updates.title = title;
      if (description !== undefined) updates.description = description;

      const [updated] = await db
        .update(task)
        .set(updates)
        .where(and(eq(task.id, id), eq(task.userId, userId)))
        .returning();

      if (!updated) {
        throw new Error(`Task ${id} not found or access denied`);
      }

      return {
        id: updated.id,
        title: updated.title,
        description: updated.description,
        status: updated.status,
        priority: updated.priority,
        createdAt: updated.createdAt,
        updatedAt: updated.updatedAt,
      };
    },
  });

  const listTasks = tool({
    description:
      "List the user's current tasks. Use this when the user asks about their tasks, to-do list, or what they need to do.",
    inputSchema: z.object({
      status: z
        .enum(["todo", "in_progress", "done", "cancelled", "all"])
        .default("all")
        .describe("Filter by status. Use 'all' to show everything."),
    }),
    execute: async ({ status }): Promise<TaskListResult> => {
      const conditions = [eq(task.userId, userId)];

      if (status !== "all") {
        conditions.push(eq(task.status, status));
      }

      const tasks = await db
        .select()
        .from(task)
        .where(and(...conditions))
        .orderBy(task.sortOrder);

      return {
        tasks: tasks.map((t) => ({
          id: t.id,
          title: t.title,
          description: t.description,
          status: t.status,
          priority: t.priority,
          createdAt: t.createdAt,
          updatedAt: t.updatedAt,
        })),
        total: tasks.length,
      };
    },
  });

  return { createTask, updateTask, listTasks };
}
```

### Step 3: Create `src/components/ai/task-list.tsx`

```tsx
"use client";

import { useState, useEffect, useCallback, useId, memo } from "react";

type TaskStatus = "todo" | "in_progress" | "done" | "cancelled";
type TaskPriority = "low" | "medium" | "high" | "urgent";

type Task = {
  id: string;
  title: string;
  description: string | null;
  status: TaskStatus;
  priority: TaskPriority;
  createdAt: string;
  updatedAt: string;
};

type TaskListProps = {
  tasks: Task[];
  onToggle: (id: string, done: boolean) => void;
  isLoading: boolean;
};

const PRIORITY_STYLES: Record<
  TaskPriority,
  { bg: string; text: string; label: string }
> = {
  low: {
    bg: "bg-slate-100 dark:bg-slate-800",
    text: "text-slate-600 dark:text-slate-400",
    label: "Low",
  },
  medium: {
    bg: "bg-blue-100 dark:bg-blue-900",
    text: "text-blue-700 dark:text-blue-300",
    label: "Med",
  },
  high: {
    bg: "bg-orange-100 dark:bg-orange-900",
    text: "text-orange-700 dark:text-orange-300",
    label: "High",
  },
  urgent: {
    bg: "bg-red-100 dark:bg-red-900",
    text: "text-red-700 dark:text-red-300",
    label: "Urgent",
  },
};

const STATUS_STYLES: Record<
  TaskStatus,
  { bg: string; text: string; label: string }
> = {
  todo: {
    bg: "bg-gray-100 dark:bg-gray-800",
    text: "text-gray-600 dark:text-gray-400",
    label: "To Do",
  },
  in_progress: {
    bg: "bg-yellow-100 dark:bg-yellow-900",
    text: "text-yellow-700 dark:text-yellow-300",
    label: "In Progress",
  },
  done: {
    bg: "bg-green-100 dark:bg-green-900",
    text: "text-green-700 dark:text-green-300",
    label: "Done",
  },
  cancelled: {
    bg: "bg-gray-100 dark:bg-gray-800",
    text: "text-gray-400 dark:text-gray-500",
    label: "Cancelled",
  },
};

const PriorityBadge = memo(function PriorityBadge({ priority }: { priority: TaskPriority }) {
  const style = PRIORITY_STYLES[priority];
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${style.bg} ${style.text}`}
    >
      {style.label}
    </span>
  );
});

const StatusBadge = memo(function StatusBadge({ status }: { status: TaskStatus }) {
  const style = STATUS_STYLES[status];
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${style.bg} ${style.text}`}
    >
      {style.label}
    </span>
  );
});

type TaskFilter = "all" | TaskStatus;

export function TaskList({ tasks, onToggle, isLoading }: TaskListProps) {
  const itemId = useId();
  const [filter, setFilter] = useState<TaskFilter>("all");
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const filteredTasks =
    filter === "all"
      ? tasks
      : tasks.filter((t) => t.status === filter);

  const counts = {
    all: tasks.length,
    todo: tasks.filter((t) => t.status === "todo").length,
    in_progress: tasks.filter((t) => t.status === "in_progress").length,
    done: tasks.filter((t) => t.status === "done").length,
    cancelled: tasks.filter((t) => t.status === "cancelled").length,
  };

  const filters: { key: TaskFilter; label: string }[] = [
    { key: "all", label: `All (${counts.all})` },
    { key: "todo", label: `To Do (${counts.todo})` },
    { key: "in_progress", label: `Active (${counts.in_progress})` },
    { key: "done", label: `Done (${counts.done})` },
  ];

  if (tasks.length === 0 && !isLoading) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
        <div className="rounded-full bg-muted p-3">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="text-muted-foreground"
          >
            <path d="M12 2v4" />
            <path d="m16.24 7.76-2.12 2.12" />
            <circle cx="12" cy="14" r="8" />
            <path d="M12 10v4" />
            <path d="M12 18h.01" />
          </svg>
        </div>
        <p className="text-sm font-medium">No tasks yet</p>
        <p className="text-xs text-muted-foreground">
          Tell the AI about things you need to do and it will create tasks
          for you.
        </p>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      {/* Filter tabs */}
      <div className="flex gap-1 overflow-x-auto border-b px-2 py-2">
        {filters.map((f) => (
          <button
            key={`${itemId}-filter-${f.key}`}
            type="button"
            onClick={() => setFilter(f.key)}
            className={`shrink-0 rounded-md px-3 py-1.5 text-xs font-medium transition-colors ${
              filter === f.key
                ? "bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-muted"
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      {/* Task items */}
      <div className="flex-1 overflow-auto">
        {isLoading ? (
          <div className="flex items-center justify-center p-8">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-primary border-t-transparent" />
          </div>
        ) : (
          <ul className="divide-y">
            {filteredTasks.map((taskItem) => (
              <li
                key={`${itemId}-task-${taskItem.id}`}
                className="group px-4 py-3"
              >
                <div className="flex items-start gap-3">
                  {/* Checkbox */}
                  <button
                    type="button"
                    onClick={() =>
                      onToggle(taskItem.id, taskItem.status !== "done")
                    }
                    className={`mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded border-2 transition-colors ${
                      taskItem.status === "done"
                        ? "border-green-500 bg-green-500 text-white"
                        : "border-muted-foreground/30 hover:border-primary"
                    }`}
                    aria-label={
                      taskItem.status === "done"
                        ? "Mark as incomplete"
                        : "Mark as complete"
                    }
                  >
                    {taskItem.status === "done" && (
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        width="12"
                        height="12"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="3"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      >
                        <polyline points="20 6 9 17 4 12" />
                      </svg>
                    )}
                  </button>

                  {/* Content */}
                  <div className="flex-1 min-w-0">
                    <button
                      type="button"
                      onClick={() =>
                        setExpandedId(
                          expandedId === taskItem.id
                            ? null
                            : taskItem.id
                        )
                      }
                      className="w-full text-left"
                    >
                      <p
                        className={`text-sm font-medium ${
                          taskItem.status === "done"
                            ? "text-muted-foreground line-through"
                            : ""
                        }`}
                      >
                        {taskItem.title}
                      </p>
                    </button>
                    {expandedId === taskItem.id &&
                      taskItem.description && (
                        <p className="mt-1 text-xs text-muted-foreground">
                          {taskItem.description}
                        </p>
                      )}
                  </div>

                  {/* Badges */}
                  <div className="flex shrink-0 items-center gap-1.5">
                    <PriorityBadge priority={taskItem.priority} />
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>

      {/* Summary footer */}
      <div className="border-t px-4 py-2">
        <p className="text-xs text-muted-foreground">
          {counts.done} of {counts.all} completed
        </p>
      </div>
    </div>
  );
}

export type { Task, TaskStatus, TaskPriority };
```

### Step 4: (Optional) Modify `src/db/schema/index.ts`

If you use a barrel file for schema exports, add the task schema:

```typescript
export * from "./task";
```

If schema files are imported directly (e.g., `import { task } from "@/db/schema/task"`), skip this step.

### Step 5: Modify `src/app/api/ai/chat/route.ts`

Register the task tools in the route pipeline. Task tools need `userId` context, so they are created per-request.

Find this in `src/app/api/ai/chat/route.ts`:

```typescript
import { allTools } from "@src/lib/ai/tools";
```

Replace with:

```typescript
import { allTools } from "@src/lib/ai/tools";
import { createTaskTools } from "@src/lib/ai/tools/task";
```

Find this in `src/app/api/ai/chat/route.ts`:

```typescript
  const tools: ToolSet = {};
  // [ai-tools]: spread registered tools here
```

Replace with:

```typescript
  const tools: ToolSet = {};
  // [ai-tools]: spread registered tools here
  // [ai-tasks]: add createTask, updateTask, listTasks
  const taskTools = createTaskTools(userId, sessionId);
  Object.assign(tools, taskTools);
```

Add task instructions to the system prompt. Find the `systemParts` array and append after it:

```typescript
  // [ai-tasks]: task instructions
  systemParts.push(
    `## Tasks

You can manage tasks for the user. When the user mentions things they need to do, action items, goals, or to-dos, use the createTask tool to track them.

- Use createTask to add new tasks. Choose an appropriate priority based on context.
- Use updateTask to change a task's status (todo, in_progress, done, cancelled) or update its details.
- Use listTasks to show the user their current tasks when they ask.

When creating multiple tasks from a single message, create them one at a time. Assign reasonable priorities based on urgency cues in the text.`
  );
```

### Step 6: Modify `src/app/(app)/chat/page.tsx`

Add a task list tab to the side panel. This composites with the artifact panel if `ai-artifacts` is installed.

Find this in `src/app/(app)/chat/page.tsx`:

```tsx
import { useState, useCallback } from "react";
```

Replace with:

```tsx
import { useState, useCallback, useEffect } from "react";
```

Add imports for task components. Find:

```tsx
import { Chat } from "@/components/ai/chat";
import { ChatSidebar } from "@/components/ai/chat-sidebar";
```

Replace with:

```tsx
import { Chat } from "@/components/ai/chat";
import { ChatSidebar } from "@/components/ai/chat-sidebar";
import { TaskList, type Task as TaskItem } from "@/components/ai/task-list";
```

Add task state management inside the component. Find:

```tsx
  const [sessionId, setSessionId] = useState<string | undefined>();
```

Replace with:

```tsx
  const [sessionId, setSessionId] = useState<string | undefined>();

  // [ai-tasks]: task state
  const [tasks, setTasks] = useState<TaskItem[]>([]);
  const [tasksLoading, setTasksLoading] = useState(false);
  const [panelTab, setPanelTab] = useState<"artifacts" | "tasks">("artifacts");

  // Fetch tasks on mount and when session changes
  useEffect(() => {
    async function fetchTasks() {
      setTasksLoading(true);
      try {
        const res = await fetch("/api/ai/sessions/tasks");
        if (res.ok) {
          const data = await res.json() as { tasks: TaskItem[] };
          setTasks(data.tasks);
        }
      } catch {
        // Tasks will load on next tool call
      } finally {
        setTasksLoading(false);
      }
    }
    fetchTasks();
  }, [sessionId]);

  const handleTaskToggle = useCallback(
    async (taskId: string, done: boolean) => {
      // Optimistic update
      setTasks((prev) =>
        prev.map((t) =>
          t.id === taskId
            ? { ...t, status: done ? ("done" as const) : ("todo" as const) }
            : t
        )
      );

      try {
        await fetch("/api/ai/sessions/tasks", {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            id: taskId,
            status: done ? "done" : "todo",
          }),
        });
      } catch {
        // Revert on failure
        setTasks((prev) =>
          prev.map((t) =>
            t.id === taskId
              ? { ...t, status: done ? ("todo" as const) : ("done" as const) }
              : t
          )
        );
      }
    },
    []
  );

  const handleTaskCreatedFromChat = useCallback((newTask: TaskItem) => {
    setTasks((prev) => {
      const exists = prev.some((t) => t.id === newTask.id);
      if (exists) {
        return prev.map((t) => (t.id === newTask.id ? newTask : t));
      }
      return [...prev, newTask];
    });
    setPanelTab("tasks");
  }, []);
```

Add the task panel alongside the artifacts panel. Find the comment slot:

```tsx
        {/* [ai-tasks]: add panel tabs here */}
```

Replace with:

```tsx
        {/* [ai-tasks]: task panel */}
        {tasks.length > 0 && (
          <div className="flex h-full w-80 flex-col border-l bg-background">
            {/* Tab switcher — only shows if artifacts panel is also present */}
            <div className="flex border-b">
              <button
                type="button"
                onClick={() => setPanelTab("artifacts")}
                className={`flex-1 px-4 py-2 text-sm font-medium transition-colors ${
                  panelTab === "artifacts"
                    ? "border-b-2 border-primary text-primary"
                    : "text-muted-foreground hover:text-foreground"
                }`}
              >
                Artifacts
              </button>
              <button
                type="button"
                onClick={() => setPanelTab("tasks")}
                className={`flex-1 px-4 py-2 text-sm font-medium transition-colors ${
                  panelTab === "tasks"
                    ? "border-b-2 border-primary text-primary"
                    : "text-muted-foreground hover:text-foreground"
                }`}
              >
                Tasks
                {tasks.length > 0 && (
                  <span className="ml-1.5 rounded-full bg-muted px-1.5 py-0.5 text-xs">
                    {tasks.filter((t) => t.status !== "done").length}
                  </span>
                )}
              </button>
            </div>
            {panelTab === "tasks" && (
              <TaskList
                tasks={tasks}
                onToggle={handleTaskToggle}
                isLoading={tasksLoading}
              />
            )}
          </div>
        )}
```

### Step 7: Create `src/app/api/ai/sessions/tasks/route.ts`

A simple API endpoint for the task list UI to fetch and update tasks directly (bypassing the AI tool flow for checkbox toggles).

```typescript
import { withAuth } from "@src/lib/auth-guard";
import { db } from "@/db";
import { task } from "@/db/schema/task";
import { eq, and } from "drizzle-orm";

export const GET = withAuth(async (_request, { user }) => {
  const tasks = await db
    .select()
    .from(task)
    .where(eq(task.userId, user.id))
    .orderBy(task.sortOrder);

  return Response.json({ tasks });
});

type PatchBody = {
  id: string;
  status?: "todo" | "in_progress" | "done" | "cancelled";
  priority?: "low" | "medium" | "high" | "urgent";
  title?: string;
  description?: string;
};

export const PATCH = withAuth(async (request, { user }) => {
  const body = (await request.json()) as PatchBody;

  if (!body.id) {
    return Response.json(
      { error: "Task ID is required" },
      { status: 400 }
    );
  }

  const updates: Record<string, unknown> = {
    updatedAt: new Date(),
  };
  if (body.status !== undefined) updates.status = body.status;
  if (body.priority !== undefined) updates.priority = body.priority;
  if (body.title !== undefined) updates.title = body.title;
  if (body.description !== undefined)
    updates.description = body.description;

  const [updated] = await db
    .update(task)
    .set(updates)
    .where(and(eq(task.id, body.id), eq(task.userId, user.id)))
    .returning();

  if (!updated) {
    return Response.json(
      { error: "Task not found" },
      { status: 404 }
    );
  }

  return Response.json({ task: updated });
});
```

## Usage

Once installed, the AI automatically creates tasks from conversation:

```
User: "I need to buy groceries, schedule a dentist appointment, and file my taxes before April"

AI: [calls createTask 3 times]
  - "Buy groceries" (medium priority)
  - "Schedule dentist appointment" (medium priority)
  - "File taxes" (high priority)

"I've created 3 tasks for you! I set 'File taxes' as high priority since you mentioned a deadline."
```

Users can also interact directly:

```
User: "What are my tasks?"
AI: [calls listTasks] → displays the list

User: "Mark the groceries task as done"
AI: [calls updateTask with status: "done"]

User: "Change the taxes priority to urgent"
AI: [calls updateTask with priority: "urgent"]
```

### Direct UI Interaction

The task list panel supports direct interaction without going through the AI:

- **Checkbox**: Click to toggle between "todo" and "done"
- **Priority badges**: Visual indicator of task priority (color-coded)
- **Filter tabs**: Filter by status (All, To Do, Active, Done)
- **Expandable descriptions**: Click a task to see its full description
- **Progress footer**: Shows "X of Y completed"

## Acceptance Criteria

- Tell AI "I need to buy groceries, schedule a dentist appointment, and file taxes" -- 3 tasks created with appropriate priorities
- Task list panel shows tasks with checkboxes and priority badges
- Click a checkbox -- task status toggles between "todo" and "done"
- Ask "what are my tasks" -- AI calls listTasks and reports the list
- Ask "mark groceries as done" -- AI calls updateTask, task shows as completed
- Filter tabs work: selecting "Done" shows only completed tasks
- Tasks persist across page refreshes (stored in Postgres)
- Tasks are scoped to the authenticated user
- After applying, `bunx drizzle-kit push` creates the `task` table
- `tsc` passes with no errors
