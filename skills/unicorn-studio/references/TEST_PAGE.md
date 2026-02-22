# Unicorn Studio Test/Debug Page

A complete test page for verifying Unicorn Studio shader integration with configurable performance settings, multiple scene demos, and debug controls.

## Complete Test Page

### 1. Page Component

Create `app/shader-test/page.tsx`:

```tsx
import { ShaderTestClient } from "./shader-test-client";

export const metadata = {
  title: "Shader Test",
  description: "Unicorn Studio WebGL shader test and debug page",
};

export default function ShaderTestPage() {
  return (
    <div className="flex min-h-screen flex-col bg-background">
      <header className="border-b border-border bg-card px-4 py-3">
        <h1 className="text-xl font-semibold text-foreground">
          Unicorn Studio Shader Test
        </h1>
      </header>
      <main className="flex-1">
        <ShaderTestClient />
      </main>
    </div>
  );
}
```

### 2. Client Component with Debug Panel

Create `app/shader-test/shader-test-client.tsx`:

```tsx
"use client";

import { useState, useEffect, useCallback, useId } from "react";
import dynamic from "next/dynamic";

// Dynamic import for SSR safety
const UnicornScene = dynamic(
  () => import("unicornstudio-react/next").then((mod) => mod.default),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-full w-full items-center justify-center bg-muted">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
      </div>
    ),
  }
);

// Demo project IDs - replace with your own
const DEMO_SCENES = [
  {
    id: "demo-1",
    name: "Gradient Flow",
    projectId: "YOUR_PROJECT_ID_1", // Replace with actual ID
    description: "Animated gradient with mouse interaction",
  },
  {
    id: "demo-2",
    name: "Particle System",
    projectId: "YOUR_PROJECT_ID_2", // Replace with actual ID
    description: "Interactive particle effects",
  },
  {
    id: "demo-3",
    name: "Noise Pattern",
    projectId: "YOUR_PROJECT_ID_3", // Replace with actual ID
    description: "Procedural noise animation",
  },
];

type ValidFPS = 15 | 24 | 30 | 60 | 120;

type PerformanceConfig = {
  scale: number;
  dpi: number;
  fps: ValidFPS;
  lazyLoad: boolean;
  production: boolean;
};

type PerformanceMetrics = {
  loadTime: number | null;
  isLoaded: boolean;
  hasError: boolean;
  errorMessage: string | null;
};

export function ShaderTestClient() {
  const sceneId = useId();
  const [selectedScene, setSelectedScene] = useState(DEMO_SCENES[0]);
  const [showDebugPanel, setShowDebugPanel] = useState(true);
  const [showScene, setShowScene] = useState(true);
  const [isPaused, setIsPaused] = useState(false);

  // Performance configuration
  const [config, setConfig] = useState<PerformanceConfig>({
    scale: 1,
    dpi: 1.5,
    fps: 60,
    lazyLoad: true,
    production: true,
  });

  // Performance metrics
  const [metrics, setMetrics] = useState<PerformanceMetrics>({
    loadTime: null,
    isLoaded: false,
    hasError: false,
    errorMessage: null,
  });

  const [loadStartTime, setLoadStartTime] = useState<number | null>(null);

  // Device info
  const [deviceInfo, setDeviceInfo] = useState({
    isMobile: false,
    reducedMotion: false,
    hardwareConcurrency: 0,
    webglSupported: false,
    webgl2Supported: false,
  });

  useEffect(() => {
    // Detect device capabilities
    const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
    const reducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    ).matches;
    const hardwareConcurrency = navigator.hardwareConcurrency || 0;

    // Check WebGL support
    const canvas = document.createElement("canvas");
    const webglSupported = !!(
      canvas.getContext("webgl") || canvas.getContext("experimental-webgl")
    );
    const webgl2Supported = !!canvas.getContext("webgl2");

    setDeviceInfo({
      isMobile,
      reducedMotion,
      hardwareConcurrency,
      webglSupported,
      webgl2Supported,
    });

    // Auto-adjust config for mobile
    if (isMobile) {
      setConfig((prev) => ({
        ...prev,
        scale: 0.5,
        dpi: 1,
        fps: 30 as ValidFPS,
      }));
    }
  }, []);

  const handleSceneLoad = useCallback(() => {
    const endTime = performance.now();
    const loadTime = loadStartTime ? endTime - loadStartTime : null;

    setMetrics({
      loadTime,
      isLoaded: true,
      hasError: false,
      errorMessage: null,
    });
  }, [loadStartTime]);

  const handleSceneError = useCallback((error: Error) => {
    setMetrics({
      loadTime: null,
      isLoaded: false,
      hasError: true,
      errorMessage: error.message,
    });
  }, []);

  const handleSceneChange = useCallback((scene: typeof DEMO_SCENES[0]) => {
    setLoadStartTime(performance.now());
    setMetrics({
      loadTime: null,
      isLoaded: false,
      hasError: false,
      errorMessage: null,
    });
    setSelectedScene(scene);
  }, []);

  const handleConfigChange = useCallback(
    (key: keyof PerformanceConfig, value: number | boolean) => {
      setConfig((prev) => ({ ...prev, [key]: value }));
      // Reset metrics when config changes
      setLoadStartTime(performance.now());
      setMetrics({
        loadTime: null,
        isLoaded: false,
        hasError: false,
        errorMessage: null,
      });
    },
    []
  );

  const applyPreset = useCallback((preset: "low" | "medium" | "high") => {
    const presets = {
      low: { scale: 0.5, dpi: 1, fps: 30 as ValidFPS, lazyLoad: true, production: true },
      medium: { scale: 0.75, dpi: 1.5, fps: 60 as ValidFPS, lazyLoad: true, production: true },
      high: { scale: 1, dpi: 2, fps: 60 as ValidFPS, lazyLoad: false, production: true },
    };
    setConfig(presets[preset]);
    setLoadStartTime(performance.now());
  }, []);

  return (
    <div className="flex h-[calc(100vh-57px)]">
      {/* Main Scene Area */}
      <div className="relative flex-1">
        {showScene && selectedScene.projectId !== "YOUR_PROJECT_ID_1" ? (
          <UnicornScene
            key={`${sceneId}-${selectedScene.id}-${JSON.stringify(config)}-${isPaused}`}
            projectId={selectedScene.projectId}
            width="100%"
            height="100%"
            scale={config.scale}
            dpi={config.dpi}
            fps={config.fps}
            lazyLoad={config.lazyLoad}
            production={config.production}
            altText={selectedScene.description}
            ariaLabel={`${selectedScene.name} shader effect`}
            onLoad={handleSceneLoad}
            onError={handleSceneError}
          />
        ) : (
          <div className="flex h-full w-full flex-col items-center justify-center bg-gradient-to-br from-primary/20 via-muted to-primary/10">
            <div className="text-center">
              <div className="mb-4 text-6xl">🦄</div>
              <h2 className="text-2xl font-bold text-foreground">
                Unicorn Studio Demo
              </h2>
              <p className="mt-2 text-muted-foreground">
                Replace projectId with your Unicorn Studio embed ID
              </p>
              <p className="mt-4 text-sm text-muted-foreground">
                Get your embed ID from{" "}
                <a
                  href="https://www.unicorn.studio"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-primary underline"
                >
                  unicorn.studio
                </a>
              </p>
            </div>
          </div>
        )}

        {/* Overlay Controls */}
        <div className="absolute left-4 top-4 flex gap-2">
          <button
            onClick={() => setShowScene(!showScene)}
            className="rounded-lg bg-background/80 px-3 py-2 text-sm font-medium backdrop-blur-sm hover:bg-background"
          >
            {showScene ? "Hide Scene" : "Show Scene"}
          </button>
          <button
            onClick={() => setIsPaused(!isPaused)}
            className="rounded-lg bg-background/80 px-3 py-2 text-sm font-medium backdrop-blur-sm hover:bg-background"
          >
            {isPaused ? "▶ Resume" : "⏸ Pause"}
          </button>
        </div>

        {/* Status Badge */}
        <div className="absolute right-4 top-4">
          <div
            className={`rounded-full px-3 py-1 text-xs font-medium ${
              metrics.hasError
                ? "bg-red-500/80 text-white"
                : metrics.isLoaded
                  ? "bg-green-500/80 text-white"
                  : "bg-yellow-500/80 text-black"
            }`}
          >
            {metrics.hasError
              ? "Error"
              : metrics.isLoaded
                ? "Loaded"
                : "Loading..."}
          </div>
        </div>
      </div>

      {/* Debug Panel */}
      {showDebugPanel && (
        <div className="w-80 overflow-y-auto border-l border-border bg-card p-4">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-lg font-semibold text-foreground">
              Debug Panel
            </h2>
            <button
              onClick={() => setShowDebugPanel(false)}
              className="text-muted-foreground hover:text-foreground"
            >
              ✕
            </button>
          </div>

          {/* Scene Selector */}
          <section className="mb-6">
            <h3 className="mb-2 text-sm font-medium text-foreground">
              Scene Selection
            </h3>
            <div className="space-y-2">
              {DEMO_SCENES.map((scene) => (
                <button
                  key={scene.id}
                  onClick={() => handleSceneChange(scene)}
                  className={`w-full rounded-lg border p-3 text-left transition-colors ${
                    selectedScene.id === scene.id
                      ? "border-primary bg-primary/10"
                      : "border-border hover:border-primary/50"
                  }`}
                >
                  <div className="font-medium text-foreground">{scene.name}</div>
                  <div className="text-xs text-muted-foreground">
                    {scene.description}
                  </div>
                </button>
              ))}
            </div>
          </section>

          {/* Performance Presets */}
          <section className="mb-6">
            <h3 className="mb-2 text-sm font-medium text-foreground">
              Performance Presets
            </h3>
            <div className="grid grid-cols-3 gap-2">
              <button
                onClick={() => applyPreset("low")}
                className="rounded border border-border px-2 py-1 text-xs hover:bg-muted"
              >
                Low
              </button>
              <button
                onClick={() => applyPreset("medium")}
                className="rounded border border-border px-2 py-1 text-xs hover:bg-muted"
              >
                Medium
              </button>
              <button
                onClick={() => applyPreset("high")}
                className="rounded border border-border px-2 py-1 text-xs hover:bg-muted"
              >
                High
              </button>
            </div>
          </section>

          {/* Performance Settings */}
          <section className="mb-6">
            <h3 className="mb-2 text-sm font-medium text-foreground">
              Performance Settings
            </h3>
            <div className="space-y-4">
              {/* Scale */}
              <div>
                <label className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">Scale</span>
                  <span className="font-mono">{config.scale}</span>
                </label>
                <input
                  type="range"
                  min="0.25"
                  max="1"
                  step="0.05"
                  value={config.scale}
                  onChange={(e) =>
                    handleConfigChange("scale", parseFloat(e.target.value))
                  }
                  className="w-full"
                />
              </div>

              {/* DPI */}
              <div>
                <label className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">DPI</span>
                  <span className="font-mono">{config.dpi}</span>
                </label>
                <input
                  type="range"
                  min="1"
                  max="2"
                  step="0.1"
                  value={config.dpi}
                  onChange={(e) =>
                    handleConfigChange("dpi", parseFloat(e.target.value))
                  }
                  className="w-full"
                />
              </div>

              {/* FPS */}
              <div>
                <label className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">FPS</span>
                </label>
                <select
                  value={config.fps}
                  onChange={(e) => handleConfigChange("fps", Number(e.target.value) as ValidFPS)}
                  className="w-full rounded border border-border bg-background p-2 text-sm"
                >
                  <option value={15}>15 FPS</option>
                  <option value={24}>24 FPS</option>
                  <option value={30}>30 FPS</option>
                  <option value={60}>60 FPS (Default)</option>
                  <option value={120}>120 FPS</option>
                </select>
              </div>

              {/* Toggles */}
              <div className="space-y-2">
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={config.lazyLoad}
                    onChange={(e) =>
                      handleConfigChange("lazyLoad", e.target.checked)
                    }
                    className="rounded"
                  />
                  <span className="text-sm text-muted-foreground">
                    Lazy Load
                  </span>
                </label>
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={config.production}
                    onChange={(e) =>
                      handleConfigChange("production", e.target.checked)
                    }
                    className="rounded"
                  />
                  <span className="text-sm text-muted-foreground">
                    Production Mode (CDN)
                  </span>
                </label>
              </div>
            </div>
          </section>

          {/* Metrics */}
          <section className="mb-6">
            <h3 className="mb-2 text-sm font-medium text-foreground">
              Load Metrics
            </h3>
            <div className="rounded-lg bg-muted p-3 font-mono text-xs">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Status:</span>
                <span
                  className={
                    metrics.hasError
                      ? "text-red-500"
                      : metrics.isLoaded
                        ? "text-green-500"
                        : "text-yellow-500"
                  }
                >
                  {metrics.hasError
                    ? "Error"
                    : metrics.isLoaded
                      ? "Loaded"
                      : "Loading"}
                </span>
              </div>
              {metrics.loadTime && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Load Time:</span>
                  <span>{metrics.loadTime.toFixed(0)}ms</span>
                </div>
              )}
              {metrics.errorMessage && (
                <div className="mt-2 text-red-400">{metrics.errorMessage}</div>
              )}
            </div>
          </section>

          {/* Device Info */}
          <section className="mb-6">
            <h3 className="mb-2 text-sm font-medium text-foreground">
              Device Capabilities
            </h3>
            <div className="rounded-lg bg-muted p-3 font-mono text-xs">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Mobile:</span>
                <span>{deviceInfo.isMobile ? "Yes" : "No"}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Reduced Motion:</span>
                <span>{deviceInfo.reducedMotion ? "Yes" : "No"}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">CPU Cores:</span>
                <span>{deviceInfo.hardwareConcurrency || "Unknown"}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">WebGL:</span>
                <span
                  className={
                    deviceInfo.webglSupported ? "text-green-500" : "text-red-500"
                  }
                >
                  {deviceInfo.webglSupported ? "Supported" : "Not Supported"}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">WebGL2:</span>
                <span
                  className={
                    deviceInfo.webgl2Supported
                      ? "text-green-500"
                      : "text-yellow-500"
                  }
                >
                  {deviceInfo.webgl2Supported ? "Supported" : "Not Supported"}
                </span>
              </div>
            </div>
          </section>

          {/* Current Config */}
          <section>
            <h3 className="mb-2 text-sm font-medium text-foreground">
              Current Config (JSON)
            </h3>
            <pre className="overflow-x-auto rounded-lg bg-muted p-3 text-xs">
              {JSON.stringify(
                {
                  projectId: selectedScene.projectId,
                  ...config,
                },
                null,
                2
              )}
            </pre>
          </section>
        </div>
      )}

      {/* Toggle Debug Panel Button (when hidden) */}
      {!showDebugPanel && (
        <button
          onClick={() => setShowDebugPanel(true)}
          className="absolute bottom-4 right-4 rounded-lg bg-card px-3 py-2 text-sm font-medium shadow-lg hover:bg-muted"
        >
          Show Debug
        </button>
      )}
    </div>
  );
}
```

