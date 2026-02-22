---
name: motion
description: Setup Motion (Framer Motion) for animations and transitions in Next.js. Use this skill when the user says "setup motion", "add animations", "framer motion", "animated transitions", "setup framer", or "motion effects".
author: "@mattwoodco"
version: 1.1.0
created: 2026-01-12
---

# Motion Skill

Production-grade animation library for React 19 and Next.js App Router. Motion (formerly Framer Motion) provides declarative animations, gestures, scroll effects, and layout transitions.

## Installation

```bash
bun add motion
```

## Quick Start

Motion components require client-side rendering in Next.js App Router.

```tsx
// components/motion/animated-button.tsx
"use client";

import { motion } from "motion/react";

export function AnimatedButton({ children }: { children: React.ReactNode }) {
  return (
    <motion.button
      whileHover={{ scale: 1.05 }}
      whileTap={{ scale: 0.95 }}
      transition={{ type: "spring", stiffness: 400, damping: 17 }}
      className="px-6 py-3 bg-primary text-primary-foreground rounded-lg"
    >
      {children}
    </motion.button>
  );
}
```

## Core Concepts

### Animation Anatomy

Every Motion animation has three parts:

1. **Initial State** - Where the animation starts (`initial`)
2. **Target State** - Where the animation ends (`animate`)
3. **Transition** - How it moves between states (`transition`)

```tsx
<motion.div
  initial={{ opacity: 0, y: 20 }}
  animate={{ opacity: 1, y: 0 }}
  transition={{ duration: 0.3, ease: "easeOut" }}
/>
```

### Spring vs Tween

- **Spring**: Physics-based, natural feel (use for `scale`, `x`, `y`, `rotate`)
- **Tween**: Duration-based, precise timing (use for `opacity`, `color`)

```tsx
// Spring (bouncy, responsive)
transition={{ type: "spring", stiffness: 400, damping: 17 }}

// Tween (precise timing)
transition={{ type: "tween", duration: 0.3, ease: "easeOut" }}
```

### Variants (Declarative Animation States)

Organize complex animations with named states:

```tsx
const cardVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: { opacity: 1, y: 0 },
  hover: { scale: 1.02 }
};

<motion.div
  variants={cardVariants}
  initial="hidden"
  animate="visible"
  whileHover="hover"
/>
```

---

## Utility Components

### 1. Motion Reveal (Scroll-Triggered)

```tsx
// components/motion/motion-reveal.tsx
"use client";

import { motion, type Variant } from "motion/react";
import type { ReactNode } from "react";

type RevealDirection = "up" | "down" | "left" | "right" | "none";

type MotionRevealProps = {
  children: ReactNode;
  direction?: RevealDirection;
  delay?: number;
  duration?: number;
  once?: boolean;
  amount?: number;
  className?: string;
};

const directionVariants: Record<RevealDirection, { hidden: Variant; visible: Variant }> = {
  up: {
    hidden: { opacity: 0, y: 50 },
    visible: { opacity: 1, y: 0 }
  },
  down: {
    hidden: { opacity: 0, y: -50 },
    visible: { opacity: 1, y: 0 }
  },
  left: {
    hidden: { opacity: 0, x: 50 },
    visible: { opacity: 1, x: 0 }
  },
  right: {
    hidden: { opacity: 0, x: -50 },
    visible: { opacity: 1, x: 0 }
  },
  none: {
    hidden: { opacity: 0 },
    visible: { opacity: 1 }
  }
};

export function MotionReveal({
  children,
  direction = "up",
  delay = 0,
  duration = 0.5,
  once = true,
  amount = 0.3,
  className
}: MotionRevealProps) {
  const variants = directionVariants[direction];

  return (
    <motion.div
      initial="hidden"
      whileInView="visible"
      viewport={{ once, amount }}
      variants={{
        hidden: variants.hidden,
        visible: {
          ...variants.visible,
          transition: {
            type: "spring",
            stiffness: 100,
            damping: 15,
            delay
          }
        }
      }}
      className={className}
    >
      {children}
    </motion.div>
  );
}
```

**Usage:**
```tsx
<MotionReveal direction="up" delay={0.1}>
  <Card>Content reveals on scroll</Card>
</MotionReveal>
```

### 2. Motion Stagger (List Animation)

