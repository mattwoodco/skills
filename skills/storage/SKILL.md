---
name: storage
description: Unified file storage — S3-compatible (RustFS/MinIO) for local dev, Vercel Blob for production. Simple upload/download/delete/list API with presigned URLs.
author: Claude
version: 2.0.0
created: 2025-01-11
updated: 2026-02-13
dependencies: [docker, env-config]
---

# Storage Skill

Server-side file storage abstraction with automatic provider detection. Uses S3-compatible storage (RustFS) locally and Vercel Blob in production.

## Prerequisites

- Next.js app with `src/` directory and App Router
- Docker setup (for local RustFS — see docker-compose section)

## Installation

```bash
bun add @aws-sdk/client-s3 @aws-sdk/s3-request-presigner @vercel/blob
```

## Environment Variables

Add to `.env.local`:

```env
# Local Development — S3-compatible storage (RustFS)
S3_ENDPOINT=http://localhost:9000
S3_ACCESS_KEY=rustfsadmin
S3_SECRET_KEY=rustfsadmin
S3_BUCKET=uploads
S3_REGION=us-east-1
```

For production, set `BLOB_READ_WRITE_TOKEN` in your Vercel project settings. When present, the provider auto-switches to Vercel Blob.

## Docker Setup

The `docker` skill (dependency) provides the RustFS service in `docker-compose.yml`. After `docker compose up`, create the uploads bucket:

```bash
bunx @rustfs/mc alias set local http://localhost:9000 rustfsadmin rustfsadmin
bunx @rustfs/mc mb local/uploads
```

## What Gets Created

```
src/
├── lib/
│   └── storage/
│       ├── types.ts              # StorageProvider interface, StorageFile, StorageError
│       ├── config.ts             # Environment config, constants, MIME types
│       ├── s3-provider.ts        # S3-compatible provider (RustFS, MinIO, AWS)
│       ├── vercel-blob-provider.ts  # Vercel Blob provider
│       └── storage-provider.ts   # Factory — getStorageProvider()
└── app/
    └── api/
        └── storage/
            ├── route.ts          # GET  /api/storage — list files
            ├── upload/
            │   └── route.ts      # POST /api/storage/upload — upload file
            ├── download/
            │   └── [key]/
            │       └── route.ts  # GET  /api/storage/download/[key] — download file
            └── delete/
                └── route.ts      # POST /api/storage/delete — delete file(s)
```

## Setup Steps

### Step 1: Create `src/lib/storage/types.ts`

```typescript
export interface StorageFile {
  key: string;
  name: string;
  size: number;
  contentType: string;
  url: string;
  lastModified: Date;
}

export interface UploadOptions {
  contentType?: string;
  metadata?: Record<string, string>;
}

export interface ListOptions {
  prefix?: string;
  limit?: number;
  cursor?: string;
}

export interface ListResult {
  files: StorageFile[];
  cursor?: string;
  hasMore: boolean;
}

export interface StorageProvider {
  readonly name: string;
  list(options?: ListOptions): Promise<ListResult>;
  upload(key: string, data: Buffer, options?: UploadOptions): Promise<StorageFile>;
  delete(key: string): Promise<void>;
  download(key: string): Promise<Buffer>;
  getUrl(key: string, expiresInSeconds?: number): Promise<string>;
}

export type StorageErrorCode =
  | "FILE_NOT_FOUND"
  | "FILE_TOO_LARGE"
  | "UPLOAD_FAILED"
  | "DOWNLOAD_FAILED"
  | "DELETE_FAILED"
  | "CONFIGURATION_ERROR";

export class StorageError extends Error {
  constructor(
    public readonly code: StorageErrorCode,
    message: string,
    public readonly cause?: unknown
  ) {
    super(message);
    this.name = "StorageError";
  }

  static fileNotFound(key: string): StorageError {
    return new StorageError("FILE_NOT_FOUND", `File not found: ${key}`);
  }

  static fileTooLarge(size: number, maxSize: number): StorageError {
    return new StorageError(
      "FILE_TOO_LARGE",
      `File size ${size} exceeds maximum ${maxSize}`
    );
  }

  static uploadFailed(message: string, cause?: unknown): StorageError {
    return new StorageError("UPLOAD_FAILED", message, cause);
  }

  static configurationError(message: string): StorageError {
    return new StorageError("CONFIGURATION_ERROR", message);
  }
}
```

