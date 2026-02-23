---
name: ai-voice-room
description: AI voice agent for video rooms — dispatch an AI participant that listens, thinks, and speaks in real-time meetings via LiveKit. Supports configurable personas (note-taker, strategist, interviewer, tutor). Use this skill when the user says "add AI agent to room", "ai voice participant", "setup voice agent", "add ai to meeting", or "setup ai-voice-room".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [video-room, ai-core, transcription, env-config]
---

# AI Voice Room

Dispatch an AI voice agent into a LiveKit video room as a real participant. The agent listens to room audio, transcribes speech via Deepgram (from the `transcription` skill), processes it through an LLM (via `ai-core`'s `getModel()`), generates a spoken response via TTS, and publishes audio back to the room. Includes predefined personas (note-taker, strategist, interviewer, tutor) and a management API for creating and removing agents.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `video-room` skill installed (LiveKit room + participant tokens)
- `ai-core` skill installed (`getModel()` at `@src/lib/ai`)
- `transcription` skill installed (Deepgram client at `@src/lib/video/transcription`)
- `env-config` skill installed (`src/env.ts`)
- shadcn/ui initialized

## Installation

No new packages required. Uses packages already installed by dependencies:

- `ai` (from ai-core)
- `livekit-server-sdk` (from video-room)
- `@deepgram/sdk` (from transcription)

## Environment Variables

No new environment variables required. Uses existing variables from dependencies:

- `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` (from video-room)
- `LIVEKIT_URL` (from video-room)
- `DEEPGRAM_API_KEY` (from transcription)
- `AI_GATEWAY_API_KEY` (from ai-core)

## What Gets Created

```
src/
├── lib/
│   └── ai/
│       ├── voice-agent.ts                # Server: create, dispatch, remove AI agents
│       ├── agent-personas.ts             # Predefined agent personas with system prompts
│       └── types-voice-agent.ts          # VoiceAgentConfig, AgentPersona, AgentState
├── app/
│   └── api/
│       └── ai/
│           └── voice-agent/
│               └── route.ts              # POST create / DELETE remove agent
└── components/
    └── video/
        └── ai-agent-indicator.tsx        # UI indicator for AI agent state
```

## Architecture

The AI voice agent pipeline runs as follows:

```
Room Audio → Deepgram STT → LLM (via ai-core) → TTS → Room Audio
                                ↑
                          Agent Persona
                        (system prompt)
```

**Important**: The real-time audio pipeline (STT -> LLM -> TTS running continuously) is a background worker process. This skill provides:

1. **Dispatch layer** — API to create/remove agents in rooms
2. **Persona system** — Configurable agent behaviors
3. **Agent token management** — LiveKit participant tokens for AI agents
4. **State tracking** — Track agent state (idle/listening/thinking/speaking)
5. **UI indicator** — Visual feedback for agent state in the room

The actual continuous audio processing loop would run as a separate worker (e.g., a LiveKit Agents framework worker or a custom Node.js process). The dispatch API creates the agent's room presence and signals the worker to start processing.

## Setup Steps

### Step 1: Create `src/lib/ai/types-voice-agent.ts`

```typescript
export type AgentState = "idle" | "listening" | "thinking" | "speaking";

export type AgentPersona = {
  /** Unique identifier for the persona */
  id: string;
  /** Display name shown in the room */
  name: string;
  /** System prompt that shapes the agent's behavior */
  systemPrompt: string;
  /** TTS voice identifier (provider-specific, e.g., "aura-asteria-en" for Deepgram) */
  voice: string;
  /** Whether the agent proactively speaks or only responds when addressed */
  speakingStyle: "proactive" | "reactive";
  /** Optional model override (defaults to ai-core's getModel()) */
  modelId?: string;
};

export type VoiceAgentConfig = {
  /** The LiveKit room to join */
  roomName: string;
  /** The persona to use for this agent */
  persona: AgentPersona;
  /** Agent's participant identity in the room */
  participantIdentity: string;
  /** Agent's display name in the room */
  participantName: string;
};

export type VoiceAgentStatus = {
  /** The agent's current state */
  state: AgentState;
  /** Room the agent is in */
  roomName: string;
  /** Persona being used */
  personaId: string;
  /** Participant identity in the room */
  participantIdentity: string;
  /** When the agent was dispatched */
  dispatchedAt: Date;
};

export type DispatchAgentRequest = {
  roomName: string;
  personaId: string;
};

export type DispatchAgentResponse = {
  participantIdentity: string;
  participantName: string;
  roomName: string;
  personaId: string;
  token: string;
};
```

### Step 2: Create `src/lib/ai/agent-personas.ts`

```typescript
import type { AgentPersona } from "./types-voice-agent";

/**
 * Predefined agent personas for AI voice room participants.
 * Each persona defines the agent's behavior, voice, and speaking style.
 */
export const AGENT_PERSONAS: Record<string, AgentPersona> = {
  "note-taker": {
    id: "note-taker",
    name: "Notetaker",
    systemPrompt: `You are an AI note-taking assistant in a live meeting. Your role:
- Listen carefully to the entire conversation
- Rarely speak unless directly asked a question
- When asked, provide a concise summary of key points discussed so far
- Track action items, decisions, and open questions
- If asked "what did we decide about X?", recall the relevant discussion accurately
- Keep your responses brief (1-2 sentences) unless asked for a full summary
- Never interrupt the flow of conversation
- When summarizing, organize by: Key Decisions, Action Items, Open Questions`,
    voice: "aura-asteria-en",
    speakingStyle: "reactive",
  },

  strategist: {
    id: "strategist",
    name: "Strategist",
    systemPrompt: `You are an AI strategic advisor participating in a meeting. Your role:
- Actively engage in the discussion with thoughtful contributions
- Offer alternative perspectives and identify blind spots
- Challenge assumptions constructively with "have you considered..." prompts
- Synthesize multiple viewpoints into actionable frameworks
- Suggest next steps and prioritization when the discussion stalls
- Keep contributions concise (2-3 sentences max)
- Wait for natural pauses before contributing — don't interrupt
- Reference specific points others have made to show active listening`,
    voice: "aura-orion-en",
    speakingStyle: "proactive",
  },

  interviewer: {
    id: "interviewer",
    name: "Interviewer",
    systemPrompt: `You are an AI interviewer conducting a conversational interview. Your role:
- Ask thoughtful follow-up questions that dig deeper into responses
- Use the STAR method (Situation, Task, Action, Result) to structure follow-ups
- Probe for specifics: "Can you give me a concrete example of that?"
- Listen for gaps or vague answers and ask for clarification
- Maintain a warm, encouraging tone
- Keep questions short and focused (one question at a time)
- After 3-4 follow-ups on a topic, transition to a new area
- Summarize what you've heard before moving on to validate understanding`,
    voice: "aura-luna-en",
    speakingStyle: "proactive",
  },

  tutor: {
    id: "tutor",
    name: "Tutor",
    systemPrompt: `You are an AI tutor participating in a learning session. Your role:
- Explain complex concepts in simple, clear language
- Use analogies and real-world examples to make ideas concrete
- Ask comprehension-check questions: "Does that make sense?" or "Can you explain it back to me?"
- Break down problems into smaller steps
- When someone is confused, try a different explanation approach
- Encourage questions and make it safe to say "I don't understand"
- Build on what the learner already knows
- Keep explanations under 30 seconds of speech — pause for questions`,
    voice: "aura-athena-en",
    speakingStyle: "reactive",
  },
} as const;

