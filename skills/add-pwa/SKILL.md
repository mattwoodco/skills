---
name: add-pwa
description: Setup Progressive Web App (PWA) support for a Next.js project using Serwist. Use when user says "setup pwa", "add pwa", "make it a pwa", "progressive web app", or "enable offline support".
author: "@mattwoodco"
version: 2.0.2
created: 2026-02-13
updated: 2026-02-14
validated: 2026-02-14
dependencies: [create-next]
---

# Add PWA Support

Adds Progressive Web App capabilities to a Next.js project using [`@serwist/turbopack`](https://serwist.pages.dev/docs/next/turbo) — the Turbopack-compatible Serwist integration. Uses esbuild via a Route Handler to bundle the service worker, so **no webpack fallback is needed**. Provides installability, offline support, precaching, and runtime caching strategies out of the box.

## What Gets Created

| File | Purpose |
|------|---------|
| `app/manifest.ts` | Web app manifest (name, icons, theme) |
| `app/sw.ts` | Service worker with precaching and offline fallback |
| `app/serwist/[path]/route.ts` | Route handler that bundles and serves the SW via esbuild |
| `app/serwist-provider.tsx` | Re-exports `SerwistProvider` with `"use client"` directive |
| `app/~offline/page.tsx` | Offline fallback page |
| `components/pwa-install-prompt.tsx` | Install prompt banner component |
| `components/pwa-provider.tsx` | PWA context provider (online/offline status) |
| `scripts/generate-icons.ts` | Placeholder icon generator |
| `public/icons/icon-192x192.svg` | Android/Chrome app icon (placeholder) |
| `public/icons/icon-512x512.svg` | Android/Chrome splash icon (placeholder) |
| `public/icons/apple-touch-icon.svg` | iOS home screen icon (placeholder) |

## Prerequisites

- Next.js 15+ project (App Router)
- TypeScript configured

## Installation

```bash
bun add -D @serwist/turbopack esbuild serwist
```

## Setup Steps

### 1. Create Web App Manifest

Create `app/manifest.ts`:

```ts
import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "My App",
    short_name: "MyApp",
    description: "A Progressive Web App built with Next.js",
    start_url: "/",
    display: "standalone",
    background_color: "#ffffff",
    theme_color: "#000000",
    orientation: "portrait",
    icons: [
      {
        src: "/icons/icon-192x192.svg",
        sizes: "192x192",
        type: "image/svg+xml",
        purpose: "maskable",
      },
      {
        src: "/icons/icon-512x512.svg",
        sizes: "512x512",
        type: "image/svg+xml",
      },
    ],
  };
}
```

**Note:** Next.js automatically serves this at `/manifest.webmanifest` and adds the `<link rel="manifest">` tag. No manual `<link>` tag needed. Replace SVG placeholders with real PNG icons for production.

### 2. Create Service Worker

Create `app/sw.ts`:

```ts
/// <reference no-default-lib="true" />
/// <reference lib="esnext" />
/// <reference lib="webworker" />
import { defaultCache } from "@serwist/turbopack/worker";
import type { PrecacheEntry, SerwistGlobalConfig } from "serwist";
import { Serwist } from "serwist";

declare global {
  interface WorkerGlobalScope extends SerwistGlobalConfig {
    __SW_MANIFEST: (PrecacheEntry | string)[] | undefined;
  }
}

declare const self: ServiceWorkerGlobalScope;

const serwist = new Serwist({
  precacheEntries: self.__SW_MANIFEST,
  skipWaiting: true,
  clientsClaim: true,
  navigationPreload: true,
  runtimeCaching: defaultCache,
  fallbacks: {
    entries: [
      {
        url: "/~offline",
        matcher({ request }) {
          return request.destination === "document";
        },
      },
    ],
  },
});

serwist.addEventListeners();
```

**Important:** The `/// <reference no-default-lib="true" />` directive removes default type definitions (including `dom`) from the compilation scope. You **must** exclude this file from the main TypeScript compilation. Add `"app/sw.ts"` to the `exclude` array in `tsconfig.json`:

```jsonc
{
  "exclude": ["node_modules", "app/sw.ts"]
}
```

This is safe because `app/sw.ts` is bundled separately by esbuild via the route handler — it does not go through the normal `tsc` / Next.js compilation pipeline.

### 3. Create Serwist Route Handler

Create `app/serwist/[path]/route.ts`:

```ts
import { spawnSync } from "node:child_process";
import { createSerwistRoute } from "@serwist/turbopack";

const revision =
  spawnSync("git", ["rev-parse", "HEAD"], { encoding: "utf-8" }).stdout.trim() ||
  crypto.randomUUID();

export const { dynamic, dynamicParams, revalidate, generateStaticParams, GET } =
  createSerwistRoute({
    additionalPrecacheEntries: [{ url: "/~offline", revision }],
    swSrc: "app/sw.ts", // Use "src/app/sw.ts" if project has --src-dir
    useNativeEsbuild: true,
  });
```

This route handler uses esbuild to bundle `app/sw.ts` on-demand, injecting the precache manifest. The compiled service worker is served at `/serwist/sw.js`.

### 4. Create Offline Fallback Page

Create `app/~offline/page.tsx`:

```tsx
export default function OfflinePage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-background">
      <div className="text-center px-6">
        <div className="text-6xl mb-6">📡</div>
        <h1 className="text-2xl font-bold text-foreground mb-2">
          You&apos;re offline
        </h1>
        <p className="text-muted-foreground max-w-sm">
          Check your internet connection and try again. Some features may still
          be available offline.
        </p>
      </div>
    </div>
  );
}
```

### 5. Configure next.config.ts

Update `next.config.ts` to wrap with Serwist:

```ts
import { withSerwist } from "@serwist/turbopack";

export default withSerwist({
  // Your existing Next.js config goes here
});
```

**Important:** If the project has an existing `next.config.ts` with other config (e.g. `reactCompiler: true`), pass it inside the `withSerwist()` call:

```ts
import { withSerwist } from "@serwist/turbopack";

export default withSerwist({
  reactCompiler: true,
  // ...other config
});
```

### 6. Create SerwistProvider Re-export

Create `app/serwist-provider.tsx`:

```tsx
"use client";
export { SerwistProvider } from "@serwist/turbopack/react";
```

Serwist's `SerwistProvider` must be used in a client component. This re-export adds the `"use client"` directive.

### 7. Update Root Layout Metadata & Wire Up Provider

Update `app/layout.tsx` to include PWA metadata and the Serwist provider:

```tsx
import type { Metadata, Viewport } from "next";
import { SerwistProvider } from "./serwist-provider";
import { PWAInstallPrompt } from "@/components/pwa-install-prompt";
import { PWAProvider } from "@/components/pwa-provider";

export const metadata: Metadata = {
  applicationName: "My App",
  title: {
    default: "My App",
    template: "%s | My App",
  },
  description: "A Progressive Web App built with Next.js",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "My App",
  },
  formatDetection: {
    telephone: false,
  },
};

export const viewport: Viewport = {
  themeColor: "#000000",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <SerwistProvider swUrl="/serwist/sw.js">
          <PWAProvider>
            {children}
            <PWAInstallPrompt />
          </PWAProvider>
        </SerwistProvider>
      </body>
    </html>
  );
}
```

**Note:** `themeColor` must be in the `viewport` export, not `metadata` (changed in Next.js 14+). The `swUrl` points to the route handler path, not a static file.

### 8. Generate Placeholder Icons

Create `scripts/generate-icons.ts`:

```ts
import { mkdirSync, writeFileSync } from "node:fs";

function generatePlaceholderSVG(size: number): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <rect width="${size}" height="${size}" fill="#000000" rx="${size * 0.1}"/>
  <text x="50%" y="50%" dominant-baseline="central" text-anchor="middle" fill="white" font-family="system-ui" font-size="${size * 0.4}" font-weight="bold">App</text>
</svg>`;
}

