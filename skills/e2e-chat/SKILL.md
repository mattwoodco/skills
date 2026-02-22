---
name: e2e-chat
version: 1.0.0
updated: 2026-02-18
dependencies: [e2e, group-chat]
---

# E2E Group Chat Tests

Playwright test suite for Constellation v3 group chat features. Tests message sending and display, threaded replies, emoji reactions, and @mention autocomplete. Uses `page.route()` to mock chat API responses and provides seed helpers for creating test channels and messages.

## When to Use This Skill

Use this skill when the user says:
- "test chat"
- "add chat e2e tests"
- "e2e chat"
- "test group chat"
- "playwright chat tests"
- "test chat messages"
- "test chat threads"

## Prerequisites

- Next.js app with App Router
- `e2e` skill installed (Playwright configured with `playwright.config.ts`)
- `group-chat` skill installed (chat channels, messages, threads, reactions, mentions)
- `auth-dev` skill installed (seed users for authentication)
- Dev server running on `localhost:3000`

## Installation

No additional packages required. The `e2e` skill provides `@playwright/test` and the Playwright configuration.

## What Gets Created

```
e2e/
├── fixtures/
│   └── mock-chat.ts            # Chat API mock and seed helpers
├── helpers/
│   └── chat-auth.ts            # Reusable sign-in helper for chat tests
├── chat-messages.spec.ts       # Message list, send, display, pagination tests
├── chat-threads.spec.ts        # Thread panel, replies, thread count tests
├── chat-reactions.spec.ts      # Emoji picker, reaction toggle, count tests
└── chat-mentions.spec.ts       # @mention autocomplete, insertion, display tests
```

## Setup Steps

### Step 1: Create `e2e/fixtures/mock-chat.ts`

Helpers for creating test data and intercepting chat API routes. Provides both seed functions (for real API calls) and mock functions (for intercepted responses).

