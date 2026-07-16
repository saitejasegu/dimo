// swift-tools-version: 5.9

import PackageDescription

// Reproducible packaging shim for google-ai-edge/LiteRT-LM v0.13.0.
// See UPSTREAM.md for provenance and why the upstream remote product cannot
// currently be linked directly by an Xcode application target.
let package = Package(
  name: "LiteRTLM",
  platforms: [.iOS(.v15)],
  products: [
    .library(name: "LiteRTLM", targets: ["LiteRTLM"]),
  ],
  targets: [
    .binaryTarget(
      name: "CLiteRTLM",
      url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.12.0/CLiteRTLM.xcframework.zip",
      checksum: "3c2a11ecc8511d1e74efa7ca308dc7130c95223325c33212337ffb0563b79cde"
    ),
    .target(
      name: "LiteRTLM",
      dependencies: ["CLiteRTLM"]
    ),
    .testTarget(
      name: "LiteRTLMTests",
      dependencies: ["LiteRTLM"]
    ),
  ]
)
