---
name: add-spec
description: >
  Create a project spec from an idea using the full brainstorming design workflow, then output
  a no-frills spec for Ralph loops and add-project. Use when the user says "spec a project",
  "create a spec", "spec this idea", "plan a project", "write a spec", or when add-project
  delegates Phase 1 spec generation. Runs brainstorming first (clarify → approaches → design
  approval → design doc), then writes docs/specs/{name}.md with mission, features, flows,
  screens, and skills mapping.
metadata:
  author: "@mattwoodco"
  version: 1.0.0
  created: 2026-02-22
  updated: 2026-02-22
---

# Add Spec — Brainstorming to No-Frills Spec

Creates a project specification by running the **full brainstorming workflow** first, then writing a **concise, digestible spec** to `docs/specs/{project-name}.md` for use with add-project and Ralph loops.

## Quick Start

```
1. Run full brainstorming workflow (explore context → clarify → approaches → design sections → approval)
2. Write design doc to docs/plans/YYYY-MM-DD-<topic>-design.md
3. Write no-frills spec to docs/specs/{project-name}.md from the approved design
4. Do NOT invoke writing-plans; add-spec stops at the spec file
```

## Phase 1: Run Brainstorming (Full Workflow)

Follow the **brainstorming** skill end-to-end up to and including the design doc:

1. **Explore project context** — check files, docs, recent commits
2. **Ask clarifying questions** — one at a time; purpose, constraints, success criteria
3. **Propose 2–3 approaches** — with trade-offs and your recommendation
4. **Present design** — in sections scaled to complexity; get user approval after each section
5. **Write design doc** — save to `docs/plans/YYYY-MM-DD-<topic>-design.md`

**Do not** invoke writing-plans or any implementation skill. add-spec terminates after writing the spec file.

## Phase 2: Write No-Frills Spec

After the design doc is written and approved, derive and write the spec to `docs/specs/{project-name}.md`.

Keep the spec **no-frills and easily digestible** for Ralph loops and add-project: short bullets, clear headings, no filler.

### Required Spec Sections

Use this structure. Each section should be concise (bullets or short paragraphs).

```markdown
# {Project Name} — Spec

**Created**: {date}
**Status**: APPROVED

## Mission

- One sentence: what this project is and for whom.

## Main Features

- Feature 1
- Feature 2
- …

## Major User Flows

- Flow 1: step → step → outcome
- Flow 2: …

## Required Screens

- Screen/page name — purpose
- …

## Required Features (from /skills)

Map each requirement to existing skills from the catalog. List skill names and what they cover.

| Requirement | Skill(s) | Notes |
|-------------|----------|-------|
| Auth | auth, auth-dev | better-auth |
| Chat | ai-chat, ai-core | streaming |
| … | … | … |

## Open Gaps

- Anything that has no existing skill; custom implementation needed.

## Constraints / Assumptions

- Hard constraints (APIs, no Docker, auth provider, etc.)
- Assumptions (e.g. local dev only, specific stack).
```

### Rules for the Spec

- **No frills**: no long prose, no duplicate content from the design doc. The spec is a compact reference.
- **Digestible**: someone running add-project or a Ralph loop should grasp scope and skills in one read.
- **Skills mapping**: scan the skill catalog (e.g. from add-feature or skills/*/SKILL.md) to map requirements to skill names; flag gaps as Open Gaps.

## What Gets Created

- `docs/plans/YYYY-MM-DD-<topic>-design.md` — full design (from brainstorming)
- `docs/specs/{project-name}.md` — no-frills spec for add-project / Ralph

## When Invoked by add-project

If add-project delegated Phase 1 to add-spec:

1. Run add-spec as above (brainstorming → design doc → spec file).
2. After the spec is written, return the spec path `docs/specs/{project-name}.md` to add-project so it can proceed to Phase 2 (shell) and Phase 3 (Ralph loop).

## Acceptance Criteria

- [ ] Full brainstorming workflow completed (context, questions, approaches, design approval)
- [ ] Design doc written to docs/plans/YYYY-MM-DD-<topic>-design.md
- [ ] No-frills spec written to docs/specs/{project-name}.md
- [ ] Spec includes all required sections: Mission, Main Features, Major User Flows, Required Screens, Required Features (skills mapping), Open Gaps, Constraints/Assumptions
- [ ] Spec is concise and digestible; no writing-plans or implementation skill invoked