/**
 * Get an agent persona by ID.
 * @throws Error if the persona ID is not found.
 */
export function getPersona(personaId: string): AgentPersona {
  const persona = AGENT_PERSONAS[personaId];
  if (!persona) {
    const available = Object.keys(AGENT_PERSONAS).join(", ");
    throw new Error(
      `Unknown persona "${personaId}". Available personas: ${available}`
    );
  }
  return persona;
}

/**
 * List all available persona IDs and names.
 */
export function listPersonas(): Array<{ id: string; name: string; speakingStyle: string }> {
  return Object.values(AGENT_PERSONAS).map((p) => ({
    id: p.id,
    name: p.name,
    speakingStyle: p.speakingStyle,
  }));
}
```

### Step 3: Create `src/lib/ai/voice-agent.ts`

```typescript
import { AccessToken } from "livekit-server-sdk";
import { generateText } from "ai";
import { getModel } from "@src/lib/ai";
import { getPersona } from "./agent-personas";
import type {
  VoiceAgentConfig,
  VoiceAgentStatus,
  DispatchAgentResponse,
  AgentState,
} from "./types-voice-agent";

/**
 * In-memory registry of active voice agents.
 * In production, this should be backed by Redis or a database.
 */
const activeAgents = new Map<string, VoiceAgentStatus>();

