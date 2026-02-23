---
name: storyboard-canvas
description: React Flow canvas preconfigured for storyboarding — custom shot nodes with frame image, description, duration, and camera angle, with a side panel for regeneration. Use this skill when the user says "add storyboard", "storyboard canvas", "shot list canvas", "visual storyboard", or "react flow storyboard".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: [react-flow, add-shadcn, ai-image-gen]
---

# Storyboard Canvas

A React Flow canvas tailored for video/film storyboarding. Each shot is a draggable node showing its frame image (or placeholder), description, duration, and camera angle. Clicking a node opens a right-side panel for editing metadata, regenerating the frame with a prompt, and browsing image history.

## Prerequisites

- Next.js app with App Router (no `src/` directory)
- `@xyflow/react` installed (from the `react-flow` skill)
- shadcn/ui installed (from the `add-shadcn` skill)
- `@phosphor-icons/react` installed

## Installation

```bash
bun add @xyflow/react
bun add @phosphor-icons/react
bunx shadcn@latest add button textarea badge scroll-area
```

## What Gets Created

```
components/
└── storyboard/
    ├── storyboard-canvas.tsx
    ├── storyboard-node.tsx
    └── shot-panel.tsx
lib/
└── storyboard/
    └── types.ts
```

## Setup Steps

### Step 1: Create `lib/storyboard/types.ts`

```typescript
import type { Edge, Node } from "@xyflow/react"

export type ShotStatus = "pending" | "generating" | "done" | "error"

export type ShotData = {
  shotNumber: number
  description: string
  cameraAngle: string
  duration: number
  imageUrl?: string
  imageHistory?: string[]
  status: ShotStatus
  notes?: string
}

export type StoryboardShot = Node<ShotData>

export type StoryboardEdge = Edge

export type StoryboardCanvasProps = {
  shots: ShotData[]
  onShotsChange?: (shots: ShotData[]) => void
  onRegenerateShot?: (shotId: string, prompt: string) => Promise<string>
  onExportPdf?: () => void
  onShareLink?: () => void
  className?: string
}
```

### Step 2: Create `components/storyboard/storyboard-node.tsx`

```typescript
"use client"

import type { ShotData } from "@src/lib/storyboard/types"
import { Camera } from "@phosphor-icons/react"
import { Handle, Position, type NodeProps } from "@xyflow/react"

export function StoryboardNode({ data, selected }: NodeProps<{ data: ShotData } & Record<string, unknown>>) {
  const shotData = data as unknown as ShotData

  return (
    <div
      className={[
        "w-[300px] rounded-xl bg-white shadow-md border transition-all select-none",
        selected ? "border-blue-500 ring-2 ring-blue-300" : "border-zinc-200",
      ].join(" ")}
    >
      <Handle type="target" position={Position.Left} className="!bg-zinc-400" />

      {/* Header */}
      <div className="flex items-center justify-between px-3 pt-3 pb-1">
        <span className="flex h-6 w-6 items-center justify-center rounded-full bg-blue-500 text-[11px] font-bold text-white">
          {shotData.shotNumber}
        </span>
        <StatusDot status={shotData.status} />
      </div>

      {/* Frame */}
      <div className="mx-3 h-[168px] overflow-hidden rounded-lg bg-zinc-100">
        {shotData.status === "generating" ? (
          <div className="h-full w-full animate-pulse bg-gradient-to-r from-zinc-200 via-zinc-100 to-zinc-200" />
        ) : shotData.imageUrl ? (
          <img
            src={shotData.imageUrl}
            alt={`Shot ${shotData.shotNumber}`}
            className="h-full w-full object-cover"
          />
        ) : (
          <div className="flex h-full w-full flex-col items-center justify-center gap-2 text-zinc-400">
            <Camera size={36} weight="thin" />
            <span className="text-xs">No frame yet</span>
          </div>
        )}
      </div>

      {/* Meta */}
      <div className="px-3 pb-3 pt-2">
        <p className="line-clamp-2 text-[13px] leading-snug text-zinc-700">
          {shotData.description || <span className="italic text-zinc-400">No description</span>}
        </p>
        <div className="mt-2 flex items-center gap-2">
          <span className="rounded-full bg-zinc-100 px-2 py-0.5 text-[11px] font-medium text-zinc-600">
            {shotData.duration}s
          </span>
          <span className="rounded-full bg-blue-50 px-2 py-0.5 text-[11px] font-medium text-blue-600">
            {shotData.cameraAngle}
          </span>
        </div>
      </div>

      <Handle type="source" position={Position.Right} className="!bg-zinc-400" />
    </div>
  )
}

function StatusDot({ status }: { status: ShotData["status"] }) {
  const colors: Record<ShotData["status"], string> = {
    pending: "bg-zinc-300",
    generating: "bg-yellow-400 animate-pulse",
    done: "bg-green-400",
    error: "bg-red-400",
  }
  return <span className={`block h-2.5 w-2.5 rounded-full ${colors[status]}`} />
}
```

