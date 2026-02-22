# Motion Test Page

A comprehensive test/debug page for verifying Motion installation and demonstrating all animation patterns.

## Complete Test Page Component

```tsx
// app/motion-test/page.tsx
import { MotionTestEditor } from "@/components/motion/motion-test-editor";

export default function MotionTestPage() {
  return (
    <div className="min-h-screen bg-background">
      <MotionTestEditor />
    </div>
  );
}
```

## Motion Test Editor Component

```tsx
// components/motion/motion-test-editor.tsx
"use client";

import { useState, useId } from "react";
import {
  motion,
  AnimatePresence,
  useScroll,
  useSpring,
  useReducedMotion,
  LayoutGroup
} from "motion/react";

// Spring presets for testing
const springPresets = {
  snappy: { stiffness: 400, damping: 17 },
  bouncy: { stiffness: 300, damping: 10 },
  subtle: { stiffness: 500, damping: 30 },
  heavy: { stiffness: 230, damping: 4, mass: 4 },
  pop: { stiffness: 600, damping: 20 }
} as const;

type SpringPreset = keyof typeof springPresets;

// Section wrapper with reveal animation
function Section({
  title,
  children,
  id
}: {
  title: string;
  children: React.ReactNode;
  id: string;
}) {
  return (
    <motion.section
      id={id}
      initial={{ opacity: 0, y: 30 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, amount: 0.2 }}
      transition={{ type: "spring", stiffness: 100, damping: 15 }}
      className="p-6 bg-card border border-border rounded-xl"
    >
      <h2 className="text-xl font-bold text-foreground mb-4">{title}</h2>
      {children}
    </motion.section>
  );
}

// Scroll Progress Bar
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

// Debug Panel
function DebugPanel() {
  const shouldReduceMotion = useReducedMotion();
  const [renderCount, setRenderCount] = useState(0);

  return (
    <div className="fixed bottom-4 right-4 p-4 bg-card/95 backdrop-blur border border-border rounded-lg shadow-lg max-w-xs z-40">
      <h3 className="font-bold text-sm text-foreground mb-2">Debug Info</h3>
      <div className="space-y-1 text-xs text-muted-foreground">
        <div>Reduced Motion: {shouldReduceMotion ? "Yes" : "No"}</div>
        <div>Render Count: {renderCount}</div>
        <button
          onClick={() => setRenderCount((c) => c + 1)}
          className="mt-2 px-2 py-1 bg-muted rounded text-foreground hover:bg-accent transition-colors"
        >
          Force Re-render
        </button>
      </div>
    </div>
  );
}

// Button Variants Test
function ButtonVariantsTest() {
  const [activePreset, setActivePreset] = useState<SpringPreset>("snappy");
  const spring = springPresets[activePreset];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        {(Object.keys(springPresets) as SpringPreset[]).map((preset) => (
          <button
            key={preset}
            onClick={() => setActivePreset(preset)}
            className={`px-3 py-1 rounded text-sm transition-colors ${
              activePreset === preset
                ? "bg-primary text-primary-foreground"
                : "bg-muted text-foreground hover:bg-accent"
            }`}
          >
            {preset}
          </button>
        ))}
      </div>

      <div className="p-4 bg-muted/50 rounded-lg">
        <p className="text-xs text-muted-foreground mb-2">
          Stiffness: {spring.stiffness}, Damping: {spring.damping}
          {"mass" in spring ? `, Mass: ${spring.mass}` : ""}
        </p>
        <motion.button
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          transition={{ type: "spring", ...spring }}
          className="px-6 py-3 bg-primary text-primary-foreground rounded-lg font-medium"
        >
          Test Button ({activePreset})
        </motion.button>
      </div>
    </div>
  );
}

// Stagger Test
function StaggerTest() {
  const [key, setKey] = useState(0);
  const [staggerDelay, setStaggerDelay] = useState(0.1);
  const id = useId();

  const containerVariants = {
    hidden: { opacity: 0 },
    visible: {
      opacity: 1,
      transition: {
        staggerChildren: staggerDelay,
        delayChildren: 0.2
      }
    }
  };

  const itemVariants = {
    hidden: { opacity: 0, y: 20 },
    visible: {
      opacity: 1,
      y: 0,
      transition: { type: "spring", stiffness: 300, damping: 24 }
    }
  };

  const items = ["First Item", "Second Item", "Third Item", "Fourth Item", "Fifth Item"];

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-4">
        <label className="text-sm text-muted-foreground">
          Stagger Delay: {staggerDelay}s
        </label>
        <input
          type="range"
          min="0.02"
          max="0.3"
          step="0.02"
          value={staggerDelay}
          onChange={(e) => setStaggerDelay(parseFloat(e.target.value))}
          className="w-32"
        />
        <button
          onClick={() => setKey((k) => k + 1)}
          className="px-3 py-1 bg-muted rounded text-sm hover:bg-accent transition-colors"
        >
          Replay
        </button>
      </div>

      <motion.div
        key={key}
        variants={containerVariants}
        initial="hidden"
        animate="visible"
        className="space-y-2"
      >
        {items.map((item, index) => (
          <motion.div
            key={`${id}-${item}`}
            variants={itemVariants}
            className="p-3 bg-muted rounded-lg text-foreground"
          >
            {item}
          </motion.div>
        ))}
      </motion.div>
    </div>
  );
}

// Reveal Test
function RevealTest() {
  const directions = ["up", "down", "left", "right"] as const;

  return (
    <div className="grid grid-cols-2 gap-4">
      {directions.map((direction) => (
        <motion.div
          key={direction}
          initial={{
            opacity: 0,
            y: direction === "up" ? 50 : direction === "down" ? -50 : 0,
            x: direction === "left" ? 50 : direction === "right" ? -50 : 0
          }}
          whileInView={{ opacity: 1, y: 0, x: 0 }}
          viewport={{ once: true, amount: 0.5 }}
          transition={{ type: "spring", stiffness: 100, damping: 15 }}
          className="p-4 bg-muted rounded-lg text-center"
        >
          <span className="text-sm text-muted-foreground">Reveal from</span>
          <div className="font-bold text-foreground capitalize">{direction}</div>
        </motion.div>
      ))}
    </div>
  );
}

// Presence Test (Enter/Exit)
function PresenceTest() {
  const [items, setItems] = useState([1, 2, 3]);
  const [nextId, setNextId] = useState(4);
  const id = useId();

  const addItem = () => {
    setItems([...items, nextId]);
    setNextId(nextId + 1);
  };

  const removeItem = (itemId: number) => {
    setItems(items.filter((i) => i !== itemId));
  };

  return (
    <div className="space-y-4">
      <button
        onClick={addItem}
        className="px-4 py-2 bg-primary text-primary-foreground rounded-lg hover:bg-primary/90 transition-colors"
      >
        Add Item
      </button>

      <div className="space-y-2">
        <AnimatePresence mode="popLayout">
          {items.map((item) => (
            <motion.div
              key={`${id}-${item}`}
              layout
              initial={{ opacity: 0, scale: 0.8, y: -20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.8, y: 20 }}
              transition={{ type: "spring", stiffness: 500, damping: 30 }}
              className="flex items-center justify-between p-3 bg-muted rounded-lg"
            >
              <span className="text-foreground">Item {item}</span>
              <button
                onClick={() => removeItem(item)}
                className="px-2 py-1 text-xs bg-destructive/10 text-destructive rounded hover:bg-destructive/20 transition-colors"
              >
                Remove
              </button>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
    </div>
  );
}

// Layout Animation Test (Tabs)
function LayoutTest() {
  const tabs = ["Overview", "Features", "Pricing", "Contact"];
  const [activeTab, setActiveTab] = useState(tabs[0]);

  return (
    <div className="space-y-4">
      <LayoutGroup id="tabs-test">
        <div className="flex gap-1 p-1 bg-muted rounded-lg">
          {tabs.map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className="relative px-4 py-2 text-sm font-medium rounded-md transition-colors"
            >
              {activeTab === tab && (
                <motion.div
                  layoutId="active-tab-bg"
                  className="absolute inset-0 bg-background rounded-md shadow-sm"
                  transition={{ type: "spring", stiffness: 500, damping: 30 }}
                />
              )}
              <span
                className={`relative z-10 ${
                  activeTab === tab ? "text-foreground" : "text-muted-foreground"
                }`}
              >
                {tab}
              </span>
            </button>
          ))}
        </div>
      </LayoutGroup>

      <AnimatePresence mode="wait">
        <motion.div
          key={activeTab}
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -10 }}
          transition={{ duration: 0.2 }}
          className="p-4 bg-muted/50 rounded-lg"
        >
          <p className="text-muted-foreground">Content for {activeTab} tab</p>
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

// Toggle Switch Test
function ToggleTest() {
  const [isOn, setIsOn] = useState(false);

  return (
    <div className="flex items-center gap-4">
      <span className="text-sm text-muted-foreground">Toggle Switch:</span>
      <motion.div
        onClick={() => setIsOn(!isOn)}
        className={`w-14 h-8 flex items-center rounded-full p-1 cursor-pointer transition-colors ${
          isOn ? "bg-primary justify-end" : "bg-muted justify-start"
        }`}
      >
        <motion.div
          layout
          className="w-6 h-6 bg-background rounded-full shadow-md"
          transition={{ type: "spring", stiffness: 700, damping: 30 }}
        />
      </motion.div>
      <span className="text-sm text-foreground">{isOn ? "On" : "Off"}</span>
    </div>
  );
}

// Gesture Test
function GestureTest() {
  return (
    <div className="flex flex-wrap gap-4">
      <motion.div
        whileHover={{ scale: 1.1, rotate: 5 }}
        whileTap={{ scale: 0.9 }}
        className="w-24 h-24 bg-gradient-to-br from-primary to-primary/50 rounded-xl flex items-center justify-center cursor-pointer"
      >
        <span className="text-primary-foreground text-xs font-medium">Hover/Tap</span>
      </motion.div>

      <motion.div
        drag
        dragConstraints={{ left: 0, right: 0, top: 0, bottom: 0 }}
        dragElastic={0.2}
        whileDrag={{ scale: 1.1, cursor: "grabbing" }}
        className="w-24 h-24 bg-gradient-to-br from-accent to-accent/50 rounded-xl flex items-center justify-center cursor-grab"
      >
        <span className="text-accent-foreground text-xs font-medium">Drag Me</span>
      </motion.div>

      <motion.div
        whileHover={{ y: -8, boxShadow: "0 20px 40px rgba(0,0,0,0.15)" }}
        transition={{ type: "spring", stiffness: 400, damping: 17 }}
        className="w-24 h-24 bg-card border border-border rounded-xl flex items-center justify-center cursor-pointer shadow-md"
      >
        <span className="text-foreground text-xs font-medium">Lift</span>
      </motion.div>
    </div>
  );
}

// Main Test Editor
export function MotionTestEditor() {
  return (
    <>
      <ScrollProgress />
      <DebugPanel />

      <div className="max-w-4xl mx-auto p-6 space-y-8">
        <header className="text-center py-8">
          <motion.h1
            initial={{ opacity: 0, y: -20 }}
            animate={{ opacity: 1, y: 0 }}
            className="text-4xl font-bold text-foreground mb-2"
          >
            Motion Test Page
          </motion.h1>
          <motion.p
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.2 }}
            className="text-muted-foreground"
          >
            Interactive playground for testing all animation patterns
          </motion.p>
        </header>

        <nav className="flex flex-wrap gap-2 justify-center">
          {[
            "buttons",
            "stagger",
            "reveal",
            "presence",
            "layout",
            "toggle",
            "gestures"
          ].map((section) => (
            <a
              key={section}
              href={`#${section}`}
              className="px-3 py-1 bg-muted rounded-full text-sm text-muted-foreground hover:bg-accent hover:text-foreground transition-colors capitalize"
            >
              {section}
            </a>
          ))}
        </nav>

        <Section id="buttons" title="1. Button Spring Variants">
          <ButtonVariantsTest />
        </Section>

        <Section id="stagger" title="2. Stagger Animation">
          <StaggerTest />
        </Section>

        <Section id="reveal" title="3. Scroll Reveal">
          <RevealTest />
        </Section>

        <Section id="presence" title="4. AnimatePresence (Enter/Exit)">
          <PresenceTest />
        </Section>

        <Section id="layout" title="5. Layout Animation (Tabs)">
          <LayoutTest />
        </Section>

        <Section id="toggle" title="6. Toggle Switch">
          <ToggleTest />
        </Section>

        <Section id="gestures" title="7. Gesture Interactions">
          <GestureTest />
        </Section>

        <div className="h-32" /> {/* Spacer for scroll testing */}
      </div>
    </>
  );
}
```

## Features Included

- **Scroll Progress Bar**: Fixed progress indicator showing scroll position
- **Debug Panel**: Shows reduced motion preference and render count
- **Button Variants**: Interactive spring preset selector with live preview
- **Stagger Animation**: Adjustable delay with replay functionality
- **Scroll Reveal**: Four direction variants (up, down, left, right)
- **AnimatePresence**: Add/remove items with enter/exit animations
- **Layout Animation**: Tab switching with shared element transition
- **Toggle Switch**: Spring-based layout animation
- **Gesture Interactions**: Hover, tap, drag, and lift effects

## Usage Instructions

1. **Install Motion**: `bun add motion`
2. **Create the test page** at `app/motion-test/page.tsx`
3. **Create the editor component** at `components/motion/motion-test-editor.tsx`
4. **Navigate to** `/motion-test` in your browser
5. **Test each section**:
   - Click through button presets to feel different spring physics
   - Adjust stagger delay slider and click Replay
   - Scroll to see reveal animations trigger
   - Add/remove items to test enter/exit
   - Click tabs to see layout transitions
   - Toggle the switch
   - Hover, tap, and drag the gesture boxes

## Testing Checklist

### Core Functionality
- [ ] Page loads without hydration errors
- [ ] Scroll progress bar updates smoothly
- [ ] Debug panel shows correct reduced motion status

### Button Animations
- [ ] All spring presets feel distinct
- [ ] Hover scale animation triggers
- [ ] Tap/press scale animation triggers
- [ ] Spring physics feels natural (no jank)

### Stagger Animation
- [ ] Items animate in sequence
- [ ] Changing delay slider affects timing
- [ ] Replay button resets and replays animation

### Scroll Reveal
- [ ] Elements reveal when scrolling into view
- [ ] Each direction variant works correctly
- [ ] `once: true` prevents re-triggering

### AnimatePresence
- [ ] New items animate in with scale/opacity
- [ ] Removed items animate out before unmounting
- [ ] Layout shifts smoothly when items removed

### Layout Animation
- [ ] Tab indicator slides between tabs
- [ ] Tab content cross-fades
- [ ] No layout jump on tab change

### Toggle Switch
- [ ] Toggle animates smoothly between states
- [ ] Spring physics feels satisfying

### Gestures
- [ ] Hover effects trigger on mouse enter
- [ ] Tap effects trigger on click
- [ ] Drag element returns to origin
- [ ] Lift card rises with shadow

### Performance
- [ ] No jank at 60fps
- [ ] No unnecessary re-renders (check debug panel)
- [ ] Animations complete without stuttering

### Accessibility
- [ ] Reduced motion preference is detected
- [ ] Page is navigable with keyboard
- [ ] No vestibular motion triggers

## Troubleshooting

### Animations not playing
- Check browser console for errors
- Verify `"use client"` directive is present
- Ensure Motion is installed: `bun add motion`

### Hydration errors
- Don't use `window` or `document` in initial values
- Ensure server and client render the same initial state

### Stutter or jank
- Check if too many elements are animating simultaneously
- Reduce stagger delay for large lists
- Use `will-change: transform` sparingly

### Exit animations not working
- Ensure `AnimatePresence` wraps the conditional
- Check that keys are unique (not array index)
- Verify `exit` prop is defined on motion component

### Layout animation distortion
- Add `layout` prop to child elements
- Use inline `style` for borderRadius
- Avoid `display: inline` elements
