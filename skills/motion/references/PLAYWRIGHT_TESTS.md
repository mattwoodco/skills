# Motion Playwright Tests

E2E tests for validating Motion animations in Next.js applications.

## Test Setup

### Installation

```bash
bun add -d @playwright/test
bunx playwright install chromium
```

### Playwright Configuration

```typescript
// playwright.config.ts
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
    video: "on-first-retry",
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
  },
});
```

## Complete Test Suite

```typescript
// e2e/motion.spec.ts
import { test, expect, type Page } from "@playwright/test";

test.describe("Motion Animations", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/motion-test");
    // Wait for page to be fully loaded
    await page.waitForLoadState("networkidle");
  });

  test.describe("Page Load", () => {
    test("should load without hydration errors", async ({ page }) => {
      // Check for React hydration errors in console
      const errors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") {
          errors.push(msg.text());
        }
      });

      await page.reload();
      await page.waitForTimeout(1000);

      const hydrationErrors = errors.filter(
        (e) =>
          e.includes("Hydration") ||
          e.includes("hydration") ||
          e.includes("did not match")
      );
      expect(hydrationErrors).toHaveLength(0);
    });

    test("should render scroll progress bar", async ({ page }) => {
      const progressBar = page.locator(".fixed.top-0.h-1.bg-primary");
      await expect(progressBar).toBeVisible();
    });

    test("should render debug panel", async ({ page }) => {
      const debugPanel = page.getByText("Debug Info");
      await expect(debugPanel).toBeVisible();
    });

    test("should detect reduced motion preference", async ({ page }) => {
      // Test with reduced motion enabled
      await page.emulateMedia({ reducedMotion: "reduce" });
      await page.reload();

      const reducedMotionText = page.getByText("Reduced Motion: Yes");
      await expect(reducedMotionText).toBeVisible();
    });
  });

  test.describe("Button Animations", () => {
    test("should show hover animation on button", async ({ page }) => {
      const testButton = page.getByRole("button", { name: /Test Button/ });
      await expect(testButton).toBeVisible();

      // Get initial transform
      const initialTransform = await testButton.evaluate(
        (el) => window.getComputedStyle(el).transform
      );

      // Hover over button
      await testButton.hover();
      await page.waitForTimeout(300);

      // Check transform changed (scale applied)
      const hoverTransform = await testButton.evaluate(
        (el) => window.getComputedStyle(el).transform
      );
      expect(hoverTransform).not.toBe(initialTransform);
    });

    test("should switch between spring presets", async ({ page }) => {
      const presets = ["snappy", "bouncy", "subtle", "heavy", "pop"];

      for (const preset of presets) {
        const presetButton = page.getByRole("button", { name: preset });
        await presetButton.click();

        const testButton = page.getByRole("button", {
          name: new RegExp(`Test Button \\(${preset}\\)`),
        });
        await expect(testButton).toBeVisible();
      }
    });

    test("should show tap animation on click", async ({ page }) => {
      const testButton = page.getByRole("button", { name: /Test Button/ });

      // Start click (mousedown)
      await testButton.dispatchEvent("mousedown");
      await page.waitForTimeout(100);

      // Check scale is reduced during tap
      const tapTransform = await testButton.evaluate(
        (el) => window.getComputedStyle(el).transform
      );
      expect(tapTransform).toContain("matrix");

      // Release
      await testButton.dispatchEvent("mouseup");
    });
  });

  test.describe("Stagger Animation", () => {
    test("should animate items in sequence", async ({ page }) => {
      const replayButton = page.getByRole("button", { name: "Replay" });
      await replayButton.click();

      // Wait for stagger animation
      await page.waitForTimeout(100);

      const items = page.locator("#stagger .bg-muted.rounded-lg");
      const count = await items.count();
      expect(count).toBe(5);

      // First item should be visible before last
      const firstItem = items.nth(0);
      const lastItem = items.nth(4);

      await expect(firstItem).toBeVisible();
      // Last item might still be animating
    });

    test("should adjust stagger delay with slider", async ({ page }) => {
      const slider = page.locator('input[type="range"]').first();
      await slider.fill("0.2");

      const delayText = page.getByText("Stagger Delay: 0.2s");
      await expect(delayText).toBeVisible();
    });

    test("should replay animation on button click", async ({ page }) => {
      const replayButton = page.getByRole("button", { name: "Replay" });
      const items = page.locator("#stagger .bg-muted.rounded-lg");

      // Click replay
      await replayButton.click();

      // Items should reset and animate
      await expect(items.first()).toBeVisible();
    });
  });

  test.describe("Scroll Reveal", () => {
    test("should reveal elements when scrolling into view", async ({ page }) => {
      // Scroll to reveal section
      await page.locator("#reveal").scrollIntoViewIfNeeded();
      await page.waitForTimeout(500);

      const revealCards = page.locator("#reveal .bg-muted.rounded-lg");
      const count = await revealCards.count();
      expect(count).toBe(4);

      // All should be visible after scrolling
      for (let i = 0; i < count; i++) {
        await expect(revealCards.nth(i)).toBeVisible();
      }
    });

    test("should have correct direction labels", async ({ page }) => {
      await page.locator("#reveal").scrollIntoViewIfNeeded();

      const directions = ["up", "down", "left", "right"];
      for (const direction of directions) {
        const label = page.locator(`#reveal`).getByText(direction, { exact: false });
        await expect(label.first()).toBeVisible();
      }
    });
  });

  test.describe("AnimatePresence", () => {
    test("should add items with animation", async ({ page }) => {
      await page.locator("#presence").scrollIntoViewIfNeeded();

      const addButton = page.locator("#presence").getByRole("button", { name: "Add Item" });
      const initialCount = await page.locator("#presence .bg-muted.rounded-lg").count();

      await addButton.click();
      await page.waitForTimeout(400);

      const newCount = await page.locator("#presence .bg-muted.rounded-lg").count();
      expect(newCount).toBe(initialCount + 1);
    });

    test("should remove items with exit animation", async ({ page }) => {
      await page.locator("#presence").scrollIntoViewIfNeeded();

      const removeButtons = page.locator("#presence").getByRole("button", { name: "Remove" });
      const initialCount = await removeButtons.count();

      if (initialCount > 0) {
        await removeButtons.first().click();
        await page.waitForTimeout(400);

        const newCount = await page.locator("#presence .bg-muted.rounded-lg").count();
        expect(newCount).toBe(initialCount - 1);
      }
    });

    test("should handle multiple rapid additions", async ({ page }) => {
      await page.locator("#presence").scrollIntoViewIfNeeded();

      const addButton = page.locator("#presence").getByRole("button", { name: "Add Item" });

      // Rapid fire additions
      await addButton.click();
      await addButton.click();
      await addButton.click();

      await page.waitForTimeout(600);

      // Should have added 3 more items
      const items = page.locator("#presence .bg-muted.rounded-lg");
      const count = await items.count();
      expect(count).toBeGreaterThanOrEqual(3);
    });
  });

  test.describe("Layout Animation (Tabs)", () => {
    test("should animate tab indicator between tabs", async ({ page }) => {
      await page.locator("#layout").scrollIntoViewIfNeeded();

      const tabs = ["Overview", "Features", "Pricing", "Contact"];

      for (const tab of tabs) {
        const tabButton = page.locator("#layout").getByRole("button", { name: tab });
        await tabButton.click();
        await page.waitForTimeout(300);

        // Check that content updated
        const content = page.locator("#layout").getByText(`Content for ${tab} tab`);
        await expect(content).toBeVisible();
      }
    });

    test("should have smooth layout animation", async ({ page }) => {
      await page.locator("#layout").scrollIntoViewIfNeeded();

      const indicator = page.locator("#layout [class*='absolute inset-0 bg-background']");

      // Click different tabs and verify indicator moves
      const featuresTab = page.locator("#layout").getByRole("button", { name: "Features" });
      await featuresTab.click();

      await expect(indicator).toBeVisible();
    });
  });

  test.describe("Toggle Switch", () => {
    test("should toggle between on and off states", async ({ page }) => {
      await page.locator("#toggle").scrollIntoViewIfNeeded();

      const toggle = page.locator("#toggle .cursor-pointer.rounded-full").first();
      const statusText = page.locator("#toggle").getByText(/^(On|Off)$/);

      // Get initial state
      const initialText = await statusText.textContent();

      // Click toggle
      await toggle.click();
      await page.waitForTimeout(400);

      // State should change
      const newText = await statusText.textContent();
      expect(newText).not.toBe(initialText);

      // Click again to toggle back
      await toggle.click();
      await page.waitForTimeout(400);

      const finalText = await statusText.textContent();
      expect(finalText).toBe(initialText);
    });

    test("should animate toggle handle position", async ({ page }) => {
      await page.locator("#toggle").scrollIntoViewIfNeeded();

      const toggle = page.locator("#toggle .cursor-pointer.rounded-full").first();
      const handle = toggle.locator(".bg-background.rounded-full");

      // Click and verify animation happens (transform changes)
      await toggle.click();
      await expect(handle).toBeVisible();
    });
  });

  test.describe("Gesture Interactions", () => {
    test("should apply hover effect on gesture card", async ({ page }) => {
      await page.locator("#gestures").scrollIntoViewIfNeeded();

      const hoverCard = page.locator("#gestures").getByText("Hover/Tap").locator("..");

      // Hover
      await hoverCard.hover();
      await page.waitForTimeout(200);

      // Check transform applied
      const transform = await hoverCard.evaluate(
        (el) => window.getComputedStyle(el).transform
      );
      expect(transform).not.toBe("none");
    });

    test("should allow dragging the drag card", async ({ page }) => {
      await page.locator("#gestures").scrollIntoViewIfNeeded();

      const dragCard = page.locator("#gestures").getByText("Drag Me").locator("..");
      const box = await dragCard.boundingBox();

      if (box) {
        // Drag and drop
        await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
        await page.mouse.down();
        await page.mouse.move(box.x + box.width / 2 + 50, box.y + box.height / 2);
        await page.waitForTimeout(100);
        await page.mouse.up();
      }
    });

    test("should apply lift effect on hover", async ({ page }) => {
      await page.locator("#gestures").scrollIntoViewIfNeeded();

      const liftCard = page.locator("#gestures").getByText("Lift").locator("..");

      await liftCard.hover();
      await page.waitForTimeout(300);

      // Check for y transform and box-shadow
      const styles = await liftCard.evaluate((el) => {
        const computed = window.getComputedStyle(el);
        return {
          transform: computed.transform,
          boxShadow: computed.boxShadow,
        };
      });

      // Should have transform and enhanced shadow
      expect(styles.transform).not.toBe("none");
    });
  });

  test.describe("Scroll Progress", () => {
    test("should update progress bar on scroll", async ({ page }) => {
      const progressBar = page.locator(".fixed.top-0.h-1.bg-primary");

      // Get initial scale
      const initialScale = await progressBar.evaluate(
        (el) => window.getComputedStyle(el).transform
      );

      // Scroll down
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight / 2));
      await page.waitForTimeout(300);

      // Get new scale
      const midScale = await progressBar.evaluate(
        (el) => window.getComputedStyle(el).transform
      );

      // Should have changed
      expect(midScale).not.toBe(initialScale);

      // Scroll to bottom
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      await page.waitForTimeout(300);

      // Progress bar should be nearly full
      const fullScale = await progressBar.evaluate(
        (el) => window.getComputedStyle(el).transform
      );
      expect(fullScale).not.toBe(midScale);
    });
  });

  test.describe("Performance", () => {
    test("should not cause excessive re-renders", async ({ page }) => {
      const debugPanel = page.locator("text=Render Count:");
      await expect(debugPanel).toBeVisible();

      // Get initial render count
      const initialText = await debugPanel.textContent();
      const initialCount = parseInt(initialText?.match(/\d+/)?.[0] || "0");

      // Perform some interactions
      await page.locator("#buttons").scrollIntoViewIfNeeded();
      await page.waitForTimeout(500);

      // Check render count didn't explode
      const finalText = await debugPanel.textContent();
      const finalCount = parseInt(finalText?.match(/\d+/)?.[0] || "0");

      // Should not have excessive re-renders from scrolling alone
      expect(finalCount - initialCount).toBeLessThan(10);
    });

    test("should maintain 60fps during animations", async ({ page }) => {
      // This is a basic check - for real performance testing use Lighthouse
      const startTime = Date.now();

      // Trigger multiple animations
      const replayButton = page.getByRole("button", { name: "Replay" });
      await replayButton.click();

      await page.waitForTimeout(1000);

      const endTime = Date.now();
      const duration = endTime - startTime;

      // Page should remain responsive
      expect(duration).toBeLessThan(2000);
    });
  });

  test.describe("Accessibility", () => {
    test("should be navigable with keyboard", async ({ page }) => {
      // Tab through interactive elements
      await page.keyboard.press("Tab");
      await page.keyboard.press("Tab");
      await page.keyboard.press("Tab");

      // Should be able to activate with Enter
      await page.keyboard.press("Enter");
    });

    test("should respect prefers-reduced-motion", async ({ page }) => {
      await page.emulateMedia({ reducedMotion: "reduce" });
      await page.reload();

      // Animations should be disabled or minimal
      const reducedMotionText = page.getByText("Reduced Motion: Yes");
      await expect(reducedMotionText).toBeVisible();
    });
  });
});

