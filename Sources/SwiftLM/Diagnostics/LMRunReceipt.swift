import Foundation

/// A compact, redacted summary of the request shape used for diagnostics.
public struct LMRunRequestSummary: Codable, Equatable, Sendable {
  public var contextItemCount: Int
  public var estimatedContextTokens: Int?
  public var messageCount: Int
  public var promptID: String?
  public var promptVersion: String?
  public var requiredCapabilities: [String]
  public var responseFormat: String
  public var toolCount: Int
  public var toolResultCount: Int

  public init(
    contextItemCount: Int,
    estimatedContextTokens: Int? = nil,
    messageCount: Int,
    promptID: String? = nil,
    promptVersion: String? = nil,
    requiredCapabilities: [String],
    responseFormat: String,
    toolCount: Int,
    toolResultCount: Int
  ) {
    self.contextItemCount = contextItemCount
    self.estimatedContextTokens = estimatedContextTokens
    self.messageCount = messageCount
    self.promptID = promptID
    self.promptVersion = promptVersion
    self.requiredCapabilities = requiredCapabilities
    self.responseFormat = responseFormat
    self.toolCount = toolCount
    self.toolResultCount = toolResultCount
  }

  public init(request: LMRequest) {
    self.init(
      contextItemCount: request.contextPlan?.items.count ?? 0,
      estimatedContextTokens: request.contextPlan?.estimatedInputTokens(),
      messageCount: request.messages.count,
      promptID: request.metadata["promptID"],
      promptVersion: request.metadata["promptVersion"],
      requiredCapabilities: request.requiredCapabilities().map(\.rawValue).sorted(),
      responseFormat: request.responseFormat.diagnosticName,
      toolCount: request.tools.count,
      toolResultCount: request.messages.filter { $0.role == .tool }.count
    )
  }
}

/// Provider metadata copied into diagnostics without depending on app-specific client types.
public struct LMProviderReceiptSnapshot: Codable, Equatable, Sendable {
  public var modelIdentifier: String?
  public var privacyMode: String
  public var promptVersion: String
  public var providerConfigurationID: String?
  public var providerDisplayName: String
  public var providerKind: String

  public init(
    modelIdentifier: String? = nil,
    privacyMode: String,
    promptVersion: String,
    providerConfigurationID: String? = nil,
    providerDisplayName: String,
    providerKind: String
  ) {
    self.modelIdentifier = modelIdentifier
    self.privacyMode = privacyMode
    self.promptVersion = promptVersion
    self.providerConfigurationID = providerConfigurationID
    self.providerDisplayName = providerDisplayName
    self.providerKind = providerKind
  }

  public init(metadata: LMProviderMetadata) {
    self.init(
      modelIdentifier: metadata.modelIdentifier,
      privacyMode: metadata.privacyMode.rawValue,
      promptVersion: metadata.promptVersion,
      providerConfigurationID: metadata.providerConfigurationID,
      providerDisplayName: metadata.providerDisplayName,
      providerKind: metadata.providerKind.rawValue
    )
  }
}

public struct LMTokenUsageReceipt: Codable, Equatable, Sendable {
  public var cacheWriteInputTokens: Int?
  public var cachedInputTokens: Int?
  public var estimatedInputTokens: Int
  public var estimatedOutputTokens: Int
  public var measuredInputTokens: Int?
  public var measuredOutputTokens: Int?
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

  public init(usage: LMTokenUsage) {
    self.init(
      estimatedInputTokens: usage.estimatedInputTokens,
      estimatedOutputTokens: usage.estimatedOutputTokens,
      measuredInputTokens: usage.measuredInputTokens,
      measuredOutputTokens: usage.measuredOutputTokens,
      cachedInputTokens: usage.cachedInputTokens,
      reasoningTokens: usage.reasoningTokens,
      cacheWriteInputTokens: usage.cacheWriteInputTokens
    )
  }
}

public enum LMRunAttemptStatus: String, Codable, Equatable, Sendable {
  case failed
  case skippedUnsupportedCapabilities
  case succeeded
}

public struct LMRunErrorReceipt: Codable, Equatable, Sendable {
  public var errorType: String
  public var fallbackReason: String?
  public var providerReason: String?
  public var statusCode: Int?

  public init(
    errorType: String,
    fallbackReason: String? = nil,
    providerReason: String? = nil,
    statusCode: Int? = nil
  ) {
    self.errorType = errorType
    self.fallbackReason = fallbackReason
    self.providerReason = providerReason
    self.statusCode = statusCode
  }

  public init(error: any Error) {
    let clientError = error as? LMClientError
    self.init(
      errorType: String(reflecting: type(of: error)),
      fallbackReason: (error as? any LMFallbackClassifiableError)?.fallbackReason.diagnosticCode,
      providerReason: clientError?.reason.diagnosticCode,
      statusCode: clientError?.statusCode
    )
  }
}

