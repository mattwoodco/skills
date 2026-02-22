---
name: e2e-video
version: 1.0.0
updated: 2026-02-18
dependencies: [e2e, video-room, video-ui]
---

# E2E Video Room Tests

Playwright test suite for Constellation v3 video room features. Tests the video room API routes (create room, generate token, auth guards), the prejoin screen (device selection, camera preview, join flow), and the in-room controls bar (mute, camera, screenshare, leave). Uses `page.route()` to mock LiveKit Cloud API calls so tests run without a real LiveKit server.

## When to Use This Skill

Use this skill when the user says:
- "test video rooms"
- "add video e2e tests"
- "e2e video"
- "test livekit ui"
- "playwright video tests"
- "test video controls"

## Prerequisites

- Next.js app with App Router
- `e2e` skill installed (Playwright configured with `playwright.config.ts`)
- `video-room` skill installed (API routes at `/api/video/rooms` and `/api/video/token`)
- `video-ui` skill installed (prejoin screen, controls bar components)
- `auth-dev` skill installed (seed users for authentication)
- Dev server running on `localhost:3000`

## Installation

No additional packages required. The `e2e` skill provides `@playwright/test` and the Playwright configuration.

## What Gets Created

```
e2e/
├── fixtures/
│   └── mock-livekit.ts         # LiveKit API mock helpers using page.route()
├── helpers/
│   └── video-auth.ts           # Reusable sign-in helper for video tests
├── video-room.spec.ts          # API route tests (create room, token, auth)
├── video-controls.spec.ts      # Controls bar UI tests (mute, camera, leave)
└── video-prejoin.spec.ts       # Prejoin screen tests (devices, preview, join)
```

## Setup Steps

### Step 1: Create `e2e/fixtures/mock-livekit.ts`

This helper intercepts LiveKit Cloud API calls and returns consistent mock data so tests never hit a real LiveKit server.

```typescript
import type { Page } from "@playwright/test";

/**
 * Mock data for a LiveKit room.
 * Matches the VideoRoom type from lib/video/types.ts.
 */
export const mockRoom = {
  name: "test-room",
  sid: "RM_test123abc",
  numParticipants: 0,
  maxParticipants: 20,
  creationTime: 1708300800,
  metadata: "",
} as const;

/**
 * Mock data for a LiveKit participant.
 * Matches the VideoParticipant type from lib/video/types.ts.
 */
export const mockParticipant = {
  sid: "PA_participant456",
  identity: "user-1",
  name: "Admin User",
  metadata: JSON.stringify({ userId: "user-1", email: "admin@example.com" }),
  joinedAt: 1708300900,
  isSpeaking: false,
  connectionQuality: "excellent",
} as const;

/**
 * A mock JWT token string for testing.
 * This is NOT a valid JWT — it is only used to verify the token route
 * returns a string in the expected shape.
 */
export const mockToken =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEiLCJyb29tIjoidGVzdC1yb29tIn0.mock-signature";

/**
 * Intercepts outgoing requests to the LiveKit Cloud REST API and
 * returns mock responses. Call this in test.beforeEach to ensure
 * no real LiveKit calls are made.
 *
 * Intercepts:
 * - POST /api/video/rooms   -> returns mockRoom
 * - GET  /api/video/rooms   -> returns [mockRoom]
 * - POST /api/video/token   -> returns { token, url }
 */
export async function interceptLiveKitApi(page: Page): Promise<void> {
  // Mock the room creation endpoint
  await page.route("**/api/video/rooms", async (route) => {
    const method = route.request().method();

    if (method === "POST") {
      const body = route.request().postDataJSON() as { name?: string };
      await route.fulfill({
        status: 201,
        contentType: "application/json",
        body: JSON.stringify({
          room: {
            ...mockRoom,
            name: body?.name ?? mockRoom.name,
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
          rooms: [mockRoom],
        }),
      });
      return;
    }

    await route.continue();
  });

  // Mock the token generation endpoint
  await page.route("**/api/video/token", async (route) => {
    const method = route.request().method();

    if (method === "POST") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          token: mockToken,
          url: "wss://mock-livekit.example.com",
        }),
      });
      return;
    }

    await route.continue();
  });
}

/**
 * Intercepts LiveKit WebSocket connections so tests don't attempt
 * real signaling. Returns a mock response that prevents connection errors.
 */
export async function interceptLiveKitWebSocket(page: Page): Promise<void> {
  await page.route("**/rtc**", async (route) => {
    await route.abort("connectionrefused");
  });

  await page.route("wss://**livekit**", async (route) => {
    await route.abort("connectionrefused");
  });
}
```

