---
name: add-feature
description: >
  Parent skill for feature and project workflows. Use when the user wants to build a project,
  add a feature, polish a skill, test all skills, or browse the skill catalog. Routes to add-project
  (build project from idea), improve-skill (refine one skill in a sandbox), test-skills (validate
  full skill composition), or any child skill by name.
---

# Add Feature — Skill Index and Usage
<!-- markdownlint-disable MD060 -->

This skill is the entry point for project and feature workflows. Use it to choose the right child skill or to see the full catalog.

## Meta child skills (invoke by name)

| Skill | When to use |
|-------|-------------|
| **add-spec** | User says "spec a project", "create a spec", "spec this idea", "plan a project", "write a spec". Runs full brainstorming workflow then writes a no-frills spec to docs/specs/{name}.md for Ralph loops and add-project. |
| **add-project** | User says "build project", "new project", "create project", "scaffold project". Creates project shell + Ralph execution loop (Phase 1 delegates to add-spec for the spec); does not scaffold Next.js (Ralph does that at step 1.1). |
| **improve-skill** | User says "polish a skill", "refine skill", "test a skill", "improve skill docs", "validate a skill". Iteratively implements one skill in a sandbox, validates, reflects on errors, updates SKILL.md, reverts, retries until clean. |
| **test-skills** | User says "test all skills", "validate skill composition", "integration test skills". Applies all skills in dependency order across sandboxes, validates composition, fixes markdown, ports back. |
| **eval-projects** | User says "eval projects", "evaluate loops", "review ralph loops", "suggest loop improvements". Reviews evaluation tracking from all ralph loops and logs in loops/, then suggests critical and nice-to-have improvements. |

## How to use child skills

- **Explicit invocation:** Invoke by name (e.g. `/skills:add-project` or `/skills:create-next`). The agent loads that skill's full instructions.
- **From this index:** If the user asks to "add a feature", "build a project", or "spec a project", read this SKILL.md then invoke the appropriate child (add-spec for specs only, add-project for full build, improve-skill, test-skills, or the specific feature skill).
- **Paths:** All skills live under `skills/<name>/SKILL.md`. References in add-project, improve-skill, and test-skills use `skills/` as the canonical root.

## Full skill catalog

The plugin provides the following skills. Invoke any by name when the task matches that skill's scope.

### Meta & project

- add-feature (this skill)
- add-spec
- add-project
- improve-skill
- test-skills
- eval-projects
- create-next
- docker
- env-config
- setup-vercel
- setup-lefthook
- env-from-1password
- ralph-ci
- openclaw-generator

### UI & design

- add-shadcn
- add-seo
- add-pwa
- motion
- lottie
- react-flow
- react-three-fiber
- image-editor

### Data & backend

- db
- storage
- storage-ui
- queue
- auth
- auth-dev
- email
- payments
- search
- cms
- compliance
- observability
- analytics

### AI

- ai-sdk
- ai-core
- ai-chat
- ai-tools
- ai-reasoning
- ai-memory
- ai-tasks
- ai-artifacts
- ai-mcp
- ai-image-gen
- ai-video-gen
- ai-generative-ui
- ai-captions
- ai-meeting-notes
- ai-voice-room
- ai-rag-ingest
- ai-rag-vectors
- ai-rag-viewer
- ai-rag-chat
- ai-rag-app
- ai-multi-agent

### Realtime & media

- realtime
- video-room
- video-ui
- video-player
- screen-share
- audio-room
- stream-mux
- livestream
- recording
- transcription
- video-messaging
- media-bunny

### Debrief & content

- debrief
- debrief-intake
- debrief-index
- debrief-viewer-sync
- debrief-cited-chat
- debrief-deep-analysis
- debrief-executive-summary
- debrief-export
- debrief-demo-access

### Other

- group-chat
- notifications-push
- knowledge-sync
- voice-retell
- embeddable-widget
- structured-editor
- slides
- spec-export
- workflow
- rss
- yt-dlp
- dj-tracklist-downloader
- unicorn-studio
- mcp-server

### Testing

- e2e
- e2e-chat
- e2e-streaming
- e2e-video

## Dependencies

Child skills declare dependencies in their frontmatter (`metadata.dependencies` or `dependencies`). When applying multiple skills, respect dependency order (e.g. create-next before add-shadcn; db before auth). add-project and test-skills build dependency graphs from skill frontmatter.
