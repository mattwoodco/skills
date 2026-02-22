# Dependency Resolution Reference

How to parse skill dependencies, topologically sort them, detect cycles, and group skills into sandbox families.

## Overview

Each saved skill has a YAML frontmatter field `dependencies:` listing other skill names that must be implemented first. This reference explains how to resolve these into a valid execution order.

## Parsing Dependencies

### Frontmatter Format

```yaml
---
name: ai-chat
description: ...
metadata:
  ...
  dependencies: [ai-core, auth, docker]
---
```

**Extract from each `skills/*/SKILL.md`:**

1. Read the file
2. Parse YAML between `---` markers
3. Extract `name` (string) and `dependencies` (array of strings, may be empty or absent)

### Dependency Map

Build an adjacency list representing the full dependency graph:

```
{
  "create-next":       [],
  "docker":            [],
  "env-config":        [],
  "add-shadcn":        ["create-next"],
  "add-pwa":           ["create-next"],
  "add-seo":           ["create-next"],
  "auth":              ["env-config", "docker"],
  "auth-dev":          ["auth"],
  "db":                ["docker", "env-config"],
  "storage":           ["docker", "env-config"],
  "email":             ["docker"],
  "ai-core":           ["env-config"],
  "storage-ui":        ["storage"],
  "media-bunny":       ["storage", "db"],
  "realtime":          ["auth", "env-config"],
  "image-editor":      ["add-shadcn"],
  "ai-chat":           ["ai-core", "auth", "docker"],
  "ai":                ["docker", "auth", "env-config"],
  "payments":          ["auth", "db", "env-config", "docker"],
  "queue":             ["db", "env-config", "auth"],
  "cms":               ["env-config", "docker", "auth", "storage", "storage-ui"],
  "ai-image-gen":      ["db", "env-config", "auth", "storage"],
  "ai-video-gen":      ["db", "env-config", "auth", "storage"],
  "ai-tools":          ["ai-chat"],
  "ai-reasoning":      ["ai-chat"],
  "ai-rag-ingest":     ["storage", "db", "auth", "docker"],
  "ai-memory":         ["ai-chat", "ai-tools"],
  "ai-tasks":          ["ai-tools"],
  "ai-artifacts":      ["ai-tools"],
  "ai-generative-ui":  ["ai-tools"],
  "ai-rag-vectors":    ["db", "ai-core", "ai-rag-ingest", "docker"],
  "ai-mcp":            ["ai-chat", "ai-tools"],
  "ai-rag-chat":       ["ai-chat", "ai-rag-vectors"],
  "ai-rag-viewer":     ["storage"],
  "ai-rag-app":        ["ai-rag-ingest", "ai-rag-vectors", "ai-rag-chat", "ai-rag-viewer", "auth"]
}
```

**Standalone skills** (no dependencies, no dependents in the Next.js family):

```
setup-lefthook, mcp-server, yt-dlp, lottie, react-flow,
react-three-fiber, e2e, env-from-1password, workflow
```

---

## Topological Sort — Kahn's Algorithm

Kahn's algorithm produces a valid ordering where every skill appears after all its dependencies.

### Algorithm

```
Input:  graph (adjacency list: skill → [dependencies])
Output: ordered list of skills, or error if cycle detected

1. Compute in-degree for each node:
   in_degree[skill] = number of skills that depend on it? NO —
   in_degree[skill] = number of dependencies skill has (edges pointing INTO it)

   For each skill S:
     in_degree[S] = len(graph[S])  # count of its dependencies

2. Initialize queue with all nodes where in_degree == 0:
   queue = [S for S in graph if in_degree[S] == 0]

3. While queue is not empty:
   a. Dequeue skill S
   b. Add S to result list
   c. For each skill T that depends on S (S is in T's dependency list):
      - Decrement in_degree[T] by 1
      - If in_degree[T] == 0, enqueue T

4. If result list length != total skill count:
   → Cycle detected! The skills NOT in the result list form the cycle.
   → Report error with the cycle members.

5. Return result list
```

### Building the Reverse Map

To efficiently find "which skills depend on S" (step 3c), build a reverse adjacency list:

```
reverse_graph = {}
for skill, deps in graph.items():
    for dep in deps:
        reverse_graph.setdefault(dep, []).append(skill)
```

Then in step 3c: iterate over `reverse_graph[S]`.

### Example Trace

Given skills: `create-next → add-shadcn → image-editor`