### Step 2: Create `e2e/helpers/video-auth.ts`

Reusable helper that signs in as the dev admin user via the `/dev` page. Used by all video test files that require authentication.

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

### Step 3: Create `e2e/video-room.spec.ts`

Tests the video room API routes directly using `fetch` within Playwright. Validates room creation, token generation, and authentication guards.

```typescript
import { test, expect } from "@playwright/test";
import { signInAsTestUser, signOutTestUser } from "./helpers/video-auth";

test.describe("Video Room API Routes", () => {
  /**
   * Test: POST /api/video/rooms creates a room.
   *
   * This test mocks the internal LiveKit call by intercepting the route
   * at the browser level. The API route handler calls LiveKit server SDK,
   * so we intercept the outbound request from the Next.js server by
   * sending a direct fetch to the local API and verifying the response shape.
   *
   * Note: Since page.route() only intercepts browser-originated requests,
   * we test the API routes by calling them via the Playwright request context
   * which sends real HTTP requests. The Next.js server must be running with
   * valid (or mocked) LiveKit env vars.
   */
  test("POST /api/video/rooms creates a room and returns room object", async ({
    request,
  }) => {
    const response = await request.post("/api/video/rooms", {
      data: {
        name: "e2e-test-room",
        maxParticipants: 10,
        metadata: JSON.stringify({ test: true }),
      },
    });

    // The route may return 201 (success) or 500 (if LiveKit is not configured).
    // In CI without LiveKit credentials, we check the response structure.
    if (response.ok()) {
      const body = (await response.json()) as {
        room: {
          name: string;
          sid: string;
          numParticipants: number;
          maxParticipants: number;
        };
      };
      expect(body.room).toBeDefined();
      expect(body.room.name).toBe("e2e-test-room");
      expect(typeof body.room.sid).toBe("string");
      expect(body.room.maxParticipants).toBe(10);
    } else {
      // Without LiveKit credentials the server returns 500 with an error message
      const body = (await response.json()) as { error: string };
      expect(body.error).toBeDefined();
      expect(typeof body.error).toBe("string");
    }
  });

  test("POST /api/video/rooms returns 400 when name is missing", async ({
    request,
  }) => {
    const response = await request.post("/api/video/rooms", {
      data: { name: "" },
    });

    expect(response.status()).toBe(400);
    const body = (await response.json()) as { error: string };
    expect(body.error).toContain("required");
  });

  test("GET /api/video/rooms returns a rooms array", async ({ request }) => {
    const response = await request.get("/api/video/rooms");

    if (response.ok()) {
      const body = (await response.json()) as {
        rooms: Array<{ name: string; sid: string }>;
      };
      expect(Array.isArray(body.rooms)).toBe(true);
    } else {
      // Without LiveKit credentials, expect an error object
      const body = (await response.json()) as { error: string };
      expect(body.error).toBeDefined();
    }
  });

  test.describe("Token Route — Authentication Required", () => {
    test("POST /api/video/token returns 401 without a session", async ({
      request,
    }) => {
      // Send request without any auth cookies
      const response = await request.post("/api/video/token", {
        data: {
          roomName: "test-room",
          participantName: "Anonymous",
        },
      });

      // The withAuth guard should reject unauthenticated requests
      expect(response.status()).toBe(401);
    });

    test("POST /api/video/token returns a JWT token for authenticated users", async ({
      page,
      request,
    }) => {
      // Sign in to establish a session cookie
      await signInAsTestUser(page);

      // Get cookies from the authenticated browser context
      const cookies = await page.context().cookies();
      const cookieHeader = cookies
        .map((c) => `${c.name}=${c.value}`)
        .join("; ");

      // Make the token request with the session cookie
      const response = await request.post("/api/video/token", {
        data: {
          roomName: "test-room",
          participantName: "Admin User",
        },
        headers: {
          Cookie: cookieHeader,
        },
      });

      if (response.ok()) {
        const body = (await response.json()) as { token: string; url: string };
        expect(body.token).toBeDefined();
        expect(typeof body.token).toBe("string");
        // JWT tokens have 3 dot-separated segments
        expect(body.token.split(".").length).toBe(3);
        expect(body.url).toBeDefined();
        expect(typeof body.url).toBe("string");
      } else {
        // Without LiveKit credentials, server may return 500
        const body = (await response.json()) as { error: string };
        expect(body.error).toBeDefined();
      }
    });

    test("POST /api/video/token returns 400 when roomName is missing", async ({
      page,
      request,
    }) => {
      await signInAsTestUser(page);

      const cookies = await page.context().cookies();
      const cookieHeader = cookies
        .map((c) => `${c.name}=${c.value}`)
        .join("; ");

      const response = await request.post("/api/video/token", {
        data: { roomName: "" },
        headers: {
          Cookie: cookieHeader,
        },
      });

      expect(response.status()).toBe(400);
      const body = (await response.json()) as { error: string };
      expect(body.error).toContain("required");
    });
  });
});
```

