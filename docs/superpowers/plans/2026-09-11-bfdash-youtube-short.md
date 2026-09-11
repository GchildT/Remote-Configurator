# BFDash YouTube Short Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a 30-second, 4K-vertical Remotion video announcing BFDash, driven by a data-driven scene config, real radio-screen photos, and a licensed-in-name-only Tame Impala clip.

**Architecture:** A standalone Remotion project (`video/bfdash-short/`) with one root composition (`BFDashShort`) that maps a single `scenes.ts` array to `<Sequence>` blocks. Each scene renders one of five small, independently-tested components (`Caption`, `CalloutBox`, `PhotoBeat`, `TitleCard`, `OutroCard`). Animation math (easing, stagger, zoom curves) lives in co-located `*.timing.ts` pure functions so it can be unit-tested with Vitest without a Remotion rendering context; components stay thin wrappers around that math.

**Tech Stack:** Remotion 4.x, React 18, TypeScript, Vitest + @testing-library/react for component tests, `sharp` for one-time photo pre-processing, `ffmpeg`/`ffprobe` (already used elsewhere in this environment) for audio trimming and verification.

## Global Constraints

- Composition: 2160×3840 (4K vertical), 30fps, 900 frames total (30 seconds) — per [design spec](../specs/2026-09-11-bfdash-youtube-short-design.md#format).
- Captions/on-screen text only — no voiceover — per [design spec](../specs/2026-09-11-bfdash-youtube-short-design.md#format).
- Music bed is `C:\Drone\Music\Tame Impala - Cause I'm A Man.flac`, trimmed to exactly 1:11–1:41 (30.000s) — per [design spec](../specs/2026-09-11-bfdash-youtube-short-design.md#audio). No SFX assets exist yet (Epidemic Sound connector is down); the audio Sequence structure must leave room for an `sfx` field to be added later, but no SFX files are wired in this plan.
- Source photos live in `C:\Users\gchil\Downloads\Compressed\Photos-1-001_2\` and must be copied/renamed into the Remotion project, not read from that external path at render time.
- Brand asset used throughout: `C:\Drone\DirtyNach0s_FPV\branding\output\splash_neontag_blue.png` and `pfp_neontag_blue.png` (blue neon-tag variant only) — per [design spec](../specs/2026-09-11-bfdash-youtube-short-design.md#visual--animation-style).
- **Interpretation note (not in the spec, decided here for implementability):** the design spec's beat table doesn't assign a distinct photo to the Payoff (0:23–0:26) or CTA (0:26–0:28) beats. This plan has those two beats continue on the `motor.jpg` photo (the last feature-rip image) as one held, slowly-zooming background with an intensified dim/vignette so caption text stays legible — i.e. one cut into that photo at 0:23, no further cuts until the Outro at 0:28.
- Exact caption copy, per beat, is fixed by the design spec's [Caption Copy](../specs/2026-09-11-bfdash-youtube-short-design.md#feature-rip-beats-in-order) section and reproduced verbatim in Task 2's `scenes.ts`.

---

## File Structure

```
video/bfdash-short/
  package.json
  tsconfig.json
  remotion.config.ts
  vitest.config.ts
  scripts/
    prepare-photos.mjs       # Task 8: one-time photo rotate/crop/grade pass
    extract-audio.sh         # Task 9: one-time ffmpeg trim of the music bed
  public/
    photos/                  # Task 8 output: tools-menu.jpg, pids.jpg, rates.jpg,
                              #   filters-p.jpg, vtx.jpg, motor.jpg
    audio/
      hook-track.mp3          # Task 9 output: trimmed 30s Tame Impala clip
    brand/
      splash-neontag-blue.png # Task 6 input, copied from the branding output folder
  src/
    index.ts                 # Task 1: registerRoot
    Root.tsx                 # Task 1: <Composition> registration
    BFDashShort.tsx           # Task 1 (placeholder) -> Task 10 (final assembly)
    scenes.ts                 # Task 2: the data-driven scene array + types
    scenes.test.ts            # Task 2
    components/
      Caption.tsx              # Task 3
      Caption.timing.ts         # Task 3
      Caption.timing.test.ts    # Task 3
      CalloutBox.tsx            # Task 4
      CalloutBox.timing.ts      # Task 4
      CalloutBox.timing.test.ts # Task 4
      PhotoBeat.tsx             # Task 5
      PhotoBeat.timing.ts       # Task 5
      PhotoBeat.timing.test.ts  # Task 5
      TitleCard.tsx             # Task 6
      TitleCard.test.tsx        # Task 6
      OutroCard.tsx             # Task 7
      OutroCard.test.tsx        # Task 7
  out/
    bfdash-short.mp4          # Task 11 final render output (git-ignored)
```

---

### Task 1: Project scaffold + smoke test

**Files:**
- Create: `video/bfdash-short/package.json`
- Create: `video/bfdash-short/tsconfig.json`
- Create: `video/bfdash-short/remotion.config.ts`
- Create: `video/bfdash-short/vitest.config.ts`
- Create: `video/bfdash-short/.gitignore`
- Create: `video/bfdash-short/src/index.ts`
- Create: `video/bfdash-short/src/Root.tsx`
- Create: `video/bfdash-short/src/BFDashShort.tsx`
- Test: `video/bfdash-short/src/BFDashShort.test.tsx`

**Interfaces:**
- Produces: `BFDashShort` — a `React.FC` with no required props, registered as composition id `"BFDashShort"`, 2160×3840, 30fps, 900 frames. All later tasks (2–10) build up this component's internals; Task 10 is the only task that edits its body again after this one.

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "bfdash-short",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "remotion studio",
    "build": "remotion render BFDashShort out/bfdash-short.mp4",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "remotion": "^4.0.0",
    "@remotion/cli": "^4.0.0"
  },
  "devDependencies": {
    "@remotion/renderer": "^4.0.0",
    "@testing-library/react": "^16.0.0",
    "@types/node": "^20.0.0",
    "@types/react": "^18.3.0",
    "@types/react-dom": "^18.3.0",
    "jsdom": "^25.0.0",
    "sharp": "^0.33.0",
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
  },
});
```

- [ ] **Step 5: Write `.gitignore`**

```
node_modules
out
.remotion
```

- [ ] **Step 6: Write `src/index.ts`**

```ts
import { registerRoot } from "remotion";
import { RemotionRoot } from "./Root";

registerRoot(RemotionRoot);
```

- [ ] **Step 7: Write `src/BFDashShort.tsx` (placeholder body, replaced in Task 10)**

```tsx
import React from "react";
import { AbsoluteFill } from "remotion";

export const BFDashShort: React.FC = () => {
  return <AbsoluteFill style={{ backgroundColor: "#05070d" }} />;
};
```

- [ ] **Step 8: Write `src/Root.tsx`**

```tsx
import React from "react";
import { Composition } from "remotion";
import { BFDashShort } from "./BFDashShort";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="BFDashShort"
      component={BFDashShort}
      durationInFrames={900}
      fps={30}
      width={2160}
      height={3840}
    />
  );
};
```

- [ ] **Step 9: Write the failing smoke test `src/BFDashShort.test.tsx`**

```tsx
import { describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { BFDashShort } from "./BFDashShort";

describe("BFDashShort", () => {
  it("renders without throwing", () => {
    const { container } = render(<BFDashShort />);
    expect(container.firstChild).not.toBeNull();
  });
});
```

- [ ] **Step 10: Install dependencies**

Run: `cd video/bfdash-short && npm install`
Expected: installs succeed, `node_modules` created, no error output.

- [ ] **Step 11: Run the test to verify it passes**

Run: `cd video/bfdash-short && npm test`
Expected: PASS — `BFDashShort > renders without throwing`

- [ ] **Step 12: Typecheck**

Run: `cd video/bfdash-short && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 13: Commit**

```bash
git add video/bfdash-short
git commit -m "feat(video): scaffold bfdash-short Remotion project"
```

---

### Task 2: Scene data config

**Files:**
- Create: `video/bfdash-short/src/scenes.ts`
- Test: `video/bfdash-short/src/scenes.test.ts`

**Interfaces:**
- Produces: `SceneType` (union type), `FocalPoint`, `CalloutRect`, `Scene` interface, and the exported `scenes: Scene[]` array. Tasks 3–7 render individual `Scene` objects; Task 10 consumes the full `scenes` array to build `<Sequence>` blocks.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { scenes } from "./scenes";

describe("scenes", () => {
  it("covers exactly 900 frames with no gaps or overlaps, in order", () => {
    let expectedStart = 0;
    for (const scene of scenes) {
      expect(scene.startFrame).toBe(expectedStart);
      expect(scene.durationFrames).toBeGreaterThan(0);
      expectedStart += scene.durationFrames;
    }
    expect(expectedStart).toBe(900);
  });

  it("gives every scene a non-empty caption", () => {
    for (const scene of scenes) {
      expect(scene.caption.length).toBeGreaterThan(0);
    }
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd video/bfdash-short && npm test -- scenes.test.ts`
Expected: FAIL with "Cannot find module './scenes'" (file doesn't exist yet).

- [ ] **Step 3: Write `src/scenes.ts`**

```ts
export type SceneType = "hook" | "reveal" | "feature" | "payoff" | "cta" | "outro";
export type RevealVariant = "caption" | "title";

export interface FocalPoint {
  xPct: number;
  yPct: number;
}

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
  focalPoint?: FocalPoint;
  calloutRect?: CalloutRect;
  revealVariant?: RevealVariant;
}

export const scenes: Scene[] = [
  {
    id: "hook",
    type: "hook",
    startFrame: 0,
    durationFrames: 120,
    image: "photos/rates.jpg",
    caption: "Tired of tabbing between goggles and Betaflight mid-tune?",
    focalPoint: { xPct: 50, yPct: 50 },
  },
  {
    id: "reveal-caption",
    type: "reveal",
    revealVariant: "caption",
    startFrame: 120,
    durationFrames: 50,
    caption: "So I vibe-coded my own LUA app.",
  },
  {
    id: "reveal-title",
    type: "reveal",
    revealVariant: "title",
    startFrame: 170,
    durationFrames: 70,
    caption: "BFDash",
    subtitle: "Remote Betaflight Configuration Dashboard",
  },
  {
    id: "feature-pids-sliders",
    type: "feature",
    startFrame: 240,
    durationFrames: 75,
    image: "photos/pids.jpg",
    caption: "8 PID tuning sliders \u2014 matched to Configurator",
    focalPoint: { xPct: 30, yPct: 50 },
    calloutRect: { xPct: 5, yPct: 20, wPct: 45, hPct: 60 },
  },
  {
    id: "feature-pids-numbers",
    type: "feature",
    startFrame: 315,
    durationFrames: 75,
    image: "photos/pids.jpg",
    caption: "Live P / I / D / D-Min / FF preview",
    focalPoint: { xPct: 72, yPct: 45 },
    calloutRect: { xPct: 50, yPct: 15, wPct: 45, hPct: 70 },
  },
  {
    id: "feature-rates-data",
    type: "feature",
    startFrame: 390,
    durationFrames: 75,
    image: "photos/rates.jpg",
    caption: "All 4 rate types, every axis",
    focalPoint: { xPct: 50, yPct: 65 },
    calloutRect: { xPct: 15, yPct: 45, wPct: 70, hPct: 45 },
  },
  {
    id: "feature-filters",
    type: "feature",
    startFrame: 465,
    durationFrames: 75,
    image: "photos/filters-p.jpg",
    caption: "Gyro + D-term filters \u2014 global & per-profile",
    focalPoint: { xPct: 50, yPct: 45 },
    calloutRect: { xPct: 10, yPct: 15, wPct: 80, hPct: 70 },
  },
  {
    id: "feature-vtx",
    type: "feature",
    startFrame: 540,
    durationFrames: 75,
    image: "photos/vtx.jpg",
    caption: "Band, channel, power",
    focalPoint: { xPct: 40, yPct: 70 },
    calloutRect: { xPct: 10, yPct: 60, wPct: 60, hPct: 30 },
  },
  {
    id: "feature-motor",
    type: "feature",
    startFrame: 615,
    durationFrames: 75,
    image: "photos/motor.jpg",
    caption: "Throttle boost, idle, sag comp",
    focalPoint: { xPct: 50, yPct: 45 },
    calloutRect: { xPct: 10, yPct: 25, wPct: 80, hPct: 55 },
  },
  {
    id: "payoff",
    type: "payoff",
    startFrame: 690,
    durationFrames: 90,
    image: "photos/motor.jpg",
    caption: "Change it in the field.\nNo goggles. No laptop. No USB.",
    focalPoint: { xPct: 50, yPct: 45 },
  },
  {
    id: "cta",
    type: "cta",
    startFrame: 780,
    durationFrames: 60,
    image: "photos/motor.jpg",
    caption: "Tested on Jumper T15 & RadioMaster TX15 \u2014\ntry it, tell me what breaks.",
    focalPoint: { xPct: 50, yPct: 45 },
  },
  {
    id: "outro",
    type: "outro",
    startFrame: 840,
    durationFrames: 60,
    caption: "Subscribe for more FPV builds & tuning\nLink in bio \u00b7 comments open",
  },
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd video/bfdash-short && npm test -- scenes.test.ts`
Expected: PASS — both `scenes` tests green.

- [ ] **Step 5: Commit**

```bash
git add video/bfdash-short/src/scenes.ts video/bfdash-short/src/scenes.test.ts
git commit -m "feat(video): add data-driven scene config for BFDash short"
```

---

### Task 3: Caption component

**Files:**
- Create: `video/bfdash-short/src/components/Caption.timing.ts`
- Create: `video/bfdash-short/src/components/Caption.tsx`
- Test: `video/bfdash-short/src/components/Caption.timing.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `getWordStyle(frame: number, wordStartFrame: number): { opacity: number; translateY: number; scale: number }` and `splitIntoLines(caption: string): string[][]` (each inner array is the words of one line, `\n` in the source string splits lines) from `Caption.timing.ts`. `Caption` component: `React.FC<{ text: string; startFrame: number }>` — renders one caption block whose words pop in relative to `startFrame`. Tasks 5, 6, 7 all render `<Caption text={scene.caption} startFrame={0} />` inside their own `<Sequence from={scene.startFrame}>`, so `startFrame` is always relative (0 unless a sub-delay is needed).

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

Run: `cd video/bfdash-short && npm test -- Caption.timing.test.ts`
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

Run: `cd video/bfdash-short && npm test -- Caption.timing.test.ts`
Expected: PASS — all 4 tests green.

- [ ] **Step 5: Write `src/components/Caption.tsx`**

```tsx
import React from "react";
import { useCurrentFrame } from "remotion";
import { getWordStartFrame, getWordStyle, splitIntoLines } from "./Caption.timing";

export const Caption: React.FC<{ text: string; startFrame: number }> = ({ text, startFrame }) => {
  const frame = useCurrentFrame() - startFrame;
  const lines = splitIntoLines(text);
  let wordsBeforeThisLine = 0;

  return (
    <div
      style={{
        position: "absolute",
        left: "8%",
        right: "8%",
        bottom: "12%",
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

Run: `cd video/bfdash-short && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add video/bfdash-short/src/components/Caption.timing.ts video/bfdash-short/src/components/Caption.timing.test.ts video/bfdash-short/src/components/Caption.tsx
git commit -m "feat(video): add word-pop-in Caption component"
```

---

### Task 4: CalloutBox component

**Files:**
- Create: `video/bfdash-short/src/components/CalloutBox.timing.ts`
- Create: `video/bfdash-short/src/components/CalloutBox.tsx`
- Test: `video/bfdash-short/src/components/CalloutBox.timing.test.ts`

**Interfaces:**
- Consumes: `CalloutRect` type from `../scenes`.
- Produces: `getCalloutOpacity(frame: number, durationFrames: number): number` and `getCalloutScale(frame: number, durationFrames: number): number` from `CalloutBox.timing.ts`. `CalloutBox` component: `React.FC<{ rect: CalloutRect; durationFrames: number }>`, expected to be rendered as a child of `PhotoBeat` (Task 5) inside the same `<Sequence>`, so its internal `useCurrentFrame()` is already relative to the beat's start.

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

Run: `cd video/bfdash-short && npm test -- CalloutBox.timing.test.ts`
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

Run: `cd video/bfdash-short && npm test -- CalloutBox.timing.test.ts`
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

Run: `cd video/bfdash-short && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add video/bfdash-short/src/components/CalloutBox.timing.ts video/bfdash-short/src/components/CalloutBox.timing.test.ts video/bfdash-short/src/components/CalloutBox.tsx
git commit -m "feat(video): add glowing CalloutBox component"
```

---

### Task 5: PhotoBeat component

**Files:**
- Create: `video/bfdash-short/src/components/PhotoBeat.timing.ts`
- Create: `video/bfdash-short/src/components/PhotoBeat.tsx`
- Test: `video/bfdash-short/src/components/PhotoBeat.timing.test.ts`

**Interfaces:**
- Consumes: `FocalPoint`, `CalloutRect` from `../scenes`; `CalloutBox` from `./CalloutBox`.
- Produces: `getKenBurnsScale(frame: number, durationFrames: number): number` from `PhotoBeat.timing.ts`. `PhotoBeat` component: `React.FC<{ image: string; durationFrames: number; focalPoint: FocalPoint; calloutRect?: CalloutRect }>`. Task 10 renders one `PhotoBeat` per hook/feature/payoff/cta scene, inside a `<Sequence from={scene.startFrame} durationInFrames={scene.durationFrames}>`.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { getKenBurnsScale } from "./PhotoBeat.timing";

describe("getKenBurnsScale", () => {
  it("starts at 1.0", () => {
    expect(getKenBurnsScale(0, 75)).toBeCloseTo(1.0, 3);
  });

  it("ends at 1.08", () => {
    expect(getKenBurnsScale(75, 75)).toBeCloseTo(1.08, 3);
  });

  it("is strictly increasing partway through", () => {
    const early = getKenBurnsScale(10, 75);
    const late = getKenBurnsScale(60, 75);
    expect(late).toBeGreaterThan(early);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd video/bfdash-short && npm test -- PhotoBeat.timing.test.ts`
Expected: FAIL with "Cannot find module './PhotoBeat.timing'".

- [ ] **Step 3: Write `src/components/PhotoBeat.timing.ts`**

```ts
import { Easing, interpolate } from "remotion";

export const KEN_BURNS_START_SCALE = 1.0;
export const KEN_BURNS_END_SCALE = 1.08;

export const getKenBurnsScale = (frame: number, durationFrames: number): number => {
  return interpolate(frame, [0, durationFrames], [KEN_BURNS_START_SCALE, KEN_BURNS_END_SCALE], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd video/bfdash-short && npm test -- PhotoBeat.timing.test.ts`
Expected: PASS — all 3 tests green.

- [ ] **Step 5: Write `src/components/PhotoBeat.tsx`**

```tsx
import React from "react";
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import type { CalloutRect, FocalPoint } from "../scenes";
import { CalloutBox } from "./CalloutBox";
import { getKenBurnsScale } from "./PhotoBeat.timing";

export const PhotoBeat: React.FC<{
  image: string;
  durationFrames: number;
  focalPoint: FocalPoint;
  calloutRect?: CalloutRect;
  dim?: boolean;
}> = ({ image, durationFrames, focalPoint, calloutRect, dim = false }) => {
  const frame = useCurrentFrame();
  const scale = getKenBurnsScale(frame, durationFrames);

  return (
    <AbsoluteFill style={{ overflow: "hidden", backgroundColor: "#05070d" }}>
      <Img
        src={staticFile(image)}
        style={{
          position: "absolute",
          width: "100%",
          height: "100%",
          objectFit: "cover",
          objectPosition: `${focalPoint.xPct}% ${focalPoint.yPct}%`,
          transform: `scale(${scale})`,
          filter: "contrast(1.12) saturate(1.08) brightness(0.92)",
        }}
      />
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(circle at 50% 45%, rgba(0,0,0,0) 40%, rgba(0,5,15,0.85) 100%)",
        }}
      />
      {dim && (
        <AbsoluteFill style={{ backgroundColor: "rgba(2, 6, 15, 0.55)" }} />
      )}
      {calloutRect && <CalloutBox rect={calloutRect} durationFrames={durationFrames} />}
    </AbsoluteFill>
  );
};
```

- [ ] **Step 6: Typecheck**

Run: `cd video/bfdash-short && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add video/bfdash-short/src/components/PhotoBeat.timing.ts video/bfdash-short/src/components/PhotoBeat.timing.test.ts video/bfdash-short/src/components/PhotoBeat.tsx
git commit -m "feat(video): add Ken-Burns PhotoBeat component"
```

---

### Task 6: TitleCard component

**Files:**
- Create: `video/bfdash-short/src/components/TitleCard.tsx`
- Test: `video/bfdash-short/src/components/TitleCard.test.tsx`
- Copy: `C:\Drone\DirtyNach0s_FPV\branding\output\splash_neontag_blue.png` to `video/bfdash-short/public/brand/splash-neontag-blue.png`

**Interfaces:**
- Consumes: nothing from earlier tasks (self-contained; does not use `Caption` because its word-pop timing doesn't fit a two-part logo+subtitle reveal).
- Produces: `TitleCard` component: `React.FC<{ title: string; subtitle: string }>`. Task 10 renders this for the `reveal-title` scene, inside its own `<Sequence>`.

- [ ] **Step 1: Copy the brand asset**

Run: `mkdir -p video/bfdash-short/public/brand && cp "/c/Drone/DirtyNach0s_FPV/branding/output/splash_neontag_blue.png" video/bfdash-short/public/brand/splash-neontag-blue.png`
Expected: file copied, no error.

- [ ] **Step 2: Write the failing test**

```tsx
import { describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { TitleCard } from "./TitleCard";

describe("TitleCard", () => {
  it("renders the title and subtitle text", () => {
    const { getByText } = render(<TitleCard title="BFDash" subtitle="Remote Betaflight Configuration Dashboard" />);
    expect(getByText("BFDash")).not.toBeNull();
    expect(getByText("Remote Betaflight Configuration Dashboard")).not.toBeNull();
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd video/bfdash-short && npm test -- TitleCard.test.tsx`
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
          width: "70%",
          opacity: logoProgress,
          transform: `scale(${interpolate(logoProgress, [0, 1], [0.85, 1])})`,
        }}
      />
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
      <div style={{ position: "absolute", opacity: 0, height: 0, overflow: "hidden" }}>{title}</div>
    </AbsoluteFill>
  );
};
```

Note: `title` is rendered off-screen (visually hidden) because the visible brand wordmark already spells "BFDash" inside `splash-neontag-blue.png`; the prop is kept so the test (and Task 10's caller) can assert the right title string flows into this scene without duplicating the wordmark as separate on-screen text.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd video/bfdash-short && npm test -- TitleCard.test.tsx`
Expected: PASS.

- [ ] **Step 6: Typecheck**

Run: `cd video/bfdash-short && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add video/bfdash-short/src/components/TitleCard.tsx video/bfdash-short/src/components/TitleCard.test.tsx video/bfdash-short/public/brand/splash-neontag-blue.png
git commit -m "feat(video): add BFDash TitleCard reveal component"
```

---

### Task 7: OutroCard component

**Files:**
- Create: `video/bfdash-short/src/components/OutroCard.tsx`
- Test: `video/bfdash-short/src/components/OutroCard.test.tsx`
- Copy: `C:\Drone\DirtyNach0s_FPV\branding\output\pfp_neontag_blue.png` to `video/bfdash-short/public/brand/pfp-neontag-blue.png`

**Interfaces:**
- Consumes: `Caption` from `./Caption`.
- Produces: `OutroCard` component: `React.FC<{ caption: string }>`. Task 10 renders this for the `outro` scene.

- [ ] **Step 1: Copy the brand asset**

Run: `cp "/c/Drone/DirtyNach0s_FPV/branding/output/pfp_neontag_blue.png" video/bfdash-short/public/brand/pfp-neontag-blue.png`
Expected: file copied, no error.

- [ ] **Step 2: Write the failing test**

```tsx
import { describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { OutroCard } from "./OutroCard";

describe("OutroCard", () => {
  it("renders both outro lines", () => {
    const { getByText } = render(
      <OutroCard caption={"Subscribe for more FPV builds & tuning\nLink in bio \u00b7 comments open"} />,
    );
    expect(getByText("Subscribe")).not.toBeNull();
    expect(getByText("open")).not.toBeNull();
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd video/bfdash-short && npm test -- OutroCard.test.tsx`
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
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", top: "-15%" }}>
        <Img
          src={staticFile("brand/pfp-neontag-blue.png")}
          style={{
            width: "45%",
            transform: `scale(${logoScale})`,
          }}
        />
      </AbsoluteFill>
      <Caption text={caption} startFrame={0} />
    </AbsoluteFill>
  );
};
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd video/bfdash-short && npm test -- OutroCard.test.tsx`
Expected: PASS.

- [ ] **Step 6: Typecheck**

Run: `cd video/bfdash-short && npm run typecheck`
Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add video/bfdash-short/src/components/OutroCard.tsx video/bfdash-short/src/components/OutroCard.test.tsx video/bfdash-short/public/brand/pfp-neontag-blue.png
git commit -m "feat(video): add OutroCard logo + subscribe component"
```

---

### Task 8: Photo pre-processing script

**Files:**
- Create: `video/bfdash-short/scripts/prepare-photos.mjs`
- Test: `video/bfdash-short/scripts/prepare-photos.test.mjs`

**Interfaces:**
- Consumes: source photos from `C:\Users\gchil\Downloads\Compressed\Photos-1-001_2\`.
- Produces: `video/bfdash-short/public/photos/{tools-menu,pids,rates,filters-p,vtx,motor}.jpg` — the exact filenames `PhotoBeat` (Task 5) and `scenes.ts` (Task 2) reference via `staticFile("photos/<name>.jpg")`.

This script's rotate angle and crop percentages are first-pass values based on visual inspection of the source photos (all 8 are phone photos of the radio screen shot with the phone rotated 90°, landscape screen content, portrait 3000x4000 frame). They are verified and adjusted in Step 4 below, not left as guesses.

- [ ] **Step 1: Write `scripts/prepare-photos.mjs`**

```js
import sharp from "sharp";
import { mkdir } from "node:fs/promises";
import path from "node:path";

const SOURCE_DIR = "C:/Users/gchil/Downloads/Compressed/Photos-1-001_2";
const OUT_DIR = path.resolve("public/photos");

// { output filename (without .jpg): [source filename, rotation degrees clockwise] }
const PHOTOS = {
  "tools-menu": ["IMG20260911082542.jpg", 90],
  "pids": ["IMG20260911082554.jpg", 90],
  "rates": ["IMG20260911082608.jpg", 90],
  "filters-p": ["IMG20260911082634.jpg", 90],
  "vtx": ["IMG20260911082643.jpg", 90],
  "motor": ["IMG20260911082653.jpg", 90],
};

async function main() {
  await mkdir(OUT_DIR, { recursive: true });

  for (const [outName, [sourceName, rotation]] of Object.entries(PHOTOS)) {
    const sourcePath = path.join(SOURCE_DIR, sourceName);
    const outPath = path.join(OUT_DIR, `${outName}.jpg`);

    await sharp(sourcePath)
      .rotate(rotation)
      .resize({ width: 3840, withoutEnlargement: true })
      .jpeg({ quality: 92 })
      .toFile(outPath);

    console.log(`${sourceName} -> ${outName}.jpg (rotated ${rotation}deg)`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 2: Write the failing test `scripts/prepare-photos.test.mjs`**

```js
import { describe, expect, it } from "vitest";
import { existsSync } from "node:fs";
import path from "node:path";

const OUT_DIR = path.resolve("public/photos");
const EXPECTED = ["tools-menu", "pids", "rates", "filters-p", "vtx", "motor"];

describe("prepare-photos output", () => {
  for (const name of EXPECTED) {
    it(`produces public/photos/${name}.jpg`, () => {
      expect(existsSync(path.join(OUT_DIR, `${name}.jpg`))).toBe(true);
    });
  }
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd video/bfdash-short && npm test -- prepare-photos.test.mjs`
Expected: FAIL — all 6 files missing (`public/photos` doesn't exist yet).

- [ ] **Step 4: Run the script, then visually verify orientation**

Run: `cd video/bfdash-short && node scripts/prepare-photos.mjs`

Then open each of the 6 output files in `video/bfdash-short/public/photos/` (e.g. with the Windows Photos app or VS Code's image preview) and confirm the on-screen radio text reads upright and left-to-right, not sideways or upside-down. If any file is rotated wrong, change that file's rotation degrees in the `PHOTOS` map (try `-90` or `180` instead of `90`) and re-run the script — sharp's `.rotate(n)` accepts negative values and normalizes them.

Expected after verification: all 6 images show the radio screen upright, tab bar (PIDs/Rates/Filters(G)/Filters(P)/VTX/Motor) reading horizontally.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd video/bfdash-short && npm test -- prepare-photos.test.mjs`
Expected: PASS — all 6 files found.

- [ ] **Step 6: Commit**

```bash
git add video/bfdash-short/scripts/prepare-photos.mjs video/bfdash-short/scripts/prepare-photos.test.mjs video/bfdash-short/public/photos
git commit -m "feat(video): add photo pre-processing script and processed stills"
```

---

### Task 9: Audio extraction script

**Files:**
- Create: `video/bfdash-short/scripts/extract-audio.sh`
- Test: `video/bfdash-short/scripts/extract-audio.test.mjs`

**Interfaces:**
- Consumes: `C:\Drone\Music\Tame Impala - Cause I'm A Man.flac`.
- Produces: `video/bfdash-short/public/audio/hook-track.mp3`, exactly 30.0 seconds (±0.1s), the file Task 10's `<Audio>` element references via `staticFile("audio/hook-track.mp3")`.

- [ ] **Step 1: Write `scripts/extract-audio.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SOURCE="/c/Drone/Music/Tame Impala - Cause I'm A Man.flac"
OUT_DIR="public/audio"
OUT_FILE="$OUT_DIR/hook-track.mp3"

mkdir -p "$OUT_DIR"

ffmpeg -y -ss 00:01:11 -t 00:00:30 -i "$SOURCE" -c:a libmp3lame -q:a 2 "$OUT_FILE"

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
  it("produces a ~30 second hook-track.mp3", () => {
    expect(existsSync(OUT_PATH)).toBe(true);
    const durationStr = execSync(
      `ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${OUT_PATH}"`,
    ).toString().trim();
    const duration = parseFloat(durationStr);
    expect(duration).toBeGreaterThan(29.5);
    expect(duration).toBeLessThan(30.5);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd video/bfdash-short && npm test -- extract-audio.test.mjs`
Expected: FAIL — `public/audio/hook-track.mp3` does not exist.

- [ ] **Step 4: Run the script**

Run: `cd video/bfdash-short && chmod +x scripts/extract-audio.sh && ./scripts/extract-audio.sh`
Expected: `Wrote public/audio/hook-track.mp3`, ffmpeg logs, exit code 0.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd video/bfdash-short && npm test -- extract-audio.test.mjs`
Expected: PASS — duration between 29.5s and 30.5s.

- [ ] **Step 6: Commit**

```bash
git add video/bfdash-short/scripts/extract-audio.sh video/bfdash-short/scripts/extract-audio.test.mjs video/bfdash-short/public/audio
git commit -m "feat(video): add audio extraction script and trimmed music bed"
```

---

### Task 10: Assemble the root composition

**Files:**
- Modify: `video/bfdash-short/src/BFDashShort.tsx` (replaces the Task 1 placeholder body)
- Test: `video/bfdash-short/src/BFDashShort.render.test.ts`

**Interfaces:**
- Consumes: `scenes` from `./scenes`; `Caption` from `./components/Caption`; `PhotoBeat` from `./components/PhotoBeat`; `TitleCard` from `./components/TitleCard`; `OutroCard` from `./components/OutroCard`.
- Produces: the final `BFDashShort` component body. No further tasks consume this — it's the render root.

- [ ] **Step 1: Replace `src/BFDashShort.tsx`**

```tsx
import React from "react";
import { AbsoluteFill, Audio, Sequence, staticFile } from "remotion";
import { scenes } from "./scenes";
import { Caption } from "./components/Caption";
import { PhotoBeat } from "./components/PhotoBeat";
import { TitleCard } from "./components/TitleCard";
import { OutroCard } from "./components/OutroCard";

export const BFDashShort: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
      <Audio src={staticFile("audio/hook-track.mp3")} />
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
          ) : scene.image && scene.focalPoint ? (
            <>
              <PhotoBeat
                image={scene.image}
                durationFrames={scene.durationFrames}
                focalPoint={scene.focalPoint}
                calloutRect={scene.calloutRect}
                dim={scene.type === "payoff" || scene.type === "cta"}
              />
              <Caption text={scene.caption} startFrame={0} />
            </>
          ) : null}
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
```

- [ ] **Step 2: Write the failing integration test `src/BFDashShort.render.test.ts`**

This renders real frames through `@remotion/renderer` to catch anything the component-level unit tests can't (missing static assets, a scene with no matching render branch, a crash only at a specific frame).

```ts
import { describe, expect, it } from "vitest";
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import path from "node:path";
import { existsSync, mkdirSync } from "node:fs";

const SAMPLE_FRAMES = [0, 150, 400, 700, 850, 899];

describe("BFDashShort render", () => {
  it("renders every sample frame without throwing", async () => {
    const bundled = await bundle({ entryPoint: path.resolve("src/index.ts") });
    const composition = await selectComposition({ serveUrl: bundled, id: "BFDashShort" });

    const outDir = path.resolve("out/frame-samples");
    mkdirSync(outDir, { recursive: true });

    for (const frame of SAMPLE_FRAMES) {
      const outPath = path.join(outDir, `frame-${frame}.png`);
      await renderStill({ composition, serveUrl: bundled, frame, output: outPath });
      expect(existsSync(outPath)).toBe(true);
    }
  }, 120_000);
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd video/bfdash-short && npm install --save-dev @remotion/bundler && npm test -- BFDashShort.render.test.ts`
Expected: FAILs before Step 1's rewrite is in place would show a missing-scene-branch crash; after Step 1 is written this should already be close to passing — run it now to confirm, and treat any thrown error (e.g. a missing static file from Tasks 8/9, or a typo in a scene's `image` path) as a real bug to fix before moving on.

- [ ] **Step 4: Fix any failures, then run test to verify it passes**

Run: `cd video/bfdash-short && npm test -- BFDashShort.render.test.ts`
Expected: PASS — 6 PNG files created under `out/frame-samples/`.

- [ ] **Step 5: Manual visual check**

Open the 6 PNGs in `video/bfdash-short/out/frame-samples/` and confirm: frame 0 shows the Rates photo with hook caption words visible, frame 150 shows the "BFDash" title card, frame 400/700 show feature-rip photos with callout boxes and correct captions, frame 850 shows the OutroCard with logo and subscribe text. If any callout box is misplaced relative to the actual on-screen data in the photo, adjust that scene's `calloutRect` percentages in `src/scenes.ts` and re-run Step 4.

- [ ] **Step 6: Run the full test suite**

Run: `cd video/bfdash-short && npm test`
Expected: PASS — every test file from Tasks 1–10 green.

- [ ] **Step 7: Commit**

```bash
git add video/bfdash-short/src/BFDashShort.tsx video/bfdash-short/src/BFDashShort.render.test.ts video/bfdash-short/package.json video/bfdash-short/package-lock.json
git commit -m "feat(video): assemble BFDashShort composition from scene config"
```

---

### Task 11: Final render

**Files:** none created or modified — this task produces the deliverable video file.

**Interfaces:** none — terminal task.

- [ ] **Step 1: Render the final video**

Run: `cd video/bfdash-short && npm run build`
Expected: Remotion renders all 900 frames and writes `out/bfdash-short.mp4`, exiting 0.

- [ ] **Step 2: Confirm output**

Run: `ffprobe -v quiet -show_entries format=duration,stream=width,height -of default=noprint_wrappers=1 video/bfdash-short/out/bfdash-short.mp4`
Expected: `duration=30.0...`, `width=2160`, `height=3840`.

- [ ] **Step 3: Watch the full render**

Open `video/bfdash-short/out/bfdash-short.mp4` and watch it start to finish, checking against the [design spec](../specs/2026-09-11-bfdash-youtube-short-design.md): every caption from Task 2's `scenes.ts` appears and is readable, callout boxes line up with the real data they're pointing at, the BFDash title card and full-name subtitle both appear, the Tame Impala clip plays under the whole thing without cutting off early or leaving silence at the end, and the outro shows the logo and both subscribe/link lines.

This is the final acceptance check before the video is ready to upload — there is no automated substitute for watching it.