### Step 2: Create `src/lib/storage/config.ts`

```typescript
import { StorageError } from "./types";

export interface S3Config {
  endpoint: string;
  accessKey: string;
  secretKey: string;
  bucket: string;
  region: string;
  forcePathStyle: boolean;
}

export interface VercelBlobConfig {
  token: string;
}

export type StorageConfig =
  | { provider: "s3"; config: S3Config }
  | { provider: "vercel-blob"; config: VercelBlobConfig };

export const MAX_FILE_SIZE = 5 * 1024 * 1024 * 1024; // 5GB

export function getStorageConfig(): StorageConfig {
  if (process.env.BLOB_READ_WRITE_TOKEN) {
    return {
      provider: "vercel-blob",
      config: { token: process.env.BLOB_READ_WRITE_TOKEN },
    };
  }

  const endpoint = process.env.S3_ENDPOINT;
  const accessKey = process.env.S3_ACCESS_KEY;
  const secretKey = process.env.S3_SECRET_KEY;
  const bucket = process.env.S3_BUCKET;

  if (!endpoint || !accessKey || !secretKey || !bucket) {
    throw StorageError.configurationError(
      "No storage configured. Set BLOB_READ_WRITE_TOKEN (Vercel Blob) or S3_ENDPOINT + S3_ACCESS_KEY + S3_SECRET_KEY + S3_BUCKET (S3)."
    );
  }

  return {
    provider: "s3",
    config: {
      endpoint,
      accessKey,
      secretKey,
      bucket,
      region: process.env.S3_REGION || "us-east-1",
      forcePathStyle: true,
    },
  };
}

export function getContentTypeFromFilename(filename: string): string {
  const ext = filename.split(".").pop()?.toLowerCase();
  const types: Record<string, string> = {
    jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png",
    gif: "image/gif", webp: "image/webp", svg: "image/svg+xml",
    mp3: "audio/mpeg", wav: "audio/wav", ogg: "audio/ogg", m4a: "audio/mp4",
    mp4: "video/mp4", webm: "video/webm", mov: "video/quicktime",
    pdf: "application/pdf", txt: "text/plain", csv: "text/csv",
    json: "application/json", zip: "application/zip", gz: "application/gzip",
  };
  return types[ext || ""] || "application/octet-stream";
}

export function validateFileSize(size: number): void {
  if (size > MAX_FILE_SIZE) {
    throw StorageError.fileTooLarge(size, MAX_FILE_SIZE);
  }
}
```

### Step 3: Create `src/lib/storage/s3-provider.ts`