/**
 * Create a LiveKit participant token for an AI voice agent.
 * The token grants the agent permission to subscribe to audio tracks
 * and publish its own audio track back to the room.
 */
async function createAgentToken(config: VoiceAgentConfig): Promise<string> {
  const apiKey = process.env.LIVEKIT_API_KEY;
  const apiSecret = process.env.LIVEKIT_API_SECRET;

  if (!apiKey || !apiSecret) {
    throw new Error("LIVEKIT_API_KEY and LIVEKIT_API_SECRET must be set");
  }

  const token = new AccessToken(apiKey, apiSecret, {
    identity: config.participantIdentity,
    name: config.participantName,
  });

  token.addGrant({
    room: config.roomName,
    roomJoin: true,
    canSubscribe: true,
    canPublish: true,
    canPublishData: true,
  });

  return await token.toJwt();
}

/**
 * Generate a unique participant identity for an AI agent.
 */
function generateAgentIdentity(personaId: string, roomName: string): string {
  const suffix = Date.now().toString(36);
  return `ai-agent-${personaId}-${roomName}-${suffix}`;
}

/**
 * Dispatch an AI voice agent into a LiveKit room.
 *
 * This creates a participant token and registers the agent in the active registry.
 * The actual audio pipeline (STT -> LLM -> TTS) runs as a background worker
 * that connects to the room using the returned token.
 *
 * @param roomName - The LiveKit room to join
 * @param personaId - The persona ID (e.g., "note-taker", "strategist")
 * @returns The agent's participant identity, name, room, and connection token
 */
export async function dispatchVoiceAgent(
  roomName: string,
  personaId: string
): Promise<DispatchAgentResponse> {
  const persona = getPersona(personaId);

  const participantIdentity = generateAgentIdentity(personaId, roomName);
  const participantName = `${persona.name} (AI)`;

  const config: VoiceAgentConfig = {
    roomName,
    persona,
    participantIdentity,
    participantName,
  };

  const token = await createAgentToken(config);

  // Register the agent
  const status: VoiceAgentStatus = {
    state: "idle",
    roomName,
    personaId,
    participantIdentity,
    dispatchedAt: new Date(),
  };
  activeAgents.set(participantIdentity, status);

  return {
    participantIdentity,
    participantName,
    roomName,
    personaId,
    token,
  };
}

/**
 * Remove an AI voice agent from a room.
 * Removes the agent from the active registry.
 * The background worker should detect the removal and disconnect.
 *
 * @param participantIdentity - The agent's participant identity
 * @returns true if the agent was found and removed, false otherwise
 */
export function removeVoiceAgent(participantIdentity: string): boolean {
  return activeAgents.delete(participantIdentity);
}

/**
 * Remove all AI voice agents from a specific room.
 *
 * @param roomName - The room to clear agents from
 * @returns The number of agents removed
 */
export function removeAllAgentsFromRoom(roomName: string): number {
  let removed = 0;
  for (const [identity, status] of activeAgents) {
    if (status.roomName === roomName) {
      activeAgents.delete(identity);
      removed++;
    }
  }
  return removed;
}

