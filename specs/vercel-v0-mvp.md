# Vercel v0 MVP - Spec

**Created**: 2026-02-22  
**Status**: APPROVED

## Mission

- Help teams ship high-quality MVP surfaces quickly by converting precise product descriptions into reviewable, production-aligned UI code.

## Main Features

- Prompt workspace for structured UI requests
- Full-page generation for landing/dashboard/MVP views
- Output validation for responsiveness and accessibility
- Reusable component extraction from generated pages
- Integration workflow into existing codebase patterns
- Iterative prompt refinement with comparison history

## Major User Flows

- Rapid MVP: define UI intent -> generate full page -> review quality -> integrate -> ship preview
- Component reuse: generate page -> extract reusable primitives -> add to library -> reuse in next feature

## Required Screens

- Generation workspace - prompt + constraints
- Render/code preview - immediate output inspection
- Quality check panel - a11y/responsive/pattern checks
- Integration review - diff and acceptance controls
- Prompt/run history - compare iterations

## Required Features (from /skills)

| Requirement | Skill(s) | Notes |
| ------------- | ---------- | ----- |
| App framework baseline | create-next | Target stack alignment |
| UI primitives | add-shadcn | Consistent component vocabulary |
| AI generation foundation | ai-core | Prompt-to-code orchestration support |
| Persistence | db | Prompt/run metadata and comparisons |
| Artifact storage | storage | Saved outputs and references |
| Async processing | queue | Long-running generation jobs |
| SEO readiness | add-seo | Landing/MVP pages metadata baseline |
| Adoption tracking | analytics | Measure generation impact |

## Open Gaps

- Complex state/business-logic scaffolding quality
- Advanced interaction/animation generation reliability
- Team workflows for generation governance and approvals

## Constraints / Assumptions

- Best fit for UI-heavy surfaces, not deep domain logic
- High-quality output depends on precise prompt writing
- Generated code always receives developer hardening before production
