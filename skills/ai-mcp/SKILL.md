---
name: ai-mcp
description: Config-driven MCP (Model Context Protocol) server integration. Add external tool servers (GitHub, Brave Search, databases, etc.) by editing one config file — tools are auto-discovered, prefixed, and merged into the chat. Use this skill when the user says "add MCP", "connect MCP servers", "add external tools", or "setup ai-mcp".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-13
updated: 2026-02-13
dependencies: [ai-chat, ai-tools]
---

# AI MCP

Config-driven MCP server integration for the AI chat system. Users add MCP servers by editing **one config file** (`src/lib/ai/mcp/servers.ts`). Tools from all configured servers are automatically discovered, prefixed to avoid collisions, merged into the chat, and described in the system prompt.

## Prerequisites

- `ai-chat` skill applied (provides `route.ts` with comment slots)
- `ai-tools` skill applied (provides tool infrastructure)
- `ai-core` skill applied (provides `getModel()`)

## Installation

```bash
bun add @ai-sdk/mcp
```

## What Gets Created

```
src/
└── lib/
    └── ai/
        └── mcp/
            ├── servers.ts    # Server config array — edit this to add servers
            └── client.ts     # connectMCPServers() factory
```

Plus modification to:

```
src/app/api/ai/chat/route.ts    # MODIFIED — connect MCP, merge tools, close clients
```

## Comment Slots

- **route.ts**: `// [ai-mcp]: merge MCP server tools` — merges auto-discovered MCP tools into the tools object
- **route.ts**: `// [ai-mcp]: append MCP tool descriptions` — adds MCP server descriptions to the system prompt
- **route.ts**: `// [ai-mcp]: close MCP server connections` — closes MCP clients in `onFinish`

## Setup Steps

### Step 1: Create `src/lib/ai/mcp/servers.ts`

```typescript
type MCPTransportConfig = {
  type: "sse" | "http";
  url: string;
  headers?: Record<string, string>;
};

export type MCPServerConfig = {
  /** Unique name for this server (used as tool prefix) */
  name: string;
  /** Human-readable description shown to the AI in the system prompt */
  description: string;
  /** Transport configuration — use "http" for modern servers, "sse" for legacy */
  transport: MCPTransportConfig;
  /** Set to false to temporarily disable without removing config. Defaults to true. */
  enabled?: boolean;
  /** Custom tool name prefix. Defaults to the server name. Set to "" to disable prefixing. */
  toolPrefix?: string;
};

/**
 * Add your MCP servers here. Each entry auto-discovers tools from the server
 * and merges them into the AI chat. Tool names are prefixed with the server
 * name (e.g. "github_create_issue") to prevent collisions.
 *
 * Example:
 *
 * {
 *   name: "brave-search",
 *   description: "Web search via Brave Search API",
 *   transport: {
 *     type: "http",
 *     url: "https://mcp.brave.com/sse",
 *     headers: { Authorization: `Bearer ${process.env.BRAVE_API_KEY}` },
 *   },
 * },
 * {
 *   name: "github",
 *   description: "GitHub repository management — issues, PRs, code search",
 *   transport: {
 *     type: "http",
 *     url: "https://mcp.github.com/sse",
 *     headers: { Authorization: `Bearer ${process.env.GITHUB_TOKEN}` },
 *   },
 * },
 */
export const mcpServers: MCPServerConfig[] = [
  // Add your MCP server configs here
];
```

### Step 2: Create `src/lib/ai/mcp/client.ts`