```
graph = {
  "create-next":  [],
  "add-shadcn":   ["create-next"],
  "image-editor": ["add-shadcn"]
}

in_degree = { "create-next": 0, "add-shadcn": 1, "image-editor": 1 }
queue = ["create-next"]

Step 1: process "create-next"
  → result: [create-next]
  → "add-shadcn" depends on "create-next" → in_degree["add-shadcn"] = 0 → enqueue
  queue = ["add-shadcn"]

Step 2: process "add-shadcn"
  → result: [create-next, add-shadcn]
  → "image-editor" depends on "add-shadcn" → in_degree["image-editor"] = 0 → enqueue
  queue = ["image-editor"]

Step 3: process "image-editor"
  → result: [create-next, add-shadcn, image-editor]
  queue = []

Done. Result length (3) == total (3). No cycle.
```

---

## Cycle Detection

If after Kahn's algorithm completes, `len(result) < len(graph)`:

1. The missing skills form one or more cycles
2. Identify them: `cycle_members = set(graph.keys()) - set(result)`
3. To find the exact cycle, pick any member and follow dependencies until you revisit a node
4. Report to user: "Circular dependency detected: A → B → C → A"
5. **Do NOT proceed** — ask user which dependency edge to remove

### Current Graph Status

The current skills dependency graph has **no cycles**. This has been verified. However, always re-check when new skills are added.

---

## Grouping into Sandbox Families

### Sandbox Grouping Strategy

Strict connected-component analysis reveals ~11 separate components (the `create-next` branch and the `docker/env-config` branch are technically disconnected in the graph). However, **for sandbox purposes** we merge them into a single Next.js sandbox because:

1. Most skills in both branches assume a Next.js project structure (`src/app/`, `src/lib/`, `tsconfig.json` paths, etc.)
2. Running them in isolation would miss composition issues (e.g., `auth` and `add-shadcn` both modify `layout.tsx`)
3. The goal is to test real-world layering where all skills coexist

**Grouping algorithm:**

```
1. Find connected components in the undirected dependency graph
2. Merge all components where ANY skill assumes Next.js into Group A
   (heuristic: has dependencies, or its code imports from "next/*")
3. Remaining truly standalone skills → Group B
```

### Current Groups

**Group A — Next.js Sandbox** (merged from 2 connected subgraphs + skills needing Next.js):

- **Subgraph 1** (`create-next` branch): create-next → add-shadcn, add-pwa, add-seo → image-editor
- **Subgraph 2** (`docker/env-config` branch): docker, env-config → auth, db, storage, ai-core, email → ... → ai-rag-app
- Merged because both subgraphs assume Next.js project structure

**Group B — Standalone** (skills with no dependencies that don't assume Next.js):

```
setup-lefthook, mcp-server, yt-dlp, lottie, react-flow,
react-three-fiber, e2e, env-from-1password, workflow
```

**Note:** Some standalone skills may implicitly require Next.js. If they fail in the standalone sandbox, move them to Group A (see SKILL.md edge cases section).

---

## Layer Assignment

Within each group, assign layers based on the longest path from a root:

```
layer[skill] = 0  if skill has no dependencies
layer[skill] = max(layer[dep] for dep in dependencies[skill]) + 1
```

This ensures all dependencies are in earlier layers.

### Current Layer Assignment (Group A)

| Layer | Skills |
|-------|--------|
| 0 | create-next, docker, env-config |
| 1 | add-shadcn, add-pwa, add-seo, auth, db, storage, email, ai-core |
| 2 | auth-dev, storage-ui, media-bunny, realtime, image-editor, ai-chat, ai, payments, queue, ai-image-gen, ai-video-gen, ai-rag-ingest, ai-rag-viewer |
| 3 | cms, ai-tools, ai-reasoning, ai-rag-vectors |
| 4 | ai-memory, ai-tasks, ai-artifacts, ai-generative-ui, ai-rag-chat, ai-mcp |
| 5 | ai-rag-app |

**Layer computation**: `layer[S] = max(layer[dep] for dep in deps[S]) + 1` (0 if no deps)

**Within a layer**, skills can be implemented in any order since they don't depend on each other.

---

## Handling Missing Dependencies

If a skill lists a dependency that doesn't exist in `skills/`:

1. Report to user: "Skill '<name>' lists dependency '<missing>' which is not found"
2. Options:
   - **Skip**: Skip the skill and all its dependents
   - **Ignore**: Proceed without that dependency (may cause errors)
   - **Create**: User provides the missing skill

Always present options and wait for user decision.

---

## Execution Order Summary

```
1. Parse all frontmatter → build graph
2. Topological sort → detect cycles
3. Group by connected components → assign sandbox type
4. Assign layers within each group
5. Execute: Layer 0 first, then Layer 1, etc.
6. Within each layer: any order (skills are independent)
```
