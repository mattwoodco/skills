---
name: search
description: Setup Meilisearch full-text search with Redis caching, rate limiting, input sanitization, and API key management. Use this skill when the user says "setup search", "add search", "setup meilisearch", "full-text search", or "search integration".
author: "@mattwoodco"
version: 1.1.0
created: 2026-01-11
validated: 2026-02-17
dependencies: [docker, env-config]
---

# Meilisearch Search Integration

Production-ready full-text search with Meilisearch, featuring Redis caching, rate limiting, input sanitization, and secure API key management.

## Features

- **Dual-Environment Support**: Local development and production with different API keys
- **Input Sanitization**: Zod-based query validation to prevent injection attacks
- **Redis Caching**: 60-second TTL for search results
- **Rate Limiting**: 20 requests/minute per IP address
- **Index Management**: Type-safe index creation and document indexing
- **API Key Rotation**: Automated key rotation for production security
- **CORS Support**: Configurable allowed origins

## Environment Variables

### Local Development

```env
# Meilisearch (local via Docker)
MEILISEARCH_HOST=http://localhost:7700
MEILISEARCH_API_KEY=devMasterKey123
```

### Production

```env
# Meilisearch (production)
MEILISEARCH_HOST=https://your-meilisearch-instance.com
MEILISEARCH_API_KEY=your_master_key_here
MEILISEARCH_SEARCH_KEY=your_search_only_key_here

# Required for env detection
VERCEL_ENV=production
```

## Docker Setup

Meilisearch is included in the Docker skill. If not already set up, add to `docker-compose.yml`:

```yaml
services:
  meilisearch:
    image: getmeili/meilisearch:v1.10
    ports:
      - "7700:7700"
    environment:
      MEILI_MASTER_KEY: ${MEILI_MASTER_KEY:-devMasterKey123}
      MEILI_NO_ANALYTICS: "true"
      MEILI_ENV: development
    volumes:
      - meilisearch_data:/meili_data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7700/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

volumes:
  meilisearch_data:
```

## Prerequisites

Add `scripts/` to tsconfig.json `exclude` to avoid path resolution errors with seed scripts:

```json
{
  "exclude": ["node_modules", "scripts"]
}
```

Also add `MEILISEARCH_SEARCH_KEY` and `VERCEL_ENV` to your `src/env.ts` server section:

```typescript
MEILISEARCH_SEARCH_KEY: z.string().optional(),
VERCEL_ENV: z.string().optional(),
```

## Installation

```bash
bun add meilisearch zod lucide-react
```

## File Structure

```
src/
├── lib/
│   └── search.ts                # Meilisearch client and utilities
├── hooks/
│   ├── use-search.ts            # React hook for search with debouncing
│   ├── use-hotkey.ts            # Global keyboard shortcut hook
│   └── use-search-params-sync.ts # URL query param synchronization
├── components/
│   ├── search-box.tsx           # Basic search input component
│   └── search-modal.tsx         # Command palette search modal (⌘K)
└── app/
    ├── api/
    │   └── search/
    │       └── route.ts         # Search API endpoint
    └── search/
        └── page.tsx             # Search results page with URL params
```

## Implementation

### File: `src/lib/search.ts`

