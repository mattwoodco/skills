---
name: spec-export
description: Structured spec-to-ticket export pipeline — maps document sections to project management tickets (Linear, GitHub Issues) via MCP, preserving hierarchy and acceptance criteria. Use this skill when the user says "export spec", "push to linear", "create tickets from spec", "spec to issues", or "export to jira".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
updated: 2026-02-18
dependencies: [ai-mcp, ai-tasks, structured-editor]
---

# Spec Export

Export pipeline that reads all sections from a structured-editor document, uses AI to map them into a ticket hierarchy (epic, stories, tasks), presents a preview for confirmation, and creates tickets in Linear or GitHub Issues via MCP. Created ticket IDs are stored back on document sections as external references.

The pipeline flow:

1. Read all sections from a structured-editor document
2. Use AI to map sections into a ticket hierarchy (epic -> stories -> tasks)
3. Present a preview of tickets to be created
4. User confirms -> tickets created via MCP tools (Linear or GitHub Issues)
5. Created ticket IDs stored back on sections as external references

## Prerequisites

- Next.js app with `src/` directory and App Router
- `ai-mcp` skill installed (provides MCP server connectivity for Linear/GitHub)
- `ai-tasks` skill installed (provides task management infrastructure)
- `structured-editor` skill installed (provides document + sections data model)
- `ai-core` skill installed (provides `getModel()`)
- Auth skill installed (provides `withAuth` from `@src/lib/auth-guard`)
- shadcn/ui initialized

## Installation

```bash
bunx shadcn@latest add dialog radio-group checkbox progress
```

No additional npm packages required. Uses `ai`, `zod`, and existing infrastructure from prerequisite skills.

## What Gets Created

```
src/
├── lib/
│   └── spec-export/
│       ├── types.ts               # ExportTarget, TicketPreview, ExportResult types
│       ├── mapper.ts              # Maps document sections -> ticket hierarchy using AI
│       └── targets/
│           ├── linear.ts          # Linear-specific ticket format + MCP tool calls
│           └── github.ts          # GitHub Issues format + MCP tool calls
├── app/
│   └── api/
│       └── documents/
│           └── [documentId]/
│               └── export/
│                   ├── preview/
│                   │   └── route.ts   # POST — generates ticket preview from document
│                   └── execute/
│                       └── route.ts   # POST — creates tickets in target system
└── components/
    └── editor/
        ├── export-dialog.tsx      # Modal: target picker -> preview -> confirm -> progress
        └── export-button.tsx      # "Export to..." button that opens export dialog
```

## What Gets Modified

```
src/components/editor/document-editor.tsx   # Add export button to toolbar
```

## Setup Steps

### Step 1: Create `src/lib/spec-export/types.ts`

```typescript
export type ExportTarget = "linear" | "github";

export type TicketType = "epic" | "story" | "task";

export type TicketPreview = {
  id: string;
  type: TicketType;
  title: string;
  description: string;
  labels: string[];
  priority: "urgent" | "high" | "medium" | "low" | "none";
  parentId: string | null;
  sourceSectionId: string;
  sourceSectionType: string;
  acceptanceCriteria: string[];
};

export type ExportResult = {
  ticketId: string;
  externalId: string;
  externalUrl: string;
  status: "created" | "failed";
  error?: string;
};

export type ExportPreviewResponse = {
  target: ExportTarget;
  documentTitle: string;
  tickets: TicketPreview[];
  totalCount: number;
};

export type ExportExecuteRequest = {
  target: ExportTarget;
  tickets: TicketPreview[];
};

export type ExportExecuteResponse = {
  results: ExportResult[];
  successCount: number;
  failCount: number;
};
```

### Step 2: Create `src/lib/spec-export/mapper.ts`

