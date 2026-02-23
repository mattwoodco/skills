---
name: queue
description: Background job queue with Inngest — serverless, works on Vercel, no Redis needed. Durable functions with retry, progress tracking, and job history. Use this skill when the user says "add queue", "setup jobs", "background jobs", "add inngest", or "async tasks".
author: "@mattwoodco"
version: 1.1.0
created: 2026-02-13
updated: 2026-02-18
dependencies: [db, env-config, auth]
---

# Background Job Queue (Inngest)

Serverless background job queue using [Inngest](https://www.inngest.com). Jobs survive crashes, retry with exponential backoff, report progress, and persist history to Postgres. Works on Vercel — no Redis or worker processes needed.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `db` skill applied (Drizzle + Postgres)
- `env-config` skill applied (Zod env validation)
- `auth` skill applied (for user context)

## Installation

```bash
bun add inngest
```

## Environment Variables

Add to `.env.local`:

```env
# Inngest
INNGEST_EVENT_KEY=local
INNGEST_SIGNING_KEY=local
```

Add to `src/env.ts` server schema:

```typescript
INNGEST_EVENT_KEY: z.string().default("local"),
INNGEST_SIGNING_KEY: z.string().default("local"),
```

## What Gets Created

```
src/
├── app/
│   └── api/
│       ├── inngest/
│       │   └── route.ts              # Inngest serve endpoint
│       └── jobs/
│           ├── route.ts              # GET list jobs, POST submit job
│           └── [id]/
│               └── route.ts          # GET job status/result
└── lib/
    ├── db/
    │   └── schema/
    │       └── jobs.ts               # Drizzle schema: jobs table
    └── queue/
        ├── client.ts                 # Inngest client setup
        ├── types.ts                  # Job types and event schemas
        └── functions/
            └── example-job.ts        # Example Inngest function
```

## Setup Steps

### Step 1: Create `src/lib/db/schema/jobs.ts`

```typescript
import { pgTable, text, integer, timestamp, jsonb, uuid } from "drizzle-orm/pg-core";

export const jobs = pgTable("jobs", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull(),
  type: text("type").notNull(),
  status: text("status", {
    enum: ["queued", "running", "completed", "failed"],
  }).notNull().default("queued"),
  progress: integer("progress").notNull().default(0),
  input: jsonb("input"),
  result: jsonb("result"),
  error: text("error"),
  inngestRunId: text("inngest_run_id"),
  startedAt: timestamp("started_at", { withTimezone: true }),
  completedAt: timestamp("completed_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).defaultNow().notNull(),
});

export type Job = typeof jobs.$inferSelect;
export type NewJob = typeof jobs.$inferInsert;
```

### Step 2: Add export to `src/lib/db/schema/index.ts`

Find the existing exports in `src/lib/db/schema/index.ts` and add:

```typescript
export * from "./jobs";
```

### Step 3: Create `src/lib/queue/types.ts`

```typescript
type JobEventBase = {
  data: {
    jobId: string;
    userId: string;
  };
};

export type QueueEvents = {
  "job/example": JobEventBase & {
    data: JobEventBase["data"] & {
      prompt: string;
    };
  };
};
```

### Step 4: Create `src/lib/queue/client.ts`

```typescript
import { Inngest } from "inngest";

export const inngest = new Inngest({
  id: "my-app",
});
```

> **Note:** The Inngest client is intentionally untyped at the client level. Type safety is enforced per-function via `createFunction()` event triggers. This allows the generic `/api/jobs` route to send events for any job type without type conflicts.

### Step 5: Create `src/lib/queue/functions/example-job.ts`

```typescript
import { inngest } from "@src/lib/queue/client";
import { db } from "@src/lib/db";
import { jobs } from "@src/lib/db/schema";
import { eq } from "drizzle-orm";

export const exampleJob = inngest.createFunction(
  {
    id: "example-job",
    retries: 3,
  },
  { event: "job/example" },
  async ({ event, step }) => {
    const { jobId, userId, prompt } = event.data;

    // Mark as running
    await step.run("mark-running", async () => {
      await db
        .update(jobs)
        .set({
          status: "running",
          startedAt: new Date(),
          updatedAt: new Date(),
        })
        .where(eq(jobs.id, jobId));
    });

    // Simulate work with progress updates
    const result = await step.run("process", async () => {
      // Update progress to 50%
      await db
        .update(jobs)
        .set({ progress: 50, updatedAt: new Date() })
        .where(eq(jobs.id, jobId));

      // Do the actual work here
      const output = { message: `Processed: ${prompt}`, timestamp: Date.now() };

      // Update progress to 100%
      await db
        .update(jobs)
        .set({ progress: 100, updatedAt: new Date() })
        .where(eq(jobs.id, jobId));

      return output;
    });

    // Mark as completed
    await step.run("mark-completed", async () => {
      await db
        .update(jobs)
        .set({
          status: "completed",
          result,
          completedAt: new Date(),
          updatedAt: new Date(),
        })
        .where(eq(jobs.id, jobId));
    });

    return result;
  }
);
```

### Step 6: Create `src/app/api/inngest/route.ts`

```typescript
import { serve } from "inngest/next";
import { inngest } from "@src/lib/queue/client";
import { exampleJob } from "@src/lib/queue/functions/example-job";

export const { GET, POST, PUT } = serve({
  client: inngest,
  functions: [exampleJob],
});
```

### Step 7: Create `src/app/api/jobs/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod";
import { db } from "@src/lib/db";
import { jobs } from "@src/lib/db/schema";
import { eq, desc } from "drizzle-orm";
import { inngest } from "@src/lib/queue/client";
import { auth } from "@src/lib/auth";
import { headers } from "next/headers";

const submitSchema = z.object({
  type: z.string(),
  input: z.record(z.string(), z.unknown()).optional(),
});

export async function GET(request: Request) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const userJobs = await db
    .select()
    .from(jobs)
    .where(eq(jobs.userId, session.user.id))
    .orderBy(desc(jobs.createdAt))
    .limit(50);

  return NextResponse.json(userJobs);
}

