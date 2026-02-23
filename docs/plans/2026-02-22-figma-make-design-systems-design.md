# Figma Make Design Systems - Design

**Date**: 2026-02-22  
**Status**: APPROVED  
**Source**: `specs/.private/blog-posts/design-tool-guides/design-tools-guides-2.md`

## Clarifying Question

Integration depth?

- A) Figma API read-only import + generation
- B) Bidirectional sync with Code Connect

**Selected**: B (recommended)

## Approaches

### Approach 1 - One-way import and generate

- Faster setup and lower integration risk
- Good for early adoption
- Creates ongoing manual sync burden

### Approach 2 - Bidirectional design/code sync (Recommended)

- Stronger handoff and less drift between Figma and code
- Enables reusable component mapping discipline
- Requires deeper setup and governance

## Design

### Architecture and Components

- Design system ingestion: tokens, components, variants, modes
- Mapping registry for Figma component IDs -> code components
- Prompt generation workspace constrained by imported primitives
- Sync service for mapping refresh and drift checks
- Review panel for generated output before implementation

### Data Flow

- Import design library -> normalize tokens/components -> mapping registry
- Prompt request -> constrained generation against registry -> preview/diff
- Mapping update -> drift detection -> reconciliation suggestions

### Error Handling

- Invalid/missing tokens blocked with explicit fix guidance
- Broken mappings downgraded to manual mapping queue
- Drift alerts when code and design semantics diverge
- Safe fallback to one-way generation when sync is unavailable

### Testing

- Unit: token normalization + mapping validation
- Integration: import -> generate -> review loop
- Contract tests for mapping schema stability
- E2E for responsive + dark mode component variants

## Approval Notes

- Anchored to "design systems as blueprint" thesis
- Optimizes for consistency and production readiness over novelty
