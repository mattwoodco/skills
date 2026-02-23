---
name: ai-meeting-notes
description: AI-powered meeting notes — generates executive summaries, key decisions, action items, and timestamped timelines from transcripts using structured output. Use this skill when the user says "add meeting notes", "setup ai meeting notes", "meeting summary", "extract action items", or "ai meeting notes".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [transcription, ai-core, ai-tools, db]
---

# AI Meeting Notes

Generates structured meeting notes from transcripts using the AI SDK's `generateObject` with Zod schemas. Extracts executive summaries, key decisions, action items with assignees, follow-up questions, and a timestamped timeline of key moments. Stores results in Postgres via Drizzle and exposes both API routes and React components for rendering.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `ai-core` skill installed (`getModel()` available at `@src/lib/ai`)
- `transcription` skill installed (provides `Transcript` type and transcript storage)
- `ai-tools` skill installed (provides `tool()` from AI SDK for tool definitions)
- `db` skill installed (Drizzle ORM + Postgres)
- shadcn/ui initialized

## Installation

No new packages required. Uses `ai` (already installed via `ai-core`).

Install shadcn components if not already present:

```bash
bunx shadcn@latest add card badge button collapsible checkbox avatar scroll-area
```

## Environment Variables

No additional environment variables required. Uses `AI_GATEWAY_API_KEY` and `AI_GATEWAY_MODEL` from the `ai-core` skill.

## What Gets Created

```
src/
├── lib/
│   ├── ai/
│   │   ├── meeting-notes.ts                    # generateMeetingNotes(transcript) — structured output
│   │   ├── types-meeting-notes.ts              # MeetingNotes, ActionItem, Decision, KeyMoment types
│   │   └── tools/
│   │       └── meeting-notes-tool.ts           # AI tool definition for meeting notes generation
│   └── db/
│       └── schema/
│           └── meeting-notes.ts                # meeting_notes + action_items Drizzle tables
├── components/
│   └── ai/
│       ├── meeting-summary.tsx                 # Full meeting summary card with collapsible sections
│       ├── action-items.tsx                    # Checklist of extracted action items
│       └── meeting-timeline.tsx                # Vertical timeline of key moments
└── app/
    └── api/
        └── ai/
            └── meeting-notes/
                ├── route.ts                    # POST generate, GET list
                └── [id]/
                    └── route.ts                # GET meeting notes by id
```

## Database

After applying this skill, push the schema:

```bash
bunx drizzle-kit push
```

## Setup Steps

### Step 1: Create `src/lib/ai/types-meeting-notes.ts`

```typescript
export type ActionItem = {
  task: string;
  assignee: string;
  dueDate: string | null;
  priority: "low" | "medium" | "high" | "critical";
};

export type Decision = {
  description: string;
  rationale: string;
  madeBy: string;
};

export type KeyMoment = {
  timestamp: string;
  description: string;
  speaker: string;
  type: "decision" | "action" | "insight" | "question";
};

export type MeetingNotes = {
  executiveSummary: string;
  keyDecisions: Decision[];
  actionItems: ActionItem[];
  followUpQuestions: string[];
  keyMoments: KeyMoment[];
};

export type MeetingNotesRecord = {
  id: string;
  roomName: string;
  transcriptId: string;
  summary: string;
  decisions: Decision[];
  actionItems: ActionItem[];
  keyMoments: KeyMoment[];
  followUpQuestions: string[];
  createdAt: Date;
  userId: string;
};
```

### Step 2: Create `src/lib/ai/meeting-notes.ts`

