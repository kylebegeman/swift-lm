// swift-tools-version: 6.2

import Foundation
import PackageDescription

// SwiftPM names a path dependency after its folder, so read the checkout's folder name instead of
// assuming one. A clone under any name still resolves.
let repository = URL(fileURLWithPath: Context.packageDirectory)
  .appendingPathComponent("../..")
  .standardizedFileURL
  .lastPathComponent
  .lowercased()

let package = Package(
  name: "readme-assets",
  platforms: [
    .macOS(.v26),
  ],
  dependencies: [
    .package(path: "../.."),
  ],
  targets: [
    .executableTarget(
      name: "ReadmeAssets",
      dependencies: [
        .product(name: "SwiftLM", package: repository),
        .product(name: "SwiftLMAnthropic", package: repository),
        .product(name: "SwiftLMEvaluation", package: repository),
        .product(name: "SwiftLMFoundationModels", package: repository),
        .product(name: "SwiftLMOpenAI", package: repository),
      ]
    ),
  ]
)
