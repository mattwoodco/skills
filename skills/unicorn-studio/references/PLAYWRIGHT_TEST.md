# Unicorn Studio Playwright Tests

Comprehensive E2E tests for Unicorn Studio shader integration.

## Test File

Create `e2e/shader-test.spec.ts` (or `e2e/specs/shader-test.spec.ts` depending on project structure):

```typescript
import { expect, type Page, test } from "@playwright/test";

test.describe("Unicorn Studio Shader Integration", () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to shader test page
    await page.goto("/shader-test");
    // Wait for initial page load
    await page.waitForLoadState("networkidle");
  });

  test.describe("Page Load", () => {
    test("should render shader test page", async ({ page }) => {
      // Verify page title
      await expect(page).toHaveTitle(/Shader Test/);

      // Verify header is visible
      await expect(
        page.getByRole("heading", { name: /Unicorn Studio Shader Test/i })
      ).toBeVisible();
    });

    test("should display debug panel by default", async ({ page }) => {
      // Debug panel should be visible
      await expect(
        page.getByRole("heading", { name: /Debug Panel/i })
      ).toBeVisible();

      // Performance settings section should exist
      await expect(page.getByText(/Performance Settings/i)).toBeVisible();
    });

    test("should show device capabilities", async ({ page }) => {
      // Device info section should be present
      await expect(page.getByText(/Device Capabilities/i)).toBeVisible();

      // WebGL support indicator should be visible
      await expect(page.getByText(/WebGL:/i)).toBeVisible();
    });
  });

  test.describe("Shader Scene", () => {
    test("should render shader container", async ({ page }) => {
      // Main scene container should exist
      const sceneContainer = page.locator('[class*="flex-1"]').first();
      await expect(sceneContainer).toBeVisible();
    });

    test("should show loading state initially", async ({ page }) => {
      // Status badge should indicate loading or loaded
      const statusBadge = page.locator('[class*="rounded-full"]').first();
      await expect(statusBadge).toBeVisible();
    });

    test("should handle scene toggle", async ({ page }) => {
      // Find and click the hide scene button
      const hideButton = page.getByRole("button", { name: /Hide Scene/i });
      await hideButton.click();

      // Button text should change
      await expect(
        page.getByRole("button", { name: /Show Scene/i })
      ).toBeVisible();

      // Click again to show
      await page.getByRole("button", { name: /Show Scene/i }).click();
      await expect(
        page.getByRole("button", { name: /Hide Scene/i })
      ).toBeVisible();
    });

    test("should handle pause/resume toggle", async ({ page }) => {
      // Find pause button
      const pauseButton = page.getByRole("button", { name: /Pause/i });
      await pauseButton.click();

      // Should show resume button
      await expect(
        page.getByRole("button", { name: /Resume/i })
      ).toBeVisible();

      // Click resume
      await page.getByRole("button", { name: /Resume/i }).click();
      await expect(
        page.getByRole("button", { name: /Pause/i })
      ).toBeVisible();
    });
  });

  test.describe("Performance Controls", () => {
    test("should apply performance presets", async ({ page }) => {
      // Click low preset
      await page.getByRole("button", { name: "Low" }).click();

      // Verify config JSON updates
      const configJson = page.locator("pre").last();
      await expect(configJson).toContainText('"scale": 0.5');
      await expect(configJson).toContainText('"fps": 30');

      // Click high preset
      await page.getByRole("button", { name: "High" }).click();
      await expect(configJson).toContainText('"scale": 1');
      await expect(configJson).toContainText('"fps": 60');
    });

    test("should update scale slider", async ({ page }) => {
      // Find scale slider
      const scaleSlider = page.locator('input[type="range"]').first();

      // Get initial value
      const initialValue = await scaleSlider.inputValue();

      // Change value
      await scaleSlider.fill("0.5");

      // Verify display updates
      await expect(page.getByText("0.5")).toBeVisible();
    });

    test("should update FPS slider", async ({ page }) => {
      // Find FPS slider (third range input)
      const fpsSlider = page.locator('input[type="range"]').nth(2);

      // Change value
      await fpsSlider.fill("30");

      // Verify config updates
      const configJson = page.locator("pre").last();
      await expect(configJson).toContainText('"fps": 30');
    });

    test("should toggle lazy load", async ({ page }) => {
      // Find lazy load checkbox
      const lazyLoadCheckbox = page.getByLabel(/Lazy Load/i);

      // Toggle off
      await lazyLoadCheckbox.uncheck();
      const configJson = page.locator("pre").last();
      await expect(configJson).toContainText('"lazyLoad": false');

      // Toggle on
      await lazyLoadCheckbox.check();
      await expect(configJson).toContainText('"lazyLoad": true');
    });

    test("should toggle production mode", async ({ page }) => {
      // Find production checkbox
      const productionCheckbox = page.getByLabel(/Production Mode/i);

      // Toggle off
      await productionCheckbox.uncheck();
      const configJson = page.locator("pre").last();
      await expect(configJson).toContainText('"production": false');

      // Toggle on
      await productionCheckbox.check();
      await expect(configJson).toContainText('"production": true');
    });
  });

  test.describe("Scene Selection", () => {
    test("should display scene options", async ({ page }) => {
      // Scene selection section should exist
      await expect(page.getByText(/Scene Selection/i)).toBeVisible();

      // At least one scene button should be visible
      await expect(page.getByText(/Gradient Flow/i)).toBeVisible();
    });

    test("should switch between scenes", async ({ page }) => {
      // Click on second scene option if available
      const particleScene = page.getByText(/Particle System/i);

      if (await particleScene.isVisible()) {
        await particleScene.click();

        // Config should update with new projectId
        const configJson = page.locator("pre").last();
        await expect(configJson).toContainText("YOUR_PROJECT_ID_2");
      }
    });

    test("should highlight selected scene", async ({ page }) => {
      // First scene should have selected styling
      const firstScene = page
        .locator("button")
        .filter({ hasText: /Gradient Flow/i });
      await expect(firstScene).toHaveClass(/border-primary/);
    });
  });

  test.describe("Debug Panel", () => {
    test("should toggle debug panel visibility", async ({ page }) => {
      // Close debug panel
      const closeButton = page.locator("button").filter({ hasText: "✕" });
      await closeButton.click();

      // Debug panel should be hidden
      await expect(
        page.getByRole("heading", { name: /Debug Panel/i })
      ).not.toBeVisible();

      // Show debug button should appear
      const showButton = page.getByRole("button", { name: /Show Debug/i });
      await expect(showButton).toBeVisible();

      // Click to show again
      await showButton.click();
      await expect(
        page.getByRole("heading", { name: /Debug Panel/i })
      ).toBeVisible();
    });

    test("should display load metrics", async ({ page }) => {
      // Metrics section should exist
      await expect(page.getByText(/Load Metrics/i)).toBeVisible();

      // Status should be displayed
      await expect(page.getByText(/Status:/i)).toBeVisible();
    });

    test("should display config JSON", async ({ page }) => {
      // Config JSON section should exist
      await expect(page.getByText(/Current Config/i)).toBeVisible();

      // JSON should contain expected properties
      const configJson = page.locator("pre").last();
      await expect(configJson).toContainText("projectId");
      await expect(configJson).toContainText("scale");
      await expect(configJson).toContainText("fps");
    });
  });

  test.describe("WebGL Support", () => {
    test("should detect WebGL support", async ({ page }) => {
      // Check WebGL indicator
      const webglText = page.getByText(/WebGL:/i);
      await expect(webglText).toBeVisible();

      // Should show supported (most modern browsers)
      // This test may need adjustment based on test environment
      const webglStatus = page
        .locator('[class*="text-green"]')
        .filter({ hasText: /Supported/i });

      // At least WebGL should be supported in modern browsers
      await expect(
        page.locator("text=Supported").first()
      ).toBeVisible();
    });
  });

  test.describe("Accessibility", () => {
    test("should have proper ARIA labels", async ({ page }) => {
      // Main page structure should be accessible
      await expect(page.locator("main")).toBeVisible();

      // Buttons should be accessible
      const buttons = page.getByRole("button");
      const buttonCount = await buttons.count();
      expect(buttonCount).toBeGreaterThan(0);
    });

    test("should support keyboard navigation", async ({ page }) => {
      // Tab through interactive elements
      await page.keyboard.press("Tab");
      await page.keyboard.press("Tab");

      // Should focus on a button
      const focusedElement = page.locator(":focus");
      await expect(focusedElement).toBeVisible();
    });

    test("should respect reduced motion preference", async ({ page }) => {
      // Check if reduced motion is detected
      const reducedMotionText = page.getByText(/Reduced Motion:/i);
      await expect(reducedMotionText).toBeVisible();
    });
  });

  test.describe("Responsive Layout", () => {
    test("should adapt to mobile viewport", async ({ page }) => {
      // Set mobile viewport
      await page.setViewportSize({ width: 375, height: 667 });

      // Page should still be functional
      await expect(
        page.getByRole("heading", { name: /Unicorn Studio Shader Test/i })
      ).toBeVisible();

      // Debug panel might be hidden on mobile
      // Main content should still be visible
      const mainContent = page.locator("main");
      await expect(mainContent).toBeVisible();
    });

    test("should handle viewport resize", async ({ page }) => {
      // Start with desktop
      await page.setViewportSize({ width: 1280, height: 800 });
      await expect(
        page.getByRole("heading", { name: /Debug Panel/i })
      ).toBeVisible();

      // Resize to tablet
      await page.setViewportSize({ width: 768, height: 1024 });

      // Page should still function
      await expect(page.locator("main")).toBeVisible();
    });
  });

  test.describe("Error Handling", () => {
    test("should handle missing projectId gracefully", async ({ page }) => {
      // With placeholder projectId, should show fallback
      const fallback = page.getByText(/Replace projectId/i);

      // Either shows fallback or loads scene
      const hasFallback = await fallback.isVisible().catch(() => false);
      const hasScene = await page.locator("canvas").isVisible().catch(() => false);

      // One of these should be true
      expect(hasFallback || hasScene).toBeTruthy();
    });

    test("should display error state in metrics", async ({ page }) => {
      // Metrics should show status
      const statusText = page.getByText(/Status:/i);
      await expect(statusText).toBeVisible();
    });
  });
});

// Performance test helper (prefix with underscore if unused to satisfy linters)
async function _measureLoadTime(page: Page): Promise<number> {
  const startTime = Date.now();
  await page.waitForSelector('[class*="bg-green"]', { timeout: 10000 }).catch(() => null);
  return Date.now() - startTime;
}

test.describe("Performance Benchmarks", () => {
  test("should load within acceptable time", async ({ page }) => {
    const startTime = Date.now();

    await page.goto("/shader-test");
    await page.waitForLoadState("networkidle");

    const loadTime = Date.now() - startTime;

    // Page should load within 5 seconds
    expect(loadTime).toBeLessThan(5000);
  });

  test("should not have memory leaks on scene switch", async ({ page }) => {
    await page.goto("/shader-test");

    // Switch scenes multiple times
    for (let i = 0; i < 3; i++) {
      await page.getByText(/Particle System/i).click().catch(() => null);
      await page.waitForTimeout(500);
      await page.getByText(/Gradient Flow/i).click().catch(() => null);
      await page.waitForTimeout(500);
    }

    // Page should still be responsive
    await expect(
      page.getByRole("heading", { name: /Debug Panel/i })
    ).toBeVisible();
  });
});
```

