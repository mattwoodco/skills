# Cosmos Mood Board - Design

**Date**: 2026-02-22  
**Status**: APPROVED  
**Source**: `specs/.private/blog-posts/design-tool-guides/design-tools-guides-1.md`

## Clarifying Question

Primary use case focus?

- A) Personal inspiration curation
- B) Team collaboration

**Selected**: B (recommended blend with personal-first onboarding)

## Approaches

### Approach 1 - Full-stack web app + browser extension (Recommended)

- Best save UX for fast collection from web/mobile browsing
- Supports scalable tagging/search and collaboration patterns
- Higher implementation complexity (extension lifecycle, sync, offline queue)

### Approach 2 - Web app + bookmarklet/API ingest

- Faster to ship initial capture flow
- Lower integration complexity
- More friction during capture; weaker long-term habit loop

## Design

### Architecture and Components

- Next.js app with authenticated collections, clusters, and search
- Capture clients: browser extension and mobile share target (phase 2)
- AI tagging service for mood/style/color/subject extraction
- Vector + metadata search service for "search by feeling"
- Collaboration layer for shared/public clusters and comments

### Data Flow

- Capture image/link -> upload/store -> AI tag extraction -> embedding index
- Query (mood/hex/text) -> hybrid search -> ranked inspiration results
- Cluster updates -> share/publication state -> collaborators notified

### Error Handling

- Capture retry queue for network failures
- Tagging fallback to manual tags when AI fails
- Upload guardrails for unsupported formats/oversized assets
- Permission checks for private/public cluster boundaries

### Testing

- E2E: capture -> organize -> search -> share
- Integration: AI tagging + search ranking behavior
- Unit: cluster rules, permission policy, query parsing
- Regression snapshots for inspiration card rendering

## Approval Notes

- Keeps "AI as amplifier, not replacement" framing
- Prioritizes speed without sacrificing taste/consistency
- Leaves extension build complexity explicit in constraints
