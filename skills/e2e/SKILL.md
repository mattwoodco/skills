---
name: e2e
version: 1.1.0
updated: 2026-02-18
dependencies: [create-next]
---

# E2E Testing with Playwright

Setup end-to-end testing with Playwright. Works with any Next.js app — no auth or database required. Includes GitHub Actions CI, page object model, and an extensible test structure.

## When to Use This Skill

Use this skill when the user says:
- "setup e2e testing"
- "add playwright"
- "setup playwright tests"
- "add end-to-end tests"
- "setup browser testing"
- "add e2e tests"

## Prerequisites

- Next.js project with App Router
- bun as package manager

## Installation

```bash
bun add -d @playwright/test

bunx playwright install chromium
```

## Setup Steps

### Step 1: Create directory structure

```bash
mkdir -p e2e playwright/.auth
touch playwright/.auth/.gitkeep
```

### Step 2: Create playwright.config.ts

Create `playwright.config.ts` in the project root:

```typescript
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.spec.ts",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [["html", { open: "never" }]],
  outputDir: "test-results",

  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? "http://localhost:3000",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],

  webServer: {
    command: "bun run dev",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
```

### Step 3: Create smoke test

Create `e2e/smoke.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";

test.describe("Smoke Tests", () => {
  test("homepage loads successfully", async ({ page }) => {
    const response = await page.goto("/");
    expect(response?.status()).toBe(200);
    await expect(page).toHaveTitle(/.+/);
  });

  test("page responds with 200", async ({ page }) => {
    const response = await page.goto("/");
    expect(response?.status()).toBe(200);
  });
});
```

### Step 4: Add package.json scripts

Add these scripts to `package.json`:

```json
{
  "scripts": {
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui",
    "test:e2e:headed": "playwright test --headed"
  }
}
```

### Step 5: Update .gitignore

Append to `.gitignore`:

```gitignore
# Playwright
/test-results/
/playwright-report/
/blob-report/
/playwright/.cache/
/playwright/.auth/*
!/playwright/.auth/.gitkeep
```

### Step 6: Exclude e2e from Biome

If using Biome, add `e2e/` and `playwright.config.ts` to the ignore list in `biome.json` so Playwright's `test` function doesn't trigger false positives:

```json
{
  "files": {
    "ignore": ["e2e/**", "playwright.config.ts"]
  }
}
```

### Step 7: Create GitHub Actions workflow

Create `.github/workflows/e2e.yml`:

```yaml
name: E2E Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  CI: true

jobs:
  e2e:
    name: E2E Tests
    runs-on: ubuntu-latest
    timeout-minutes: 15

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Bun
        uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Cache Playwright browsers
        id: playwright-cache
        uses: actions/cache@v4
        with:
          path: ~/.cache/ms-playwright
          key: playwright-${{ runner.os }}-${{ hashFiles('bun.lock') }}

      - name: Install Playwright browsers
        if: steps.playwright-cache.outputs.cache-hit != 'true'
        run: bunx playwright install chromium --with-deps

      - name: Install Playwright deps (cached)
        if: steps.playwright-cache.outputs.cache-hit == 'true'
        run: bunx playwright install-deps chromium

      - name: Build application
        run: bun run build

      - name: Run E2E tests
        run: bun run test:e2e
        env:
          PLAYWRIGHT_BASE_URL: http://localhost:3000

      - name: Upload test report
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 7

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: test-results
          path: test-results/
          retention-days: 7
```

## What Gets Created

```
project/
├── e2e/
│   └── smoke.spec.ts            # Smoke tests (works out of the box)
├── playwright/
│   └── .auth/
│       └── .gitkeep             # Auth state directory (gitignored)
├── playwright.config.ts         # Playwright configuration
└── .github/
    └── workflows/
        └── e2e.yml              # GitHub Actions CI workflow
```

## Adding a New E2E Test

When the user asks to add a new e2e test (e.g., "add e2e test for the settings page"), create a spec file directly in `e2e/`:

Create `e2e/settings.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";

test.describe("Settings Page", () => {
  test("page loads correctly", async ({ page }) => {
    await page.goto("/settings");
    await expect(page.getByRole("heading", { name: /settings/i })).toBeVisible();
  });

  test("can save settings", async ({ page }) => {
    await page.goto("/settings");
    // Fill in form fields
    await page.getByLabel("Name").fill("Test User");
    await page.getByRole("button", { name: /save/i }).click();
    // Assert success
    await expect(page.getByText(/saved/i)).toBeVisible();
  });
});
```

Run the new test:

```bash
# Run just the new spec
bunx playwright test e2e/settings.spec.ts

# Run headed to watch it
bunx playwright test e2e/settings.spec.ts --headed

# Debug interactively
bunx playwright test e2e/settings.spec.ts --debug
```

> **Page objects are optional.** For simple pages, inline selectors are clearer. Introduce page objects when multiple specs share the same selectors.

## Adding Authentication to E2E Tests (Optional)

If your project uses authentication, extend the setup:

### 1. Install auth setup

Create `e2e/auth.setup.ts`:

```typescript
import { test as setup } from "@playwright/test";
import { join } from "node:path";

const authFile = join(process.cwd(), "playwright", ".auth", "user.json");

setup("authenticate", async ({ page }) => {
  await page.goto("/login");

  const email = process.env.TEST_USER_EMAIL ?? "test@example.com";
  const password = process.env.TEST_USER_PASSWORD ?? "testpassword123";

  await page.getByLabel(/email/i).fill(email);
  await page.getByLabel(/password/i).fill(password);
  await page.getByRole("button", { name: /sign in|log in/i }).click();

  await page.waitForURL(/dashboard|home/i, { timeout: 15_000 });

  await page.context().storageState({ path: authFile });
});
```

### 2. Update playwright.config.ts projects

Replace the `projects` array:

```typescript
projects: [
  {
    name: "setup",
    testMatch: /auth\.setup\.ts/,
    use: { ...devices["Desktop Chrome"] },
  },
  {
    name: "chromium",
    use: {
      ...devices["Desktop Chrome"],
      storageState: "playwright/.auth/user.json",
    },
    dependencies: ["setup"],
  },
],
```

### 3. Add test env vars

Create `.env.test`:

```bash
TEST_USER_EMAIL=test@example.com
TEST_USER_PASSWORD=testpassword123
PLAYWRIGHT_BASE_URL=http://localhost:3000
```

## Best Practices

### Use accessible selectors

```typescript
// Prefer role-based selectors
await page.getByRole("button", { name: "Submit" }).click();
await page.getByLabel("Email").fill("test@example.com");

// Use test IDs for complex components
await page.getByTestId("user-card").click();
```

### Use web-first assertions

```typescript
// These auto-retry until the condition is met
await expect(page.getByRole("alert")).toBeVisible();
await expect(page).toHaveURL(/dashboard/);
await expect(page.getByTestId("count")).toHaveText("5");
```

### Mock API responses when needed

```typescript
await page.route("/api/users", async (route) => {
  await route.fulfill({
    status: 200,
    contentType: "application/json",
    body: JSON.stringify({ users: [] }),
  });
});
```

## Debugging

```bash
# Interactive UI mode
bun run test:e2e:ui

# Watch browser while tests run
bun run test:e2e:headed

# Step through with inspector
bun run test:e2e:debug

# Record a new test
bun run test:e2e:codegen

# View last report
bun run test:e2e:report

# Run a single test by name
bunx playwright test -g "homepage loads"
```
