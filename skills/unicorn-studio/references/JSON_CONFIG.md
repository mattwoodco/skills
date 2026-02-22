# Unicorn Studio JSON Configuration

Reference for self-hosted shader JSON configuration and best practices.

## Single JSON Configuration Pattern

All Unicorn Studio scenes can be exported as a single JSON file for self-hosting (Legend subscribers). This provides complete control over caching, versioning, and offline capabilities.

## JSON Schema Reference

```typescript
// types/unicorn-scene.ts
export type UnicornSceneJSON = {
  // Metadata
  version: string;                    // SDK version (e.g., "2.0.1")
  name: string;                       // Scene name
  id: string;                         // Unique scene identifier

  // Canvas dimensions
  width: number;                      // Base width in pixels
  height: number;                     // Base height in pixels

  // Rendering settings
  fps: number;                        // Target frames per second (0-120)
  backgroundColor?: string;           // Hex color (e.g., "#000000")
  backgroundOpacity?: number;         // 0-1

  // Layers (rendered bottom to top)
  layers: UnicornLayer[];

  // Global effects applied to entire scene
  effects?: UnicornEffect[];

  // Mouse/touch interaction settings
  interactivity?: {
    mouse?: {
      enabled: boolean;
      strength?: number;              // 0-1, effect intensity
      radius?: number;                // Interaction radius
      disableMobile?: boolean;        // Disable on touch devices
    };
    scroll?: {
      enabled: boolean;
      direction?: "vertical" | "horizontal";
      speed?: number;
    };
  };

  // Asset references
  assets?: {
    images?: UnicornAsset[];
    fonts?: UnicornAsset[];
  };
};

export type UnicornLayer = {
  id: string;
  type: LayerType;
  name?: string;
  visible: boolean;
  opacity: number;                    // 0-1
  blendMode?: BlendMode;

  // Position and transform
  position?: { x: number; y: number };
  scale?: { x: number; y: number };
  rotation?: number;                  // Degrees
  anchor?: { x: number; y: number };  // 0-1

  // Layer-specific properties
  properties: LayerProperties;

  // Per-layer effects
  effects?: UnicornEffect[];

  // Animation
  animation?: LayerAnimation;
};

export type LayerType =
  | "gradient"
  | "solid"
  | "image"
  | "shape"
  | "text"
  | "noise"
  | "particles"
  | "3d";

export type BlendMode =
  | "normal"
  | "multiply"
  | "screen"
  | "overlay"
  | "darken"
  | "lighten"
  | "color-dodge"
  | "color-burn"
  | "hard-light"
  | "soft-light"
  | "difference"
  | "exclusion";

export type UnicornEffect = {
  type: EffectType;
  enabled: boolean;
  properties: EffectProperties;
};

export type EffectType =
  | "blur"
  | "noise"
  | "bloom"
  | "glow"
  | "distortion"
  | "chromatic"
  | "vignette"
  | "grain"
  | "pixelate"
  | "wave"
  | "ripple";

export type UnicornAsset = {
  id: string;
  name: string;
  url: string;                        // Relative or absolute URL
  type: "image" | "font";
};
```

## Example Scene Configurations

### 1. Animated Gradient Background

```json
{
  "version": "2.0.1",
  "name": "Hero Gradient",
  "id": "hero-gradient-001",
  "width": 1920,
  "height": 1080,
  "fps": 60,
  "backgroundColor": "#000000",
  "layers": [
    {
      "id": "gradient-base",
      "type": "gradient",
      "name": "Base Gradient",
      "visible": true,
      "opacity": 1,
      "properties": {
        "type": "linear",
        "angle": 45,
        "colors": [
          { "color": "#667eea", "position": 0 },
          { "color": "#764ba2", "position": 0.5 },
          { "color": "#f093fb", "position": 1 }
        ],
        "animated": true,
        "animationSpeed": 0.5,
        "animationType": "shift"
      }
    }
  ],
  "effects": [
    {
      "type": "noise",
      "enabled": true,
      "properties": {
        "intensity": 0.05,
        "scale": 1.5,
        "animated": true,
        "speed": 0.2
      }
    }
  ],
  "interactivity": {
    "mouse": {
      "enabled": true,
      "strength": 0.3,
      "radius": 200,
      "disableMobile": false
    }
  }
}
```

### 2. Particle System

