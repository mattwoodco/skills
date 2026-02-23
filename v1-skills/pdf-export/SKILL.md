---
name: pdf-export
description: Server-side PDF generation from structured data using @react-pdf/renderer — storyboard exports and document summaries. Use this skill when the user says "add pdf export", "export to pdf", "generate pdf", "download storyboard", or "export summary".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: [auth]
---

# PDF Export Skill

Server-side PDF generation endpoint using `@react-pdf/renderer`. Supports two document types: storyboard grids (landscape A4, 2 shots per row) and summary documents (portrait A4, heading/content sections).

## Prerequisites

- Next.js App Router (no `src/` directory)
- better-auth session via `@src/lib/auth`

## Installation

```bash
bun add @react-pdf/renderer
```

## What Gets Created

```
app/api/export/pdf/route.ts
lib/pdf-export/styles.ts
lib/pdf-export/storyboard-pdf.tsx
lib/pdf-export/summary-pdf.tsx
lib/pdf-export/client.ts
```

## Setup Steps

### Step 1: Create `lib/pdf-export/styles.ts`

```typescript
import { StyleSheet } from "@react-pdf/renderer";

export const COLORS = {
  primary: "#2563EB",
  text: "#111827",
  muted: "#6B7280",
  border: "#E5E7EB",
} as const;

export const SPACING = {
  sm: 4,
  md: 8,
  lg: 16,
  xl: 24,
} as const;

export const sharedStyles = StyleSheet.create({
  page: {
    fontFamily: "Helvetica",
    color: COLORS.text,
    padding: SPACING.xl,
  },
  title: {
    fontSize: 20,
    fontFamily: "Helvetica-Bold",
    color: COLORS.text,
    marginBottom: SPACING.sm,
  },
  subtitle: {
    fontSize: 12,
    color: COLORS.muted,
    marginBottom: SPACING.md,
  },
  sectionHeading: {
    fontSize: 13,
    fontFamily: "Helvetica-Bold",
    color: COLORS.text,
    marginTop: SPACING.lg,
    marginBottom: SPACING.sm,
  },
  bodyText: {
    fontSize: 10,
    color: COLORS.text,
    lineHeight: 1.5,
  },
  footer: {
    position: "absolute",
    bottom: SPACING.xl,
    left: SPACING.xl,
    right: SPACING.xl,
    fontSize: 9,
    color: COLORS.muted,
    textAlign: "right",
  },
});
```

### Step 2: Create `lib/pdf-export/storyboard-pdf.tsx`

