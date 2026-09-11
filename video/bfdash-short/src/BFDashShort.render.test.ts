// @vitest-environment node
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