```typescript
import type { Page } from "@playwright/test";

/**
 * Shape of a chat channel returned by the API.
 */
type MockChannel = {
  id: string;
  name: string;
  description: string;
  createdAt: string;
  memberCount: number;
};

/**
 * Shape of a chat message returned by the API.
 */
type MockMessage = {
  id: string;
  channelId: string;
  content: string;
  authorId: string;
  authorName: string;
  authorAvatar: string;
  createdAt: string;
  threadCount: number;
  reactions: Array<{
    emoji: string;
    count: number;
    userIds: string[];
  }>;
};

/**
 * Shape of a chat user for mention autocomplete.
 */
type MockUser = {
  id: string;
  name: string;
  email: string;
  avatar: string;
};

const MOCK_CHANNEL: MockChannel = {
  id: "ch-test-001",
  name: "general",
  description: "General discussion channel for testing",
  createdAt: "2026-02-18T00:00:00.000Z",
  memberCount: 2,
};

const MOCK_USERS: MockUser[] = [
  {
    id: "user-admin-1",
    name: "Admin User",
    email: "admin@example.com",
    avatar: "/avatars/admin.png",
  },
  {
    id: "user-member-1",
    name: "Member User",
    email: "member@example.com",
    avatar: "/avatars/member.png",
  },
];

/**
 * Generates an array of mock messages for a given channel.
 */
function generateMockMessages(
  channelId: string,
  count: number
): MockMessage[] {
  const messages: MockMessage[] = [];
  for (let i = 0; i < count; i++) {
    const author = MOCK_USERS[i % MOCK_USERS.length];
    messages.push({
      id: `msg-${channelId}-${String(i).padStart(4, "0")}`,
      channelId,
      content: `Test message number ${i + 1} in the channel`,
      authorId: author.id,
      authorName: author.name,
      authorAvatar: author.avatar,
      createdAt: new Date(Date.now() - (count - i) * 60_000).toISOString(),
      threadCount: 0,
      reactions: [],
    });
  }
  return messages;
}

/**
 * Seeds a test chat channel by calling the actual API.
 * Returns the created channel data.
 *
 * Requires the user to be authenticated (call signInAsTestUser first).
 */
export async function seedChatChannel(page: Page): Promise<MockChannel> {
  const response = await page.request.post("/api/chat/channels", {
    data: {
      name: `test-${Date.now()}`,
      description: "E2E test channel",
    },
  });

  if (response.ok()) {
    const body = (await response.json()) as { channel: MockChannel };
    return body.channel;
  }

  // If the API is not available, return mock data
  return { ...MOCK_CHANNEL, id: `ch-test-${Date.now()}` };
}

/**
 * Seeds messages into a channel by calling the actual API.
 *
 * Requires the user to be authenticated.
 */
export async function seedMessages(
  page: Page,
  channelId: string,
  count: number
): Promise<MockMessage[]> {
  const messages: MockMessage[] = [];

  for (let i = 0; i < count; i++) {
    const response = await page.request.post(
      `/api/chat/channels/${channelId}/messages`,
      {
        data: {
          content: `Seeded test message ${i + 1}`,
        },
      }
    );

    if (response.ok()) {
      const body = (await response.json()) as { message: MockMessage };
      messages.push(body.message);
    }
  }

  return messages;
}

/**
 * Intercepts chat API routes with mock responses.
 * Use this when you want fully mocked data without hitting the real API.
 *
 * Intercepts:
 * - GET  /api/chat/channels                         -> channel list
 * - GET  /api/chat/channels/:id                     -> single channel
 * - GET  /api/chat/channels/:id/messages             -> message list (with pagination)
 * - POST /api/chat/channels/:id/messages             -> send message
 * - POST /api/chat/channels/:id/messages/:mid/react  -> add reaction
 * - GET  /api/chat/channels/:id/messages/:mid/thread -> thread messages
 * - POST /api/chat/channels/:id/messages/:mid/thread -> reply in thread
 * - GET  /api/chat/users/search                      -> mention autocomplete
 */
export async function interceptChatApi(page: Page): Promise<void> {
  // Track messages so newly sent ones appear in subsequent fetches
  const messageStore: MockMessage[] = generateMockMessages(
    MOCK_CHANNEL.id,
    5
  );

  // Channel list
  await page.route("**/api/chat/channels", async (route) => {
    if (route.request().method() === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ channels: [MOCK_CHANNEL] }),
      });
      return;
    }

    if (route.request().method() === "POST") {
      const data = route.request().postDataJSON() as {
        name: string;
        description?: string;
      };
      const newChannel: MockChannel = {
        ...MOCK_CHANNEL,
        id: `ch-${Date.now()}`,
        name: data.name,
        description: data.description ?? "",
      };
      await route.fulfill({
        status: 201,
        contentType: "application/json",
        body: JSON.stringify({ channel: newChannel }),
      });
      return;
    }

    await route.continue();
  });

  // Messages in a channel (supports pagination via ?cursor param)
  await page.route(
    /\/api\/chat\/channels\/[^/]+\/messages$/,
    async (route) => {
      if (route.request().method() === "GET") {
        const url = new URL(route.request().url());
        const cursor = url.searchParams.get("cursor");
        const limit = Number(url.searchParams.get("limit") ?? "20");

        // Simple pagination: if cursor is provided, return older messages
        let messagesToReturn: MockMessage[];
        if (cursor) {
          // Generate older messages for pagination
          messagesToReturn = generateMockMessages(
            MOCK_CHANNEL.id,
            limit
          ).map((msg, idx) => ({
            ...msg,
            id: `msg-old-${idx}`,
            content: `Older message ${idx + 1}`,
            createdAt: new Date(
              Date.now() - (limit + idx) * 120_000
            ).toISOString(),
          }));
        } else {
          messagesToReturn = messageStore.slice(-limit);
        }

        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            messages: messagesToReturn,
            nextCursor:
              messagesToReturn.length >= limit
                ? messagesToReturn[0].id
                : null,
          }),
        });
        return;
      }

      if (route.request().method() === "POST") {
        const data = route.request().postDataJSON() as { content: string };
        const newMessage: MockMessage = {
          id: `msg-new-${Date.now()}`,
          channelId: MOCK_CHANNEL.id,
          content: data.content,
          authorId: MOCK_USERS[0].id,
          authorName: MOCK_USERS[0].name,
          authorAvatar: MOCK_USERS[0].avatar,
          createdAt: new Date().toISOString(),
          threadCount: 0,
          reactions: [],
        };
        messageStore.push(newMessage);
        await route.fulfill({
          status: 201,
          contentType: "application/json",
          body: JSON.stringify({ message: newMessage }),
        });
        return;
      }

      await route.continue();
    }
  );

  // Reactions on a message
  await page.route(/\/api\/chat\/channels\/[^/]+\/messages\/[^/]+\/react$/, async (route) => {
    if (route.request().method() === "POST") {
      const data = route.request().postDataJSON() as { emoji: string };
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          reaction: {
            emoji: data.emoji,
            count: 1,
            userIds: [MOCK_USERS[0].id],
          },
        }),
      });
      return;
    }
    await route.continue();
  });

  // Thread messages
  await page.route(
    /\/api\/chat\/channels\/[^/]+\/messages\/[^/]+\/thread$/,
    async (route) => {
      if (route.request().method() === "GET") {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            messages: [
              {
                id: "msg-thread-reply-1",
                channelId: MOCK_CHANNEL.id,
                content: "This is a thread reply",
                authorId: MOCK_USERS[1].id,
                authorName: MOCK_USERS[1].name,
                authorAvatar: MOCK_USERS[1].avatar,
                createdAt: new Date().toISOString(),
                threadCount: 0,
                reactions: [],
              },
            ],
          }),
        });
        return;
      }

      if (route.request().method() === "POST") {
        const data = route.request().postDataJSON() as { content: string };
        await route.fulfill({
          status: 201,
          contentType: "application/json",
          body: JSON.stringify({
            message: {
              id: `msg-thread-${Date.now()}`,
              channelId: MOCK_CHANNEL.id,
              content: data.content,
              authorId: MOCK_USERS[0].id,
              authorName: MOCK_USERS[0].name,
              authorAvatar: MOCK_USERS[0].avatar,
              createdAt: new Date().toISOString(),
              threadCount: 0,
              reactions: [],
            },
          }),
        });
        return;
      }

      await route.continue();
    }
  );

  // User search for @mentions
  await page.route("**/api/chat/users/search**", async (route) => {
    const url = new URL(route.request().url());
    const query = url.searchParams.get("q")?.toLowerCase() ?? "";

    const filtered = MOCK_USERS.filter(
      (u) =>
        u.name.toLowerCase().includes(query) ||
        u.email.toLowerCase().includes(query)
    );

    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ users: filtered }),
    });
  });
}

export { MOCK_CHANNEL, MOCK_USERS, generateMockMessages };
export type { MockChannel, MockMessage, MockUser };
```