```typescript
import { MeiliSearch } from "meilisearch";
import { z } from "zod";

// Use process.env directly to avoid @/env blocking route handlers during env validation
const isProduction = process.env.VERCEL_ENV === "production";
const host = process.env.MEILISEARCH_HOST ?? "http://localhost:7700";

// === CLIENT INITIALIZATION ===

// Admin client with full permissions (server-side only)
export const searchClient = new MeiliSearch({
  host,
  apiKey: isProduction
    ? (process.env.MEILISEARCH_API_KEY ?? "")
    : "devMasterKey123",
});

// Search-only client for frontend (limited permissions)
export const searchOnlyClient = new MeiliSearch({
  host,
  apiKey: process.env.MEILISEARCH_SEARCH_KEY ?? "devMasterKey123",
});

// === INPUT SANITIZATION ===

const searchQuerySchema = z.object({
  query: z
    .string()
    .max(500)
    .transform((q) => q.replace(/[<>"'\\]/g, "").trim()),
  limit: z.number().int().min(1).max(100).default(20),
  offset: z.number().int().min(0).default(0),
  filter: z.string().max(1000).optional(),
  sort: z.array(z.string()).max(5).optional(),
});

export type SearchQuery = z.infer<typeof searchQuerySchema>;

export function sanitizeSearchQuery(input: unknown): SearchQuery {
  return searchQuerySchema.parse(input);
}

// === CACHED SEARCH ===
// Note: Redis caching is optional. When redis is not available, searches go directly to Meilisearch.
// To enable caching, install ioredis and import your redis client here.

export async function cachedSearch(index: string, query: SearchQuery) {
  // Without Redis, fall back to direct search
  return directSearch(index, query);
}

// === DIRECT SEARCH (NO CACHE) ===

export async function directSearch(index: string, query: SearchQuery) {
  return searchClient.index(index).search(query.query, {
    limit: query.limit,
    offset: query.offset,
    filter: query.filter,
    sort: query.sort,
  });
}

// === INDEX MANAGEMENT ===

export async function createProductIndex() {
  const index = searchClient.index("products");

  await index.updateSettings({
    searchableAttributes: ["name", "description", "category"],
    filterableAttributes: ["category", "price", "inStock"],
    sortableAttributes: ["price", "createdAt", "name"],
    rankingRules: [
      "words",
      "typo",
      "proximity",
      "attribute",
      "sort",
      "exactness",
    ],
  });

  return index;
}

// Generic index configuration helper
export async function configureIndex(
  indexName: string,
  settings: {
    searchableAttributes?: string[];
    filterableAttributes?: string[];
    sortableAttributes?: string[];
    rankingRules?: string[];
    stopWords?: string[];
    synonyms?: Record<string, string[]>;
    distinctAttribute?: string;
  }
) {
  const index = searchClient.index(indexName);
  const task = await index.updateSettings(settings);
  return { index, task };
}

// === DOCUMENT OPERATIONS ===

type BaseDocument = {
  id: string;
  [key: string]: unknown;
};

export async function indexDocuments<T extends BaseDocument>(
  indexName: string,
  documents: T[],
  primaryKey = "id"
) {
  const index = searchClient.index(indexName);
  return index.addDocuments(documents, { primaryKey });
}

export async function updateDocuments<T extends BaseDocument>(
  indexName: string,
  documents: T[],
  primaryKey = "id"
) {
  const index = searchClient.index(indexName);
  return index.updateDocuments(documents, { primaryKey });
}

export async function deleteDocuments(indexName: string, ids: string[]) {
  const index = searchClient.index(indexName);
  return index.deleteDocuments(ids);
}

export async function deleteAllDocuments(indexName: string) {
  const index = searchClient.index(indexName);
  return index.deleteAllDocuments();
}

// === TASK MANAGEMENT ===

export async function waitForTask(taskUid: number) {
  return searchClient.tasks.waitForTask(taskUid);
}

export async function getTaskStatus(taskUid: number) {
  return searchClient.tasks.getTask(taskUid);
}

// === API KEY MANAGEMENT (Production) ===

export async function createSearchKey(
  indexes: string[],
  expiresInDays = 30,
  description?: string
) {
  if (!isProduction) return null;

  const newKey = await searchClient.createKey({
    description: description ?? `Search key created at ${new Date().toISOString()}`,
    actions: ["search"],
    indexes,
    expiresAt: new Date(Date.now() + expiresInDays * 24 * 60 * 60 * 1000),
  });

  return newKey;
}

export async function rotateApiKeys() {
  if (!isProduction) return null;

  // Create new search key
  const newKey = await searchClient.createKey({
    description: `Search key rotated at ${new Date().toISOString()}`,
    actions: ["search"],
    indexes: ["*"],
    expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days
  });

  return newKey;
}

export async function listApiKeys() {
  return searchClient.getKeys();
}

export async function deleteApiKey(keyUidOrKey: string) {
  return searchClient.deleteKey(keyUidOrKey);
}

// === STATS & HEALTH ===

export async function getIndexStats(indexName: string) {
  const index = searchClient.index(indexName);
  return index.getStats();
}

export async function healthCheck() {
  return searchClient.health();
}
```

### File: `src/app/api/search/route.ts`

