import Foundation

public struct PromptContract: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var id: String
  public var instructions: String
  public var responseSchemaDescription: String
  public var version: String

  public init(
    id: String,
    version: String,
    instructions: String,
    responseSchemaDescription: String = ""
  ) {
    self.id = id
    self.version = version
    self.instructions = instructions
    self.responseSchemaDescription = responseSchemaDescription
  }
}

public struct PromptExample: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var id: String
  public var input: String
  public var notes: String
  public var output: String
  public var tags: Set<String>

  public init(
    id: String,
    input: String,
    output: String,
    tags: Set<String> = [],
    notes: String = ""
  ) {
    self.id = id
    self.input = input
    self.output = output
    self.tags = tags
    self.notes = notes
  }

  public var promptFragment: String {
    """
    Example ID: \(id)
    Input:
    \(input)
    Expected output:
    \(output)
    """
  }
}

public struct ExampleSelector: Sendable {
  public var limit: Int
  public var preferredTags: Set<String>

  public init(
    limit: Int = 4,
    preferredTags: Set<String> = []
  ) {
    self.limit = limit
    self.preferredTags = preferredTags
  }

  public func select(from examples: [PromptExample]) -> [PromptExample] {
    guard limit > 0 else { return [] }

    return examples
      .enumerated()
      .sorted { lhs, rhs in
        let lhsScore = score(lhs.element)
        let rhsScore = score(rhs.element)
        if lhsScore != rhsScore {
          return lhsScore > rhsScore
        }
        return lhs.offset < rhs.offset
      }
      .prefix(limit)
      .map(\.element)
  }

  private func score(_ example: PromptExample) -> Int {
    example.tags.intersection(preferredTags).count
  }
}

public struct CompiledPrompt: Equatable, Sendable {
  public var contract: PromptContract
  public var contextPlan: LMContextPlan?
  public var examples: [PromptExample]
  public var metadata: LMProviderMetadata
  public var userPrompt: String

  public init(
    contract: PromptContract,
    examples: [PromptExample] = [],
    contextPlan: LMContextPlan? = nil,
    metadata: LMProviderMetadata,
    userPrompt: String
  ) {
    self.contract = contract
    self.contextPlan = contextPlan
    self.examples = examples
    self.metadata = metadata
    self.userPrompt = userPrompt
  }

  public var systemInstructions: String {
    let baseInstructions = [
      contract.instructions,
      contract.responseSchemaDescription.isEmpty ? nil : contract.responseSchemaDescription,
    ]
    .compactMap { $0 }
    .joined(separator: "\n\n")
    let exampleText = examples.map(\.promptFragment).joined(separator: "\n\n")
    guard !exampleText.isEmpty else { return baseInstructions }

    return [
      baseInstructions,
      "Use these examples for style and boundary behavior only. Do not copy example facts unless they are present in the current input.",
      exampleText,
    ]
    .filter { !$0.isEmpty }
    .joined(separator: "\n\n")
  }
}