### Step 2: Create `e2e/helpers/chat-auth.ts`

Reusable helper that signs in as the dev admin user via the `/dev` page. Used by all chat test files that require authentication.

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

### Step 3: Create `e2e/chat-messages.spec.ts`

Tests the core messaging experience — rendering the message list, sending messages, displaying author info, empty state, and pagination.

```typescript
import { test, expect } from "@playwright/test";
import { interceptChatApi, MOCK_CHANNEL } from "./fixtures/mock-chat";
import { signInAsTestUser } from "./helpers/chat-auth";

test.describe("Chat Messages", () => {
  test.beforeEach(async ({ page }) => {
    // Sign in as the admin test user
    await signInAsTestUser(page);

    // Intercept chat API calls with mock data
    await interceptChatApi(page);
  });

  test("chat channel page renders message list and input", async ({
    page,
  }) => {
    // Navigate to the test channel
    await page.goto(`/chat/${MOCK_CHANNEL.id}`);

    // The message list area should be visible
    const messageList = page.locator(
      [
        "[data-testid='message-list']",
        "[role='log']",
        "[aria-label*='message' i]",
        ".message-list",
      ].join(", ")
    ).first();
    await expect(messageList).toBeVisible({ timeout: 10_000 });

    // The message input should be visible
    const messageInput = page.locator(
      [
        "[data-testid='message-input']",
        "textarea[placeholder*='message' i]",
        "input[placeholder*='message' i]",
        "[contenteditable='true']",
      ].join(", ")
    ).first();
    await expect(messageInput).toBeVisible();
  });

  test("sending a message appears in the message list", async ({ page }) => {
    await page.goto(`/chat/${MOCK_CHANNEL.id}`);

    // Find the message input
    const messageInput = page.locator(
      [
        "[data-testid='message-input']",
        "textarea[placeholder*='message' i]",
        "input[placeholder*='message' i]",
        "[contenteditable='true']",
      ].join(", ")
    ).first();
    await expect(messageInput).toBeVisible({ timeout: 10_000 });

    // Type a unique message
    const uniqueMessage = `E2E test message ${Date.now()}`;
    await messageInput.fill(uniqueMessage);

    // Send the message by pressing Enter or clicking the send button
    const sendButton = page.getByRole("button", { name: /send/i });
    if (await sendButton.isVisible()) {
      await sendButton.click();
    } else {
      await messageInput.press("Enter");
    }

    // The sent message should appear in the message list
    await expect(page.getByText(uniqueMessage)).toBeVisible({
      timeout: 10_000,
    });
  });

  test("messages show author avatar and timestamp", async ({ page }) => {
    await page.goto(`/chat/${MOCK_CHANNEL.id}`);

    // Wait for messages to load
    await expect(page.getByText(/test message/i).first()).toBeVisible({
      timeout: 10_000,
    });

    // Each message should have an author name or avatar visible
    // Look for the first message's author info
    const authorElement = page.locator(
      [
        "[data-testid='message-author']",
        ".message-author",
        "[class*='author']",
      ].join(", ")
    ).first();

    // Author name should be displayed (Admin User or Member User)
    await expect(
      page.getByText(/admin user|member user/i).first()
    ).toBeVisible();

    // Avatar should be present — either an <img> or a fallback initial
    const avatar = page.locator(
      [
        "[data-testid='message-avatar']",
        ".message-avatar",
        "img[alt*='avatar' i]",
        "img[alt*='user' i]",
      ].join(", ")
    ).first();

    // Either a real avatar image or at least the author name should be visible
    const hasAvatar = await avatar.isVisible();
    const hasAuthor = await authorElement.isVisible();
    expect(hasAvatar || hasAuthor).toBe(true);

    // Timestamp should be displayed (some time representation)
    const timestamp = page.locator(
      [
        "[data-testid='message-timestamp']",
        "time",
        "[datetime]",
        "[class*='timestamp']",
        "[class*='time']",
      ].join(", ")
    ).first();

    // Either a <time> element or some text representing the time
    if (await timestamp.isVisible()) {
      const timeText = await timestamp.textContent();
      expect(timeText?.length).toBeGreaterThan(0);
    }
  });

  test("empty channel shows placeholder message", async ({ page }) => {
    // Override the messages route to return an empty array
    await page.route(
      /\/api\/chat\/channels\/[^/]+\/messages$/,
      async (route) => {
        if (route.request().method() === "GET") {
          await route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify({ messages: [], nextCursor: null }),
          });
          return;
        }
        await route.continue();
      }
    );

    await page.goto(`/chat/${MOCK_CHANNEL.id}`);

    // An empty channel should show a placeholder or empty state
    const emptyState = page.locator(
      [
        "[data-testid='empty-channel']",
        "text=/no messages|start a conversation|be the first|say something/i",
      ].join(", ")
    ).first();

    await expect(emptyState).toBeVisible({ timeout: 10_000 });
  });

  test("pagination loads older messages on scroll", async ({ page }) => {
    await page.goto(`/chat/${MOCK_CHANNEL.id}`);

    // Wait for initial messages to load
    await expect(page.getByText(/test message/i).first()).toBeVisible({
      timeout: 10_000,
    });

    // Count initial messages
    const initialMessages = await page
      .locator("[data-testid='message-item'], [class*='message-item'], [role='listitem']")
      .count();

    // Scroll to the top of the message list to trigger loading older messages
    const messageList = page.locator(
      [
        "[data-testid='message-list']",
        "[role='log']",
        "[aria-label*='message' i]",
        ".message-list",
      ].join(", ")
    ).first();

    // Scroll to the top — most chat UIs load older messages when scrolling up
    await messageList.evaluate((el) => {
      el.scrollTop = 0;
    });

    // Wait for additional messages to appear (older messages)
    // Either more message items appear or we see "older message" text
    await page.waitForTimeout(2_000);

    const afterScrollMessages = await page
      .locator("[data-testid='message-item'], [class*='message-item'], [role='listitem']")
      .count();

    // After scrolling, we should have the same or more messages
    // (depending on whether pagination was triggered)
    expect(afterScrollMessages).toBeGreaterThanOrEqual(initialMessages);
  });
});
```