```typescript
import { generateObject } from "ai";
import { z } from "zod";
import { getModel } from "@src/lib/ai";
import type { MeetingNotes } from "./types-meeting-notes";

const actionItemSchema = z.object({
  task: z.string().describe("The specific task to be completed"),
  assignee: z.string().describe("Person responsible for this task"),
  dueDate: z.string().nullable().describe("Due date in ISO format, or null if not specified"),
  priority: z.enum(["low", "medium", "high", "critical"]).describe("Priority level based on urgency and context"),
});

const decisionSchema = z.object({
  description: z.string().describe("What was decided"),
  rationale: z.string().describe("Why this decision was made"),
  madeBy: z.string().describe("Who made or proposed the decision"),
});

const keyMomentSchema = z.object({
  timestamp: z.string().describe("Timestamp in the transcript (e.g. '00:05:23')"),
  description: z.string().describe("What happened at this moment"),
  speaker: z.string().describe("Who was speaking"),
  type: z.enum(["decision", "action", "insight", "question"]).describe("Category of this moment"),
});

const meetingNotesSchema = z.object({
  executiveSummary: z.string().describe("A concise 2-4 sentence summary of the entire meeting"),
  keyDecisions: z.array(decisionSchema).describe("All decisions made during the meeting"),
  actionItems: z.array(actionItemSchema).describe("All action items with assignees and priorities"),
  followUpQuestions: z.array(z.string()).describe("Unresolved questions that need follow-up"),
  keyMoments: z.array(keyMomentSchema).describe("Chronological list of key moments with timestamps"),
});

type Transcript = {
  id: string;
  roomName: string;
  content: string;
  speakers: string[];
  duration: number;
};

export async function generateMeetingNotes(transcript: Transcript): Promise<MeetingNotes> {
  const { object } = await generateObject({
    model: getModel(),
    schema: meetingNotesSchema,
    prompt: `You are an expert meeting analyst. Analyze the following meeting transcript and extract structured meeting notes.

Meeting Room: ${transcript.roomName}
Duration: ${Math.floor(transcript.duration / 60)} minutes
Participants: ${transcript.speakers.join(", ")}

--- TRANSCRIPT ---
${transcript.content}
--- END TRANSCRIPT ---

Extract:
1. An executive summary (2-4 sentences covering the key topics and outcomes)
2. All key decisions made (with rationale and who made them)
3. All action items (with specific assignees, due dates if mentioned, and priority)
4. Follow-up questions that were raised but not resolved
5. Key moments in chronological order with timestamps from the transcript

Be precise with assignees — use the speaker names from the transcript. For priorities, infer from context (urgency words, deadlines, business impact). For timestamps, use the format from the transcript.`,
  });

  return object;
}
```

### Step 3: Create `src/lib/ai/tools/meeting-notes-tool.ts`

```typescript
import { tool } from "ai";
import { z } from "zod/v4";
import { db } from "@src/lib/db";
import { meetingNotes, actionItems } from "@src/lib/db/schema/meeting-notes";
import { transcripts } from "@src/lib/db/schema/transcripts";
import { generateMeetingNotes } from "@src/lib/ai/meeting-notes";
import { eq } from "drizzle-orm";

type TranscriptRow = {
  id: string;
  roomName: string;
  content: string;
  speakers: string[];
  duration: number;
};

async function fetchTranscript(params: {
  transcriptId?: string;
  roomName?: string;
}): Promise<TranscriptRow | null> {
  if (params.transcriptId) {
    const rows = await db
      .select()
      .from(transcripts)
      .where(eq(transcripts.id, params.transcriptId))
      .limit(1);
    return (rows[0] as TranscriptRow | undefined) ?? null;
  }

  if (params.roomName) {
    const rows = await db
      .select()
      .from(transcripts)
      .where(eq(transcripts.roomName, params.roomName))
      .orderBy(transcripts.createdAt)
      .limit(1);
    return (rows[0] as TranscriptRow | undefined) ?? null;
  }

  return null;
}

export const meetingNotesTool = tool({
  description:
    "Generate structured meeting notes from a transcript. Extracts executive summary, key decisions, action items, follow-up questions, and key moments with timestamps.",
  inputSchema: z.object({
    transcriptId: z
      .string()
      .optional()
      .describe("The ID of the transcript to generate notes for"),
    roomName: z
      .string()
      .optional()
      .describe("The room name to find the latest transcript for"),
  }),
  execute: async ({ transcriptId, roomName }) => {
    if (!transcriptId && !roomName) {
      return { error: "Either transcriptId or roomName is required" };
    }

    const transcript = await fetchTranscript({ transcriptId, roomName });
    if (!transcript) {
      return { error: "Transcript not found" };
    }

    const notes = await generateMeetingNotes(transcript);

    // Store the generated notes
    const [inserted] = await db
      .insert(meetingNotes)
      .values({
        roomName: transcript.roomName,
        transcriptId: transcript.id,
        summary: notes.executiveSummary,
        decisions: notes.keyDecisions,
        actionItems: notes.actionItems,
        keyMoments: notes.keyMoments,
        followUpQuestions: notes.followUpQuestions,
        userId: "system",
      })
      .returning();

    // Store action items in their own table for tracking
    if (notes.actionItems.length > 0) {
      await db.insert(actionItems).values(
        notes.actionItems.map((item) => ({
          meetingNoteId: inserted.id,
          task: item.task,
          assignee: item.assignee,
          dueDate: item.dueDate ? new Date(item.dueDate) : null,
          priority: item.priority,
        }))
      );
    }

    return {
      meetingNoteId: inserted.id,
      executiveSummary: notes.executiveSummary,
      decisionsCount: notes.keyDecisions.length,
      actionItemsCount: notes.actionItems.length,
      followUpQuestionsCount: notes.followUpQuestions.length,
      keyMomentsCount: notes.keyMoments.length,
    };
  },
});
```