```typescript
import {
  S3Client,
  ListObjectsV2Command,
  GetObjectCommand,
  PutObjectCommand,
  DeleteObjectCommand,
  CreateMultipartUploadCommand,
  UploadPartCommand,
  CompleteMultipartUploadCommand,
  AbortMultipartUploadCommand,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import type { S3Config } from "./config";
import { getContentTypeFromFilename, validateFileSize } from "./config";
import type {
  StorageProvider,
  StorageFile,
  UploadOptions,
  ListOptions,
  ListResult,
} from "./types";
import { StorageError } from "./types";

const PART_SIZE = 5 * 1024 * 1024; // 5MB
const MULTIPART_THRESHOLD = 5 * 1024 * 1024; // 5MB

export class S3Provider implements StorageProvider {
  readonly name = "s3";
  private client: S3Client;
  private bucket: string;
  private endpoint: string;

  constructor(config: S3Config) {
    this.bucket = config.bucket;
    this.endpoint = config.endpoint;
    this.client = new S3Client({
      region: config.region,
      endpoint: config.endpoint,
      credentials: {
        accessKeyId: config.accessKey,
        secretAccessKey: config.secretKey,
      },
      forcePathStyle: config.forcePathStyle,
    });
  }

  async list(options?: ListOptions): Promise<ListResult> {
    try {
      const command = new ListObjectsV2Command({
        Bucket: this.bucket,
        Prefix: options?.prefix,
        MaxKeys: options?.limit ?? 100,
        ContinuationToken: options?.cursor,
      });
      const response = await this.client.send(command);
      const files: StorageFile[] = (response.Contents ?? []).map((item) => {
        const key = item.Key ?? "";
        return {
          key,
          name: key.split("/").pop() ?? key,
          size: item.Size ?? 0,
          contentType: getContentTypeFromFilename(key),
          url: `${this.endpoint}/${this.bucket}/${key}`,
          lastModified: item.LastModified ?? new Date(),
        };
      });
      return {
        files,
        cursor: response.NextContinuationToken,
        hasMore: response.IsTruncated ?? false,
      };
    } catch (error) {
      throw new StorageError("UPLOAD_FAILED", "Failed to list files", error);
    }
  }

  async upload(key: string, data: Buffer, options?: UploadOptions): Promise<StorageFile> {
    validateFileSize(data.length);
    const contentType = options?.contentType ?? getContentTypeFromFilename(key);

    if (data.length > MULTIPART_THRESHOLD) {
      return this.uploadMultipart(key, data, contentType, options);
    }
    return this.uploadSimple(key, data, contentType, options);
  }

  private async uploadSimple(
    key: string,
    data: Buffer,
    contentType: string,
    options?: UploadOptions
  ): Promise<StorageFile> {
    try {
      await this.client.send(
        new PutObjectCommand({
          Bucket: this.bucket,
          Key: key,
          Body: data,
          ContentType: contentType,
          Metadata: options?.metadata,
        })
      );
      return {
        key,
        name: key.split("/").pop() ?? key,
        size: data.length,
        contentType,
        url: `${this.endpoint}/${this.bucket}/${key}`,
        lastModified: new Date(),
      };
    } catch (error) {
      throw StorageError.uploadFailed(`Failed to upload ${key}`, error);
    }
  }

  private async uploadMultipart(
    key: string,
    data: Buffer,
    contentType: string,
    options?: UploadOptions
  ): Promise<StorageFile> {
    const createCmd = new CreateMultipartUploadCommand({
      Bucket: this.bucket,
      Key: key,
      ContentType: contentType,
      Metadata: options?.metadata,
    });
    const { UploadId } = await this.client.send(createCmd);
    if (!UploadId) throw StorageError.uploadFailed("No upload ID returned");

    try {
      const totalParts = Math.ceil(data.length / PART_SIZE);
      const parts: { PartNumber: number; ETag: string }[] = [];

      for (let i = 0; i < totalParts; i++) {
        const start = i * PART_SIZE;
        const end = Math.min(start + PART_SIZE, data.length);
        const response = await this.client.send(
          new UploadPartCommand({
            Bucket: this.bucket,
            Key: key,
            UploadId,
            PartNumber: i + 1,
            Body: data.subarray(start, end),
          })
        );
        if (!response.ETag) throw new Error("No ETag for part");
        parts.push({ PartNumber: i + 1, ETag: response.ETag });
      }

      await this.client.send(
        new CompleteMultipartUploadCommand({
          Bucket: this.bucket,
          Key: key,
          UploadId,
          MultipartUpload: { Parts: parts },
        })
      );

      return {
        key,
        name: key.split("/").pop() ?? key,
        size: data.length,
        contentType,
        url: `${this.endpoint}/${this.bucket}/${key}`,
        lastModified: new Date(),
      };
    } catch (error) {
      await this.client
        .send(new AbortMultipartUploadCommand({ Bucket: this.bucket, Key: key, UploadId }))
        .catch(() => {});
      throw StorageError.uploadFailed(`Multipart upload failed for ${key}`, error);
    }
  }

  async delete(key: string): Promise<void> {
    try {
      await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
    } catch (error) {
      throw new StorageError("DELETE_FAILED", `Failed to delete ${key}`, error);
    }
  }

  async download(key: string): Promise<Buffer> {
    try {
      const response = await this.client.send(
        new GetObjectCommand({ Bucket: this.bucket, Key: key })
      );
      if (!response.Body) throw StorageError.fileNotFound(key);
      const bytes = await response.Body.transformToByteArray();
      return Buffer.from(bytes);
    } catch (error) {
      if (error instanceof StorageError) throw error;
      throw new StorageError("DOWNLOAD_FAILED", `Failed to download ${key}`, error);
    }
  }

  async getUrl(key: string, expiresInSeconds = 3600): Promise<string> {
    const command = new GetObjectCommand({ Bucket: this.bucket, Key: key });
    return getSignedUrl(this.client, command, { expiresIn: expiresInSeconds });
  }
}
```