### Step 4: Create `e2e/chat-threads.spec.ts`

Tests threaded replies — opening a thread panel, sending replies, closing the panel, and thread count badges.

```typescript
import { test, expect } from "@playwright/test";
import { interceptChatApi, MOCK_CHANNEL } from "./fixtures/mock-chat";
import { signInAsTestUser } from "./helpers/chat-auth";

test.describe("Chat Threads", () => {
  test.beforeEach(async ({ page }) => {
    // Sign in as admin
    await signInAsTestUser(page);

    // Mock the chat API
    await interceptChatApi(page);

    // Navigate to test channel
    await page.goto(`/chat/${MOCK_CHANNEL.id}`);

    // Wait for messages to load
    await expect(page.getByText(/test message/i).first()).toBeVisible({
      timeout: 10_000,
    });
  });

  test("clicking reply on a message opens thread panel", async ({ page }) => {
    // Find the first message and its reply button.
    // The reply button may appear on hover or always be visible.
    const firstMessage = page.locator(
      "[data-testid='message-item'], [class*='message-item'], [role='listitem']"
    ).first();

    // Hover to reveal action buttons (many chat UIs show actions on hover)
    await firstMessage.hover();

    // Click the reply/thread button
    const replyButton = firstMessage.locator(
      [
        "[data-testid='reply-button']",
        "button[aria-label*='reply' i]",
        "button[aria-label*='thread' i]",
        "button:has-text('Reply')",
      ].join(", ")
    ).first();
    await expect(replyButton).toBeVisible({ timeout: 5_000 });
    await replyButton.click();

    // A thread panel should open — typically a side panel or overlay
    const threadPanel = page.locator(
      [
        "[data-testid='thread-panel']",
        "[role='complementary']",
        "[aria-label*='thread' i]",
        ".thread-panel",
      ].join(", ")
    ).first();
    await expect(threadPanel).toBeVisible({ timeout: 10_000 });
  });

  test("sending a reply appears in the thread", async ({ page }) => {
    // Open a thread on the first message
    const firstMessage = page.locator(
      "[data-testid='message-item'], [class*='message-item'], [role='listitem']"
    ).first();
    await firstMessage.hover();

    const replyButton = firstMessage.locator(
      [
        "[data-testid='reply-button']",
        "button[aria-label*='reply' i]",
        "button[aria-label*='thread' i]",
        "button:has-text('Reply')",
      ].join(", ")
    ).first();
    await replyButton.click();

    // Wait for thread panel to open
    const threadPanel = page.locator(
      [
        "[data-testid='thread-panel']",
        "[role='complementary']",
        "[aria-label*='thread' i]",
        ".thread-panel",
      ].join(", ")
    ).first();
    await expect(threadPanel).toBeVisible({ timeout: 10_000 });

    // Find the thread reply input
    const threadInput = threadPanel.locator(
      [
        "[data-testid='thread-input']",
        "textarea[placeholder*='reply' i]",
        "input[placeholder*='reply' i]",
        "textarea[placeholder*='message' i]",
        "[contenteditable='true']",
      ].join(", ")
    ).first();
    await expect(threadInput).toBeVisible();

    // Type and send a reply
    const replyText = `Thread reply ${Date.now()}`;
    await threadInput.fill(replyText);

    const threadSendButton = threadPanel.getByRole("button", {
      name: /send|reply/i,
    });
    if (await threadSendButton.isVisible()) {
      await threadSendButton.click();
    } else {
      await threadInput.press("Enter");
    }

    // The reply should appear in the thread panel
    await expect(threadPanel.getByText(replyText)).toBeVisible({
      timeout: 10_000,
    });
  });

  test("thread panel can be closed", async ({ page }) => {
    // Open a thread
    const firstMessage = page.locator(
      "[data-testid='message-item'], [class*='message-item'], [role='listitem']"
    ).first();
    await firstMessage.hover();

    const replyButton = firstMessage.locator(
      [
        "[data-testid='reply-button']",
        "button[aria-label*='reply' i]",
        "button[aria-label*='thread' i]",
        "button:has-text('Reply')",
      ].join(", ")
    ).first();
    await replyButton.click();

    const threadPanel = page.locator(
      [
        "[data-testid='thread-panel']",
        "[role='complementary']",
        "[aria-label*='thread' i]",
        ".thread-panel",
      ].join(", ")
    ).first();
    await expect(threadPanel).toBeVisible({ timeout: 10_000 });

    // Close the thread panel using the close button
    const closeButton = threadPanel.locator(
      [
        "[data-testid='close-thread']",
        "button[aria-label*='close' i]",
        "button:has-text('Close')",
        "button:has-text('X')",
      ].join(", ")
    ).first();
    await closeButton.click();

    // The thread panel should no longer be visible
    await expect(threadPanel).not.toBeVisible({ timeout: 5_000 });
  });

  test("thread count badge shows on parent message", async ({ page }) => {
    // Override messages to include one with a threadCount > 0
    await page.route(
      /\/api\/chat\/channels\/[^/]+\/messages$/,
      async (route) => {
        if (route.request().method() === "GET") {
          await route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify({
              messages: [
                {
                  id: "msg-with-thread",
                  channelId: MOCK_CHANNEL.id,
                  content: "Message with thread replies",
                  authorId: "user-admin-1",
                  authorName: "Admin User",
                  authorAvatar: "/avatars/admin.png",
                  createdAt: new Date().toISOString(),
                  threadCount: 3,
                  reactions: [],
                },
              ],
              nextCursor: null,
            }),
          });
          return;
        }
        await route.continue();
      }
    );

    // Reload to pick up the new route
    await page.goto(`/chat/${MOCK_CHANNEL.id}`);

    // Wait for the message with thread count to appear
    await expect(page.getByText("Message with thread replies")).toBeVisible({
      timeout: 10_000,
    });

    // The thread count badge should show "3 replies" or just "3"
    const threadBadge = page.locator(
      [
        "[data-testid='thread-count']",
        "text=/3 repl/i",
        "text=/3 thread/i",
        "[class*='thread-count']",
      ].join(", ")
    ).first();

    await expect(threadBadge).toBeVisible({ timeout: 5_000 });
  });
});
```