```tsx
// components/motion/motion-stagger.tsx
"use client";

import { motion } from "motion/react";
import type { ReactNode } from "react";

type MotionStaggerProps = {
  children: ReactNode;
  staggerDelay?: number;
  delayChildren?: number;
  className?: string;
};

const containerVariants = {
  hidden: { opacity: 0 },
  visible: (custom: { staggerDelay: number; delayChildren: number }) => ({
    opacity: 1,
    transition: {
      staggerChildren: custom.staggerDelay,
      delayChildren: custom.delayChildren
    }
  })
};

export function MotionStagger({
  children,
  staggerDelay = 0.1,
  delayChildren = 0.2,
  className
}: MotionStaggerProps) {
  return (
    <motion.div
      variants={containerVariants}
      initial="hidden"
      animate="visible"
      custom={{ staggerDelay, delayChildren }}
      className={className}
    >
      {children}
    </motion.div>
  );
}

// Child component for stagger items
type MotionStaggerItemProps = {
  children: ReactNode;
  className?: string;
};

const itemVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: {
    opacity: 1,
    y: 0,
    transition: {
      type: "spring" as const,
      stiffness: 300,
      damping: 24
    }
  }
};

export function MotionStaggerItem({ children, className }: MotionStaggerItemProps) {
  return (
    <motion.div variants={itemVariants} className={className}>
      {children}
    </motion.div>
  );
}
```

**Usage:**
```tsx
<MotionStagger staggerDelay={0.1}>
  {items.map((item) => (
    <MotionStaggerItem key={item.id}>
      <Card>{item.title}</Card>
    </MotionStaggerItem>
  ))}
</MotionStagger>
```

### 3. Motion Button (Delightful Microinteractions)

```tsx
// components/motion/motion-button.tsx
"use client";

import { motion, type HTMLMotionProps } from "motion/react";
import type { ReactNode } from "react";

type ButtonVariant = "snappy" | "bouncy" | "subtle" | "heavy";

type MotionButtonProps = HTMLMotionProps<"button"> & {
  children: ReactNode;
  variant?: ButtonVariant;
};

const springConfigs: Record<ButtonVariant, { stiffness: number; damping: number; mass?: number }> = {
  snappy: { stiffness: 400, damping: 17 },
  bouncy: { stiffness: 300, damping: 10 },
  subtle: { stiffness: 500, damping: 30 },
  heavy: { stiffness: 230, damping: 4, mass: 4 }
};

const scaleConfigs: Record<ButtonVariant, { hover: number; tap: number }> = {
  snappy: { hover: 1.05, tap: 0.95 },
  bouncy: { hover: 1.1, tap: 0.9 },
  subtle: { hover: 1.02, tap: 0.98 },
  heavy: { hover: 1.05, tap: 0.95 }
};

export function MotionButton({
  children,
  variant = "snappy",
  className,
  ...props
}: MotionButtonProps) {
  const spring = springConfigs[variant];
  const scale = scaleConfigs[variant];

  return (
    <motion.button
      whileHover={{ scale: scale.hover }}
      whileTap={{ scale: scale.tap }}
      transition={{ type: "spring", ...spring }}
      className={className}
      {...props}
    >
      {children}
    </motion.button>
  );
}
```

**Usage:**
```tsx
<MotionButton variant="snappy" className="px-6 py-3 bg-primary text-white rounded-lg">
  Click Me
</MotionButton>
```

### 4. Motion Presence (Enter/Exit Animations)

```tsx
// components/motion/motion-presence.tsx
"use client";

import { AnimatePresence, motion } from "motion/react";
import type { ReactNode } from "react";

type PresenceVariant = "fade" | "slide" | "scale" | "slideUp";

type MotionPresenceProps = {
  children: ReactNode;
  isVisible: boolean;
  variant?: PresenceVariant;
  className?: string;
};

const presenceVariants = {
  fade: {
    initial: { opacity: 0 },
    animate: { opacity: 1 },
    exit: { opacity: 0 }
  },
  slide: {
    initial: { opacity: 0, x: 100 },
    animate: { opacity: 1, x: 0 },
    exit: { opacity: 0, x: -100 }
  },
  scale: {
    initial: { opacity: 0, scale: 0.9 },
    animate: { opacity: 1, scale: 1 },
    exit: { opacity: 0, scale: 0.9 }
  },
  slideUp: {
    initial: { opacity: 0, y: 20 },
    animate: { opacity: 1, y: 0 },
    exit: { opacity: 0, y: -20 }
  }
} as const;

export function MotionPresence({
  children,
  isVisible,
  variant = "fade",
  className
}: MotionPresenceProps) {
  const variants = presenceVariants[variant];

  return (
    <AnimatePresence mode="wait">
      {isVisible && (
        <motion.div
          initial={variants.initial}
          animate={{
            ...variants.animate,
            transition: { type: "spring", stiffness: 300, damping: 25 }
          }}
          exit={{
            ...variants.exit,
            transition: { ease: "easeIn", duration: 0.2 }
          }}
          className={className}
        >
          {children}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
```