```json
{
  "version": "2.0.1",
  "name": "Floating Particles",
  "id": "particles-001",
  "width": 1920,
  "height": 1080,
  "fps": 60,
  "backgroundColor": "#0a0a0a",
  "layers": [
    {
      "id": "particles-layer",
      "type": "particles",
      "name": "Main Particles",
      "visible": true,
      "opacity": 0.8,
      "properties": {
        "count": 100,
        "size": { "min": 2, "max": 8 },
        "color": "#ffffff",
        "colorVariation": 0.2,
        "speed": { "min": 0.5, "max": 2 },
        "direction": "up",
        "spread": 45,
        "life": { "min": 3, "max": 8 },
        "fadeIn": true,
        "fadeOut": true,
        "turbulence": 0.3,
        "attractToMouse": true,
        "attractStrength": 0.5
      }
    },
    {
      "id": "glow-layer",
      "type": "particles",
      "name": "Glow Particles",
      "visible": true,
      "opacity": 0.4,
      "blendMode": "screen",
      "properties": {
        "count": 30,
        "size": { "min": 20, "max": 50 },
        "color": "#667eea",
        "speed": { "min": 0.2, "max": 0.5 },
        "blur": 20
      }
    }
  ],
  "interactivity": {
    "mouse": {
      "enabled": true,
      "strength": 0.8,
      "radius": 150
    }
  }
}
```

### 3. Noise Pattern

```json
{
  "version": "2.0.1",
  "name": "Organic Noise",
  "id": "noise-001",
  "width": 1920,
  "height": 1080,
  "fps": 30,
  "backgroundColor": "#1a1a2e",
  "layers": [
    {
      "id": "noise-base",
      "type": "noise",
      "name": "Perlin Noise",
      "visible": true,
      "opacity": 1,
      "properties": {
        "noiseType": "perlin",
        "scale": 3,
        "octaves": 4,
        "persistence": 0.5,
        "lacunarity": 2,
        "colorA": "#16213e",
        "colorB": "#0f3460",
        "animated": true,
        "speed": 0.3,
        "direction": { "x": 1, "y": 0.5 }
      }
    },
    {
      "id": "color-overlay",
      "type": "gradient",
      "name": "Color Overlay",
      "visible": true,
      "opacity": 0.5,
      "blendMode": "overlay",
      "properties": {
        "type": "radial",
        "colors": [
          { "color": "#e94560", "position": 0 },
          { "color": "transparent", "position": 1 }
        ],
        "center": { "x": 0.3, "y": 0.3 },
        "radius": 0.8
      }
    }
  ],
  "effects": [
    {
      "type": "grain",
      "enabled": true,
      "properties": {
        "intensity": 0.1,
        "animated": true
      }
    }
  ]
}
```

### 4. Interactive Blob

```json
{
  "version": "2.0.1",
  "name": "Morphing Blob",
  "id": "blob-001",
  "width": 800,
  "height": 800,
  "fps": 60,
  "backgroundColor": "transparent",
  "backgroundOpacity": 0,
  "layers": [
    {
      "id": "blob-main",
      "type": "shape",
      "name": "Main Blob",
      "visible": true,
      "opacity": 1,
      "position": { "x": 0.5, "y": 0.5 },
      "properties": {
        "shapeType": "blob",
        "points": 8,
        "radius": 200,
        "randomness": 0.4,
        "fill": {
          "type": "gradient",
          "colors": [
            { "color": "#667eea", "position": 0 },
            { "color": "#764ba2", "position": 1 }
          ],
          "angle": 135
        },
        "stroke": {
          "color": "#ffffff",
          "width": 2,
          "opacity": 0.3
        },
        "morphSpeed": 0.5,
        "morphIntensity": 0.3
      },
      "animation": {
        "rotation": {
          "enabled": true,
          "speed": 10,
          "direction": "clockwise"
        },
        "scale": {
          "enabled": true,
          "min": 0.95,
          "max": 1.05,
          "speed": 2
        }
      }
    }
  ],
  "interactivity": {
    "mouse": {
      "enabled": true,
      "strength": 0.6,
      "radius": 100
    }
  }
}
```

## File Organization

```
public/
  shaders/
    scenes/
      hero-gradient.json
      particles-background.json
      noise-pattern.json
      blob-interactive.json
    assets/
      images/
        texture-1.png
        pattern-overlay.jpg
      fonts/
        custom-font.woff2
```

## Loading Self-Hosted JSON

### With unicornstudio-react

