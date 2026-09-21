// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RecipeKit",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [.library(name: "RecipeKit", targets: ["RecipeKit"])],
  dependencies: [.package(path: "../GuidanceCore")],
  targets: [
    .target(
      name: "RecipeKit",
      dependencies: ["GuidanceCore"],
      path: ".",
      exclude: ["Package.swift", "Tests"],
      sources: ["RecipeKit.swift", "RecipeQuestion.swift", "RecipeAblation.swift"],
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "RecipeKitTests",
      dependencies: ["RecipeKit", "GuidanceCore"],
      path: "Tests/RecipeKitTests"
    ),
  ]
)
