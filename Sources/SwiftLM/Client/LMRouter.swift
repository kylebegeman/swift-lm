import Foundation

public struct LMRouter: LMClient {
  public var fallbacks: [AnyLMClient]
  public var fallbackPolicy: LMRouterFallbackPolicy
  public var primary: AnyLMClient
  public var runReceiptHandler: (@Sendable (LMRunReceipt) -> Void)?
  public var streamFallbackMode: LMStreamFallbackMode

  public init(
    primary: AnyLMClient,
    fallbacks: [AnyLMClient] = [],
    fallbackPolicy: LMRouterFallbackPolicy = .retryable,
    runReceiptHandler: (@Sendable (LMRunReceipt) -> Void)? = nil,
    streamFallbackMode: LMStreamFallbackMode = .beforeFirstOutput
  ) {
    self.fallbacks = fallbacks
    self.fallbackPolicy = fallbackPolicy
    self.primary = primary
    self.runReceiptHandler = runReceiptHandler
    self.streamFallbackMode = streamFallbackMode
  }

  /// The union of every configured client's features. The context window is the largest window
  /// when every client reports one, and `nil` when any client's window is unknown, because a
  /// request can land on any of them.
  public var capabilities: LMClientCapabilities {
    let clients = configuredClients
    guard var merged = clients.first?.capabilities else {
      return .broadlyCompatible
    }
    for client in clients.dropFirst() {
      merged.supportedFeatures.formUnion(client.capabilities.supportedFeatures)
      if let current = merged.contextWindowTokens,
         let candidate = client.capabilities.contextWindowTokens
      {
        merged.contextWindowTokens = max(current, candidate)
      } else {
        merged.contextWindowTokens = nil
      }
    }
    return merged
  }

  public var metadata: LMProviderMetadata {
    primary.metadata
  }

  public func respond(to request: LMRequest) async throws -> LMResponse {
    do {
      let result = try await respondWithReceipt(to: request)
      runReceiptHandler?(result.receipt)
      return result.response
    } catch let error as LMRunReceiptError {
      runReceiptHandler?(error.receipt)
      throw error.underlyingError
    }
  }

  public func respondWithReceipt(to request: LMRequest) async throws -> LMInstrumentedResponse {
    var lastError: (any Error)?
    let clients = configuredClients
    let runID = UUID().uuidString
    let runStartedAt = Date()
    var receipt = LMRunReceipt(
      id: runID,
      request: LMRunRequestSummary(request: request),
      startedAt: runStartedAt
    )

    for (index, client) in clients.enumerated() {
      try Task.checkCancellation()
      let remainingFallbackCount = clients.count - index - 1
      let context = fallbackContext(
        client: client,
        request: request,
        attemptIndex: index,
        remainingFallbackCount: remainingFallbackCount
      )
      let unsupportedCapabilities = client.capabilities.unsupportedCapabilities(
        for: request,
        streaming: false
      )
      if !unsupportedCapabilities.isEmpty {
        let unsupportedError = Self.unsupportedCapabilitiesError(
          unsupportedCapabilities,
          client: client
        )
        lastError = unsupportedError
        let attemptedAt = Date()
        receipt.attempts.append(
          LMRunAttemptReceipt(
            id: "\(runID)-attempt-\(index)",
            provider: LMProviderReceiptSnapshot(metadata: client.metadata),
            startedAt: attemptedAt,
            completedAt: Date(),
            status: .skippedUnsupportedCapabilities,
            unsupportedCapabilities: unsupportedCapabilities.map(\.rawValue).sorted(),
            error: LMRunErrorReceipt(error: unsupportedError)
          )
        )
        guard remainingFallbackCount > 0,
              fallbackPolicy.shouldAttemptFallback(unsupportedError, context)
        else {
          receipt.completedAt = Date()
          receipt.outcome = .failed
          throw LMRunReceiptError(underlyingError: unsupportedError, receipt: receipt)
        }
        continue
      }

      let attemptedAt = Date()
      do {
        let response = try await client.respond(to: request)
        let completedAt = Date()
        receipt.attempts.append(
          LMRunAttemptReceipt(
            id: "\(runID)-attempt-\(index)",
            provider: LMProviderReceiptSnapshot(metadata: client.metadata),
            startedAt: attemptedAt,
            completedAt: completedAt,
            status: .succeeded,
            tokenUsage: response.tokenUsage.map(LMTokenUsageReceipt.init)
          )
        )
        receipt.completedAt = completedAt
        receipt.finalProvider = LMProviderReceiptSnapshot(metadata: response.metadata)
        receipt.outcome = .succeeded
        receipt.tokenUsage = response.tokenUsage.map(LMTokenUsageReceipt.init)
        return LMInstrumentedResponse(response: response, receipt: receipt)
      } catch {
        lastError = error
        receipt.attempts.append(
          LMRunAttemptReceipt(
            id: "\(runID)-attempt-\(index)",
            provider: LMProviderReceiptSnapshot(metadata: client.metadata),
            startedAt: attemptedAt,
            completedAt: Date(),
            status: .failed,
            error: LMRunErrorReceipt(error: error)
          )
        )
        guard remainingFallbackCount > 0,
              fallbackPolicy.shouldAttemptFallback(error, context)
        else {
          receipt.completedAt = Date()
          receipt.outcome = .failed
          throw LMRunReceiptError(underlyingError: error, receipt: receipt)
        }
      }
    }

    let error = lastError ?? Self.noProvidersError
    receipt.completedAt = Date()
    receipt.outcome = .failed
    throw LMRunReceiptError(underlyingError: error, receipt: receipt)
  }

