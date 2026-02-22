---
name: lottie
description: Setup Lottie animations for Next.js with JSON-based vector animations. Use this skill when the user says "setup lottie", "add lottie", "lottie animation", "json animation", or "vector animation".
author: "@mattwoodco"
version: 1.1.0
created: 2026-01-12
updated: 2026-02-13
---

# Lottie Animations for Next.js

Lightweight, scalable JSON-based animations using lottie-react. Perfect for micro-interactions, loading states, icons, and hero animations.

## Why Lottie?

- **Tiny file sizes**: Up to 600% smaller than GIFs
- **Infinite scalability**: Vector-based, sharp at any resolution
- **Full control**: Play, pause, speed, direction, segments
- **Interactive**: Scroll-sync, hover triggers, click events
- **Cross-platform**: Same JSON works on web, iOS, Android

## Installation

```bash
bun add lottie-react
```

**Version Compatibility:**
- Next.js 15+/16+ with React 19: Works with dynamic imports (`ssr: false`)
- lottie-react wraps lottie-web, which requires browser APIs
- Note: Next.js 16 removed the `eslint` key from `next.config.ts` — use Biome instead

## Next.js App Router Setup

Lottie uses browser APIs (canvas/SVG). Use dynamic imports to prevent SSR errors.

### 1. Create the Lottie Component

```tsx
// components/lottie/lottie-animation.tsx
"use client";

import { useEffect, useRef } from "react";
import Lottie from "lottie-react";
import type { LottieRefCurrentProps } from "lottie-react";

type LottieAnimationProps = {
  animationData: object;
  loop?: boolean;
  autoplay?: boolean;
  speed?: number;
  direction?: 1 | -1;
  className?: string;
  onComplete?: () => void;
  onLoopComplete?: () => void;
};

export function LottieAnimation({
  animationData,
  loop = true,
  autoplay = true,
  speed = 1,
  direction = 1,
  className,
  onComplete,
  onLoopComplete,
}: LottieAnimationProps) {
  const lottieRef = useRef<LottieRefCurrentProps>(null);

  useEffect(() => {
    if (lottieRef.current) {
      lottieRef.current.setSpeed(speed);
      lottieRef.current.setDirection(direction);
    }
  }, [speed, direction]);

  return (
    <Lottie
      lottieRef={lottieRef}
      animationData={animationData}
      loop={loop}
      autoplay={autoplay}
      className={className}
      onComplete={onComplete}
      onLoopComplete={onLoopComplete}
    />
  );
}
```

### 2. Create Dynamic Import Wrapper

```tsx
// components/lottie/dynamic-lottie.tsx
"use client";

import dynamic from "next/dynamic";

export const DynamicLottie = dynamic(
  () => import("./lottie-animation").then((mod) => mod.LottieAnimation),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-full w-full items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-gray-300 border-t-blue-500" />
      </div>
    ),
  }
);
```

### 3. Store Animation JSON Files

Place Lottie JSON files in `src/animations/` so the `@/` alias works (since `@/` maps to `./src/`). Do NOT put them under `public/` if you plan to import them — the `@/public/` path will fail because `@/` resolves to `./src/`, not the project root.

```
src/
  animations/
    checkmark.json
    loading.json
    success.json
```

### 4. Use in Page

**Important:** If you pass event handler props (like `onComplete`, `onLoopComplete`), the parent must be a Client Component. Server Components cannot pass functions as props to Client Components.

```tsx
// app/page.tsx
"use client";

import { DynamicLottie } from "@/components/lottie/dynamic-lottie";
import checkmarkAnimation from "@/animations/checkmark.json";

export default function Page() {
  return (
    <div className="h-64 w-64">
      <DynamicLottie
        animationData={checkmarkAnimation}
        loop={false}
        onComplete={() => console.log("Animation complete!")}
      />
    </div>
  );
}
```

If you don't need event handlers, the page can remain a Server Component:

```tsx
// app/page.tsx (Server Component - no event handlers)
import { DynamicLottie } from "@/components/lottie/dynamic-lottie";
import checkmarkAnimation from "@/animations/checkmark.json";

export default function Page() {
  return (
    <div className="h-64 w-64">
      <DynamicLottie animationData={checkmarkAnimation} loop={false} />
    </div>
  );
}
```

## Core Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `animationData` | `object` | required | The Lottie JSON data |
| `loop` | `boolean \| number` | `true` | Loop infinitely or N times |
| `autoplay` | `boolean` | `true` | Start playing immediately |
| `speed` | `number` | `1` | Playback speed (1 = normal) |
| `initialSegment` | `[number, number]` | - | Start/end frames |
| `style` | `CSSProperties` | - | Container styles |
| `className` | `string` | - | Container class |

## Playback Control Methods

Access via `lottieRef`:

```tsx
"use client";

import Lottie from "lottie-react";
import type { LottieRefCurrentProps } from "lottie-react";
import { useRef } from "react";
import animationData from "./animation.json";

export function ControlledAnimation() {
  const lottieRef = useRef<LottieRefCurrentProps>(null);

  return (
    <div>
      <Lottie
        lottieRef={lottieRef}
        animationData={animationData}
        autoplay={false}
      />

      <div className="flex gap-2 mt-4">
        <button onClick={() => lottieRef.current?.play()}>
          Play
        </button>
        <button onClick={() => lottieRef.current?.pause()}>
          Pause
        </button>
        <button onClick={() => lottieRef.current?.stop()}>
          Stop
        </button>
        <button onClick={() => lottieRef.current?.setSpeed(2)}>
          2x Speed
        </button>
        <button onClick={() => lottieRef.current?.setDirection(-1)}>
          Reverse
        </button>
        <button onClick={() => lottieRef.current?.goToAndPlay(0, true)}>
          Restart
        </button>
      </div>
    </div>
  );
}
```

### All Methods

| Method | Parameters | Description |
|--------|------------|-------------|
| `play()` | - | Start playback |
| `pause()` | - | Pause at current frame |
| `stop()` | - | Stop and reset to frame 0 |
| `setSpeed(speed)` | `number` | Set playback speed |
| `setDirection(dir)` | `1 \| -1` | Forward or reverse |
| `goToAndPlay(value, isFrame?)` | `number, boolean` | Jump and play |
| `goToAndStop(value, isFrame?)` | `number, boolean` | Jump and stop |
| `playSegments(segments, force?)` | `[number, number][], boolean` | Play specific segments |
| `getDuration(inFrames?)` | `boolean` | Get total duration |
| `destroy()` | - | Cleanup |

## Event Callbacks

```tsx
<Lottie
  animationData={animationData}
  onComplete={() => console.log("Animation finished")}
  onLoopComplete={() => console.log("Loop completed")}
  onEnterFrame={(e) => console.log("Frame:", e.currentTime)}
  onSegmentStart={() => console.log("Segment started")}
  onConfigReady={() => console.log("Config ready")}
  onDataReady={() => console.log("Data loaded")}
  onDOMLoaded={() => console.log("DOM ready")}
  onDestroy={() => console.log("Destroyed")}
/>
```

## Hover Trigger Animation

```tsx
"use client";

import Lottie from "lottie-react";
import type { LottieRefCurrentProps } from "lottie-react";
import { useRef } from "react";
import iconAnimation from "./icon.json";

export function HoverIcon() {
  const lottieRef = useRef<LottieRefCurrentProps>(null);

  return (
    <div
      className="h-12 w-12 cursor-pointer"
      onMouseEnter={() => lottieRef.current?.play()}
      onMouseLeave={() => lottieRef.current?.stop()}
    >
      <Lottie
        lottieRef={lottieRef}
        animationData={iconAnimation}
        autoplay={false}
        loop={false}
      />
    </div>
  );
}
```

## Click Toggle Animation

```tsx
"use client";

import Lottie from "lottie-react";
import type { LottieRefCurrentProps } from "lottie-react";
import { useRef, useState } from "react";
import toggleAnimation from "./toggle.json";

export function ClickToggle() {
  const lottieRef = useRef<LottieRefCurrentProps>(null);
  const [isActive, setIsActive] = useState(false);

  const handleClick = () => {
    if (isActive) {
      lottieRef.current?.setDirection(-1);
    } else {
      lottieRef.current?.setDirection(1);
    }
    lottieRef.current?.play();
    setIsActive(!isActive);
  };

  return (
    <button onClick={handleClick} className="h-16 w-16">
      <Lottie
        lottieRef={lottieRef}
        animationData={toggleAnimation}
        autoplay={false}
        loop={false}
      />
    </button>
  );
}
```

## Scroll-Triggered Animation

```tsx
"use client";

import Lottie from "lottie-react";
import type { LottieRefCurrentProps } from "lottie-react";
import { useRef, useEffect } from "react";
import scrollAnimation from "./scroll-reveal.json";

export function ScrollReveal() {
  const lottieRef = useRef<LottieRefCurrentProps>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            lottieRef.current?.play();
          } else {
            lottieRef.current?.stop();
          }
        });
      },
      { threshold: 0.5 }
    );

    if (containerRef.current) {
      observer.observe(containerRef.current);
    }

    return () => observer.disconnect();
  }, []);

  return (
    <div ref={containerRef} className="h-64 w-64">
      <Lottie
        lottieRef={lottieRef}
        animationData={scrollAnimation}
        autoplay={false}
        loop={false}
      />
    </div>
  );
}
```

## Scroll Progress Sync