```typescript
import { createMCPClient } from "@ai-sdk/mcp";
import type { ToolSet } from "ai";
import type { MCPServerConfig } from "./servers";

type MCPConnection = {
  tools: ToolSet;
  systemPrompt: string;
  close: () => Promise<void>;
};

type MCPClient = Awaited<ReturnType<typeof createMCPClient>>;

function prefixTools(tools: ToolSet, prefix: string): ToolSet {
  if (!prefix) return tools;
  const prefixed: ToolSet = {};
  for (const [name, tool] of Object.entries(tools)) {
    prefixed[`${prefix}_${name}`] = tool;
  }
  return prefixed;
}

export async function connectMCPServers(
  servers: MCPServerConfig[],
): Promise<MCPConnection> {
  const enabledServers = servers.filter((s) => s.enabled !== false);

  if (enabledServers.length === 0) {
    return { tools: {}, systemPrompt: "", close: async () => {} };
  }

  const clients: MCPClient[] = [];
  const allTools: ToolSet = {};
  const descriptions: string[] = [];

  const results = await Promise.allSettled(
    enabledServers.map(async (server) => {
      const client = await createMCPClient({
        transport: server.transport,
      });
      const tools = await client.tools();
      return { server, client, tools };
    }),
  );

  for (const result of results) {
    if (result.status === "fulfilled") {
      const { server, client, tools } = result.value;
      clients.push(client);
      const prefix =
        server.toolPrefix !== undefined ? server.toolPrefix : server.name;
      const prefixed = prefixTools(tools, prefix);
      Object.assign(allTools, prefixed);
      const toolNames = Object.keys(prefixed);
      if (toolNames.length > 0) {
        descriptions.push(
          `- **${server.name}**: ${server.description} (tools: ${toolNames.join(", ")})`,
        );
      }
    } else {
      const serverName =
        enabledServers[results.indexOf(result)]?.name ?? "unknown";
      console.warn(
        `[ai-mcp] Failed to connect to "${serverName}":`,
        result.reason,
      );
    }
  }

  const systemPrompt =
    descriptions.length > 0
      ? `## MCP Tools\nThe following external tool servers are available:\n${descriptions.join("\n")}`
      : "";

  return {
    tools: allTools,
    systemPrompt,
    close: async () => {
      await Promise.allSettled(clients.map((c) => c.close()));
    },
  };
}
```

### Step 3: Modify `src/app/api/ai/chat/route.ts`

Add the MCP imports at the top of the file.

Find this:

```typescript
import { allTools } from "@src/lib/ai/tools";
```

Replace with:

```typescript
import { allTools } from "@src/lib/ai/tools";
import { connectMCPServers } from "@src/lib/ai/mcp/client";
import { mcpServers } from "@src/lib/ai/mcp/servers";
```

Next, connect MCP servers and merge their tools. Find this:

```typescript
  // --- TOOLS (ai-tools registers, ai-artifacts/tasks/memory/gen-ui add tools) ---
  const tools: ToolSet = {};
```

Replace with:

```typescript
  // --- MCP (connect external tool servers) ---
  const mcp = await connectMCPServers(mcpServers);

  // --- TOOLS (ai-tools registers, ai-artifacts/tasks/memory/gen-ui add tools) ---
  const tools: ToolSet = {};
```

Next, merge MCP tools after existing tools. Find this:

```typescript
  const memoryTools = createMemoryTools(userId);
  Object.assign(tools, memoryTools);
```

Replace with:

```typescript
  const memoryTools = createMemoryTools(userId);
  Object.assign(tools, memoryTools);
  // [ai-mcp]: merge MCP server tools
  Object.assign(tools, mcp.tools);
```

Next, append MCP tool descriptions to the system prompt. Find this:

```typescript
  // --- PROVIDER OPTIONS (ai-reasoning adds thinking config) ---
```

Replace with:

```typescript
  // [ai-mcp]: append MCP tool descriptions
  if (mcp.systemPrompt) {
    systemParts.push(mcp.systemPrompt);
  }

  // --- PROVIDER OPTIONS (ai-reasoning adds thinking config) ---
```

Finally, close MCP clients in `onFinish`. Find this:

```typescript
    async onFinish({ text }) {
      // Persist the assistant's response
```

Replace with:

```typescript
    async onFinish({ text }) {
      // [ai-mcp]: close MCP server connections
      await mcp.close();

      // Persist the assistant's response
```

## Usage

### Adding an MCP Server

1. Add any required API keys to `.env.local`:

   ```
   BRAVE_API_KEY=your-key-here
   ```

2. Add a server config to the `mcpServers` array in `src/lib/ai/mcp/servers.ts`:

   ```typescript
   export const mcpServers: MCPServerConfig[] = [
     {
       name: "brave-search",
       description: "Web search via Brave Search API",
       transport: {
         type: "http",
         url: "https://mcp.brave.com/sse",
         headers: { Authorization: `Bearer ${process.env.BRAVE_API_KEY}` },
       },
     },
   ];
   ```

3. Restart the dev server. The AI can now use all tools from that server, prefixed as `brave-search_web_search`, etc.

### Disabling a Server

Set `enabled: false` to temporarily disable a server without removing its config:

```typescript
{
  name: "github",
  description: "GitHub repo management",
  transport: { type: "http", url: "https://mcp.github.com/sse" },
  enabled: false, // temporarily disabled
},
```

### Custom Tool Prefix

By default, tool names are prefixed with the server name. Override with `toolPrefix`:

```typescript
{
  name: "brave-search",
  description: "Web search",
  transport: { type: "http", url: "https://mcp.brave.com/sse" },
  toolPrefix: "search", // tools become search_web_search instead of brave-search_web_search
},
```

Set `toolPrefix: ""` to disable prefixing entirely (only safe when there are no name collisions).

## Acceptance Criteria

- Empty `mcpServers[]` array: app works identically, no errors, zero overhead
- Invalid server URL: warning logged to console, other tools still work, chat functions normally
- Tool names are prefixed correctly (e.g. `github_create_issue`, `brave-search_web_search`)
- MCP tool descriptions appear in the system prompt under `## MCP Tools`
- MCP clients are closed after each request via `onFinish`
- `tsc --noEmit` passes with no errors
- `bun run build` succeeds