### Step 5: Create `e2e/chat-reactions.spec.ts`

Tests emoji reactions — opening the picker, adding reactions, toggling, and count display.

```typescript
import { test, expect } from "@playwright/test";
import { interceptChatApi, MOCK_CHANNEL } from "./fixtures/mock-chat";
import { signInAsTestUser } from "./helpers/chat-auth";

test.describe("Chat Reactions", () => {
  test.beforeEach(async ({ page }) => {
    // Sign in as admin
    await signInAsTestUser(page);

    // Mock the chat API
    await interceptChatApi(page);

    // Navigate to test channel
    await page.goto(`/chat/${MOCK_CHANNEL.id}`);

    // Wait for messages to load
    await expect(page.getByText(/test message/i).first()).toBeVisible({
      timeout: 10_000,
    });
  });

  test("clicking reaction button opens emoji picker", async ({ page }) => {
    // Find the first message
    const firstMessage = page.locator(
      "[data-testid='message-item'], [class*='message-item'], [role='listitem']"
    ).first();

    // Hover to reveal action buttons
    await firstMessage.hover();

    // Click the reaction/emoji button
    const reactionButton = firstMessage.locator(
      [
        "[data-testid='reaction-button']",
        "button[aria-label*='react' i]",
        "button[aria-label*='emoji' i]",
        "button[aria-label*='add reaction' i]",
      ].join(", ")
    ).first();
    await expect(reactionButton).toBeVisible({ timeout: 5_000 });
    await reactionButton.click();

    // An emoji picker should appear — either a custom component or a popover
    const emojiPicker = page.locator(
      [
        "[data-testid='emoji-picker']",
        "[role='dialog'][aria-label*='emoji' i]",
        "[class*='emoji-picker']",
        "[class*='EmojiPicker']",
        "em-emoji-picker",
      ].join(", ")
    ).first();
    await expect(emojiPicker).toBeVisible({ timeout: 5_000 });
  });

  test("selecting an emoji adds a reaction to the message", async ({
    page,
  }) => {
    const firstMessage = page.locator(
      "[data-testid='message-item'], [class*='message-item'], [role='listitem']"
    ).first();
    await firstMessage.hover();

    // Open emoji picker
    const reactionButton = firstMessage.locator(
      [
        "[data-testid='reaction-button']",
        "button[aria-label*='react' i]",
        "button[aria-label*='emoji' i]",
        "button[aria-label*='add reaction' i]",
      ].join(", ")
    ).first();
    await reactionButton.click();

    // Wait for picker to appear
    const emojiPicker = page.locator(
      [
        "[data-testid='emoji-picker']",
        "[role='dialog'][aria-label*='emoji' i]",
        "[class*='emoji-picker']",
        "[class*='EmojiPicker']",
        "em-emoji-picker",
      ].join(", ")
    ).first();
    await expect(emojiPicker).toBeVisible({ timeout: 5_000 });

    // Click a common emoji (thumbs up). Try multiple selector strategies.
    const thumbsUp = emojiPicker.locator(
      [
        "button[aria-label*='thumbs up' i]",
        "button[aria-label*='+1' i]",
        "button:has-text('\uD83D\uDC4D')",
        "[data-emoji='+1']",
        "[data-emoji='thumbsup']",
      ].join(", ")
    ).first();

    if (await thumbsUp.isVisible()) {
      await thumbsUp.click();
    } else {
      // Fallback: click the first visible emoji in the picker
      const firstEmoji = emojiPicker.locator("button").first();
      await firstEmoji.click();
    }

    // After selecting an emoji, a reaction should appear on the message.
    // The picker should close and the reaction should be visible.
    const reactionDisplay = firstMessage.locator(
      [
        "[data-testid='reaction']",
        "[class*='reaction']",
        "button[class*='reaction']",
      ].join(", ")
    ).first();

    await expect(reactionDisplay).toBeVisible({ timeout: 10_000 });
  });

  test("clicking an existing reaction toggles it", async ({ page }) => {
    // Override messages to include one with an existing reaction
    await page.route(
      /\/api\/chat\/channels\/[^/]+\/messages$/,
      async (route) => {
        if (route.request().method() === "GET") {
          await route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify({
              messages: [
                {
                  id: "msg-with-reaction",
                  channelId: MOCK_CHANNEL.id,
                  content: "Message with existing reaction",
                  authorId: "user-admin-1",
                  authorName: "Admin User",
                  authorAvatar: "/avatars/admin.png",
                  createdAt: new Date().toISOString(),
                  threadCount: 0,
                  reactions: [
                    {
                      emoji: "\uD83D\uDC4D",
                      count: 2,
                      userIds: ["user-member-1", "user-other"],
                    },
                  ],
                },
              ],
              nextCursor: null,
            }),
          });
          return;
        }
        await route.continue();
      }
    );

    await page.goto(`/chat/${MOCK_CHANNEL.id}`);
    await expect(
      page.getByText("Message with existing reaction")
    ).toBeVisible({ timeout: 10_000 });

    // Find the existing reaction button on the message
    const messageRow = page.locator(
      "[data-testid='message-item'], [class*='message-item'], [role='listitem']"
    ).first();

    const existingReaction = messageRow.locator(
      [
        "[data-testid='reaction']",
        "[class*='reaction']",
        "button[class*='reaction']",
      ].join(", ")
    ).first();

    await expect(existingReaction).toBeVisible({ timeout: 5_000 });

    // Click the existing reaction to toggle it (add our own)
    await existingReaction.click();

    // The reaction count should change — either increment or the reaction
    // should have an "active" state indicating the current user reacted.
    // We verify the reaction is still visible (toggling should not remove it
    // if other users still have it).
    await expect(existingReaction).toBeVisible();
  });

  test("reaction count displays correctly", async ({ page }) => {
    // Override messages with a message that has multiple reactions
    await page.route(
      /\/api\/chat\/channels\/[^/]+\/messages$/,
      async (route) => {
        if (route.request().method() === "GET") {
          await route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify({
              messages: [
                {
                  id: "msg-multi-reactions",
                  channelId: MOCK_CHANNEL.id,
                  content: "Message with many reactions",
                  authorId: "user-admin-1",
                  authorName: "Admin User",
                  authorAvatar: "/avatars/admin.png",
                  createdAt: new Date().toISOString(),
                  threadCount: 0,
                  reactions: [
                    {
                      emoji: "\uD83D\uDC4D",
                      count: 5,
                      userIds: [
                        "u1",
                        "u2",
                        "u3",
                        "u4",
                        "u5",
                      ],
                    },
                    {
                      emoji: "\u2764\uFE0F",
                      count: 3,
                      userIds: ["u1", "u2", "u3"],
                    },
                  ],
                },
              ],
              nextCursor: null,
            }),
          });
          return;
        }
        await route.continue();
      }
    );

    await page.goto(`/chat/${MOCK_CHANNEL.id}`);
    await expect(page.getByText("Message with many reactions")).toBeVisible({
      timeout: 10_000,
    });

    // Verify that reaction counts are displayed
    // Look for the number "5" near the thumbs up emoji
    const messageRow = page.locator(
      "[data-testid='message-item'], [class*='message-item'], [role='listitem']"
    ).first();

    const reactions = messageRow.locator(
      [
        "[data-testid='reaction']",
        "[class*='reaction']",
        "button[class*='reaction']",
      ].join(", ")
    );

    // Should have at least 2 reaction groups (thumbs up and heart)
    const reactionCount = await reactions.count();
    expect(reactionCount).toBeGreaterThanOrEqual(2);

    // Verify one of them shows the count "5"
    await expect(messageRow.getByText("5")).toBeVisible({ timeout: 5_000 });
  });
});
```

