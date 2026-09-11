import sharp from "sharp";
import { mkdir } from "node:fs/promises";
import path from "node:path";

const SOURCE_DIR = "C:/Users/gchil/Downloads/Compressed/Photos-1-001_2";
const OUT_DIR = path.resolve("public/photos");

// { output filename (without .jpg): [source filename, rotation degrees
//   clockwise to apply, crop] }
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
//
// `crop` is a fraction-based extract box (percent of the ROTATED image's
// width/height, i.e. as measured on the previously-shipped uncropped
// output) applied BEFORE the resize step. It exists to fix a bug where
// PhotoBeat's objectFit:"cover" in a 2160x3840 portrait frame only shows
// the center ~42% of these landscape (~4:3) photos, slicing off left-edge
// setting labels ("Sensitivity" -> "tivity", etc).
//
// The crop boxes were chosen empirically (rotate -> Read the output ->
// eyeball the screen's content bounding box as a fraction of the frame ->
// compute pixel values -> extract -> Read again to confirm no label text
// is cut at the left/right edge) using this rule of thumb: cover's
// left/right crop amount for a source of pixel-height H depends on H, not
// on the crop's width -- a wider crop of the SAME height doesn't lose any
// more of a given label. So each box below (a) keeps close to the full
// available screen height (more height = less width discarded by `cover`)
// and (b) trims width only where it's genuinely dead space (phone
// background, unused menu real estate, or a second data column that isn't
// this photo's primary subject) so the remaining content register fits
// inside the ~42-80% band `cover` ends up showing once the aspect ratio is
// less extreme. Per-scene `focalPoint`/`calloutRect` values in
// src/scenes.ts were re-derived against these new crops (see Fix 2 in the
// final review).
const PHOTOS = {
  "tools-menu": [
    "IMG20260911082542.jpg",
    -90,
    { left: 0, top: 10, width: 97, height: 80 },
  ],
  "pids": [
    "IMG20260911082554.jpg",
    90,
    { left: 6, top: 11, width: 91, height: 89 },
  ],
  "rates": [
    "IMG20260911082608.jpg",
    90,
    { left: 0, top: 12, width: 43, height: 88 },
  ],
  "filters-p": [
    "IMG20260911082634.jpg",
    90,
    { left: 0, top: 12, width: 52, height: 88 },
  ],
  "vtx": [
    "IMG20260911082643.jpg",
    90,
    { left: 0, top: 13, width: 45, height: 87 },
  ],
  "motor": [
    "IMG20260911082653.jpg",
    90,
    { left: 8, top: 13, width: 47, height: 87 },
  ],
};

async function main() {
  await mkdir(OUT_DIR, { recursive: true });

  for (const [outName, [sourceName, rotation, crop]] of Object.entries(PHOTOS)) {
    const sourcePath = path.join(SOURCE_DIR, sourceName);
    const outPath = path.join(OUT_DIR, `${outName}.jpg`);

    // Rotate first so the crop fractions below (measured against the
    // rotated, right-side-up image) land in the right place, then read
    // back the actual rotated pixel dimensions -- sharp's `.rotate()` on a
    // 90/-90deg swaps width/height, and we don't want to hardcode that.
    const rotated = sharp(sourcePath).rotate(rotation);
    const { width: rotatedWidth, height: rotatedHeight } = await rotated
      .clone()
      .toBuffer({ resolveWithObject: true })
      .then((r) => r.info);

    const extractBox = {
      left: Math.round((crop.left / 100) * rotatedWidth),
      top: Math.round((crop.top / 100) * rotatedHeight),
      width: Math.round((crop.width / 100) * rotatedWidth),
      height: Math.round((crop.height / 100) * rotatedHeight),
    };

    await rotated
      .extract(extractBox)
      .resize({ width: 3840, withoutEnlargement: true })
      .jpeg({ quality: 92 })
      .toFile(outPath);

    console.log(
      `${sourceName} -> ${outName}.jpg (rotated ${rotation}deg, cropped ${JSON.stringify(extractBox)})`,
    );
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
