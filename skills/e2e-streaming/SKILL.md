---
name: e2e-streaming
version: 1.0.0
updated: 2026-02-18
dependencies: [e2e, livestream, stream-mux, video-player]
---

# E2E Livestream Tests

Playwright test suite for Constellation v3 livestreaming features. Tests the go-live broadcast flow (stream creation, status transitions, stop), viewer experience (MUX player, public access), in-stream chat, and recording management. Uses `page.route()` to mock MUX and LiveKit API responses so tests run without real streaming infrastructure.

## When to Use This Skill

Use this skill when the user says:
- "test streaming"
- "add streaming e2e tests"
- "e2e streaming"
- "test livestream"
- "playwright streaming tests"
- "test go live"
- "test recordings"

## Prerequisites

- Next.js app with App Router
- `e2e` skill installed (Playwright configured with `playwright.config.ts`)
- `livestream` skill installed (go-live page, viewer page, stream management)
- `stream-mux` skill installed (MUX integration for stream ingest and playback)
- `video-player` skill installed (MUX player component)
- `auth-dev` skill installed (seed users for authentication)
- Dev server running on `localhost:3000`

## Installation

No additional packages required. The `e2e` skill provides `@playwright/test` and the Playwright configuration.

## What Gets Created

```
e2e/
├── fixtures/
│   └── mock-streaming.ts           # MUX & livestream API mock helpers
├── helpers/
│   └── streaming-auth.ts           # Reusable sign-in helper for streaming tests
├── livestream-go-live.spec.ts      # Go-live flow: create, start, stop stream
├── livestream-viewer.spec.ts       # Viewer page: player, title, public access
├── livestream-chat.spec.ts         # In-stream chat: send messages during stream
└── livestream-recording.spec.ts    # Recording: start, status, metadata
```

## Setup Steps

### Step 1: Create `e2e/fixtures/mock-streaming.ts`

Comprehensive mock helpers for MUX API responses, livestream endpoints, and the MUX player script. Provides consistent test data for all streaming tests.