### Step 4: Create `src/lib/storage/vercel-blob-provider.ts`

```typescript
import { put, del, list } from "@vercel/blob";
import type { VercelBlobConfig } from "./config";
import { getContentTypeFromFilename, validateFileSize } from "./config";
import type {
  StorageProvider,
  StorageFile,
  UploadOptions,
  ListOptions,
  ListResult,
} from "./types";
import { StorageError } from "./types";

export class VercelBlobProvider implements StorageProvider {
  readonly name = "vercel-blob";
  private token: string;

  constructor(config: VercelBlobConfig) {
    this.token = config.token;
  }

  async list(options?: ListOptions): Promise<ListResult> {
    try {
      const response = await list({
        token: this.token,
        prefix: options?.prefix,
        limit: options?.limit ?? 100,
        cursor: options?.cursor,
      });
      const files: StorageFile[] = response.blobs.map((blob) => ({
        key: blob.pathname,
        name: blob.pathname.split("/").pop() ?? blob.pathname,
        size: blob.size,
        contentType: getContentTypeFromFilename(blob.pathname),
        url: blob.url,
        lastModified: new Date(blob.uploadedAt),
      }));
      return {
        files,
        cursor: response.cursor,
        hasMore: response.hasMore,
      };
    } catch (error) {
      throw new StorageError("UPLOAD_FAILED", "Failed to list files", error);
    }
  }

  async upload(key: string, data: Buffer, options?: UploadOptions): Promise<StorageFile> {
    validateFileSize(data.length);
    const contentType = options?.contentType ?? getContentTypeFromFilename(key);

    try {
      const result = await put(key, data, {
        token: this.token,
        access: "public",
        contentType,
        multipart: data.length > 5 * 1024 * 1024,
      });
      return {
        key: result.pathname,
        name: result.pathname.split("/").pop() ?? result.pathname,
        size: data.length,
        contentType: result.contentType,
        url: result.url,
        lastModified: new Date(),
      };
    } catch (error) {
      throw StorageError.uploadFailed(`Failed to upload ${key}`, error);
    }
  }

  async delete(key: string): Promise<void> {
    try {
      const response = await list({ token: this.token, prefix: key, limit: 1 });
      const blob = response.blobs.find((b) => b.pathname === key);
      if (!blob) return;
      await del(blob.url, { token: this.token });
    } catch (error) {
      throw new StorageError("DELETE_FAILED", `Failed to delete ${key}`, error);
    }
  }

  async download(key: string): Promise<Buffer> {
    try {
      const response = await list({ token: this.token, prefix: key, limit: 1 });
      const blob = response.blobs.find((b) => b.pathname === key);
      if (!blob) throw StorageError.fileNotFound(key);
      const fetchResponse = await fetch(blob.downloadUrl);
      if (!fetchResponse.ok) throw new Error(`HTTP ${fetchResponse.status}`);
      return Buffer.from(await fetchResponse.arrayBuffer());
    } catch (error) {
      if (error instanceof StorageError) throw error;
      throw new StorageError("DOWNLOAD_FAILED", `Failed to download ${key}`, error);
    }
  }

  async getUrl(key: string, _expiresInSeconds = 3600): Promise<string> {
    const response = await list({ token: this.token, prefix: key, limit: 1 });
    const blob = response.blobs.find((b) => b.pathname === key);
    if (!blob) throw StorageError.fileNotFound(key);
    return blob.url;
  }
}
```

