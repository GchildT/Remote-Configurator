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
