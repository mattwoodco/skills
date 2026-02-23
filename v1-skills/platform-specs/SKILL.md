---
name: platform-specs
description: Typed library of social media platform image/video dimensions and safe zones. Use this skill when the user says "add platform specs", "social media dimensions", "platform presets", or "aspect ratio presets".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: []
---

# Platform Specs

Pure TypeScript data library of social media platform image and video dimensions, safe zones, file size limits, and accepted formats. Zero dependencies — import and use directly in any component or API route.

## Prerequisites

- Next.js app with App Router (no `src/` directory)

## Installation

No installation needed. This skill is pure TypeScript data with no external dependencies.

## What Gets Created

```
lib/
└── platform-specs/
    └── index.ts    # Full typed library — types, data, helpers, groups
```

## Setup Steps

### Step 1: Create `lib/platform-specs/index.ts`

```typescript
export type PlatformId =
  | "instagram-post"
  | "instagram-story"
  | "instagram-reel"
  | "youtube-thumbnail"
  | "youtube-shorts"
  | "tiktok"
  | "twitter-post"
  | "twitter-header"
  | "linkedin-post"
  | "linkedin-cover"
  | "facebook-post"
  | "pinterest-pin";

export interface SafeZone {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export interface PlatformSpec {
  id: PlatformId;
  label: string;
  width: number;
  height: number;
  /** Human-readable ratio string e.g. "16:9", "9:16", "1:1" */
  aspectRatio: string;
  /** Pixels from each edge that UI chrome may obscure — keep text/logos inside */
  safeZone?: SafeZone;
  /** Maximum file size in bytes */
  maxFileSize?: number;
  /** Accepted MIME types or file extensions */
  formats: string[];
  description: string;
}

export const PLATFORMS: Record<PlatformId, PlatformSpec> = {
  "instagram-post": {
    id: "instagram-post",
    label: "Instagram Post",
    width: 1080,
    height: 1080,
    aspectRatio: "1:1",
    maxFileSize: 30 * 1024 * 1024, // 30 MB
    formats: ["image/jpeg", "image/png", "image/webp"],
    description: "Square post for the Instagram feed. Displays at 1:1 in grid and feed.",
  },
  "instagram-story": {
    id: "instagram-story",
    label: "Instagram Story",
    width: 1080,
    height: 1920,
    aspectRatio: "9:16",
    safeZone: { top: 250, right: 0, bottom: 250, left: 0 },
    maxFileSize: 30 * 1024 * 1024, // 30 MB
    formats: ["image/jpeg", "image/png", "video/mp4"],
    description:
      "Full-screen vertical story. Keep key content within safe zone — top/bottom 250 px may be covered by UI chrome.",
  },
  "instagram-reel": {
    id: "instagram-reel",
    label: "Instagram Reel",
    width: 1080,
    height: 1920,
    aspectRatio: "9:16",
    safeZone: { top: 250, right: 0, bottom: 350, left: 0 },
    maxFileSize: 650 * 1024 * 1024, // 650 MB
    formats: ["video/mp4"],
    description:
      "Short-form vertical video. Bottom safe zone is taller (350 px) due to action buttons overlay.",
  },
  "youtube-thumbnail": {
    id: "youtube-thumbnail",
    label: "YouTube Thumbnail",
    width: 1280,
    height: 720,
    aspectRatio: "16:9",
    maxFileSize: 2 * 1024 * 1024, // 2 MB
    formats: ["image/jpeg", "image/png", "image/gif", "image/webp"],
    description:
      "Widescreen thumbnail displayed in search results and the watch page. High contrast text and faces perform best.",
  },
  "youtube-shorts": {
    id: "youtube-shorts",
    label: "YouTube Shorts",
    width: 1080,
    height: 1920,
    aspectRatio: "9:16",
    maxFileSize: 256 * 1024 * 1024, // 256 MB
    formats: ["video/mp4"],
    description:
      "Vertical short-form video up to 60 seconds. Displayed full-screen in the Shorts player.",
  },
  "tiktok": {
    id: "tiktok",
    label: "TikTok",
    width: 1080,
    height: 1920,
    aspectRatio: "9:16",
    safeZone: { top: 250, right: 0, bottom: 350, left: 0 },
    maxFileSize: 287 * 1024 * 1024, // 287 MB
    formats: ["video/mp4", "video/quicktime"],
    description:
      "Full-screen vertical video. Keep key content in safe zone — top 250 px (header) and bottom 350 px (caption + buttons) may be overlaid.",
  },
  "twitter-post": {
    id: "twitter-post",
    label: "X (Twitter) Post",
    width: 1200,
    height: 675,
    aspectRatio: "16:9",
    maxFileSize: 5 * 1024 * 1024, // 5 MB
    formats: ["image/jpeg", "image/png", "image/gif", "image/webp"],
    description:
      "Landscape image attached to a tweet. Displayed cropped to 16:9 in the timeline; full image shown on click.",
  },
  "twitter-header": {
    id: "twitter-header",
    label: "X (Twitter) Header",
    width: 1500,
    height: 500,
    aspectRatio: "3:1",
    maxFileSize: 5 * 1024 * 1024, // 5 MB
    formats: ["image/jpeg", "image/png"],
    description:
      "Profile banner displayed at the top of the X profile page. Center-crop safe — avoid edges which may be clipped on mobile.",
  },
  "linkedin-post": {
    id: "linkedin-post",
    label: "LinkedIn Post",
    width: 1200,
    height: 627,
    aspectRatio: "1.91:1",
    maxFileSize: 5 * 1024 * 1024, // 5 MB
    formats: ["image/jpeg", "image/png"],
    description:
      "Landscape image shared in the LinkedIn feed. Recommended ~1.91:1 ratio for maximum display area.",
  },
  "linkedin-cover": {
    id: "linkedin-cover",
    label: "LinkedIn Cover",
    width: 1584,
    height: 396,
    aspectRatio: "4:1",
    maxFileSize: 8 * 1024 * 1024, // 8 MB
    formats: ["image/jpeg", "image/png"],
    description:
      "Ultra-wide profile background banner. Keep important content centered — sides are cropped on smaller viewports.",
  },
  "facebook-post": {
    id: "facebook-post",
    label: "Facebook Post",
    width: 1200,
    height: 630,
    aspectRatio: "1.91:1",
    maxFileSize: 4 * 1024 * 1024, // 4 MB
    formats: ["image/jpeg", "image/png"],
    description:
      "Landscape image shared in the Facebook feed. Also used as the OG image when sharing external links.",
  },
  "pinterest-pin": {
    id: "pinterest-pin",
    label: "Pinterest Pin",
    width: 1000,
    height: 1500,
    aspectRatio: "2:3",
    maxFileSize: 32 * 1024 * 1024, // 32 MB
    formats: ["image/jpeg", "image/png", "image/webp"],
    description:
      "Tall portrait pin optimised for the Pinterest grid. 2:3 performs best; taller ratios may be truncated in-feed.",
  },
};

/**
 * Return the full spec for a platform ID.
 * Throws if the ID is not found (should not happen with correct types).
 */
export function getPlatform(id: PlatformId): PlatformSpec {
  const spec = PLATFORMS[id];
  if (!spec) {
    throw new Error(`Unknown platform: ${id}`);
  }
  return spec;
}

/**
 * Return width / height as a decimal float.
 * Useful for canvas/renderer aspect ratio calculations.
 */
export function getAspectRatio(id: PlatformId): number {
  const { width, height } = getPlatform(id);
  return width / height;
}

/**
 * Platforms grouped by category for UI pickers or menus.
 */
export const PLATFORM_GROUPS: {
  social: PlatformId[];
  video: PlatformId[];
  professional: PlatformId[];
} = {
  social: [
    "instagram-post",
    "instagram-story",
    "instagram-reel",
    "twitter-post",
    "twitter-header",
    "facebook-post",
    "pinterest-pin",
  ],
  video: ["youtube-thumbnail", "youtube-shorts", "tiktok"],
  professional: ["linkedin-post", "linkedin-cover"],
};
```

