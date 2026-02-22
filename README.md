# skills
<!-- markdownlint-disable MD060 -->

Agent skill factory to create skills for feature and project development.

Each skill/feature lives under`skills/<name>/SKILL.md`, following the [Agent Skills spec](https://agentskills.io).

- `skills/` - current skills and routed feature skills
- `specs/` - generated specs
- `loops/` - generated ralph loops

## Install

```text
/plugin marketplace add mattwoodco/skills
/plugin install skills@mattwoodco
```

---

## Features (routed)

Features are written in skill format and become available when routed to by the entry skills. They are not registered in the plugin's top-level skills list.

### Project setup

| Feature              | Description                                               |
| -------------------- | --------------------------------------------------------- |
| `create-next`        | Initialize a new Next.js project with optimal defaults    |
| `add-shadcn`         | Design system using shadcn/ui                             |
| `setup-vercel`       | Setup Vercel for a project                                |
| `setup-lefthook`     | Git hooks with biome linting and type checking            |
| `env-config`         | Type-safe environment configuration with validation       |
| `env-from-1password` | Copy environment variables from 1Password to `.env.local` |

### AI / LLM

| Feature            | Description                                                          |
| ------------------ | -------------------------------------------------------------------- |
| `ai-core`          | Foundation AI layer - configures AI Gateway and exports `getModel()` |
| `ai-sdk`           | AI SDK integration                                                   |
| `ai-chat`          | Streaming chat UI with Postgres persistence                          |
| `ai-tools`         | Tool calling framework with collapsible UI cards                     |
| `ai-artifacts`     | Rich artifact panel - code, HTML, Mermaid, tables                   |
| `ai-reasoning`     | Extended thinking display with collapsible accordion                 |
| `ai-memory`        | Cross-session memory with context injection                          |
| `ai-tasks`         | Task extraction and management from conversation                     |
| `ai-mcp`           | Config-driven MCP server integration                                 |
| `ai-multi-agent`   | Multi-agent orchestration - N agents debate sequentially             |
| `ai-generative-ui` | Tool results rendered as React components                            |
| `ai-image-gen`     | AI image generation with Replicate and fal.ai                        |
| `ai-video-gen`     | AI video generation - text-to-video, image-to-video                 |
| `ai-voice-room`    | AI voice agent for LiveKit video rooms                               |
| `ai-meeting-notes` | Summaries, decisions, action items                                   |
| `ai-captions`      | Live closed captions via Deepgram + LiveKit                          |
| `workflow`         | Durable AI agent infrastructure with Workflow DevKit                 |

### RAG

| Feature          | Description                                                  |
| ---------------- | ------------------------------------------------------------ |
| `ai-rag-app`     | RAG application page - split-pane PDF chat with citations   |
| `ai-rag-ingest`  | PDF ingestion pipeline - chunked upload, parsing, extraction |
| `ai-rag-vectors` | Vector embeddings layer with pgvector + cosine similarity   |
| `ai-rag-chat`    | RAG-powered chat with source citations                       |
| `ai-rag-viewer`  | PDF viewer with text highlighting from search results        |

### Video / audio / realtime

| Feature           | Description                                                   |
| ----------------- | ------------------------------------------------------------- |
| `video-room`      | LiveKit video room infrastructure                             |
| `video-ui`        | LiveKit video UI components - grid, controls, prejoin        |
| `video-player`    | MUX Player React components                                   |
| `video-messaging` | Async video messaging - record, upload, transcribe, summarize |
| `stream-mux`      | MUX video infra - live streaming, VOD, webhooks              |
| `screen-share`    | Screen sharing components for LiveKit rooms                   |
| `audio-room`      | Audio-only room - circular avatar grid, speaking indicators  |
| `recording`       | Server-side room recording with LiveKit Egress                |
| `livestream`      | LiveKit -> MUX/YouTube/Twitch via RTMP                       |
| `transcription`   | Real-time and batch speech-to-text via Deepgram              |
| `realtime`        | Real-time collaboration with Liveblocks                       |
| `group-chat`      | Group chat with threads, reactions, mentions                  |
| `voice-retell`    | Browser voice calling via Retell AI                           |

### Infrastructure

| Feature              | Description                                                  |
| -------------------- | ------------------------------------------------------------ |
| `db`                 | PostgreSQL with Drizzle ORM - Docker local, pooling in prod |
| `auth`               | better-auth - email/password, social, RBAC, sessions        |
| `auth-dev`           | Dev-mode auth tooling - seed users, quick sign-in buttons   |
| `storage`            | Unified file storage - S3 local, Vercel Blob production     |
| `storage-ui`         | File UI - dropzone, list, preview modal                     |
| `queue`              | Background jobs with Inngest - serverless, no Redis         |
| `docker`             | Docker Compose local dev stack                              |
| `payments`           | Credit-based billing with Stripe                            |
| `email`              | Transactional email with Resend + Mailpit                   |
| `search`             | Meilisearch full-text search with Redis caching             |
| `notifications-push` | Web Push notifications with VAPID                           |
| `observability`      | OpenTelemetry tracing + structured logging                  |
| `analytics`          | Vercel Analytics with custom event tracking                 |

### Content and editing

| Feature             | Description                                       |
| ------------------- | ------------------------------------------------- |
| `cms`               | Simple CMS - posts/pages/categories + Tiptap      |
| `rss`               | RSS, Atom, and JSON Feed generation               |
| `add-seo`           | Comprehensive SEO via Next.js metadata APIs       |
| `add-pwa`           | PWA support with Serwist                          |
| `slides`            | Markdown -> presentation slides with Marp         |
| `structured-editor` | Section-based document editor with inline editing |
| `spec-export`       | Spec-to-ticket export - Linear, GitHub Issues     |
| `compliance`        | ADRs, runbooks, project documentation             |
| `image-editor`      | Canvas image editor with Konva.js                 |
| `embeddable-widget` | Embeddable iframe chat widget                     |

### Graphics and animation

| Feature             | Description                              |
| ------------------- | ---------------------------------------- |
| `motion`            | Framer Motion animations and transitions |
| `lottie`            | Lottie JSON-based vector animations      |
| `react-three-fiber` | 3D graphics with R3F and drei            |
| `unicorn-studio`    | Unicorn Studio WebGL shader effects      |
| `react-flow`        | Node-based diagrams and flowcharts       |

### Utilities

| Feature                   | Description                                           |
| ------------------------- | ----------------------------------------------------- |
| `media-bunny`             | Browser-based video processing with WebCodecs         |
| `knowledge-sync`          | External knowledge sync via REST API to RAG pipeline  |
| `mcp-server`              | Deploy a remote MCP server with OAuth 2.1             |
| `openclaw-generator`      | OpenClaw contract generation                          |

### Development

| Feature         | Description                                     |
| --------------- | ----------------------------------------------- |
| `improve-skill` | Refine and validate skill markdown in a sandbox |
| `test-skills`   | Test all skills in dependency order             |
| `eval-projects` | Evaluate projects                               |
| `ralph-ci`      | CI pipeline                                     |

## License

This repository is licensed under the MIT License. See `LICENSE`.