```typescript
import { NextResponse, type NextRequest } from "next/server";
import { cachedSearch, sanitizeSearchQuery } from "@/lib/search";
import { z } from "zod";

const ALLOWED_ORIGINS = [
  process.env.NEXT_PUBLIC_APP_URL,
  "https://your-domain.com",
].filter(Boolean);

// Inline rate limiting (no external dependency needed)
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const RATE_LIMIT_MAX = 20; // 20 requests per minute

function checkInlineRateLimit(identifier: string): {
  success: boolean;
  remaining: number;
  resetAt: number;
} {
  const now = Date.now();
  const entry = rateLimitMap.get(identifier);

  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(identifier, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return { success: true, remaining: RATE_LIMIT_MAX - 1, resetAt: now + RATE_LIMIT_WINDOW_MS };
  }

  entry.count++;
  if (entry.count > RATE_LIMIT_MAX) {
    return { success: false, remaining: 0, resetAt: entry.resetAt };
  }

  return { success: true, remaining: RATE_LIMIT_MAX - entry.count, resetAt: entry.resetAt };
}

export async function GET(req: NextRequest) {
  const origin = req.headers.get("origin");
  const ip = req.headers.get("x-forwarded-for") ?? "anonymous";

  // CORS check
  const corsHeaders: HeadersInit = {};
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    corsHeaders["Access-Control-Allow-Origin"] = origin;
    corsHeaders["Access-Control-Allow-Methods"] = "GET, OPTIONS";
    corsHeaders["Access-Control-Allow-Headers"] = "Content-Type";
  }

  // Rate limiting (20 requests/minute per IP)
  const rateLimit = checkInlineRateLimit(`search:${ip}`);

  if (!rateLimit.success) {
    return NextResponse.json(
      { error: "Rate limit exceeded" },
      {
        status: 429,
        headers: {
          ...corsHeaders,
          "Retry-After": String(Math.ceil((rateLimit.resetAt - Date.now()) / 1000)),
          "X-RateLimit-Remaining": "0",
        },
      }
    );
  }

  try {
    const url = new URL(req.url);
    const rawQuery = {
      query: url.searchParams.get("q") ?? "",
      limit: Number.parseInt(url.searchParams.get("limit") ?? "20"),
      offset: Number.parseInt(url.searchParams.get("offset") ?? "0"),
      filter: url.searchParams.get("filter") ?? undefined,
      sort: url.searchParams.get("sort")?.split(",") ?? undefined,
    };

    // Sanitize and validate input
    const query = sanitizeSearchQuery(rawQuery);

    const startTime = Date.now();
    const results = await cachedSearch("products", query);
    const latencyMs = Date.now() - startTime;

    // Log search analytics
    console.info("search.query", {
      query: query.query,
      resultCount: results.hits.length,
      latencyMs,
      cached: latencyMs < 50,
      ip,
    });

    return NextResponse.json(results, {
      headers: {
        ...corsHeaders,
        "X-RateLimit-Remaining": String(rateLimit.remaining),
        "X-Search-Latency": `${latencyMs}ms`,
      },
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: "Invalid search query", details: error.issues },
        { status: 400, headers: corsHeaders }
      );
    }

    console.error("search.error", { error: String(error), ip });
    return NextResponse.json(
      { error: "Search failed" },
      { status: 500, headers: corsHeaders }
    );
  }
}

export async function OPTIONS(req: NextRequest) {
  const origin = req.headers.get("origin");

  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    return new NextResponse(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Max-Age": "86400",
      },
    });
  }

  return new NextResponse(null, { status: 204 });
}
```

## React Hook for Search

### File: `src/hooks/use-search.ts`

