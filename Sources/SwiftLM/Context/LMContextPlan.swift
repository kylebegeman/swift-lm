import Foundation

/// The part of a model request that an item occupies in the provider context window.
public enum LMContextSurface: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
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
public enum LMContextTrust: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case modelGenerated
  case toolGenerated
  case trustedApp
  case trustedSystem
  case userProvided
}

/// How an app expects a language-model session to be created and reused.
public enum LMSessionPolicy: String, Codable, Equatable, Sendable {
  case statelessPerRequest
  case reuseWithinTask
  case rehydrateTranscript
}

/// Whether tools are available to the model, or whether the app should run them before generation.
public enum LMToolExecutionPolicy: String, Codable, Equatable, Sendable {
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
public struct LMContextItem: Codable, Equatable, Identifiable, Sendable {
  public var estimatedTokens: Int?
  public var id: String
  public var sourceID: String?
  public var surface: LMContextSurface
  public var text: String
  public var trust: LMContextTrust

  public init(
    id: String,
    surface: LMContextSurface,
    text: String,
    trust: LMContextTrust,
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
public struct LMContextPlan: Codable, Equatable, Sendable {
  public var includeGeneratedSchemaInPrompt: Bool
  public var items: [LMContextItem]
  public var prewarmPromptPrefix: String?
  public var sessionPolicy: LMSessionPolicy
  public var toolExecutionPolicy: LMToolExecutionPolicy
  public var tools: [LMToolDefinition]

  public init(
    items: [LMContextItem] = [],
    sessionPolicy: LMSessionPolicy = .statelessPerRequest,
    toolExecutionPolicy: LMToolExecutionPolicy = .noTools,
    tools: [LMToolDefinition] = [],
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

  public var requiredCapabilities: Set<LMCapability> {
    var capabilities: Set<LMCapability> = []

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

  static func toolItemID(for tool: LMToolDefinition) -> String {
    "tool-\(tool.name)"
  }

  public func budgetReport(
    budget: TokenBudget = TokenBudget(),
    counter: TokenCounter = .latinHeuristic
  ) -> LMContextBudgetReport {
    let used = estimatedInputTokens(using: counter)
    return LMContextBudgetReport(
      availableInputTokens: budget.availableInputTokens,
      estimatedInputTokens: used
    )
  }

  public static func foundationModelExtraction(
    instructions: String,
    userPrompt: String,
    schemaDescription: String,
    tools: [LMToolDefinition] = [],
    sessionPolicy: LMSessionPolicy = .statelessPerRequest,
    prewarmPromptPrefix: String? = nil
  ) -> Self {
    var items = [
      LMContextItem(
        id: "instructions",
        surface: .instructions,
        text: instructions,
        trust: .trustedSystem
      ),
      LMContextItem(
        id: "prompt",
        surface: .prompt,
        text: userPrompt,
        trust: .userProvided
      ),
      LMContextItem(
        id: "generated-schema",
        surface: .generatedSchema,
        text: schemaDescription,
        trust: .trustedApp
      ),
    ]

    items += tools.map { tool in
      LMContextItem(
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

public struct LMContextBudgetReport: Codable, Equatable, Sendable {
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