```tsx
"use client";

import UnicornScene from "unicornstudio-react/next";

export function SelfHostedScene() {
  return (
    <UnicornScene
      jsonFilePath="/shaders/scenes/hero-gradient.json"
      width="100%"
      height="100%"
      scale={1}
      dpi={1.5}
      fps={60}
      lazyLoad={true}
    />
  );
}
```

### With SDK Directly

```tsx
"use client";

import { useEffect, useRef } from "react";

declare global {
  interface Window {
    UnicornStudio: {
      addScene: (config: {
        elementId: string;
        filePath: string;
        scale?: number;
        dpi?: number;
        fps?: number;
        lazyLoad?: boolean;
      }) => Promise<{ destroy: () => void; paused: boolean }>;
      destroy: () => void;
    };
  }
}

export function DirectSDKScene({ jsonPath }: { jsonPath: string }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<{ destroy: () => void } | null>(null);

  useEffect(() => {
    // Load SDK script
    const script = document.createElement("script");
    script.src =
      "https://cdn.jsdelivr.net/gh/hiunicornstudio/unicornstudio.js@v2.0.1/dist/unicornStudio.umd.js";
    script.async = true;

    script.onload = async () => {
      if (containerRef.current && window.UnicornStudio) {
        try {
          const scene = await window.UnicornStudio.addScene({
            elementId: containerRef.current.id,
            filePath: jsonPath,
            scale: 1,
            dpi: 1.5,
            fps: 60,
            lazyLoad: true,
          });
          sceneRef.current = scene;
        } catch (err) {
          console.error("Failed to load scene:", err);
        }
      }
    };

    document.head.appendChild(script);

    return () => {
      // Cleanup
      sceneRef.current?.destroy();
      script.remove();
    };
  }, [jsonPath]);

  return (
    <div
      ref={containerRef}
      id="unicorn-scene"
      className="h-full w-full"
    />
  );
}
```

## Caching Strategy

### Next.js Cache Headers

```typescript
// next.config.ts
const nextConfig = {
  async headers() {
    return [
      {
        // Cache shader JSON files aggressively
        source: "/shaders/:path*.json",
        headers: [
          {
            key: "Cache-Control",
            value: "public, max-age=31536000, immutable",
          },
        ],
      },
      {
        // Cache shader assets
        source: "/shaders/assets/:path*",
        headers: [
          {
            key: "Cache-Control",
            value: "public, max-age=31536000, immutable",
          },
        ],
      },
    ];
  },
};

export default nextConfig;
```

### Versioning Pattern

```tsx
// Use version in filename for cache busting
const SHADER_SCENES = {
  hero: "/shaders/scenes/hero-gradient-v1.2.json",
  particles: "/shaders/scenes/particles-v2.0.json",
} as const;

export function VersionedScene({ scene }: { scene: keyof typeof SHADER_SCENES }) {
  return (
    <UnicornScene
      jsonFilePath={SHADER_SCENES[scene]}
      width="100%"
      height="100%"
    />
  );
}
```

## Validation

### JSON Schema Validation

```typescript
// lib/validate-shader.ts
import { z } from "zod";

const LayerSchema = z.object({
  id: z.string(),
  type: z.enum(["gradient", "solid", "image", "shape", "text", "noise", "particles", "3d"]),
  visible: z.boolean(),
  opacity: z.number().min(0).max(1),
  properties: z.record(z.unknown()),
});

const UnicornSceneSchema = z.object({
  version: z.string(),
  name: z.string(),
  id: z.string(),
  width: z.number().positive(),
  height: z.number().positive(),
  fps: z.number().min(0).max(120),
  layers: z.array(LayerSchema),
  effects: z.array(z.unknown()).optional(),
  interactivity: z.object({
    mouse: z.object({
      enabled: z.boolean(),
      strength: z.number().optional(),
      radius: z.number().optional(),
      disableMobile: z.boolean().optional(),
    }).optional(),
  }).optional(),
});

export function validateShaderJSON(json: unknown) {
  return UnicornSceneSchema.safeParse(json);
}
```

## Best Practices

1. **Version your JSON files** - Include version in filename for cache busting
2. **Optimize layer count** - Each layer requires additional shader passes
3. **Use appropriate FPS** - 30fps for subtle effects, 60fps for smooth animations
4. **Minimize asset sizes** - Compress images, use WebP when possible
5. **Test on target devices** - Performance varies significantly across hardware
6. **Enable lazy loading** - Only load scenes when visible
7. **Provide fallbacks** - Handle JSON load failures gracefully
