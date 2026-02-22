---
name: react-three-fiber
description: Setup react-three-fiber (R3F) with drei for 3D graphics and WebGL scenes. Use this skill when the user says "setup 3d", "add three.js", "3d scene", "webgl", "react-three-fiber", or "r3f".
author: "@mattwoodco"
version: 1.0.1
created: 2026-01-12
updated: 2026-02-13
---

# React Three Fiber (R3F) with Drei for Next.js

## Installation

```bash
bun add three @react-three/fiber @react-three/drei leva
bun add -D @types/three
```

**Version Compatibility:**
- Next.js 15/16+ with React 19 requires `@react-three/fiber@9+` and `@react-three/drei@10+`
- Next.js 14 with React 18 uses `@react-three/fiber@8`

**Tested Versions (February 2026):**
- `three@0.182.0`
- `@react-three/fiber@9.5.0`
- `@react-three/drei@10.7.7`
- `leva@0.10.1` (optional, for debug controls)
- Next.js 16.1.6 with React 19.2.3

## Next.js App Router Setup

R3F uses WebGL which requires browser APIs. Use dynamic imports with `ssr: false` to prevent hydration errors.

### 1. Create a Scene Component (Client Component)

```tsx
// components/three/scene.tsx
"use client";

import { Canvas } from "@react-three/fiber";
import { OrbitControls, Environment } from "@react-three/drei";
import { Suspense } from "react";

type SceneProps = {
  children: React.ReactNode;
};

export function Scene({ children }: SceneProps) {
  return (
    <Canvas
      camera={{ position: [0, 0, 5], fov: 50 }}
      gl={{ antialias: true, alpha: true }}
      dpr={[1, 2]}
    >
      <Suspense fallback={null}>
        <ambientLight intensity={0.5} />
        <directionalLight position={[10, 10, 5]} intensity={1} />
        {children}
        <OrbitControls enableDamping dampingFactor={0.05} />
        <Environment preset="city" />
      </Suspense>
    </Canvas>
  );
}
```

### 2. Create a Dynamic Wrapper

```tsx
// components/three/dynamic-scene.tsx
"use client";

import dynamic from "next/dynamic";

export const DynamicScene = dynamic(
  () => import("./scene").then((mod) => mod.Scene),
  { ssr: false }
);
```

### 3. Use in Page

```tsx
// app/page.tsx
import { DynamicScene } from "@/components/three/dynamic-scene";
import { Box } from "@/components/three/box";

export default function Page() {
  return (
    <div className="h-screen w-full">
      <DynamicScene>
        <Box position={[0, 0, 0]} />
      </DynamicScene>
    </div>
  );
}
```

## Core Concepts

### Mesh, Geometry, Material

```tsx
"use client";

import { useRef } from "react";
import { useFrame } from "@react-three/fiber";
import type { Mesh } from "three";

type BoxProps = {
  position?: [number, number, number];
  color?: string;
};

export function Box({ position = [0, 0, 0], color = "#ff6b6b" }: BoxProps) {
  const meshRef = useRef<Mesh>(null);

  useFrame((state, delta) => {
    if (meshRef.current) {
      meshRef.current.rotation.x += delta * 0.5;
      meshRef.current.rotation.y += delta * 0.3;
    }
  });

  return (
    <mesh ref={meshRef} position={position}>
      <boxGeometry args={[1, 1, 1]} />
      <meshStandardMaterial color={color} />
    </mesh>
  );
}
```

### Lights

```tsx
// Common lighting setup
<>
  <ambientLight intensity={0.4} />
  <directionalLight
    position={[5, 5, 5]}
    intensity={1}
    castShadow
    shadow-mapSize={[1024, 1024]}
  />
  <pointLight position={[-5, 5, -5]} intensity={0.5} />
  <spotLight position={[0, 10, 0]} angle={0.3} penumbra={1} intensity={1} />
</>
```

## Essential Hooks

### useFrame - Animation Loop

