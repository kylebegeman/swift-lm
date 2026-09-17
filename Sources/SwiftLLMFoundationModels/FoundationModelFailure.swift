import Foundation
import SwiftLLM

public enum FoundationModelFailureReason: Equatable, Sendable {
  case assetsUnavailable
  case concurrentRequests
  case contextExceeded(contextSize: Int? = nil, tokenCount: Int? = nil)
  case decodingFailure
  case guardrailViolation
  /// The network is reachable but Private Cloud Compute could not be contacted.
  case networkUnavailable
  case quotaLimitReached(resetsAt: Date? = nil, limitIncreaseSuggestionAvailable: Bool = false)
  case rateLimited(resetsAt: Date? = nil)
  case refusal
  case serviceUnavailable
  case timeout
  case toolCallFailed
  case transcriptMutationWhileResponding
  case unavailable(FoundationModelAvailability)
  case unsupportedCapability
  case unsupportedGuide
  case unsupportedLanguageOrLocale
  case unsupportedTranscriptContent
  case providerError
}

public struct FoundationModelFailure: LLMFallbackClassifiableError, Equatable, LocalizedError, Sendable {
  public var debugDescription: String?
  public var reason: FoundationModelFailureReason

  public init(
    reason: FoundationModelFailureReason,
    debugDescription: String? = nil
  ) {
    self.debugDescription = debugDescription
    self.reason = reason
  }

  public var errorDescription: String? {
    switch reason {
    case .assetsUnavailable:
      return "Foundation Models assets are unavailable."
    case .concurrentRequests:
      return "The Foundation Models session is already responding."
    case let .contextExceeded(contextSize, tokenCount):
      if let contextSize, let tokenCount {
        return "The request used \(tokenCount) tokens, which exceeds the \(contextSize)-token context window."
      }
      return "The request exceeded the Foundation Models context window."
    case .decodingFailure:
      return "Foundation Models could not decode the generated structured response."
    case .guardrailViolation:
      return "Foundation Models guardrails rejected the request or response."
    case .networkUnavailable:
      return "Private Cloud Compute could not be reached."
    case .quotaLimitReached:
      return "The Private Cloud Compute usage limit was reached."
    case .rateLimited:
      return "Foundation Models rate-limited the request."
    case .refusal:
      return "Foundation Models refused the request."
    case .serviceUnavailable:
      return "The Foundation Models service could not handle the request."
    case .timeout:
      return "The Foundation Models request timed out."
    case .toolCallFailed:
      return "A Foundation Models tool call failed."
    case .transcriptMutationWhileResponding:
      return "The session transcript was changed while the model was responding."
    case let .unavailable(availability):
      return availability.diagnosticMessage
    case .unsupportedCapability:
      return "The resolved Foundation Models target does not support a requested capability."
    case .unsupportedGuide:
      return "The request used a generation guide Foundation Models does not support."
    case .unsupportedLanguageOrLocale:
      return "Foundation Models does not support the requested language or locale."
    case .unsupportedTranscriptContent:
      return "The session transcript contains content the model does not support."
    case .providerError:
      return "Foundation Models failed to generate a response."
    }
  }

  public var fallbackReason: FallbackReason {
    switch reason {
    case .assetsUnavailable:
      return .assetsUnavailable
    case .concurrentRequests:
      return .concurrentRequest
    case .contextExceeded:
      return .contextExceeded
    case .decodingFailure:
      return .decodingFailed
    case .guardrailViolation:
      return .guardrailViolation
    case .networkUnavailable, .serviceUnavailable:
      return .unavailable
    case .quotaLimitReached:
      return .quotaExceeded
    case .rateLimited:
      return .rateLimited
    case .refusal:
      return .refusal
    case .timeout:
      return .timeout
    case .toolCallFailed:
      return .providerError(debugDescription ?? "Tool call failed.")
    case .transcriptMutationWhileResponding:
      return .providerError(debugDescription ?? "Transcript mutated while responding.")
    case let .unavailable(availability):
      return availability.fallbackReason ?? .unavailable
    case .unsupportedCapability, .unsupportedTranscriptContent:
      return .unsupported
    case .unsupportedGuide:
      return .unsupportedGuide
    case .unsupportedLanguageOrLocale:
      return .unsupportedLocale
    case .providerError:
      return .providerError(debugDescription ?? "Foundation Models failed.")
    }
  }
}