**Usage:**
```tsx
<MotionPresence isVisible={isModalOpen} variant="scale">
  <Modal onClose={() => setIsModalOpen(false)} />
</MotionPresence>
```

### 5. Motion Layout (Shared Element Transitions)

```tsx
// components/motion/motion-layout.tsx
"use client";

import { motion, LayoutGroup, AnimatePresence } from "motion/react";
import type { ReactNode } from "react";

type MotionLayoutProps = {
  children: ReactNode;
  layoutId: string;
  className?: string;
};

export function MotionLayout({ children, layoutId, className }: MotionLayoutProps) {
  return (
    <motion.div
      layoutId={layoutId}
      layout
      transition={{
        type: "spring",
        stiffness: 300,
        damping: 30
      }}
      className={className}
    >
      {children}
    </motion.div>
  );
}

// Tab indicator component
type MotionTabIndicatorProps = {
  layoutId?: string;
  className?: string;
};

export function MotionTabIndicator({
  layoutId = "tab-indicator",
  className = "absolute bottom-0 left-0 right-0 h-0.5 bg-primary"
}: MotionTabIndicatorProps) {
  return (
    <motion.div
      layoutId={layoutId}
      className={className}
      transition={{
        type: "spring",
        stiffness: 500,
        damping: 30
      }}
    />
  );
}

// Layout group wrapper
type MotionLayoutGroupProps = {
  children: ReactNode;
  id?: string;
};

export function MotionLayoutGroup({ children, id }: MotionLayoutGroupProps) {
  return <LayoutGroup id={id}>{children}</LayoutGroup>;
}
```

**Usage:**
```tsx
<MotionLayoutGroup id="tabs">
  {tabs.map((tab) => (
    <button key={tab.id} onClick={() => setActiveTab(tab.id)} className="relative px-4 py-2">
      {tab.label}
      {activeTab === tab.id && <MotionTabIndicator />}
    </button>
  ))}
</MotionLayoutGroup>
```

### 6. Motion Page Transition (App Router)

```tsx
// components/motion/motion-page-transition.tsx
"use client";

import { AnimatePresence, motion } from "motion/react";
import { useSelectedLayoutSegment } from "next/navigation";
import { LayoutRouterContext } from "next/dist/shared/lib/app-router-context.shared-runtime";
import { useContext, useEffect, useRef, type ReactNode } from "react";

function usePreviousValue<T>(value: T): T | undefined {
  const prevValue = useRef<T | undefined>(undefined);

  useEffect(() => {
    prevValue.current = value;
    return () => {
      prevValue.current = undefined;
    };
  });

  return prevValue.current;
}

function FrozenRouter({ children }: { children: ReactNode }) {
  const context = useContext(LayoutRouterContext);
  const prevContext = usePreviousValue(context) || null;

  const segment = useSelectedLayoutSegment();
  const prevSegment = usePreviousValue(segment);

  const changed =
    segment !== prevSegment &&
    segment !== undefined &&
    prevSegment !== undefined;

  return (
    <LayoutRouterContext.Provider value={changed ? prevContext : context}>
      {children}
    </LayoutRouterContext.Provider>
  );
}

type MotionPageTransitionProps = {
  children: ReactNode;
  className?: string;
};

export function MotionPageTransition({ children, className }: MotionPageTransitionProps) {
  const segment = useSelectedLayoutSegment();

  return (
    <AnimatePresence mode="wait" initial={false}>
      <motion.div
        key={segment}
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -20 }}
        transition={{ duration: 0.3, ease: "easeInOut" }}
        className={className}
      >
        <FrozenRouter>{children}</FrozenRouter>
      </motion.div>
    </AnimatePresence>
  );
}
```

**Usage in layout.tsx:**
```tsx
// app/layout.tsx
import { MotionPageTransition } from "@/components/motion/motion-page-transition";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <MotionPageTransition>
          {children}
        </MotionPageTransition>
      </body>
    </html>
  );
}
```

---

## Spring Configuration Cheat Sheet

| Feel | Stiffness | Damping | Mass | Use Case |
|------|-----------|---------|------|----------|
| Snappy | 400 | 17 | 1 | Primary CTAs, buttons |
| Bouncy | 300 | 10 | 1 | Playful UIs, games |
| Subtle | 500 | 30 | 1 | Professional, enterprise |
| Heavy | 230 | 4 | 4 | Dramatic emphasis |
| Drawer | 380 | 32 | 1 | Slide-in panels |
| Pop | 600 | 20 | 1 | Notifications, toasts |

## Timing Guidelines

| Animation Type | Duration | Notes |
|---------------|----------|-------|
| Micro interactions | 150-250ms | Button hovers, toggles |
| Content changes | 250-400ms | Page transitions, modals |
| Large reveals | 400-600ms | Hero sections |
| Stagger delay | 50-150ms | Between list items |
| Exit animations | 150-250ms | Faster than enter |