```typescript
import { generateObject } from "ai";
import { getModel } from "@src/lib/ai";
import { z } from "zod";
import type { TicketPreview } from "./types";

const ticketSchema = z.object({
  tickets: z.array(
    z.object({
      title: z.string(),
      type: z.enum(["epic", "story", "task"]),
      description: z.string(),
      labels: z.array(z.string()),
      priority: z.enum(["urgent", "high", "medium", "low", "none"]),
      parentIndex: z.number().nullable(),
      sourceSectionId: z.string(),
      sourceSectionType: z.string(),
      acceptanceCriteria: z.array(z.string()),
    })
  ),
});

type DocumentInput = {
  title: string;
  description: string | null;
};

type SectionInput = {
  id: string;
  type: string;
  title: string;
  content: unknown;
};

export async function mapDocumentToTickets(
  document: DocumentInput,
  sections: SectionInput[]
): Promise<TicketPreview[]> {
  const sectionSummary = sections
    .map(
      (s) =>
        `## ${s.title} (type: ${s.type}, id: ${s.id})\n${JSON.stringify(s.content, null, 2)}`
    )
    .join("\n\n");

  const result = await generateObject({
    model: getModel(),
    schema: ticketSchema,
    system: `You are a project management expert. Convert a feature specification into a ticket hierarchy.

Rules:
- Create exactly ONE epic for the overall feature
- Create stories for each user story in the spec
- Create tasks for each acceptance criterion, edge case, error state, and open question
- Tasks belong to their most relevant story (or directly to the epic if no story fits)
- Set priority based on importance signals in the text
- Add labels: section type, "edge-case", "error-handling", "question", etc.
- Keep titles concise (under 80 chars)
- Descriptions should include enough context to implement independently
- Include acceptance criteria from the spec on relevant stories
- For parentIndex, use the array index of the parent ticket (null for the epic)
- sourceSectionId must match one of the provided section IDs
- sourceSectionType must match the type of the source section`,
    prompt: `Feature: ${document.title}
${document.description ? `Description: ${document.description}` : ""}

Sections:
${sectionSummary}`,
  });

  return result.object.tickets.map((ticket, index) => ({
    id: `ticket-${index}`,
    type: ticket.type,
    title: ticket.title,
    description: ticket.description,
    labels: ticket.labels,
    priority: ticket.priority,
    parentId:
      ticket.parentIndex !== null ? `ticket-${ticket.parentIndex}` : null,
    sourceSectionId: ticket.sourceSectionId,
    sourceSectionType: ticket.sourceSectionType,
    acceptanceCriteria: ticket.acceptanceCriteria,
  }));
}
```

### Step 3: Create `src/lib/spec-export/targets/linear.ts`

```typescript
import type { TicketPreview, ExportResult } from "../types";

type LinearIssuePayload = {
  title: string;
  description: string;
  priority: number;
  labelNames: string[];
  parentId?: string;
};

export function formatLinearIssue(ticket: TicketPreview): LinearIssuePayload {
  const descriptionParts: string[] = [ticket.description];

  if (ticket.acceptanceCriteria.length > 0) {
    descriptionParts.push(
      `\n## Acceptance Criteria\n${ticket.acceptanceCriteria.map((c) => `- [ ] ${c}`).join("\n")}`
    );
  }

  return {
    title: ticket.title,
    description: descriptionParts.filter(Boolean).join("\n"),
    priority: mapPriority(ticket.priority),
    labelNames: ticket.labels,
  };
}

function mapPriority(priority: TicketPreview["priority"]): number {
  const map: Record<TicketPreview["priority"], number> = {
    urgent: 1,
    high: 2,
    medium: 3,
    low: 4,
    none: 0,
  };
  return map[priority];
}

type LinearCreateResponse = {
  id: string;
  url: string;
};