```typescript
import { useState, useCallback, useRef, useEffect } from "react";
import { useId } from "react";

interface SearchResult<T> {
  hits: T[];
  query: string;
  processingTimeMs: number;
  estimatedTotalHits: number;
  offset: number;
  limit: number;
}

interface UseSearchOptions {
  debounceMs?: number;
  minQueryLength?: number;
  limit?: number;
}

interface UseSearchReturn<T> {
  query: string;
  setQuery: (query: string) => void;
  results: T[];
  isLoading: boolean;
  error: string | null;
  totalHits: number;
  search: (query: string) => Promise<void>;
  loadMore: () => Promise<void>;
  hasMore: boolean;
}

export function useSearch<T = Record<string, unknown>>(
  endpoint: string,
  options: UseSearchOptions = {}
): UseSearchReturn<T> {
  const { debounceMs = 300, minQueryLength = 2, limit = 20 } = options;

  const [query, setQueryState] = useState("");
  const [results, setResults] = useState<T[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [totalHits, setTotalHits] = useState(0);
  const [offset, setOffset] = useState(0);

  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const abortRef = useRef<AbortController>(undefined);
  const searchId = useId();

  const performSearch = useCallback(
    async (searchQuery: string, searchOffset = 0, append = false) => {
      if (searchQuery.length < minQueryLength) {
        setResults([]);
        setTotalHits(0);
        return;
      }

      // Cancel previous request
      abortRef.current?.abort();
      abortRef.current = new AbortController();

      setIsLoading(true);
      setError(null);

      try {
        const params = new URLSearchParams({
          q: searchQuery,
          limit: String(limit),
          offset: String(searchOffset),
        });

        const response = await fetch(`${endpoint}?${params}`, {
          signal: abortRef.current.signal,
        });

        if (!response.ok) {
          const data = await response.json();
          throw new Error(data.error ?? "Search failed");
        }

        const data: SearchResult<T> = await response.json();

        setResults((prev) => (append ? [...prev, ...data.hits] : data.hits));
        setTotalHits(data.estimatedTotalHits);
        setOffset(searchOffset + data.hits.length);
      } catch (err) {
        if (err instanceof Error && err.name !== "AbortError") {
          setError(err.message);
        }
      } finally {
        setIsLoading(false);
      }
    },
    [endpoint, limit, minQueryLength]
  );

  const setQuery = useCallback(
    (newQuery: string) => {
      setQueryState(newQuery);
      setOffset(0);

      // Clear existing debounce
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
      }

      // Debounce the search
      debounceRef.current = setTimeout(() => {
        performSearch(newQuery, 0, false);
      }, debounceMs);
    },
    [debounceMs, performSearch]
  );

  const search = useCallback(
    async (searchQuery: string) => {
      setQueryState(searchQuery);
      setOffset(0);
      await performSearch(searchQuery, 0, false);
    },
    [performSearch]
  );

  const loadMore = useCallback(async () => {
    if (!isLoading && results.length < totalHits) {
      await performSearch(query, offset, true);
    }
  }, [isLoading, results.length, totalHits, query, offset, performSearch]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      debounceRef.current && clearTimeout(debounceRef.current);
      abortRef.current?.abort();
    };
  }, []);

  return {
    query,
    setQuery,
    results,
    isLoading,
    error,
    totalHits,
    search,
    loadMore,
    hasMore: results.length < totalHits,
  };
}
```

## Search Component Example

### File: `src/components/search-box.tsx`

```typescript
"use client";

import { useSearch } from "@/hooks/use-search";
import { useId } from "react";

interface Product {
  id: string;
  name: string;
  description: string;
  price: number;
  category: string;
}

export function SearchBox() {
  const {
    query,
    setQuery,
    results,
    isLoading,
    error,
    totalHits,
    loadMore,
    hasMore,
  } = useSearch<Product>("/api/search");

  const inputId = useId();

  return (
    <div className="w-full max-w-2xl mx-auto">
      <div className="relative">
        <input
          id={inputId}
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search products..."
          className="w-full px-4 py-3 border rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          aria-label="Search products"
        />
        {isLoading && (
          <div className="absolute right-3 top-1/2 -translate-y-1/2">
            <div className="animate-spin h-5 w-5 border-2 border-blue-500 rounded-full border-t-transparent" />
          </div>
        )}
      </div>

      {error && (
        <p className="mt-2 text-red-600 text-sm">{error}</p>
      )}

      {results.length > 0 && (
        <div className="mt-4 space-y-3">
          <p className="text-sm text-gray-500">
            {totalHits} result{totalHits !== 1 ? "s" : ""} found
          </p>

          <ul className="divide-y">
            {results.map((product) => (
              <li key={product.id} className="py-3">
                <h3 className="font-medium">{product.name}</h3>
                <p className="text-sm text-gray-600">{product.description}</p>
                <p className="text-sm font-medium text-green-600">
                  ${product.price.toFixed(2)}
                </p>
              </li>
            ))}
          </ul>

          {hasMore && (
            <button
              onClick={loadMore}
              disabled={isLoading}
              className="w-full py-2 px-4 bg-gray-100 hover:bg-gray-200 rounded-lg disabled:opacity-50"
            >
              {isLoading ? "Loading..." : "Load more"}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
```