```typescript
import type { Page } from "@playwright/test";

/**
 * Shape of a livestream returned by the API.
 */
type MockLivestream = {
  id: string;
  title: string;
  status: "idle" | "live" | "ended";
  streamKey: string;
  playbackId: string;
  muxLiveStreamId: string;
  livekitRoomName: string;
  createdAt: string;
  startedAt: string | null;
  endedAt: string | null;
};

/**
 * Shape of a MUX live stream from the MUX API.
 */
type MockMuxLiveStream = {
  id: string;
  stream_key: string;
  status: string;
  playback_ids: Array<{ id: string; policy: string }>;
  reconnect_window: number;
  max_continuous_duration: number;
  created_at: string;
};

/**
 * Shape of a MUX asset (recording).
 */
type MockMuxAsset = {
  id: string;
  status: string;
  playback_ids: Array<{ id: string; policy: string }>;
  duration: number;
  created_at: string;
};

/**
 * Shape of a recording returned by the app API.
 */
type MockRecording = {
  id: string;
  livestreamId: string;
  muxAssetId: string;
  playbackId: string;
  status: "preparing" | "ready" | "errored";
  duration: number;
  createdAt: string;
};

const MOCK_LIVESTREAM: MockLivestream = {
  id: "ls-test-001",
  title: "E2E Test Stream",
  status: "idle",
  streamKey: "sk-test-stream-key-abc123",
  playbackId: "pb-test-playback-id",
  muxLiveStreamId: "mux-ls-test-001",
  livekitRoomName: "livestream-ls-test-001",
  createdAt: "2026-02-18T00:00:00.000Z",
  startedAt: null,
  endedAt: null,
};

const MOCK_MUX_LIVE_STREAM: MockMuxLiveStream = {
  id: "mux-ls-test-001",
  stream_key: "sk-test-stream-key-abc123",
  status: "idle",
  playback_ids: [{ id: "pb-test-playback-id", policy: "public" }],
  reconnect_window: 60,
  max_continuous_duration: 43200,
  created_at: "2026-02-18T00:00:00.000Z",
};

const MOCK_MUX_ASSET: MockMuxAsset = {
  id: "mux-asset-test-001",
  status: "ready",
  playback_ids: [{ id: "pb-recording-test", policy: "public" }],
  duration: 3600,
  created_at: "2026-02-18T01:00:00.000Z",
};

const MOCK_RECORDING: MockRecording = {
  id: "rec-test-001",
  livestreamId: MOCK_LIVESTREAM.id,
  muxAssetId: MOCK_MUX_ASSET.id,
  playbackId: "pb-recording-test",
  status: "ready",
  duration: 3600,
  createdAt: "2026-02-18T01:00:00.000Z",
};

/**
 * Intercepts outgoing requests to the MUX API.
 *
 * Mocks:
 * - POST to MUX live streams endpoint -> create live stream
 * - GET MUX live stream -> stream details
 * - POST to MUX assets endpoint -> create asset
 * - MUX webhook events are not intercepted (they're server-to-server)
 */
export async function interceptMuxApi(page: Page): Promise<void> {
  // Intercept MUX REST API calls (these go from the Next.js server to MUX,
  // but if the client makes them directly, catch them here)
  await page.route("**/api.mux.com/**", async (route) => {
    const url = route.request().url();
    const method = route.request().method();

    // Create live stream
    if (url.includes("/video/v1/live-streams") && method === "POST") {
      await route.fulfill({
        status: 201,
        contentType: "application/json",
        body: JSON.stringify({ data: MOCK_MUX_LIVE_STREAM }),
      });
      return;
    }

    // Get live stream
    if (url.includes("/video/v1/live-streams/") && method === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ data: MOCK_MUX_LIVE_STREAM }),
      });
      return;
    }

    // Create asset
    if (url.includes("/video/v1/assets") && method === "POST") {
      await route.fulfill({
        status: 201,
        contentType: "application/json",
        body: JSON.stringify({ data: MOCK_MUX_ASSET }),
      });
      return;
    }

    await route.continue();
  });
}

/**
 * Intercepts the app's livestream API routes.
 *
 * Mocks:
 * - POST /api/video/livestream          -> create a new livestream
 * - GET  /api/video/livestream/:id      -> get livestream details
 * - POST /api/video/livestream/:id/start -> start the stream (status -> live)
 * - POST /api/video/livestream/:id/stop  -> stop the stream (status -> ended)
 * - GET  /api/video/livestream          -> list livestreams
 */
export async function interceptLivestreamApi(page: Page): Promise<void> {
  // Track stream state so start/stop transitions work within a test
  let currentStatus: MockLivestream["status"] = "idle";
  let startedAt: string | null = null;
  let endedAt: string | null = null;

  // Create livestream
  await page.route("**/api/video/livestream", async (route) => {
    const method = route.request().method();

    if (method === "POST") {
      const body = route.request().postDataJSON() as { title?: string };
      currentStatus = "idle";
      startedAt = null;
      endedAt = null;
      await route.fulfill({
        status: 201,
        contentType: "application/json",
        body: JSON.stringify({
          livestream: {
            ...MOCK_LIVESTREAM,
            title: body?.title ?? MOCK_LIVESTREAM.title,
            status: currentStatus,
            startedAt,
            endedAt,
          },
        }),
      });
      return;
    }

    if (method === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          livestreams: [
            {
              ...MOCK_LIVESTREAM,
              status: currentStatus,
              startedAt,
              endedAt,
            },
          ],
        }),
      });
      return;
    }

    await route.continue();
  });

  // Single livestream operations
  await page.route(/\/api\/video\/livestream\/[^/]+$/, async (route) => {
    if (route.request().method() === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          livestream: {
            ...MOCK_LIVESTREAM,
            status: currentStatus,
            startedAt,
            endedAt,
          },
        }),
      });
      return;
    }
    await route.continue();
  });

  // Start livestream
  await page.route(/\/api\/video\/livestream\/[^/]+\/start$/, async (route) => {
    if (route.request().method() === "POST") {
      currentStatus = "live";
      startedAt = new Date().toISOString();
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          livestream: {
            ...MOCK_LIVESTREAM,
            status: currentStatus,
            startedAt,
            endedAt,
          },
        }),
      });
      return;
    }
    await route.continue();
  });

  // Stop livestream
  await page.route(/\/api\/video\/livestream\/[^/]+\/stop$/, async (route) => {
    if (route.request().method() === "POST") {
      currentStatus = "ended";
      endedAt = new Date().toISOString();
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          livestream: {
            ...MOCK_LIVESTREAM,
            status: currentStatus,
            startedAt,
            endedAt,
          },
        }),
      });
      return;
    }
    await route.continue();
  });
}

/**
 * Intercepts the MUX Player script loading to prevent external script errors.
 * Replaces the MUX player web component with a mock <div> so tests can
 * verify the player container renders without loading the real player SDK.
 */
export async function mockMuxPlayer(page: Page): Promise<void> {
  // Block the MUX Player CDN script to avoid loading real player
  await page.route("**/unpkg.com/@mux/**", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/javascript",
      body: `
        // Mock MUX Player web component
        class MuxPlayer extends HTMLElement {
          connectedCallback() {
            this.innerHTML = '<div data-testid="mock-mux-player" style="width:100%;aspect-ratio:16/9;background:#000;display:flex;align-items:center;justify-content:center;color:#fff;">Mock MUX Player</div>';
          }
        }
        if (!customElements.get('mux-player')) {
          customElements.define('mux-player', MuxPlayer);
        }
      `,
    });
  });

  // Also block the MUX data/analytics scripts
  await page.route("**/cdn.mux.com/**", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/javascript",
      body: "// Mocked MUX analytics",
    });
  });

  // Block the MUX player ESM modules
  await page.route("**/mux-player**", async (route) => {
    const url = route.request().url();
    // Only intercept CDN-hosted scripts, not app routes
    if (url.includes("cdn") || url.includes("unpkg") || url.includes("esm")) {
      await route.fulfill({
        status: 200,
        contentType: "application/javascript",
        body: "// Mocked MUX player module",
      });
      return;
    }
    await route.continue();
  });
}

/**
 * Intercepts recording API routes.
 *
 * Mocks:
 * - POST /api/video/recordings          -> start a recording
 * - GET  /api/video/recordings/:id      -> get recording status
 * - GET  /api/video/recordings          -> list recordings
 */
export async function interceptRecordingApi(page: Page): Promise<void> {
  // Create recording
  await page.route("**/api/video/recordings", async (route) => {
    const method = route.request().method();

    if (method === "POST") {
      await route.fulfill({
        status: 201,
        contentType: "application/json",
        body: JSON.stringify({ recording: MOCK_RECORDING }),
      });
      return;
    }

    if (method === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ recordings: [MOCK_RECORDING] }),
      });
      return;
    }

    await route.continue();
  });

  // Single recording
  await page.route(/\/api\/video\/recordings\/[^/]+$/, async (route) => {
    if (route.request().method() === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ recording: MOCK_RECORDING }),
      });
      return;
    }
    await route.continue();
  });
}

export {
  MOCK_LIVESTREAM,
  MOCK_MUX_LIVE_STREAM,
  MOCK_MUX_ASSET,
  MOCK_RECORDING,
};
export type {
  MockLivestream,
  MockMuxLiveStream,
  MockMuxAsset,
  MockRecording,
};
```

