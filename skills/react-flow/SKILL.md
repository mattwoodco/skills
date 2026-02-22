---
name: react-flow
description: Setup react-flow for node-based diagrams and flowcharts. Use this skill when the user says "setup react-flow", "add flow diagram", "node editor", "flowchart builder", or "visual workflow".
author: "@mattwoodco"
version: 1.3.0
created: 2026-01-12
updated: 2026-02-19
---

# React Flow Skill

Node-based diagram and flowchart library for React 19 and Next.js App Router.

## Installation

```bash
bun add @xyflow/react
```

## Next.js App Router Setup

React Flow requires client-side rendering. Create a wrapper component.

### 1. Flow Provider Wrapper

```tsx
// components/flow/flow-provider.tsx
"use client";

import { ReactFlowProvider } from "@xyflow/react";
import type { ReactNode } from "react";

type FlowProviderProps = {
  children: ReactNode;
};

export function FlowProvider({ children }: FlowProviderProps) {
  return <ReactFlowProvider>{children}</ReactFlowProvider>;
}
```

### 2. Basic Flow Component

```tsx
// components/flow/basic-flow.tsx
"use client";

import { useEffect, useState, useCallback, useMemo } from "react";
import {
  ReactFlow,
  Controls,
  Background,
  MiniMap,
  applyNodeChanges,
  applyEdgeChanges,
  addEdge,
  useReactFlow,
  type Node,
  type Edge,
  type NodeChange,
  type EdgeChange,
  type Connection,
  type OnConnect,
  type NodeTypes,
  type EdgeTypes,
} from "@xyflow/react";
import { useTheme } from "next-themes";
import "@xyflow/react/dist/style.css";

type BasicFlowProps = {
  initialNodes?: Node[];
  initialEdges?: Edge[];
  nodeTypes?: NodeTypes;
  edgeTypes?: EdgeTypes;
};

const defaultNodes: Node[] = [
  {
    id: "node-1",
    position: { x: 0, y: 0 },
    data: { label: "Start" },
  },
  {
    id: "node-2",
    position: { x: 0, y: 150 },
    data: { label: "Process" },
  },
  {
    id: "node-3",
    position: { x: 0, y: 300 },
    data: { label: "End" },
  },
];

const defaultEdges: Edge[] = [
  { id: "edge-1-2", source: "node-1", target: "node-2" },
  { id: "edge-2-3", source: "node-2", target: "node-3" },
];

export function BasicFlow({
  initialNodes = defaultNodes,
  initialEdges = defaultEdges,
  nodeTypes,
  edgeTypes,
}: BasicFlowProps) {
  const [nodes, setNodes] = useState<Node[]>(initialNodes);
  const [edges, setEdges] = useState<Edge[]>(initialEdges);

  // Dark mode: sync with next-themes (mounted guard prevents SSR mismatch)
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  // Re-center flow on window resize
  const { fitView } = useReactFlow();
  useEffect(() => {
    let rafId: number;
    const handleResize = () => {
      cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(() => {
        fitView({ padding: 0.4 });
      });
    };
    window.addEventListener("resize", handleResize);
    return () => {
      window.removeEventListener("resize", handleResize);
      cancelAnimationFrame(rafId);
    };
  }, [fitView]);

  const onNodesChange = useCallback(
    (changes: NodeChange[]) =>
      setNodes((nds) => applyNodeChanges(changes, nds)),
    []
  );

  const onEdgesChange = useCallback(
    (changes: EdgeChange[]) =>
      setEdges((eds) => applyEdgeChanges(changes, eds)),
    []
  );

  const onConnect: OnConnect = useCallback(
    (connection: Connection) => setEdges((eds) => addEdge(connection, eds)),
    []
  );

  const defaultEdgeOptions = useMemo(
    () => ({
      animated: true,
      type: "smoothstep",
    }),
    []
  );

  return (
    <div className="h-[600px] w-full">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        defaultEdgeOptions={defaultEdgeOptions}
        fitView
        fitViewOptions={{ padding: 0.4, maxZoom: 1.2 }}
        proOptions={{ hideAttribution: true }}
        colorMode={mounted && resolvedTheme === "dark" ? "dark" : mounted && resolvedTheme === "light" ? "light" : "dark"}
      >
        <Controls />
        <MiniMap className="hidden md:block" />
        <Background gap={16} size={1} />
      </ReactFlow>
    </div>
  );
}
```