export async function createLinearTickets(
  tickets: TicketPreview[],
  mcpFetch: (toolName: string, args: Record<string, unknown>) => Promise<unknown>
): Promise<ExportResult[]> {
  const results: ExportResult[] = [];
  const idMap = new Map<string, string>();

  // Sort so epics are created first, then stories, then tasks
  const typeOrder: Record<string, number> = { epic: 0, story: 1, task: 2 };
  const sorted = [...tickets].sort(
    (a, b) => (typeOrder[a.type] ?? 2) - (typeOrder[b.type] ?? 2)
  );

  for (const ticket of sorted) {
    try {
      const payload = formatLinearIssue(ticket);

      // If this ticket has a parent, resolve the external ID
      if (ticket.parentId && idMap.has(ticket.parentId)) {
        payload.parentId = idMap.get(ticket.parentId);
      }

      const response = (await mcpFetch("linear_create_issue", payload)) as LinearCreateResponse;

      idMap.set(ticket.id, response.id);

      results.push({
        ticketId: ticket.id,
        externalId: response.id,
        externalUrl: response.url,
        status: "created",
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      results.push({
        ticketId: ticket.id,
        externalId: "",
        externalUrl: "",
        status: "failed",
        error: message,
      });
    }
  }

  return results;
}
```

### Step 4: Create `src/lib/spec-export/targets/github.ts`

```typescript
import type { TicketPreview, ExportResult } from "../types";

type GitHubIssuePayload = {
  title: string;
  body: string;
  labels: string[];
};

export function formatGitHubIssue(ticket: TicketPreview): GitHubIssuePayload {
  const bodyParts: string[] = [ticket.description];

  if (ticket.acceptanceCriteria.length > 0) {
    bodyParts.push(
      `\n## Acceptance Criteria\n${ticket.acceptanceCriteria.map((c) => `- [ ] ${c}`).join("\n")}`
    );
  }

  bodyParts.push(`\n---\nSource: ${ticket.sourceSectionType} section`);

  return {
    title: `[${ticket.type.toUpperCase()}] ${ticket.title}`,
    body: bodyParts.filter(Boolean).join("\n"),
    labels: [...ticket.labels, ticket.type],
  };
}

type GitHubCreateResponse = {
  number: number;
  html_url: string;
};

export async function createGitHubTickets(
  tickets: TicketPreview[],
  mcpFetch: (toolName: string, args: Record<string, unknown>) => Promise<unknown>,
  repo: { owner: string; name: string }
): Promise<ExportResult[]> {
  const results: ExportResult[] = [];
  const idMap = new Map<string, number>();

  // Sort so epics are created first, then stories, then tasks
  const typeOrder: Record<string, number> = { epic: 0, story: 1, task: 2 };
  const sorted = [...tickets].sort(
    (a, b) => (typeOrder[a.type] ?? 2) - (typeOrder[b.type] ?? 2)
  );

  for (const ticket of sorted) {
    try {
      const payload = formatGitHubIssue(ticket);

      // If this ticket has a parent, add a reference in the body
      if (ticket.parentId && idMap.has(ticket.parentId)) {
        const parentNumber = idMap.get(ticket.parentId);
        payload.body = `Parent: #${parentNumber}\n\n${payload.body}`;
      }

      const response = (await mcpFetch("github_create_issue", {
        owner: repo.owner,
        repo: repo.name,
        ...payload,
      })) as GitHubCreateResponse;

      idMap.set(ticket.id, response.number);

      results.push({
        ticketId: ticket.id,
        externalId: String(response.number),
        externalUrl: response.html_url,
        status: "created",
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      results.push({
        ticketId: ticket.id,
        externalId: "",
        externalUrl: "",
        status: "failed",
        error: message,
      });
    }
  }

  return results;
}
```

### Step 5: Create `src/app/api/documents/[documentId]/export/preview/route.ts`

```typescript
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { withAuth } from "@src/lib/auth-guard";
import { db } from "@src/lib/db";
import { document, section } from "@src/lib/db/schema/editor";
import { eq, and, asc } from "drizzle-orm";
import { mapDocumentToTickets } from "@src/lib/spec-export/mapper";
import type { ExportTarget, ExportPreviewResponse } from "@src/lib/spec-export/types";

type PreviewBody = {
  target: ExportTarget;
};

export const POST = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const documentIdIndex = pathParts.indexOf("documents") + 1;
  const documentId = pathParts[documentIdIndex];

  if (!documentId) {
    return NextResponse.json(
      { error: "Document ID is required" },
      { status: 400 }
    );
  }

  const body = (await request.json()) as PreviewBody;

  if (!body.target || !["linear", "github"].includes(body.target)) {
    return NextResponse.json(
      { error: "Invalid export target. Must be 'linear' or 'github'." },
      { status: 400 }
    );
  }

  // Fetch document, verifying ownership
  const docs = await db
    .select()
    .from(document)
    .where(and(eq(document.id, documentId), eq(document.userId, user.id)))
    .limit(1);

  if (docs.length === 0) {
    return NextResponse.json(
      { error: "Document not found" },
      { status: 404 }
    );
  }

  const doc = docs[0];

  // Fetch all sections for this document
  const sections = await db
    .select()
    .from(section)
    .where(eq(section.documentId, documentId))
    .orderBy(asc(section.sortOrder));

  if (sections.length === 0) {
    return NextResponse.json(
      { error: "Document has no sections to export" },
      { status: 400 }
    );
  }

  // Map sections to ticket hierarchy using AI
  const tickets = await mapDocumentToTickets(
    { title: doc.title, description: doc.description ?? null },
    sections.map((s) => ({
      id: s.id,
      type: s.type,
      title: s.title,
      content: s.content,
    }))
  );

  const response: ExportPreviewResponse = {
    target: body.target,
    documentTitle: doc.title,
    tickets,
    totalCount: tickets.length,
  };

  return NextResponse.json(response);
});
```

### Step 6: Create `src/app/api/documents/[documentId]/export/execute/route.ts`

```typescript
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { withAuth } from "@src/lib/auth-guard";
import { db } from "@src/lib/db";
import { document, section } from "@src/lib/db/schema/editor";
import { eq, and } from "drizzle-orm";
import { connectMCPServers } from "@src/lib/ai/mcp/client";
import { mcpServers } from "@src/lib/ai/mcp/servers";
import { createLinearTickets } from "@src/lib/spec-export/targets/linear";
import { createGitHubTickets } from "@src/lib/spec-export/targets/github";
import type {
  ExportExecuteRequest,
  ExportExecuteResponse,
  ExportResult,
} from "@src/lib/spec-export/types";

export const POST = withAuth(async (request: NextRequest, { user }) => {
  const pathParts = request.nextUrl.pathname.split("/");
  const documentIdIndex = pathParts.indexOf("documents") + 1;
  const documentId = pathParts[documentIdIndex];

  if (!documentId) {
    return NextResponse.json(
      { error: "Document ID is required" },
      { status: 400 }
    );
  }

  const body = (await request.json()) as ExportExecuteRequest;

  if (!body.target || !["linear", "github"].includes(body.target)) {
    return NextResponse.json(
      { error: "Invalid export target" },
      { status: 400 }
    );
  }

  if (!body.tickets || body.tickets.length === 0) {
    return NextResponse.json(
      { error: "No tickets to create" },
      { status: 400 }
    );
  }

  // Verify document ownership
  const docs = await db
    .select({ id: document.id })
    .from(document)
    .where(and(eq(document.id, documentId), eq(document.userId, user.id)))
    .limit(1);

  if (docs.length === 0) {
    return NextResponse.json(
      { error: "Document not found" },
      { status: 404 }
    );
  }

  // Connect to MCP servers to access Linear/GitHub tools
  const mcp = await connectMCPServers(mcpServers);

  try {
    // Create an MCP tool caller function
    const mcpFetch = async (
      toolName: string,
      args: Record<string, unknown>
    ): Promise<unknown> => {
      const tool = mcp.tools[toolName];
      if (!tool) {
        throw new Error(
          `MCP tool "${toolName}" not found. Ensure the corresponding MCP server is configured.`
        );
      }
      // Execute the MCP tool with the provided arguments
      const result = await tool.execute(args, {
        toolCallId: crypto.randomUUID(),
        messages: [],
      });
      return result;
    };

    let results: ExportResult[];

    if (body.target === "linear") {
      results = await createLinearTickets(body.tickets, mcpFetch);
    } else {
      // For GitHub, we need the repo info — extract from env or MCP config
      const owner = process.env.GITHUB_REPO_OWNER ?? "";
      const name = process.env.GITHUB_REPO_NAME ?? "";

      if (!owner || !name) {
        return NextResponse.json(
          {
            error:
              "GitHub repository not configured. Set GITHUB_REPO_OWNER and GITHUB_REPO_NAME environment variables.",
          },
          { status: 400 }
        );
      }

      results = await createGitHubTickets(body.tickets, mcpFetch, {
        owner,
        name,
      });
    }

    // Store external references back on sections
    const successfulResults = results.filter((r) => r.status === "created");
    for (const result of successfulResults) {
      const ticket = body.tickets.find((t) => t.id === result.ticketId);
      if (ticket) {
        await db
          .update(section)
          .set({
            metadata: {
              externalTicketId: result.externalId,
              externalTicketUrl: result.externalUrl,
              exportTarget: body.target,
            },
          })
          .where(
            and(
              eq(section.id, ticket.sourceSectionId),
              eq(section.documentId, documentId)
            )
          );
      }
    }

    const response: ExportExecuteResponse = {
      results,
      successCount: results.filter((r) => r.status === "created").length,
      failCount: results.filter((r) => r.status === "failed").length,
    };

    return NextResponse.json(response);
  } finally {
    await mcp.close();
  }
});
```

### Step 7: Create `src/components/editor/export-button.tsx`

```tsx
"use client";

import { useState, useId } from "react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { ExportDialog } from "@/components/editor/export-dialog";
import type { ExportTarget } from "@src/lib/spec-export/types";

type ExportButtonProps = {
  documentId: string;
};

type TargetOption = {
  value: ExportTarget;
  label: string;
};

const TARGET_OPTIONS: TargetOption[] = [
  { value: "linear", label: "Linear" },
  { value: "github", label: "GitHub Issues" },
];

export function ExportButton({ documentId }: ExportButtonProps) {
  const menuId = useId();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [selectedTarget, setSelectedTarget] = useState<ExportTarget>("linear");

  function handleSelectTarget(target: ExportTarget) {
    setSelectedTarget(target);
    setDialogOpen(true);
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="outline" size="sm">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="mr-2"
            >
              <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
              <polyline points="17 8 12 3 7 8" />
              <line x1="12" x2="12" y1="3" y2="15" />
            </svg>
            Export to...
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {TARGET_OPTIONS.map((option) => (
            <DropdownMenuItem
              key={`${menuId}-${option.value}`}
              onClick={() => handleSelectTarget(option.value)}
            >
              {option.label}
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>

      <ExportDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        documentId={documentId}
        initialTarget={selectedTarget}
      />
    </>
  );
}
```

### Step 8: Create `src/components/editor/export-dialog.tsx`

```tsx
"use client";

import { useState, useCallback, useId } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Checkbox } from "@/components/ui/checkbox";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";
import { Label } from "@/components/ui/label";
import type {
  ExportTarget,
  TicketPreview,
  ExportResult,
  ExportPreviewResponse,
  ExportExecuteResponse,
} from "@src/lib/spec-export/types";

type ExportDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  documentId: string;
  initialTarget: ExportTarget;
};

type DialogStep = "target" | "preview" | "confirm" | "progress";

const TICKET_TYPE_STYLES: Record<string, { variant: "default" | "secondary" | "outline"; label: string }> = {
  epic: { variant: "default", label: "Epic" },
  story: { variant: "secondary", label: "Story" },
  task: { variant: "outline", label: "Task" },
};

export function ExportDialog({
  open,
  onOpenChange,
  documentId,
  initialTarget,
}: ExportDialogProps) {
  const ticketListId = useId();
  const resultListId = useId();

  const [step, setStep] = useState<DialogStep>("target");
  const [target, setTarget] = useState<ExportTarget>(initialTarget);
  const [tickets, setTickets] = useState<TicketPreview[]>([]);
  const [excludedIds, setExcludedIds] = useState<Set<string>>(new Set());
  const [results, setResults] = useState<ExportResult[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [progressPercent, setProgressPercent] = useState(0);
  const [documentTitle, setDocumentTitle] = useState("");

  const includedTickets = tickets.filter((t) => !excludedIds.has(t.id));

  const resetDialog = useCallback(() => {
    setStep("target");
    setTarget(initialTarget);
    setTickets([]);
    setExcludedIds(new Set());
    setResults([]);
    setIsLoading(false);
    setError(null);
    setProgressPercent(0);
    setDocumentTitle("");
  }, [initialTarget]);

  const handleOpenChange = useCallback(
    (nextOpen: boolean) => {
      if (!nextOpen) {
        resetDialog();
      }
      onOpenChange(nextOpen);
    },
    [onOpenChange, resetDialog]
  );

  const handleGeneratePreview = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const res = await fetch(
        `/api/documents/${documentId}/export/preview`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ target }),
        }
      );

      if (!res.ok) {
        const data = (await res.json()) as { error: string };
        throw new Error(data.error || "Failed to generate preview");
      }

      const data = (await res.json()) as ExportPreviewResponse;
      setTickets(data.tickets);
      setDocumentTitle(data.documentTitle);
      setStep("preview");
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      setError(message);
    } finally {
      setIsLoading(false);
    }
  }, [documentId, target]);

  const handleToggleTicket = useCallback((ticketId: string) => {
    setExcludedIds((prev) => {
      const next = new Set(prev);
      if (next.has(ticketId)) {
        next.delete(ticketId);
      } else {
        next.add(ticketId);
      }
      return next;
    });
  }, []);

  const handleExecuteExport = useCallback(async () => {
    setStep("progress");
    setIsLoading(true);
    setError(null);
    setProgressPercent(10);

    try {
      const res = await fetch(
        `/api/documents/${documentId}/export/execute`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            target,
            tickets: includedTickets,
          }),
        }
      );

      setProgressPercent(90);

      if (!res.ok) {
        const data = (await res.json()) as { error: string };
        throw new Error(data.error || "Failed to create tickets");
      }

      const data = (await res.json()) as ExportExecuteResponse;
      setResults(data.results);
      setProgressPercent(100);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      setError(message);
      setProgressPercent(100);
    } finally {
      setIsLoading(false);
    }
  }, [documentId, target, includedTickets]);

  const targetLabel = target === "linear" ? "Linear" : "GitHub Issues";
  const successCount = results.filter((r) => r.status === "created").length;
  const failCount = results.filter((r) => r.status === "failed").length;

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-w-2xl max-h-[80vh] overflow-hidden flex flex-col">
        <DialogHeader>
          <DialogTitle>
            {step === "target" && "Export Spec to Tickets"}
            {step === "preview" && `Preview: ${documentTitle}`}
            {step === "confirm" && "Confirm Export"}
            {step === "progress" && "Creating Tickets..."}
          </DialogTitle>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto py-4">
          {/* Step 1: Target Selection */}
          {step === "target" && (
            <div className="space-y-4">
              <p className="text-sm text-muted-foreground">
                Choose where to create tickets from this spec document.
              </p>
              <RadioGroup
                value={target}
                onValueChange={(value) => setTarget(value as ExportTarget)}
                className="space-y-3"
              >
                <div className="flex items-center space-x-3 rounded-lg border p-4">
                  <RadioGroupItem value="linear" id="target-linear" />
                  <Label htmlFor="target-linear" className="flex-1 cursor-pointer">
                    <div className="font-medium">Linear</div>
                    <div className="text-sm text-muted-foreground">
                      Create issues with epics, stories, and tasks hierarchy
                    </div>
                  </Label>
                </div>
                <div className="flex items-center space-x-3 rounded-lg border p-4">
                  <RadioGroupItem value="github" id="target-github" />
                  <Label htmlFor="target-github" className="flex-1 cursor-pointer">
                    <div className="font-medium">GitHub Issues</div>
                    <div className="text-sm text-muted-foreground">
                      Create issues with type labels and parent references
                    </div>
                  </Label>
                </div>
              </RadioGroup>
              {error && (
                <p className="text-sm text-destructive">{error}</p>
              )}
            </div>
          )}

          {/* Step 2: Preview */}
          {step === "preview" && (
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <p className="text-sm text-muted-foreground">
                  {includedTickets.length} of {tickets.length} tickets selected
                </p>
                <Badge variant="outline">{targetLabel}</Badge>
              </div>
              <div className="space-y-1">
                {tickets.map((ticket) => {
                  const isExcluded = excludedIds.has(ticket.id);
                  const depth = ticket.parentId
                    ? tickets.find((t) => t.id === ticket.parentId)?.parentId
                      ? 2
                      : 1
                    : 0;
                  const indent = depth * 24;
                  const typeStyle = TICKET_TYPE_STYLES[ticket.type] ?? {
                    variant: "outline" as const,
                    label: ticket.type,
                  };

                  return (
                    <div
                      key={`${ticketListId}-${ticket.id}`}
                      className="flex items-start gap-3 rounded-md border p-3"
                      style={{ marginLeft: `${indent}px` }}
                    >
                      <Checkbox
                        checked={!isExcluded}
                        onCheckedChange={() => handleToggleTicket(ticket.id)}
                        className="mt-0.5"
                      />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <Badge variant={typeStyle.variant} className="shrink-0">
                            {typeStyle.label}
                          </Badge>
                          <span
                            className={`text-sm font-medium truncate ${isExcluded ? "line-through text-muted-foreground" : ""}`}
                          >
                            {ticket.title}
                          </span>
                        </div>
                        {ticket.labels.length > 0 && (
                          <div className="mt-1 flex flex-wrap gap-1">
                            {ticket.labels.map((label) => (
                              <Badge
                                key={`${ticketListId}-${ticket.id}-label-${label}`}
                                variant="outline"
                                className="text-xs"
                              >
                                {label}
                              </Badge>
                            ))}
                          </div>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* Step 3: Confirm */}
          {step === "confirm" && (
            <div className="space-y-4 text-center">
              <p className="text-lg font-medium">
                Create {includedTickets.length} tickets in {targetLabel}?
              </p>
              <p className="text-sm text-muted-foreground">
                This will create{" "}
                {includedTickets.filter((t) => t.type === "epic").length} epic(s),{" "}
                {includedTickets.filter((t) => t.type === "story").length} story(s),
                and {includedTickets.filter((t) => t.type === "task").length} task(s).
              </p>
              {error && (
                <p className="text-sm text-destructive">{error}</p>
              )}
            </div>
          )}

          {/* Step 4: Progress */}
          {step === "progress" && (
            <div className="space-y-4">
              <Progress value={progressPercent} className="w-full" />
              {isLoading && (
                <p className="text-sm text-muted-foreground text-center">
                  Creating tickets in {targetLabel}...
                </p>
              )}
              {!isLoading && results.length > 0 && (
                <>
                  <div className="flex items-center justify-center gap-4 text-sm">
                    {successCount > 0 && (
                      <span className="text-green-600 dark:text-green-400">
                        {successCount} created
                      </span>
                    )}
                    {failCount > 0 && (
                      <span className="text-destructive">
                        {failCount} failed
                      </span>
                    )}
                  </div>
                  <div className="space-y-1 max-h-60 overflow-y-auto">
                    {results.map((result) => {
                      const ticket = tickets.find(
                        (t) => t.id === result.ticketId
                      );
                      return (
                        <div
                          key={`${resultListId}-${result.ticketId}`}
                          className="flex items-center justify-between rounded-md border p-2 text-sm"
                        >
                          <span className="truncate">
                            {ticket?.title ?? result.ticketId}
                          </span>
                          {result.status === "created" ? (
                            <a
                              href={result.externalUrl}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="shrink-0 text-blue-600 dark:text-blue-400 hover:underline"
                            >
                              {result.externalId}
                            </a>
                          ) : (
                            <span className="shrink-0 text-destructive">
                              {result.error ?? "Failed"}
                            </span>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </>
              )}
              {error && !results.length && (
                <p className="text-sm text-destructive text-center">
                  {error}
                </p>
              )}
            </div>
          )}
        </div>

        <DialogFooter>
          {step === "target" && (
            <>
              <Button
                variant="ghost"
                onClick={() => handleOpenChange(false)}
              >
                Cancel
              </Button>
              <Button onClick={handleGeneratePreview} disabled={isLoading}>
                {isLoading ? (
                  <span className="flex items-center gap-2">
                    <span className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
                    Generating...
                  </span>
                ) : (
                  "Generate Preview"
                )}
              </Button>
            </>
          )}

          {step === "preview" && (
            <>
              <Button variant="ghost" onClick={() => setStep("target")}>
                Back
              </Button>
              <Button
                onClick={() => setStep("confirm")}
                disabled={includedTickets.length === 0}
              >
                Continue ({includedTickets.length} tickets)
              </Button>
            </>
          )}

          {step === "confirm" && (
            <>
              <Button variant="ghost" onClick={() => setStep("preview")}>
                Back
              </Button>
              <Button onClick={handleExecuteExport} disabled={isLoading}>
                Create Tickets
              </Button>
            </>
          )}

          {step === "progress" && !isLoading && (
            <Button onClick={() => handleOpenChange(false)}>Done</Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

### Step 9: Modify `src/components/editor/document-editor.tsx`

Add the export button to the document editor toolbar.

Find this:

```tsx
import { Button } from "@/components/ui/button";
```

Replace with:

```tsx
import { Button } from "@/components/ui/button";
import { ExportButton } from "@/components/editor/export-button";
```

Then find the toolbar area in the component (near the document title). Add the export button next to the existing toolbar controls:

```tsx
        {/* [spec-export]: export button */}
        <ExportButton documentId={documentId} />
```

## Usage

### Exporting a Spec to Linear

1. Open a document in the structured editor.
2. Click **"Export to..."** in the toolbar.
3. Select **Linear** from the dropdown menu.
4. Click **"Generate Preview"** -- the AI analyzes all sections and maps them to a ticket hierarchy.
5. Review the preview:
   - Epic at the top level (the overall feature)
   - Stories indented under the epic (one per user story section)
   - Tasks indented under their stories (acceptance criteria, edge cases, open questions)
6. Uncheck any tickets you do not want to create.
7. Click **"Continue"** then **"Create Tickets"**.
8. Watch the progress bar as tickets are created one by one.
9. Click the external ID links to open created tickets in Linear.

### Exporting to GitHub Issues

1. Ensure `GITHUB_REPO_OWNER` and `GITHUB_REPO_NAME` are set in `.env.local`.
2. Follow the same flow as above, selecting **GitHub Issues** instead.
3. Tickets are created as GitHub Issues with `[EPIC]`, `[STORY]`, or `[TASK]` prefixes in the title.
4. Parent references are added as `Parent: #<number>` in the issue body.

### Programmatic Usage

```typescript
// Generate a preview
const previewRes = await fetch(`/api/documents/${docId}/export/preview`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ target: "linear" }),
});
const preview = await previewRes.json();
// preview.tickets contains the full ticket hierarchy

// Execute the export
const executeRes = await fetch(`/api/documents/${docId}/export/execute`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    target: "linear",
    tickets: preview.tickets,
  }),
});
const result = await executeRes.json();
// result.results contains external IDs and URLs
```

## Acceptance Criteria

- Click "Export to..." -- dialog opens with target selection (Linear / GitHub Issues)
- Select Linear -- click "Generate Preview" -- preview shows ticket hierarchy with epic/story/task badges
- Uncheck a ticket -- it is excluded from the preview count and will not be created
- Click "Continue" then "Create Tickets" -- progress bar shows, tickets created
- Created tickets show external URL links that open in the target system
- Failed tickets show an error message in the results list
- Export results (external IDs) are stored back on the document sections as metadata
- Unauthenticated requests to `/api/documents/[id]/export/*` return 401
- `tsc` passes with no errors
- `bun run build` succeeds