### Step 3: Create `components/storyboard/shot-panel.tsx`

```typescript
"use client"

import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import type { ShotData } from "@src/lib/storyboard/types"
import { ArrowCounterClockwise, X } from "@phosphor-icons/react"
import { useId, useState } from "react"

type ShotPanelProps = {
  shotId: string
  data: ShotData
  onClose: () => void
  onChange: (updated: Partial<ShotData>) => void
  onRegenerate?: (shotId: string, prompt: string) => Promise<string>
}

export function ShotPanel({ shotId, data, onClose, onChange, onRegenerate }: ShotPanelProps) {
  const [prompt, setPrompt] = useState("")
  const [isRegenerating, setIsRegenerating] = useState(false)
  const historyId = useId()

  async function handleRegenerate() {
    if (!onRegenerate || !prompt.trim()) return
    setIsRegenerating(true)
    try {
      const newUrl = await onRegenerate(shotId, prompt)
      const history = [...(data.imageHistory ?? []), ...(data.imageUrl ? [data.imageUrl] : [])]
      onChange({ imageUrl: newUrl, imageHistory: history.slice(-3), status: "done" })
      setPrompt("")
    } catch {
      onChange({ status: "error" })
    } finally {
      setIsRegenerating(false)
    }
  }

  function restoreFromHistory(url: string) {
    const current = data.imageUrl
    const history = (data.imageHistory ?? []).filter((u) => u !== url)
    if (current) history.push(current)
    onChange({ imageUrl: url, imageHistory: history.slice(-3) })
  }

  return (
    <div className="flex h-full w-[380px] flex-col border-l border-zinc-200 bg-white">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-zinc-100 px-5 py-4">
        <div>
          <p className="text-xs font-medium text-zinc-400 uppercase tracking-wide">Shot {data.shotNumber}</p>
          <h2 className="text-sm font-semibold text-zinc-800">{data.cameraAngle}</h2>
        </div>
        <button
          onClick={onClose}
          className="flex h-7 w-7 items-center justify-center rounded-md text-zinc-400 hover:bg-zinc-100 hover:text-zinc-700 transition-colors"
          aria-label="Close panel"
        >
          <X size={16} />
        </button>
      </div>

      {/* Scrollable body */}
      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-5">
        {/* Description */}
        <section>
          <label className="mb-1.5 block text-xs font-medium text-zinc-600">Description</label>
          <Textarea
            value={data.description}
            onChange={(e) => onChange({ description: e.target.value })}
            rows={3}
            className="resize-none text-sm"
            placeholder="Describe the shot..."
          />
        </section>

        {/* Duration stepper */}
        <section>
          <label className="mb-1.5 block text-xs font-medium text-zinc-600">Duration</label>
          <div className="flex items-center gap-3">
            <button
              onClick={() => onChange({ duration: Math.max(1, data.duration - 1) })}
              className="flex h-8 w-8 items-center justify-center rounded-md border border-zinc-200 text-zinc-600 hover:bg-zinc-50 transition-colors font-medium"
            >
              −
            </button>
            <span className="text-sm font-semibold text-zinc-800 w-8 text-center">{data.duration}s</span>
            <button
              onClick={() => onChange({ duration: data.duration + 1 })}
              className="flex h-8 w-8 items-center justify-center rounded-md border border-zinc-200 text-zinc-600 hover:bg-zinc-50 transition-colors font-medium"
            >
              +
            </button>
          </div>
        </section>

        {/* Regenerate */}
        {onRegenerate && (
          <section>
            <label className="mb-1.5 block text-xs font-medium text-zinc-600">Regenerate Frame</label>
            <Textarea
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              rows={2}
              className="resize-none text-sm mb-2"
              placeholder="Describe what the frame should look like..."
            />
            <Button
              onClick={handleRegenerate}
              disabled={isRegenerating || !prompt.trim()}
              size="sm"
              className="w-full gap-2"
            >
              <ArrowCounterClockwise size={14} className={isRegenerating ? "animate-spin" : ""} />
              {isRegenerating ? "Generating..." : "Regenerate Frame"}
            </Button>
          </section>
        )}

        {/* Image history */}
        {data.imageHistory && data.imageHistory.length > 0 && (
          <section>
            <label className="mb-1.5 block text-xs font-medium text-zinc-600">Previous Frames</label>
            <div className="flex gap-2">
              {data.imageHistory.slice(-3).map((url, i) => {
                const key = `${historyId}-history-${i}`
                return (
                  <button
                    key={key}
                    onClick={() => restoreFromHistory(url)}
                    className="h-16 w-16 overflow-hidden rounded-md border border-zinc-200 hover:border-blue-400 transition-colors"
                    title="Restore this frame"
                  >
                    <img src={url} alt={`History ${i + 1}`} className="h-full w-full object-cover" />
                  </button>
                )
              })}
            </div>
          </section>
        )}

        {/* Notes */}
        <section>
          <label className="mb-1.5 block text-xs font-medium text-zinc-600">Notes</label>
          <Textarea
            value={data.notes ?? ""}
            onChange={(e) => onChange({ notes: e.target.value })}
            rows={3}
            className="resize-none text-sm"
            placeholder="Director notes, props, lighting cues..."
          />
        </section>
      </div>
    </div>
  )
}
```

