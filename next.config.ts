import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Static export so Electron can bundle the web app.
  output: "export",
  images: { unoptimized: true },
  devIndicators: false,
  allowedDevOrigins: [
    "192.168.88.6",
    "saitejas-macbook-pro.tail54df4a.ts.net",
  ],
};

export default nextConfig;