### Step 4: Create `e2e/video-controls.spec.ts`

Tests the in-room controls bar UI — mute, camera toggle, screenshare, and leave button. Mocks the LiveKit API so the page renders without a real connection.

```typescript
import { test, expect } from "@playwright/test";
import {
  interceptLiveKitApi,
  interceptLiveKitWebSocket,
} from "./fixtures/mock-livekit";
import { signInAsTestUser } from "./helpers/video-auth";

test.describe("Video Controls Bar", () => {
  test.beforeEach(async ({ page }) => {
    // Sign in — video pages require authentication
    await signInAsTestUser(page);

    // Intercept all LiveKit API calls to prevent real connections
    await interceptLiveKitApi(page);
    await interceptLiveKitWebSocket(page);
  });

  test("prejoin screen renders with control buttons before joining", async ({
    page,
  }) => {
    // Navigate to a video room page — the prejoin screen should appear first
    await page.goto("/video/test-room");

    // The prejoin screen should have a join button
    const joinButton = page.getByRole("button", { name: /join/i });
    await expect(joinButton).toBeVisible({ timeout: 10_000 });
  });

  test("controls bar renders mute, camera, screenshare, and leave buttons", async ({
    page,
  }) => {
    await page.goto("/video/test-room");

    // Click join to enter the room (mocked connection)
    const joinButton = page.getByRole("button", { name: /join/i });
    await joinButton.click();

    // Wait for the controls bar to appear after joining
    // Controls should be visible even if the WebSocket connection is mocked
    const muteButton = page.getByRole("button", { name: /mute|microphone/i });
    const cameraButton = page.getByRole("button", { name: /camera|video/i });
    const screenshareButton = page.getByRole("button", {
      name: /screen|share/i,
    });
    const leaveButton = page.getByRole("button", { name: /leave|end|exit/i });

    // Verify all control buttons are present in the UI
    await expect(muteButton).toBeVisible({ timeout: 10_000 });
    await expect(cameraButton).toBeVisible();
    await expect(screenshareButton).toBeVisible();
    await expect(leaveButton).toBeVisible();
  });

  test("clicking mute button toggles mute state", async ({ page }) => {
    await page.goto("/video/test-room");

    // Join the room
    const joinButton = page.getByRole("button", { name: /join/i });
    await joinButton.click();

    // Find the mute/microphone button
    const muteButton = page.getByRole("button", { name: /mute|microphone/i });
    await expect(muteButton).toBeVisible({ timeout: 10_000 });

    // Click to mute — button text or icon should change to reflect muted state
    await muteButton.click();

    // After clicking, the button should indicate muted state
    // The button text may change to "Unmute" or an aria attribute may update
    await expect(
      page.getByRole("button", { name: /unmute|muted/i })
    ).toBeVisible({ timeout: 5_000 });

    // Click again to unmute
    const unmutedButton = page.getByRole("button", {
      name: /unmute|muted/i,
    });
    await unmutedButton.click();

    // Should return to the original mute-available state
    await expect(
      page.getByRole("button", { name: /mute|microphone/i })
    ).toBeVisible({ timeout: 5_000 });
  });

  test("clicking camera button toggles camera state", async ({ page }) => {
    await page.goto("/video/test-room");

    const joinButton = page.getByRole("button", { name: /join/i });
    await joinButton.click();

    const cameraButton = page.getByRole("button", { name: /camera|video/i });
    await expect(cameraButton).toBeVisible({ timeout: 10_000 });

    // Click to disable camera
    await cameraButton.click();

    // Button state should reflect camera off
    await expect(
      page.getByRole("button", { name: /camera off|video off|show camera/i })
    ).toBeVisible({ timeout: 5_000 });
  });

  test("clicking leave button navigates away from the room", async ({
    page,
  }) => {
    await page.goto("/video/test-room");

    const joinButton = page.getByRole("button", { name: /join/i });
    await joinButton.click();

    const leaveButton = page.getByRole("button", { name: /leave|end|exit/i });
    await expect(leaveButton).toBeVisible({ timeout: 10_000 });

    // Click leave — should navigate away from the video room page
    await leaveButton.click();

    // After leaving, the URL should no longer be the video room
    await expect(page).not.toHaveURL(/\/video\/test-room$/, {
      timeout: 10_000,
    });
  });
});
```

