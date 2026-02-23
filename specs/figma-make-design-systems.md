# Figma Make Design Systems - Spec

**Created**: 2026-02-22  
**Status**: APPROVED

## Mission

- Use design systems as AI-ready blueprints so teams can generate production-aligned UI faster without design/code drift.

## Main Features

- Import tokens/components/variants from design libraries
- Maintain mapping between design components and code components
- Generate UI from prompts constrained by system primitives
- Preview/diff generated output before implementation
- Detect and surface design/code mapping drift
- Support responsive and theme mode variants

## Major User Flows

- System setup: import library -> validate tokens -> map components -> save constraints
- Constrained generation: prompt page/feature -> generate with mappings -> review diff -> approve handoff

## Required Screens

- Library ingest - import and validation
- Mapping registry - design-to-code component mapping
- Generation workspace - prompt, constraints, preview
- Review/diff - approve or request regeneration
- Drift monitor - mapping health and alerts

## Required Features (from /skills)

| Requirement | Skill(s) | Notes |
| ------------- | ---------- | ----- |
| Data modeling | db | Tokens, mappings, generation metadata |
| AI generation core | ai-core | Constrained generation backend |
| Generation workflows | ai-tools | Tool-driven generation/review actions |
| User access | auth | Team/project scoping |
| UI component foundation | add-shadcn | Consistent admin/workspace UI |
| Spec/task handoff | spec-export | Optional issue/ticket export |

## Open Gaps

- Vendor-specific API and sync semantics for deep bidirectional workflows
- Automated mapping confidence scoring and conflict resolution
- Governance model for mapping ownership across teams

## Constraints / Assumptions

- Team already has a maintained design system
- Naming conventions are disciplined enough for reliable mapping
- Generated output always goes through review before merge