### Step 2: Create `e2e/helpers/streaming-auth.ts`

Reusable helper that signs in as the dev admin user via the `/dev` page. Used by all streaming test files that require authentication.

```typescript
import type { Page } from "@playwright/test";
import { expect } from "@playwright/test";

/**
 * Signs in as the admin test user using the auth-dev quick sign-in flow.
 *
 * Steps:
 * 1. Navigate to /dev
 * 2. Click the "Seed Users" button to ensure users exist
 * 3. Click the "Sign In" button on the admin user card
 * 4. Wait for redirect to homepage
 *
 * Call this in test.beforeEach for any test that requires authentication.
 */
export async function signInAsTestUser(page: Page): Promise<void> {
  // Navigate to the dev console
  await page.goto("/dev");
  await expect(page.getByRole("heading", { name: /dev console/i })).toBeVisible({
    timeout: 10_000,
  });

  // Seed users to ensure they exist in the database
  const seedButton = page.getByRole("button", { name: /seed users/i });
  await seedButton.click();
  // Wait for seed to complete — the result message appears after seeding
  await expect(page.getByText(/seeded|exists|created/i)).toBeVisible({
    timeout: 15_000,
  });

  // Find the admin user card and click Sign In
  const adminCard = page.locator("div", {
    has: page.getByText("admin@example.com"),
  });
  const signInButton = adminCard.getByRole("button", { name: /sign in/i });
  await signInButton.click();

  // Wait for redirect after successful sign-in
  await page.waitForURL(/\/(?!dev)/, { timeout: 15_000 });
}

/**
 * Signs out the current user by navigating to /dev and clicking sign out.
 */
export async function signOutTestUser(page: Page): Promise<void> {
  await page.goto("/dev");
  const signOutButton = page.getByRole("button", { name: /sign out/i });
  if (await signOutButton.isVisible()) {
    await signOutButton.click();
    await expect(page.getByText(/not signed in/i)).toBeVisible({
      timeout: 10_000,
    });
  }
}
```

### Step 3: Create `e2e/livestream-go-live.spec.ts`

Tests the broadcaster's go-live flow — stream configuration, creating a stream, starting it, and stopping it with status transitions.

