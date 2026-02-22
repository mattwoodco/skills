---
name: add-shadcn
description: Setup a design system using shadcn/ui. Use this skill when the user says "setup design system", "set up design system", "create design system", "setup shadcn", or "initialize design system".
author: "@mattwoodco"
version: 1.5.0
created: 2026-01-11
updated: 2026-02-18
validated: 2026-02-18
dependencies: [create-next]
---

## Quick Start

The `shadcn/ui` initialization supports custom themes via a URL parameter.

**Compatibility:** This skill works with both standard Next.js projects and projects using `--no-src-dir`. The component paths (`components/`) automatically adapt to your project structure.

Use this command

```bash
bunx shadcn@latest create $(jq -r .name package.json) --preset "https://ui.shadcn.com/init?base=base&baseColor=gray&theme=emerald&iconLibrary=phosphor&radius=none&style=maia&font=nunito-sans&menuAccent=subtle&menuColor=default&template=next" --template next
```

After initialization, auto-fix formatting and lint issues in generated components:

```bash
bunx biome format --write . && bunx biome check --fix .
```

**Note:** The `format` step fixes whitespace/style, and the `check --fix` step fixes import sorting (`organizeImports`) in shadcn-generated files. Both are required — shadcn components ship with unsorted imports that fail `biome check`.

### Remove Demo Component

The shadcn preset includes a demo `component-example.tsx` file. Remove it:

```bash
rm -f src/components/component-example.tsx components/component-example.tsx
```

### Update globals.css

After initialization, add the following to `app/globals.css` (or `src/app/globals.css`) inside the `@layer base` block, or as a top-level rule:

```css
html {
  @apply h-dvh overscroll-none;
}
```

This ensures the app fills the dynamic viewport height on mobile and prevents overscroll bounce effects.

### Enforce Monochrome Dark Mode Grays (Required)

After initialization, **always** post-process the `.dark` theme block in `globals.css` to remove chroma from all neutral gray variables. shadcn themes sometimes generate dark grays with blue or purple tint (non-zero chroma in oklch). Mixing these tinted grays with components that use pure neutrals (e.g., React Flow, canvas elements, third-party widgets) creates an ugly warm/cold mismatch.

**Rule:** Every oklch color in the `.dark {}` block that represents a **neutral gray** (background, card, popover, muted, accent, secondary, sidebar, ring, foreground) must have **chroma set to 0**. Only accent colors like `--primary`, `--destructive`, and `--chart-*` should retain chroma.

For example, if shadcn generates:
```css
.dark {
  --background: oklch(0.13 0.028 261.692);
  --card: oklch(0.21 0.034 264.665);
  --muted: oklch(0.278 0.033 256.848);
  --muted-foreground: oklch(0.707 0.022 261.325);
}
```

Post-process to:
```css
.dark {
  --background: oklch(0.13 0 0);
  --card: oklch(0.18 0 0);
  --muted: oklch(0.22 0 0);
  --muted-foreground: oklch(0.65 0 0);
}
```

**Variables to make monochrome (chroma=0, hue=0):**
`--background`, `--foreground`, `--card`, `--card-foreground`, `--popover`, `--popover-foreground`, `--secondary`, `--secondary-foreground`, `--muted`, `--muted-foreground`, `--accent`, `--accent-foreground`, `--border`, `--input`, `--ring`, `--sidebar`, `--sidebar-foreground`, `--sidebar-accent`, `--sidebar-accent-foreground`

**Variables to keep as-is (retain generated chroma):**
`--primary`, `--primary-foreground`, `--destructive`, `--chart-1` through `--chart-5`, `--sidebar-primary`, `--sidebar-primary-foreground`

After initialization, if an `AGENTS.md` file exists at the project root, verify it documents the Base UI and Phosphor icon conventions. The `create-next` skill creates this file with the correct conventions.

## Multi-Registry Configuration

shadcn/ui supports multiple component registries beyond the official library. This enables access to specialized components from third-party sources.

### Recommended Registries

**React Bits** - Animated and interactive components
- URL: https://reactbits.dev/
- Installation: `npx shadcn add @react-bits/<component>`

**ElevenLabs UI** - Agent and audio components
- URL: https://ui.elevenlabs.io/
- Installation: `npx shadcn add @elevenlabs-ui/<component>`

**MapCN** - Map components built on MapLibre
- URL: https://mapcn.dev/
- Installation: `npx shadcn add @mapcn/<component>`

### Configure Custom Registries

After running `shadcn init`, your `components.json` file supports namespace-based registries. Add custom registries to the configuration:

```json
{
  "$schema": "https://ui.shadcn.com/schema.json",
  "style": "base-maia",
  "registries": {
    "@react-bits": {
      "url": "https://reactbits.dev"
    },
    "@elevenlabs-ui": {
      "url": "https://ui.elevenlabs.io"
    },
    "@mapcn": {
      "url": "https://mapcn.dev"
    }
  }
}
```

**Note:** Most community registries work without explicit configuration - the CLI discovers them automatically. The registries section is only needed for private or custom registries.

### Using Components from Different Registries