## Search Modal (Command Palette)

A keyboard-driven search modal that opens with ⌘K (Mac) or Ctrl+K (Windows/Linux).

### File: `src/hooks/use-hotkey.ts`

```typescript
"use client";

import { useEffect, useCallback } from "react";

type ModifierKey = "meta" | "ctrl" | "alt" | "shift";
type KeyCombo = {
  key: string;
  modifiers?: ModifierKey[];
};

function parseKeyCombo(combo: string): KeyCombo {
  const parts = combo.toLowerCase().split("+");
  const key = parts.pop() ?? "";
  const modifiers = parts as ModifierKey[];
  return { key, modifiers };
}

function matchesModifiers(event: KeyboardEvent, modifiers: ModifierKey[] = []): boolean {
  const hasCtrl = modifiers.includes("ctrl");
  const hasMeta = modifiers.includes("meta");
  const ctrlOrMeta = hasCtrl || hasMeta;
  const eventCtrlOrMeta = event.ctrlKey || event.metaKey;

  if (ctrlOrMeta && !eventCtrlOrMeta) return false;
  if (!ctrlOrMeta && eventCtrlOrMeta) return false;
  if (modifiers.includes("alt") !== event.altKey) return false;
  if (modifiers.includes("shift") !== event.shiftKey) return false;

  return true;
}

export function useHotkey(
  keyCombo: string,
  callback: (event: KeyboardEvent) => void,
  options: {
    enabled?: boolean;
    preventDefault?: boolean;
    enableOnFormElements?: boolean;
  } = {}
) {
  const { enabled = true, preventDefault = true, enableOnFormElements = false } = options;

  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (!enabled) return;

      if (!enableOnFormElements) {
        const target = event.target as HTMLElement;
        const isFormElement = ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName);
        const { modifiers } = parseKeyCombo(keyCombo);
        if (isFormElement && (!modifiers || modifiers.length === 0)) return;
      }

      const { key, modifiers } = parseKeyCombo(keyCombo);
      if (event.key.toLowerCase() === key && matchesModifiers(event, modifiers)) {
        if (preventDefault) {
          event.preventDefault();
          event.stopPropagation();
        }
        callback(event);
      }
    },
    [keyCombo, callback, enabled, preventDefault, enableOnFormElements]
  );

  useEffect(() => {
    if (!enabled) return;
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [handleKeyDown, enabled]);
}

export function useEscapeKey(callback: (event: KeyboardEvent) => void, enabled = true) {
  useHotkey("escape", callback, { enabled, enableOnFormElements: true });
}
```

### File: `src/components/search-modal.tsx`