  /// Streams from the first client that can honor the request, falling back before the first
  /// output event. Receipts are delivered to `runReceiptHandler` when the stream finishes or fails.
  public func stream(to request: LMRequest) -> AsyncThrowingStream<LMStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        let clients = configuredClients
        let runID = UUID().uuidString
        var lastError: (any Error)?
        var receipt = LMRunReceipt(
          id: runID,
          request: LMRunRequestSummary(request: request),
          startedAt: Date()
        )

        func finish(with outcome: LMRunReceiptOutcome, error: (any Error)?) {
          receipt.completedAt = Date()
          receipt.outcome = outcome
          runReceiptHandler?(receipt)
          if let error {
            continuation.finish(throwing: error)
          } else {
            continuation.finish()
          }
        }

        for (index, client) in clients.enumerated() {
          if Task.isCancelled {
            finish(with: .failed, error: CancellationError())
            return
          }
          let remainingFallbackCount = clients.count - index - 1
          let context = fallbackContext(
            client: client,
            request: request,
            attemptIndex: index,
            remainingFallbackCount: remainingFallbackCount
          )
          let attemptedAt = Date()
          let unsupportedCapabilities = client.capabilities.unsupportedCapabilities(
            for: request,
            streaming: true
          )
          if !unsupportedCapabilities.isEmpty {
            let unsupportedError = Self.unsupportedCapabilitiesError(
              unsupportedCapabilities,
              client: client
            )
            lastError = unsupportedError
            receipt.attempts.append(
              LMRunAttemptReceipt(
                id: "\(runID)-attempt-\(index)",
                provider: LMProviderReceiptSnapshot(metadata: client.metadata),
                startedAt: attemptedAt,
                completedAt: Date(),
                status: .skippedUnsupportedCapabilities,
                unsupportedCapabilities: unsupportedCapabilities.map(\.rawValue).sorted(),
                error: LMRunErrorReceipt(error: unsupportedError)
              )
            )
            guard shouldAttemptStreamFallback(
              after: unsupportedError,
              context: context,
              remainingFallbackCount: remainingFallbackCount,
              emittedOutput: false
            )
            else {
              finish(with: .failed, error: unsupportedError)
              return
            }
            continue
          }

          var emittedOutput = false
          var completedResponse: LMResponse?
          do {
            for try await event in client.stream(to: request) {
              if event.isOutput {
                emittedOutput = true
              }
              if case let .completed(response) = event {
                completedResponse = response
              }
              continuation.yield(event)
            }
            let completedAt = Date()
            receipt.attempts.append(
              LMRunAttemptReceipt(
                id: "\(runID)-attempt-\(index)",
                provider: LMProviderReceiptSnapshot(metadata: client.metadata),
                startedAt: attemptedAt,
                completedAt: completedAt,
                status: .succeeded,
                tokenUsage: completedResponse?.tokenUsage.map(LMTokenUsageReceipt.init)
              )
            )
            receipt.finalProvider = LMProviderReceiptSnapshot(
              metadata: completedResponse?.metadata ?? client.metadata
            )
            receipt.tokenUsage = completedResponse?.tokenUsage.map(LMTokenUsageReceipt.init)
            finish(with: .succeeded, error: nil)
            return
          } catch {
            lastError = error
            receipt.attempts.append(
              LMRunAttemptReceipt(
                id: "\(runID)-attempt-\(index)",
                provider: LMProviderReceiptSnapshot(metadata: client.metadata),
                startedAt: attemptedAt,
                completedAt: Date(),
                status: .failed,
                error: LMRunErrorReceipt(error: error)
              )
            )
            guard shouldAttemptStreamFallback(
              after: error,
              context: context,
              remainingFallbackCount: remainingFallbackCount,
              emittedOutput: emittedOutput
            )
            else {
              finish(with: .failed, error: error)
              return
            }
          }
        }

        finish(with: .failed, error: lastError ?? Self.noProvidersError)
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private var configuredClients: [AnyLMClient] {
    [primary] + fallbacks
  }

  private static var noProvidersError: LMClientError {
    LMClientError(
      reason: .unavailable,
      debugDescription: "No providers were configured."
    )
  }

  private func fallbackContext(
    client: AnyLMClient,
    request: LMRequest,
    attemptIndex: Int,
    remainingFallbackCount: Int
  ) -> LMRouterFallbackContext {
    LMRouterFallbackContext(
      attemptIndex: attemptIndex,
      client: client.metadata,
      remainingFallbackCount: remainingFallbackCount,
      request: request
    )
  }

  private func shouldAttemptStreamFallback(
    after error: any Error,
    context: LMRouterFallbackContext,
    remainingFallbackCount: Int,
    emittedOutput: Bool
  ) -> Bool {
    guard streamFallbackMode == .beforeFirstOutput,
          !emittedOutput,
          remainingFallbackCount > 0
    else { return false }

    return fallbackPolicy.shouldAttemptFallback(error, context)
  }

  private static func unsupportedCapabilitiesError(
    _ unsupportedCapabilities: [LMCapability],
    client: AnyLMClient
  ) -> LMClientError {
    LMClientError(
      reason: .unsupported,
      debugDescription: """
      \(client.metadata.providerDisplayName) does not support required capabilities: \
      \(unsupportedCapabilities.map(\.rawValue).joined(separator: ", ")).
      """
    )
  }
}

private extension LMStreamEvent {
  /// Output events mark the point after which the router must not splice in a fallback provider.
  var isOutput: Bool {
    switch self {
    case .completed, .reasoningDelta, .textDelta, .toolCall:
      return true
    case .started, .usage:
      return false
    }
  }
}