public struct LMRunAttemptReceipt: Codable, Equatable, Identifiable, Sendable {
  public var completedAt: Date?
  public var durationMilliseconds: Double?
  public var error: LMRunErrorReceipt?
  public var id: String
  public var provider: LMProviderReceiptSnapshot
  public var startedAt: Date
  public var status: LMRunAttemptStatus
  public var tokenUsage: LMTokenUsageReceipt?
  public var unsupportedCapabilities: [String]

  public init(
    id: String,
    provider: LMProviderReceiptSnapshot,
    startedAt: Date,
    completedAt: Date? = nil,
    status: LMRunAttemptStatus,
    unsupportedCapabilities: [String] = [],
    error: LMRunErrorReceipt? = nil,
    tokenUsage: LMTokenUsageReceipt? = nil
  ) {
    self.completedAt = completedAt
    self.durationMilliseconds = completedAt.map { $0.timeIntervalSince(startedAt) * 1_000 }
    self.error = error
    self.id = id
    self.provider = provider
    self.startedAt = startedAt
    self.status = status
    self.tokenUsage = tokenUsage
    self.unsupportedCapabilities = unsupportedCapabilities
  }
}

public enum LMRunReceiptOutcome: String, Codable, Equatable, Sendable {
  case failed
  case succeeded
}

/// A redacted local diagnostic receipt for one provider-neutral generation run.
public struct LMRunReceipt: Codable, Equatable, Identifiable, Sendable {
  public var attempts: [LMRunAttemptReceipt]
  public var completedAt: Date?
  public var finalProvider: LMProviderReceiptSnapshot?
  public var id: String
  public var outcome: LMRunReceiptOutcome
  public var request: LMRunRequestSummary
  public var startedAt: Date
  public var tokenUsage: LMTokenUsageReceipt?

  public init(
    id: String = UUID().uuidString,
    request: LMRunRequestSummary,
    startedAt: Date = Date(),
    completedAt: Date? = nil,
    outcome: LMRunReceiptOutcome = .failed,
    attempts: [LMRunAttemptReceipt] = [],
    finalProvider: LMProviderReceiptSnapshot? = nil,
    tokenUsage: LMTokenUsageReceipt? = nil
  ) {
    self.attempts = attempts
    self.completedAt = completedAt
    self.finalProvider = finalProvider
    self.id = id
    self.outcome = outcome
    self.request = request
    self.startedAt = startedAt
    self.tokenUsage = tokenUsage
  }

  public var durationMilliseconds: Double? {
    completedAt.map { $0.timeIntervalSince(startedAt) * 1_000 }
  }

  public func jsonData(prettyPrinted: Bool = true) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    return try encoder.encode(self)
  }
}

public struct LMInstrumentedResponse: Sendable {
  public var receipt: LMRunReceipt
  public var response: LMResponse

  public init(
    response: LMResponse,
    receipt: LMRunReceipt
  ) {
    self.receipt = receipt
    self.response = response
  }
}

public struct LMRunReceiptError: Error, LocalizedError {
  public var receipt: LMRunReceipt
  public var underlyingError: any Error

  public init(
    underlyingError: any Error,
    receipt: LMRunReceipt
  ) {
    self.receipt = receipt
    self.underlyingError = underlyingError
  }

  public var errorDescription: String? {
    (underlyingError as? any LocalizedError)?.errorDescription ?? underlyingError.localizedDescription
  }
}

extension FallbackReason {
  public var diagnosticCode: String {
    switch self {
    case .assetsUnavailable:
      return "assetsUnavailable"
    case .concurrentRequest:
      return "concurrentRequest"
    case .contextExceeded:
      return "contextExceeded"
    case .decodingFailed:
      return "decodingFailed"
    case .guardrailViolation:
      return "guardrailViolation"
    case .providerError:
      return "providerError"
    case .quotaExceeded:
      return "quotaExceeded"
    case .rateLimited:
      return "rateLimited"
    case .refusal:
      return "refusal"
    case .timeout:
      return "timeout"
    case .unavailable:
      return "unavailable"
    case .unsupported:
      return "unsupported"
    case .unsupportedGuide:
      return "unsupportedGuide"
    case .unsupportedLocale:
      return "unsupportedLocale"
    case .validationFailed:
      return "validationFailed"
    }
  }
}

extension LMClientErrorReason {
  public var diagnosticCode: String {
    switch self {
    case .authentication:
      return "authentication"
    case .badRequest:
      return "badRequest"
    case .cancelled:
      return "cancelled"
    case .contextExceeded:
      return "contextExceeded"
    case .decoding:
      return "decoding"
    case .guardrailViolation:
      return "guardrailViolation"
    case .network:
      return "network"
    case .provider:
      return "provider"
    case .quotaExceeded:
      return "quotaExceeded"
    case .rateLimited:
      return "rateLimited"
    case .timeout:
      return "timeout"
    case .unavailable:
      return "unavailable"
    case .unsupported:
      return "unsupported"
    }
  }
}

private extension LMResponseFormat {
  var diagnosticName: String {
    switch self {
    case .jsonObject:
      return "jsonObject"
    case .jsonSchema:
      return "jsonSchema"
    case .text:
      return "text"
    }
  }
}
