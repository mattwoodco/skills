# Cosmos Mood Board - Spec

**Created**: 2026-02-22  
**Status**: APPROVED

## Mission

- Build an inspiration system for experienced designers that turns saved visual references into searchable, shareable design intelligence.

## Main Features

- One-click capture from browser/mobile surfaces
- AI tagging for mood, style, color, and subject
- Search by feeling (natural language + color + tags)
- Clusters for project/theme organization
- Team sharing with public/private controls
- Similarity-based discovery across saved references

## Major User Flows

- Capture and organize: discover reference -> save -> auto-tag -> assign to cluster -> reuse in project
- Search and share: enter mood/query -> review ranked references -> refine filters -> share cluster with team

## Required Screens

- Dashboard - recent captures and cluster overview
- Cluster detail - curate references and collaboration state
- Search workspace - query, filters, and visual results
- Capture surface - quick-save interactions and metadata hints
- Settings - privacy, integrations, and account preferences

## Required Features (from /skills)

| Requirement | Skill(s) | Notes |
| ------------- | ---------- | ----- |
| Accounts and ownership | auth | Team/private boundary enforcement |
| Data persistence | db | Stores captures, tags, clusters, history |
| Asset storage | storage, storage-ui | Image ingest, preview, lifecycle |
| AI tagging foundation | ai-core | Model calls for visual metadata |
| Similarity retrieval | ai-rag-vectors | Embedding-based "search by feeling" |
| Supplemental text lookup | search | Optional metadata/tag search layer |
| UI system | add-shadcn | Consistent app primitives |

## Open Gaps

- Browser extension implementation and review workflow
- Vision model choice/tuning for consistent tagging quality
- Deduplication policy for repeated captures

## Constraints / Assumptions

- AI tagging quality must be good enough to trust daily use
- Teams need strict controls for private vs public clusters
- Speed matters: capture + retrieve loop must feel immediate
