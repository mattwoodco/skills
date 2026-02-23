# Design Mood Board - Master Execution Plan

**Created:** 2026-02-22
**Status:** READY TO START
**Goal:** Build a production-ready MVP for designers to capture inspiration, curate clusters, and retrieve references using hybrid semantic search with strict privacy boundaries.
**Scaffold:** fresh

---

## Overview

Apply 16 skills + 4 custom implementations to deliver the Design Mood Board MVP.
Every step is independently verifiable and done one step per Ralph loop.

**Rule: ONE step per Ralph loop. Test before marking done.**

### Testing Requirements

- Every loop runs: `bun run build`, `bunx biome check .`, `bun test`
- UI loops also run playwright validation and save screenshot under `.ralph/screenshots/`
- API loops validate route status with `curl`

### Progressive Test Writing

- Unit tests for utilities/policies/ranking
- Integration tests for ingest pipeline, queue workers, and permission boundaries
- E2E tests for capture, organize, search, and sharing flows

---

## Phase 1: Shared Substrate

| Step | Task | Verify |
|------|------|--------|
| 1.1 | PENDING: Apply `create-next` skill | `bun run build` |
| 1.2 | PENDING: Apply `docker` skill | `docker compose config` |
| 1.3 | PENDING: Apply `env-config` skill | `bun run typecheck` |
| 1.4 | PENDING: Apply `add-shadcn` skill | `bunx shadcn@latest --help` |
| 1.5 | PENDING: Apply `db` skill (Postgres + pgvector baseline) | `bun drizzle-kit check` |
| 1.6 | PENDING: Apply `e2e` skill (Playwright harness) | `bunx playwright test --list` |
| 1.7 | PENDING: Validate Phase 1 | `bun run build && bunx biome check . && bun test` |
| 1.8 | PENDING: Fix Phase 1 errors | `bun run build && bun test` |

## Phase 2: Product Core

| Step | Task | Verify |
|------|------|--------|
| 2.1 | PENDING: Apply `auth` skill | `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/sign-in` |
| 2.2 | PENDING: Apply `auth-dev` skill | `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/dev/seed` |
| 2.3 | PENDING: Apply `storage` skill | `bun test __tests__/integration` |
| 2.4 | PENDING: Apply `storage-ui` skill | `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/upload` |
| 2.5 | PENDING: Apply `queue` skill | `bun test __tests__/integration` |
| 2.6 | PENDING: Apply `ai-core` skill | `bun test __tests__/unit` |
| 2.7 | PENDING: Apply `ai-rag-vectors` skill | `bun test __tests__/integration` |
| 2.8 | PENDING: Apply `search` skill | `bun test __tests__/integration` |
| 2.9 | PENDING: Apply `observability` skill | `bun test __tests__/integration` |
| 2.10 | PENDING: Apply `analytics` skill | `bun test __tests__/integration` |
| 2.11 | PENDING: Validate Phase 2 | `bun run build && bunx biome check . && bun test` |
| 2.12 | PENDING: Fix Phase 2 errors | `bun run build && bun test` |

## Phase 3: Design Custom Gaps

| Step | Task | Verify |
|------|------|--------|
| 3.1 | PENDING: Implement browser extension capture contract and callback auth | `bun test __tests__/integration/capture-extension.test.ts` |
| 3.2 | PENDING: Implement mobile share ingest contract and idempotency handling | `bun test __tests__/integration/capture-mobile.test.ts` |
| 3.3 | PENDING: Implement vision model policy and deterministic style-tag fallback | `bun test __tests__/unit/vision-policy.test.ts` |
| 3.4 | PENDING: Implement near-duplicate resolution UX policy (`needs_attention` routing) | `bun test __tests__/integration/duplicate-policy.test.ts` |
| 3.5 | PENDING: Validate Phase 3 | `bun run build && bunx biome check . && bun test` |
| 3.6 | PENDING: Fix Phase 3 errors | `bun run build && bun test` |

## Phase 4: E2E Critical Journeys

| Step | Task | Verify |
|------|------|--------|
| 4.1 | PENDING: E2E capture flow (`processing` to `ready`) | `bunx playwright test __tests__/e2e/capture-flow.spec.ts` |
| 4.2 | PENDING: E2E organize flow (cluster curate move/remove) | `bunx playwright test __tests__/e2e/organize-flow.spec.ts` |
| 4.3 | PENDING: E2E search flow (semantic + filters ranking) | `bunx playwright test __tests__/e2e/search-flow.spec.ts` |
| 4.4 | PENDING: E2E share/privacy flow (private/team/public boundaries) | `bunx playwright test __tests__/e2e/share-privacy-flow.spec.ts` |
| 4.5 | PENDING: Validate Phase 4 and release readiness | `bun run build && bunx biome check . && bun test` |
| 4.6 | PENDING: Fix Phase 4 errors and prepare handoff | `bun run build && bun test` |
