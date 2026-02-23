---
name: clip-score
description: 4-axis video segment scoring using AI extended thinking — returns emotional peak, info density, surprise, and standalone scores per segment. Use this skill when the user says "add clip scoring", "score video segments", "find best clips", or "clip analysis".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: [ai-reasoning, env-config]
---

# Clip Score Skill

Sends transcript segments to Claude with extended thinking (budgetTokens: 8000) and receives per-segment scores on four axes: emotional peak, info density, surprise, and standalone. Returns a ranked list plus the full scored set. Auth-protected POST endpoint.

## Prerequisites

- Next.js app with App Router (no `src/` directory)
- `ai-reasoning` skill applied (provides `@anthropic-ai/sdk` and extended thinking pattern)
- `env-config` skill applied (provides env var validation)
- `better-auth` configured at `@src/lib/auth`

## Installation

```bash
bun add @anthropic-ai/sdk
```

## What Gets Created

```
app/
└── api/
    └── clip-score/
        └── route.ts          # POST endpoint — auth-gated, calls Anthropic with extended thinking
lib/
└── clip-score/
    └── index.ts              # Types + scoring prompt builder
```

## Environment Variables

Add to `.env.local`:

```
ANTHROPIC_API_KEY=sk-ant-...
```

## Setup Steps

### Step 1: Create `lib/clip-score/index.ts`

```typescript
export type TranscriptSegment = {
  id: number;
  start: number; // seconds
  end: number; // seconds
  text: string;
};

export type ClipScoreInput = {
  segments: TranscriptSegment[];
  videoContext?: string; // optional: title, description of the video
  preferences?: {
    preferFunny?: boolean;
    preferInformational?: boolean;
    preferControversial?: boolean;
  };
};

export type ScoredSegment = TranscriptSegment & {
  score: number; // composite 0-1
  axes: {
    emotionalPeak: number; // 0-1
    infoDensity: number; // 0-1
    surprise: number; // 0-1
    standAlone: number; // 0-1
  };
  rationale: string;
};

export type ClipScoreResult = {
  segments: ScoredSegment[];
  topSegments: ScoredSegment[]; // top 5 by score
  processingMs: number;
};

const TOP_SEGMENT_COUNT = 5;

export function buildScoringPrompt(input: ClipScoreInput): string {
  const { segments, videoContext, preferences } = input;

  const contextBlock = videoContext
    ? `\nVideo context:\n${videoContext}\n`
    : "";

  const preferenceLines: string[] = [];
  if (preferences?.preferFunny) {
    preferenceLines.push("- Prefer segments that are funny or entertaining");
  }
  if (preferences?.preferInformational) {
    preferenceLines.push("- Prefer segments with high informational value");
  }
  if (preferences?.preferControversial) {
    preferenceLines.push("- Prefer segments with provocative or controversial content");
  }
  const preferencesBlock =
    preferenceLines.length > 0
      ? `\nUser preferences (adjust weights accordingly):\n${preferenceLines.join("\n")}\n`
      : "";

  const segmentLines = segments
    .map(
      (seg) =>
        `[ID:${seg.id}] ${formatTime(seg.start)}–${formatTime(seg.end)}: ${seg.text.trim()}`
    )
    .join("\n");

  return `You are an expert video editor and content analyst. Your task is to score each transcript segment on four axes to identify the best short-form clips.
${contextBlock}${preferencesBlock}
## Scoring Axes

Score each axis from 0.0 to 1.0:

- **emotionalPeak**: How much laughter, surprise, strong emotion, or high energy is present. 1.0 = maximum emotional intensity.
- **infoDensity**: Facts, insights, actionable takeaways, or memorable information per minute. 1.0 = packed with value.
- **surprise**: Unexpected revelations, counterintuitive ideas, or dramatic turns. 1.0 = completely unexpected.
- **standAlone**: Can this clip be understood without watching the rest of the video? 1.0 = fully self-contained.

The composite **score** is the weighted average: (emotionalPeak * 0.3) + (infoDensity * 0.25) + (surprise * 0.25) + (standAlone * 0.2).

## Transcript Segments

${segmentLines}

## Output Format

Return ONLY a valid JSON array with no markdown fences or extra text. Each element must match this shape:

{
  "id": <number matching the segment ID>,
  "score": <number 0.0–1.0, two decimal places>,
  "axes": {
    "emotionalPeak": <number 0.0–1.0>,
    "infoDensity": <number 0.0–1.0>,
    "surprise": <number 0.0–1.0>,
    "standAlone": <number 0.0–1.0>
  },
  "rationale": "<one sentence explaining the scores>"
}

Return one object per segment in the same order as the input. Do not omit any segments.`;
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

type RawScoredItem = {
  id: number;
  score: number;
  axes: {
    emotionalPeak: number;
    infoDensity: number;
    surprise: number;
    standAlone: number;
  };
  rationale: string;
};

export function mergeScores(
  segments: TranscriptSegment[],
  rawScores: RawScoredItem[]
): ScoredSegment[] {
  return segments.map((seg) => {
    const scored = rawScores.find((r) => r.id === seg.id);
    if (!scored) {
      return {
        ...seg,
        score: 0,
        axes: { emotionalPeak: 0, infoDensity: 0, surprise: 0, standAlone: 0 },
        rationale: "No score returned for this segment.",
      };
    }
    return { ...seg, ...scored };
  });
}

export function getTopSegments(segments: ScoredSegment[]): ScoredSegment[] {
  return segments
    .slice()
    .sort((a, b) => b.score - a.score)
    .slice(0, TOP_SEGMENT_COUNT);
}
```

