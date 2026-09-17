// swift-tools-version: 6.2
import PackageDescription

// Compile-checks the OS 27 code path of SwiftLLMFoundationModels against a stub of Apple's
// documented FoundationModels API. It is not a substitute for building with Xcode 27.
let package = Package(
  name: "os27check",
  platforms: [.macOS(.v26)],
  targets: [
    .target(name: "FoundationModels"),
    .target(name: "SwiftLLM"),
    .target(
      name: "SwiftLLMFoundationModels",
      dependencies: ["SwiftLLM", "FoundationModels"],
      swiftSettings: [.define("SWIFTLLM_ASSUME_OS27")]
    ),
  ]
)
