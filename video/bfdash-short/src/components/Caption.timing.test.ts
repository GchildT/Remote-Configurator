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
