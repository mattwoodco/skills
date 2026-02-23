# Design Mood Board - Spec

**Created**: 2026-02-22  
**Status**: APPROVED

## Mission

- Build a production-ready MVP for designers to capture visual inspiration, organize it in clusters, and retrieve it through semantic search with strict privacy controls.

## Main Features

- Capture from browser extension and mobile share.
- AI auto-processing per capture (tags, colors, embeddings).
- Cluster management (create, edit, move, remove captures).
- Hybrid search (semantic similarity + structured filters).
- Sharing model with private/team/public visibility.
- Lightweight UI animations for clarity and delight.

## Major User Flows

- Capture flow: save from browser/mobile -> status `processing` -> auto-analysis completes -> item becomes `ready`.
- Organize flow: open cluster -> add/move/remove captures -> curate visual direction -> keep team alignment.
- Search flow: enter mood query -> apply filters -> review ranked results -> open/save to cluster.
- Share flow: set cluster privacy -> share with team or public -> collaborators view curated references safely.

## Required Screens

- Dashboard - recent captures, processing state, quick actions.
- Capture Inbox - ingest queue with `processing`, `ready`, `needs_attention`.
- Cluster Detail - curation workspace and permission controls.
- Search Workspace - semantic query, filters, ranked visual results.
- Settings - privacy defaults, integrations, account/team configuration.

## Required Features (from /skills)

| Requirement | Skill(s) | Notes |
| ------------- | ---------- | ----- |
| Auth and team access | auth, auth-dev | Required for ownership + privacy enforcement |
| Relational data model | db | Captures, clusters, tags, team roles, audit events |
| Asset storage and previews | storage, storage-ui | Raw + optimized image lifecycle |
| AI processing orchestration | ai-core | Tagging/color/metadata generation workflow |
| Embeddings + semantic retrieval | ai-rag-vectors | "Search by feeling" capability |
| Structured query/filter layer | search | Tag/date/source/privacy filtering |
| Background processing pipeline | queue | Async jobs, retries, dead-letter handling |
| UI primitives | add-shadcn | Fast, consistent component baseline |
| Reliability + product telemetry | observability, analytics | Processing latency, failure rates, search quality |
| End-to-end validation | e2e | Capture/search/share critical journey tests |

## Open Gaps

- Browser extension implementation details and store-review workflow.
- Mobile share extension implementation and OS-level edge cases.
- Vision model selection/tuning for consistent style tags.
- Duplicate-resolution UX policy for near-identical captures.

## Constraints / Assumptions

- Fixed stack: Next.js app/API + Postgres (`pgvector`) + object storage + worker queue.
- MVP includes browser and mobile capture (not deferred).
- Save flow must feel immediate (`processing` state visible fast).
- Privacy boundaries must be strict across private/team/public scopes.
- Partial processing success is acceptable (item remains usable if embedding fails).