## Usage

1. Install the package:

```bash
bun add unicornstudio-react
```

2. Create the test page files above

3. Navigate to `/shader-test`

4. Replace `YOUR_PROJECT_ID_X` with your actual Unicorn Studio embed IDs

## Features Demonstrated

- **Scene Selection**: Switch between multiple shader scenes
- **Performance Presets**: Quick low/medium/high quality toggles
- **Live Configuration**: Adjust scale, DPI, FPS in real-time
- **Load Metrics**: Track shader load time and status
- **Device Detection**: Auto-detect mobile, WebGL support, CPU cores
- **Pause/Resume**: Control animation playback (via key-based re-rendering)
- **Reduced Motion**: Respects user accessibility preferences
- **Error Handling**: Display load errors with messages
- **JSON Config Export**: View current configuration as JSON

## Known Limitations

### FPS Values
The `fps` prop only accepts: `15 | 24 | 30 | 60 | 120`. Use a dropdown select instead of a slider.

### Pause Functionality
The `paused` prop is not supported. Use key-based re-rendering or conditional component visibility to simulate pause.

## Common Test Scenarios

### 1. Performance Testing

- Toggle between presets and observe visual quality
- Monitor load times with different scale/DPI settings
- Test on mobile devices with reduced settings

### 2. Error Handling

- Test with invalid projectId
- Test with network offline
- Test on browsers without WebGL

### 3. Accessibility

- Enable reduced motion in OS settings
- Test screen reader announcements
- Verify keyboard navigation

### 4. Responsive Behavior

- Test at different viewport sizes
- Verify scene resizes correctly
- Test lazy loading with scroll
