// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "swift-lm",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
    .visionOS(.v26),
    .watchOS(.v26),
  ],
  products: [
    .library(name: "SwiftLM", targets: ["SwiftLM"]),
    .library(name: "SwiftLMFoundationModels", targets: ["SwiftLMFoundationModels"]),
    .library(name: "SwiftLMOpenAI", targets: ["SwiftLMOpenAI"]),
    .library(name: "SwiftLMAnthropic", targets: ["SwiftLMAnthropic"]),
    .library(name: "SwiftLMEvaluation", targets: ["SwiftLMEvaluation"]),
  ],
  targets: [
    .target(name: "SwiftLM"),
    .target(
      name: "SwiftLMFoundationModels",
      dependencies: ["SwiftLM"]
    ),
    .target(
      name: "SwiftLMOpenAI",
      dependencies: ["SwiftLM"]
    ),
    .target(
      name: "SwiftLMAnthropic",
      dependencies: ["SwiftLM"]
    ),
    .target(
      name: "SwiftLMEvaluation",
      dependencies: ["SwiftLM"]
    ),
    .testTarget(
      name: "SwiftLMTests",
      dependencies: [
        "SwiftLM",
        "SwiftLMFoundationModels",
        "SwiftLMOpenAI",
        "SwiftLMAnthropic",
        "SwiftLMEvaluation",
      ]
    ),
  ]
)