### Step 5: Create `src/lib/storage/storage-provider.ts`

```typescript
import type { StorageProvider } from "./types";
import { getStorageConfig } from "./config";
import { S3Provider } from "./s3-provider";
import { VercelBlobProvider } from "./vercel-blob-provider";

let instance: StorageProvider | null = null;

export function getStorageProvider(): StorageProvider {
  if (instance) return instance;
  const config = getStorageConfig();
  switch (config.provider) {
    case "s3":
      instance = new S3Provider(config.config);
      break;
    case "vercel-blob":
      instance = new VercelBlobProvider(config.config);
      break;
  }
  return instance;
}

export function resetStorageProvider(): void {
  instance = null;
}

export type { StorageProvider, StorageFile, UploadOptions, ListOptions, ListResult } from "./types";
export { StorageError } from "./types";
export { MAX_FILE_SIZE, getContentTypeFromFilename } from "./config";
```

### Step 6: Create `src/app/api/storage/route.ts`

```typescript
import { type NextRequest, NextResponse } from "next/server";
import { getStorageProvider, type ListResult, StorageError } from "@/lib/storage/storage-provider";

export async function GET(
  request: NextRequest
): Promise<NextResponse<ListResult | { error: string }>> {
  try {
    const searchParams = request.nextUrl.searchParams;
    const prefix = searchParams.get("prefix") ?? undefined;
    const limitParam = searchParams.get("limit");
    const cursor = searchParams.get("cursor") ?? undefined;
    const limit = limitParam ? parseInt(limitParam, 10) : undefined;

    if (limit !== undefined && (Number.isNaN(limit) || limit < 1)) {
      return NextResponse.json({ error: "Invalid limit parameter" }, { status: 400 });
    }

    const storage = getStorageProvider();
    const result = await storage.list({ prefix, limit, cursor });
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof StorageError) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }
    return NextResponse.json({ error: "An unexpected error occurred" }, { status: 500 });
  }
}
```

### Step 7: Create `src/app/api/storage/upload/route.ts`

```typescript
import { type NextRequest, NextResponse } from "next/server";
import { getStorageProvider, type StorageFile, StorageError } from "@/lib/storage/storage-provider";

function generateFileKey(filename: string): string {
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(2, 8);
  const sanitized = filename.replace(/[^a-zA-Z0-9.-]/g, "_");
  return `uploads/${timestamp}-${random}-${sanitized}`;
}

export async function POST(
  request: NextRequest
): Promise<NextResponse<{ file: StorageFile } | { error: string }>> {
  try {
    const formData = await request.formData();
    const file = formData.get("file");

    if (!file || !(file instanceof File)) {
      return NextResponse.json({ error: "No file provided" }, { status: 400 });
    }

    const storage = getStorageProvider();
    const buffer = Buffer.from(await file.arrayBuffer());
    const key = generateFileKey(file.name);
    const contentType = file.type || "application/octet-stream";

    const result = await storage.upload(key, buffer, { contentType });
    return NextResponse.json({ file: result });
  } catch (error) {
    if (error instanceof StorageError) {
      const status = error.code === "FILE_TOO_LARGE" ? 413 : 500;
      return NextResponse.json({ error: error.message }, { status });
    }
    return NextResponse.json({ error: "An unexpected error occurred" }, { status: 500 });
  }
}
```

### Step 8: Create `src/app/api/storage/download/[key]/route.ts`