### Step 4: Create `src/lib/db/schema/meeting-notes.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  jsonb,
  boolean,
} from "drizzle-orm/pg-core";
import type { ActionItem, Decision, KeyMoment } from "@src/lib/ai/types-meeting-notes";

export const meetingNotes = pgTable("meeting_notes", {
  id: uuid("id").defaultRandom().primaryKey(),
  roomName: text("room_name").notNull(),
  transcriptId: text("transcript_id").notNull(),
  summary: text("summary").notNull(),
  decisions: jsonb("decisions").$type<Decision[]>().notNull(),
  actionItems: jsonb("action_items").$type<ActionItem[]>().notNull(),
  keyMoments: jsonb("key_moments").$type<KeyMoment[]>().notNull(),
  followUpQuestions: jsonb("follow_up_questions").$type<string[]>().notNull(),
  userId: text("user_id").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});

export const actionItems = pgTable("action_items", {
  id: uuid("id").defaultRandom().primaryKey(),
  meetingNoteId: uuid("meeting_note_id")
    .notNull()
    .references(() => meetingNotes.id, { onDelete: "cascade" }),
  task: text("task").notNull(),
  assignee: text("assignee").notNull(),
  dueDate: timestamp("due_date", { withTimezone: true }),
  priority: text("priority", {
    enum: ["low", "medium", "high", "critical"],
  }).notNull().default("medium"),
  completed: boolean("completed").notNull().default(false),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});
```

### Step 5: Add exports to `src/lib/db/schema/index.ts`

```typescript
export * from "./meeting-notes";
```

### Step 6: Create `src/components/ai/meeting-summary.tsx`

```tsx
"use client";

