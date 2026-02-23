# Vercel v0 MVP - Design

**Date**: 2026-02-22  
**Status**: APPROVED  
**Source**: `specs/.private/blog-posts/design-tool-guides/design-tools-guides-6.md`

## Clarifying Question

Generation granularity?

- A) Full-page MVP generation
- B) Component-level generation only

**Selected**: A (recommended with component extraction)

## Approaches

### Approach 1 - Full-page generation first (Recommended)

- Highest speed for MVP/landing/dashboard validation
- Strong demo and feedback loop velocity
- Requires post-generation hardening and review

### Approach 2 - Component-only generation

- Better composability and maintainability in mature codebases
- Lower risk of monolithic generated output
- Slower for early-stage validation cycles

## Design

### Architecture and Components

- Prompt workspace with structured UI intent inputs
- Generation pipeline for page + section + component outputs
- Quality gate for a11y, semantics, and responsiveness checks
- Extractor for reusable components into library
- Integration assistant for codebase import and diff review

### Data Flow

- Prompt + constraints -> generated output -> quality checks -> review
- Accepted output -> optional component extraction -> library registration
- Review notes feedback loop informs next prompt iteration

### Error Handling

- Prompt ambiguity warnings with suggested specificity improvements
- Generation failure retries with reduced complexity strategy
- Policy checks for unsupported patterns in target codebase
- Reject/redo path without contaminating main branch

### Testing

- E2E: prompt -> generated page -> review -> integrate
- Unit: prompt normalizer and template selectors
- Integration: extraction into component library
- QA checks for responsive breakpoints and keyboard navigation

## Approval Notes

- Preserves "speed without sacrificing taste" framing
- Explicitly states developer review requirement for production