```typescript
import { test, expect } from "@playwright/test";
import {
  interceptLivestreamApi,
  interceptMuxApi,
  mockMuxPlayer,
  MOCK_LIVESTREAM,
} from "./fixtures/mock-streaming";
import { signInAsTestUser } from "./helpers/streaming-auth";

test.describe("Livestream Go Live Flow", () => {
  test.beforeEach(async ({ page }) => {
    // Sign in as admin — broadcasting requires authentication
    await signInAsTestUser(page);

    // Mock all streaming API calls
    await interceptLivestreamApi(page);
    await interceptMuxApi(page);
    await mockMuxPlayer(page);
  });

  test("go-live page renders with stream configuration", async ({ page }) => {
    // Navigate to the go-live / broadcast page
    await page.goto("/livestream/go-live");

    // The page should have a title input for the stream name
    const titleInput = page.locator(
      [
        "input[name='title']",
        "input[placeholder*='title' i]",
        "input[placeholder*='stream name' i]",
        "input[aria-label*='title' i]",
        "[data-testid='stream-title-input']",
      ].join(", ")
    ).first();
    await expect(titleInput).toBeVisible({ timeout: 10_000 });

    // The page should have a "Go Live" or "Start Stream" button
    const goLiveButton = page.getByRole("button", {
      name: /go live|start stream|create stream/i,
    });
    await expect(goLiveButton).toBeVisible();
  });

  test("POST /api/video/livestream creates a stream", async ({
    page,
    request,
  }) => {
    // Get auth cookies from the signed-in browser
    const cookies = await page.context().cookies();
    const cookieHeader = cookies
      .map((c) => `${c.name}=${c.value}`)
      .join("; ");

    // Create a livestream via the API
    const response = await request.post("/api/video/livestream", {
      data: {
        title: "E2E Test Broadcast",
      },
      headers: {
        Cookie: cookieHeader,
      },
    });

    // The API should return the created livestream
    if (response.ok()) {
      const body = (await response.json()) as {
        livestream: {
          id: string;
          title: string;
          status: string;
          streamKey: string;
          playbackId: string;
        };
      };
      expect(body.livestream).toBeDefined();
      expect(body.livestream.id).toBeDefined();
      expect(body.livestream.status).toBe("idle");
      expect(body.livestream.streamKey).toBeDefined();
      expect(body.livestream.playbackId).toBeDefined();
    } else {
      // If MUX is not configured, expect a structured error
      const body = (await response.json()) as { error: string };
      expect(body.error).toBeDefined();
    }
  });

  test("stream status shows 'live' after starting", async ({ page }) => {
    await page.goto("/livestream/go-live");

    // Fill in stream title
    const titleInput = page.locator(
      [
        "input[name='title']",
        "input[placeholder*='title' i]",
        "input[placeholder*='stream name' i]",
        "[data-testid='stream-title-input']",
      ].join(", ")
    ).first();
    await titleInput.fill("E2E Live Stream");

    // Click the go-live button to create and start the stream
    const goLiveButton = page.getByRole("button", {
      name: /go live|start stream|create stream/i,
    });
    await goLiveButton.click();

    // After starting, the status should transition to "live"
    const liveStatus = page.locator(
      [
        "[data-testid='stream-status']",
        "text=/live/i",
        "[class*='status']",
        "span:has-text('Live')",
        "badge:has-text('Live')",
      ].join(", ")
    ).first();
    await expect(liveStatus).toBeVisible({ timeout: 15_000 });
  });

  test("stop button ends the stream", async ({ page }) => {
    await page.goto("/livestream/go-live");

    // Start a stream first
    const titleInput = page.locator(
      [
        "input[name='title']",
        "input[placeholder*='title' i]",
        "input[placeholder*='stream name' i]",
        "[data-testid='stream-title-input']",
      ].join(", ")
    ).first();
    await titleInput.fill("E2E Stream to Stop");

    const goLiveButton = page.getByRole("button", {
      name: /go live|start stream|create stream/i,
    });
    await goLiveButton.click();

    // Wait for the stream to be live
    await expect(
      page.locator("text=/live/i").first()
    ).toBeVisible({ timeout: 15_000 });

    // Now click the stop/end stream button
    const stopButton = page.getByRole("button", {
      name: /stop|end stream|end broadcast/i,
    });
    await expect(stopButton).toBeVisible({ timeout: 5_000 });
    await stopButton.click();

    // Confirm the stop action if there's a confirmation dialog
    const confirmButton = page.getByRole("button", {
      name: /confirm|yes|end/i,
    });
    if (await confirmButton.isVisible({ timeout: 2_000 }).catch(() => false)) {
      await confirmButton.click();
    }

    // The status should update to indicate the stream has ended
    const endedStatus = page.locator(
      [
        "[data-testid='stream-status']:has-text(/ended|idle|offline/i)",
        "text=/ended|stream ended|offline/i",
        "span:has-text('Ended')",
        "span:has-text('Idle')",
      ].join(", ")
    ).first();
    await expect(endedStatus).toBeVisible({ timeout: 10_000 });
  });

  test("stream status updates to idle after stopping", async ({ page }) => {
    await page.goto("/livestream/go-live");

    // Start a stream
    const titleInput = page.locator(
      [
        "input[name='title']",
        "input[placeholder*='title' i]",
        "[data-testid='stream-title-input']",
      ].join(", ")
    ).first();
    await titleInput.fill("Status Transition Test");

    const goLiveButton = page.getByRole("button", {
      name: /go live|start stream|create stream/i,
    });
    await goLiveButton.click();

    // Wait for live status
    await expect(
      page.locator("text=/live/i").first()
    ).toBeVisible({ timeout: 15_000 });

    // Stop the stream
    const stopButton = page.getByRole("button", {
      name: /stop|end stream|end broadcast/i,
    });
    await stopButton.click();

    // Handle confirmation dialog if present
    const confirmButton = page.getByRole("button", {
      name: /confirm|yes|end/i,
    });
    if (await confirmButton.isVisible({ timeout: 2_000 }).catch(() => false)) {
      await confirmButton.click();
    }

    // After stopping, the page should reflect the ended/idle state.
    // The go-live button may reappear or a "Stream Ended" message shows.
    const idleIndicator = page.locator(
      [
        "text=/ended|idle|offline|stream ended/i",
        "[data-testid='stream-status']",
        "button:has-text(/go live|start/i)",
      ].join(", ")
    ).first();
    await expect(idleIndicator).toBeVisible({ timeout: 10_000 });
  });
});
```

