import Foundation

public struct LMRouterFallbackContext: Sendable {
  public var attemptIndex: Int
  public var client: LMProviderMetadata
  public var remainingFallbackCount: Int
  public var request: LMRequest

  public init(
    attemptIndex: Int,
    client: LMProviderMetadata,
    remainingFallbackCount: Int,
    request: LMRequest
  ) {
    self.attemptIndex = attemptIndex
    self.client = client
    self.remainingFallbackCount = remainingFallbackCount
    self.request = request
  }
}

public struct LMRouterFallbackPolicy: Sendable {
  public var shouldAttemptFallback: @Sendable (any Error, LMRouterFallbackContext) -> Bool

  public init(
    shouldAttemptFallback: @escaping @Sendable (any Error, LMRouterFallbackContext) -> Bool
  ) {
    self.shouldAttemptFallback = shouldAttemptFallback
  }

  public static let retryable = Self { error, _ in
    let fallbackReason = (error as? any LMFallbackClassifiableError)?.fallbackReason
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

public enum LMStreamFallbackMode: Equatable, Sendable {
  case beforeFirstOutput
  case disabled
}