```typescript
import { type NextRequest, NextResponse } from "next/server";
import { getStorageProvider, StorageError } from "@/lib/storage/storage-provider";

type RouteParams = { params: Promise<{ key: string }> };

export async function GET(
  request: NextRequest,
  { params }: RouteParams
): Promise<NextResponse> {
  try {
    const { key } = await params;
    if (!key) {
      return NextResponse.json({ error: "File key is required" }, { status: 400 });
    }

    const decodedKey = decodeURIComponent(key);
    const storage = getStorageProvider();
    const buffer = await storage.download(decodedKey);

    const filename = decodedKey.split("/").pop() ?? decodedKey;
    const listResult = await storage.list({ prefix: decodedKey, limit: 1 });
    const meta = listResult.files.find((f) => f.key === decodedKey);
    const contentType = meta?.contentType ?? "application/octet-stream";

    const disposition = request.nextUrl.searchParams.get("download") === "true"
      ? "attachment"
      : "inline";

    return new NextResponse(new Uint8Array(buffer), {
      status: 200,
      headers: {
        "Content-Type": contentType,
        "Content-Disposition": `${disposition}; filename="${encodeURIComponent(filename)}"`,
        "Content-Length": buffer.length.toString(),
        "Cache-Control": "private, max-age=3600",
      },
    });
  } catch (error) {
    if (error instanceof StorageError && error.code === "FILE_NOT_FOUND") {
      return NextResponse.json({ error: "File not found" }, { status: 404 });
    }
    return NextResponse.json({ error: "An unexpected error occurred" }, { status: 500 });
  }
}
```

### Step 9: Create `src/app/api/storage/delete/route.ts`

```typescript
import { type NextRequest, NextResponse } from "next/server";
import { getStorageProvider, StorageError } from "@/lib/storage/storage-provider";

type DeleteBody = { key: string } | { keys: string[] };

function isValidBody(body: unknown): body is DeleteBody {
  if (typeof body !== "object" || body === null) return false;
  const obj = body as Record<string, unknown>;
  if ("key" in obj) return typeof obj.key === "string" && obj.key.trim() !== "";
  if ("keys" in obj) {
    return (
      Array.isArray(obj.keys) &&
      obj.keys.length > 0 &&
      obj.keys.every((k) => typeof k === "string" && k.trim() !== "")
    );
  }
  return false;
}

export async function POST(
  request: NextRequest
): Promise<NextResponse<{ success: true } | { error: string }>> {
  try {
    const body: unknown = await request.json();
    if (!isValidBody(body)) {
      return NextResponse.json(
        { error: 'Provide { key: string } or { keys: string[] }' },
        { status: 400 }
      );
    }

    const storage = getStorageProvider();

    if ("key" in body) {
      await storage.delete(body.key);
    } else {
      if (body.keys.length > 100) {
        return NextResponse.json({ error: "Batch limited to 100 files" }, { status: 400 });
      }
      await Promise.all(body.keys.map((k) => storage.delete(k)));
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    if (error instanceof StorageError) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }
    return NextResponse.json({ error: "An unexpected error occurred" }, { status: 500 });
  }
}
```

## Usage

```typescript
import { getStorageProvider } from "@/lib/storage/storage-provider";

const storage = getStorageProvider();

// Upload
const file = await storage.upload("images/photo.jpg", buffer, {
  contentType: "image/jpeg",
});

// List
const { files } = await storage.list({ prefix: "images/" });

// Download
const data = await storage.download("images/photo.jpg");

// Delete
await storage.delete("images/photo.jpg");

// Get presigned URL (S3) or public URL (Vercel Blob)
const url = await storage.getUrl("images/photo.jpg", 3600);
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/storage?prefix=&limit=&cursor=` | List files |
| POST | `/api/storage/upload` | Upload file (FormData with `file` field) |
| GET | `/api/storage/download/[key]?download=true` | Download file |
| POST | `/api/storage/delete` | Delete file(s) — `{ key }` or `{ keys }` |
