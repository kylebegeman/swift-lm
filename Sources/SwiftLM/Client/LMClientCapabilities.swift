/// A provider feature that can materially change request behavior.
public enum LMCapability: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  /// The provider honors `toolChoice` values that force a tool call (`required` or a named tool).
  case forcedToolChoice
  case guidedGeneration
  case instructions
  case jsonObjectResponse
  case jsonSchemaResponse
  case nativeJSONSchemaResponse
  case prewarm
  case reasoning
  case sessionTranscript
  case stopSequences
  case streaming
  case temperature
  case toolResults
  case tools
  case topP
}

/// Capability metadata used by routers to skip providers that cannot honor a request.
public struct LMClientCapabilities: Equatable, Sendable {
  public var contextWindowTokens: Int?
  public var supportedFeatures: Set<LMCapability>

  public init(
    supportedFeatures: Set<LMCapability> = Set(LMCapability.allCases),
    contextWindowTokens: Int? = nil
  ) {
    self.contextWindowTokens = contextWindowTokens
    self.supportedFeatures = supportedFeatures
  }

  public func supports(_ capability: LMCapability) -> Bool {
    supportedFeatures.contains(capability)
  }

  public func unsupportedCapabilities(
    for request: LMRequest,
    streaming: Bool = false
  ) -> [LMCapability] {
    request.requiredCapabilities(streaming: streaming)
      .filter { !supports($0) }
      .sorted { $0.rawValue < $1.rawValue }
  }

  public static let broadlyCompatible = Self()

  public static let deterministicLocal = Self(
    supportedFeatures: [
      .forcedToolChoice,
      .instructions,
      .jsonObjectResponse,
      .jsonSchemaResponse,
      .stopSequences,
      .streaming,
      .temperature,
      .toolResults,
      .tools,
      .topP,
    ]
  )

  /// The on-device Apple Foundation Models baseline. The live adapter replaces the context window
  /// with the platform-reported `contextSize` and adds `reasoning` when the resolved model supports it.
  public static let foundationModelsProviderNeutral = Self(
    supportedFeatures: [
      .guidedGeneration,
      .instructions,
      .jsonObjectResponse,
      .jsonSchemaResponse,
      .prewarm,
      .sessionTranscript,
      .streaming,
      .temperature,
    ],
    contextWindowTokens: 4_096
  )

  /// Apple Foundation Models on Private Cloud Compute: the on-device feature set plus reasoning
  /// and the 32K context window Apple documents for the server model.
  public static let foundationModelsPrivateCloudCompute = Self(
    supportedFeatures: Self.foundationModelsProviderNeutral.supportedFeatures.union([.reasoning]),
    contextWindowTokens: 32_768
  )

  public static let openAIResponses = Self(
    supportedFeatures: [
      .forcedToolChoice,
      .instructions,
      .jsonObjectResponse,
      .jsonSchemaResponse,
      .nativeJSONSchemaResponse,
      .reasoning,
      .streaming,
      .temperature,
      .toolResults,
      .tools,
      .topP,
    ]
  )

  public static let anthropicMessages = Self(
    supportedFeatures: [
      .forcedToolChoice,
      .instructions,
      .jsonObjectResponse,
      .jsonSchemaResponse,
      .nativeJSONSchemaResponse,
      .reasoning,
      .stopSequences,
      .streaming,
      .temperature,
      .toolResults,
      .tools,
      .topP,
    ]
  )
}

extension LMRequest {
  public func requiredCapabilities(streaming: Bool = false) -> Set<LMCapability> {
    var capabilities: Set<LMCapability> = []

    if streaming {
      capabilities.insert(.streaming)
    }

    switch responseFormat {
    case .jsonObject:
      capabilities.insert(.jsonObjectResponse)
    case .jsonSchema:
      capabilities.insert(.jsonSchemaResponse)
    case .text:
      break
    }

    if let instructions, !instructions.isEmpty {
      capabilities.insert(.instructions)
    }

    if !tools.isEmpty ||
      toolChoice?.requiresToolSupport == true ||
      messages.contains(where: { !$0.toolCalls.isEmpty })
    {
      capabilities.insert(.tools)
    }

    if toolChoice?.requiresToolSupport == true {
      capabilities.insert(.forcedToolChoice)
    }

    if messages.contains(where: { $0.role == .tool }) {
      capabilities.insert(.toolResults)
    }

    if parameters.temperature != nil {
      capabilities.insert(.temperature)
    }

    if parameters.topP != nil {
      capabilities.insert(.topP)
    }

    if !parameters.stopSequences.isEmpty {
      capabilities.insert(.stopSequences)
    }

    if parameters.reasoningEffort != nil {
      capabilities.insert(.reasoning)
    }

    if let contextPlan {
      capabilities.formUnion(contextPlan.requiredCapabilities)
    }

    return capabilities
  }
}

extension LMToolChoice {
  public var requiresToolSupport: Bool {
    switch self {
    case .auto, .noTools:
      return false
    case .required, .tool:
      return true
    }
  }
}