import { useId, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { ScrollArea } from "@/components/ui/scroll-area";
import { ChevronDown, ChevronRight } from "lucide-react";
import type { Decision, ActionItem, KeyMoment } from "@src/lib/ai/types-meeting-notes";

type MeetingSummaryProps = {
  summary: string;
  decisions: Decision[];
  actionItems: ActionItem[];
  followUpQuestions: string[];
  keyMoments: KeyMoment[];
  roomName: string;
  createdAt: string;
};

function SectionHeader({
  title,
  count,
  isOpen,
}: {
  title: string;
  count: number;
  isOpen: boolean;
}) {
  return (
    <div className="flex items-center gap-2">
      {isOpen ? (
        <ChevronDown className="h-4 w-4" />
      ) : (
        <ChevronRight className="h-4 w-4" />
      )}
      <span className="font-medium">{title}</span>
      <Badge variant="secondary" className="text-xs">
        {count}
      </Badge>
    </div>
  );
}

export function MeetingSummary({
  summary,
  decisions,
  actionItems,
  followUpQuestions,
  keyMoments,
  roomName,
  createdAt,
}: MeetingSummaryProps) {
  const sectionId = useId();
  const [openSections, setOpenSections] = useState<Record<string, boolean>>({
    decisions: true,
    actions: true,
    questions: false,
    moments: false,
  });

  const toggleSection = (section: string) => {
    setOpenSections((prev) => ({ ...prev, [section]: !prev[section] }));
  };

  const priorityColor: Record<string, string> = {
    critical: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
    high: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200",
    medium: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
    low: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
  };

  const momentTypeColor: Record<string, string> = {
    decision: "bg-blue-500",
    action: "bg-orange-500",
    insight: "bg-purple-500",
    question: "bg-yellow-500",
  };

  return (
    <ScrollArea className="h-full">
      <div className="space-y-4 p-4">
        {/* Header */}
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle className="text-lg">Meeting Summary</CardTitle>
              <Badge variant="outline">{roomName}</Badge>
            </div>
            <p className="text-sm text-muted-foreground">
              {new Date(createdAt).toLocaleDateString("en-US", {
                weekday: "long",
                year: "numeric",
                month: "long",
                day: "numeric",
                hour: "2-digit",
                minute: "2-digit",
              })}
            </p>
          </CardHeader>
          <CardContent>
            <p className="text-sm leading-relaxed">{summary}</p>
          </CardContent>
        </Card>

        {/* Key Decisions */}
        <Collapsible
          open={openSections.decisions}
          onOpenChange={() => toggleSection("decisions")}
        >
          <Card>
            <CollapsibleTrigger asChild>
              <CardHeader className="cursor-pointer hover:bg-muted/50">
                <SectionHeader
                  title="Key Decisions"
                  count={decisions.length}
                  isOpen={openSections.decisions ?? false}
                />
              </CardHeader>
            </CollapsibleTrigger>
            <CollapsibleContent>
              <CardContent className="space-y-3 pt-0">
                {decisions.map((decision, idx) => (
                  <div
                    key={`${sectionId}-decision-${decision.description.slice(0, 20)}-${idx}`}
                    className="rounded-lg border p-3"
                  >
                    <p className="font-medium text-sm">{decision.description}</p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      {decision.rationale}
                    </p>
                    <Badge variant="outline" className="mt-2 text-xs">
                      {decision.madeBy}
                    </Badge>
                  </div>
                ))}
                {decisions.length === 0 && (
                  <p className="text-sm text-muted-foreground">
                    No decisions recorded.
                  </p>
                )}
              </CardContent>
            </CollapsibleContent>
          </Card>
        </Collapsible>

        {/* Action Items */}
        <Collapsible
          open={openSections.actions}
          onOpenChange={() => toggleSection("actions")}
        >
          <Card>
            <CollapsibleTrigger asChild>
              <CardHeader className="cursor-pointer hover:bg-muted/50">
                <SectionHeader
                  title="Action Items"
                  count={actionItems.length}
                  isOpen={openSections.actions ?? false}
                />
              </CardHeader>
            </CollapsibleTrigger>
            <CollapsibleContent>
              <CardContent className="space-y-2 pt-0">
                {actionItems.map((item, idx) => (
                  <div
                    key={`${sectionId}-action-${item.task.slice(0, 20)}-${idx}`}
                    className="flex items-start gap-3 rounded-lg border p-3"
                  >
                    <div className="flex-1">
                      <p className="text-sm font-medium">{item.task}</p>
                      <div className="mt-1 flex flex-wrap items-center gap-2">
                        <Badge variant="outline" className="text-xs">
                          {item.assignee}
                        </Badge>
                        <Badge
                          className={`text-xs ${priorityColor[item.priority] ?? ""}`}
                        >
                          {item.priority}
                        </Badge>
                        {item.dueDate && (
                          <span className="text-xs text-muted-foreground">
                            Due: {new Date(item.dueDate).toLocaleDateString()}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
                {actionItems.length === 0 && (
                  <p className="text-sm text-muted-foreground">
                    No action items recorded.
                  </p>
                )}
              </CardContent>
            </CollapsibleContent>
          </Card>
        </Collapsible>

        {/* Follow-up Questions */}
        <Collapsible
          open={openSections.questions}
          onOpenChange={() => toggleSection("questions")}
        >
          <Card>
            <CollapsibleTrigger asChild>
              <CardHeader className="cursor-pointer hover:bg-muted/50">
                <SectionHeader
                  title="Follow-up Questions"
                  count={followUpQuestions.length}
                  isOpen={openSections.questions ?? false}
                />
              </CardHeader>
            </CollapsibleTrigger>
            <CollapsibleContent>
              <CardContent className="pt-0">
                <ul className="space-y-2">
                  {followUpQuestions.map((question, idx) => (
                    <li
                      key={`${sectionId}-question-${question.slice(0, 20)}-${idx}`}
                      className="flex items-start gap-2 text-sm"
                    >
                      <span className="mt-0.5 text-muted-foreground">?</span>
                      <span>{question}</span>
                    </li>
                  ))}
                </ul>
                {followUpQuestions.length === 0 && (
                  <p className="text-sm text-muted-foreground">
                    No follow-up questions.
                  </p>
                )}
              </CardContent>
            </CollapsibleContent>
          </Card>
        </Collapsible>

        {/* Key Moments Timeline */}
        <Collapsible
          open={openSections.moments}
          onOpenChange={() => toggleSection("moments")}
        >
          <Card>
            <CollapsibleTrigger asChild>
              <CardHeader className="cursor-pointer hover:bg-muted/50">
                <SectionHeader
                  title="Key Moments"
                  count={keyMoments.length}
                  isOpen={openSections.moments ?? false}
                />
              </CardHeader>
            </CollapsibleTrigger>
            <CollapsibleContent>
              <CardContent className="pt-0">
                <div className="space-y-3">
                  {keyMoments.map((moment, idx) => (
                    <div
                      key={`${sectionId}-moment-${moment.timestamp}-${idx}`}
                      className="flex items-start gap-3"
                    >
                      <div
                        className={`mt-1 h-2.5 w-2.5 shrink-0 rounded-full ${momentTypeColor[moment.type] ?? "bg-gray-500"}`}
                      />
                      <div className="flex-1">
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-xs text-muted-foreground">
                            {moment.timestamp}
                          </span>
                          <Badge variant="outline" className="text-xs">
                            {moment.speaker}
                          </Badge>
                          <Badge variant="secondary" className="text-xs capitalize">
                            {moment.type}
                          </Badge>
                        </div>
                        <p className="mt-0.5 text-sm">{moment.description}</p>
                      </div>
                    </div>
                  ))}
                </div>
                {keyMoments.length === 0 && (
                  <p className="text-sm text-muted-foreground">
                    No key moments recorded.
                  </p>
                )}
              </CardContent>
            </CollapsibleContent>
          </Card>
        </Collapsible>
      </div>
    </ScrollArea>
  );
}
```

### Step 7: Create `src/components/ai/action-items.tsx`

```tsx
"use client";

import { useId, useState, useCallback } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Loader2 } from "lucide-react";

type ActionItemData = {
  id: string;
  task: string;
  assignee: string;
  dueDate: string | null;
  priority: "low" | "medium" | "high" | "critical";
  completed: boolean;
};

type ActionItemsProps = {
  items: ActionItemData[];
  meetingNoteId: string;
  onCreateTask?: (item: ActionItemData) => void;
};

export function ActionItems({ items, meetingNoteId, onCreateTask }: ActionItemsProps) {
  const listId = useId();
  const [localItems, setLocalItems] = useState<ActionItemData[]>(items);
  const [togglingIds, setTogglingIds] = useState<Set<string>>(new Set());

  const priorityColor: Record<string, string> = {
    critical: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
    high: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200",
    medium: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
    low: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
  };

  const handleToggle = useCallback(
    async (itemId: string, completed: boolean) => {
      setTogglingIds((prev) => new Set(prev).add(itemId));

      try {
        const res = await fetch(`/api/ai/meeting-notes/${meetingNoteId}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ actionItemId: itemId, completed }),
        });

        if (res.ok) {
          setLocalItems((prev) =>
            prev.map((item) =>
              item.id === itemId ? { ...item, completed } : item
            )
          );
        }
      } catch {
        // Revert on failure — state unchanged
      } finally {
        setTogglingIds((prev) => {
          const next = new Set(prev);
          next.delete(itemId);
          return next;
        });
      }
    },
    [meetingNoteId]
  );

  const completedCount = localItems.filter((item) => item.completed).length;

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle className="text-lg">Action Items</CardTitle>
          <Badge variant="secondary">
            {completedCount}/{localItems.length} done
          </Badge>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {localItems.map((item) => {
          const isToggling = togglingIds.has(item.id);

          return (
            <div
              key={`${listId}-${item.id}`}
              className={`flex items-start gap-3 rounded-lg border p-3 transition-colors ${
                item.completed ? "bg-muted/50 opacity-60" : ""
              }`}
            >
              <div className="pt-0.5">
                {isToggling ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Checkbox
                    checked={item.completed}
                    onCheckedChange={(checked) =>
                      handleToggle(item.id, checked === true)
                    }
                  />
                )}
              </div>

              <div className="flex-1">
                <p
                  className={`text-sm font-medium ${
                    item.completed ? "line-through" : ""
                  }`}
                >
                  {item.task}
                </p>
                <div className="mt-1 flex flex-wrap items-center gap-2">
                  <Badge variant="outline" className="text-xs">
                    {item.assignee}
                  </Badge>
                  <Badge
                    className={`text-xs ${priorityColor[item.priority] ?? ""}`}
                  >
                    {item.priority}
                  </Badge>
                  {item.dueDate && (
                    <span className="text-xs text-muted-foreground">
                      Due: {new Date(item.dueDate).toLocaleDateString()}
                    </span>
                  )}
                </div>
              </div>

              {onCreateTask && !item.completed && (
                <Button
                  variant="outline"
                  size="sm"
                  className="shrink-0 text-xs"
                  onClick={() => onCreateTask(item)}
                >
                  Create Task
                </Button>
              )}
            </div>
          );
        })}

        {localItems.length === 0 && (
          <p className="text-sm text-muted-foreground">
            No action items found.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
```

### Step 8: Create `src/components/ai/meeting-timeline.tsx`

```tsx
"use client";

import { useId } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { KeyMoment } from "@src/lib/ai/types-meeting-notes";

type MeetingTimelineProps = {
  moments: KeyMoment[];
  onSeek?: (timestamp: string) => void;
};

export function MeetingTimeline({ moments, onSeek }: MeetingTimelineProps) {
  const listId = useId();

  const typeConfig: Record<
    string,
    { color: string; bgColor: string; label: string }
  > = {
    decision: {
      color: "border-blue-500",
      bgColor: "bg-blue-500",
      label: "Decision",
    },
    action: {
      color: "border-orange-500",
      bgColor: "bg-orange-500",
      label: "Action",
    },
    insight: {
      color: "border-purple-500",
      bgColor: "bg-purple-500",
      label: "Insight",
    },
    question: {
      color: "border-yellow-500",
      bgColor: "bg-yellow-500",
      label: "Question",
    },
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-lg">Meeting Timeline</CardTitle>
      </CardHeader>
      <CardContent>
        <ScrollArea className="h-[400px]">
          <div className="relative ml-4">
            {/* Vertical line */}
            <div className="absolute left-0 top-0 h-full w-px bg-border" />

            <div className="space-y-6">
              {moments.map((moment, idx) => {
                const config = typeConfig[moment.type] ?? {
                  color: "border-gray-500",
                  bgColor: "bg-gray-500",
                  label: moment.type,
                };

                return (
                  <div
                    key={`${listId}-${moment.timestamp}-${idx}`}
                    className="relative pl-6"
                  >
                    {/* Dot on the vertical line */}
                    <div
                      className={`absolute -left-[5px] top-1.5 h-2.5 w-2.5 rounded-full ${config.bgColor}`}
                    />

                    <div className="space-y-1">
                      <div className="flex items-center gap-2">
                        {onSeek ? (
                          <Button
                            variant="ghost"
                            size="sm"
                            className="h-auto p-0 font-mono text-xs text-muted-foreground hover:text-foreground"
                            onClick={() => onSeek(moment.timestamp)}
                          >
                            {moment.timestamp}
                          </Button>
                        ) : (
                          <span className="font-mono text-xs text-muted-foreground">
                            {moment.timestamp}
                          </span>
                        )}
                        <Badge variant="outline" className="text-xs">
                          {moment.speaker}
                        </Badge>
                        <Badge
                          variant="secondary"
                          className="text-xs capitalize"
                        >
                          {config.label}
                        </Badge>
                      </div>
                      <p className="text-sm">{moment.description}</p>
                    </div>
                  </div>
                );
              })}
            </div>

            {moments.length === 0 && (
              <p className="text-sm text-muted-foreground pl-6">
                No key moments recorded.
              </p>
            )}
          </div>
        </ScrollArea>
      </CardContent>
    </Card>
  );
}
```

### Step 9: Create `src/app/api/ai/meeting-notes/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod";
import { db } from "@src/lib/db";
import { meetingNotes, actionItems } from "@src/lib/db/schema/meeting-notes";
import { transcripts } from "@src/lib/db/schema/transcripts";
import { generateMeetingNotes } from "@src/lib/ai/meeting-notes";
import { withAuth } from "@src/lib/auth-guard";
import { eq, desc, and } from "drizzle-orm";

const generateSchema = z.object({
  transcriptId: z.string().optional(),
  roomName: z.string().optional(),
  transcriptContent: z.string().optional(),
  speakers: z.array(z.string()).optional(),
  duration: z.number().optional(),
}).refine(
  (data) => data.transcriptId || data.roomName || data.transcriptContent,
  { message: "Either transcriptId, roomName, or transcriptContent is required" }
);

export const POST = withAuth(async (request, { user }) => {
  const body = await request.json();
  const params = generateSchema.parse(body);

  let transcript: {
    id: string;
    roomName: string;
    content: string;
    speakers: string[];
    duration: number;
  };

  if (params.transcriptContent) {
    // Direct transcript content provided
    transcript = {
      id: "inline",
      roomName: params.roomName ?? "unknown",
      content: params.transcriptContent,
      speakers: params.speakers ?? [],
      duration: params.duration ?? 0,
    };
  } else {
    // Fetch from database via transcription skill
    let rows: (typeof transcripts.$inferSelect)[];
    if (params.transcriptId) {
      rows = await db
        .select()
        .from(transcripts)
        .where(eq(transcripts.id, params.transcriptId))
        .limit(1);
    } else if (params.roomName) {
      rows = await db
        .select()
        .from(transcripts)
        .where(eq(transcripts.roomName, params.roomName))
        .orderBy(desc(transcripts.createdAt))
        .limit(1);
    } else {
      rows = [];
    }

    if (rows.length === 0) {
      return NextResponse.json(
        { error: "Transcript not found" },
        { status: 404 }
      );
    }

    const row = rows[0];
    transcript = {
      id: row.id,
      roomName: row.roomName,
      content: row.content,
      speakers: row.speakers,
      duration: row.duration,
    };
  }

  const notes = await generateMeetingNotes(transcript);

  // Store in database
  const [inserted] = await db
    .insert(meetingNotes)
    .values({
      roomName: transcript.roomName,
      transcriptId: transcript.id,
      summary: notes.executiveSummary,
      decisions: notes.keyDecisions,
      actionItems: notes.actionItems,
      keyMoments: notes.keyMoments,
      followUpQuestions: notes.followUpQuestions,
      userId: user.id,
    })
    .returning();

  // Store individual action items
  if (notes.actionItems.length > 0) {
    await db.insert(actionItems).values(
      notes.actionItems.map((item) => ({
        meetingNoteId: inserted.id,
        task: item.task,
        assignee: item.assignee,
        dueDate: item.dueDate ? new Date(item.dueDate) : null,
        priority: item.priority,
      }))
    );
  }

  // Fetch inserted action items with their IDs
  const insertedActionItems = await db
    .select()
    .from(actionItems)
    .where(eq(actionItems.meetingNoteId, inserted.id));

  return NextResponse.json({
    ...inserted,
    actionItemRecords: insertedActionItems,
  });
});

export const GET = withAuth(async (request, { user }) => {
  const { searchParams } = new URL(request.url);
  const limit = Math.min(parseInt(searchParams.get("limit") ?? "20", 10), 100);
  const roomName = searchParams.get("roomName");

  const whereClause = roomName
    ? and(eq(meetingNotes.userId, user.id), eq(meetingNotes.roomName, roomName))
    : eq(meetingNotes.userId, user.id);

  const notes = await db
    .select()
    .from(meetingNotes)
    .where(whereClause)
    .orderBy(desc(meetingNotes.createdAt))
    .limit(limit);

  return NextResponse.json(notes);
});
```

### Step 10: Create `src/app/api/ai/meeting-notes/[id]/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod";
import { db } from "@src/lib/db";
import { meetingNotes, actionItems } from "@src/lib/db/schema/meeting-notes";
import { eq, and } from "drizzle-orm";
import { auth } from "@src/lib/auth";
import { headers } from "next/headers";

type RouteParams = { params: Promise<{ id: string }> };

/** GET /api/ai/meeting-notes/[id] — Get meeting notes by ID with action items */
export async function GET(
  _request: Request,
  { params }: RouteParams
): Promise<NextResponse> {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id: noteId } = await params;

  const notes = await db
    .select()
    .from(meetingNotes)
    .where(
      and(
        eq(meetingNotes.id, noteId),
        eq(meetingNotes.userId, session.user.id)
      )
    )
    .limit(1);

  if (notes.length === 0) {
    return NextResponse.json({ error: "Meeting notes not found" }, { status: 404 });
  }

  const items = await db
    .select()
    .from(actionItems)
    .where(eq(actionItems.meetingNoteId, noteId));

  return NextResponse.json({
    ...notes[0],
    actionItemRecords: items,
  });
}

const patchSchema = z.object({
  actionItemId: z.string(),
  completed: z.boolean(),
});

/** PATCH /api/ai/meeting-notes/[id] — Toggle action item completion */
export async function PATCH(
  request: Request,
  { params }: RouteParams
): Promise<NextResponse> {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id: noteId } = await params;

  // Verify ownership
  const notes = await db
    .select({ id: meetingNotes.id })
    .from(meetingNotes)
    .where(
      and(
        eq(meetingNotes.id, noteId),
        eq(meetingNotes.userId, session.user.id)
      )
    )
    .limit(1);

  if (notes.length === 0) {
    return NextResponse.json({ error: "Meeting notes not found" }, { status: 404 });
  }

  const body = await request.json();
  const parsed = patchSchema.parse(body);

  const [updated] = await db
    .update(actionItems)
    .set({ completed: parsed.completed })
    .where(
      and(
        eq(actionItems.id, parsed.actionItemId),
        eq(actionItems.meetingNoteId, noteId)
      )
    )
    .returning();

  if (!updated) {
    return NextResponse.json({ error: "Action item not found" }, { status: 404 });
  }

  return NextResponse.json(updated);
}
```

## Usage

### Generate meeting notes from a transcript

```typescript
const response = await fetch("/api/ai/meeting-notes", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ transcriptId: "transcript-uuid-here" }),
});
const notes = await response.json();
// { id, summary, decisions, actionItems, keyMoments, followUpQuestions, ... }
```

### Generate from inline transcript content

```typescript
const response = await fetch("/api/ai/meeting-notes", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    transcriptContent: "00:00:00 Alice: Let's discuss the Q3 roadmap...",
    roomName: "roadmap-planning",
    speakers: ["Alice", "Bob", "Charlie"],
    duration: 3600,
  }),
});
```

### List meeting notes

```typescript
const response = await fetch("/api/ai/meeting-notes?limit=10");
const notes = await response.json();
```

### Get meeting notes by ID

```typescript
const response = await fetch(`/api/ai/meeting-notes/${noteId}`);
const { actionItemRecords, ...notes } = await response.json();
```

### Toggle action item completion

```typescript
await fetch(`/api/ai/meeting-notes/${noteId}`, {
  method: "PATCH",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ actionItemId: "item-uuid", completed: true }),
});
```

### Render meeting summary in a component

```tsx
import { MeetingSummary } from "@/components/ai/meeting-summary";
import { ActionItems } from "@/components/ai/action-items";
import { MeetingTimeline } from "@/components/ai/meeting-timeline";

