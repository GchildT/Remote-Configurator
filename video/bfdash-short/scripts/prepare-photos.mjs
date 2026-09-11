import sharp from "sharp";
import { mkdir } from "node:fs/promises";
import path from "node:path";

const SOURCE_DIR = "C:/Users/gchil/Downloads/Compressed/Photos-1-001_2";
const OUT_DIR = path.resolve("public/photos");

// { output filename (without .jpg): [source filename, rotation degrees
//   clockwise to apply] }
//
// These source JPEGs all carry EXIF Orientation: 1 (no embedded rotation) --
// verified with sharp's metadata() -- so sharp's auto-orient mode
// (`.rotate()` with no argument) is a no-op here and leaves the photos
// sideways, since the phone was physically rotated 90 degrees when each
// shot was taken. An explicit rotation is required instead.
//
// Note: sharp (0.33.x) does NOT compose multiple `.rotate()` calls in one
// pipeline -- chaining `.rotate().rotate(90)` silently drops the second
// call. Use exactly one `.rotate(angle)` call per pipeline.
//
// Rotation values below were determined by running the script and visually
// inspecting each output file with the Read tool (see task-8 report). Five
// of the six needed +90deg clockwise; "tools-menu" was shot with the phone
// held the opposite way and needed -90deg instead (a plain +90 left it
// upside-down).
const PHOTOS = {
  "tools-menu": ["IMG20260911082542.jpg", -90],
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
