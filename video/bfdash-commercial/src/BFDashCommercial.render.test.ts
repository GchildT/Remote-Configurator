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