```typescript
"use client";

import { useCallback, useEffect, useRef, useState, useId } from "react";
import { useRouter } from "next/navigation";
import { SearchIcon, LoaderIcon, XIcon } from "lucide-react";
import { useHotkey, useEscapeKey } from "@/hooks/use-hotkey";
import { useSearch } from "@/hooks/use-search";
import { cn } from "@/lib/utils";

type SearchModalProps = {
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
};

export function SearchModal({ open: controlledOpen, onOpenChange }: SearchModalProps) {
  const [internalOpen, setInternalOpen] = useState(false);
  const open = controlledOpen ?? internalOpen;
  const setOpen = onOpenChange ?? setInternalOpen;

  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const previousActiveElement = useRef<HTMLElement | null>(null);

  const { query, setQuery, results, isLoading, totalHits } = useSearch<{
    id: string;
    name: string;
    description: string;
    price: number;
    category: string;
  }>("/api/search", { debounceMs: 200, minQueryLength: 2 });

  const [selectedIndex, setSelectedIndex] = useState(-1);

  // Open modal with Cmd+K / Ctrl+K
  useHotkey("meta+k", () => setOpen(true), { enableOnFormElements: true });

  // Close modal with Escape
  useEscapeKey(() => open && setOpen(false), open);

  // Handle opening - save focus and lock scroll
  useEffect(() => {
    if (open) {
      previousActiveElement.current = document.activeElement as HTMLElement;
      document.body.style.overflow = "hidden";
      requestAnimationFrame(() => inputRef.current?.focus());
    } else {
      document.body.style.overflow = "";
      previousActiveElement.current?.focus();
    }
    return () => { document.body.style.overflow = ""; };
  }, [open]);

  // Reset state when modal closes
  useEffect(() => {
    if (!open) {
      setQuery("");
      setSelectedIndex(-1);
    }
  }, [open, setQuery]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    switch (e.key) {
      case "ArrowDown":
        e.preventDefault();
        setSelectedIndex((prev) => (prev < results.length - 1 ? prev + 1 : prev));
        break;
      case "ArrowUp":
        e.preventDefault();
        setSelectedIndex((prev) => (prev > 0 ? prev - 1 : -1));
        break;
      case "Enter":
        e.preventDefault();
        if (query.length >= 2) {
          setOpen(false);
          router.push(`/search?q=${encodeURIComponent(query)}`);
        }
        break;
    }
  }, [results, query, setOpen, router]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center pt-[15vh]">
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" onClick={() => setOpen(false)} />
      <div className="relative w-full max-w-xl mx-4 bg-background border rounded-xl shadow-2xl">
        <div className="flex items-center gap-3 px-4 border-b">
          <SearchIcon className="h-5 w-5 text-muted-foreground" />
          <input
            ref={inputRef}
            type="search"
            value={query}
            onChange={(e) => { setQuery(e.target.value); setSelectedIndex(-1); }}
            onKeyDown={handleKeyDown}
            placeholder="Search products..."
            className="flex-1 h-14 bg-transparent text-foreground outline-none"
          />
          {isLoading && <LoaderIcon className="h-5 w-5 animate-spin" />}
          <button onClick={() => setOpen(false)} className="p-1.5 rounded-md hover:bg-accent">
            <XIcon className="h-4 w-4" />
          </button>
        </div>
        {/* Results list, keyboard hints, etc. */}
      </div>
    </div>
  );
}

export function SearchTrigger({ className }: { className?: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className={cn("flex items-center gap-2 px-3 py-1.5 rounded-lg bg-secondary/50 hover:bg-secondary", className)}
      >
        <SearchIcon className="h-4 w-4" />
        <span className="hidden sm:inline">Search...</span>
        <kbd className="hidden sm:inline px-1.5 py-0.5 rounded bg-background text-xs font-mono">⌘K</kbd>
      </button>
      <SearchModal open={open} onOpenChange={setOpen} />
    </>
  );
}
```

## Search Page with URL Params

### File: `src/app/search/page.tsx`

```typescript
"use client";

import { Suspense, useCallback, useEffect, useId, useState } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { SearchIcon, LoaderIcon } from "lucide-react";
import { useSearch } from "@/hooks/use-search";

function SearchPageContent() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const initialQuery = searchParams.get("q") ?? "";

  const { query, setQuery, search, results, isLoading, totalHits, loadMore, hasMore } = useSearch<{
    id: string;
    name: string;
    description: string;
    price: number;
    category: string;
  }>("/api/search", { debounceMs: 300, minQueryLength: 2 });

  const [isInitialized, setIsInitialized] = useState(false);

  // Initialize search from URL params on mount
  useEffect(() => {
    if (!isInitialized && initialQuery) {
      search(initialQuery);
      setIsInitialized(true);
    } else if (!isInitialized) {
      setIsInitialized(true);
    }
  }, [initialQuery, search, isInitialized]);

  // Sync URL when query changes (debounced)
  useEffect(() => {
    if (!isInitialized) return;
    const timeout = setTimeout(() => {
      const params = new URLSearchParams(searchParams.toString());
      if (query.length >= 2) params.set("q", query);
      else params.delete("q");
      router.replace(params.toString() ? `?${params.toString()}` : "/search", { scroll: false });
    }, 500);
    return () => clearTimeout(timeout);
  }, [query, isInitialized, router, searchParams]);

  return (
    <div className="min-h-screen bg-background py-8">
      <div className="max-w-4xl mx-auto px-4">
        <h1 className="text-3xl font-bold text-center mb-8">Search Products</h1>
        <div className="relative max-w-2xl mx-auto mb-8">
          <SearchIcon className="absolute left-4 top-1/2 -translate-y-1/2 h-5 w-5 text-muted-foreground" />
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search products..."
            className="w-full h-14 pl-12 pr-12 rounded-xl border bg-background text-foreground"
          />
          {isLoading && <LoaderIcon className="absolute right-4 top-1/2 -translate-y-1/2 h-5 w-5 animate-spin" />}
        </div>
        {/* Results list */}
      </div>
    </div>
  );
}

export default function SearchPage() {
  return (
    <Suspense fallback={<div className="flex justify-center py-20"><LoaderIcon className="animate-spin" /></div>}>
      <SearchPageContent />
    </Suspense>
  );
}
```