/**
 * Get the status of a specific voice agent.
 */
export function getAgentStatus(participantIdentity: string): VoiceAgentStatus | undefined {
  return activeAgents.get(participantIdentity);
}

/**
 * Update the state of a voice agent (called by the background worker).
 */
export function updateAgentState(participantIdentity: string, state: AgentState): void {
  const status = activeAgents.get(participantIdentity);
  if (status) {
    status.state = state;
  }
}

/**
 * List all active voice agents, optionally filtered by room.
 */
export function listActiveAgents(roomName?: string): VoiceAgentStatus[] {
  const agents = Array.from(activeAgents.values());
  if (roomName) {
    return agents.filter((a) => a.roomName === roomName);
  }
  return agents;
}

/**
 * Generate an AI text response for the voice agent pipeline.
 * This is called by the background worker after STT produces a transcript.
 * The response text is then sent to TTS for audio synthesis.
 *
 * @param personaId - The persona ID to use for the system prompt
 * @param conversationHistory - The accumulated conversation transcript
 * @param latestUtterance - The most recent utterance to respond to
 * @returns The agent's text response
 */
export async function generateAgentResponse(
  personaId: string,
  conversationHistory: string,
  latestUtterance: string
): Promise<string> {
  const persona = getPersona(personaId);

  const { text } = await generateText({
    model: getModel(persona.modelId),
    system: persona.systemPrompt,
    messages: [
      {
        role: "user",
        content: `Conversation so far:\n${conversationHistory}\n\nLatest utterance: "${latestUtterance}"\n\nRespond naturally as if you are in the meeting. Keep your response concise and conversational (under 3 sentences). If your persona is "reactive" and you weren't directly addressed, respond with an empty string.`,
      },
    ],
  });

  return text;
}
```

### Step 4: Create `src/app/api/ai/voice-agent/route.ts`

```typescript
import { NextResponse } from "next/server";
import {
  dispatchVoiceAgent,
  removeVoiceAgent,
  removeAllAgentsFromRoom,
  listActiveAgents,
} from "@src/lib/ai/voice-agent";
import { listPersonas } from "@src/lib/ai/agent-personas";
import type { DispatchAgentRequest } from "@src/lib/ai/types-voice-agent";

/**
 * GET /api/ai/voice-agent — list active agents and available personas
 *
 * Query params:
 * - roomName (optional): filter agents by room
 * - personas (optional): if "true", include available personas
 */
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const roomName = searchParams.get("roomName") ?? undefined;
  const includePersonas = searchParams.get("personas") === "true";

  const agents = listActiveAgents(roomName);

  const response: Record<string, unknown> = { agents };

  if (includePersonas) {
    response.personas = listPersonas();
  }

  return NextResponse.json(response);
}

/**
 * POST /api/ai/voice-agent — dispatch an AI agent into a room
 *
 * Body: { roomName: string, personaId: string }
 * Returns: { participantIdentity, participantName, roomName, personaId, token }
 */
export async function POST(request: Request) {
  const body: DispatchAgentRequest = await request.json();

  if (!body.roomName) {
    return NextResponse.json(
      { error: "roomName is required" },
      { status: 400 }
    );
  }

  if (!body.personaId) {
    return NextResponse.json(
      { error: "personaId is required" },
      { status: 400 }
    );
  }

  try {
    const result = await dispatchVoiceAgent(body.roomName, body.personaId);
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    return NextResponse.json(
      {
        error: error instanceof Error ? error.message : "Failed to dispatch agent",
      },
      { status: 500 }
    );
  }
}

/**
 * DELETE /api/ai/voice-agent — remove an AI agent from a room
 *
 * Query params:
 * - participantIdentity: remove a specific agent
 * - roomName: remove all agents from a room (if participantIdentity not provided)
 */