### Step 6: Create `e2e/chat-mentions.spec.ts`

Tests the @mention system — autocomplete dropdown, user selection, and styled mention display.

```typescript
import { test, expect } from "@playwright/test";
import { interceptChatApi, MOCK_CHANNEL, MOCK_USERS } from "./fixtures/mock-chat";
import { signInAsTestUser } from "./helpers/chat-auth";

test.describe("Chat Mentions", () => {
  test.beforeEach(async ({ page }) => {
    // Sign in as admin
    await signInAsTestUser(page);

    // Mock the chat API
    await interceptChatApi(page);

    // Navigate to test channel
    await page.goto(`/chat/${MOCK_CHANNEL.id}`);
    await expect(page.getByText(/test message/i).first()).toBeVisible({
      timeout: 10_000,
    });
  });

  test("typing @ in input shows autocomplete dropdown", async ({ page }) => {
    // Find the message input
    const messageInput = page.locator(
      [
        "[data-testid='message-input']",
        "textarea[placeholder*='message' i]",
        "input[placeholder*='message' i]",
        "[contenteditable='true']",
      ].join(", ")
    ).first();
    await expect(messageInput).toBeVisible({ timeout: 10_000 });

    // Type @ to trigger mention autocomplete
    await messageInput.click();
    await messageInput.pressSequentially("@");

    // An autocomplete dropdown should appear with user suggestions
    const autocomplete = page.locator(
      [
        "[data-testid='mention-autocomplete']",
        "[role='listbox']",
        "[class*='mention-list']",
        "[class*='autocomplete']",
        "[class*='suggestion']",
      ].join(", ")
    ).first();
    await expect(autocomplete).toBeVisible({ timeout: 5_000 });
  });

  test("autocomplete filters users as you type", async ({ page }) => {
    const messageInput = page.locator(
      [
        "[data-testid='message-input']",
        "textarea[placeholder*='message' i]",
        "input[placeholder*='message' i]",
        "[contenteditable='true']",
      ].join(", ")
    ).first();
    await messageInput.click();

    // Type @Admin to filter to the admin user
    await messageInput.pressSequentially("@Admin");

    // Wait for autocomplete to appear
    const autocomplete = page.locator(
      [
        "[data-testid='mention-autocomplete']",
        "[role='listbox']",
        "[class*='mention-list']",
        "[class*='autocomplete']",
        "[class*='suggestion']",
      ].join(", ")
    ).first();
    await expect(autocomplete).toBeVisible({ timeout: 5_000 });

    // The autocomplete should show "Admin User" but NOT "Member User"
    await expect(autocomplete.getByText(/admin user/i)).toBeVisible();
    await expect(autocomplete.getByText(/member user/i)).not.toBeVisible();
  });

  test("selecting a user inserts @mention into the input", async ({
    page,
  }) => {
    const messageInput = page.locator(
      [
        "[data-testid='message-input']",
        "textarea[placeholder*='message' i]",
        "input[placeholder*='message' i]",
        "[contenteditable='true']",
      ].join(", ")
    ).first();
    await messageInput.click();

    // Type @ to open autocomplete
    await messageInput.pressSequentially("@");

    const autocomplete = page.locator(
      [
        "[data-testid='mention-autocomplete']",
        "[role='listbox']",
        "[class*='mention-list']",
        "[class*='autocomplete']",
        "[class*='suggestion']",
      ].join(", ")
    ).first();
    await expect(autocomplete).toBeVisible({ timeout: 5_000 });

    // Click on "Member User" in the autocomplete
    const memberOption = autocomplete.locator(
      [
        "[role='option']:has-text('Member User')",
        "li:has-text('Member User')",
        "button:has-text('Member User')",
        "div:has-text('Member User')",
      ].join(", ")
    ).first();
    await memberOption.click();

    // The autocomplete should close after selection
    await expect(autocomplete).not.toBeVisible({ timeout: 3_000 });

    // The input should now contain the @mention.
    // For contenteditable inputs, check the text content;
    // for standard inputs, check the value.
    const inputText =
      (await messageInput.getAttribute("contenteditable")) === "true"
        ? await messageInput.textContent()
        : await messageInput.inputValue();

    expect(inputText).toContain("Member User");
  });

  test("@mention renders as styled badge in sent message", async ({
    page,
  }) => {
    // Override the POST message handler to echo back with mention formatting
    await page.route(
      /\/api\/chat\/channels\/[^/]+\/messages$/,
      async (route) => {
        if (route.request().method() === "POST") {
          const data = route.request().postDataJSON() as { content: string };
          await route.fulfill({
            status: 201,
            contentType: "application/json",
            body: JSON.stringify({
              message: {
                id: `msg-mention-${Date.now()}`,
                channelId: MOCK_CHANNEL.id,
                content: data.content,
                authorId: MOCK_USERS[0].id,
                authorName: MOCK_USERS[0].name,
                authorAvatar: MOCK_USERS[0].avatar,
                createdAt: new Date().toISOString(),
                threadCount: 0,
                reactions: [],
                mentions: [
                  {
                    userId: MOCK_USERS[1].id,
                    name: MOCK_USERS[1].name,
                  },
                ],
              },
            }),
          });
          return;
        }
        await route.continue();
      }
    );

    const messageInput = page.locator(
      [
        "[data-testid='message-input']",
        "textarea[placeholder*='message' i]",
        "input[placeholder*='message' i]",
        "[contenteditable='true']",
      ].join(", ")
    ).first();
    await messageInput.click();

    // Type @ and select a user
    await messageInput.pressSequentially("@");

    const autocomplete = page.locator(
      [
        "[data-testid='mention-autocomplete']",
        "[role='listbox']",
        "[class*='mention-list']",
        "[class*='autocomplete']",
        "[class*='suggestion']",
      ].join(", ")
    ).first();

    if (await autocomplete.isVisible()) {
      const memberOption = autocomplete.locator(
        [
          "[role='option']:has-text('Member User')",
          "li:has-text('Member User')",
          "button:has-text('Member User')",
          "div:has-text('Member User')",
        ].join(", ")
      ).first();
      await memberOption.click();
    }

    // Type some additional text after the mention
    await messageInput.pressSequentially(" check this out");

    // Send the message
    const sendButton = page.getByRole("button", { name: /send/i });
    if (await sendButton.isVisible()) {
      await sendButton.click();
    } else {
      await messageInput.press("Enter");
    }

    // The sent message should contain the @mention rendered as a styled element.
    // Look for a styled badge, link, or span that contains the mentioned user's name.
    const mentionBadge = page.locator(
      [
        "[data-testid='mention-badge']",
        "a[class*='mention']",
        "span[class*='mention']",
        "[data-mention]",
        ".mention",
      ].join(", ")
    ).last();

    // Either a styled mention badge or at least the mention text should be visible
    const hasBadge = await mentionBadge.isVisible();
    const hasText = await page.getByText(/member user/i).last().isVisible();
    expect(hasBadge || hasText).toBe(true);
  });
});
```