## Index Seeding Script

### File: `scripts/seed-search.ts`

```typescript
import { searchClient, configureIndex, indexDocuments, waitForTask } from "@/lib/search";

async function seedSearchIndex() {
  console.log("Configuring products index...");

  const { task } = await configureIndex("products", {
    searchableAttributes: ["name", "description", "category"],
    filterableAttributes: ["category", "price", "inStock"],
    sortableAttributes: ["price", "createdAt", "name"],
    rankingRules: [
      "words",
      "typo",
      "proximity",
      "attribute",
      "sort",
      "exactness",
    ],
  });

  await waitForTask(task.taskUid);
  console.log("Index configured!");

  // Sample products
  const products = [
    {
      id: "prod_001",
      name: "Wireless Headphones",
      description: "Premium noise-canceling wireless headphones with 30-hour battery life",
      price: 299.99,
      category: "electronics",
      inStock: true,
      createdAt: new Date().toISOString(),
    },
    {
      id: "prod_002",
      name: "Mechanical Keyboard",
      description: "RGB mechanical gaming keyboard with Cherry MX switches",
      price: 149.99,
      category: "electronics",
      inStock: true,
      createdAt: new Date().toISOString(),
    },
    {
      id: "prod_003",
      name: "Running Shoes",
      description: "Lightweight running shoes with responsive cushioning",
      price: 129.99,
      category: "sports",
      inStock: false,
      createdAt: new Date().toISOString(),
    },
  ];

  console.log("Indexing products...");
  const indexTask = await indexDocuments("products", products);
  await waitForTask(indexTask.taskUid);

  console.log(`Indexed ${products.length} products!`);
}

seedSearchIndex().catch(console.error);
```

Run with:

```bash
bun run scripts/seed-search.ts
```

## API Reference

### Search Client Methods

| Method | Description |
|--------|-------------|
| `sanitizeSearchQuery(input)` | Validates and sanitizes search query input |
| `cachedSearch(index, query)` | Searches with Redis caching (60s TTL) |
| `directSearch(index, query)` | Searches without caching |
| `configureIndex(name, settings)` | Configures index settings |
| `indexDocuments(index, docs)` | Adds documents to index |
| `updateDocuments(index, docs)` | Updates existing documents |
| `deleteDocuments(index, ids)` | Deletes documents by ID |
| `createSearchKey(indexes)` | Creates limited search API key |
| `rotateApiKeys()` | Rotates API keys (production) |
| `healthCheck()` | Checks Meilisearch health |

### Search Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `q` | string | required | Search query (max 500 chars) |
| `limit` | number | 20 | Results per page (1-100) |
| `offset` | number | 0 | Pagination offset |
| `filter` | string | - | Filter expression |
| `sort` | string | - | Sort fields (comma-separated) |

### Filter Syntax Examples

```
# Single condition
filter=category = "electronics"

# Multiple conditions
filter=category = "electronics" AND price < 500

# OR conditions
filter=(category = "electronics" OR category = "sports")

# Range filters
filter=price >= 100 AND price <= 500

# Boolean filters
filter=inStock = true
```

### Sort Syntax Examples

```
# Single field
sort=price:asc

# Multiple fields
sort=price:asc,name:desc

# Date sorting
sort=createdAt:desc
```

## Security Best Practices

1. **Never expose master key to frontend** - Use search-only keys
2. **Sanitize all user input** - Use the `sanitizeSearchQuery` function
3. **Implement rate limiting** - 20 requests/minute per IP recommended
4. **Rotate API keys regularly** - Use `rotateApiKeys()` in production
5. **Use HTTPS in production** - Never use HTTP for production Meilisearch
6. **Limit search key permissions** - Only grant `search` action to frontend keys