### 3. Usage in Page

```tsx
// app/flow/page.tsx
import { FlowProvider } from "@/components/flow/flow-provider";
import { BasicFlow } from "@/components/flow/basic-flow";

export default function FlowPage() {
  return (
    <FlowProvider>
      <div className="p-4">
        <h1 className="text-2xl font-bold mb-4">Flow Editor</h1>
        <BasicFlow />
      </div>
    </FlowProvider>
  );
}
```

## Core Concepts

### Nodes

Nodes are the building blocks of a flow. Each node requires:

- `id`: Unique identifier (string)
- `position`: `{ x: number, y: number }` coordinates
- `data`: Object containing node data (e.g., `{ label: "My Node" }`)
- `type`: Optional node type (default, input, output, or custom)

```tsx
const nodes: Node[] = [
  {
    id: "1",
    type: "input",
    position: { x: 100, y: 100 },
    data: { label: "Input Node" },
  },
  {
    id: "2",
    type: "default",
    position: { x: 100, y: 200 },
    data: { label: "Default Node" },
  },
  {
    id: "3",
    type: "output",
    position: { x: 100, y: 300 },
    data: { label: "Output Node" },
  },
];
```

### Edges

Edges connect nodes together:

- `id`: Unique identifier
- `source`: Source node ID
- `target`: Target node ID
- `sourceHandle`: Optional handle ID on source
- `targetHandle`: Optional handle ID on target
- `type`: Edge type (default, straight, step, smoothstep, bezier)
- `animated`: Boolean for animation
- `label`: Optional edge label

```tsx
const edges: Edge[] = [
  {
    id: "e1-2",
    source: "1",
    target: "2",
    type: "smoothstep",
    animated: true,
    label: "connects to",
  },
];
```

### Handles

Handles are connection points on nodes:

```tsx
import { Handle, Position, type Node, type NodeProps } from "@xyflow/react";

type LabelNodeData = { label: string };
type LabelNode = Node<LabelNodeData>;

function CustomNode({ data }: NodeProps<LabelNode>) {
  return (
    <div className="px-4 py-2 bg-white border rounded shadow">
      <Handle type="target" position={Position.Top} />
      <div>{data.label}</div>
      <Handle type="source" position={Position.Bottom} />
    </div>
  );
}
```

**Important**: Always provide a generic type parameter to `NodeProps`. The default `NodeProps` types `data` as `Record<string, unknown>`, so `data.label` will be `unknown` and cause TypeScript errors when rendered in JSX.

Handle positions: `Position.Top`, `Position.Right`, `Position.Bottom`, `Position.Left`

### Controls

Built-in controls for zoom and fit:

```tsx
import { Controls } from "@xyflow/react";

<ReactFlow nodes={nodes} edges={edges}>
  <Controls />
</ReactFlow>;
```

## Custom Nodes

Define custom nodes outside the component to prevent re-renders.

```tsx
// components/flow/custom-nodes/card-node.tsx
"use client";

import { memo } from "react";
import { Handle, Position, type NodeProps, type Node } from "@xyflow/react";

type CardNodeData = {
  title: string;
  description: string;
  status: "pending" | "active" | "complete";
};

type CardNode = Node<CardNodeData, "card">;

function CardNodeComponent({ data, selected }: NodeProps<CardNode>) {
  const statusColors = {
    pending: "bg-yellow-100 border-yellow-400",
    active: "bg-blue-100 border-blue-400",
    complete: "bg-green-100 border-green-400",
  };

  return (
    <div
      className={`
        px-4 py-3 rounded-lg border-2 min-w-[200px]
        ${statusColors[data.status]}
        ${selected ? "ring-2 ring-blue-500" : ""}
      `}
    >
      <Handle type="target" position={Position.Top} className="!bg-gray-500" />
      <div className="font-semibold text-sm">{data.title}</div>
      <div className="text-xs text-gray-600 mt-1">{data.description}</div>
      <div className="text-xs text-gray-400 mt-2 capitalize">{data.status}</div>
      <Handle
        type="source"
        position={Position.Bottom}
        className="!bg-gray-500"
      />
    </div>
  );
}

export const CardNode = memo(CardNodeComponent);
```

### Registering Custom Nodes