```bash
# Official shadcn components
bunx shadcn@latest add button

# React Bits - animated components
bunx shadcn@latest add @react-bits/animated-card

# ElevenLabs - audio player
bunx shadcn@latest add @elevenlabs-ui/audio-player

# MapCN - interactive maps
bunx shadcn@latest add @mapcn/map-viewer
```

### MCP Server for Natural Language Component Discovery

The shadcn MCP server enables AI-assisted component discovery and installation using natural language.

**Setup:**
```bash
# Install shadcn MCP server (if using Claude Code or compatible IDE)
# Configuration is typically added to your MCP settings
```

**Usage:**
Ask your AI assistant to find and install components:
- "Find me a login form from the shadcn registry"
- "Install an animated card component from React Bits"
- "Add a map component for displaying locations"

The MCP server works with:
- Official shadcn/ui registry
- Third-party component libraries (React Bits, ElevenLabs UI, MapCN, etc.)
- Private company registries (requires authentication via `.env.local`)

## Dark Mode Setup (Required)

After running the shadcn init command, dark mode requires additional setup.

### 1. Install Dependencies

```bash
bun add next-themes
```

### 2. Create ThemeProvider Component

Create `components/theme-provider.tsx`:

```tsx
"use client";

import { ThemeProvider as NextThemesProvider } from "next-themes";

type ThemeProviderProps = React.ComponentProps<typeof NextThemesProvider>;

export function ThemeProvider({ children, ...props }: ThemeProviderProps) {
  return <NextThemesProvider {...props}>{children}</NextThemesProvider>;
}
```

### 3. Create ModeToggle Component

**Note:** The preset includes the `dropdown-menu` component, so no additional installation is needed.

Create `components/mode-toggle.tsx`:

```tsx
"use client";

import { Moon, Sun } from "@phosphor-icons/react";
import { useTheme } from "next-themes";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

export function ModeToggle() {
  const { setTheme } = useTheme();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger className="inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 border border-input bg-background hover:bg-accent hover:text-accent-foreground h-10 w-10 shrink-0 cursor-pointer">
        <Sun size={20} className="scale-100 rotate-0 transition-transform dark:scale-0 dark:-rotate-90" />
        <Moon size={20} className="absolute scale-0 rotate-90 transition-transform dark:scale-100 dark:rotate-0" />
        <span className="sr-only">Toggle theme</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={() => setTheme("light")}>
          Light
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => setTheme("dark")}>
          Dark
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => setTheme("system")}>
          System
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
```

### 4. Update Root Layout

Update `app/layout.tsx` (or `src/app/layout.tsx`):

```tsx
import { Nunito_Sans } from "next/font/google";
import { ThemeProvider } from "@/components/theme-provider";

const nunitoSans = Nunito_Sans({ variable: "--font-sans" });

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning className={nunitoSans.variable}>
      <body className="font-sans antialiased">
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

> **Font setup:** The shadcn preset uses Nunito Sans with the `--font-sans` CSS variable, which is referenced by the `@theme inline` block in `globals.css`. The `font-sans` Tailwind utility then uses this variable.

### 5. Use the ModeToggle Component

The `ModeToggle` component is now ready to use anywhere in your app. Example usage in a page:

Update `app/page.tsx`:

```tsx
import { ModeToggle } from "@/components/mode-toggle";

export default function Home() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-background">
      <div className="text-center">
        <h1 className="text-4xl font-bold text-foreground mb-4">
          Dark Mode Setup Complete
        </h1>
        <p className="text-muted-foreground mb-8">
          Click the button below to toggle themes
        </p>
        <ModeToggle />
      </div>
    </div>
  );
}
```

## Critical Requirements

### Prevent Flash of Unstyled Content (FOUC)

- **Always** add `suppressHydrationWarning` to the `<html>` tag
- Use `disableTransitionOnChange` to prevent jarring transitions
- Use `defaultTheme="system"` to respect OS preference

### Use Semantic Color Classes

**DO NOT** use hardcoded colors like:

- `bg-white`, `bg-zinc-50`, `text-zinc-900`, `border-zinc-200`

**DO** use semantic colors:

- `bg-background`, `bg-muted`, `text-foreground`, `border-border`

### Tailwind CSS v4 Canonical Classes

This skill uses **Tailwind CSS v4**. Some class names have changed from v3:

| Old (v3) | New (v4) | Usage |
|----------|----------|-------|
| `bg-gradient-to-b` | `bg-linear-to-b` | Linear gradients |
| `bg-gradient-to-r` | `bg-linear-to-r` | Linear gradients |
| `bg-gradient-to-t` | `bg-linear-to-t` | Linear gradients |
| `bg-gradient-to-l` | `bg-linear-to-l` | Linear gradients |

**Always use canonical v4 class names** to avoid linter warnings.

### Color Token Reference

| Semantic Class | Light Mode | Dark Mode |
|---------------|------------|-----------|
| `bg-background` | White | Dark gray |
| `bg-foreground` | Dark text | Light text |
| `bg-card` | White | Dark card |
| `bg-muted` | Light gray | Dark gray |
| `bg-accent` | Hover state | Hover state |
| `bg-primary` | Brand color | Brand color |
| `text-foreground` | Dark text | Light text |
| `text-muted-foreground` | Gray text | Light gray text |
| `border-border` | Light border | Dark border |

### Common Patterns

Hero section:

```tsx
<section className="bg-linear-to-b from-muted/50 to-background">
```

Cards:

```tsx
<div className="bg-card border border-border rounded-xl">
```

Text:

```tsx
<h1 className="text-foreground">Title</h1>
<p className="text-muted-foreground">Description</p>
```

Buttons:

```tsx
<button className="bg-primary text-primary-foreground hover:bg-primary/90">
```

## Base UI Compatibility Notes

When using shadcn with **Base UI** (not Radix), several component APIs differ. Base UI variants **do not support `asChild`**. Use these patterns instead:

### Triggers: use `render` prop instead of `asChild`

```tsx
// WRONG - Base UI does not support asChild
<AlertDialogTrigger asChild>
  <Button variant="ghost">Delete</Button>
