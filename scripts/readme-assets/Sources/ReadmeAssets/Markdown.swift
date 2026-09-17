import Foundation
import SwiftLM
import SwiftLMAnthropic
import SwiftLMFoundationModels
import SwiftLMOpenAI

/// The README's capability table, built from the adapters' own capability values.
enum CapabilityTable {
  struct Column {
    var title: String
    var capabilities: LMClientCapabilities
    /// Cells that depend on the model rather than the adapter.
    var notes: [LMCapability: String] = [:]
    /// Product, privacy mode, context window, and requirements, in `factColumns` order.
    var facts: [String]
  }

  static let perModel = "Per model"

  static func columns() -> [Column] {
    let onDevice = FoundationModelRuntimeProfile.onDevice
    let privateCloud = FoundationModelRuntimeProfile.privateCloudCompute
    let custom = FoundationModelRuntimeProfile.preset(for: .customLocal("model"))
    let providerPackage = FoundationModelExecutionTarget.providerPackage("model")
    let openAI = OpenAIClient(apiKey: "", model: "model")
    let anthropic = AnthropicClient(apiKey: "", model: "model")
    let typedTools = "Typed API"
    return [
      Column(
        title: "On device",
        capabilities: onDevice.capabilities,
        notes: [.reasoning: perModel, .imageInput: perModel, .tools: typedTools],
        facts: [
          "`SwiftLMFoundationModels`",
          "`\(onDevice.privacyMode.rawValue)`",
          "Reported by the OS",
          "Apple Intelligence on a supported device",
        ]
      ),
      Column(
        title: "Private Cloud Compute",
        capabilities: privateCloud.capabilities,
        notes: [.imageInput: perModel, .tools: typedTools],
        facts: [
          "`SwiftLMFoundationModels`",
          "`\(privateCloud.privacyMode.rawValue)`",
          "Reported by the OS",
          "OS 27, the entitlement, and daily quota",
        ]
      ),
      Column(
        title: "Your model",
        capabilities: custom.capabilities,
        notes: [.reasoning: perModel, .imageInput: perModel, .tools: typedTools],
        facts: [
          "`SwiftLMFoundationModels`",
          "`\(custom.privacyMode.rawValue)`, or `\(providerPackage.privacyMode.rawValue)` for a provider package",
          "The value you pass",
          "OS 27 and a `LanguageModel`",
        ]
      ),
      Column(
        title: "OpenAI",
        capabilities: LMClientCapabilities.openAIResponses,
        notes: [.temperature: perModel],
        facts: [
          "`SwiftLMOpenAI`",
          "`\(openAI.metadata.privacyMode.rawValue)`",
          "Not reported",
          "An API key from your app",
        ]
      ),
      Column(
        title: "Anthropic",
        capabilities: LMClientCapabilities.anthropicMessages,
        notes: [.temperature: perModel],
        facts: [
          "`SwiftLMAnthropic`",
          "`\(anthropic.metadata.privacyMode.rawValue)`",
          "Not reported",
          "An API key from your app",
        ]
      ),
    ]
  }

  static let factColumns = ["Product", "Privacy mode", "Context window", "Needs"]

  static let capabilityRows: [(title: String, capability: LMCapability)] = [
    ("Streaming", .streaming),
    ("JSON output", .jsonObjectResponse),
    ("Enforced JSON schema", .nativeJSONSchemaResponse),
    ("Reasoning effort", .reasoning),
    ("Image input", .imageInput),
    ("Tool calls", .tools),
    ("Temperature", .temperature),
    ("Stop sequences", .stopSequences),
    ("Prewarming", .prewarm),
  ]

