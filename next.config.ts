import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Static export so Capacitor can bundle the web app into the iOS shell.
  output: "export",
  images: { unoptimized: true },
};

export default nextConfig;