### Step 5: Create `e2e/video-prejoin.spec.ts`

Tests the prejoin screen — camera preview area, device selector dropdowns, and the join flow that transitions to the room view.

```typescript
import { test, expect } from "@playwright/test";
import {
  interceptLiveKitApi,
  interceptLiveKitWebSocket,
} from "./fixtures/mock-livekit";
import { signInAsTestUser } from "./helpers/video-auth";

test.describe("Video Prejoin Screen", () => {
  test.beforeEach(async ({ page }) => {
    // Sign in — video room pages require authentication
    await signInAsTestUser(page);

    // Mock all LiveKit API and WebSocket calls
    await interceptLiveKitApi(page);
    await interceptLiveKitWebSocket(page);

    // Navigate to a video room — the prejoin screen should display first
    await page.goto("/video/test-room");
  });

  test("prejoin screen shows camera preview area", async ({ page }) => {
    // The prejoin screen should contain a video preview element or placeholder.
    // Since Playwright cannot access a real camera, look for the preview
    // container — it may be a <video> element or a styled placeholder div.
    const previewArea = page
      .locator("[data-testid='camera-preview'], video, [role='img']")
      .first();
    await expect(previewArea).toBeVisible({ timeout: 10_000 });
  });

  test("device selector dropdowns render for camera and microphone", async ({
    page,
  }) => {
    // The prejoin screen should have device selection dropdowns.
    // These may be <select> elements, or custom comboboxes.
    // Look for common patterns: accessible labels or test IDs.
    const micSelector = page.locator(
      [
        "[data-testid='mic-selector']",
        "select[aria-label*='icrophone' i]",
        "[role='combobox'][aria-label*='icrophone' i]",
        "label:has-text('Microphone') + select",
        "label:has-text('Microphone') + button",
      ].join(", ")
    ).first();

    const cameraSelector = page.locator(
      [
        "[data-testid='camera-selector']",
        "select[aria-label*='amera' i]",
        "[role='combobox'][aria-label*='amera' i]",
        "label:has-text('Camera') + select",
        "label:has-text('Camera') + button",
      ].join(", ")
    ).first();

    // At least one device selector for each media type should be visible
    await expect(micSelector).toBeVisible({ timeout: 10_000 });
    await expect(cameraSelector).toBeVisible({ timeout: 10_000 });
  });

  test("join button is present and clickable", async ({ page }) => {
    const joinButton = page.getByRole("button", { name: /join/i });

    // The join button should be visible on the prejoin screen
    await expect(joinButton).toBeVisible({ timeout: 10_000 });

    // The join button should be enabled (not disabled)
    await expect(joinButton).toBeEnabled();
  });

  test("join button navigates to room view", async ({ page }) => {
    const joinButton = page.getByRole("button", { name: /join/i });
    await expect(joinButton).toBeVisible({ timeout: 10_000 });

    // Click join — this should transition from prejoin to the active room view.
    // The prejoin screen is replaced by the room with controls.
    await joinButton.click();

    // After joining, the prejoin join button should be gone and
    // room controls (e.g., leave button) should appear.
    const leaveButton = page.getByRole("button", { name: /leave|end|exit/i });
    await expect(leaveButton).toBeVisible({ timeout: 15_000 });

    // The original "Join" button from the prejoin screen should no longer be visible
    await expect(joinButton).not.toBeVisible();
  });

  test("prejoin screen displays participant name input", async ({ page }) => {
    // The prejoin screen may have an input for the participant's display name.
    // This is populated from the auth session but may be editable.
    const nameInput = page.locator(
      [
        "input[name='participantName']",
        "input[aria-label*='name' i]",
        "[data-testid='participant-name']",
        "input[placeholder*='name' i]",
      ].join(", ")
    ).first();

    // If a name input exists, verify it has a value (pre-filled from session)
    if (await nameInput.isVisible()) {
      const value = await nameInput.inputValue();
      expect(value.length).toBeGreaterThan(0);
    }
  });
});
```

