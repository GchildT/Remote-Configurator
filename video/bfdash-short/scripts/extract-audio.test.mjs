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
