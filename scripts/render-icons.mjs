// Regenerates every raster icon from the SVG brand sources.
//
//   node scripts/render-icons.mjs
//
// Sources of truth:
//   public/brand/dimo-logo.svg  full-bleed square (app icons, OAuth logo)
//   public/favicon.svg          rounded tile (browser favicon)
//
// Android's launcher icon is a vector and is edited directly in
// android-native/app/src/main/res/drawable/ic_launcher_foreground.xml.

import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** [source, output, pixel size] */
const targets = [
  ["public/brand/dimo-logo.svg", "public/brand/dimo-logo.png", 1024],
  ["public/brand/dimo-logo.svg", "public/brand/dimo-logo-512.png", 512],
  ["public/brand/dimo-logo.svg", "public/brand/dimo-logo-120.png", 120],
  ["public/brand/dimo-logo.svg", "public/icon-192.png", 192],
  ["public/brand/dimo-logo.svg", "public/icon-512.png", 512],
  ["public/brand/dimo-logo.svg", "public/apple-icon.png", 180],
  ["public/brand/dimo-logo.svg", "public/apple-touch-icon.png", 180],
  ["public/brand/dimo-logo.svg", "app/icon.png", 512],
  ["public/brand/dimo-logo.svg", "app/apple-icon.png", 180],
  // Google OAuth branding requires exactly 120x120.
  ["public/brand/dimo-logo.svg", "store/oauth-logo.png", 120],
  ["public/brand/dimo-logo.svg", "store/AppIcon-1024.png", 1024],
  [
    "public/brand/dimo-logo.svg",
    "ios-native/Dimo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    1024,
  ],
  ["public/favicon.svg", "public/favicon-32.png", 32],
];

const SQUARE_SOURCE = "public/brand/dimo-logo.svg";
const GREEN = "#1f9d63";

for (const [from, to, size] of targets) {
  const svg = await readFile(path.join(root, from));
  // Render well above the target, then downsample, so thin ledger rows and the
  // torn edge stay clean at favicon sizes.
  let pipeline = sharp(svg, { density: 1024 }).resize(size, size, {
    fit: "contain",
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  });
  // The square master is full-bleed, so flattening changes nothing visually but
  // drops the alpha channel — App Store Connect rejects app icons that have one.
  // The rounded favicon keeps its alpha so the corners stay transparent.
  if (from === SQUARE_SOURCE) pipeline = pipeline.flatten({ background: GREEN });
  const png = await pipeline.png({ compressionLevel: 9 }).toBuffer();
  await writeFile(path.join(root, to), png);
  console.log(`${String(size).padStart(4)}px  ${to}`);
}
