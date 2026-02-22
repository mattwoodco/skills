---
name: zip-download
description: Bundle multiple remote files into a ZIP archive and stream it to the browser. Use this skill when the user says "add zip download", "download all as zip", "batch download", or "bundle files".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: [auth, env-config]
---

# Zip Download Skill

Server-side ZIP bundling endpoint that fetches remote files in parallel and streams a ZIP archive to the browser. Uses `fflate` for synchronous in-memory compression.

## Prerequisites

- Next.js App Router (no `src/` directory)
- better-auth session via `@/lib/auth`

## Installation

```bash
bun add fflate
```

## What Gets Created

```
app/api/zip/route.ts
lib/zip-download/client.ts
```

## Setup Steps

### Step 1: Create `app/api/zip/route.ts`

```typescript
import { type NextRequest, NextResponse } from "next/server";
import { zipSync } from "fflate";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";

type ZipRequest = {
  files: Array<{ url: string; filename: string }>;
  zipName?: string;
};

function isValidZipRequest(body: unknown): body is ZipRequest {
  if (typeof body !== "object" || body === null) return false;
  const obj = body as Record<string, unknown>;
  if (!Array.isArray(obj.files)) return false;
  if (obj.files.length === 0 || obj.files.length > 50) return false;
  return obj.files.every(
    (f) =>
      typeof f === "object" &&
      f !== null &&
      typeof (f as Record<string, unknown>).url === "string" &&
      typeof (f as Record<string, unknown>).filename === "string" &&
      ((f as Record<string, unknown>).url as string).startsWith("http://") ||
      ((f as Record<string, unknown>).url as string).startsWith("https://")
  );
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!isValidZipRequest(body)) {
    return NextResponse.json(
      {
        error:
          "Invalid request. Provide 1–50 files, each with a url (http/https) and filename.",
      },
      { status: 400 }
    );
  }

  const { files, zipName = "download" } = body;

  const buffers = await Promise.all(
    files.map(async (f) => {
      const res = await fetch(f.url);
      if (!res.ok) {
        throw new Error(`Failed to fetch ${f.url}: ${res.status}`);
      }
      return res.arrayBuffer();
    })
  );

  const filesObj: Record<string, Uint8Array> = {};
  for (let i = 0; i < files.length; i++) {
    filesObj[files[i].filename] = new Uint8Array(buffers[i]);
  }

  const zipped = zipSync(filesObj);

  return new Response(zipped, {
    headers: {
      "Content-Type": "application/zip",
      "Content-Disposition": `attachment; filename="${zipName}.zip"`,
      "Content-Length": String(zipped.byteLength),
    },
  });
}
```

### Step 2: Create `lib/zip-download/client.ts`

```typescript
type ZipFile = { url: string; filename: string };

export async function downloadAsZip(
  files: ZipFile[],
  zipName?: string
): Promise<void> {
  const response = await fetch("/api/zip", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ files, zipName }),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({ error: "Unknown error" }));
    throw new Error((err as { error?: string }).error ?? `HTTP ${response.status}`);
  }

  const blob = await response.blob();
  const objectUrl = URL.createObjectURL(blob);

  const anchor = document.createElement("a");
  anchor.href = objectUrl;
  anchor.download = `${zipName ?? "download"}.zip`;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(objectUrl);
}
```

## Usage

```typescript
import { downloadAsZip } from "@/lib/zip-download/client";

// In a React component or event handler
await downloadAsZip(
  [
    { url: "https://example.com/image1.jpg", filename: "image1.jpg" },
    { url: "https://example.com/image2.png", filename: "image2.png" },
  ],
  "my-images"
);
```

## Request / Response

**POST `/api/zip`**

Request body:
```json
{
  "files": [
    { "url": "https://example.com/file.pdf", "filename": "report.pdf" }
  ],
  "zipName": "exports"
}
```

| Status | Reason |
|--------|--------|
| 200 | ZIP stream with `Content-Type: application/zip` |
| 400 | Empty files array, more than 50 files, or non-http URL |
| 401 | Not authenticated |

## Acceptance Criteria

- Authenticated POST with 1 valid file returns a `application/zip` response
- Unauthenticated POST returns 401
- POST with 0 files returns 400
- POST with 51 files returns 400
- POST with a file URL not starting with `http://` or `https://` returns 400
- `downloadAsZip` triggers a browser file download without navigation
- `tsc` passes with no errors
- Build succeeds (`bun run build`)
