import Foundation

/// A provider-neutral preference for how much reasoning a model should spend before answering.
///
/// Adapters map this onto their own controls: Apple Private Cloud Compute reasoning levels,
/// OpenAI reasoning effort, or Anthropic adaptive thinking effort. `nil` keeps the provider
/// default. Requests that set an effort require the `reasoning` capability, so routers skip
/// clients that cannot honor it instead of silently ignoring it.
public enum LLMReasoningEffort: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case low
  case medium
  case high
}

/// Sampling and output controls shared by provider adapters.
public struct LLMGenerationParameters: Codable, Equatable, Sendable {
  public var maxOutputTokens: Int?
  public var reasoningEffort: LLMReasoningEffort?
  public var stopSequences: [String]
  public var temperature: Double?
  public var topP: Double?

  public init(
    temperature: Double? = nil,
    maxOutputTokens: Int? = nil,
    topP: Double? = nil,
    stopSequences: [String] = [],
    reasoningEffort: LLMReasoningEffort? = nil
  ) {
    self.maxOutputTokens = maxOutputTokens
    self.reasoningEffort = reasoningEffort
    self.stopSequences = stopSequences
    self.temperature = temperature
    self.topP = topP
  }

  public static let deterministic = Self(
    temperature: 0,
    maxOutputTokens: nil,
    topP: nil,
    stopSequences: []
  )
}

/// A JSON schema request that can be translated into provider-native structured
/// output where supported, or prompt instructions where it is not.
///
/// `strict` asks for provider-enforced schema output where the provider offers it. Strict
/// providers require object schemas with `additionalProperties: false` and every property listed
/// in `required`.
public struct LLMJSONSchema: Codable, Equatable, Sendable {
  public var description: String?
  public var name: String
  public var schema: JSONValue
  public var strict: Bool

  public init(
    name: String,
    description: String? = nil,
    schema: JSONValue,
    strict: Bool = true
  ) {
    self.description = description
    self.name = name
    self.schema = schema
    self.strict = strict
  }
}

public enum LLMResponseFormat: Equatable, Sendable {
  case jsonObject
  case jsonSchema(LLMJSONSchema)
  case text
}

/// Provider-neutral definition for a callable model tool.
public struct LLMToolDefinition: Codable, Equatable, Sendable {
  public var description: String
  public var inputSchema: JSONValue
  public var name: String
  public var strict: Bool

  public init(
    name: String,
    description: String,
    inputSchema: JSONValue,
    strict: Bool = true
  ) {
    self.description = description
    self.inputSchema = inputSchema
    self.name = name
    self.strict = strict
  }
}

extension LLMToolDefinition {
  /// Estimated prompt cost of the definition: name, description, and the compact JSON schema.
  public func estimatedDefinitionTokens(using counter: TokenCounter = .latinHeuristic) -> Int {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let schema = (try? encoder.encode(inputSchema)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    return counter.count(name) + counter.count(description) + counter.count(schema)
  }
}

public enum LLMToolChoice: Equatable, Sendable {
  case auto
  /// Prevents tool calls even when tools are attached. Named `noTools` rather than `none` so an
  /// optional `toolChoice` cannot silently resolve to `Optional.none`.
  case noTools
  case required
  case tool(String)
}

/// A tool call emitted by a model.
public struct LLMToolCall: Codable, Equatable, Identifiable, Sendable {
  public var argumentsJSON: String
  public var id: String
  public var name: String

  public init(
    id: String,
    name: String,
    argumentsJSON: String
  ) {
    self.argumentsJSON = argumentsJSON
    self.id = id
    self.name = name
  }
}

/// A complete provider-neutral generation request.
public struct LLMRequest: Equatable, Sendable {
  public var contextPlan: LLMContextPlan?
  public var instructions: String?
  public var messages: [LLMMessage]
  public var metadata: [String: String]
  public var parameters: LLMGenerationParameters
  public var responseFormat: LLMResponseFormat
  public var toolChoice: LLMToolChoice?
  public var tools: [LLMToolDefinition]

  public init(
    instructions: String? = nil,
    messages: [LLMMessage],
    responseFormat: LLMResponseFormat = .text,
    tools: [LLMToolDefinition] = [],
    toolChoice: LLMToolChoice? = nil,
    parameters: LLMGenerationParameters = LLMGenerationParameters(),
    contextPlan: LLMContextPlan? = nil,
    metadata: [String: String] = [:]
  ) {
    self.contextPlan = contextPlan
    self.instructions = instructions
    self.messages = messages
    self.metadata = metadata
    self.parameters = parameters
    self.responseFormat = responseFormat
    self.toolChoice = toolChoice
    self.tools = tools
  }

  public init(
    prompt: CompiledPrompt,
    responseFormat: LLMResponseFormat = .text,
    tools: [LLMToolDefinition] = [],
    toolChoice: LLMToolChoice? = nil,
    parameters: LLMGenerationParameters = LLMGenerationParameters(),
    metadata: [String: String] = [:]
  ) {
    self.init(
      instructions: prompt.systemInstructions,
      messages: [.user(prompt.userPrompt)],
      responseFormat: responseFormat,
      tools: tools,
      toolChoice: toolChoice,
      parameters: parameters,
      contextPlan: prompt.contextPlan,
      metadata: metadata.merging([
        "promptID": prompt.contract.id,
        "promptVersion": prompt.contract.version,
      ]) { current, _ in current }
    )
  }
}