export async function DELETE(request: Request) {
  const { searchParams } = new URL(request.url);
  const participantIdentity = searchParams.get("participantIdentity");
  const roomName = searchParams.get("roomName");

  if (participantIdentity) {
    const removed = removeVoiceAgent(participantIdentity);
    if (!removed) {
      return NextResponse.json(
        { error: "Agent not found" },
        { status: 404 }
      );
    }
    return NextResponse.json({ success: true, participantIdentity });
  }

  if (roomName) {
    const count = removeAllAgentsFromRoom(roomName);
    return NextResponse.json({ success: true, removedCount: count });
  }

  return NextResponse.json(
    { error: "Provide participantIdentity or roomName" },
    { status: 400 }
  );
}
```

### Step 5: Create `src/components/video/ai-agent-indicator.tsx`

```tsx
"use client";

import { useId } from "react";
import { cn } from "@src/lib/utils";
import type { AgentState } from "@src/lib/ai/types-voice-agent";

type AgentInfo = {
  participantIdentity: string;
  name: string;
  personaId: string;
  state: AgentState;
};

type AIAgentIndicatorProps = {
  agent: AgentInfo;
  className?: string;
  compact?: boolean;
};

const STATE_CONFIG: Record<AgentState, { label: string; color: string; animation: string }> = {
  idle: {
    label: "Idle",
    color: "text-muted-foreground",
    animation: "",
  },
  listening: {
    label: "Listening",
    color: "text-blue-500",
    animation: "animate-pulse",
  },
  thinking: {
    label: "Thinking",
    color: "text-amber-500",
    animation: "animate-spin",
  },
  speaking: {
    label: "Speaking",
    color: "text-emerald-500",
    animation: "animate-bounce",
  },
};

function AgentIcon({ state, className }: { state: AgentState; className?: string }) {
  const config = STATE_CONFIG[state];

  return (
    <div className={cn("relative", className)}>
      {/* Outer ring animation for active states */}
      {state !== "idle" && (
        <div
          className={cn(
            "absolute inset-0 rounded-full opacity-30",
            state === "listening" && "animate-ping bg-blue-500",
            state === "thinking" && "animate-pulse bg-amber-500",
            state === "speaking" && "animate-ping bg-emerald-500"
          )}
        />
      )}
      {/* Core icon */}
      <div
        className={cn(
          "relative flex items-center justify-center rounded-full",
          config.color
        )}
      >
        {state === "idle" && (
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="10" />
            <path d="M8 12h8" />
          </svg>
        )}
        {state === "listening" && (
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={config.animation}>
            <path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z" />
            <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
            <line x1="12" x2="12" y1="19" y2="22" />
          </svg>
        )}
        {state === "thinking" && (
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="10" />
            <path d="M12 6v6l4 2" />
          </svg>
        )}
        {state === "speaking" && (
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
            <path d="M15.54 8.46a5 5 0 0 1 0 7.07" />
            <path d="M19.07 4.93a10 10 0 0 1 0 14.14" />
          </svg>
        )}
      </div>
    </div>
  );
}

export function AIAgentIndicator({ agent, className, compact = false }: AIAgentIndicatorProps) {
  const config = STATE_CONFIG[agent.state];

  if (compact) {
    return (
      <div
        className={cn("flex items-center gap-1.5", className)}
        title={`${agent.name} — ${config.label}`}
      >
        <AgentIcon state={agent.state} className="h-4 w-4" />
        <span className={cn("text-xs font-medium", config.color)}>
          {agent.name}
        </span>
      </div>
    );
  }

  return (
    <div
      className={cn(
        "flex items-center gap-3 rounded-lg border bg-card p-3",
        className
      )}
    >
      <div className="relative h-10 w-10 shrink-0">
        <div
          className={cn(
            "flex h-full w-full items-center justify-center rounded-full bg-muted",
            agent.state !== "idle" && "ring-2",
            agent.state === "listening" && "ring-blue-500/50",
            agent.state === "thinking" && "ring-amber-500/50",
            agent.state === "speaking" && "ring-emerald-500/50"
          )}
        >
          <AgentIcon state={agent.state} className="h-5 w-5" />
        </div>
      </div>

      <div className="flex flex-col gap-0.5 min-w-0">
        <span className="truncate text-sm font-medium">{agent.name}</span>
        <span className={cn("text-xs", config.color)}>
          {config.label}
        </span>
      </div>
    </div>
  );
}