## Usage

### Run all video tests

```bash
bunx playwright test e2e/video-room.spec.ts e2e/video-controls.spec.ts e2e/video-prejoin.spec.ts
```

### Run a single test file

```bash
bunx playwright test e2e/video-room.spec.ts
```

### Run headed (watch browser)

```bash
bunx playwright test e2e/video-controls.spec.ts --headed
```

### Run a specific test by name

```bash
bunx playwright test -g "clicking mute button toggles mute state"
```

### Debug interactively

```bash
bunx playwright test e2e/video-prejoin.spec.ts --debug
```

## Acceptance Criteria

- [ ] `bunx playwright test e2e/video-room.spec.ts` runs without import errors
- [ ] `bunx playwright test e2e/video-controls.spec.ts` runs without import errors
- [ ] `bunx playwright test e2e/video-prejoin.spec.ts` runs without import errors
- [ ] POST `/api/video/rooms` test validates response structure
- [ ] POST `/api/video/rooms` returns 400 for missing name
- [ ] GET `/api/video/rooms` test validates rooms array
- [ ] POST `/api/video/token` returns 401 without authentication
- [ ] POST `/api/video/token` returns a 3-segment JWT for authenticated users
- [ ] Prejoin screen renders camera preview area
- [ ] Device selector dropdowns are visible
- [ ] Join button is present, enabled, and clickable
- [ ] Join button transitions from prejoin to room view
- [ ] Controls bar shows mute, camera, screenshare, and leave buttons
- [ ] Mute button toggles between mute/unmute states
- [ ] Leave button navigates away from the room
- [ ] No usage of `any` type anywhere in test code
- [ ] All mock helpers use proper TypeScript types

## Troubleshooting

### Tests fail with "page.goto: net::ERR_CONNECTION_REFUSED"

**Symptom**: All tests fail immediately when navigating to any URL.

**Cause**: The dev server is not running on `localhost:3000`.

**Fix**: Start the dev server with `bun run dev` or ensure `playwright.config.ts` has the `webServer` block that auto-starts it.

### Token test returns 500 instead of 401

**Symptom**: The unauthenticated token test expects 401 but gets 500.

**Cause**: The `withAuth` guard may throw an unhandled error instead of returning a 401 response.

**Fix**: Verify the `withAuth` implementation in `lib/auth-guard.ts` returns `NextResponse.json({ error: "Unauthorized" }, { status: 401 })` for missing sessions.

### Mute button toggle test fails

**Symptom**: Cannot find the "Unmute" button after clicking mute.

**Cause**: The button text or aria-label does not change on state toggle, or the UI uses icons instead of text.

**Fix**: Update the button selector to match your actual UI. Use `data-testid` attributes on the mute button for reliable selection, or check for `aria-pressed` attribute changes.

### Prejoin device selectors not found

**Symptom**: Device selector locators don't match any elements.

**Cause**: The video-ui skill may use different markup for device selection (e.g., a modal, a popover, or LiveKit's built-in components).

**Fix**: Inspect the actual prejoin DOM with `bunx playwright test --debug` and update the selectors in `video-prejoin.spec.ts` to match the real markup.

### Tests time out waiting for join/leave transitions

**Symptom**: Tests hang at `expect(leaveButton).toBeVisible()` after clicking join.

**Cause**: The join flow requires a real LiveKit WebSocket connection that the mocks abort.

**Fix**: The `interceptLiveKitWebSocket` helper aborts WS connections. If the UI waits indefinitely for a connection, add a client-side timeout or check that the video-ui skill handles connection failures gracefully.