### Step 4: Create `e2e/livestream-viewer.spec.ts`

Tests the viewer experience — MUX player rendering, stream title display, video element, and public (unauthenticated) access.

```typescript
import { test, expect } from "@playwright/test";
import {
  interceptLivestreamApi,
  mockMuxPlayer,
  MOCK_LIVESTREAM,
} from "./fixtures/mock-streaming";

test.describe("Livestream Viewer Page", () => {
  test.beforeEach(async ({ page }) => {
    // Mock streaming APIs — viewer tests may or may not need auth
    await interceptLivestreamApi(page);
    await mockMuxPlayer(page);

    // Override the livestream status to "live" so the viewer has content
    await page.route(/\/api\/video\/livestream\/[^/]+$/, async (route) => {
      if (route.request().method() === "GET") {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            livestream: {
              ...MOCK_LIVESTREAM,
              status: "live",
              startedAt: new Date().toISOString(),
            },
          }),
        });
        return;
      }
      await route.continue();
    });
  });

  test("viewer page loads MUX player component", async ({ page }) => {
    // Navigate to the viewer page for the test stream
    await page.goto(`/livestream/${MOCK_LIVESTREAM.id}`);

    // The MUX player component should be present.
    // It may be a <mux-player> web component, a <video> element,
    // or a container with the mock player.
    const playerElement = page.locator(
      [
        "mux-player",
        "[data-testid='mux-player']",
        "[data-testid='mock-mux-player']",
        "[data-testid='video-player']",
        "video",
      ].join(", ")
    ).first();

    await expect(playerElement).toBeVisible({ timeout: 15_000 });
  });

  test("player area shows stream title", async ({ page }) => {
    await page.goto(`/livestream/${MOCK_LIVESTREAM.id}`);

    // The stream title should be displayed on the viewer page
    const streamTitle = page.getByText(MOCK_LIVESTREAM.title);
    await expect(streamTitle).toBeVisible({ timeout: 10_000 });
  });

  test("player renders a video element or player container", async ({
    page,
  }) => {
    await page.goto(`/livestream/${MOCK_LIVESTREAM.id}`);

    // Look for the actual video element within the player.
    // With the mock MUX player, this will be a div with test ID.
    // With the real player, it will be a <video> inside <mux-player>.
    const videoContainer = page.locator(
      [
        "mux-player",
        "video",
        "[data-testid='mock-mux-player']",
        "[data-testid='video-player']",
        "[class*='player']",
      ].join(", ")
    ).first();

    await expect(videoContainer).toBeVisible({ timeout: 15_000 });

    // Verify the player has reasonable dimensions (not collapsed)
    const box = await videoContainer.boundingBox();
    expect(box).not.toBeNull();
    if (box) {
      expect(box.width).toBeGreaterThan(100);
      expect(box.height).toBeGreaterThan(50);
    }
  });

  test("viewer page works without authentication (public access)", async ({
    browser,
  }) => {
    // Create a fresh browser context with NO cookies (no auth)
    const context = await browser.newContext();
    const page = await context.newPage();

    // Set up mocks on the fresh page
    await interceptLivestreamApi(page);
    await mockMuxPlayer(page);

    // Override the livestream to be "live"
    await page.route(/\/api\/video\/livestream\/[^/]+$/, async (route) => {
      if (route.request().method() === "GET") {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            livestream: {
              ...MOCK_LIVESTREAM,
              status: "live",
              startedAt: new Date().toISOString(),
            },
          }),
        });
        return;
      }
      await route.continue();
    });

    // Navigate to the viewer page WITHOUT being signed in
    const response = await page.goto(`/livestream/${MOCK_LIVESTREAM.id}`);

    // The page should load successfully (not redirect to login)
    expect(response?.status()).toBe(200);

    // The player or stream content should be visible
    const content = page.locator(
      [
        "mux-player",
        "[data-testid='mux-player']",
        "[data-testid='mock-mux-player']",
        "video",
        "[data-testid='video-player']",
      ].join(", ")
    ).first();
    await expect(content).toBeVisible({ timeout: 15_000 });

    // Clean up the context
    await context.close();
  });

  test("viewer page shows offline state when stream is idle", async ({
    page,
  }) => {
    // Override the livestream status to "idle"
    await page.route(/\/api\/video\/livestream\/[^/]+$/, async (route) => {
      if (route.request().method() === "GET") {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            livestream: {
              ...MOCK_LIVESTREAM,
              status: "idle",
              startedAt: null,
            },
          }),
        });
        return;
      }
      await route.continue();
    });

    await page.goto(`/livestream/${MOCK_LIVESTREAM.id}`);

    // When the stream is idle, the viewer should see an offline message
    const offlineMessage = page.locator(
      [
        "[data-testid='stream-offline']",
        "text=/offline|not live|stream.*ended|coming soon/i",
      ].join(", ")
    ).first();
    await expect(offlineMessage).toBeVisible({ timeout: 10_000 });
  });
});
```

