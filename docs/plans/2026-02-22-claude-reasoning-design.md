# Claude Reasoning Partner - Design

**Date**: 2026-02-22  
**Status**: APPROVED  
**Source**: `specs/.private/blog-posts/design-tool-guides/design-tools-guides-4.md`

## Clarifying Question

Scope of reasoning experience?

- A) Extend generic reasoning surface
- B) Design-specific reasoning workspace

**Selected**: B (recommended)

## Approaches

### Approach 1 - Extend generic reasoning interface

- Reuses existing patterns and ships faster
- Lower maintenance overhead
- Weak separation between execution and strategy workflows

### Approach 2 - Dedicated design reasoning workspace (Recommended)

- Better framing for strategy, accessibility, tone, and systems thinking
- Clear outputs for decision logs and artifacts
- Additional UX and context-modeling effort

## Design

### Architecture and Components

- Design reasoning chat focused on problem framing and trade-offs
- Context pack manager (brand docs, constraints, audience, WCAG goals)
- Artifact panel for decision records, token notes, and docs
- Session memory for reasoning continuity across design cycles

### Data Flow

- Problem statement -> clarifying prompts -> option analysis -> decision artifacts
- Context pack updates re-rank recommendations
- Final reasoning output exported to handoff/design docs

### Error Handling

- Low-context detection prompts user for missing constraints
- Contradictory goals surfaced as explicit trade-offs
- Hallucination guardrails via source-anchored reasoning templates
- Timeout fallback to partial recommendation summaries

### Testing

- Unit: context-pack injection and template selection
- Integration: reasoning-to-artifact output correctness
- E2E: strategy session -> approved decision log export
- Quality checks on accessibility recommendation fidelity

## Approval Notes

- Preserves "thinking partner, not executor" intent
- Explicitly separates strategic reasoning from production generation steps
