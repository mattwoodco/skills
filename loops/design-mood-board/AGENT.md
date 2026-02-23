# Design Mood Board - Agent Instructions

## Project Type

Production-oriented Next.js MVP for designer inspiration capture, clustering, semantic retrieval, and privacy-controlled sharing.

## Directory Layout

```
.claude/skills/    # Symlinked skills (16 total)
src/               # Next.js app (created at PLAN 1.1)
__tests__/         # Unit, integration, and e2e suites
.ralph/            # Execution loop artifacts
  ├── PLAN.md
  ├── PROMPT.md
  ├── PROGRESS.md
  ├── logs/
  └── screenshots/
```

## Validation Commands

1. `bun run build`
2. `bunx biome check .`
3. `bun test`
4. `bunx playwright test` for e2e checks
5. `curl` checks for route/API readiness where relevant

## Technology Stack

- Next.js App Router (UI + API)
- Postgres with `pgvector`
- Object storage for raw/optimized captures
- Queue workers for async processing
- Hybrid retrieval (semantic + structured filters)
- Privacy model: private / team / public
