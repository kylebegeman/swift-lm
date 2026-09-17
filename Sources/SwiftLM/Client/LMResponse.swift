import Foundation

public enum LMFinishReason: String, Equatable, Sendable {
  case contentFilter
  case error
  case length
  case stop
  case toolCalls
  case unknown
}

/// A completed provider-neutral generation response.
public struct LMResponse: Equatable, Identifiable, Sendable {
  public var finishReason: LMFinishReason?
  public var id: String
  public var message: LMMessage
  public var metadata: LMProviderMetadata
  public var model: String?
  /// Reasoning or thinking text the provider exposed alongside the answer.
  ///
  /// Providers only surface this when the request asked for reasoning and the provider returns it
  /// as readable text. It is never merged into `text` or `message`.
  public var reasoningText: String?
  public var text: String
  public var tokenUsage: LMTokenUsage?
  public var toolCalls: [LMToolCall]

  public init(
    id: String = UUID().uuidString,
    text: String,
    message: LMMessage? = nil,
    toolCalls: [LMToolCall] = [],
    finishReason: LMFinishReason? = nil,
    tokenUsage: LMTokenUsage? = nil,
    model: String? = nil,
    metadata: LMProviderMetadata,
    reasoningText: String? = nil
  ) {
    self.finishReason = finishReason
    self.id = id
    self.message = message ?? .assistant(text, toolCalls: toolCalls)
    self.metadata = metadata
    self.model = model
    self.reasoningText = reasoningText
    self.text = text
    self.tokenUsage = tokenUsage
    self.toolCalls = toolCalls
  }

  public var candidate: GenerationCandidate<String> {
    GenerationCandidate(
      output: text,
      metadata: metadata,
      tokenUsage: tokenUsage
    )
  }
}

/// Streaming lifecycle events emitted by an `LMClient`.
public enum LMStreamEvent: Equatable, Sendable {
  case completed(LMResponse)
  /// A fragment of reasoning or thinking text. Providers emit it before answer text when they
  /// expose reasoning as readable output.
  case reasoningDelta(String)
  case started(LMProviderMetadata)
  case textDelta(String)
  case toolCall(LMToolCall)
  /// A token usage update reported before completion. The `completed` response carries the
  /// authoritative usage for the whole request.
  case usage(LMTokenUsage)
}

public enum LMClientErrorReason: Equatable, Sendable {
  case authentication
  case badRequest
  case cancelled
  case contextExceeded
  case decoding
  case guardrailViolation
  case network
  case provider(String)
  /// A usage allotment such as a daily request quota or a prepaid balance is exhausted. Unlike a
  /// rate limit, waiting a few seconds does not help.
  case quotaExceeded
  case rateLimited
  case timeout
  case unavailable
  case unsupported
}

public struct LMClientError: LMFallbackClassifiableError, Equatable, LocalizedError, Sendable {
  public var debugDescription: String?
  public var reason: LMClientErrorReason
  public var statusCode: Int?

  public init(
    reason: LMClientErrorReason,
    statusCode: Int? = nil,
    debugDescription: String? = nil
  ) {
    self.debugDescription = debugDescription
    self.reason = reason
    self.statusCode = statusCode
  }

  public var errorDescription: String? {
    switch reason {
    case .authentication:
      return "The provider rejected the configured credentials."
    case .badRequest:
      return "The provider rejected the request."
    case .cancelled:
      return "The generation request was cancelled."
    case .contextExceeded:
      return "The request exceeded the model context window."
    case .decoding:
      return "The provider response could not be decoded."
    case .guardrailViolation:
      return "The provider rejected the request or response for safety reasons."
    case .network:
      return "The provider request failed before a response was received."
    case let .provider(message):
      return message
    case .quotaExceeded:
      return "The provider usage quota is exhausted."
    case .rateLimited:
      return "The provider rate-limited the request."
    case .timeout:
      return "The provider request timed out."
    case .unavailable:
      return "The provider is unavailable."
    case .unsupported:
      return "The provider does not support this request."
    }
  }

  public var fallbackReason: FallbackReason {
    switch reason {
    case .authentication, .badRequest, .provider:
      return .providerError(debugDescription ?? errorDescription ?? "Provider error.")
    case .network:
      return .unavailable
    case .cancelled:
      return .providerError("Request cancelled.")
    case .contextExceeded:
      return .contextExceeded
    case .decoding:
      return .decodingFailed
    case .guardrailViolation:
      return .guardrailViolation
    case .quotaExceeded:
      return .quotaExceeded
    case .rateLimited:
      return .rateLimited
    case .timeout:
      return .timeout
    case .unavailable:
      return .unavailable
    case .unsupported:
      return .unsupported
    }
  }
}