mkdirSync("public/icons", { recursive: true });

for (const size of [192, 512]) {
  writeFileSync(
    `public/icons/icon-${size}x${size}.svg`,
    generatePlaceholderSVG(size),
  );
}

writeFileSync("public/icons/apple-touch-icon.svg", generatePlaceholderSVG(180));
```

Run it:

```bash
bun run scripts/generate-icons.ts
```

For production, replace these SVGs with real PNG icons using [Real Favicon Generator](https://realfavicongenerator.net/) and update `app/manifest.ts` to use `type: "image/png"`.

### 9. Create PWA Provider Component

Create `components/pwa-provider.tsx`:

```tsx
"use client";

import {
  createContext,
  useContext,
  useMemo,
  useSyncExternalStore,
} from "react";

type PWAContextValue = {
  isOnline: boolean;
  isInstalled: boolean;
};

const PWAContext = createContext<PWAContextValue>({
  isOnline: true,
  isInstalled: false,
});

function subscribeOnline(callback: () => void) {
  window.addEventListener("online", callback);
  window.addEventListener("offline", callback);
  return () => {
    window.removeEventListener("online", callback);
    window.removeEventListener("offline", callback);
  };
}

function getOnlineSnapshot() {
  return navigator.onLine;
}

function getServerSnapshot() {
  return true;
}