## Usage

```typescript
import {
  PLATFORMS,
  getPlatform,
  getAspectRatio,
  PLATFORM_GROUPS,
} from "@/lib/platform-specs";

// Look up a single platform
const spec = getPlatform("instagram-story");
console.log(spec.width, spec.height); // 1080 1920
console.log(spec.safeZone); // { top: 250, right: 0, bottom: 250, left: 0 }

// Get decimal aspect ratio for canvas calculations
const ratio = getAspectRatio("youtube-thumbnail"); // 1.7777...

// Iterate all platforms
const allSpecs = Object.values(PLATFORMS);

// Use grouped IDs for a UI picker
const videoIds = PLATFORM_GROUPS.video; // ["youtube-thumbnail", "youtube-shorts", "tiktok"]
const videoPlatforms = videoIds.map(getPlatform);
```

## Acceptance Criteria

- `import { PLATFORMS, getPlatform, getAspectRatio, PLATFORM_GROUPS } from "@/lib/platform-specs"` compiles with no errors
- All 12 platforms are present in `PLATFORMS` with `width`, `height`, `label`, `aspectRatio`, and `formats`
- `getPlatform("instagram-story").safeZone` is defined with `top: 250` and `bottom: 250`
- `getPlatform("tiktok").safeZone` is defined with `top: 250` and `bottom: 350`
- `getPlatform("instagram-reel").safeZone` is defined with `top: 250` and `bottom: 350`
- `getAspectRatio("instagram-post")` returns `1`
- `getAspectRatio("youtube-thumbnail")` returns approximately `1.778`
- `PLATFORM_GROUPS.social`, `PLATFORM_GROUPS.video`, and `PLATFORM_GROUPS.professional` each contain at least one entry covering all 12 platform IDs
- `tsc` passes with no errors
- Build succeeds