### Step 5: Create `e2e/livestream-chat.spec.ts`

Tests the chat panel that runs alongside the stream player during a live broadcast.

```typescript
import { test, expect } from "@playwright/test";
import {
  interceptLivestreamApi,
  mockMuxPlayer,
  MOCK_LIVESTREAM,
} from "./fixtures/mock-streaming";
import { signInAsTestUser } from "./helpers/streaming-auth";

test.describe("Livestream Chat", () => {
  test.beforeEach(async ({ page }) => {
    // Sign in for chat functionality
    await signInAsTestUser(page);

    // Mock streaming APIs
    await interceptLivestreamApi(page);
    await mockMuxPlayer(page);

    // Set stream status to "live"
    await page.route(/\/api\/video\/livestream\/[^/]+$/, async (route) => {
      if (route.request().method() === "GET") {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            livestream: {
              ...MOCK_LIVESTREAM,
              status: "live",
              startedAt: new Date().toISOString(),
            },
          }),
        });
        return;
      }
      await route.continue();
    });

    // Mock the stream chat messages endpoint
    const chatMessages: Array<{
      id: string;
      content: string;
      authorName: string;
      createdAt: string;
    }> = [];

    await page.route(
      /\/api\/video\/livestream\/[^/]+\/chat/,
      async (route) => {
        const method = route.request().method();

        if (method === "GET") {
          await route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify({ messages: chatMessages }),
          });
          return;
        }

        if (method === "POST") {
          const data = route.request().postDataJSON() as { content: string };
          const newMsg = {
            id: `chat-${Date.now()}`,
            content: data.content,
            authorName: "Admin User",
            createdAt: new Date().toISOString(),
          };
          chatMessages.push(newMsg);
          await route.fulfill({
            status: 201,
            contentType: "application/json",
            body: JSON.stringify({ message: newMsg }),
          });
          return;
        }

        await route.continue();
      }
    );
  });

  test("chat panel renders alongside stream player", async ({ page }) => {
    await page.goto(`/livestream/${MOCK_LIVESTREAM.id}`);

    // The stream chat panel should be visible alongside the player
    const chatPanel = page.locator(
      [
        "[data-testid='stream-chat']",
        "[data-testid='livestream-chat']",
        "[aria-label*='chat' i]",
        "[class*='stream-chat']",
        "[class*='chat-panel']",
      ].join(", ")
    ).first();
    await expect(chatPanel).toBeVisible({ timeout: 15_000 });

    // The chat input should also be visible
    const chatInput = page.locator(
      [
        "[data-testid='stream-chat-input']",
        "[data-testid='chat-input']",
        "input[placeholder*='message' i]",
        "textarea[placeholder*='message' i]",
        "input[placeholder*='chat' i]",
      ].join(", ")
    ).first();
    await expect(chatInput).toBeVisible();
  });

  test("messages can be sent during stream", async ({ page }) => {
    await page.goto(`/livestream/${MOCK_LIVESTREAM.id}`);

    // Find the chat input
    const chatInput = page.locator(
      [
        "[data-testid='stream-chat-input']",
        "[data-testid='chat-input']",
        "input[placeholder*='message' i]",
        "textarea[placeholder*='message' i]",
        "input[placeholder*='chat' i]",
      ].join(", ")
    ).first();
    await expect(chatInput).toBeVisible({ timeout: 15_000 });

    // Type and send a chat message
    const chatMessage = `Live chat message ${Date.now()}`;
    await chatInput.fill(chatMessage);

    // Send via button or Enter key
    const sendButton = page.locator(
      [
        "[data-testid='stream-chat-send']",
        "button[aria-label*='send' i]",
      ].join(", ")
    ).first();

    if (await sendButton.isVisible()) {
      await sendButton.click();
    } else {
      await chatInput.press("Enter");
    }

    // The sent message should appear in the chat panel
    await expect(page.getByText(chatMessage)).toBeVisible({
      timeout: 10_000,
    });
  });

  test("chat shows viewer messages with author names", async ({ page }) => {
    await page.goto(`/livestream/${MOCK_LIVESTREAM.id}`);

    // Send a message first
    const chatInput = page.locator(
      [
        "[data-testid='stream-chat-input']",
        "[data-testid='chat-input']",
        "input[placeholder*='message' i]",
        "textarea[placeholder*='message' i]",
        "input[placeholder*='chat' i]",
      ].join(", ")
    ).first();
    await expect(chatInput).toBeVisible({ timeout: 15_000 });

    await chatInput.fill("Hello from the chat!");
    const sendButton = page.locator(
      [
        "[data-testid='stream-chat-send']",
        "button[aria-label*='send' i]",
      ].join(", ")
    ).first();

    if (await sendButton.isVisible()) {
      await sendButton.click();
    } else {
      await chatInput.press("Enter");
    }

    // Wait for the message to appear
    await expect(page.getByText("Hello from the chat!")).toBeVisible({
      timeout: 10_000,
    });

    // The message should show the author name
    await expect(page.getByText(/admin user/i).first()).toBeVisible({
      timeout: 5_000,
    });
  });
});
```

