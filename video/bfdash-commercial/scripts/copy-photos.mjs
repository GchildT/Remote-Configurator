import { copyFile, mkdir } from "node:fs/promises";
import path from "node:path";

const SOURCE_DIR = path.resolve("../bfdash-short/public/photos");
const OUT_DIR = path.resolve("public/photos");

const PHOTOS = ["rates", "pids", "filters-p", "vtx", "motor"];

async function main() {
  await mkdir(OUT_DIR, { recursive: true });

  for (const name of PHOTOS) {
    const src = path.join(SOURCE_DIR, `${name}.jpg`);
    const dest = path.join(OUT_DIR, `${name}.jpg`);
    await copyFile(src, dest);
    console.log(`${src} -> ${dest}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
