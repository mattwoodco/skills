# Wave — No-Frills Spec

**Created**: 2026-02-22
**Status**: APPROVED
**Design doc**: docs/plans/2026-02-22-weave-studio-design.md

## Mission

Enable a solo designer to build node-based creative production workflows where AI accelerates output while the human keeps craft and brand control.

## Main Features

- Zero-chrome canvas: fullscreen React Flow editor, contextual controls only
- Three MVP node types: ImageGenerate, BrandLock, Export
- Workflow persistence with autosave
- Queue-based execution with retries and progress reporting
- Output gallery with compare, select, and bulk export
- Brand lock constraints enforced across generated outputs

## Major User Flows

- **Build + run pipeline:** add nodes on canvas -> configure via node-anchored popovers -> click Run -> watch progress on bottom ticker -> review outputs in gallery popover -> select and export
- **Retry failed run:** failure appears on ticker -> open details popover -> click Retry -> resumes from failed stage

## Required Screens

Single-screen studio:
- Center: React Flow canvas (persistent workspace)
- Node creation: cursor-triggered popover (Space or + button)
- Node config: node-anchored popovers on selection
- Top bar: workflow name, save, run button (minimal)
- Bottom ticker: run status, appears only when a run is active
- Output gallery: popover from completed run (grid compare, select, export)
- Export options: popover from gallery selection

## Required Features (from /skills)

| Requirement | Skill(s) | Notes |
| --- | --- | --- |
| App shell | create-next | Next.js, TS, Tailwind, Biome, Bun |
| Runtime | docker, env-config | Local services, typed env contracts |
| UI primitives | add-shadcn | shadcn/ui components |
| Database | db | Drizzle + Postgres for workflows, runs, artifacts |
| Testing | e2e | Playwright harness |
| AI generation | ai-core | Single provider adapter for image generation |
| Background jobs | queue | BullMQ + Redis for execution queue |
| Flow canvas | react-flow | Node/edge workflow editor |
| Asset storage | storage | Input/intermediate/final output persistence |

## Custom Implementations

| Feature | Description |
| --- | --- |
| C1: Brand lock node | Color palette, font, style keyword constraints enforced on generated outputs |
| C2: Workflow execution engine | Topological sort, stage-by-stage runner, progress reporting |
| C3: Zero-chrome canvas shell | Fullscreen canvas layout, contextual popover system, minimal top bar |
| C4: Output gallery popover | Grid compare, side-by-side, select/deselect, bulk zip export |
| C5: Run status ticker | Bottom ticker that appears only during active runs, shows progress + retry |

## Open Gaps

- Fine-grained quality scoring/ranking of outputs (post-MVP)
- Multi-editor collaboration (post-MVP)
- Cross-tool import/export standards (post-MVP)
- Provider-agnostic abstraction layer (post-MVP, currently single provider)

## Constraints / Assumptions

- Solo designer is the only user persona for MVP
- Single AI image generation provider (specific provider chosen at build time)
- Brand consistency is a hard requirement across all outputs
- Long-running jobs require queue with backoff and retry
- Run status UI appears only when a run is active
- No persistent sidebars — all controls are contextual popovers