<MeetingSummary
  summary={notes.summary}
  decisions={notes.decisions}
  actionItems={notes.actionItems}
  followUpQuestions={notes.followUpQuestions}
  keyMoments={notes.keyMoments}
  roomName={notes.roomName}
  createdAt={notes.createdAt}
/>

<ActionItems
  items={actionItemRecords}
  meetingNoteId={notes.id}
  onCreateTask={(item) => console.log("Create task:", item)}
/>

<MeetingTimeline
  moments={notes.keyMoments}
  onSeek={(timestamp) => console.log("Seek to:", timestamp)}
/>
```

### Use as an AI tool

The `meetingNotesTool` can be registered with the ai-tools skill so the AI assistant can generate meeting notes on demand during chat:

```typescript
import { meetingNotesTool } from "@src/lib/ai/tools/meeting-notes-tool";

// In your tools registration:
const tools = {
  generateMeetingNotes: meetingNotesTool,
};
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/ai/meeting-notes` | Generate meeting notes from transcript |
| GET | `/api/ai/meeting-notes` | List meeting notes for current user |
| GET | `/api/ai/meeting-notes/[id]` | Get meeting notes by ID with action items |
| PATCH | `/api/ai/meeting-notes/[id]` | Toggle action item completion |

## Acceptance Criteria

- POST with a transcriptId generates structured meeting notes with all sections populated
- POST with inline transcriptContent works without a stored transcript
- Generated notes include executive summary, decisions, action items, follow-up questions, and key moments
- Action items have assignees, priorities, and due dates extracted from context
- Key moments have timestamps matching the transcript
- GET list returns user's meeting notes sorted by creation date
- GET by ID returns notes with associated action item records
- PATCH toggles action item completion state
- MeetingSummary component renders all sections with collapsible panels
- ActionItems component shows checkboxes, priority badges, and assignee labels
- MeetingTimeline component renders a vertical timeline with clickable timestamps
- Unauthenticated requests return 401
- `tsc` passes with no errors
- `bun run build` succeeds

## Troubleshooting

### "Transcript not found" error

**Symptoms**: POST returns 404 with "Transcript not found"

**Cause**: The transcript ID or room name doesn't match any stored transcripts.

**Fix**: Ensure the `transcription` skill is installed and transcripts are being stored. Alternatively, use `transcriptContent` to provide the transcript inline.

### Empty action items or decisions

**Symptoms**: Generated notes have empty arrays for some sections.

**Cause**: The transcript may be too short or the AI model couldn't identify structured content.

**Fix**: Ensure transcripts have clear speaker attribution and substantive discussion. Try a more capable model via `getModel("anthropic/claude-sonnet-4")` for better extraction.

### Zod schema validation errors

**Symptoms**: `generateObject` throws a validation error.

**Cause**: The AI model returned data that doesn't match the Zod schema.

**Fix**: This is handled by the AI SDK's retry logic. If persistent, check that the model supports structured output (most AI Gateway models do).