type AIAgentListProps = {
  agents: AgentInfo[];
  className?: string;
  compact?: boolean;
};

export function AIAgentList({ agents, className, compact = false }: AIAgentListProps) {
  const listId = useId();

  if (agents.length === 0) return null;

  return (
    <div className={cn("flex flex-col gap-2", className)}>
      {!compact && (
        <h3 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          AI Agents ({agents.length})
        </h3>
      )}
      {agents.map((agent) => (
        <AIAgentIndicator
          key={`${listId}-${agent.participantIdentity}`}
          agent={agent}
          compact={compact}
        />
      ))}
    </div>
  );
}
```

## Usage

### Dispatch an AI Agent into a Room

```typescript
// Add a strategist AI to a meeting
const res = await fetch("/api/ai/voice-agent", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    roomName: "meeting-standup-2026-02-18",
    personaId: "strategist",
  }),
});
const agent = await res.json();
// { participantIdentity, participantName, roomName, personaId, token }
```

### List Active Agents in a Room

```typescript
const res = await fetch("/api/ai/voice-agent?roomName=meeting-standup-2026-02-18&personas=true");
const { agents, personas } = await res.json();
```

### Remove an Agent

```typescript
// Remove a specific agent
await fetch("/api/ai/voice-agent?participantIdentity=ai-agent-strategist-meeting-abc123", {
  method: "DELETE",
});

// Remove all agents from a room
await fetch("/api/ai/voice-agent?roomName=meeting-standup-2026-02-18", {
  method: "DELETE",
});
```

### Display Agent Status in a Room UI

```tsx
"use client";

import { useState, useEffect, useId } from "react";
import { AIAgentList } from "@/components/video/ai-agent-indicator";
import type { AgentState } from "@src/lib/ai/types-voice-agent";

type AgentApiItem = {
  participantIdentity: string;
  personaId: string;
  roomName: string;
  state: AgentState;
};

type PersonaItem = {
  id: string;
  name: string;
  speakingStyle: string;
};

export function RoomAgentPanel({ roomName }: { roomName: string }) {
  const personaListId = useId();
  const [agents, setAgents] = useState<AgentApiItem[]>([]);
  const [personas, setPersonas] = useState<PersonaItem[]>([]);

  useEffect(() => {
    fetch(`/api/ai/voice-agent?roomName=${roomName}&personas=true`)
      .then((res) => res.json())
      .then((data: { agents: AgentApiItem[]; personas: PersonaItem[] }) => {
        setAgents(data.agents);
        setPersonas(data.personas);
      });
  }, [roomName]);

  const addAgent = async (personaId: string) => {
    const res = await fetch("/api/ai/voice-agent", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ roomName, personaId }),
    });
    if (res.ok) {
      // Refresh agent list
      const updated = await fetch(`/api/ai/voice-agent?roomName=${roomName}`);
      const data: { agents: AgentApiItem[] } = await updated.json();
      setAgents(data.agents);
    }
  };

  return (
    <div className="flex flex-col gap-4 p-4">
      <AIAgentList
        agents={agents.map((a) => ({
          participantIdentity: a.participantIdentity,
          name: personas.find((p) => p.id === a.personaId)?.name ?? a.personaId,
          personaId: a.personaId,
          state: a.state,
        }))}
      />

      <div className="flex flex-wrap gap-2">
        {personas.map((p) => (
          <button
            key={`${personaListId}-${p.id}`}
            type="button"
            onClick={() => addAgent(p.id)}
            className="rounded-md border px-3 py-1.5 text-sm hover:bg-accent"
          >
            + {p.name}
          </button>
        ))}
      </div>
    </div>
  );
}
```

### Generate a Response (Worker-Side)

```typescript
import { generateAgentResponse } from "@src/lib/ai/voice-agent";

