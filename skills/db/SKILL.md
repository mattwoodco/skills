---
name: db
description: PostgreSQL database with Drizzle ORM — Docker for local dev, connection pooling for production. Type-safe schema, migrations, and query patterns. Use this skill when the user says "setup database", "add db", "setup drizzle", "setup postgres", or "database setup".
author: Claude
version: 1.0.0
created: 2026-02-13
updated: 2026-02-13
dependencies: [docker, env-config]
---

# Database Setup with Drizzle ORM

Sets up a type-safe PostgreSQL database layer using Drizzle ORM with the `postgres` driver. Uses Docker for local development with a production-ready migration workflow.

## Prerequisites

- Next.js app with `src/` directory and App Router
- Docker setup (for local PostgreSQL -- see docker-compose section)
- Environment configuration (dependency: `env-config` skill)

## Installation

```bash
bun add drizzle-orm postgres
bun add -D drizzle-kit
```

## Environment Variables

Add to `.env.local`:

```env
DATABASE_URL=postgresql://app:password@localhost:5432/appdb
```

If using the `env-config` skill, add to your `env.ts`:

```typescript
// In env.ts, add to server object:
server: {
  // ... existing variables
  DATABASE_URL: z.string().url(),
},

// Add to runtimeEnv:
runtimeEnv: {
  // ... existing variables
  DATABASE_URL: process.env.DATABASE_URL,
},
```

## Docker Setup

Add the PostgreSQL service to `docker-compose.yml`. Uses `pgvector/pgvector:pg16` for vector search support (compatible with standard Postgres usage):

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-password}
      POSTGRES_DB: ${POSTGRES_DB:-appdb}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "${POSTGRES_USER:-app}"]
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 60s
    restart: unless-stopped

volumes:
  postgres_data:
```

> **Note:** Credentials here match the `docker` skill defaults (`app/password/appdb`). If your `docker-compose.yml` already defines a `postgres` service (from the `docker` skill), skip this section — the database is already configured.

Start the database:

```bash
docker compose up -d db
```

## What Gets Created

```
src/
├── lib/
│   └── db/
│       ├── index.ts           # Database client factory
│       └── schema/
│           └── index.ts       # Schema barrel export (add tables here)
├── lib/
│   └── db/
│       └── migrate.ts         # Migration runner
drizzle.config.ts              # Drizzle Kit config (project root)
```

## Setup Steps

### Step 1: Create Database Client (`src/lib/db/index.ts`)

This is the main database client factory. It uses the `postgres` package (NOT `pg`) with `drizzle-orm/postgres-js`.

```typescript
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error("DATABASE_URL is not set");
}

const client = postgres(connectionString);
export const db = drizzle(client, { schema });
export type Database = typeof db;
```

### Step 2: Create Schema Barrel Export (`src/lib/db/schema/index.ts`)

This is the barrel export for all schema tables. Add your own tables here as you build features.

```typescript
import { pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

// Example table -- replace with your schema
export const example = pgTable("example", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});
```

### Step 3: Create Migration Runner (`src/lib/db/migrate.ts`)

A standalone script that runs migrations against the database. Uses a single connection (`max: 1`) and exits cleanly after completion.

```typescript
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error("DATABASE_URL is not set");
}

const client = postgres(connectionString, { max: 1 });
const db = drizzle(client);

async function main() {
  console.log("Running migrations...");
  await migrate(db, { migrationsFolder: "./drizzle" });
  console.log("Migrations complete!");
  await client.end();
}

main().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
```

### Step 4: Create Drizzle Kit Config (`drizzle.config.ts`)

Create this file at the project root. It tells Drizzle Kit where to find the schema and where to output migration files.

```typescript
import { defineConfig } from "drizzle-kit";

const url = process.env.DATABASE_URL;
if (!url) throw new Error("DATABASE_URL is required");