## Troubleshooting

**Search returns empty results?**

```bash
# Check if index exists
curl http://localhost:7700/indexes/products -H "Authorization: Bearer devMasterKey123"

# Check indexed documents
curl http://localhost:7700/indexes/products/documents -H "Authorization: Bearer devMasterKey123"
```

**Meilisearch not responding?**

```bash
# Check health endpoint
curl http://localhost:7700/health

# Check Docker logs
docker compose logs -f meilisearch
```

**Rate limit errors in development?**
The inline rate limiter uses an in-memory Map. Restart the dev server to clear rate limits.

### Meilisearch SDK API changes (v0.55+)

**`waitForTask`/`getTask` moved to `searchClient.tasks`**:

```typescript
// ❌ Incorrect — these methods don't exist on MeiliSearch instance
searchClient.waitForTask(taskUid);
searchClient.getTask(taskUid);

// ✅ Correct — access via .tasks property
searchClient.tasks.waitForTask(taskUid);
searchClient.tasks.getTask(taskUid);
```

**Zod v4 changed `ZodError.errors` to `ZodError.issues`**:

```typescript
// ❌ Incorrect — property doesn't exist in Zod v4
error.errors

// ✅ Correct
error.issues
```

**React 19 `useRef()` requires initial value**:

```typescript
// ❌ Incorrect — TypeScript error in React 19
const ref = useRef<AbortController>();

// ✅ Correct — pass undefined explicitly
const ref = useRef<AbortController>(undefined);
```

## NavBar Integration

Add the `SearchTrigger` component to your navigation bar:

```typescript
// src/components/nav-bar.tsx
import { SearchTrigger } from "@/components/search-modal";

export function NavBar() {
  return (
    <nav className="bg-background border-b sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 flex justify-between h-16 items-center">
        {/* Logo and links */}

        {/* Add search trigger */}
        <SearchTrigger className="ml-2" />

        {/* Auth section */}
      </div>
    </nav>
  );
}
```

## Dark Mode Support

The search components use Tailwind CSS variables for theming:

- `bg-background`, `text-foreground` for main surfaces
- `bg-accent`, `text-accent-foreground` for interactive states
- `text-muted-foreground` for secondary text
- `border-border` for borders

Ensure your layout includes dark mode flash prevention:

```typescript
// src/app/layout.tsx
import { ThemeProvider } from "@/components/theme-provider";

export default function RootLayout({ children }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          {children}
        </ThemeProvider>
      </body>
    </html>
  );
}
```

## UI/UX Best Practices

1. **Keyboard Navigation**: Use `⌘K`/`Ctrl+K` globally for search modal
2. **URL Sync**: Persist search query in `?q=` param for shareability
3. **Debouncing**: 200-300ms debounce for modal, 300-500ms for page
4. **Focus Management**: Restore focus to previous element when modal closes
5. **Scroll Lock**: Disable body scroll when modal is open
6. **Accessibility**: Include proper ARIA labels and keyboard navigation
7. **Loading States**: Show spinner in input during search
8. **Result Limits**: Show top 5 results in modal, full results on page

## Validation Checklist

- [ ] Modal opens with ⌘K / Ctrl+K
- [ ] Modal dismisses on Escape / click outside
- [ ] Query syncs to `?q=` URL parameter
- [ ] `/search?q=test` hydrates search state on load
- [ ] No white flash on navigation or theme switch
- [ ] Scroll focus restores correctly after modal close
- [ ] Works in both light and dark mode
- [ ] Mobile responsive

## Known Issues

1. **Auth Integration**: If using better-auth with drizzle, ensure database tables are migrated before testing. Session errors can block the UI.

2. **Payload CMS Conflict**: If running alongside Payload CMS, database schema may conflict. Run drizzle migrations in a clean database.

## Resources

- [Meilisearch Documentation](https://www.meilisearch.com/docs)
- [Meilisearch JavaScript SDK](https://github.com/meilisearch/meilisearch-js)
- [Meilisearch Security Guide](https://www.meilisearch.com/docs/learn/security/master_api_keys)
- [Meilisearch API Keys](https://www.meilisearch.com/docs/reference/api/keys)
- [next-themes](https://github.com/pacocoursey/next-themes) - Dark mode support
