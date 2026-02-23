# Claude Reasoning - Spec

**Created**: 2026-02-22  
**Status**: APPROVED

## Mission

- Give designers a dedicated reasoning partner for strategy, accessibility, and systems decisions before execution starts.

## Main Features

- Design-focused reasoning chat and prompts
- Context pack injection (brand, audience, constraints, WCAG)
- Structured trade-off and options analysis
- Artifact outputs for decision logs and documentation
- Session memory for ongoing projects
- Exportable recommendations for downstream handoff

## Major User Flows

- Strategy loop: describe challenge -> get clarifying prompts -> compare options -> log decision
- Accessibility loop: provide screen/problem context -> receive WCAG-aware guidance -> generate remediation checklist

## Required Screens

- Reasoning workspace - conversation + structured output
- Context manager - upload/select constraints and references
- Option analysis view - trade-offs and recommendations
- Artifact panel - docs/tokens/checklists
- Session history - revisit and continue prior reasoning

## Required Features (from /skills)

| Requirement | Skill(s) | Notes |
| ------------- | ---------- | ----- |
| Reasoning UX | ai-reasoning | Extended thinking interaction pattern |
| Conversational surface | ai-chat | Session and message flow |
| Model access | ai-core | Reasoning model configuration |
| Structured outputs | ai-artifacts | Decision and doc artifacts |
| Persistence | db | Session memory and references |
| Access control | auth | Team/project context separation |
| Reference storage | storage | Supporting files and docs |

## Open Gaps

- First-class design file ingestion for richer context
- Team review workflows around reasoning artifacts
- Quality rubric for recommendation consistency over time

## Constraints / Assumptions

- Focus is reasoning quality, not auto-generating final UI
- Users provide enough context for high-signal recommendations
- Recommendations still require human design judgment