### Step 4: Create `components/storyboard/storyboard-canvas.tsx`

```typescript
"use client"

import { ShotPanel } from "@/components/storyboard/shot-panel"
import { StoryboardNode } from "@/components/storyboard/storyboard-node"
import type { ShotData, StoryboardCanvasProps, StoryboardEdge, StoryboardShot } from "@src/lib/storyboard/types"
import { Export, Link, VideoCamera } from "@phosphor-icons/react"
import {
  Background,
  Controls,
  ReactFlow,
  SmoothStepEdge,
  useEdgesState,
  useNodesState,
} from "@xyflow/react"
import "@xyflow/react/dist/style.css"
import { useCallback, useId, useEffect, useState } from "react"

const NODE_TYPES = { shot: StoryboardNode }
const EDGE_TYPES = { smoothstep: SmoothStepEdge }
const NODE_WIDTH = 300
const NODE_GAP = 40

function buildNodes(shots: ShotData[], idPrefix: string): StoryboardShot[] {
  return shots.map((shot, i) => ({
    id: `${idPrefix}-${i}`,
    type: "shot" as const,
    position: { x: i * (NODE_WIDTH + NODE_GAP), y: 0 },
    data: shot,
    dragHandle: ".storyboard-node-drag",
  }))
}

function buildEdges(nodes: StoryboardShot[], idPrefix: string): StoryboardEdge[] {
  return nodes.slice(0, -1).map((node, i) => ({
    id: `${idPrefix}-edge-${i}`,
    source: node.id,
    target: nodes[i + 1].id,
    type: "smoothstep",
    animated: false,
  }))
}

export function StoryboardCanvas({
  shots,
  onShotsChange,
  onRegenerateShot,
  onExportPdf,
  onShareLink,
  className,
}: StoryboardCanvasProps) {
  const idPrefix = useId()
  const initialNodes = buildNodes(shots, idPrefix)
  const initialEdges = buildEdges(initialNodes, idPrefix)

  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes)
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges)
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null)

  useEffect(() => {
    const updated = buildNodes(shots, idPrefix)
    setNodes(updated)
    setEdges(buildEdges(updated, idPrefix))
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shots])

  const selectedNode = nodes.find((n) => n.id === selectedNodeId)
  const selectedData = selectedNode ? (selectedNode.data as unknown as ShotData) : null

  const handleNodeClick = useCallback((_: React.MouseEvent, node: StoryboardShot) => {
    setSelectedNodeId((prev) => (prev === node.id ? null : node.id))
  }, [])

  const handlePanelChange = useCallback(
    (updated: Partial<ShotData>) => {
      if (!selectedNodeId) return
      setNodes((prev) =>
        prev.map((n) =>
          n.id === selectedNodeId
            ? { ...n, data: { ...(n.data as unknown as ShotData), ...updated } }
            : n,
        ),
      )
      if (onShotsChange) {
        const newShots = nodes.map((n) =>
          n.id === selectedNodeId
            ? { ...(n.data as unknown as ShotData), ...updated }
            : (n.data as unknown as ShotData),
        )
        onShotsChange(newShots)
      }
    },
    [selectedNodeId, nodes, onShotsChange, setNodes],
  )

  const handleNodesChangeWithCallback = useCallback(
    (changes: Parameters<typeof onNodesChange>[0]) => {
      onNodesChange(changes)
      if (onShotsChange) {
        const hasPositionChange = changes.some((c) => c.type === "position" && !c.dragging)
        if (hasPositionChange) {
          const sorted = [...nodes].sort((a, b) => a.position.x - b.position.x)
          onShotsChange(sorted.map((n) => n.data as unknown as ShotData))
        }
      }
    },
    [onNodesChange, onShotsChange, nodes],
  )

  return (
    <div className={["flex h-full w-full overflow-hidden rounded-xl border border-zinc-200 bg-zinc-50", className].filter(Boolean).join(" ")}>
      {/* Canvas area */}
      <div className="relative flex flex-1 flex-col">
        {/* Toolbar */}
        <div className="flex items-center justify-between border-b border-zinc-200 bg-white px-4 py-2.5">
          <div className="flex items-center gap-2">
            <VideoCamera size={18} className="text-zinc-500" />
            <span className="text-sm font-semibold text-zinc-800">Storyboard</span>
            <span className="rounded-full bg-zinc-100 px-2 py-0.5 text-xs font-medium text-zinc-500">
              {shots.length} shot{shots.length !== 1 ? "s" : ""}
            </span>
          </div>
          <div className="flex items-center gap-2">
            {onShareLink && (
              <button
                onClick={onShareLink}
                className="flex items-center gap-1.5 rounded-md border border-zinc-200 bg-white px-3 py-1.5 text-xs font-medium text-zinc-600 hover:bg-zinc-50 transition-colors"
              >
                <Link size={13} />
                Share Link
              </button>
            )}
            {onExportPdf && (
              <button
                onClick={onExportPdf}
                className="flex items-center gap-1.5 rounded-md bg-zinc-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-zinc-700 transition-colors"
              >
                <Export size={13} />
                Export PDF
              </button>
            )}
          </div>
        </div>

        {/* React Flow */}
        <div className="flex-1">
          <ReactFlow
            nodes={nodes}
            edges={edges}
            onNodesChange={handleNodesChangeWithCallback}
            onEdgesChange={onEdgesChange}
            onNodeClick={handleNodeClick}
            nodeTypes={NODE_TYPES}
            edgeTypes={EDGE_TYPES}
            fitView
            fitViewOptions={{ padding: 0.3 }}
            proOptions={{ hideAttribution: true }}
          >
            <Background color="#e4e4e7" gap={20} />
            <Controls showInteractive={false} />
          </ReactFlow>
        </div>
      </div>

      {/* Side panel */}
      {selectedNodeId && selectedData && (
        <ShotPanel
          shotId={selectedNodeId}
          data={selectedData}
          onClose={() => setSelectedNodeId(null)}
          onChange={handlePanelChange}
          onRegenerate={onRegenerateShot}
        />
      )}
    </div>
  )
}
```