```tsx
"use client";

import Lottie from "lottie-react";
import type { LottieRefCurrentProps } from "lottie-react";
import { useRef, useEffect, useState } from "react";
import progressAnimation from "./progress.json";

export function ScrollProgress() {
  const lottieRef = useRef<LottieRefCurrentProps>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [totalFrames, setTotalFrames] = useState(0);

  useEffect(() => {
    const duration = lottieRef.current?.getDuration(true);
    if (duration) setTotalFrames(duration);
  }, []);

  useEffect(() => {
    const handleScroll = () => {
      if (!containerRef.current || !lottieRef.current || !totalFrames) return;

      const rect = containerRef.current.getBoundingClientRect();
      const scrollProgress = Math.max(
        0,
        Math.min(1, 1 - rect.top / window.innerHeight)
      );

      const frame = Math.floor(scrollProgress * totalFrames);
      lottieRef.current.goToAndStop(frame, true);
    };

    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, [totalFrames]);

  return (
    <div ref={containerRef} className="sticky top-0 h-screen">
      <Lottie
        lottieRef={lottieRef}
        animationData={progressAnimation}
        autoplay={false}
        loop={false}
      />
    </div>
  );
}
```

## Accessibility: Reduced Motion

```tsx
"use client";

import Lottie from "lottie-react";
import { useEffect, useState } from "react";
import animationData from "./animation.json";

export function AccessibleAnimation() {
  const [prefersReducedMotion, setPrefersReducedMotion] = useState(false);

  useEffect(() => {
    const mediaQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    setPrefersReducedMotion(mediaQuery.matches);

    const handler = (e: MediaQueryListEvent) => {
      setPrefersReducedMotion(e.matches);
    };

    mediaQuery.addEventListener("change", handler);
    return () => mediaQuery.removeEventListener("change", handler);
  }, []);

  if (prefersReducedMotion) {
    return (
      <div className="flex h-full w-full items-center justify-center bg-gray-100">
        <span className="text-2xl">✓</span>
      </div>
    );
  }

  return <Lottie animationData={animationData} />;
}
```

## Loading State Component

```tsx
"use client";

import dynamic from "next/dynamic";
import loadingAnimation from "@/animations/loading.json";

const Lottie = dynamic(() => import("lottie-react"), { ssr: false });

type LoadingSpinnerProps = {
  size?: number;
  className?: string;
};

export function LoadingSpinner({ size = 48, className }: LoadingSpinnerProps) {
  return (
    <div
      className={className}
      style={{ width: size, height: size }}
      role="status"
      aria-label="Loading"
    >
      <Lottie
        animationData={loadingAnimation}
        loop
        autoplay
      />
    </div>
  );
}
```

## Success/Error Feedback

```tsx
"use client";

import dynamic from "next/dynamic";
import successAnimation from "@/animations/success.json";
import errorAnimation from "@/animations/error.json";

const Lottie = dynamic(() => import("lottie-react"), { ssr: false });

type FeedbackProps = {
  type: "success" | "error";
  onComplete?: () => void;
};

export function Feedback({ type, onComplete }: FeedbackProps) {
  const animationData = type === "success" ? successAnimation : errorAnimation;

  return (
    <div className="h-24 w-24">
      <Lottie
        animationData={animationData}
        loop={false}
        onComplete={onComplete}
      />
    </div>
  );
}
```

## Performance Best Practices

### 1. Lazy Load Animations

```tsx
import dynamic from "next/dynamic";

const HeroAnimation = dynamic(
  () => import("@/components/lottie/hero-animation"),
  {
    ssr: false,
    loading: () => <div className="h-96 w-full animate-pulse bg-gray-200" />,
  }
);
```

### 2. Optimize JSON Files

