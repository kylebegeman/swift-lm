import Foundation

public enum FallbackReason: Equatable, Sendable {
  case assetsUnavailable
  case concurrentRequest
  case decodingFailed
  case unavailable
  case unsupportedLocale
  case unsupportedGuide
  case contextExceeded
  case guardrailViolation
  case quotaExceeded
  case rateLimited
  case refusal
  case timeout
  case unsupported
  case validationFailed
  case providerError(String)
}

public protocol LMFallbackClassifiableError: Error, Sendable {
  var fallbackReason: FallbackReason { get }
}

public struct FallbackDecision<Output: Sendable>: Sendable {
  public var output: Output?
  public var reason: FallbackReason

  public init(output: Output?, reason: FallbackReason) {
    self.output = output
    self.reason = reason
  }
}

extension FallbackDecision: Equatable where Output: Equatable {}

public struct GenerationCandidate<Output: Sendable>: Sendable {
  public var metadata: LMProviderMetadata
  public var output: Output
  public var tokenUsage: LMTokenUsage?

  public init(
    output: Output,
    metadata: LMProviderMetadata,
    tokenUsage: LMTokenUsage? = nil
  ) {
    self.output = output
    self.metadata = metadata
    self.tokenUsage = tokenUsage
  }
}

extension GenerationCandidate: Equatable where Output: Equatable {}
