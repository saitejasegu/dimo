import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const version =
  process.env.VERCEL_GIT_COMMIT_SHA ||
  process.env.VERCEL_DEPLOYMENT_ID ||
  `local-${Date.now()}`;

const payload = {
  version,
  builtAt: new Date().toISOString(),
};

writeFileSync(
  join(root, "public", "version.json"),
  `${JSON.stringify(payload, null, 2)}\n`,
);

console.log(`Wrote public/version.json (${version})`);
