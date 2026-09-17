import Foundation

/// A common async interface for local and provider-backed language model clients.
public protocol LMClient: Sendable {
  var capabilities: LMClientCapabilities { get }
  var metadata: LMProviderMetadata { get }

  func respond(to request: LMRequest) async throws -> LMResponse
  func stream(to request: LMRequest) -> AsyncThrowingStream<LMStreamEvent, any Error>
}

extension LMClient {
  public var capabilities: LMClientCapabilities {
    .broadlyCompatible
  }

  /// Bridges `respond(to:)` into the streaming event sequence for clients without native streaming.
  public func stream(to request: LMRequest) -> AsyncThrowingStream<LMStreamEvent, any Error> {
    LMStreamEvent.stream(metadata: metadata) {
      try await respond(to: request)
    }
  }
}

extension LMStreamEvent {
  /// Emits one complete response as `started`, optional `reasoningDelta`, `textDelta`,
  /// `toolCall`, and `completed` events.
  ///
  /// Adapters without native streaming use this so routers and UI code can treat every client
  /// uniformly. The task that produces the response is cancelled when the stream is terminated.
  public static func stream(
    metadata: LMProviderMetadata,
    respond: @escaping @Sendable () async throws -> LMResponse
  ) -> AsyncThrowingStream<LMStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(.started(metadata))
      let task = Task {
        do {
          let response = try await respond()
          if let reasoningText = response.reasoningText, !reasoningText.isEmpty {
            continuation.yield(.reasoningDelta(reasoningText))
          }
          continuation.yield(.textDelta(response.text))
          for toolCall in response.toolCalls {
            continuation.yield(.toolCall(toolCall))
          }
          continuation.yield(.completed(response))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

/// Type-erased wrapper that lets routers and pipelines store heterogeneous clients.
public struct AnyLMClient: LMClient {
  private var respondHandler: @Sendable (LMRequest) async throws -> LMResponse
  private var streamHandler: @Sendable (LMRequest) -> AsyncThrowingStream<LMStreamEvent, any Error>

  public var capabilities: LMClientCapabilities
  public var metadata: LMProviderMetadata

  public init<C: LMClient>(_ client: C) {
    self.capabilities = client.capabilities
    self.metadata = client.metadata
    self.respondHandler = { request in
      try await client.respond(to: request)
    }
    self.streamHandler = { request in
      client.stream(to: request)
    }
  }

  public init(
    metadata: LMProviderMetadata,
    capabilities: LMClientCapabilities = .broadlyCompatible,
    respond: @escaping @Sendable (LMRequest) async throws -> LMResponse,
    stream: (@Sendable (LMRequest) -> AsyncThrowingStream<LMStreamEvent, any Error>)? = nil
  ) {
    self.capabilities = capabilities
    self.metadata = metadata
    self.respondHandler = respond
    self.streamHandler = stream ?? { request in
      LMStreamEvent.stream(metadata: metadata) {
        try await respond(request)
      }
    }
  }

  public func respond(to request: LMRequest) async throws -> LMResponse {
    try await respondHandler(request)
  }

  public func stream(to request: LMRequest) -> AsyncThrowingStream<LMStreamEvent, any Error> {
    streamHandler(request)
  }

  public static func testDouble(
    modelIdentifier: String = "test-double",
    promptVersion: String = "test",
    respond: @escaping @Sendable (LMRequest) async throws -> String
  ) -> Self {
    let metadata = LMProviderMetadata(
      modelIdentifier: modelIdentifier,
      privacyMode: .localOnly,
      promptVersion: promptVersion,
      providerDisplayName: "Test Double",
      providerKind: .testDouble
    )
    return Self(metadata: metadata, capabilities: .deterministicLocal) { request in
      LMResponse(
        text: try await respond(request),
        metadata: metadata
      )
    }
  }
}