export async function POST(request: Request) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json();
  const { type, input } = submitSchema.parse(body);

  // Create job record
  const [job] = await db
    .insert(jobs)
    .values({
      userId: session.user.id,
      type,
      input,
    })
    .returning();

  // Send event to Inngest
  await inngest.send({
    name: `job/${type}`,
    data: {
      jobId: job.id,
      userId: session.user.id,
      ...((input as Record<string, unknown>) ?? {}),
    },
  });

  return NextResponse.json(job, { status: 201 });
}
```

### Step 8: Create `src/app/api/jobs/[id]/route.ts`

```typescript
import { NextResponse } from "next/server";
import { db } from "@src/lib/db";
import { jobs } from "@src/lib/db/schema";
import { eq, and } from "drizzle-orm";
import { auth } from "@src/lib/auth";
import { headers } from "next/headers";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;

  const [job] = await db
    .select()
    .from(jobs)
    .where(and(eq(jobs.id, id), eq(jobs.userId, session.user.id)))
    .limit(1);

  if (!job) {
    return NextResponse.json({ error: "Job not found" }, { status: 404 });
  }

  return NextResponse.json(job);
}
```

### Step 9: Push database schema

```bash
bunx drizzle-kit push
```

## Usage

### Submit a job

```typescript
const response = await fetch("/api/jobs", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    type: "example",
    input: { prompt: "Generate something cool" },
  }),
});
const job = await response.json();
```

### Poll for status

```typescript
const response = await fetch(`/api/jobs/${job.id}`);
const status = await response.json();
// { id, status: "running", progress: 50, result: null }
```

### Register a new job function

1. Create a new function in `src/lib/queue/functions/`:

```typescript
import { inngest } from "@src/lib/queue/client";
import { db } from "@src/lib/db";
import { jobs } from "@src/lib/db/schema";
import { eq } from "drizzle-orm";

export const myCustomJob = inngest.createFunction(
  { id: "my-custom-job", retries: 3 },
  { event: "job/my-custom" },
  async ({ event, step }) => {
    const { jobId } = event.data;
    // your logic here
  }
);
```

1. Add it to the serve endpoint in `src/app/api/inngest/route.ts`:

```typescript
import { myCustomJob } from "@src/lib/queue/functions/my-custom-job";

export const { GET, POST, PUT } = serve({
  client: inngest,
  functions: [exampleJob, myCustomJob],
});
```

1. Add the event type to `src/lib/queue/types.ts`:

```typescript
export type QueueEvents = {
  "job/example": JobEventBase & { data: JobEventBase["data"] & { prompt: string } };
  "job/my-custom": JobEventBase & { data: JobEventBase["data"] & { someField: string } };
};
```

## Local Development

Inngest Dev Server runs automatically when you hit the serve endpoint. Visit `http://localhost:3000/api/inngest` to see the Inngest dashboard.

For the full Inngest Dev Server UI:

```bash
bunx inngest-cli@latest dev -u http://localhost:3000/api/inngest
```

## Acceptance Criteria

- POST `/api/jobs` creates a job record and triggers Inngest function
- GET `/api/jobs` lists user's jobs with status and progress
- GET `/api/jobs/[id]` returns individual job status
- Failed jobs retry 3x with exponential backoff
- Completed jobs have result stored in the `result` column
- `tsc` passes with no errors
- Build succeeds
