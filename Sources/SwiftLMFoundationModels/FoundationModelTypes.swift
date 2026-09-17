import Foundation
import SwiftLM

public enum FoundationModelDefaults {
  public static let defaultPromptVersion = "foundation-models-v1"
  /// The on-device context window on the OS 26.0 releases. Newer releases and hardware report
  /// larger sizes through `contextSize`; read `FoundationModelClient.runtimeProfile(for:)` instead
  /// of assuming this value.
  public static let onDeviceContextWindowTokens = 4_096
  /// The Private Cloud Compute context window Apple documents for the OS 27 releases.
  public static let privateCloudContextWindowTokens = 32_768

  public static func metadata(
    promptVersion: String = Self.defaultPromptVersion,
    modelIdentifier: String? = nil,
    executionTarget: FoundationModelExecutionTarget = .onDevice
  ) -> LMProviderMetadata {
    LMProviderMetadata(
      modelIdentifier: modelIdentifier ?? executionTarget.defaultModelIdentifier,
      privacyMode: executionTarget.privacyMode,
      promptVersion: promptVersion,
      providerDisplayName: "Apple Foundation Models",
      providerKind: .appleFoundationModels
    )
  }
}

public enum FoundationModelUseCase: String, CaseIterable, Equatable, Hashable, Sendable {
  case general
  case contentTagging
}

public enum FoundationModelAvailability: Equatable, Sendable {
  case available
  case appleIntelligenceNotEnabled
  case deviceNotEligible
  case modelNotReady
  /// Private Cloud Compute is not ready to serve requests.
  case systemNotReady
  /// The person's Private Cloud Compute quota is exhausted until `resetsAt`.
  case quotaLimitReached(resetsAt: Date?)
  case unsupportedLocale(String?)
  /// The execution target needs a bridge the live adapter does not provide yet.
  case unsupportedExecutionTarget(String)
  case unavailableInBuild
  case unsupportedOS
  case unknown(String)

  public var isAvailable: Bool {
    self == .available
  }

  public var fallbackReason: FallbackReason? {
    switch self {
    case .available:
      return nil
    case .unsupportedLocale:
      return .unsupportedLocale
    case .quotaLimitReached:
      return .quotaExceeded
    case .unsupportedExecutionTarget:
      return .unsupported
    case .appleIntelligenceNotEnabled,
      .deviceNotEligible,
      .modelNotReady,
      .systemNotReady,
      .unavailableInBuild,
      .unsupportedOS,
      .unknown:
      return .unavailable
    }
  }

  public var diagnosticMessage: String {
    switch self {
    case .available:
      return "Foundation Models are available."
    case .appleIntelligenceNotEnabled:
      return "Apple Intelligence is not enabled."
    case .deviceNotEligible:
      return "This device is not eligible for Apple Intelligence."
    case .modelNotReady:
      return "The local language model is not ready."
    case .systemNotReady:
      return "Private Cloud Compute is not ready to serve requests."
    case let .quotaLimitReached(resetsAt):
      if let resetsAt {
        return "The Private Cloud Compute usage limit was reached. It resets at \(resetsAt.formatted())."
      }
      return "The Private Cloud Compute usage limit was reached."
    case let .unsupportedLocale(identifier):
      if let identifier {
        return "The language model does not support locale \(identifier)."
      }
      return "The language model does not support the current locale."
    case let .unsupportedExecutionTarget(target):
      return "The execution target \(target) needs a LanguageModel. Create the client with FoundationModelClient.live(model:executionTarget:contextWindowTokens:)."
    case .unavailableInBuild:
      return "Foundation Models are unavailable in this build."
    case .unsupportedOS:
      return "Foundation Models require the OS 26 releases. Private Cloud Compute requires the OS 27 releases."
    case let .unknown(message):
      return message
    }
  }
}

public enum FoundationModelSamplingMode: Equatable, Sendable {
  case systemDefault
  case greedy
  case randomTop(Int, seed: UInt64? = nil)
  case randomProbabilityThreshold(Double, seed: UInt64? = nil)
}

/// How the model may use the tools attached to a request.
///
/// `disallowed` and `required` map to Apple's tool calling modes on the OS 27 releases. On OS 26
/// SDKs the live adapter rejects them instead of silently allowing tool calls.
public enum FoundationModelToolCallingMode: String, CaseIterable, Equatable, Hashable, Sendable {
  case allowed
  case disallowed
  case required
}

public struct FoundationModelGenerationOptions: Equatable, Sendable {
  public var executionTarget: FoundationModelExecutionTarget
  public var includeSchemaInPrompt: Bool
  public var maximumResponseTokens: Int?
  /// Reasoning depth for targets that support it. The live adapter rejects a non-nil value when
  /// the resolved model cannot reason, so routers can fall back instead of silently ignoring it.
  public var reasoningEffort: LMReasoningEffort?
  public var sampling: FoundationModelSamplingMode
  public var temperature: Double?
  public var toolCallingMode: FoundationModelToolCallingMode