  /// Two tables: where each client runs, then what it accepts.
  static func markdown() -> String {
    let columns = columns()
    var targets = [
      "| Client | " + factColumns.joined(separator: " | ") + " |",
      "| --- |" + factColumns.map { _ in " --- |" }.joined(),
    ]
    for column in columns {
      targets.append("| **\(column.title)** | " + column.facts.joined(separator: " | ") + " |")
    }

    var features = [
      "| | " + columns.map(\.title).joined(separator: " | ") + " |",
      "| --- |" + columns.map { _ in " :-: |" }.joined(),
    ]
    for row in capabilityRows {
      let cells = columns.map { column -> String in
        if let note = column.notes[row.capability] { return note }
        return column.capabilities.supports(row.capability) ? "Yes" : "No"
      }
      features.append("| **\(row.title)** | " + cells.joined(separator: " | ") + " |")
    }
    return targets.joined(separator: "\n") + "\n\n" + features.joined(separator: "\n")
  }
}

enum ReceiptBlock {
  static func markdown(_ receipt: LMRunReceipt) throws -> String {
    "```json\n" + String(decoding: try receipt.jsonData(), as: UTF8.self) + "\n```"
  }
}

/// A light and dark `<picture>` whose alt text is the image's own accessible label.
enum PictureBlock {
  static func markdown(name: String, directory: String, lightSVG: String) throws -> String {
    guard let start = lightSVG.range(of: #"aria-label=""#),
          let end = lightSVG.range(of: "\"", range: start.upperBound..<lightSVG.endIndex)
    else {
      throw DemoError("\(name)-light.svg has no aria-label.")
    }
    let label = lightSVG[start.upperBound..<end.lowerBound]
    return """
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="\(directory)/\(name)-dark.svg">
        <img alt="\(label)" src="\(directory)/\(name)-light.svg">
      </picture>
      """
  }
}

/// Replaces the content between `<!-- readme-assets:begin NAME -->` and
/// `<!-- readme-assets:end NAME -->` markers.
enum GeneratedBlocks {
  static func apply(_ blocks: [String: String], to readme: String) throws -> String {
    var output = readme
    for (name, content) in blocks.sorted(by: { $0.key < $1.key }) {
      let begin = "<!-- readme-assets:begin \(name) -->"
      let end = "<!-- readme-assets:end \(name) -->"
      guard let beginRange = output.range(of: begin),
            let endRange = output.range(of: end, range: beginRange.upperBound..<output.endIndex)
      else {
        throw DemoError("README.md has no \(begin) and \(end) markers.")
      }
      output.replaceSubrange(beginRange.upperBound..<endRange.lowerBound, with: "\n\n" + content + "\n\n")
    }
    return output
  }
}

/// Confirms that every Swift block in the README is a compiled snippet, and that every snippet is
/// shown.
enum SnippetCheck {
  static func swiftBlocks(in markdown: String) -> [String] {
    var blocks: [String] = []
    var current: [String]?
    for line in markdown.components(separatedBy: "\n") {
      if current == nil, line == "```swift" {
        current = []
      } else if current != nil, line == "```" {
        blocks.append(current!.joined(separator: "\n"))
        current = nil
      } else if current != nil {
        current!.append(line)
      }
    }
    return blocks
  }

  /// Package manifest blocks cannot compile inside a target, so they are the one exception.
  static func isManifest(_ block: String) -> Bool {
    block.contains(".package(url:") || block.contains(".product(name:")
  }

  static func problems(readme: String, regions: [SnippetSource.Region]) -> [String] {
    let blocks = swiftBlocks(in: readme).filter { !isManifest($0) }
    let codes = Dictionary(regions.map { ($0.code, $0.name) }, uniquingKeysWith: { first, _ in first })
    var problems: [String] = []
    for block in blocks where codes[block] == nil {
      let firstLine = block.split(separator: "\n").first.map(String.init) ?? ""
      problems.append("README.md has a Swift block that is not a snippet in Snippets.swift, starting with: \(firstLine)")
    }
    let shown = Set(blocks)
    for region in regions where !shown.contains(region.code) {
      problems.append("Snippet \(region.name) in Snippets.swift is not in README.md. Update the README block to match it.")
    }
    return problems
  }
}