```typescript
import {
  Document,
  Page,
  View,
  Text,
  Image,
  StyleSheet,
} from "@react-pdf/renderer";
import { COLORS, SPACING, sharedStyles } from "./styles";

export type StoryboardShot = {
  id: string;
  shotNumber: number;
  description: string;
  cameraAngle: string;
  duration: number;
  imageUrl?: string;
};

export type StoryboardPdfInput = {
  type: "storyboard";
  title: string;
  shots: StoryboardShot[];
  createdAt: string;
};

const styles = StyleSheet.create({
  page: {
    ...sharedStyles.page,
    flexDirection: "column",
  },
  grid: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: SPACING.md,
    marginTop: SPACING.md,
  },
  card: {
    width: "48%",
    border: `1px solid ${COLORS.border}`,
    borderRadius: 4,
    padding: SPACING.md,
    marginBottom: SPACING.md,
  },
  cardHeader: {
    flexDirection: "row",
    alignItems: "center",
    marginBottom: SPACING.sm,
    gap: SPACING.sm,
  },
  shotBadge: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: COLORS.primary,
    alignItems: "center",
    justifyContent: "center",
  },
  shotBadgeText: {
    color: "#ffffff",
    fontSize: 9,
    fontFamily: "Helvetica-Bold",
  },
  cardTitle: {
    fontSize: 10,
    fontFamily: "Helvetica-Bold",
    color: COLORS.text,
    flex: 1,
  },
  imagePlaceholder: {
    width: "100%",
    height: 75,
    backgroundColor: COLORS.border,
    borderRadius: 2,
    marginBottom: SPACING.sm,
  },
  shotImage: {
    width: "100%",
    height: 75,
    objectFit: "cover",
    borderRadius: 2,
    marginBottom: SPACING.sm,
  },
  description: {
    fontSize: 9,
    color: COLORS.text,
    marginBottom: SPACING.sm,
    lineHeight: 1.4,
  },
  tagsRow: {
    flexDirection: "row",
    gap: SPACING.sm,
    flexWrap: "wrap",
  },
  tag: {
    backgroundColor: "#F3F4F6",
    paddingHorizontal: SPACING.sm,
    paddingVertical: 2,
    borderRadius: 3,
    fontSize: 8,
    color: COLORS.muted,
  },
});

type StoryboardPDFProps = {
  input: StoryboardPdfInput;
};

export function StoryboardPDF({ input }: StoryboardPDFProps) {
  return (
    <Document>
      <Page size="A4" orientation="landscape" style={styles.page}>
        <Text style={sharedStyles.title}>{input.title}</Text>
        <Text style={sharedStyles.subtitle}>
          {input.shots.length} shots · {input.createdAt}
        </Text>
        <View style={styles.grid}>
          {input.shots.map((shot) => (
            <View key={shot.id} style={styles.card}>
              <View style={styles.cardHeader}>
                <View style={styles.shotBadge}>
                  <Text style={styles.shotBadgeText}>{shot.shotNumber}</Text>
                </View>
                <Text style={styles.cardTitle}>Shot {shot.shotNumber}</Text>
              </View>
              {shot.imageUrl ? (
                <Image src={shot.imageUrl} style={styles.shotImage} />
              ) : (
                <View style={styles.imagePlaceholder} />
              )}
              <Text style={styles.description}>{shot.description}</Text>
              <View style={styles.tagsRow}>
                <Text style={styles.tag}>{shot.cameraAngle}</Text>
                <Text style={styles.tag}>{shot.duration}s</Text>
              </View>
            </View>
          ))}
        </View>
      </Page>
    </Document>
  );
}
```

### Step 3: Create `lib/pdf-export/summary-pdf.tsx`

```typescript
import {
  Document,
  Page,
  View,
  Text,
  StyleSheet,
} from "@react-pdf/renderer";
import { COLORS, SPACING, sharedStyles } from "./styles";

export type SummarySection = {
  heading: string;
  content: string;
};

export type SummaryPdfInput = {
  type: "summary";
  title: string;
  documentName: string;
  sections: SummarySection[];
  createdAt: string;
};

const styles = StyleSheet.create({
  page: {
    ...sharedStyles.page,
    flexDirection: "column",
  },
  divider: {
    height: 1,
    backgroundColor: COLORS.border,
    marginVertical: SPACING.md,
  },
  section: {
    marginBottom: SPACING.lg,
  },
});

type SummaryPDFProps = {
  input: SummaryPdfInput;
};

export function SummaryPDF({ input }: SummaryPDFProps) {
  return (
    <Document>
      <Page size="A4" style={styles.page}>
        <Text style={sharedStyles.title}>{input.title}</Text>
        <Text style={sharedStyles.subtitle}>{input.documentName}</Text>
        <Text style={{ ...sharedStyles.subtitle, fontSize: 9 }}>
          {input.createdAt}
        </Text>
        <View style={styles.divider} />
        {input.sections.map((section, i) => (
          <View
            key={`section-${i}-${section.heading}`}
            style={styles.section}
          >
            <Text style={sharedStyles.sectionHeading}>{section.heading}</Text>
            <Text style={sharedStyles.bodyText}>{section.content}</Text>
          </View>
        ))}
        <Text
          style={sharedStyles.footer}
          render={({ pageNumber, totalPages }) =>
            `${pageNumber} / ${totalPages}`
          }
          fixed
        />
      </Page>
    </Document>
  );
}
```

### Step 4: Create `app/api/export/pdf/route.ts`