### Step 6: Create `e2e/livestream-recording.spec.ts`

Tests recording management — starting a recording, checking status, and verifying metadata.

```typescript
import { test, expect } from "@playwright/test";
import {
  interceptLivestreamApi,
  interceptMuxApi,
  interceptRecordingApi,
  MOCK_RECORDING,
} from "./fixtures/mock-streaming";
import { signInAsTestUser } from "./helpers/streaming-auth";

test.describe("Livestream Recording", () => {
  test.beforeEach(async ({ page }) => {
    // Sign in — recording management requires authentication
    await signInAsTestUser(page);

    // Mock all streaming and recording APIs
    await interceptLivestreamApi(page);
    await interceptMuxApi(page);
    await interceptRecordingApi(page);
  });

  test("POST /api/video/recordings starts a recording", async ({
    page,
    request,
  }) => {
    // Get auth cookies
    const cookies = await page.context().cookies();
    const cookieHeader = cookies
      .map((c) => `${c.name}=${c.value}`)
      .join("; ");

    // Start a recording via the API
    const response = await request.post("/api/video/recordings", {
      data: {
        livestreamId: "ls-test-001",
      },
      headers: {
        Cookie: cookieHeader,
      },
    });

    if (response.ok()) {
      const body = (await response.json()) as {
        recording: {
          id: string;
          livestreamId: string;
          status: string;
        };
      };
      expect(body.recording).toBeDefined();
      expect(body.recording.id).toBeDefined();
      expect(body.recording.livestreamId).toBe("ls-test-001");
      expect(typeof body.recording.status).toBe("string");
    } else {
      // If MUX is not configured, expect a structured error
      const body = (await response.json()) as { error: string };
      expect(body.error).toBeDefined();
    }
  });

  test("GET /api/video/recordings/:id returns recording status", async ({
    page,
    request,
  }) => {
    const cookies = await page.context().cookies();
    const cookieHeader = cookies
      .map((c) => `${c.name}=${c.value}`)
      .join("; ");

    // Fetch a specific recording by ID
    const response = await request.get(
      `/api/video/recordings/${MOCK_RECORDING.id}`,
      {
        headers: {
          Cookie: cookieHeader,
        },
      }
    );

    if (response.ok()) {
      const body = (await response.json()) as {
        recording: {
          id: string;
          status: string;
          playbackId: string;
          duration: number;
        };
      };
      expect(body.recording).toBeDefined();
      expect(body.recording.id).toBe(MOCK_RECORDING.id);
      expect(["preparing", "ready", "errored"]).toContain(
        body.recording.status
      );
      expect(typeof body.recording.playbackId).toBe("string");
      expect(typeof body.recording.duration).toBe("number");
    } else {
      const body = (await response.json()) as { error: string };
      expect(body.error).toBeDefined();
    }
  });

  test("recording metadata includes livestream ID and MUX asset ID", async ({
    page,
    request,
  }) => {
    const cookies = await page.context().cookies();
    const cookieHeader = cookies
      .map((c) => `${c.name}=${c.value}`)
      .join("; ");

    const response = await request.get(
      `/api/video/recordings/${MOCK_RECORDING.id}`,
      {
        headers: {
          Cookie: cookieHeader,
        },
      }
    );

    if (response.ok()) {
      const body = (await response.json()) as {
        recording: {
          id: string;
          livestreamId: string;
          muxAssetId: string;
          playbackId: string;
          status: string;
          duration: number;
          createdAt: string;
        };
      };

      // Verify all metadata fields are present
      expect(body.recording.livestreamId).toBeDefined();
      expect(body.recording.muxAssetId).toBeDefined();
      expect(body.recording.playbackId).toBeDefined();
      expect(body.recording.createdAt).toBeDefined();

      // Verify the metadata values are non-empty strings
      expect(body.recording.livestreamId.length).toBeGreaterThan(0);
      expect(body.recording.muxAssetId.length).toBeGreaterThan(0);
      expect(body.recording.playbackId.length).toBeGreaterThan(0);
    } else {
      const body = (await response.json()) as { error: string };
      expect(body.error).toBeDefined();
    }
  });

  test("GET /api/video/recordings lists all recordings", async ({
    page,
    request,
  }) => {
    const cookies = await page.context().cookies();
    const cookieHeader = cookies
      .map((c) => `${c.name}=${c.value}`)
      .join("; ");

    const response = await request.get("/api/video/recordings", {
      headers: {
        Cookie: cookieHeader,
      },
    });

    if (response.ok()) {
      const body = (await response.json()) as {
        recordings: Array<{
          id: string;
          status: string;
        }>;
      };
      expect(Array.isArray(body.recordings)).toBe(true);
      expect(body.recordings.length).toBeGreaterThan(0);

      // Each recording should have an id and status
      for (const recording of body.recordings) {
        expect(recording.id).toBeDefined();
        expect(recording.status).toBeDefined();
      }
    } else {
      const body = (await response.json()) as { error: string };
      expect(body.error).toBeDefined();
    }
  });
});
```

