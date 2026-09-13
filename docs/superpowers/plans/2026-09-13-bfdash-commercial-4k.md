# BFDash 4K Commercial Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a 45-second, 4K landscape (3840x2160) Remotion video reusing the Short's script, photos, music, icons, and brand assets in a left/right split layout instead of the Short's top/bottom split.

**Architecture:** A new, independent sibling Remotion project (`video/bfdash-commercial/`) that does not modify or import from `video/bfdash-short/`. It follows the same pure-timing-function / thin-component pattern as the Short: `Caption`, `CalloutBox`, `BeatIcon`, `TitleCard`, and `OutroCard` are ported verbatim (identical code, identical timing constants) since none of their internal geometry is frame-aspect-dependent — they position themselves with percentages relative to whatever container they're placed in, and that container is what changes. Only one component is new: `SplitBeat`, this project's replacement for the Short's `PhotoBeat`, which puts the photo in a left-half container and the icon+caption in a right-half container instead of stacking them top/bottom.

**Tech Stack:** Remotion 4.x, React 18, TypeScript, Vitest + @testing-library/react, ffmpeg/ffprobe for audio trimming and verification. Same versions as `video/bfdash-short/`.

## Global Constraints

- Composition: 3840x2160 (4K landscape, 16:9), 30fps, 1350 frames (45 seconds) — per [design spec](../specs/2026-09-13-bfdash-commercial-4k-design.md#format).
- Exact beat timing and caption text are fixed by the design spec's Timeline table and must be reproduced verbatim — see Task 2.
- Every `calloutRect` value is copied byte-for-byte from the Short's `scenes.ts` (they're percentages of the photo content, not the frame, so they don't change) — per [design spec](../specs/2026-09-13-bfdash-commercial-4k-design.md#layout).
- Left half of the frame is always the full, uncropped photo (never cropped); right half is icon (feature beats only) + caption — per [design spec](../specs/2026-09-13-bfdash-commercial-4k-design.md#layout).
- Music: `C:\Drone\Music\Tame Impala - Cause I'm A Man.flac`, trimmed to exactly 1:11–1:56 (45.000s) — per [design spec](../specs/2026-09-13-bfdash-commercial-4k-design.md#assets). Same Content-ID caveat as the Short applies (the project owner's deliberate choice).
- Audio fade-out: volume ramps 1→0 from frame 1327 to frame 1350 — per [design spec](../specs/2026-09-13-bfdash-commercial-4k-design.md#assets).
- `video/bfdash-short/` must not be modified by any task in this plan.

---

## File Structure

```
video/bfdash-commercial/
  package.json
  tsconfig.json
  remotion.config.ts
  vitest.config.ts
  vitest.setup.ts            # ported verbatim from the Short (Task 1, included from the start)
  scripts/
    copy-photos.mjs           # Task 9: one-time copy of 5 photos from the Short's project
    copy-photos.test.mjs
    extract-audio.sh          # Task 10: one-time ffmpeg trim (1:11-1:56) of the music bed
    extract-audio.test.mjs
  public/
    photos/                   # Task 9 output: rates.jpg, pids.jpg, filters-p.jpg, vtx.jpg, motor.jpg
    audio/
      hook-track.mp3           # Task 10 output: trimmed 45s Tame Impala clip
    brand/
      splash-neontag-blue.png # Task 7 input, copied from the Short's public/brand/
      pfp-neontag-blue.png    # Task 8 input, copied from the Short's public/brand/
  src/
    index.ts                  # Task 1: registerRoot
    Root.tsx                  # Task 1 (placeholder) -> Task 11 (final registration)
    BFDashCommercial.tsx       # Task 1 (placeholder) -> Task 11 (final assembly)
    scenes.ts                  # Task 2: the data-driven scene array + types
    scenes.test.ts
    components/
      Caption.tsx               # Task 3: ported verbatim from the Short
      Caption.timing.ts
      Caption.timing.test.ts
      CalloutBox.tsx             # Task 4: ported verbatim
      CalloutBox.timing.ts
      CalloutBox.timing.test.ts
      BeatIcon.tsx               # Task 5: ported verbatim
      BeatIcon.timing.ts
      BeatIcon.timing.test.ts
      SplitBeat.tsx              # Task 6: new -- left/right split layout
      TitleCard.tsx              # Task 7: ported verbatim
      TitleCard.test.tsx
      OutroCard.tsx              # Task 8: ported verbatim
      OutroCard.test.tsx
  out/
    bfdash-commercial.mp4      # Task 12 final render output (git-ignored)
```

---

### Task 1: Project scaffold + smoke test

**Files:**
- Create: `video/bfdash-commercial/package.json`
- Create: `video/bfdash-commercial/tsconfig.json`
- Create: `video/bfdash-commercial/remotion.config.ts`
- Create: `video/bfdash-commercial/vitest.config.ts`
- Create: `video/bfdash-commercial/vitest.setup.ts`
- Create: `video/bfdash-commercial/.gitignore`
- Create: `video/bfdash-commercial/src/index.ts`
- Create: `video/bfdash-commercial/src/Root.tsx`
- Create: `video/bfdash-commercial/src/BFDashCommercial.tsx`
- Test: `video/bfdash-commercial/src/BFDashCommercial.test.tsx`

**Interfaces:**
- Produces: `BFDashCommercial` — a `React.FC` with no required props, registered as composition id `"BFDashCommercial"`, 3840x2160, 30fps, 1350 frames. Tasks 2–11 build up this component's internals; Task 11 is the only task that edits its body again after this one.
- Produces: `mockFrameState` (exported from `vitest.setup.ts`) — a mutable `{ frame: number }` object component tests set before rendering, so they can assert on post-animation state instead of only ever seeing frame 0. This is included from the start here (the Short's project discovered it was needed partway through and had to retrofit it — this plan avoids that).

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "bfdash-commercial",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "remotion studio",
    "build": "remotion render BFDashCommercial out/bfdash-commercial.mp4",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@remotion/cli": "^4.0.0",
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "remotion": "^4.0.0"
  },
  "devDependencies": {
    "@remotion/renderer": "^4.0.0",
    "@testing-library/react": "^16.0.0",
    "@types/node": "^20.0.0",
    "@types/react": "^18.3.0",
    "@types/react-dom": "^18.3.0",
    "jsdom": "^25.0.0",
    "typescript": "^5.5.0",
    "vitest": "^2.0.0"
  }
}
```

- [ ] **Step 2: Write `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "jsx": "react-jsx",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true
  },
  "include": ["src", "scripts"]
}
```

- [ ] **Step 3: Write `remotion.config.ts`**

```ts
import { Config } from "@remotion/cli/config";

Config.setVideoImageFormat("jpeg");
```

- [ ] **Step 4: Write `vitest.config.ts`**

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./vitest.setup.ts"],
  },
});
```

- [ ] **Step 5: Write `vitest.setup.ts`**

```ts
import { vi } from "vitest";
import React from "react";

// Mutable frame state that test files can set before rendering, so
// component tests can assert on post-animation state (e.g. opacity after a
// pop-in finishes) instead of only ever seeing frame 0. Import
// `mockFrameState` from this module and set `mockFrameState.frame = 40`
// before calling `render(...)`.
export const mockFrameState = { frame: 0 };

vi.mock("remotion", async () => {
  const actual = await vi.importActual<typeof import("remotion")>("remotion");
  return {
    ...actual,
    useCurrentFrame: () => mockFrameState.frame,
    Img: ({ src, style }: any) => React.createElement("img", { src, style }),
    AbsoluteFill: ({ children, style }: any) => React.createElement("div", { style }, children),
  };
});
```

- [ ] **Step 6: Write `.gitignore`**

```
node_modules
out
.remotion
```

- [ ] **Step 7: Write `src/index.ts`**

```ts
import { registerRoot } from "remotion";
import { RemotionRoot } from "./Root";

registerRoot(RemotionRoot);
```

- [ ] **Step 8: Write `src/BFDashCommercial.tsx` (placeholder body, replaced in Task 11)**

```tsx
import React from "react";
import { AbsoluteFill } from "remotion";

export const BFDashCommercial: React.FC = () => {
  return <AbsoluteFill style={{ backgroundColor: "#05070d" }} />;
};
```

- [ ] **Step 9: Write `src/Root.tsx`**

```tsx
import React from "react";
import { Composition } from "remotion";
import { BFDashCommercial } from "./BFDashCommercial";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="BFDashCommercial"
      component={BFDashCommercial}
      durationInFrames={1350}
      fps={30}
      width={3840}
      height={2160}
    />
  );
};
```

- [ ] **Step 10: Write the failing smoke test `src/BFDashCommercial.test.tsx`**

```tsx
import { describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { BFDashCommercial } from "./BFDashCommercial";

describe("BFDashCommercial", () => {
  it("renders without throwing", () => {
    const { container } = render(<BFDashCommercial />);
    expect(container.firstChild).not.toBeNull();
  });
});
```

- [ ] **Step 11: Install dependencies**

Run: `cd video/bfdash-commercial && npm install`
Expected: installs succeed, `node_modules` created, no error output.

- [ ] **Step 12: Run the test to verify it passes**

Run: `cd video/bfdash-commercial && npm test`
Expected: PASS — `BFDashCommercial > renders without throwing`

- [ ] **Step 13: Typecheck**

Run: `cd video/bfdash-commercial && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 14: Commit**

```bash
git add video/bfdash-commercial
git commit -m "feat(video): scaffold bfdash-commercial Remotion project"
```

---

### Task 2: Scene data config

**Files:**
- Create: `video/bfdash-commercial/src/scenes.ts`
- Test: `video/bfdash-commercial/src/scenes.test.ts`

**Interfaces:**
- Produces: `SceneType`, `RevealVariant`, `BeatIconType`, `CalloutRect`, `Scene` interface, and the exported `scenes: Scene[]` array — identical shape to the Short's `scenes.ts`. Tasks 3–8 render individual `Scene` fields; Task 11 consumes the full `scenes` array.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { scenes } from "./scenes";

describe("scenes", () => {
  it("covers exactly 1350 frames with no gaps or overlaps, in order", () => {
    let expectedStart = 0;
    for (const scene of scenes) {
      expect(scene.startFrame).toBe(expectedStart);
      expect(scene.durationFrames).toBeGreaterThan(0);
      expectedStart += scene.durationFrames;
    }
    expect(expectedStart).toBe(1350);
  });

  it("gives every scene a non-empty caption", () => {
    for (const scene of scenes) {
      expect(scene.caption.length).toBeGreaterThan(0);
    }
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd video/bfdash-commercial && npm test -- scenes.test.ts`
Expected: FAIL with "Cannot find module './scenes'".

- [ ] **Step 3: Write `src/scenes.ts`**

```ts
export type SceneType = "hook" | "reveal" | "feature" | "payoff" | "cta" | "outro";
export type RevealVariant = "caption" | "title";
export type BeatIconType = "sliders" | "grid" | "gauge" | "funnel" | "signal" | "propeller";

export interface CalloutRect {
  xPct: number;
  yPct: number;
  wPct: number;
  hPct: number;
}

export interface Scene {
  id: string;
  type: SceneType;
  startFrame: number;
  durationFrames: number;
  caption: string;
  subtitle?: string;
  image?: string;
  calloutRect?: CalloutRect;
  revealVariant?: RevealVariant;
  icon?: BeatIconType;
}

export const scenes: Scene[] = [
  {
    id: "hook",
    type: "hook",
    startFrame: 0,
    durationFrames: 180,
    image: "photos/rates.jpg",
    caption: "Tired of tabbing between goggles and Betaflight mid-tune?",
  },
  {
    id: "reveal-caption",
    type: "reveal",
    revealVariant: "caption",
    startFrame: 180,
    durationFrames: 75,
    caption: "So I vibe-coded my own LUA app.",
  },
  {
    id: "reveal-title",
    type: "reveal",
    revealVariant: "title",
    startFrame: 255,
    durationFrames: 105,
    caption: "BFDash",
    subtitle: "Remote Betaflight Configuration Dashboard",
  },
  {
    id: "feature-pids-sliders",
    type: "feature",
    startFrame: 360,
    durationFrames: 113,
    image: "photos/pids.jpg",
    caption: "8 PID tuning sliders — matched to Configurator",
    calloutRect: { xPct: 9, yPct: 40, wPct: 30, hPct: 37 },
    icon: "sliders",
  },
  {
    id: "feature-pids-numbers",
    type: "feature",
    startFrame: 473,
    durationFrames: 112,
    image: "photos/pids.jpg",
    caption: "Live P / I / D / D-Min / FF preview",
    calloutRect: { xPct: 50, yPct: 40, wPct: 44, hPct: 20 },
    icon: "grid",
  },
  {
    id: "feature-rates-data",
    type: "feature",
    startFrame: 585,
    durationFrames: 113,
    image: "photos/rates.jpg",
    caption: "All 4 rate types, every axis",
    calloutRect: { xPct: 6, yPct: 40, wPct: 69, hPct: 26 },
    icon: "gauge",
  },
  {
    id: "feature-filters",
    type: "feature",
    startFrame: 698,
    durationFrames: 112,
    image: "photos/filters-p.jpg",
    caption: "Gyro + D-term filters — global & per-profile",
    calloutRect: { xPct: 9, yPct: 37, wPct: 80, hPct: 30 },
    icon: "funnel",
  },
  {
    id: "feature-vtx",
    type: "feature",
    startFrame: 810,
    durationFrames: 113,
    image: "photos/vtx.jpg",
    caption: "Band, channel, power",
    calloutRect: { xPct: 11, yPct: 34, wPct: 15, hPct: 17 },
    icon: "signal",
  },
  {
    id: "feature-motor",
    type: "feature",
    startFrame: 923,
    durationFrames: 112,
    image: "photos/motor.jpg",
    caption: "Throttle boost, idle, sag comp",
    calloutRect: { xPct: 11, yPct: 34, wPct: 56, hPct: 26 },
    icon: "propeller",
  },
  {
    id: "payoff",
    type: "payoff",
    startFrame: 1035,
    durationFrames: 135,
    image: "photos/motor.jpg",
    caption: "Change it in the field.\nNo goggles. No laptop. No USB.",
  },
  {
    id: "cta",
    type: "cta",
    startFrame: 1170,
    durationFrames: 90,
    image: "photos/motor.jpg",
    caption: "Tested on Jumper T15 & RadioMaster TX15 —\ntry it, tell me what breaks.",
  },
  {
    id: "outro",
    type: "outro",
    startFrame: 1260,
    durationFrames: 90,
    caption: "Subscribe for more FPV\nLink in Bio - Comments Open",
  },
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd video/bfdash-commercial && npm test -- scenes.test.ts`
Expected: PASS — both tests green.

- [ ] **Step 5: Commit**

```bash
git add video/bfdash-commercial/src/scenes.ts video/bfdash-commercial/src/scenes.test.ts
git commit -m "feat(video): add data-driven scene config for BFDash commercial"
```

---

### Task 3: Caption component (ported)

**Files:**
- Create: `video/bfdash-commercial/src/components/Caption.timing.ts`
- Create: `video/bfdash-commercial/src/components/Caption.tsx`
- Test: `video/bfdash-commercial/src/components/Caption.timing.test.ts`

**Interfaces:**
- Produces: `getWordStyle(frame: number, wordStartFrame: number): { opacity: number; translateY: number; scale: number }`, `splitIntoLines`, `getWordStartFrame` from `Caption.timing.ts`. `Caption` component: `React.FC<{ text: string; startFrame: number; position?: "top" | "bottom" }>` (default `position="top"`). Tasks 6, 8 render `<Caption text={...} startFrame={...} position={...} />`.
- This is a byte-for-byte port of `video/bfdash-short/src/components/Caption.tsx` and `Caption.timing.ts` — no logic changes. The `position` prop already makes it reusable inside any container regardless of that container's width, which is exactly what Task 6's right-half box needs with no modification.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { getWordStyle, splitIntoLines } from "./Caption.timing";

describe("splitIntoLines", () => {
  it("splits on newline into words", () => {
    expect(splitIntoLines("Hello world\nSecond line")).toEqual([
      ["Hello", "world"],
      ["Second", "line"],
    ]);
  });
});

describe("getWordStyle", () => {
  it("is fully invisible before its word's start frame", () => {
    const style = getWordStyle(0, 10);
    expect(style.opacity).toBe(0);
  });

  it("is fully visible well after the pop finishes", () => {
    const style = getWordStyle(30, 0);
    expect(style.opacity).toBe(1);
    expect(style.translateY).toBe(0);
    expect(style.scale).toBe(1);
  });

  it("is mid-animation partway through the pop", () => {
    const style = getWordStyle(4, 0);
    expect(style.opacity).toBeGreaterThan(0);
    expect(style.opacity).toBeLessThan(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd video/bfdash-commercial && npm test -- Caption.timing.test.ts`
Expected: FAIL with "Cannot find module './Caption.timing'".

- [ ] **Step 3: Write `src/components/Caption.timing.ts`**

```ts
import { Easing, interpolate } from "remotion";

export const WORD_STAGGER_FRAMES = 2;
export const WORD_POP_FRAMES = 8;

export const splitIntoLines = (caption: string): string[][] => {
  return caption.split("\n").map((line) => line.trim().split(/\s+/));
};

export interface WordStyle {
  opacity: number;
  translateY: number;
  scale: number;
}

export const getWordStyle = (frame: number, wordStartFrame: number): WordStyle => {
  const localFrame = frame - wordStartFrame;
  const progress = interpolate(localFrame, [0, WORD_POP_FRAMES], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  return {
    opacity: progress,
    translateY: interpolate(progress, [0, 1], [12, 0]),
    scale: interpolate(progress, [0, 1], [0.85, 1]),
  };
};

export const getWordStartFrame = (lineIndex: number, wordIndex: number, wordsBeforeThisLine: number): number => {
  return (wordsBeforeThisLine + wordIndex) * WORD_STAGGER_FRAMES;
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd video/bfdash-commercial && npm test -- Caption.timing.test.ts`
Expected: PASS — all 4 tests green.

- [ ] **Step 5: Write `src/components/Caption.tsx`**

```tsx
import React from "react";
import { useCurrentFrame } from "remotion";
import { getWordStartFrame, getWordStyle, splitIntoLines } from "./Caption.timing";

export const Caption: React.FC<{ text: string; startFrame: number; position?: "top" | "bottom" }> = ({
  text,
  startFrame,
  position = "top",
}) => {
  const frame = useCurrentFrame() - startFrame;
  const lines = splitIntoLines(text);
  let wordsBeforeThisLine = 0;

  return (
    <div
      style={{
        position: "absolute",
        left: "8%",
        right: "8%",
        ...(position === "top" ? { bottom: "54%" } : { top: "54%" }),
        display: "flex",
        flexDirection: "column",
        gap: 24,
        fontFamily: "system-ui, sans-serif",
        fontWeight: 800,
        fontSize: 96,
        lineHeight: 1.15,
        color: "#ffffff",
        textShadow: "0 0 24px rgba(56, 214, 255, 0.85), 0 0 4px rgba(56, 214, 255, 0.9)",
      }}
    >
      {lines.map((words, lineIndex) => {
        const lineStartOffset = wordsBeforeThisLine;
        wordsBeforeThisLine += words.length;
        return (
          <div key={lineIndex} style={{ display: "flex", flexWrap: "wrap", gap: "0 20px" }}>
            {words.map((word, wordIndex) => {
              const wordStartFrame = getWordStartFrame(lineIndex, wordIndex, lineStartOffset);
              const style = getWordStyle(frame, wordStartFrame);
              return (
                <span
                  key={wordIndex}
                  style={{
                    display: "inline-block",
                    opacity: style.opacity,
                    transform: `translateY(${style.translateY}px) scale(${style.scale})`,
                  }}
                >
                  {word}
                </span>
              );
            })}
          </div>
        );
      })}
    </div>
  );
};
```

- [ ] **Step 6: Typecheck**

Run: `cd video/bfdash-commercial && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add video/bfdash-commercial/src/components/Caption.timing.ts video/bfdash-commercial/src/components/Caption.timing.test.ts video/bfdash-commercial/src/components/Caption.tsx
git commit -m "feat(video): port Caption component from the Short"
```

---

### Task 4: CalloutBox component (ported)

**Files:**
- Create: `video/bfdash-commercial/src/components/CalloutBox.timing.ts`
- Create: `video/bfdash-commercial/src/components/CalloutBox.tsx`
- Test: `video/bfdash-commercial/src/components/CalloutBox.timing.test.ts`

**Interfaces:**
- Consumes: `CalloutRect` type from `../scenes`.
- Produces: `getCalloutOpacity`, `getCalloutScale` from `CalloutBox.timing.ts`. `CalloutBox` component: `React.FC<{ rect: CalloutRect; durationFrames: number }>`. Task 6 renders `CalloutBox` as a child inside the same positioned container as the photo `Img`, so its percentage-based positioning is relative to that container (the photo's displayed rect), not the frame.
- Byte-for-byte port of `video/bfdash-short/src/components/CalloutBox.tsx` and `CalloutBox.timing.ts`.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { getCalloutOpacity, getCalloutScale } from "./CalloutBox.timing";

describe("getCalloutOpacity", () => {
  it("fades in over the first 5 frames", () => {
    expect(getCalloutOpacity(0, 75)).toBe(0);
    expect(getCalloutOpacity(5, 75)).toBe(1);
  });

  it("fades out over the last 5 frames", () => {
    expect(getCalloutOpacity(70, 75)).toBe(1);
    expect(getCalloutOpacity(75, 75)).toBe(0);
  });

  it("stays fully visible in the middle", () => {
    expect(getCalloutOpacity(40, 75)).toBe(1);
  });
});

describe("getCalloutScale", () => {
  it("scales up from 0.92 to 1 during fade-in", () => {
    expect(getCalloutScale(0, 75)).toBeCloseTo(0.92, 2);
    expect(getCalloutScale(5, 75)).toBeCloseTo(1, 2);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd video/bfdash-commercial && npm test -- CalloutBox.timing.test.ts`
Expected: FAIL with "Cannot find module './CalloutBox.timing'".

- [ ] **Step 3: Write `src/components/CalloutBox.timing.ts`**

```ts
import { interpolate } from "remotion";

export const CALLOUT_FADE_FRAMES = 5;

export const getCalloutOpacity = (frame: number, durationFrames: number): number => {
  const fadeIn = interpolate(frame, [0, CALLOUT_FADE_FRAMES], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const fadeOut = interpolate(
    frame,
    [durationFrames - CALLOUT_FADE_FRAMES, durationFrames],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  return Math.min(fadeIn, fadeOut);
};

export const getCalloutScale = (frame: number, durationFrames: number): number => {
  return interpolate(frame, [0, CALLOUT_FADE_FRAMES], [0.92, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd video/bfdash-commercial && npm test -- CalloutBox.timing.test.ts`
Expected: PASS — all 4 tests green.

- [ ] **Step 5: Write `src/components/CalloutBox.tsx`**

```tsx
import React from "react";
import { useCurrentFrame } from "remotion";
import type { CalloutRect } from "../scenes";
import { getCalloutOpacity, getCalloutScale } from "./CalloutBox.timing";

export const CalloutBox: React.FC<{ rect: CalloutRect; durationFrames: number }> = ({
  rect,
  durationFrames,
}) => {
  const frame = useCurrentFrame();
  const opacity = getCalloutOpacity(frame, durationFrames);
  const scale = getCalloutScale(frame, durationFrames);

  return (
    <div
      style={{
        position: "absolute",
        left: `${rect.xPct}%`,
        top: `${rect.yPct}%`,
        width: `${rect.wPct}%`,
        height: `${rect.hPct}%`,
        opacity,
        transform: `scale(${scale})`,
        border: "6px solid #38d6ff",
        borderRadius: 32,
        boxShadow: "0 0 40px rgba(56, 214, 255, 0.9), inset 0 0 24px rgba(56, 214, 255, 0.5)",
      }}
    />
  );
};
```

- [ ] **Step 6: Typecheck**

Run: `cd video/bfdash-commercial && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add video/bfdash-commercial/src/components/CalloutBox.timing.ts video/bfdash-commercial/src/components/CalloutBox.timing.test.ts video/bfdash-commercial/src/components/CalloutBox.tsx
git commit -m "feat(video): port CalloutBox component from the Short"
```

---

### Task 5: BeatIcon component (ported)

**Files:**
- Create: `video/bfdash-commercial/src/components/BeatIcon.timing.ts`
- Create: `video/bfdash-commercial/src/components/BeatIcon.tsx`
- Test: `video/bfdash-commercial/src/components/BeatIcon.timing.test.ts`

**Interfaces:**
- Produces: `getIconDrawProgress(frame: number): number`, `ICON_DRAW_FRAMES` from `BeatIcon.timing.ts`. `BeatIcon` component: `React.FC<{ icon: BeatIconType }>`, exported `BeatIconType` union (also re-declared identically in `scenes.ts` per Task 2 — both must list the same six values: `"sliders" | "grid" | "gauge" | "funnel" | "signal" | "propeller"`). Task 6 renders `{icon && <BeatIcon icon={icon} />}` inside the right-half container.
- Byte-for-byte port of `video/bfdash-short/src/components/BeatIcon.tsx` and `BeatIcon.timing.ts`, including the exact per-icon path geometry and precomputed lengths.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { getIconDrawProgress, ICON_DRAW_FRAMES } from "./BeatIcon.timing";

describe("getIconDrawProgress", () => {
  it("starts at 0", () => {
    expect(getIconDrawProgress(0)).toBe(0);
  });

  it("reaches 1 once drawing finishes", () => {
    expect(getIconDrawProgress(ICON_DRAW_FRAMES)).toBe(1);
  });

  it("is partway through mid-draw", () => {
    const progress = getIconDrawProgress(ICON_DRAW_FRAMES / 2);
    expect(progress).toBeGreaterThan(0);
    expect(progress).toBeLessThan(1);
  });

  it("clamps beyond the draw window", () => {
    expect(getIconDrawProgress(ICON_DRAW_FRAMES + 50)).toBe(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd video/bfdash-commercial && npm test -- BeatIcon.timing.test.ts`
Expected: FAIL with "Cannot find module './BeatIcon.timing'".

- [ ] **Step 3: Write `src/components/BeatIcon.timing.ts`**

```ts
import { Easing, interpolate } from "remotion";

export const ICON_DRAW_FRAMES = 15;

export const getIconDrawProgress = (frame: number): number => {
  return interpolate(frame, [0, ICON_DRAW_FRAMES], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd video/bfdash-commercial && npm test -- BeatIcon.timing.test.ts`
Expected: PASS — all 4 tests green.

- [ ] **Step 5: Write `src/components/BeatIcon.tsx`**

```tsx
import React from "react";
import { useCurrentFrame } from "remotion";
import { getIconDrawProgress } from "./BeatIcon.timing";

export type BeatIconType = "sliders" | "grid" | "gauge" | "funnel" | "signal" | "propeller";

interface IconPath {
  d: string;
  length: number;
}

interface IconDef {
  paths: IconPath[];
  dots?: { cx: number; cy: number; r: number }[];
}

// All icons are built from straight line segments (plus filled dots) so each
// path's length is exact, computable geometry -- not an approximation. This
// matters: the stroke "draw-on" effect requires stroke-dasharray to match
// each path's real length, or the reveal is partial/glitchy (arcs and bezier
// curves make that hard to get exactly right, which is why none are used
// here).
const ICONS: Record<BeatIconType, IconDef> = {
  sliders: {
    paths: [
      { d: "M15 35 H85", length: 70 },
      { d: "M40 25 V45", length: 20 },
      { d: "M15 65 H85", length: 70 },
      { d: "M65 55 V75", length: 20 },
    ],
  },
  grid: {
    paths: [
      { d: "M20 20 H80", length: 60 },
      { d: "M20 50 H80", length: 60 },
      { d: "M20 80 H80", length: 60 },
      { d: "M20 20 V80", length: 60 },
      { d: "M50 20 V80", length: 60 },
      { d: "M80 20 V80", length: 60 },
    ],
  },
  gauge: {
    paths: [
      { d: "M20 70 L50 35", length: 46.1 },
      { d: "M50 35 L80 70", length: 46.1 },
      { d: "M50 70 L65 40", length: 33.5 },
    ],
  },
  funnel: {
    paths: [
      { d: "M20 20 L80 20", length: 60 },
      { d: "M20 20 L50 55", length: 46.1 },
      { d: "M80 20 L50 55", length: 46.1 },
      { d: "M50 55 L50 80", length: 25 },
    ],
  },
  signal: {
    paths: [
      { d: "M40 65 L50 55", length: 14.1 },
      { d: "M50 55 L60 65", length: 14.1 },
      { d: "M30 50 L50 30", length: 28.3 },
      { d: "M50 30 L70 50", length: 28.3 },
      { d: "M20 35 L50 5", length: 42.4 },
      { d: "M50 5 L80 35", length: 42.4 },
    ],
    dots: [{ cx: 50, cy: 80, r: 4 }],
  },
  propeller: {
    paths: [
      { d: "M50 20 V80", length: 60 },
      { d: "M20 50 H80", length: 60 },
    ],
    dots: [{ cx: 50, cy: 50, r: 6 }],
  },
};

export const BeatIcon: React.FC<{ icon: BeatIconType }> = ({ icon }) => {
  const frame = useCurrentFrame();
  const progress = getIconDrawProgress(frame);
  const def = ICONS[icon];

  return (
    <div
      style={{
        position: "absolute",
        top: "8%",
        left: "50%",
        transform: "translateX(-50%)",
        width: "14%",
        aspectRatio: "1 / 1",
        opacity: progress,
      }}
    >
      <svg
        viewBox="0 0 100 100"
        style={{
          width: "100%",
          height: "100%",
          color: "#38d6ff",
          filter: "drop-shadow(0 0 12px rgba(56, 214, 255, 0.85))",
        }}
      >
        <g fill="none" stroke="currentColor" strokeWidth={6} strokeLinecap="round" strokeLinejoin="round">
          {def.paths.map((path, i) => (
            <path
              key={i}
              d={path.d}
              style={{
                strokeDasharray: path.length,
                strokeDashoffset: path.length * (1 - progress),
              }}
            />
          ))}
        </g>
        {def.dots?.map((dot, i) => (
          <circle key={i} cx={dot.cx} cy={dot.cy} r={dot.r} fill="currentColor" stroke="none" />
        ))}
      </svg>
    </div>
  );
};
```

- [ ] **Step 6: Typecheck**

Run: `cd video/bfdash-commercial && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add video/bfdash-commercial/src/components/BeatIcon.timing.ts video/bfdash-commercial/src/components/BeatIcon.timing.test.ts video/bfdash-commercial/src/components/BeatIcon.tsx
git commit -m "feat(video): port BeatIcon component from the Short"
```

---

### Task 6: SplitBeat component (new)

**Files:**
- Create: `video/bfdash-commercial/src/components/SplitBeat.tsx`

**Interfaces:**
- Consumes: `CalloutRect` type from `../scenes`; `CalloutBox` from `./CalloutBox` (Task 4).
- Produces: `SplitBeat` component: `React.FC<{ image: string; durationFrames: number; calloutRect?: CalloutRect; icon?: React.ReactNode; caption: React.ReactNode; dim?: boolean }>`. This is the project's replacement for the Short's `PhotoBeat` — Task 11 renders one `SplitBeat` per hook/feature/payoff/cta scene, inside a `<Sequence>`, passing a `<BeatIcon icon={...} />` element (or `undefined`) and a `<Caption .../>` element as the `icon`/`caption` props rather than SplitBeat importing those components itself — this keeps SplitBeat's own responsibility to exactly one thing: the left/right split geometry, with no opinion on what renders in each half beyond "photo on the left."

No test file for this task, matching the plan's existing pattern for assembled layout components (the Short's `PhotoBeat` also has no direct test — its correctness is verified by the Task 11 integration render test, which is where a wrong layout would actually be visible).

- [ ] **Step 1: Write `src/components/SplitBeat.tsx`**

```tsx
import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import type { CalloutRect } from "../scenes";
import { CalloutBox } from "./CalloutBox";

// The source photos are the full, uncropped, rotated-upright phone photos,
// copied verbatim from video/bfdash-short/public/photos/ (see
// scripts/copy-photos.mjs) -- all five share the same 3840x2880 (4:3, AR
// 1.3333) dimensions. Displayed via "contain" logic inside the left-half box
// (1920x2160, AR 0.8889): since every photo's AR exceeds the box's AR,
// they're all width-constrained under contain -- full width shown,
// letterboxed top/bottom by the same fixed amount. One shared rect covers
// every photo. (This is the same underlying math as the Short's PhotoBeat,
// recomputed for a differently-shaped box: 0.8889/1.3333 = 0.6667, i.e.
// exactly 2/3 -- hence the clean 66.6667/16.6667 split below.)
const PHOTO_DISPLAY_RECT = { left: 0, top: 16.6667, width: 100, height: 66.6667 };

export const SplitBeat: React.FC<{
  image: string;
  durationFrames: number;
  calloutRect?: CalloutRect;
  icon?: React.ReactNode;
  caption: React.ReactNode;
  dim?: boolean;
}> = ({ image, durationFrames, calloutRect, icon, caption, dim = false }) => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
      <div
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: "50%",
          height: "100%",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            position: "absolute",
            left: `${PHOTO_DISPLAY_RECT.left}%`,
            top: `${PHOTO_DISPLAY_RECT.top}%`,
            width: `${PHOTO_DISPLAY_RECT.width}%`,
            height: `${PHOTO_DISPLAY_RECT.height}%`,
          }}
        >
          <Img
            src={staticFile(image)}
            style={{
              width: "100%",
              height: "100%",
              filter: "contrast(1.12) saturate(1.08) brightness(0.92)",
            }}
          />
          {calloutRect && <CalloutBox rect={calloutRect} durationFrames={durationFrames} />}
        </div>
        <AbsoluteFill
          style={{
            background:
              "radial-gradient(circle at 50% 45%, rgba(0,0,0,0) 40%, rgba(0,5,15,0.85) 100%)",
          }}
        />
        {dim && <AbsoluteFill style={{ backgroundColor: "rgba(2, 6, 15, 0.55)" }} />}
      </div>

      <div style={{ position: "absolute", left: "50%", top: 0, width: "50%", height: "100%" }}>
        {icon}
        {caption}
      </div>
    </AbsoluteFill>
  );
};
```

- [ ] **Step 2: Typecheck**

Run: `cd video/bfdash-commercial && npm run typecheck`
Expected: no output, exit code 0. (This will show errors until Tasks 4's `CalloutBox` and Task 2's `scenes.ts` exist, which they do by this point in the plan — if executed out of order, come back to this typecheck once those are in place.)

- [ ] **Step 3: Commit**

```bash
git add video/bfdash-commercial/src/components/SplitBeat.tsx
git commit -m "feat(video): add SplitBeat left/right layout component"
```

---

### Task 7: TitleCard component (ported)

**Files:**
- Create: `video/bfdash-commercial/src/components/TitleCard.tsx`
- Test: `video/bfdash-commercial/src/components/TitleCard.test.tsx`
- Copy: `video/bfdash-short/public/brand/splash-neontag-blue.png` to `video/bfdash-commercial/public/brand/splash-neontag-blue.png`

**Interfaces:**
- Produces: `TitleCard` component: `React.FC<{ title: string; subtitle: string }>`. Task 11 renders this for the `reveal-title` scene.
- Byte-for-byte port of `video/bfdash-short/src/components/TitleCard.tsx`. It's a centered, full-frame flex layout with no aspect-ratio-specific geometry, so it needs no changes for the wider 16:9 canvas — verify this visually in Task 11's integration check and only adjust sizing then if something actually looks wrong, per the design spec's "adapt naturally, adjust only if needed" note.

- [ ] **Step 1: Copy the brand asset**

Run: `mkdir -p video/bfdash-commercial/public/brand && cp video/bfdash-short/public/brand/splash-neontag-blue.png video/bfdash-commercial/public/brand/splash-neontag-blue.png`
Expected: file copied, no error.

- [ ] **Step 2: Write the failing test**

```tsx
import { describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { beforeEach, afterEach } from "vitest";
import { TitleCard } from "./TitleCard";
import { mockFrameState } from "../../vitest.setup";

describe("TitleCard", () => {
  beforeEach(() => {
    mockFrameState.frame = 40;
  });

  afterEach(() => {
    mockFrameState.frame = 0;
  });

  it("renders the title and subtitle text, visibly", () => {
    const { getByText } = render(
      <TitleCard title="BFDash" subtitle="Remote Betaflight Configuration Dashboard" />,
    );
    const titleEl = getByText("BFDash") as HTMLElement;
    expect(titleEl).not.toBeNull();
    expect(titleEl.style.opacity).not.toBe("0");
    expect(getByText("Remote Betaflight Configuration Dashboard")).not.toBeNull();
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd video/bfdash-commercial && npm test -- TitleCard.test.tsx`
Expected: FAIL with "Cannot find module './TitleCard'".

- [ ] **Step 4: Write `src/components/TitleCard.tsx`**

```tsx
import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from "remotion";

const LOGO_POP_FRAMES = 15;
const SUBTITLE_DELAY_FRAMES = 20;
const SUBTITLE_POP_FRAMES = 15;

export const TitleCard: React.FC<{ title: string; subtitle: string }> = ({ title, subtitle }) => {
  const frame = useCurrentFrame();

  const logoProgress = interpolate(frame, [0, LOGO_POP_FRAMES], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const subtitleProgress = interpolate(
    frame,
    [SUBTITLE_DELAY_FRAMES, SUBTITLE_DELAY_FRAMES + SUBTITLE_POP_FRAMES],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) },
  );

  const logoScale = interpolate(logoProgress, [0, 1], [0.85, 1]);

  return (
    <AbsoluteFill
      style={{
        backgroundColor: "#05070d",
        alignItems: "center",
        justifyContent: "center",
        flexDirection: "column",
        gap: 48,
      }}
    >
      <Img
        src={staticFile("brand/splash-neontag-blue.png")}
        style={{
          width: "30%",
          opacity: logoProgress,
          transform: `scale(${logoScale})`,
        }}
      />
      <div
        style={{
          fontFamily: "system-ui, sans-serif",
          fontWeight: 800,
          fontSize: 128,
          color: "#ffffff",
          textShadow: "0 0 24px rgba(56, 214, 255, 0.85), 0 0 4px rgba(56, 214, 255, 0.9)",
          opacity: logoProgress,
          transform: `scale(${logoScale})`,
          textAlign: "center",
        }}
      >
        {title}
      </div>
      <div
        style={{
          fontFamily: "system-ui, sans-serif",
          fontWeight: 700,
          fontSize: 56,
          color: "#bfefff",
          textShadow: "0 0 20px rgba(56, 214, 255, 0.8)",
          opacity: subtitleProgress,
          transform: `translateY(${interpolate(subtitleProgress, [0, 1], [16, 0])}px)`,
          textAlign: "center",
          padding: "0 10%",
        }}
      >
        {subtitle}
      </div>
    </AbsoluteFill>
  );
};
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd video/bfdash-commercial && npm test -- TitleCard.test.tsx`
Expected: PASS.

- [ ] **Step 6: Typecheck**

Run: `cd video/bfdash-commercial && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add video/bfdash-commercial/src/components/TitleCard.tsx video/bfdash-commercial/src/components/TitleCard.test.tsx video/bfdash-commercial/public/brand/splash-neontag-blue.png
git commit -m "feat(video): port TitleCard component from the Short"
```

---

### Task 8: OutroCard component (ported)

**Files:**
- Create: `video/bfdash-commercial/src/components/OutroCard.tsx`
- Test: `video/bfdash-commercial/src/components/OutroCard.test.tsx`
- Copy: `video/bfdash-short/public/brand/pfp-neontag-blue.png` to `video/bfdash-commercial/public/brand/pfp-neontag-blue.png`

**Interfaces:**
- Consumes: `Caption` from `./Caption` (Task 3).
- Produces: `OutroCard` component: `React.FC<{ caption: string }>`. Task 11 renders this for the `outro` scene.
- Byte-for-byte port of `video/bfdash-short/src/components/OutroCard.tsx` — logo in the top half, caption (via `Caption`'s `position="bottom"`) in the bottom half. This is a top/bottom lockup, unaffected by the left/right split used elsewhere in this project, matching the design spec's "non-split beats" note.

- [ ] **Step 1: Copy the brand asset**

Run: `cp video/bfdash-short/public/brand/pfp-neontag-blue.png video/bfdash-commercial/public/brand/pfp-neontag-blue.png`
Expected: file copied, no error.

- [ ] **Step 2: Write the failing test**

```tsx
import { describe, expect, it, beforeEach, afterEach } from "vitest";
import { render } from "@testing-library/react";
import { OutroCard } from "./OutroCard";
import { mockFrameState } from "../../vitest.setup";

describe("OutroCard", () => {
  beforeEach(() => {
    mockFrameState.frame = 40;
  });

  afterEach(() => {
    mockFrameState.frame = 0;
  });

  it("renders both outro lines, visibly", () => {
    const { getByText } = render(
      <OutroCard caption={"Subscribe for more FPV\nLink in Bio - Comments Open"} />,
    );
    const wordEl = getByText("Subscribe") as HTMLElement;
    expect(wordEl).not.toBeNull();
    expect(wordEl.style.opacity).not.toBe("0");
    expect(getByText("Open")).not.toBeNull();
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd video/bfdash-commercial && npm test -- OutroCard.test.tsx`
Expected: FAIL with "Cannot find module './OutroCard'".

- [ ] **Step 4: Write `src/components/OutroCard.tsx`**

```tsx
import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { Caption } from "./Caption";

const LOGO_PULSE_FRAMES = 20;

export const OutroCard: React.FC<{ caption: string }> = ({ caption }) => {
  const frame = useCurrentFrame();
  const logoScale = interpolate(frame, [0, LOGO_PULSE_FRAMES], [0.8, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  return (
    <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
      <AbsoluteFill style={{ top: 0, height: "50%", alignItems: "center", justifyContent: "center" }}>
        <Img
          src={staticFile("brand/pfp-neontag-blue.png")}
          style={{
            width: "45%",
            transform: `scale(${logoScale})`,
          }}
        />
      </AbsoluteFill>
      <Caption text={caption} startFrame={0} position="bottom" />
    </AbsoluteFill>
  );
};
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd video/bfdash-commercial && npm test -- OutroCard.test.tsx`
Expected: PASS.

- [ ] **Step 6: Typecheck**

Run: `cd video/bfdash-commercial && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add video/bfdash-commercial/src/components/OutroCard.tsx video/bfdash-commercial/src/components/OutroCard.test.tsx video/bfdash-commercial/public/brand/pfp-neontag-blue.png
git commit -m "feat(video): port OutroCard component from the Short"
```

---

### Task 9: Photo assets

**Files:**
- Create: `video/bfdash-commercial/scripts/copy-photos.mjs`
- Test: `video/bfdash-commercial/scripts/copy-photos.test.mjs`

**Interfaces:**
- Consumes: the 5 processed photos already committed at `video/bfdash-short/public/photos/{rates,pids,filters-p,vtx,motor}.jpg` (full, uncropped, rotated-upright — no reprocessing needed, per the design spec's Assets section).
- Produces: `video/bfdash-commercial/public/photos/{rates,pids,filters-p,vtx,motor}.jpg` — the exact filenames `SplitBeat` (Task 6) and `scenes.ts` (Task 2) reference via `staticFile("photos/<name>.jpg")`. `tools-menu.jpg` is deliberately not copied — no scene references it (same as the Short, where it was flagged as an unused asset).

- [ ] **Step 1: Write `scripts/copy-photos.mjs`**

```js
import { copyFile, mkdir } from "node:fs/promises";
import path from "node:path";

const SOURCE_DIR = path.resolve("../bfdash-short/public/photos");
const OUT_DIR = path.resolve("public/photos");

const PHOTOS = ["rates", "pids", "filters-p", "vtx", "motor"];

async function main() {
  await mkdir(OUT_DIR, { recursive: true });

  for (const name of PHOTOS) {
    const src = path.join(SOURCE_DIR, `${name}.jpg`);
    const dest = path.join(OUT_DIR, `${name}.jpg`);
    await copyFile(src, dest);
    console.log(`${src} -> ${dest}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 2: Write the failing test `scripts/copy-photos.test.mjs`**

```js
import { describe, expect, it } from "vitest";
import { existsSync } from "node:fs";
import path from "node:path";

const OUT_DIR = path.resolve("public/photos");
const EXPECTED = ["rates", "pids", "filters-p", "vtx", "motor"];

describe("copy-photos output", () => {
  for (const name of EXPECTED) {
    it(`produces public/photos/${name}.jpg`, () => {
      expect(existsSync(path.join(OUT_DIR, `${name}.jpg`))).toBe(true);
    });
  }
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd video/bfdash-commercial && npm test -- copy-photos.test.mjs`
Expected: FAIL — all 5 files missing (`public/photos` doesn't exist yet).

- [ ] **Step 4: Run the script**

Run: `cd video/bfdash-commercial && node scripts/copy-photos.mjs`
Expected: 5 lines of `<source> -> <dest>` output, exit code 0. If it fails with "no such file" for the source path, confirm `video/bfdash-short/public/photos/` still has these 5 files committed (they were part of the Short's Task 8) before proceeding.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd video/bfdash-commercial && npm test -- copy-photos.test.mjs`
Expected: PASS — all 5 files found.

- [ ] **Step 6: Commit**

```bash
git add video/bfdash-commercial/scripts/copy-photos.mjs video/bfdash-commercial/scripts/copy-photos.test.mjs video/bfdash-commercial/public/photos
git commit -m "feat(video): copy photo assets from the Short project"
```

---

### Task 10: Audio extraction script

**Files:**
- Create: `video/bfdash-commercial/scripts/extract-audio.sh`
- Test: `video/bfdash-commercial/scripts/extract-audio.test.mjs`

**Interfaces:**
- Consumes: `C:\Drone\Music\Tame Impala - Cause I'm A Man.flac`.
- Produces: `video/bfdash-commercial/public/audio/hook-track.mp3`, exactly 45.0 seconds (±0.5s), the file Task 11's `<Audio>` element references via `staticFile("audio/hook-track.mp3")`.

- [ ] **Step 1: Write `scripts/extract-audio.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SOURCE="/c/Drone/Music/Tame Impala - Cause I'm A Man.flac"
OUT_DIR="public/audio"
OUT_FILE="$OUT_DIR/hook-track.mp3"

mkdir -p "$OUT_DIR"

ffmpeg -y -ss 00:01:11 -t 00:00:45 -i "$SOURCE" -c:a libmp3lame -q:a 2 "$OUT_FILE"

echo "Wrote $OUT_FILE"
```

- [ ] **Step 2: Write the failing test `scripts/extract-audio.test.mjs`**

```js
import { describe, expect, it } from "vitest";
import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";

const OUT_PATH = path.resolve("public/audio/hook-track.mp3");

describe("extract-audio output", () => {
  it("produces a ~45 second hook-track.mp3", () => {
    expect(existsSync(OUT_PATH)).toBe(true);
    const durationStr = execSync(
      `ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${OUT_PATH}"`,
    ).toString().trim();
    const duration = parseFloat(durationStr);
    expect(duration).toBeGreaterThan(44.5);
    expect(duration).toBeLessThan(45.5);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd video/bfdash-commercial && npm test -- extract-audio.test.mjs`
Expected: FAIL — `public/audio/hook-track.mp3` does not exist.

- [ ] **Step 4: Run the script**

Run: `cd video/bfdash-commercial && chmod +x scripts/extract-audio.sh && ./scripts/extract-audio.sh`
Expected: `Wrote public/audio/hook-track.mp3`, ffmpeg logs, exit code 0.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd video/bfdash-commercial && npm test -- extract-audio.test.mjs`
Expected: PASS — duration between 44.5s and 45.5s.

- [ ] **Step 6: Commit**

```bash
git add video/bfdash-commercial/scripts/extract-audio.sh video/bfdash-commercial/scripts/extract-audio.test.mjs video/bfdash-commercial/public/audio
git commit -m "feat(video): add audio extraction script and trimmed 45s music bed"
```

---

### Task 11: Assemble the root composition

**Files:**
- Modify: `video/bfdash-commercial/src/BFDashCommercial.tsx` (replaces the Task 1 placeholder body)
- Test: `video/bfdash-commercial/src/BFDashCommercial.render.test.ts`

**Interfaces:**
- Consumes: `scenes` from `./scenes`; `Caption` from `./components/Caption`; `BeatIcon` from `./components/BeatIcon`; `SplitBeat` from `./components/SplitBeat`; `TitleCard` from `./components/TitleCard`; `OutroCard` from `./components/OutroCard`.
- Produces: the final `BFDashCommercial` component body. No further tasks consume this — it's the render root.

- [ ] **Step 1: Replace `src/BFDashCommercial.tsx`**

```tsx
import React from "react";
import { AbsoluteFill, Audio, interpolate, Sequence, staticFile } from "remotion";
import { scenes } from "./scenes";
import { Caption } from "./components/Caption";
import { BeatIcon } from "./components/BeatIcon";
import { SplitBeat } from "./components/SplitBeat";
import { TitleCard } from "./components/TitleCard";
import { OutroCard } from "./components/OutroCard";

const CAPTION_DELAY_AFTER_ICON = 10;

export const BFDashCommercial: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
      <Audio
        src={staticFile("audio/hook-track.mp3")}
        volume={(f) =>
          interpolate(f, [1327, 1350], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })
        }
      />
      {scenes.map((scene) => (
        <Sequence key={scene.id} from={scene.startFrame} durationInFrames={scene.durationFrames}>
          {scene.type === "outro" ? (
            <OutroCard caption={scene.caption} />
          ) : scene.type === "reveal" && scene.revealVariant === "title" ? (
            <TitleCard title={scene.caption} subtitle={scene.subtitle ?? ""} />
          ) : scene.type === "reveal" && scene.revealVariant === "caption" ? (
            <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
              <Caption text={scene.caption} startFrame={0} />
            </AbsoluteFill>
          ) : scene.image ? (
            <SplitBeat
              image={scene.image}
              durationFrames={scene.durationFrames}
              calloutRect={scene.calloutRect}
              dim={scene.type === "payoff" || scene.type === "cta"}
              icon={scene.icon ? <BeatIcon icon={scene.icon} /> : undefined}
              caption={
                <Caption
                  text={scene.caption}
                  startFrame={scene.icon ? CAPTION_DELAY_AFTER_ICON : 0}
                />
              }
            />
          ) : null}
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
```

- [ ] **Step 2: Write the failing integration test `src/BFDashCommercial.render.test.ts`**

```ts
// @vitest-environment node
import { describe, expect, it } from "vitest";
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import path from "node:path";
import { existsSync, mkdirSync } from "node:fs";

// One sample at the exact midpoint of every scene in src/scenes.ts, so
// every beat type gets covered by construction (not by picking round
// numbers and hoping they land in the right range):
//   hook 0-180 -> 90
//   reveal-caption 180-255 -> 217
//   reveal-title 255-360 -> 307
//   feature-pids-sliders 360-473 -> 416
//   feature-pids-numbers 473-585 -> 529
//   feature-rates-data 585-698 -> 641
//   feature-filters 698-810 -> 754
//   feature-vtx 810-923 -> 866
//   feature-motor 923-1035 -> 979
//   payoff 1035-1170 -> 1102
//   cta 1170-1260 -> 1215
//   outro 1260-1350 -> 1305
const SAMPLE_FRAMES = [90, 217, 307, 416, 529, 641, 754, 866, 979, 1102, 1215, 1305];

describe("BFDashCommercial render", () => {
  it("renders every sample frame without throwing", async () => {
    const bundled = await bundle({ entryPoint: path.resolve("src/index.ts") });
    const composition = await selectComposition({ serveUrl: bundled, id: "BFDashCommercial" });

    const outDir = path.resolve("out/frame-samples");
    mkdirSync(outDir, { recursive: true });

    for (const frame of SAMPLE_FRAMES) {
      const outPath = path.join(outDir, `frame-${frame}.png`);
      await renderStill({ composition, serveUrl: bundled, frame, output: outPath });
      expect(existsSync(outPath)).toBe(true);
    }
  }, 180_000);
});
```

If `src/scenes.ts`'s actual `startFrame`/`durationFrames` values differ from what's shown above (e.g. this task is executed out of order, or Task 2 changed), recompute the midpoints from the real values rather than trusting this comment.

- [ ] **Step 3: Install the bundler dependency and run the test**

Run: `cd video/bfdash-commercial && npm install --save-dev @remotion/bundler && npm test -- BFDashCommercial.render.test.ts`
Expected: PASS — 12 PNG files created under `out/frame-samples/`. If it fails, read the error: a missing asset reference or prop mismatch is a real bug to fix (check the exact `staticFile` paths against what Tasks 9/10 actually produced), not an environment problem to work around.

- [ ] **Step 4: Manual visual check**

Open all 12 PNGs in `video/bfdash-commercial/out/frame-samples/` (one per beat) and confirm, for each: the frames sampling `hook`/feature/`payoff`/`cta` scenes show the full uncropped photo on the LEFT half (no cropping, letterboxed top/bottom) and the icon (where applicable) + caption on the RIGHT half, with the callout box (where applicable) drawn around the correct data in the photo; the frame sampling `reveal-title` shows the "BFDash" title card centered and legible at 16:9; the frame sampling `outro` shows the logo in the top half and subscribe text in the bottom half, both legible at 16:9. If a callout box looks misaligned, adjust that scene's `calloutRect` in `src/scenes.ts` and re-run Step 3 — but note these values were copied verbatim from the already-verified Short, so a misalignment here would mean the `PHOTO_DISPLAY_RECT` math in `SplitBeat.tsx` is wrong, not the callout data; check that first.

- [ ] **Step 5: Run the full test suite**

Run: `cd video/bfdash-commercial && npm test`
Expected: PASS — every test file from Tasks 1–11 green.

- [ ] **Step 6: Commit**

```bash
git add video/bfdash-commercial/src/BFDashCommercial.tsx video/bfdash-commercial/src/BFDashCommercial.render.test.ts video/bfdash-commercial/package.json video/bfdash-commercial/package-lock.json
git commit -m "feat(video): assemble BFDashCommercial composition from scene config"
```

---

### Task 12: Final render

**Files:** none created or modified — this task produces the deliverable video file.

**Interfaces:** none — terminal task.

- [ ] **Step 1: Render the final video**

Run: `cd video/bfdash-commercial && npm run build`
Expected: Remotion renders all 1350 frames and writes `out/bfdash-commercial.mp4`, exiting 0.

- [ ] **Step 2: Confirm output**

Run: `ffprobe -v quiet -show_entries format=duration,stream=width,height -of default=noprint_wrappers=1 video/bfdash-commercial/out/bfdash-commercial.mp4`
Expected: `duration=45.0...`, `width=3840`, `height=2160`.

- [ ] **Step 3: Broader frame sanity check**

Extract ~15 evenly-spaced stills across the full timeline (e.g. every 90 frames: 0, 90, 180, ..., 1260) with ffmpeg into a scratch directory, and open each with the Read tool. For every one, confirm: no photo content is cropped (full image visible, left half), text on the right half is readable and not clipped, no beat shows a black/empty frame. This is a broader check than Step 4's 9 targeted samples from Task 11 — it exists to catch anything only visible at a timestamp neither of you picked in advance.

- [ ] **Step 4: Human review**

Watch the full rendered video with audio. This is the final acceptance check — confirm the music plays cleanly under the whole 45s with the fade-out landing smoothly at the end, the left/right layout reads well at a normal viewing distance, and nothing feels rushed or cropped. There is no automated substitute for this step.