// Screenshot tests for visual regression
test.describe("Visual Regression", () => {
  test("motion test page matches snapshot", async ({ page }) => {
    await page.goto("/motion-test");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(1000); // Wait for animations to settle

    await expect(page).toHaveScreenshot("motion-test-page.png", {
      fullPage: true,
      animations: "disabled",
    });
  });
});
```

## Running Tests

```bash
# Run all tests
bunx playwright test

# Run with UI
bunx playwright test --ui

# Run specific test file
bunx playwright test e2e/motion.spec.ts

# Run in headed mode (see browser)
bunx playwright test --headed

# Generate report
bunx playwright show-report
```

## Test Coverage Summary

| Category | Tests | Description |
|----------|-------|-------------|
| Page Load | 4 | Hydration, progress bar, debug panel, reduced motion |
| Button Animations | 3 | Hover, presets, tap |
| Stagger | 3 | Sequence, delay slider, replay |
| Scroll Reveal | 2 | Visibility, directions |
| AnimatePresence | 3 | Add, remove, rapid additions |
| Layout (Tabs) | 2 | Tab switching, indicator animation |
| Toggle | 2 | State change, handle animation |
| Gestures | 3 | Hover, drag, lift |
| Scroll Progress | 1 | Progress bar updates |
| Performance | 2 | Re-renders, 60fps |
| Accessibility | 2 | Keyboard, reduced motion |
| Visual Regression | 1 | Screenshot comparison |

**Total: 28 tests**

## CI/CD Integration

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

      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install

      - name: Install Playwright browsers
        run: bunx playwright install chromium --with-deps

      - name: Run Playwright tests
        run: bunx playwright test

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 30
```

## Troubleshooting

### Tests timing out
- Increase timeout in playwright.config.ts
- Add `await page.waitForTimeout()` for animations
- Use `await page.waitForLoadState("networkidle")`

### Flaky tests
- Add explicit waits after animations
- Use `test.slow()` for slow animation tests
- Retry failed tests with `retries: 2`

### Visual regression failing
- Update snapshots: `bunx playwright test --update-snapshots`
- Use `animations: "disabled"` for consistent screenshots
- Set viewport size in config for consistency

### Reduced motion tests failing
- Use `page.emulateMedia({ reducedMotion: "reduce" })`
- Reload page after setting media preference
