// swift-tools-version: 6.2
import PackageDescription

// Compile-checks the OS 27 code path of SwiftLMFoundationModels against a stub of Apple's
// documented FoundationModels API. It is not a substitute for building with Xcode 27.
let package = Package(
  name: "os27check",
  platforms: [.macOS(.v26)],
  targets: [
    .target(name: "FoundationModels"),
    .target(name: "SwiftLM"),
    .target(
      name: "SwiftLMFoundationModels",
      dependencies: ["SwiftLM", "FoundationModels"],
      swiftSettings: [.define("SWIFTLM_ASSUME_OS27")]
    ),
  ]
)