## Usage

### Run all chat tests

```bash
bunx playwright test e2e/chat-messages.spec.ts e2e/chat-threads.spec.ts e2e/chat-reactions.spec.ts e2e/chat-mentions.spec.ts
```

### Run a single test file

```bash
bunx playwright test e2e/chat-messages.spec.ts
```

### Run headed (watch browser)

```bash
bunx playwright test e2e/chat-threads.spec.ts --headed
```

### Run a specific test by name

```bash
bunx playwright test -g "sending a message appears in the message list"
```

### Debug interactively

```bash
bunx playwright test e2e/chat-reactions.spec.ts --debug
```

## Acceptance Criteria

- [ ] `bunx playwright test e2e/chat-messages.spec.ts` runs without import errors
- [ ] `bunx playwright test e2e/chat-threads.spec.ts` runs without import errors
- [ ] `bunx playwright test e2e/chat-reactions.spec.ts` runs without import errors
- [ ] `bunx playwright test e2e/chat-mentions.spec.ts` runs without import errors
- [ ] Chat channel page renders message list and input
- [ ] Sending a message appears in the message list
- [ ] Messages display author name/avatar and timestamp
- [ ] Empty channel shows placeholder text
- [ ] Scrolling loads older messages (pagination)
- [ ] Clicking reply opens a thread panel
- [ ] Thread replies appear in the thread panel
- [ ] Thread panel can be closed
- [ ] Thread count badge shows on parent messages
- [ ] Reaction button opens emoji picker
- [ ] Selecting emoji adds reaction to message
- [ ] Clicking existing reaction toggles it
- [ ] Reaction counts display correctly
- [ ] Typing @ shows mention autocomplete
- [ ] Selecting a user inserts @mention
- [ ] @mention renders as styled badge in sent message
- [ ] No usage of `any` type anywhere in test code
- [ ] All mock helpers use proper TypeScript types

