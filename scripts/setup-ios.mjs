#!/usr/bin/env node
/**
 * Prepare the Capacitor iOS project (and print native Swift next steps).
 *
 * Safe on Linux/macOS cloud agents: builds the static web export and runs
 * `cap sync ios`. Opening Xcode / simulators requires a Mac with full Xcode.
 */

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { platform } from "node:os";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const isMac = platform() === "darwin";
const openXcode = process.argv.includes("--open");

function run(command, args, { optional = false } = {}) {
  console.log(`\n> ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: "inherit",
    env: process.env,
    shell: false,
  });
  if (result.status !== 0) {
    if (optional) {
      console.warn(`(optional) ${command} failed with exit ${result.status ?? "unknown"}`);
      return false;
    }
    process.exit(result.status ?? 1);
  }
  return true;
}

function commandExists(command) {
  const result = spawnSync(command, ["--version"], {
    stdio: "ignore",
    shell: false,
  });
  return result.status === 0;
}

function loadEnvLocal() {
  const path = resolve(root, ".env.local");
  if (!existsSync(path)) return {};
  const values = {};
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    values[trimmed.slice(0, eq)] = trimmed.slice(eq + 1);
  }
  return values;
}

function printBanner() {
  console.log("Dimo iOS setup");
  console.log("==============");
  console.log(`Platform: ${platform()}`);
  console.log(`Open Xcode after sync: ${openXcode ? "yes" : "no"}`);
}

function checkNode() {
  const major = Number(process.versions.node.split(".")[0]);
  if (major < 22) {
    console.error(`Node.js >= 22.13.0 required (found ${process.versions.node})`);
    process.exit(1);
  }
  console.log(`Node.js ${process.versions.node}`);
}

function checkEnv() {
  const env = { ...loadEnvLocal(), ...process.env };
  const required = [
    "NEXT_PUBLIC_CONVEX_URL",
    "NEXT_PUBLIC_WORKOS_CLIENT_ID",
    "NEXT_PUBLIC_WORKOS_REDIRECT_URI",
  ];
  const missing = required.filter((key) => !env[key]);
  if (missing.length) {
    console.warn(
      "\nWarning: missing build-time auth/sync env vars. Capacitor will build, but sign-in will show “Authentication setup required”.",
    );
    console.warn(`Missing: ${missing.join(", ")}`);
    console.warn("Copy .env.example → .env.local and fill values (see README).");
  } else {
    console.log("Found NEXT_PUBLIC_* Convex / WorkOS build vars.");
  }
}

function checkMacTooling() {
  if (!isMac) {
    console.log(
      "\nNot macOS — skipping Xcode checks. Edit iOS code here; build/run on a Mac with full Xcode.",
    );
    return;
  }

  const xcodebuild = spawnSync("xcodebuild", ["-version"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (xcodebuild.status === 0) {
    console.log(xcodebuild.stdout.trim().split("\n")[0]);
  } else {
    console.warn(
      "\nWarning: xcodebuild not available. Install full Xcode from the Mac App Store (Command Line Tools alone is not enough).",
    );
  }

  if (commandExists("xcodegen")) {
    console.log("xcodegen found (ios-native)");
  } else {
    console.warn(
      "xcodegen not found — install with `brew install xcodegen` before generating ios-native/Dimo.xcodeproj.",
    );
  }
}

printBanner();
checkNode();
checkEnv();
checkMacTooling();

if (!existsSync(resolve(root, "node_modules/@capacitor/ios"))) {
  run("npm", ["install"]);
}

run("npm", ["run", "build"]);
run("npx", ["cap", "sync", "ios"]);

if (openXcode) {
  if (!isMac) {
    console.warn("\n--open ignored: Capacitor cannot open Xcode on this OS.");
  } else {
    run("npx", ["cap", "open", "ios"]);
  }
}

console.log(`
Capacitor iOS project synced → ios/App

Next steps (Mac + full Xcode):
  1. Capacitor shell:  npm run ios
     or already synced: npx cap open ios
  2. Signing & Capabilities → choose your Team (bundle id app.dimo.expenses)
  3. Run on a simulator or device

Native SwiftUI app (ios-native/, bundle id app.dimo.ios):
  brew install xcodegen
  npm run ios:native

WorkOS: register the redirect you embed at build time. Native uses dimo://callback
(already in ios-native Info.plist). Capacitor uses NEXT_PUBLIC_WORKOS_REDIRECT_URI.
`);
