# Scaffold Guide

What to install and in what order. Complete each tier before pulling from the next.

## Tier 0 — Every Project

No decisions. Always apply in order.

| Step | Skills | What you get |
| ---- | ------ | ------------ |
| App shell | `create-next` | Next.js, TypeScript, Tailwind, Biome, Bun, folder conventions |
| Runtime | `docker`, `env-config` | Local services, typed env contracts, dev/prod config |
| UI + Data | `add-shadcn`, `db` | UI primitives (shadcn), Drizzle + Postgres |
| Testing | `e2e` | Playwright harness + CI workflow |

## Tier 1 — Most Apps

Default for anything beyond a throwaway prototype. Add what applies.

| Capability | Skills | When to include |
| ---------- | ------ | --------------- |
| Auth | `auth`, `auth-dev` | Any user identity, permissions, billing, or private data |
| AI | `ai-core`, `ai-chat`, `ai-reasoning`, `ai-artifacts` | Conversational AI or copilot UX |
| Background jobs | `queue` | Work that exceeds request/response time budgets |

> **No auth?** Skip straight to Tier 2 picks. This is rare — mainly open widgets or anonymous-first prototypes.

## Tier 2 — Specialized Capabilities

Pick the packs you need. Each pack lists its prerequisites.

### Collaboration

| Capability | Skills | Requires |
| ---------- | ------ | -------- |
| Realtime state + presence | `realtime` | Auth |
| Human chat (threads, mentions, reactions) | `group-chat`, `notifications-push` | Realtime |
| Chat test coverage | `e2e-chat` | Human chat + E2E (Tier 0) |

### Video + Media

| Capability | Skills | Requires |
| ---------- | ------ | -------- |
| Live rooms (WebRTC, screen share, audio) | `video-room`, `video-ui`, `screen-share`, `audio-room` | Auth |
| Transcription | `transcription` | Video rooms |
| Meeting intelligence (captions, summaries, AI participant) | `ai-captions`, `ai-meeting-notes`, `ai-voice-room` | Transcription + AI (Tier 1) |
| Recording + archive | `recording` | Video rooms |
| Streaming + VOD (distribution, player, async video) | `stream-mux`, `video-player`, `livestream`, `video-messaging` | Recording + Background jobs (Tier 1) |
| Media test coverage | `e2e-video`, `e2e-streaming` | Video rooms + E2E (Tier 0) |

### Visual

| Capability | Skills | Requires |
| ---------- | ------ | -------- |
| Graph/flow canvas (pipelines, storyboards) | `react-flow` | UI + Data (Tier 0) |

## Tier 3 — Ops & Automation

For repo/process automation, not product features.

| Capability | Skills | What you get |
| ---------- | ------ | ------------ |
| CI/CD + deploy loops | `ralph-ci`, `openclaw-generator` | Autonomous build and deployment |
| Skill governance | `improve-skill`, `test-skills` | Skill quality loops |

## Extension Points

These are referenced by skills above but not yet packaged as tiers. Treat as seams for future packs.

- `storage` — file/media persistence (used by chat, video, recording skills)
- `ai-tools` — tool-use framework (used by artifacts, meeting intel)
- `add-pwa` — progressive web app support (used by push notifications)

## Quick Reference

**Starting a typical SaaS app?** Tier 0 → Auth + AI + Queue → pick Tier 2 packs as needed.

**Starting an anonymous tool/widget?** Tier 0 (skip auth) → VisualFlow or AI as needed.

**Adding video to an existing app?** Verify Auth is in place → Video rooms → layer on transcription/recording/streaming as needed.