```tsx
import { useFrame } from "@react-three/fiber";

function AnimatedMesh() {
  const meshRef = useRef<Mesh>(null);

  // Runs every frame (60fps)
  useFrame((state, delta) => {
    // state.clock.elapsedTime - total time
    // delta - time since last frame
    if (meshRef.current) {
      meshRef.current.rotation.y = state.clock.elapsedTime;
    }
  });

  return <mesh ref={meshRef}>...</mesh>;
}
```

### useThree - Access Three.js Internals

```tsx
import { useThree } from "@react-three/fiber";

function CameraInfo() {
  const { camera, gl, scene, size, viewport } = useThree();

  // camera - active camera
  // gl - WebGL renderer
  // scene - Three.js scene
  // size - canvas size in pixels { width, height }
  // viewport - viewport in Three.js units { width, height, factor }

  return null;
}
```

### useLoader - Load Assets

```tsx
import { useLoader } from "@react-three/fiber";
import { TextureLoader } from "three";

function TexturedMesh() {
  const texture = useLoader(TextureLoader, "/textures/wood.jpg");

  return (
    <mesh>
      <boxGeometry />
      <meshStandardMaterial map={texture} />
    </mesh>
  );
}
```

## Drei Helpers

### OrbitControls

```tsx
import { OrbitControls } from "@react-three/drei";

<OrbitControls
  enableDamping
  dampingFactor={0.05}
  enableZoom={true}
  enablePan={true}
  minDistance={2}
  maxDistance={20}
  minPolarAngle={0}
  maxPolarAngle={Math.PI / 2}
/>
```

### Environment (Lighting/Reflections)

```tsx
import { Environment } from "@react-three/drei";

// Preset environments
<Environment preset="city" /> // city, sunset, dawn, night, warehouse, forest, apartment, studio, park, lobby

// Custom HDR
<Environment files="/hdri/environment.hdr" />

// Background visible
<Environment preset="sunset" background />
```

### Html (DOM Elements in 3D)

```tsx
import { Html } from "@react-three/drei";

function Label() {
  return (
    <mesh position={[0, 2, 0]}>
      <sphereGeometry args={[0.5]} />
      <meshStandardMaterial color="blue" />
      <Html
        position={[0, 1, 0]}
        center
        distanceFactor={10}
        occlude
      >
        <div className="bg-white px-2 py-1 rounded text-sm">
          Label Text
        </div>
      </Html>
    </mesh>
  );
}
```

### useGLTF (Load 3D Models)

```tsx
import { useGLTF } from "@react-three/drei";

type ModelProps = {
  url: string;
  position?: [number, number, number];
  scale?: number;
};

function Model({ url, position = [0, 0, 0], scale = 1 }: ModelProps) {
  const { scene } = useGLTF(url);

  return <primitive object={scene} position={position} scale={scale} />;
}

// Preload for better performance
useGLTF.preload("/models/robot.glb");
```

### Text (3D Text)

```tsx
import { Text, Text3D } from "@react-three/drei";

// 2D text billboard
<Text
  position={[0, 2, 0]}
  fontSize={0.5}
  color="white"
  anchorX="center"
  anchorY="middle"
>
  Hello World
</Text>

// 3D extruded text (requires font JSON)
<Text3D
  font="/fonts/helvetiker_regular.typeface.json"
  size={0.5}
  height={0.1}
>
  3D Text
  <meshStandardMaterial color="gold" />
</Text3D>
```

### Center, Float, PresentationControls

```tsx
import { Center, Float, PresentationControls } from "@react-three/drei";

// Center objects
<Center>
  <mesh>...</mesh>
</Center>

// Floating animation
<Float speed={2} rotationIntensity={0.5} floatIntensity={1}>
  <mesh>...</mesh>
</Float>

// Touch/drag controls for showcasing
<PresentationControls
  global
  snap
  rotation={[0, -Math.PI / 4, 0]}
  polar={[-Math.PI / 4, Math.PI / 4]}
  azimuth={[-Math.PI / 4, Math.PI / 4]}
>
  <mesh>...</mesh>
</PresentationControls>
```

## Performance Best Practices

### 1. Use Instances for Repeated Objects