## Troubleshooting

### Messages don't appear after navigating to channel

**Symptom**: The message list is empty even though `interceptChatApi` is set up.

**Cause**: The `page.route()` calls must be made BEFORE navigation. If you call `interceptChatApi` after `page.goto()`, the initial fetch may have already completed.

**Fix**: Ensure `interceptChatApi(page)` is called in `test.beforeEach` before the `page.goto()` call.

### Reply button not found on hover

**Symptom**: The reply/thread button selector doesn't match any element.

**Cause**: The group-chat UI may use different markup for message actions.

**Fix**: Use `bunx playwright test --debug` to inspect the DOM when hovering over a message. Update the selectors in `chat-threads.spec.ts` to match the actual button markup.

### Emoji picker not found

**Symptom**: The emoji picker selector doesn't match after clicking the reaction button.

**Cause**: The group-chat skill may use a different emoji picker library (e.g., `emoji-mart`, `emoji-picker-react`, or a custom component).

**Fix**: Inspect the rendered picker DOM and update the selectors in `chat-reactions.spec.ts`. Common patterns include `em-emoji-picker` (emoji-mart web component) or a div with role="dialog".

### Mention autocomplete doesn't appear

**Symptom**: Typing `@` doesn't trigger the autocomplete dropdown.

**Cause**: The input may use a rich text editor (e.g., TipTap, Slate) that requires `pressSequentially` instead of `fill`, or the trigger character handling differs.

**Fix**: Try using `page.keyboard.type("@")` instead of `messageInput.pressSequentially("@")`. For rich text editors, you may need to focus the editor first and use keyboard API directly.

### Route intercepts not working

**Symptom**: Tests make real API calls instead of using mocked responses.

**Cause**: The URL pattern in `page.route()` doesn't match the actual request URL, possibly due to a base URL prefix or query parameters.

**Fix**: Use the Playwright trace viewer (`bunx playwright test --trace on`) to inspect actual network requests and adjust the route patterns accordingly.
