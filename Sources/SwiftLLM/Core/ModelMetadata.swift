import Foundation

/// Where request content can travel when a client handles it.
public enum LLMPrivacyMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  /// Content never leaves the device.
  case localOnly
  /// Content stays local, but the app may attach user-selected context.
  case localWithUserSelectedContext
  /// Content is processed by Apple's Private Cloud Compute. It is networked execution with
  /// OS-managed authentication and Apple's privacy guarantees, not on-device execution.
  case privateCloudCompute
  /// Content is sent to an external provider the app explicitly configured.
  case externalOptIn
}

public enum LLMProviderKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case anthropic
  case appleFoundationModels
  case deterministicLocal
  case external
  case openAI
  case testDouble
}

public struct LLMProviderMetadata: Codable, Equatable, Hashable, Sendable {
  public var modelIdentifier: String?
  public var privacyMode: LLMPrivacyMode
  public var promptVersion: String
  public var providerConfigurationID: String?
  public var providerDisplayName: String
  public var providerKind: LLMProviderKind

  public init(
    modelIdentifier: String? = nil,
    privacyMode: LLMPrivacyMode,
    promptVersion: String,
    providerConfigurationID: String? = nil,
    providerDisplayName: String,
    providerKind: LLMProviderKind
  ) {
    self.modelIdentifier = modelIdentifier
    self.privacyMode = privacyMode
    self.promptVersion = promptVersion
    self.providerConfigurationID = providerConfigurationID
    self.providerDisplayName = providerDisplayName
    self.providerKind = providerKind
  }
}

/// Token accounting for one generation.
///
/// Estimated counts always exist and come from the package heuristic or the request budget.
/// Measured counts are provider-reported and are `nil` when the provider did not report them.
public struct LLMTokenUsage: Codable, Equatable, Hashable, Sendable {
  /// Input tokens the provider wrote to a prompt cache during this request.
  public var cacheWriteInputTokens: Int?
  /// Input tokens the provider served from a prompt cache.
  public var cachedInputTokens: Int?
  public var estimatedInputTokens: Int
  public var estimatedOutputTokens: Int
  public var measuredInputTokens: Int?
  public var measuredOutputTokens: Int?
  /// Output tokens spent on reasoning before the answer, when the provider reports them.
  public var reasoningTokens: Int?

  public init(
    estimatedInputTokens: Int,
    estimatedOutputTokens: Int,
    measuredInputTokens: Int? = nil,
    measuredOutputTokens: Int? = nil,
    cachedInputTokens: Int? = nil,
    reasoningTokens: Int? = nil,
    cacheWriteInputTokens: Int? = nil
  ) {
    self.cacheWriteInputTokens = cacheWriteInputTokens
    self.cachedInputTokens = cachedInputTokens
    self.estimatedInputTokens = estimatedInputTokens
    self.estimatedOutputTokens = estimatedOutputTokens
    self.measuredInputTokens = measuredInputTokens
    self.measuredOutputTokens = measuredOutputTokens
    self.reasoningTokens = reasoningTokens
  }

  /// Provider-reported input plus output tokens, or `nil` when either side is unmeasured.
  public var measuredTotalTokens: Int? {
    guard let measuredInputTokens, let measuredOutputTokens else { return nil }
    return measuredInputTokens + measuredOutputTokens
  }
}

public struct LLMError: Error, Equatable, LocalizedError, Sendable {
  public var message: String

  public init(_ message: String) {
    self.message = message
  }

  public var errorDescription: String? {
    message
  }
}