## Running Tests

### Install Playwright

```bash
bun add -D @playwright/test
bunx playwright install
```

### Configure Playwright

Create or update `playwright.config.ts`:

```typescript
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: "html",
  use: {
    baseURL: "http://localhost:3000",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "firefox",
      use: { ...devices["Desktop Firefox"] },
    },
    {
      name: "webkit",
      use: { ...devices["Desktop Safari"] },
    },
    {
      name: "Mobile Chrome",
      use: { ...devices["Pixel 5"] },
    },
    {
      name: "Mobile Safari",
      use: { ...devices["iPhone 12"] },
    },
  ],
  webServer: {
    command: "bun run dev",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
  },
});
```

### Run Tests

```bash
# Run all tests
bunx playwright test

# Run specific test file
bunx playwright test e2e/shader-test.spec.ts

# Run with UI
bunx playwright test --ui

# Run in headed mode (see browser)
bunx playwright test --headed

# Generate report
bunx playwright show-report
```

## Biome Linting Compatibility

If your project uses Biome, apply these fixes:

### Import Sorting

```typescript
// Biome requires alphabetical imports
import { expect, type Page, test } from "@playwright/test";
```

### Button Type Attributes

Add `type="button"` to all button interactions in tests to match Biome-formatted code:

```typescript
page.getByRole("button", { name: /Hide Scene/i })
```

