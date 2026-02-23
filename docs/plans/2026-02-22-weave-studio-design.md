# Weave Studio — Execution MVP Design

**Created**: 2026-02-22
**Status**: APPROVED
**Scope**: Execution MVP, Solo Designer, Single AI Provider

## Decision Summary

| Decision | Choice |
| --- | --- |
| MVP boundary | Execution MVP (canvas + queue + gallery + export) |
| AI generation | Single real provider integration |
| Primary user | Solo designer/operator |
| Approach | Vertical-slice — one complete happy path end-to-end |
| Interaction model | Zero-Chrome Canvas (minimal persistent UI, contextual controls) |
| Run status UI | Appears only when a run is active |

## Mission

Enable a solo designer to build node-based creative production workflows where AI accelerates output while the human keeps craft and brand control.

## Architecture

Four thin layers, each buildable and testable independently:

1. **Editor layer (React Flow)** — controlled graph editor with a small fixed node set: `ImageGenerate`, `BrandLock`, `Export`. Author pipelines visually, save/load.
2. **Execution API (Next.js API routes / server actions)** — accepts a saved workflow + run inputs, validates graph shape, creates a run record, enqueues jobs.
3. **Worker layer (BullMQ + single provider adapter)** — executes jobs stage-by-stage, reports progress, retries with exponential backoff, writes output artifacts and status updates.
4. **Asset/result layer (storage + DB)** — persists workflow templates, run history, job state, and output artifacts for gallery and export.

### MVP boundaries

**Include:**
- Single-user auth mode (or single workspace assumption)
- One real generation provider
- Queue + retries + progress
- Output gallery compare/select/export

**Exclude:**
- Multi-editor collaboration
- Auto quality ranking/scoring
- Cross-tool import/export standards

## Single-Screen UI (Zero-Chrome Canvas)

Fullscreen canvas with almost no persistent chrome. Controls appear contextually.

- **Center:** React Flow canvas (persistent workspace)
- **Node creation:** cursor-triggered (`Space` or `+` button), node-type picker popover
- **Node config:** node-anchored popovers on selection (prompt, brand constraints, export settings)
- **Global actions:** minimal top bar — workflow name, save, run button
- **Run status:** thin bottom ticker, appears only while a run is active, disappears when idle
- **Output review:** popover triggered from completed run (grid compare, select, export)
- **Export:** popover from output review or floating action button

### Node Types (MVP)

| Node | Config | Purpose |
| --- | --- | --- |
| `ImageGenerate` | Prompt text, provider config, variation count | Generate images via AI provider |
| `BrandLock` | Color palette, allowed fonts, style keywords | Constrain outputs to brand standards |
| `Export` | Format (PNG/JPG/WebP), quality, naming pattern | Package final artifacts |

### Node Contract

```typescript
interface WorkflowNode {
  type: "image-generate" | "brand-lock" | "export";
  config: Record<string, unknown>;
  inputs: string[];
  outputs: string[];
}
```

Execution processes nodes topologically: `ImageGenerate` -> `BrandLock` -> `Export`.

## Data Flow

1. **Canvas state:** nodes, edges, selection live in a single client store (Zustand); UI chrome stays minimal and appears contextually.
2. **Draft persistence:** graph changes autosave (debounced) to a workflow draft so the user never loses the canvas.
3. **Run trigger:** `Run` validates graph shape, creates a `run` record, enqueues the workflow job.
4. **Execution updates:** worker processes stages, writes progress/status/result metadata to DB, stores generated assets in storage.
5. **Live feedback:** canvas gets subtle node-level status badges + thin bottom ticker for run state.
6. **Review/export:** clicking completed run opens output compare popover; selected assets export from there (zip/download).

## Error Handling

### Pre-run validation
- Block run if required chain is broken or required config is missing.
- Inline node error badges + compact popover with fix actions.

### Execution-time failures
- Provider/API failures, rate limits, storage write failures, and worker crashes mark the run `failed`.
- Bottom ticker appears automatically on failure with `Retry` and `View details`.

### Retry model
- Automatic retries in queue (exponential backoff, capped attempts).
- Manual retry from failure popover; resume from failed stage when possible (not full rerun by default).

### Partial output handling
- If some batch items fail, keep successful artifacts and mark failed items individually.
- Output compare popover can still open for successful artifacts.

### Observability
- Per-run event log: queued, started, stage progress, failed/completed, retry count.
- Shown in a lightweight details popover, not a separate monitoring page.

## Testing Strategy

- **Graph logic:** unit tests for topological sort, validation rules, node contract enforcement.
- **Queue/worker:** integration tests for enqueue -> process -> complete/fail cycle with mocked provider.
- **Provider adapter:** isolated tests for the single real provider; mock for all other tests.
- **UI smoke:** React Flow renders, nodes connect, config popovers open, run triggers correctly.
- **Error paths:** validation rejects broken graphs; partial failures preserve good artifacts; retry resumes from failed stage.

## Tech Stack

| Layer | Technology |
| --- | --- |
| Framework | Next.js (App Router) |
| Canvas | React Flow (@xyflow/react) |
| State | Zustand |
| Queue | BullMQ + Redis |
| DB | Postgres (or SQLite for local dev) |
| Storage | Local filesystem (MVP), S3-compatible later |
| UI components | shadcn/ui + Tailwind |
| AI provider | Single provider (TBD at build time) |