## Usage

```typescript
import { StoryboardCanvas } from "@/components/storyboard/storyboard-canvas"
import type { ShotData } from "@src/lib/storyboard/types"
import { useState } from "react"

const INITIAL_SHOTS: ShotData[] = [
  { shotNumber: 1, description: "Hero walks through door", cameraAngle: "Wide shot", duration: 3, status: "pending" },
  { shotNumber: 2, description: "Close-up on face", cameraAngle: "Close-up", duration: 2, status: "done", imageUrl: "/frames/shot2.jpg" },
  { shotNumber: 3, description: "Over-shoulder dialogue", cameraAngle: "Over-the-shoulder", duration: 5, status: "pending" },
  { shotNumber: 4, description: "Reaction cut", cameraAngle: "Medium shot", duration: 2, status: "pending" },
  { shotNumber: 5, description: "Wide establishing shot", cameraAngle: "Wide shot", duration: 4, status: "pending" },
]

export default function StoryboardPage() {
  const [shots, setShots] = useState<ShotData[]>(INITIAL_SHOTS)

  async function handleRegenerate(shotId: string, prompt: string): Promise<string> {
    const res = await fetch("/api/generate-frame", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ shotId, prompt }),
    })
    const { imageUrl } = await res.json() as { imageUrl: string }
    return imageUrl
  }

  return (
    <div className="h-screen p-6">
      <StoryboardCanvas
        shots={shots}
        onShotsChange={setShots}
        onRegenerateShot={handleRegenerate}
        onExportPdf={() => window.print()}
        onShareLink={() => console.log("open share dialog")}
      />
    </div>
  )
}
```

## Acceptance Criteria

- Canvas renders 5 shots as connected nodes laid out left to right
- Each node shows shot number badge, status dot, frame image or placeholder, description, duration, and camera angle
- Clicking a node opens `ShotPanel` on the right side with that shot's data
- Clicking the same node again or pressing the close button closes the panel
- Duration stepper in `ShotPanel` enforces a minimum of 1 second
- Regenerate button is disabled while generation is in progress and shows a spinner
- Image history thumbnails appear after regeneration; clicking one restores that frame
- Dragging nodes fires `onShotsChange` with the re-ordered shots array
- "Export PDF" button calls `onExportPdf` prop
- "Share Link" button calls `onShareLink` prop
- `@xyflow/react` stylesheet is imported in the canvas component
- `tsc --noEmit` passes with no errors
- `bun run build` succeeds
