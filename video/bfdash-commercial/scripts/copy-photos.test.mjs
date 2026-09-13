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
