// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "GuidanceCore",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [.library(name: "GuidanceCore", targets: ["GuidanceCore"])],
  targets: [
    .target(name: "GuidanceCore"),
    .testTarget(name: "GuidanceCoreTests", dependencies: ["GuidanceCore"]),
  ]
)