</AlertDialogTrigger>

// CORRECT - use render prop
<AlertDialogTrigger
  render={<Button variant="ghost" />}
>
  Delete
</AlertDialogTrigger>
```

### Styled links: use `buttonVariants` instead of `<Button asChild>`

```tsx
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

// WRONG - asChild not supported
<Button asChild variant="outline" size="sm">
  <a href={url} download>Download</a>
</Button>

// CORRECT - use buttonVariants utility
<a href={url} download className={cn(buttonVariants({ variant: "outline", size: "sm" }))}>
  Download
</a>
```

### DropdownMenuTrigger: apply styles directly

`DropdownMenuTrigger` renders a button by default. **Do NOT** wrap it with `<Button asChild>` — this causes nested buttons and hydration errors.

```tsx
// WRONG - causes hydration error
<DropdownMenuTrigger asChild>
  <Button variant="outline" size="icon">...</Button>
</DropdownMenuTrigger>

// CORRECT - apply styles directly
<DropdownMenuTrigger className="inline-flex items-center justify-center ...">
  ...
</DropdownMenuTrigger>
```

### Slider `onValueChange` type safety

The Base UI `Slider` `onValueChange` callback may return `number | number[]` depending on configuration. Always guard with `Array.isArray`:

```tsx
<Slider
  value={[currentValue]}
  onValueChange={(val) => {
    const num = Array.isArray(val) ? val[0] : val;
    setValue(num);
  }}
/>
```

## Practical Examples

### Example 1: Animated Landing Page Card (React Bits)

```bash
bunx shadcn@latest add @react-bits/animated-card
```

```tsx
import { AnimatedCard } from "@/components/ui/animated-card";

export function FeatureCard() {
  return (
    <AnimatedCard className="bg-card border border-border">
      <h3 className="text-foreground font-bold">Feature Title</h3>
      <p className="text-muted-foreground">Interactive animated card component</p>
    </AnimatedCard>
  );
}
```

### Example 2: Audio Player for Voice Content (ElevenLabs UI)

```bash
bunx shadcn@latest add @elevenlabs-ui/audio-player
```

```tsx
import { AudioPlayer } from "@/components/ui/audio-player";

export function VoicePreview() {
  return (
    <div className="bg-card border border-border rounded-xl p-4">
      <AudioPlayer
        src="/audio/sample.mp3"
        className="text-foreground"
      />
    </div>
  );
}
```

### Example 3: Interactive Map (MapCN)

```bash
bunx shadcn@latest add @mapcn/map-viewer
```

```tsx
import { MapViewer } from "@/components/ui/map-viewer";

export function LocationMap() {
  return (
    <MapViewer
      center={[-122.4194, 37.7749]}
      zoom={12}
      className="border border-border rounded-xl"
      markers={[
        { lat: 37.7749, lng: -122.4194, label: "San Francisco" }
      ]}
    />
  );
}
```

### Mixing Components from Multiple Registries

```tsx
import { Button } from "@/components/ui/button"; // Official shadcn
import { AnimatedCard } from "@/components/ui/animated-card"; // React Bits
import { AudioPlayer } from "@/components/ui/audio-player"; // ElevenLabs UI

export function RichMediaCard() {
  return (
    <AnimatedCard className="bg-card border border-border p-6">
      <h2 className="text-foreground text-2xl font-bold mb-4">Podcast Episode</h2>
      <AudioPlayer src="/episodes/latest.mp3" />
      <Button className="mt-4 bg-primary text-primary-foreground">
        Subscribe
      </Button>
    </AnimatedCard>
  );
}
```

## Testing Checklist

- [ ] Toggle works (Light/Dark/System)
- [ ] Theme persists after page refresh
- [ ] No white flash on page load
- [ ] No hydration errors in console
- [ ] All text readable in both modes
- [ ] All borders visible in both modes
- [ ] Components from different registries work together
- [ ] Registry namespaces resolve correctly
- [ ] `globals.css` contains `html { @apply h-dvh overscroll-none; }`
- [ ] `.dark` block in globals.css uses monochrome grays (chroma=0) for all neutral variables
