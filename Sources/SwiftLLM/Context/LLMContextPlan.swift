import Foundation

/// The part of a model request that an item occupies in the provider context window.
public enum LLMContextSurface: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case generatedSchema
  case instructions
  case modelResponse
  case prompt
  case retrievedContext
  case sessionTranscript
  case toolDefinition
  case toolResult
}

/// How much the app should trust a context item before the model sees it.
public enum LLMContextTrust: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case modelGenerated
  case toolGenerated
  case trustedApp
  case trustedSystem
  case userProvided
}

/// How an app expects a language-model session to be created and reused.
public enum LLMSessionPolicy: String, Codable, Equatable, Sendable {
  case statelessPerRequest
  case reuseWithinTask
  case rehydrateTranscript
}

/// Whether tools are available to the model, or whether the app should run them before generation.
public enum LLMToolExecutionPolicy: String, Codable, Equatable, Sendable {
  case appPrefetches
  case modelMayCall
  case modelMustCall
  case noTools

  public var permitsModelToolCalls: Bool {
    switch self {
    case .modelMayCall, .modelMustCall:
      return true
    case .appPrefetches, .noTools:
      return false
    }
  }
}

/// A single entry in a request's context budget.
public struct LLMContextItem: Codable, Equatable, Identifiable, Sendable {
  public var estimatedTokens: Int?
  public var id: String
  public var sourceID: String?
  public var surface: LLMContextSurface
  public var text: String
  public var trust: LLMContextTrust

  public init(
    id: String,
    surface: LLMContextSurface,
    text: String,
    trust: LLMContextTrust,
    estimatedTokens: Int? = nil,
    sourceID: String? = nil
  ) {
    self.estimatedTokens = estimatedTokens
    self.id = id
    self.sourceID = sourceID
    self.surface = surface
    self.text = text
    self.trust = trust
  }

  public func tokenCount(using counter: TokenCounter = .latinHeuristic) -> Int {
    estimatedTokens ?? counter.count(text)
  }
}

/// Provider-neutral planning data for session context, Foundation Models transcripts, guided
/// generation schemas, and tool-call style workflows.
public struct LLMContextPlan: Codable, Equatable, Sendable {
  public var includeGeneratedSchemaInPrompt: Bool
  public var items: [LLMContextItem]
  public var prewarmPromptPrefix: String?
  public var sessionPolicy: LLMSessionPolicy
  public var toolExecutionPolicy: LLMToolExecutionPolicy
  public var tools: [LLMToolDefinition]

  public init(
    items: [LLMContextItem] = [],
    sessionPolicy: LLMSessionPolicy = .statelessPerRequest,
    toolExecutionPolicy: LLMToolExecutionPolicy = .noTools,
    tools: [LLMToolDefinition] = [],
    includeGeneratedSchemaInPrompt: Bool = true,
    prewarmPromptPrefix: String? = nil
  ) {
    self.includeGeneratedSchemaInPrompt = includeGeneratedSchemaInPrompt
    self.items = items
    self.prewarmPromptPrefix = prewarmPromptPrefix
    self.sessionPolicy = sessionPolicy
    self.toolExecutionPolicy = toolExecutionPolicy
    self.tools = tools
  }

  public var requiredCapabilities: Set<LLMCapability> {
    var capabilities: Set<LLMCapability> = []

    if items.contains(where: { $0.surface == .instructions }) {
      capabilities.insert(.instructions)
    }
    if items.contains(where: { $0.surface == .generatedSchema }) {
      capabilities.insert(.guidedGeneration)
    }
    if sessionPolicy == .rehydrateTranscript || items.contains(where: { $0.surface == .sessionTranscript }) {
      capabilities.insert(.sessionTranscript)
    }
    if prewarmPromptPrefix != nil {
      capabilities.insert(.prewarm)
    }
    if !tools.isEmpty || items.contains(where: { $0.surface == .toolDefinition }) {
      capabilities.insert(.tools)
    }
    if items.contains(where: { $0.surface == .toolResult }) {
      capabilities.insert(.toolResults)
    }

    return capabilities
  }

  /// Estimated tokens for every context item plus tool definitions that are not already listed as
  /// `toolDefinition` items.
  public func estimatedInputTokens(using counter: TokenCounter = .latinHeuristic) -> Int {
    let listedToolIDs = Set(items.filter { $0.surface == .toolDefinition }.map(\.id))
    return items.reduce(0) { $0 + $1.tokenCount(using: counter) }
      + tools
        .filter { !listedToolIDs.contains(Self.toolItemID(for: $0)) }
        .reduce(0) { $0 + $1.estimatedDefinitionTokens(using: counter) }
  }

  static func toolItemID(for tool: LLMToolDefinition) -> String {
    "tool-\(tool.name)"
  }

  public func budgetReport(
    budget: TokenBudget = TokenBudget(),
    counter: TokenCounter = .latinHeuristic
  ) -> LLMContextBudgetReport {
    let used = estimatedInputTokens(using: counter)
    return LLMContextBudgetReport(
      availableInputTokens: budget.availableInputTokens,
      estimatedInputTokens: used
    )
  }

  public static func foundationModelExtraction(
    instructions: String,
    userPrompt: String,
    schemaDescription: String,
    tools: [LLMToolDefinition] = [],
    sessionPolicy: LLMSessionPolicy = .statelessPerRequest,
    prewarmPromptPrefix: String? = nil
  ) -> Self {
    var items = [
      LLMContextItem(
        id: "instructions",
        surface: .instructions,
        text: instructions,
        trust: .trustedSystem
      ),
      LLMContextItem(
        id: "prompt",
        surface: .prompt,
        text: userPrompt,
        trust: .userProvided
      ),
      LLMContextItem(
        id: "generated-schema",
        surface: .generatedSchema,
        text: schemaDescription,
        trust: .trustedApp
      ),
    ]

    items += tools.map { tool in
      LLMContextItem(
        id: toolItemID(for: tool),
        surface: .toolDefinition,
        text: "\(tool.name): \(tool.description)",
        trust: .trustedApp,
        estimatedTokens: tool.estimatedDefinitionTokens()
      )
    }

    return Self(
      items: items,
      sessionPolicy: sessionPolicy,
      toolExecutionPolicy: tools.isEmpty ? .noTools : .modelMayCall,
      tools: tools,
      includeGeneratedSchemaInPrompt: true,
      prewarmPromptPrefix: prewarmPromptPrefix
    )
  }
}

public struct LLMContextBudgetReport: Codable, Equatable, Sendable {
  public var availableInputTokens: Int
  public var estimatedInputTokens: Int

  public init(
    availableInputTokens: Int,
    estimatedInputTokens: Int
  ) {
    self.availableInputTokens = availableInputTokens
    self.estimatedInputTokens = estimatedInputTokens
  }

  public var remainingInputTokens: Int {
    max(0, availableInputTokens - estimatedInputTokens)
  }

  public var exceedsBudget: Bool {
    estimatedInputTokens > availableInputTokens
  }
}