  public init(
    sampling: FoundationModelSamplingMode = .greedy,
    temperature: Double? = 0.1,
    maximumResponseTokens: Int? = nil,
    includeSchemaInPrompt: Bool = true,
    executionTarget: FoundationModelExecutionTarget = .automatic,
    reasoningEffort: LMReasoningEffort? = nil,
    toolCallingMode: FoundationModelToolCallingMode = .allowed
  ) {
    self.executionTarget = executionTarget
    self.includeSchemaInPrompt = includeSchemaInPrompt
    self.maximumResponseTokens = maximumResponseTokens
    self.reasoningEffort = reasoningEffort
    self.sampling = sampling
    self.temperature = temperature
    self.toolCallingMode = toolCallingMode
  }

  public static let deterministic = Self()
}

public struct FoundationModelPrewarmRequest: Equatable, Sendable {
  public var executionTarget: FoundationModelExecutionTarget
  public var instructions: String
  public var promptPrefix: String?
  public var useCase: FoundationModelUseCase

  public init(
    instructions: String,
    promptPrefix: String? = nil,
    useCase: FoundationModelUseCase = .general,
    executionTarget: FoundationModelExecutionTarget = .automatic
  ) {
    self.executionTarget = executionTarget
    self.instructions = instructions
    self.promptPrefix = promptPrefix
    self.useCase = useCase
  }
}

public struct FoundationModelTokenCountRequest: Equatable, Sendable {
  public var text: String
  public var useCase: FoundationModelUseCase

  public init(
    text: String,
    useCase: FoundationModelUseCase = .general
  ) {
    self.text = text
    self.useCase = useCase
  }
}

/// One earlier turn of a Foundation Models conversation.
///
/// The adapter replays turns as transcript entries, so the model sees the conversation's real
/// structure instead of one flattened prompt.
public struct FoundationModelTranscriptTurn: Codable, Equatable, Hashable, Sendable {
  public enum Role: String, Codable, Equatable, Hashable, Sendable {
    case prompt
    case response
  }

  public var role: Role
  public var text: String

  public init(role: Role, text: String) {
    self.role = role
    self.text = text
  }

  public static func prompt(_ text: String) -> Self {
    Self(role: .prompt, text: text)
  }

  public static func response(_ text: String) -> Self {
    Self(role: .response, text: text)
  }
}

public struct FoundationModelGenerationRequest: Equatable, Sendable {
  /// Earlier turns, replayed as transcript entries before `prompt.userPrompt`.
  public var history: [FoundationModelTranscriptTurn]
  /// Images sent with `prompt.userPrompt`. They need a model that accepts images, which means the
  /// OS 27 releases.
  public var images: [LMImage]
  public var options: FoundationModelGenerationOptions
  public var prompt: CompiledPrompt
  public var prewarmPromptPrefix: String?
  public var useCase: FoundationModelUseCase

  public init(
    prompt: CompiledPrompt,
    options: FoundationModelGenerationOptions = .deterministic,
    useCase: FoundationModelUseCase = .general,
    prewarmPromptPrefix: String? = nil,
    history: [FoundationModelTranscriptTurn] = [],
    images: [LMImage] = []
  ) {
    self.history = history
    self.images = images
    self.options = options
    self.prompt = prompt
    self.prewarmPromptPrefix = prewarmPromptPrefix ?? prompt.contextPlan?.prewarmPromptPrefix
    self.useCase = useCase
  }
}

public struct FoundationModelGenerationResponse<Content: Sendable>: Sendable {
  public var completedAt: Date
  public var content: Content
  public var finishReason: LMFinishReason
  public var metadata: LMProviderMetadata
  /// Reasoning text the model produced before the answer, when the target exposes it.
  public var reasoningText: String?
  /// The runtime facts resolved for this request, including the reported context window and,
  /// for Private Cloud Compute, the quota state after the request.
  public var runtimeProfile: FoundationModelRuntimeProfile?
  public var startedAt: Date
  public var tokenUsage: LMTokenUsage

  public init(
    content: Content,
    metadata: LMProviderMetadata,
    tokenUsage: LMTokenUsage,
    startedAt: Date,
    completedAt: Date,
    finishReason: LMFinishReason = .stop,
    reasoningText: String? = nil,
    runtimeProfile: FoundationModelRuntimeProfile? = nil
  ) {
    self.completedAt = completedAt
    self.content = content
    self.finishReason = finishReason
    self.metadata = metadata
    self.reasoningText = reasoningText
    self.runtimeProfile = runtimeProfile
    self.startedAt = startedAt
    self.tokenUsage = tokenUsage
  }

  public var candidate: GenerationCandidate<Content> {
    GenerationCandidate(
      output: content,
      metadata: metadata,
      tokenUsage: tokenUsage
    )
  }
}

extension FoundationModelGenerationResponse: Equatable where Content: Equatable {}

/// Events emitted while a Foundation Models text response streams.
public enum FoundationModelStreamEvent: Equatable, Sendable {
  case textDelta(String)
  case completed(FoundationModelGenerationResponse<String>)
}