// In your background worker processing loop:
const response = await generateAgentResponse(
  "strategist",
  "Alice: We need to finalize the Q2 roadmap.\nBob: I think we should prioritize mobile.",
  "Bob: I think we should prioritize mobile."
);

if (response.trim()) {
  // Send response text to TTS, then publish audio to room
  console.log("Agent says:", response);
}
```

## Background Worker Architecture

The dispatch API creates the agent's presence in the room. The real-time audio pipeline runs as a separate process:

```
┌──────────────────────────────────────────────────────────────┐
│                    Background Worker                          │
│                                                               │
│  1. Connect to LiveKit room using agent token                │
│  2. Subscribe to all audio tracks                            │
│  3. Mix audio streams into a single buffer                   │
│  4. Stream audio to Deepgram (createLiveTranscription)       │
│  5. Accumulate transcript, detect when addressed             │
│  6. Call generateAgentResponse() with conversation context   │
│  7. Send response text to TTS provider (Deepgram Aura)      │
│  8. Publish TTS audio back to the room as an audio track     │
│  9. Broadcast agent state changes via data channel           │
│                                                               │
│  Loop: back to step 4                                        │
└──────────────────────────────────────────────────────────────┘
```

For production, consider using the [LiveKit Agents framework](https://docs.livekit.io/agents/) which provides a robust infrastructure for this pipeline, or implement a custom Node.js worker using `livekit-server-sdk`.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/ai/voice-agent` | List active agents (`?roomName=`, `?personas=true`) |
| POST | `/api/ai/voice-agent` | Dispatch agent `{ roomName, personaId }` |
| DELETE | `/api/ai/voice-agent` | Remove agent (`?participantIdentity=` or `?roomName=`) |

## Acceptance Criteria

- `dispatchVoiceAgent()` creates a valid LiveKit participant token for the AI agent
- `removeVoiceAgent()` removes the agent from the active registry
- `getPersona()` returns the correct persona for known IDs and throws for unknown ones
- `listPersonas()` returns all four built-in personas
- `generateAgentResponse()` returns a text response from the LLM using the persona's system prompt
- POST `/api/ai/voice-agent` returns `201` with agent details and a LiveKit token
- DELETE `/api/ai/voice-agent?participantIdentity=...` removes the agent
- DELETE `/api/ai/voice-agent?roomName=...` removes all agents from the room
- GET `/api/ai/voice-agent?personas=true` includes the persona list
- `AIAgentIndicator` renders the correct icon and animation for each agent state
- `AIAgentList` renders multiple agents with unique keys via `useId`
- No usage of `any` type anywhere
- `tsc` passes with no errors
- `bun run build` succeeds

## Troubleshooting

### "LIVEKIT_API_KEY and LIVEKIT_API_SECRET must be set"

**Cause**: LiveKit credentials are missing from `.env.local`.

**Fix**: Ensure the `video-room` skill has been applied and `.env.local` contains `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, and `LIVEKIT_URL`.

### "Unknown persona" error

**Cause**: The `personaId` in the POST body doesn't match any predefined persona.

**Fix**: Use one of the available personas: `note-taker`, `strategist`, `interviewer`, `tutor`. Call GET `/api/ai/voice-agent?personas=true` to see the full list.

### Agent appears in room but doesn't speak

**Cause**: The dispatch API only creates the room presence and token. The actual audio pipeline requires a running background worker.

**Fix**: Implement a background worker that connects to the room using the agent token, subscribes to audio, and runs the STT -> LLM -> TTS loop. See the Architecture section above.

### Agent generates empty responses

**Cause**: Reactive personas (note-taker, tutor) only respond when directly addressed. The `generateAgentResponse` function instructs reactive personas to return empty strings when not spoken to.

**Fix**: This is expected behavior. Proactive personas (strategist, interviewer) will contribute more frequently. Address the agent by name to trigger a response from reactive personas.