export default defineConfig({
  schema: "./src/lib/db/schema/index.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: {
    url,
  },
});
```

### Step 5: Add Package Scripts

Add these scripts to `package.json`:

```json
{
  "scripts": {
    "db:generate": "drizzle-kit generate",
    "db:migrate": "bun src/lib/db/migrate.ts",
    "db:push": "drizzle-kit push",
    "db:studio": "drizzle-kit studio"
  }
}
```

### Step 6: Initialize the Database

```bash
# Start PostgreSQL (if not already running)
docker compose up -d db

# Push the schema directly (development)
bun run db:push

# Or generate and run migrations (production workflow)
bun run db:generate
bun run db:migrate
```

## Usage

### Importing the Database Client

```typescript
import { db } from "@/lib/db";
```

> **Path convention:** The canonical import path is `@/lib/db` (not `@/db`). All downstream skills that depend on this skill should use `@/lib/db` and `@/lib/db/schema` for imports.

### Insert Records

```typescript
import { db } from "@/lib/db";
import { example } from "@/lib/db/schema";

const newRecord = await db
  .insert(example)
  .values({
    name: "My Item",
  })
  .returning();
```

### Select Records

```typescript
import { db } from "@/lib/db";
import { example } from "@/lib/db/schema";
import { eq } from "drizzle-orm";

// Select all
const allRecords = await db.select().from(example);

// Select with filter
const filtered = await db
  .select()
  .from(example)
  .where(eq(example.name, "My Item"));

// Select single record by ID
const record = await db.query.example.findFirst({
  where: eq(example.id, "some-uuid"),
});
```

### Update Records

```typescript
import { db } from "@/lib/db";
import { example } from "@/lib/db/schema";
import { eq } from "drizzle-orm";

const updated = await db
  .update(example)
  .set({
    name: "Updated Name",
    updatedAt: new Date(),
  })
  .where(eq(example.id, "some-uuid"))
  .returning();
```

### Delete Records

```typescript
import { db } from "@/lib/db";
import { example } from "@/lib/db/schema";
import { eq } from "drizzle-orm";

await db.delete(example).where(eq(example.id, "some-uuid"));
```

### Transactions

```typescript
import { db } from "@/lib/db";
import { example } from "@/lib/db/schema";