- Use [LottieFiles Optimizer](https://lottiefiles.com/tools/lottie-optimizer)
- Remove unused layers and assets
- Reduce keyframes where possible
- Target < 50KB for hero animations, < 10KB for icons

### 3. Use Segments for Long Animations

```tsx
// Only play frames 0-60 instead of the whole animation
<Lottie
  animationData={animationData}
  initialSegment={[0, 60]}
/>
```

### 4. Destroy on Unmount

The component handles this automatically, but for manual control:

```tsx
useEffect(() => {
  return () => {
    lottieRef.current?.destroy();
  };
}, []);
```

### 5. Reduce Render Quality on Low-End Devices

```tsx
<Lottie
  animationData={animationData}
  rendererSettings={{
    preserveAspectRatio: "xMidYMid slice",
    progressiveLoad: true,
  }}
/>
```

## File Structure

```
src/
  components/
    lottie/
      lottie-animation.tsx      # Base component
      dynamic-lottie.tsx        # SSR-safe wrapper
      loading-spinner.tsx       # Loading state
      hover-icon.tsx            # Hover trigger
      scroll-reveal.tsx         # Intersection observer
  animations/
    loading.json                # Loading spinner
    success.json                # Success checkmark
    error.json                  # Error X
    hero.json                   # Hero section
```

## Where to Get Animations

| Source | URL | Notes |
|--------|-----|-------|
| LottieFiles | https://lottiefiles.com/free-animations | Largest free library |
| IconScout | https://iconscout.com/lottie-animations | Curated collections |
| Lordicon | https://lordicon.com | Animated icons |
| Creattie | https://creattie.com | Free icon packs |
| Motion Elements | https://www.motionelements.com/lottie | Premium options |

## Importing JSON Files

### Option 1: Import directly (recommended)

Place JSON files in `src/animations/` and use the `@/` alias:

```tsx
import animationData from "@/animations/success.json";
```

JSON imports work by default in Next.js — no additional config needed.

**Important:** Do NOT use `@/public/animations/...` for imports. The `@/` alias maps to `./src/`, so `@/public/` resolves to `./src/public/` which does not exist. Either place files in `src/animations/` or use runtime fetching from `public/`.

### Option 2: Fetch at runtime (from `public/`)

If you prefer to serve JSON from the `public/` directory (for CDN caching), fetch at runtime:

```tsx
const [animationData, setAnimationData] = useState<object | null>(null);

useEffect(() => {
  fetch("/animations/success.json")
    .then((res) => res.json())
    .then(setAnimationData);
}, []);
```

## Vercel Deployment

1. **JSON files**: Place in `src/animations/` for direct imports. If you need CDN-served static files, place in `public/animations/` and fetch at runtime.
2. **Bundle size**: lottie-react is ~45KB minified
3. **Edge compatibility**: Works with Edge Runtime (client-side only)
4. **CDN caching**: Files in `public/` are cached at edge automatically

## Common Issues

### Server Components and Event Handlers

You cannot pass function props (like `onComplete`, `onLoopComplete`) from a Server Component to a Client Component. If your page needs event handlers, mark it as `"use client"`:

```tsx
// WRONG - Server Component passing a function prop
import { DynamicLottie } from "@/components/lottie/dynamic-lottie";
export default function Page() {
  return <DynamicLottie onComplete={() => {}} />; // Error!
}

// CORRECT - Client Component can pass function props
"use client";
import { DynamicLottie } from "@/components/lottie/dynamic-lottie";
export default function Page() {
  return <DynamicLottie onComplete={() => {}} />; // Works
}
```

### Biome/ESLint Import Order

Type imports should come after React imports but before default imports:

```tsx
// Correct order for Biome compatibility
import { useCallback, useEffect, useRef, useState } from "react";
import Lottie from "lottie-react";
import type { LottieRefCurrentProps } from "lottie-react";
import type { BMCompleteEvent, BMEnterFrameEvent } from "lottie-web";
```

### Accessibility: Label vs Span for Button Groups

Use `<span>` instead of `<label>` for button group headings. Labels must be associated with form controls:

```tsx
// WRONG - causes accessibility lint errors
<label>Speed: {speed}x</label>
<div className="flex gap-2">
  <button>0.5x</button>
  <button>1x</button>
</div>

// CORRECT - use span for button group headings
<span className="block text-sm font-medium">Speed: {speed}x</span>
<div className="flex gap-2">
  <button>0.5x</button>
  <button>1x</button>
</div>

// CORRECT - label with associated input
<label htmlFor="frame-slider">Frame Seek</label>
<input id="frame-slider" type="range" />
```

### Importing JSON from Components

Always use the `@/` alias pointing to `src/animations/`:

```tsx
// From any file under src/
import checkmarkAnimation from "@/animations/checkmark.json";
```

### Event Handler Types

Import event types from `lottie-web` for proper typing:

```tsx
import type {
  BMCompleteEvent,
  BMCompleteLoopEvent,
  BMEnterFrameEvent,
} from "lottie-web";

const handleEnterFrame = (event: BMEnterFrameEvent) => {
  console.log("Frame:", event.currentTime);
};
```

### "document is not defined"

Always use dynamic import with `ssr: false`:

```tsx
const Lottie = dynamic(() => import("lottie-react"), { ssr: false });
```

### Animation not playing

Check `autoplay={true}` and ensure the component is mounted:

```tsx
useEffect(() => {
  lottieRef.current?.play();
}, []);
```

### Animation flickering

Set explicit dimensions on container:

```tsx
<div className="h-64 w-64">
  <Lottie animationData={data} />
</div>
```

### Type errors with JSON import

Create a type declaration file:

```ts
// types/lottie.d.ts
declare module "*.json" {
  const value: object;
  export default value;
}
```

## References

- [lottie-react Documentation](https://lottiereact.com/)
- [lottie-web GitHub](https://github.com/airbnb/lottie-web)
- [LottieFiles](https://lottiefiles.com/)
- [Lottie Editor](https://lottiefiles.com/lottie-editor)
