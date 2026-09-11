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
