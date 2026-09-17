import Foundation

public struct StructuredGenerationSchema: Equatable, Identifiable, Sendable {
  public var description: String
  public var fields: [StructuredGenerationField]
  public var id: String
  public var maximumItemCount: Int?
  public var maximumResponseTokens: Int?
  public var name: String

  public init(
    id: String,
    name: String,
    description: String,
    fields: [StructuredGenerationField] = [],
    maximumItemCount: Int? = nil,
    maximumResponseTokens: Int? = nil
  ) {
    self.description = description
    self.fields = fields
    self.id = id
    self.maximumItemCount = maximumItemCount
    self.maximumResponseTokens = maximumResponseTokens
    self.name = name
  }
}

public struct StructuredGenerationField: Equatable, Identifiable, Sendable {
  public var guide: String?
  public var id: String { name }
  public var isRequired: Bool
  public var maximumCount: Int?
  public var name: String
  public var typeDescription: String

  public init(
    name: String,
    typeDescription: String,
    isRequired: Bool = true,
    guide: String? = nil,
    maximumCount: Int? = nil
  ) {
    self.guide = guide
    self.isRequired = isRequired
    self.maximumCount = maximumCount
    self.name = name
    self.typeDescription = typeDescription
  }
}

public struct StructuredGenerationContract: Equatable, Identifiable, Sendable {
  public var examples: [PromptExample]
  public var id: String { prompt.id }
  public var prompt: PromptContract
  public var schema: StructuredGenerationSchema

  public init(
    prompt: PromptContract,
    schema: StructuredGenerationSchema,
    examples: [PromptExample] = []
  ) {
    self.examples = examples
    self.prompt = prompt
    self.schema = schema
  }

  public func compiledPrompt(
    metadata: LMProviderMetadata,
    userPrompt: String
  ) -> CompiledPrompt {
    CompiledPrompt(
      contract: PromptContract(
        id: prompt.id,
        version: prompt.version,
        instructions: prompt.instructions,
        responseSchemaDescription: schema.promptDescription
      ),
      examples: examples,
      metadata: metadata,
      userPrompt: userPrompt
    )
  }
}

extension StructuredGenerationSchema {
  public var promptDescription: String {
    let fieldDescriptions = fields.map { field in
      var pieces = [
        "- \(field.name): \(field.typeDescription)",
        field.isRequired ? "required" : "optional",
      ]
      if let maximumCount = field.maximumCount {
        pieces.append("maximum count \(maximumCount)")
      }
      if let guide = field.guide, !guide.isEmpty {
        pieces.append(guide)
      }
      return pieces.joined(separator: "; ")
    }

    let limitDescription: String
    switch (maximumItemCount, maximumResponseTokens) {
    case let (.some(items), .some(tokens)):
      limitDescription = "\nMaximum items: \(items). Maximum response tokens: \(tokens)."
    case let (.some(items), .none):
      limitDescription = "\nMaximum items: \(items)."
    case let (.none, .some(tokens)):
      limitDescription = "\nMaximum response tokens: \(tokens)."
    case (.none, .none):
      limitDescription = ""
    }

    guard !fieldDescriptions.isEmpty else {
      return "\(description)\(limitDescription)"
    }

    return """
    \(description)
    Fields:
    \(fieldDescriptions.joined(separator: "\n"))
    \(limitDescription)
    """
  }
}