## Best Practices

### Performance

1. **Use `layout` prop sparingly** - Only on elements that change size/position
2. **Lazy load with `whileInView`** - Don't animate off-screen elements
3. **Prefer `transform` properties** - `x`, `y`, `scale`, `rotate` are GPU-accelerated
4. **Keep exit animations short** - 200ms max for good UX

### Accessibility

1. **Respect reduced motion preference:**

```tsx
// components/motion/motion-safe.tsx
"use client";

import { motion, useReducedMotion } from "motion/react";
import type { ReactNode, ComponentProps } from "react";

type MotionSafeProps = ComponentProps<typeof motion.div> & {
  children: ReactNode;
};

export function MotionSafe({ children, ...props }: MotionSafeProps) {
  const shouldReduceMotion = useReducedMotion();

  if (shouldReduceMotion) {
    return <div className={props.className}>{children}</div>;
  }

  return <motion.div {...props}>{children}</motion.div>;
}
```

2. **Avoid motion sickness triggers** - No fast rotations, limit parallax depth

### SSR/Hydration

1. **Always use `"use client"`** - Motion components are client-only
2. **Use `initial={false}`** on `AnimatePresence` to skip first-mount animation
3. **Avoid layout animations on initial render** - Can cause hydration mismatch

### Keys

1. **Never use array index as key** - Breaks exit animations
2. **Use `useId()` for generated keys:**

```tsx
import { useId } from "react";

function List({ items }: { items: Item[] }) {
  const id = useId();
  return items.map((item, index) => (
    <motion.div key={`${id}-${item.id}`}>{item.content}</motion.div>
  ));
}
```

## Common Patterns

### Fade In on Mount
```tsx
<motion.div
  initial={{ opacity: 0 }}
  animate={{ opacity: 1 }}
  transition={{ duration: 0.3 }}
>
  Content
</motion.div>
```

### Hover Card Lift
```tsx
<motion.div
  whileHover={{ y: -4, boxShadow: "0 10px 30px rgba(0,0,0,0.1)" }}
  transition={{ type: "spring", stiffness: 400, damping: 17 }}
>
  Card content
</motion.div>
```

### Scroll Progress Bar
```tsx
import { useScroll, useSpring, motion } from "motion/react";

function ScrollProgress() {
  const { scrollYProgress } = useScroll();
  const scaleX = useSpring(scrollYProgress, { stiffness: 100, damping: 30 });

  return (
    <motion.div
      className="fixed top-0 left-0 right-0 h-1 bg-primary origin-left z-50"
      style={{ scaleX }}
    />
  );
}
```

### Toggle Switch
```tsx
<motion.div
  className={`w-14 h-8 flex items-center rounded-full p-1 cursor-pointer ${
    isOn ? "bg-primary justify-end" : "bg-muted justify-start"
  }`}
  onClick={toggle}
>
  <motion.div
    layout
    className="w-6 h-6 bg-background rounded-full shadow"
    transition={{ type: "spring", stiffness: 700, damping: 30 }}
  />
</motion.div>
```

## File Structure

```
components/
└── motion/
    ├── motion-reveal.tsx
    ├── motion-stagger.tsx
    ├── motion-button.tsx
    ├── motion-presence.tsx
    ├── motion-layout.tsx
    ├── motion-page-transition.tsx
    └── motion-safe.tsx
```

## Troubleshooting

### Exit animations not working
- Ensure `AnimatePresence` wraps the conditional, not inside it
- Check that each child has a unique `key` prop
- Don't use React Fragments (`<>`) as direct children

### Layout animation distortion
- Add `layout` prop to child elements too
- Use `style={{ borderRadius }}` instead of className for rounded corners
- Set `display: flex` or `grid` (not `inline`)

### Hydration errors
- Ensure `"use client"` directive is present
- Don't use `window` or `document` in initial values
- Use `initial={false}` on AnimatePresence

### Page transitions not working (App Router)
- Use the FrozenRouter pattern (see Motion Page Transition component)
- Ensure `useSelectedLayoutSegment` is used for the key
- Check that layout.tsx wraps children with the transition component

## Resources

- [Motion.dev Documentation](https://motion.dev)
- [Motion Examples](https://motion.dev/examples)
- [Maxime Heckel's Animation Guide](https://blog.maximeheckel.com/posts/guide-animations-spark-joy-framer-motion/)
- [Layout Animations Deep Dive](https://blog.maximeheckel.com/posts/framer-motion-layout-animations/)
- [Spring Physics Explained](https://blog.maximeheckel.com/posts/the-physics-behind-spring-animations/)