await db.transaction(async (tx) => {
  const inserted = await tx
    .insert(example)
    .values({ name: "First" })
    .returning();

  await tx
    .update(example)
    .set({ name: "Updated" })
    .where(eq(example.id, inserted[0].id));
});
```

### Relations Example

When adding related tables, define relations for the query API:

```typescript
import { pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { relations } from "drizzle-orm";

export const posts = pgTable("posts", {
  id: uuid("id").primaryKey().defaultRandom(),
  title: text("title").notNull(),
  content: text("content"),
  authorId: uuid("author_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  email: text("email").notNull().unique(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const usersRelations = relations(users, ({ many }) => ({
  posts: many(posts),
}));

export const postsRelations = relations(posts, ({ one }) => ({
  author: one(users, {
    fields: [posts.authorId],
    references: [users.id],
  }),
}));
```

Then query with relations:

```typescript
const usersWithPosts = await db.query.users.findMany({
  with: {
    posts: true,
  },
});
```

### Type Inference

Drizzle provides type inference from your schema:

```typescript
import type { InferSelectModel, InferInsertModel } from "drizzle-orm";
import { example } from "@/lib/db/schema";

type Example = InferSelectModel<typeof example>;
type NewExample = InferInsertModel<typeof example>;
```

## Schema Patterns

### Common Column Types

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  integer,
  boolean,
  jsonb,
  pgEnum,
  varchar,
  numeric,
} from "drizzle-orm/pg-core";

// Enum type
export const statusEnum = pgEnum("status", ["active", "inactive", "archived"]);

// Full-featured table
export const items = pgTable("items", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  description: text("description"),
  slug: varchar("slug", { length: 255 }).notNull().unique(),
  price: numeric("price", { precision: 10, scale: 2 }),
  quantity: integer("quantity").notNull().default(0),
  isPublished: boolean("is_published").notNull().default(false),
  status: statusEnum("status").notNull().default("active"),
  metadata: jsonb("metadata").$type<Record<string, string>>(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});
```

### Soft Deletes

```typescript
export const documents = pgTable("documents", {
  id: uuid("id").primaryKey().defaultRandom(),
  title: text("title").notNull(),
  deletedAt: timestamp("deleted_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// Query only active records
import { isNull } from "drizzle-orm";

const activeDocuments = await db
  .select()
  .from(documents)
  .where(isNull(documents.deletedAt));
```

## Migration Workflow

### Development (quick iteration)

```bash
# Push schema changes directly to database (no migration files)
bun run db:push
```

### Production (tracked migrations)

```bash
# 1. Generate migration SQL from schema changes
bun run db:generate

# 2. Review generated migration in ./drizzle/

# 3. Run migrations
bun run db:migrate
```

### Inspect Database

```bash
# Open Drizzle Studio (visual database browser)
bun run db:studio
```

## API Endpoints

This skill is a library -- it does not create any API endpoints. Use the `db` client in your API routes:

```typescript
// src/app/api/examples/route.ts
import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { example } from "@/lib/db/schema";

export async function GET() {
  const records = await db.select().from(example);
  return NextResponse.json(records);
}
```

## Commands Reference

| Command | Description |
|---------|-------------|
| `bun run db:generate` | Generate migration SQL from schema changes |
| `bun run db:migrate` | Run pending migrations |
| `bun run db:push` | Push schema directly (dev only) |
| `bun run db:studio` | Open Drizzle Studio visual browser |
| `docker compose up -d db` | Start PostgreSQL container |
| `docker compose logs -f db` | Follow PostgreSQL logs |

## Troubleshooting

### Connection refused

**Symptoms**: `Error: connect ECONNREFUSED 127.0.0.1:5432`

**Cause**: PostgreSQL container is not running.

**Fix**:

```bash
docker compose up -d db
docker compose ps  # verify it's healthy
```

### DATABASE_URL not set

**Symptoms**: `Error: DATABASE_URL is not set`

**Cause**: Environment variable not loaded.

**Fix**: Ensure `.env.local` contains `DATABASE_URL=postgresql://app:password@localhost:5432/appdb` and restart the dev server.

### Migration fails with "relation already exists"

**Symptoms**: Migration SQL tries to create a table that already exists.

**Cause**: Schema was pushed with `db:push` before generating migrations.

**Fix**:

```bash
# Mark existing migrations as applied
bun run db:generate  # generates new migration
# Then manually delete the conflicting SQL statements from the migration file
bun run db:migrate
```

### Wrong postgres driver

**Symptoms**: Import errors or runtime crashes with `pg` or `@neondatabase/serverless`.

**Cause**: Using the wrong driver package.

**Fix**: This skill uses the `postgres` package (postgres.js). Ensure imports are:

```typescript
// CORRECT
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";

// WRONG - do NOT use these
// import { drizzle } from "drizzle-orm/node-postgres";
// import pg from "pg";
```

## Acceptance Criteria

- [ ] PostgreSQL container starts and is healthy (`docker compose up -d db`)
- [ ] `src/lib/db/index.ts` exports a typed `db` client
- [ ] `src/lib/db/schema/index.ts` contains at least one example table
- [ ] `drizzle.config.ts` exists at project root with correct schema path
- [ ] `bun run db:push` successfully creates tables in PostgreSQL
- [ ] `bun run db:generate` generates migration files in `./drizzle/`
- [ ] `bun run db:migrate` runs migrations without errors
- [ ] Insert, select, update, and delete operations work via the `db` client
- [ ] `bun run db:studio` opens Drizzle Studio
- [ ] No usage of `any` type anywhere in database code
- [ ] Uses `postgres` package (NOT `pg` or `@neondatabase/serverless`)
- [ ] Uses `drizzle-orm/postgres-js` (NOT `drizzle-orm/node-postgres`)
- [ ] Primary keys use `uuid` with `.defaultRandom()`
- [ ] Timestamps use `{ withTimezone: true }`
