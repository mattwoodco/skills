# Figma Weave Production - Spec

**Created**: 2026-02-22  
**Status**: APPROVED

## Mission

- Enable teams to build node-based creative production systems where AI accelerates output while humans keep craft and brand control.

## Main Features

- Visual node workflow builder for creative pipelines
- Reusable templates for recurring production tasks
- Brand lock constraints across generated outputs
- Batch variation generation and queue execution
- Output comparison, selection, and export workflows
- Replayable workflow runs for consistency

## Major User Flows

- Build pipeline: create node graph -> configure constraints -> run batch -> curate best outputs
- Reuse template: load approved template -> swap inputs -> execute -> export campaign assets

## Required Screens

- Workflow canvas - node graph authoring
- Node library - generation/transform/export primitives
- Brand lock manager - palette/type/style constraints
- Run queue - execution state and retries
- Output gallery - compare/select/export artifacts

## Required Features (from /skills)

| Requirement | Skill(s) | Notes |
| ------------- | ---------- | ----- |
| Node workflow UI | react-flow | Core graph interaction layer |
| Image generation | ai-image-gen, ai-core | Creative generation nodes |
| Persistence | db | Graphs, templates, run history |
| Asset storage | storage | Inputs/intermediates/final outputs |
| Access control | auth | Team ownership and sharing |
| Motion polish (optional) | motion | UI responsiveness and feedback |

## Open Gaps

- Fine-grained quality scoring/ranking of outputs
- Advanced collaboration (multi-editor graph authoring)
- Cross-tool import/export standards for external creative suites

## Constraints / Assumptions

- Creative teams prefer repeatable systems over one-off prompting
- Brand consistency is a hard requirement across outputs
- Long-running jobs require queue/backpressure strategy
