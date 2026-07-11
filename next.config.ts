import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Static export so Capacitor (iOS) and Electron can bundle the web app.
  output: "export",
  images: { unoptimized: true },
};

export default nextConfig;