function subscribeDisplayMode(callback: () => void) {
  const mql = window.matchMedia("(display-mode: standalone)");
  mql.addEventListener("change", callback);
  return () => mql.removeEventListener("change", callback);
}

function getDisplayModeSnapshot() {
  return window.matchMedia("(display-mode: standalone)").matches;
}

function getDisplayModeServerSnapshot() {
  return false;
}

export function PWAProvider({ children }: { children: React.ReactNode }) {
  const isOnline = useSyncExternalStore(
    subscribeOnline,
    getOnlineSnapshot,
    getServerSnapshot,
  );
  const isInstalled = useSyncExternalStore(
    subscribeDisplayMode,
    getDisplayModeSnapshot,
    getDisplayModeServerSnapshot,
  );

  const value = useMemo(
    () => ({ isOnline, isInstalled }),
    [isOnline, isInstalled],
  );

  return <PWAContext value={value}>{children}</PWAContext>;
}

export function usePWA() {
  return useContext(PWAContext);
}
```

### 10. Create Install Prompt Component

Create `components/pwa-install-prompt.tsx`:

```tsx
"use client";

import { useCallback, useEffect, useRef, useState } from "react";

type BeforeInstallPromptEvent = Event & {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

export function PWAInstallPrompt() {
  const deferredPromptRef = useRef<BeforeInstallPromptEvent | null>(null);
  const [showPrompt, setShowPrompt] = useState(false);

  useEffect(() => {
    function handleBeforeInstallPrompt(e: Event) {
      e.preventDefault();
      deferredPromptRef.current = e as BeforeInstallPromptEvent;
      setShowPrompt(true);
    }

    window.addEventListener("beforeinstallprompt", handleBeforeInstallPrompt);
    return () =>
      window.removeEventListener(
        "beforeinstallprompt",
        handleBeforeInstallPrompt,
      );
  }, []);

  const handleInstall = useCallback(async () => {
    const prompt = deferredPromptRef.current;
    if (!prompt) return;

    await prompt.prompt();
    const { outcome } = await prompt.userChoice;

    if (outcome === "accepted") {
      deferredPromptRef.current = null;
      setShowPrompt(false);
    }
  }, []);

  const handleDismiss = useCallback(() => {
    setShowPrompt(false);
    deferredPromptRef.current = null;
  }, []);

  if (!showPrompt) return null;

  return (
    <div className="fixed bottom-4 left-4 right-4 z-50 mx-auto max-w-md rounded-lg border border-border bg-card p-4 shadow-lg">
      <div className="flex items-start gap-3">
        <div className="flex-1">
          <p className="font-medium text-foreground">Install App</p>
          <p className="text-sm text-muted-foreground">
            Add this app to your home screen for a better experience.
          </p>
        </div>
        <div className="flex gap-2">
          <button
            type="button"
            onClick={handleDismiss}
            className="rounded-md px-3 py-1.5 text-sm text-muted-foreground hover:bg-muted"
          >
            Later
          </button>
          <button
            type="button"
            onClick={handleInstall}
            className="rounded-md bg-primary px-3 py-1.5 text-sm text-primary-foreground hover:bg-primary/90"
          >
            Install
          </button>
        </div>
      </div>
    </div>
  );
}
```

## Usage Examples

### Check Online/Offline Status

```tsx
"use client";

import { usePWA } from "@/components/pwa-provider";

export function ConnectionStatus() {
  const { isOnline } = usePWA();

  return (
    <div className="flex items-center gap-2">
      <div className={`h-2 w-2 rounded-full ${isOnline ? "bg-green-500" : "bg-red-500"}`} />
      <span className="text-sm text-muted-foreground">
        {isOnline ? "Online" : "Offline"}
      </span>
    </div>
  );
}
```

### Check if Running as Installed PWA

```tsx
"use client";

import { usePWA } from "@/components/pwa-provider";

export function AppHeader() {
  const { isInstalled } = usePWA();

  return (
    <header className="border-b border-border bg-card px-4 py-3">
      <h1 className="text-foreground font-bold">
        My App {isInstalled && <span className="text-xs text-muted-foreground">(Installed)</span>}
      </h1>
    </header>
  );
}
```

## Testing Checklist

- [ ] `bun run build` completes without errors (uses Turbopack — no `--webpack` flag needed)
- [ ] `bun dev` starts without errors (Turbopack, no fallback)
- [ ] `/serwist/sw.js` is served correctly (check in browser)
- [ ] `/manifest.webmanifest` is served correctly
- [ ] App is installable (Chrome shows install icon in address bar)
- [ ] Install prompt banner appears on first visit
- [ ] Offline fallback page shows when navigating offline
- [ ] Online/offline status updates in real time
- [ ] No TypeScript errors
- [ ] Service worker registers on page load (check DevTools > Application > Service Workers)

## Troubleshooting

### Service worker not updating in development

With `@serwist/turbopack`, the service worker is bundled by esbuild via the route handler. In dev mode, changes to `app/sw.ts` require a **dev server restart** to take effect. This is a known limitation — esbuild bundles once per server start.

### TypeScript errors (`Cannot find name 'window'`, etc.)

The `/// <reference no-default-lib="true" />` directive in `app/sw.ts` removes all default type definitions (including `dom`) from the compilation scope. If `app/sw.ts` is not excluded from `tsconfig.json`, this breaks type-checking for the entire project.

**Fix:** Ensure `"app/sw.ts"` is in the `exclude` array of `tsconfig.json`:

```jsonc
{
  "exclude": ["node_modules", "app/sw.ts"]
}
```

If your IDE still shows errors in `sw.ts` itself, that is expected — esbuild bundles the file separately and does not use `tsconfig.json`.

### Route handler 404 at `/serwist/sw.js`

Ensure the file is at exactly `app/serwist/[path]/route.ts` (with the `[path]` dynamic segment). The `generateStaticParams` export pre-renders `sw.js` and `sw.js.map`.

### Icons not showing on install

- Verify icons exist at the exact paths specified in `app/manifest.ts`
- Ensure at least a 192x192 and 512x512 icon are provided
- Use `purpose: "maskable"` on the 192x192 icon for adaptive icon support
- Test with Chrome DevTools > Application > Manifest

### Offline page not showing

- Ensure `/~offline` route exists and renders without errors
- The offline fallback only works for navigation requests (HTML pages), not API calls or assets
- Verify `additionalPrecacheEntries` in the route handler includes `{ url: "/~offline", revision }`

### Migrating from `@serwist/next` (webpack)

If upgrading from the webpack-based setup:

1. Remove `@serwist/next`: `bun remove @serwist/next`
2. Install turbopack version: `bun add -D @serwist/turbopack esbuild`
3. Replace `next.config.ts` — use `{ withSerwist } from "@serwist/turbopack"` instead of `withSerwistInit from "@serwist/next"`
4. Create the route handler at `app/serwist/[path]/route.ts`
5. Create the `app/serwist-provider.tsx` re-export
6. Update `app/sw.ts` imports: `@serwist/turbopack/worker` instead of `@serwist/next/worker`
7. Remove `turbopack: {}` workaround from `next.config.ts` (no longer needed)
8. Remove `--webpack` flags from `package.json` scripts
9. Remove `public/sw.js` and `public/sw.js.map` from `.gitignore` (no longer generated as static files)
10. Remove `@serwist/next/typings` from `tsconfig.json` types (triple-slash directives handle this now)
11. Remove `"webworker"` from `tsconfig.json` `lib` array (triple-slash directives in `sw.ts` handle this now)
12. Replace `public/sw.js` with `app/sw.ts` in `tsconfig.json` `exclude` array (the service worker is no longer generated as a static file, but still needs excluding due to `/// <reference no-default-lib="true" />`)
