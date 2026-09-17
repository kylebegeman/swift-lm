import Foundation

public struct LLMRouterFallbackContext: Sendable {
  public var attemptIndex: Int
  public var client: LLMProviderMetadata
  public var remainingFallbackCount: Int
  public var request: LLMRequest

  public init(
    attemptIndex: Int,
    client: LLMProviderMetadata,
    remainingFallbackCount: Int,
    request: LLMRequest
  ) {
    self.attemptIndex = attemptIndex
    self.client = client
    self.remainingFallbackCount = remainingFallbackCount
    self.request = request
  }
}

public struct LLMRouterFallbackPolicy: Sendable {
  public var shouldAttemptFallback: @Sendable (any Error, LLMRouterFallbackContext) -> Bool

  public init(
    shouldAttemptFallback: @escaping @Sendable (any Error, LLMRouterFallbackContext) -> Bool
  ) {
    self.shouldAttemptFallback = shouldAttemptFallback
  }

  public static let retryable = Self { error, _ in
    let fallbackReason = (error as? any LLMFallbackClassifiableError)?.fallbackReason
    switch fallbackReason {
    case .assetsUnavailable,
      .concurrentRequest,
      .contextExceeded,
      .quotaExceeded,
      .rateLimited,
      .timeout,
      .unavailable,
      .unsupported,
      .unsupportedGuide,
      .unsupportedLocale:
      return true
    case .decodingFailed,
      .guardrailViolation,
      .providerError,
      .refusal,
      .validationFailed,
      nil:
      return false
    }
  }

  public static let always = Self { _, _ in true }

  public static let never = Self { _, _ in false }
}

public enum LLMStreamFallbackMode: Equatable, Sendable {
  case beforeFirstOutput
  case disabled
}