```tsx
// components/flow/node-types.ts
import type { NodeTypes } from "@xyflow/react";
import { CardNode } from "./custom-nodes/card-node";
import { TextUpdaterNode } from "./custom-nodes/text-updater-node";

export const nodeTypes: NodeTypes = {
  card: CardNode,
  textUpdater: TextUpdaterNode,
};
```

### Using Custom Nodes

```tsx
import { nodeTypes } from "./node-types";

const nodes: Node[] = [
  {
    id: "card-1",
    type: "card",
    position: { x: 100, y: 100 },
    data: {
      title: "Task 1",
      description: "Complete the setup",
      status: "active",
    },
  },
];

<ReactFlow nodes={nodes} edges={edges} nodeTypes={nodeTypes} />;
```

## Custom Edges

Define custom edges to render labels, buttons, or animations along connections.

```tsx
// components/flow/custom-edges/labeled-edge.tsx
"use client";

import { memo } from "react";
import {
  BaseEdge,
  EdgeLabelRenderer,
  getSmoothStepPath,
  type EdgeProps,
  type Edge,
} from "@xyflow/react";

type LabeledEdgeData = { label: string };
type LabeledEdge = Edge<LabeledEdgeData, "labeled">;

function LabeledEdgeComponent({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  data,
  style,
  markerEnd,
}: EdgeProps<LabeledEdge>) {
  const [edgePath, labelX, labelY] = getSmoothStepPath({
    sourceX,
    sourceY,
    sourcePosition,
    targetX,
    targetY,
    targetPosition,
  });

  return (
    <>
      <BaseEdge id={id} path={edgePath} style={style} markerEnd={markerEnd} />
      <EdgeLabelRenderer>
        <div
          className="nodrag nopan pointer-events-auto absolute rounded bg-background px-2 py-1 text-xs border shadow-sm"
          style={{
            transform: `translate(-50%, -50%) translate(${labelX}px,${labelY}px)`,
          }}
        >
          {data?.label}
        </div>
      </EdgeLabelRenderer>
    </>
  );
}

export const LabeledEdge = memo(LabeledEdgeComponent);
```

### Registering Custom Edges

```tsx
// components/flow/edge-types.ts
import type { EdgeTypes } from "@xyflow/react";
import { LabeledEdge } from "./custom-edges/labeled-edge";

export const edgeTypes: EdgeTypes = {
  labeled: LabeledEdge,
};
```

### Using Custom Edges

```tsx
import { edgeTypes } from "./edge-types";

const edges: Edge[] = [
  {
    id: "e1-2",
    source: "1",
    target: "2",
    type: "labeled",
    data: { label: "next step" },
  },
];

<ReactFlow nodes={nodes} edges={edges} edgeTypes={edgeTypes} />;
```

## Hooks

### useReactFlow

Access flow instance methods. Must be used within `ReactFlowProvider`.

```tsx
import { useReactFlow } from "@xyflow/react";

function FlowControls() {
  const reactFlow = useReactFlow();

  const handleFitView = () => {
    reactFlow.fitView({ padding: 0.2, duration: 200 });
  };

  const handleZoomIn = () => {
    reactFlow.zoomIn({ duration: 200 });
  };

  const handleZoomOut = () => {
    reactFlow.zoomOut({ duration: 200 });
  };

  const handleGetState = () => {
    const nodes = reactFlow.getNodes();
    const edges = reactFlow.getEdges();
    console.log({ nodes, edges });
  };

  const handleAddNode = () => {
    const newNode = {
      id: `node-${Date.now()}`,
      position: { x: Math.random() * 400, y: Math.random() * 400 },
      data: { label: "New Node" },
    };
    reactFlow.addNodes(newNode);
  };

  return (
    <div className="flex gap-2">
      <button onClick={handleFitView}>Fit View</button>
      <button onClick={handleZoomIn}>Zoom In</button>
      <button onClick={handleZoomOut}>Zoom Out</button>
      <button onClick={handleAddNode}>Add Node</button>
    </div>
  );
}
```

### useNodes and useEdges

Subscribe to node/edge state changes. Use sparingly as they cause re-renders on every change.

```tsx
import { useNodes, useEdges } from "@xyflow/react";

function NodeCounter() {
  const nodes = useNodes();
  const edges = useEdges();

  return (
    <div>
      Nodes: {nodes.length}, Edges: {edges.length}
    </div>
  );
}
```

### useNodesState and useEdgesState

Convenience hooks for managing state (good for prototyping):