### Step 2: Create `app/api/clip-score/route.ts`

```typescript
import { NextRequest, NextResponse } from "next/server";
import Anthropic from "@anthropic-ai/sdk";
import { auth } from "@src/lib/auth";
import {
  buildScoringPrompt,
  mergeScores,
  getTopSegments,
  type ClipScoreInput,
  type ClipScoreResult,
  type TranscriptSegment,
  type ScoredSegment,
} from "@src/lib/clip-score";

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

type RawScoreItem = {
  id: number;
  score: number;
  axes: {
    emotionalPeak: number;
    infoDensity: number;
    surprise: number;
    standAlone: number;
  };
  rationale: string;
};

function isValidRawScoreItem(item: unknown): item is RawScoreItem {
  if (typeof item !== "object" || item === null) return false;
  const obj = item as Record<string, unknown>;
  if (typeof obj.id !== "number") return false;
  if (typeof obj.score !== "number") return false;
  if (typeof obj.rationale !== "string") return false;
  if (typeof obj.axes !== "object" || obj.axes === null) return false;
  const axes = obj.axes as Record<string, unknown>;
  return (
    typeof axes.emotionalPeak === "number" &&
    typeof axes.infoDensity === "number" &&
    typeof axes.surprise === "number" &&
    typeof axes.standAlone === "number"
  );
}

function extractJsonFromText(text: string): unknown {
  // Strip markdown code fences if present
  const stripped = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  return JSON.parse(stripped);
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  // Auth check
  const session = await auth.api.getSession({ headers: request.headers });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const input = body as Partial<ClipScoreInput>;

  if (!Array.isArray(input.segments) || input.segments.length === 0) {
    return NextResponse.json(
      { error: "segments must be a non-empty array" },
      { status: 400 }
    );
  }

  const segments = input.segments as TranscriptSegment[];
  const prompt = buildScoringPrompt({
    segments,
    videoContext: input.videoContext,
    preferences: input.preferences,
  });

  const startMs = Date.now();

  let rawScores: RawScoreItem[];

  try {
    const response = await anthropic.messages.create({
      model: "claude-sonnet-4-5",
      max_tokens: 16000,
      thinking: {
        type: "enabled",
        budget_tokens: 8000,
      },
      messages: [
        {
          role: "user",
          content: prompt,
        },
      ],
    });

    // Extract the text block from the response
    const textBlock = response.content.find((block) => block.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      return NextResponse.json(
        { error: "No text response from model" },
        { status: 502 }
      );
    }

    let parsed: unknown;
    try {
      parsed = extractJsonFromText(textBlock.text);
    } catch {
      return NextResponse.json(
        { error: "Model returned invalid JSON", raw: textBlock.text.slice(0, 500) },
        { status: 502 }
      );
    }

    if (!Array.isArray(parsed)) {
      return NextResponse.json(
        { error: "Model response was not a JSON array" },
        { status: 502 }
      );
    }

    rawScores = parsed.filter(isValidRawScoreItem);

    if (rawScores.length === 0) {
      return NextResponse.json(
        { error: "Model returned no valid score objects" },
        { status: 502 }
      );
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown Anthropic error";
    return NextResponse.json({ error: message }, { status: 502 });
  }

  const processingMs = Date.now() - startMs;
  const scoredSegments: ScoredSegment[] = mergeScores(segments, rawScores);
  const topSegments = getTopSegments(scoredSegments);

  const result: ClipScoreResult = {
    segments: scoredSegments,
    topSegments,
    processingMs,
  };

  return NextResponse.json(result);
}
```

## Usage

```typescript
// From a client component or server action
const response = await fetch("/api/clip-score", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    segments: [
      { id: 1, start: 0, end: 15, text: "Welcome to the show. Today we're talking about something that changed my life." },
      { id: 2, start: 15, end: 30, text: "I used to make ten dollars a day. Now I make ten thousand. Here's exactly what I did." },
      { id: 3, start: 30, end: 45, text: "First, I stopped watching TV. Second, I started reading two books a week." },
      { id: 4, start: 45, end: 60, text: "The thing nobody tells you is that the first six months will feel like a total failure." },
      { id: 5, start: 60, end: 75, text: "And that's it. That's the whole system. Simple, but almost nobody does it." },
    ],
    videoContext: "Personal finance YouTube video: 'How I went from broke to financial freedom'",
    preferences: {
      preferInformational: true,
    },
  }),
});

const result = await response.json();
// result.topSegments[0] — highest scoring clip
// result.segments — all segments with scores
// result.processingMs — total time including thinking
```

## Acceptance Criteria

- `POST /api/clip-score` with 5 mock segments returns `200` with all segments scored with 4 axes and a rationale
- `topSegments` contains at most 5 entries, sorted by `score` descending
- `POST /api/clip-score` with an empty `segments` array returns `400`
- `POST /api/clip-score` without a valid auth session returns `401`
- `processingMs` is a positive integer reflecting actual request duration
- Extended thinking is enabled (`thinking.type === "enabled"`, `budget_tokens: 8000`)
- `tsc` passes with no errors
- Build succeeds