```typescript
import { type NextRequest, NextResponse } from "next/server";
import { renderToBuffer } from "@react-pdf/renderer";
import { headers } from "next/headers";
import { auth } from "@src/lib/auth";
import { StoryboardPDF } from "@src/lib/pdf-export/storyboard-pdf";
import { SummaryPDF } from "@src/lib/pdf-export/summary-pdf";
import type { StoryboardPdfInput, SummaryPdfInput } from "@src/lib/pdf-export/storyboard-pdf";

type PdfInput = StoryboardPdfInput | SummaryPdfInput;

function isStoryboardInput(input: PdfInput): input is StoryboardPdfInput {
  return input.type === "storyboard";
}

function isSummaryInput(input: PdfInput): input is SummaryPdfInput {
  return input.type === "summary";
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let input: unknown;
  try {
    input = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (
    typeof input !== "object" ||
    input === null ||
    !("type" in input)
  ) {
    return NextResponse.json({ error: "Missing type field" }, { status: 400 });
  }

  const typed = input as PdfInput;

  if (!isStoryboardInput(typed) && !isSummaryInput(typed)) {
    return NextResponse.json(
      { error: 'type must be "storyboard" or "summary"' },
      { status: 400 }
    );
  }

  let buffer: Buffer;
  const title = typed.title;

  if (isStoryboardInput(typed)) {
    buffer = await renderToBuffer(<StoryboardPDF input={typed} />);
  } else {
    buffer = await renderToBuffer(<SummaryPDF input={typed} />);
  }

  const safeTitle = title.replace(/[^a-zA-Z0-9_-]/g, "_");

  return new Response(buffer, {
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `attachment; filename="${safeTitle}.pdf"`,
    },
  });
}
```

### Step 5: Create `lib/pdf-export/client.ts`

```typescript
import type { StoryboardPdfInput, SummaryPdfInput } from "./storyboard-pdf";

type PdfInput = StoryboardPdfInput | SummaryPdfInput;

export async function exportToPdf(
  input: PdfInput,
  filename?: string
): Promise<void> {
  const response = await fetch("/api/export/pdf", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({ error: "Unknown error" }));
    throw new Error(
      (err as { error?: string }).error ?? `HTTP ${response.status}`
    );
  }

  const blob = await response.blob();
  const objectUrl = URL.createObjectURL(blob);

  const safeFilename =
    filename ?? input.title.replace(/[^a-zA-Z0-9_-]/g, "_");

  const anchor = document.createElement("a");
  anchor.href = objectUrl;
  anchor.download = `${safeFilename}.pdf`;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(objectUrl);
}
```

## Usage

```typescript
import { exportToPdf } from "@src/lib/pdf-export/client";

// Storyboard PDF
await exportToPdf({
  type: "storyboard",
  title: "Product Launch Campaign",
  createdAt: new Date().toLocaleDateString(),
  shots: [
    {
      id: "shot-1",
      shotNumber: 1,
      description: "Wide establishing shot of city skyline at dawn",
      cameraAngle: "Wide",
      duration: 3,
      imageUrl: "https://example.com/frame1.jpg",
    },
  ],
});

// Summary PDF
await exportToPdf({
  type: "summary",
  title: "Q1 Strategy Review",
  documentName: "Board Meeting 2026",
  createdAt: "February 17, 2026",
  sections: [
    {
      heading: "Executive Summary",
      content: "Revenue grew 34% YoY driven by enterprise expansion...",
    },
    {
      heading: "Key Risks",
      content: "Supply chain constraints remain a challenge in Q2...",
    },
  ],
});
```

## Acceptance Criteria

- Authenticated POST with `type: "storyboard"` returns `application/pdf` with `Content-Disposition: attachment`
- Authenticated POST with `type: "summary"` returns `application/pdf` with `Content-Disposition: attachment`
- Unauthenticated POST returns 401
- POST with unknown `type` returns 400
- Storyboard PDF is landscape A4 with shot cards rendered in a 2-per-row grid
- Summary PDF is portrait A4 with page numbers in the footer
- Shot cards without `imageUrl` render a gray placeholder rectangle
- `exportToPdf` triggers a browser file download
- `tsc` passes with no errors
- Build succeeds (`bun run build`)