```tsx
import { useNodesState, useEdgesState } from "@xyflow/react";

const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);
```

### useViewport

Get current viewport state:

```tsx
import { useViewport } from "@xyflow/react";

function ViewportInfo() {
  const { x, y, zoom } = useViewport();
  return (
    <div>
      x: {x.toFixed(0)}, y: {y.toFixed(0)}, zoom: {zoom.toFixed(2)}
    </div>
  );
}
```

### useOnSelectionChange

Listen for selection changes:

```tsx
import { useOnSelectionChange } from "@xyflow/react";

function SelectionListener() {
  useOnSelectionChange({
    onChange: ({ nodes, edges }) => {
      console.log("Selected nodes:", nodes);
      console.log("Selected edges:", edges);
    },
  });
  return null;
}
```

## Best Practices

### Performance with React 19

1. **Wrap custom nodes in `memo`**:

```tsx
import { memo } from "react";
import type { Node, NodeProps } from "@xyflow/react";

type MyNodeData = { label: string };
type MyNodeType = Node<MyNodeData>;

const MyNodeComponent = ({ data }: NodeProps<MyNodeType>) => <div>{data.label}</div>;
export const MyNode = memo(MyNodeComponent);
```

2. **Define `nodeTypes` outside components**:

```tsx
// GOOD: Outside component
const nodeTypes = { custom: CustomNode };

// BAD: Inside component (causes re-renders)
function Flow() {
  const nodeTypes = { custom: CustomNode }; // Creates new object each render
}
```

3. **Memoize callbacks and objects**:

```tsx
const onNodesChange = useCallback(
  (changes: NodeChange[]) =>
    setNodes((nds) => applyNodeChanges(changes, nds)),
  []
);

const defaultEdgeOptions = useMemo(
  () => ({ animated: true, type: "smoothstep" }),
  []
);
```

4. **Use `useReactFlow` instead of `useNodes`/`useEdges`** when you only need to query state occasionally (avoids re-renders):

```tsx
// Better for occasional queries
const reactFlow = useReactFlow();
const handleExport = () => {
  const nodes = reactFlow.getNodes();
  // export logic
};
```

5. **Use `nodrag` class on interactive elements**:

```tsx
<input className="nodrag" type="text" />
```

### SSR Considerations for Next.js

React Flow uses browser APIs and cannot be server-rendered. Always:

1. Use `"use client"` directive on flow components
2. Dynamically import if needed:

```tsx
import dynamic from "next/dynamic";

const FlowEditor = dynamic(
  () => import("@/components/flow/flow-editor").then((mod) => mod.FlowEditor),
  { ssr: false }
);
```

3. Wrap in a client component boundary before using in server components

## Common Patterns

### Preventing Default Drag on Inputs

```tsx
<input
  className="nodrag nopan"
  onChange={(e) => updateNodeData(e.target.value)}
/>
```

### Connecting to Specific Handles

```tsx
// Node with multiple handles
<Handle type="source" position={Position.Right} id="output-1" />
<Handle type="source" position={Position.Right} id="output-2" style={{ top: 30 }} />

// Edge connecting to specific handle
const edges = [
  { id: 'e1', source: 'node-1', target: 'node-2', sourceHandle: 'output-1' }
];
```

### Saving and Restoring Flow State

```tsx
function FlowWithPersistence() {
  const reactFlow = useReactFlow();

  const handleSave = () => {
    const flow = reactFlow.toObject();
    localStorage.setItem("flow", JSON.stringify(flow));
  };

  const handleRestore = () => {
    const saved = localStorage.getItem("flow");
    if (saved) {
      const flow = JSON.parse(saved);
      reactFlow.setNodes(flow.nodes);
      reactFlow.setEdges(flow.edges);
      reactFlow.setViewport(flow.viewport);
    }
  };
}
```

## Required Configuration

These settings must **always** be applied to every `<ReactFlow>` instance:

### 1. Hide Attribution Watermark

```tsx
<ReactFlow proOptions={{ hideAttribution: true }} />
```

### 2. Dark Mode (next-themes Integration)

React Flow's `colorMode` prop must be synced with next-themes. The `resolvedTheme` is `undefined` during SSR, so use a mounted guard to prevent hydration mismatch:

```tsx
const { resolvedTheme } = useTheme();
const [mounted, setMounted] = useState(false);
useEffect(() => setMounted(true), []);

<ReactFlow
  colorMode={
    mounted && resolvedTheme === "dark" ? "dark"
    : mounted && resolvedTheme === "light" ? "light"
    : "dark"  // safe SSR default — avoids flash
  }
/>
```

**Why the mounted guard?** `useTheme()` returns `undefined` for `resolvedTheme` on the server. Without the guard, React Flow renders with `colorMode="light"` and then switches to `"dark"` on hydration, causing a flash and a `react-flow light` → `react-flow dark` class mismatch.

### 3. Fit View with Sane Defaults

```tsx
<ReactFlow
  fitView
  fitViewOptions={{ padding: 0.4, maxZoom: 1.2 }}
/>
```

Also re-center on window resize:

```tsx
const { fitView } = useReactFlow();

useEffect(() => {
  let rafId: number;
  const handleResize = () => {
    cancelAnimationFrame(rafId);
    rafId = requestAnimationFrame(() => {
      fitView({ padding: 0.4 });
    });
  };
  window.addEventListener("resize", handleResize);
  return () => {
    window.removeEventListener("resize", handleResize);
    cancelAnimationFrame(rafId);
  };
}, [fitView]);
```

### 4. Edge Label z-index for Popovers

Custom edge labels rendered via `EdgeLabelRenderer` sit in a shared layer. If an edge label contains a dropdown/popover, it will render **behind** nodes. Fix by dynamically setting z-index when the menu is open:

```tsx
<EdgeLabelRenderer>
  <div
    className="nodrag nopan pointer-events-auto absolute"
    style={{
      transform: `translate(-50%, -50%) translate(${labelX}px,${labelY}px)`,
      zIndex: menuOpen ? 1000 : 0,
    }}
  >
    {/* label pill + dropdown menu */}
  </div>
</EdgeLabelRenderer>
```

## Common Issues & Fixes

### TypeScript errors with generic Node types

When using typed node data like `Node<NodeData>[]`, ensure proper generic type handling:

```tsx
type NodeData = { label: string };

// Use generic type parameter on NodeChange
const onNodesChange = useCallback(
  (changes: NodeChange<Node<NodeData>>[]) =>
    setNodes((nds) => applyNodeChanges(changes, nds)),
  []
);

// Similarly for EdgeChange
const onEdgesChange = useCallback(
  (changes: EdgeChange<Edge>[]) =>
    setEdges((eds) => applyEdgeChanges(changes, eds)),
  []
);
```

### Flow canvas appears empty

1. **Check container height**: React Flow requires a parent with defined height
```tsx
// BAD - no height
<div><ReactFlow ... /></div>

// GOOD - explicit height
<div className="h-[600px]"><ReactFlow ... /></div>
<div className="h-screen"><ReactFlow ... /></div>
```

2. **Verify CSS import**:
```tsx
import "@xyflow/react/dist/style.css";
```

3. **Check initial viewport**: Use `fitView` prop or call `fitView()` after mount
```tsx
<ReactFlow fitView fitViewOptions={{ padding: 0.2 }} />
```

### next/dynamic with ssr: false error in Next.js 14+

If using `dynamic` import in a Server Component:
```
Error: `ssr: false` is not allowed with `next/dynamic` in Server Components
```

**Fix**: Add `"use client"` directive to the file using dynamic import:
```tsx
"use client";
import dynamic from "next/dynamic";

const FlowEditor = dynamic(
  () => import("@/components/flow/flow-editor").then((mod) => mod.FlowEditor),
  { ssr: false }
);
```

### Nodes not draggable in custom components

Add the `nodrag` class to interactive elements inside custom nodes:
```tsx
<input className="nodrag" type="text" />
<button className="nodrag">Click me</button>
```

### useReactFlow returns undefined

Ensure the component is wrapped in `ReactFlowProvider`:
```tsx
// The provider must wrap any component using useReactFlow
<ReactFlowProvider>
  <FlowCanvas /> {/* useReactFlow works here */}
</ReactFlowProvider>
```

### Build errors with React 19

React Flow v12+ is compatible with React 19. If you encounter issues:
1. Ensure you're using `@xyflow/react` (not the old `reactflow` package)
2. Update to the latest version: `bun add @xyflow/react@latest`

## Resources

- [React Flow Documentation](https://reactflow.dev)
- [React Flow Examples](https://github.com/xyflow/react-flow-example-apps)
- [API Reference](https://reactflow.dev/api-reference)