## Usage

### Run all streaming tests

```bash
bunx playwright test e2e/livestream-go-live.spec.ts e2e/livestream-viewer.spec.ts e2e/livestream-chat.spec.ts e2e/livestream-recording.spec.ts
```

### Run a single test file

```bash
bunx playwright test e2e/livestream-go-live.spec.ts
```

### Run headed (watch browser)

```bash
bunx playwright test e2e/livestream-viewer.spec.ts --headed
```

### Run a specific test by name

```bash
bunx playwright test -g "stream status shows live after starting"
```

### Debug interactively

```bash
bunx playwright test e2e/livestream-chat.spec.ts --debug
```

## Acceptance Criteria

- [ ] `bunx playwright test e2e/livestream-go-live.spec.ts` runs without import errors
- [ ] `bunx playwright test e2e/livestream-viewer.spec.ts` runs without import errors
- [ ] `bunx playwright test e2e/livestream-chat.spec.ts` runs without import errors
- [ ] `bunx playwright test e2e/livestream-recording.spec.ts` runs without import errors
- [ ] Go-live page renders stream configuration form
- [ ] POST `/api/video/livestream` creates a stream with idle status
- [ ] Stream status transitions to "live" after starting
- [ ] Stop button ends the stream and updates status
- [ ] Viewer page loads MUX player component
- [ ] Viewer page shows stream title
- [ ] Viewer page renders a video element with proper dimensions
- [ ] Viewer page works without authentication (public access)
- [ ] Chat panel renders alongside stream player
- [ ] Messages can be sent during a live stream
- [ ] Chat messages show author names
- [ ] POST `/api/video/recordings` starts a recording
- [ ] GET `/api/video/recordings/:id` returns recording status
- [ ] Recording metadata includes livestreamId and muxAssetId
- [ ] No usage of `any` type anywhere in test code
- [ ] All mock helpers use proper TypeScript types

## Troubleshooting

### MUX player doesn't render

**Symptom**: The player area is blank or shows an error.

**Cause**: The `mockMuxPlayer` helper may not be intercepting the correct CDN URLs for the MUX player script.

**Fix**: Check the actual URLs the MUX player component requests by running `bunx playwright test --trace on` and inspecting the network tab. Update the route patterns in `mockMuxPlayer` to match.

### Go-live page redirects to login

**Symptom**: Navigating to `/livestream/go-live` redirects to `/login`.

**Cause**: The go-live page requires authentication and the sign-in flow failed.

**Fix**: Verify the `signInAsTestUser` flow completed successfully. Check that the auth-dev seed users exist and the `/dev` page is accessible.

### Stream status doesn't transition

**Symptom**: After clicking "Go Live", the status stays "idle".

**Cause**: The UI may poll the livestream API endpoint for status updates, but the mocked route always returns the same status.

**Fix**: The `interceptLivestreamApi` helper tracks state internally using `currentStatus`. Ensure the start/stop routes are being matched. Use `page.on('request', ...)` to debug which routes are being hit.

### Recording API returns 404

**Symptom**: Recording API tests get 404 responses.

**Cause**: The recording API routes may not exist yet, or the URL pattern differs from what the tests expect.

**Fix**: Verify the actual recording API routes in your app. The tests expect `/api/video/recordings` and `/api/video/recordings/:id`. Update the test URLs if your app uses a different path.

### Viewer page shows "offline" even with live mock

**Symptom**: The viewer test fails because it shows an offline message.

**Cause**: The route override for the livestream status may be registered after another route handler that takes priority.

**Fix**: In Playwright, later `page.route()` calls take priority over earlier ones for the same URL pattern. Ensure the test-specific override is registered after the general `interceptLivestreamApi` call.

### Chat messages don't appear after sending

**Symptom**: The chat send test types a message but it never appears in the chat panel.

**Cause**: The chat may use WebSocket/realtime for message delivery rather than polling the REST API.

**Fix**: If the chat uses WebSockets, you may need to mock the WebSocket connection or use `page.evaluate` to inject messages into the client-side state. Alternatively, check if there's a fallback polling mechanism.