```tsx
import { Instances, Instance } from "@react-three/drei";

function Cubes({ count = 100 }: { count?: number }) {
  const positions = useMemo(() =>
    Array.from({ length: count }, () => [
      (Math.random() - 0.5) * 10,
      (Math.random() - 0.5) * 10,
      (Math.random() - 0.5) * 10,
    ] as [number, number, number]),
    [count]
  );

  return (
    <Instances limit={count}>
      <boxGeometry />
      <meshStandardMaterial />
      {positions.map((pos, i) => (
        <Instance key={`cube-${pos[0]}-${pos[1]}-${pos[2]}`} position={pos} />
      ))}
    </Instances>
  );
}
```

### 2. Use Suspense and Preloading

```tsx
import { Suspense } from "react";
import { useGLTF } from "@react-three/drei";

// Preload assets
useGLTF.preload("/models/scene.glb");

function App() {
  return (
    <Canvas>
      <Suspense fallback={<LoadingSpinner />}>
        <Model />
      </Suspense>
    </Canvas>
  );
}

function LoadingSpinner() {
  return (
    <mesh>
      <sphereGeometry args={[0.5, 16, 16]} />
      <meshBasicMaterial color="gray" wireframe />
    </mesh>
  );
}
```

### 3. Optimize Canvas Settings

```tsx
<Canvas
  dpr={[1, 2]} // Limit pixel ratio for performance
  gl={{
    antialias: true,
    alpha: false, // false if no transparency needed
    powerPreference: "high-performance",
  }}
  frameloop="demand" // Only render when needed (use invalidate())
  performance={{ min: 0.5 }} // Adaptive performance
>
```

### 4. Use LOD (Level of Detail)

```tsx
import { Detailed } from "@react-three/drei";

function AdaptiveModel() {
  return (
    <Detailed distances={[0, 10, 25]}>
      <HighDetailModel />  {/* < 10 units away */}
      <MediumDetailModel /> {/* 10-25 units */}
      <LowDetailModel />   {/* > 25 units */}
    </Detailed>
  );
}
```

### 5. Dispose Resources

```tsx
import { useEffect } from "react";
import { useThree } from "@react-three/fiber";

function CleanupComponent() {
  const { gl } = useThree();

  useEffect(() => {
    return () => {
      gl.dispose();
    };
  }, [gl]);

  return null;
}
```

## SSR/Hydration Considerations

1. **Always use dynamic imports** with `ssr: false` for components containing `<Canvas>`
2. **Wrap in client boundary** - All R3F components must be client components
3. **Loading states** - Provide fallback UI while 3D content loads
4. **Window checks** - If accessing `window`, check for browser environment

```tsx
// Safe pattern for Next.js App Router
"use client";

import dynamic from "next/dynamic";
import { Suspense } from "react";

const Scene3D = dynamic(() => import("./scene-3d"), {
  ssr: false,
  loading: () => (
    <div className="h-full w-full flex items-center justify-center bg-gray-900">
      <div className="animate-spin h-8 w-8 border-4 border-white border-t-transparent rounded-full" />
    </div>
  ),
});

export function ThreeContainer() {
  return (
    <div className="h-screen w-full">
      <Suspense fallback={null}>
        <Scene3D />
      </Suspense>
    </div>
  );
}
```

## File Structure

```
components/
  three/
    scene.tsx           # Main Canvas wrapper
    dynamic-scene.tsx   # Dynamic import wrapper
    objects/
      box.tsx           # Mesh components
      sphere.tsx
      model.tsx         # GLTF loader component
    helpers/
      lights.tsx        # Lighting setup
      controls.tsx      # Camera controls
public/
  models/               # .glb, .gltf files
  textures/             # Image textures
  hdri/                 # Environment maps
```

## References

- [R3F Documentation](https://r3f.docs.pmnd.rs/)
- [Drei Documentation](https://drei.docs.pmnd.rs/)
- [Three.js Documentation](https://threejs.org/docs/)
- [react-three-next Starter](https://github.com/pmndrs/react-three-next)