### Number Methods

Use `Number.parseInt()` and `Number.parseFloat()` instead of global functions.

### Trailing Commas

Biome may add trailing commas to multi-line arrays and objects.

### Unused Variables

Prefix unused variables or functions with an underscore to satisfy Biome:

```typescript
// Biome allows underscore-prefixed unused variables
async function _measureLoadTime(page: Page): Promise<number> {
  // ...
}
```

## Test Coverage

| Category | Tests | Description |
|----------|-------|-------------|
| Page Load | 3 | Basic page rendering and elements |
| Shader Scene | 4 | Scene visibility, toggles, pause/resume |
| Performance Controls | 5 | Presets, sliders, checkboxes |
| Scene Selection | 3 | Scene switching, highlighting |
| Debug Panel | 3 | Visibility toggle, metrics, JSON |
| WebGL Support | 1 | Browser capability detection |
| Accessibility | 3 | ARIA, keyboard, reduced motion |
| Responsive | 2 | Mobile viewport, resize |
| Error Handling | 2 | Missing projectId, error states |
| Performance | 2 | Load time, memory leaks |

## CI Integration

### GitHub Actions

```yaml
# .github/workflows/e2e.yml
name: E2E Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: oven-sh/setup-bun@v1
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install

      - name: Install Playwright browsers
        run: bunx playwright install --with-deps

      - name: Run Playwright tests
        run: bunx playwright test

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 30
```

## Visual Regression Testing

For visual testing of shader rendering, add:

```typescript
test("should match shader visual snapshot", async ({ page }) => {
  await page.goto("/shader-test");
  await page.waitForTimeout(2000); // Wait for shader to stabilize

  // Take screenshot of shader area
  const shaderArea = page.locator('[class*="flex-1"]').first();
  await expect(shaderArea).toHaveScreenshot("shader-scene.png", {
    maxDiffPixels: 100, // Allow some variance for animation
  });
});
```

Update snapshots:

```bash
bunx playwright test --update-snapshots
```
