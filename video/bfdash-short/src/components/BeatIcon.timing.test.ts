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
