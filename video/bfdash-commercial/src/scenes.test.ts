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
