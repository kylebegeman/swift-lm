import Foundation

/// A common async interface for local and provider-backed language model clients.
public protocol LLMClient: Sendable {
  var capabilities: LLMClientCapabilities { get }
  var metadata: LLMProviderMetadata { get }

  func respond(to request: LLMRequest) async throws -> LLMResponse
  func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error>
}

extension LLMClient {
  public var capabilities: LLMClientCapabilities {
    .broadlyCompatible
  }

  /// Bridges `respond(to:)` into the streaming event sequence for clients without native streaming.
  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    LLMStreamEvent.stream(metadata: metadata) {
      try await respond(to: request)
    }
  }
}

extension LLMStreamEvent {
  /// Emits one complete response as `started`, optional `reasoningDelta`, `textDelta`,
  /// `toolCall`, and `completed` events.
  ///
  /// Adapters without native streaming use this so routers and UI code can treat every client
  /// uniformly. The task that produces the response is cancelled when the stream is terminated.
  public static func stream(
    metadata: LLMProviderMetadata,
    respond: @escaping @Sendable () async throws -> LLMResponse
  ) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
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
public struct AnyLLMClient: LLMClient {
  private var respondHandler: @Sendable (LLMRequest) async throws -> LLMResponse
  private var streamHandler: @Sendable (LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error>

  public var capabilities: LLMClientCapabilities
  public var metadata: LLMProviderMetadata

  public init<C: LLMClient>(_ client: C) {
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
    metadata: LLMProviderMetadata,
    capabilities: LLMClientCapabilities = .broadlyCompatible,
    respond: @escaping @Sendable (LLMRequest) async throws -> LLMResponse,
    stream: (@Sendable (LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error>)? = nil
  ) {
    self.capabilities = capabilities
    self.metadata = metadata
    self.respondHandler = respond
    self.streamHandler = stream ?? { request in
      LLMStreamEvent.stream(metadata: metadata) {
        try await respond(request)
      }
    }
  }

  public func respond(to request: LLMRequest) async throws -> LLMResponse {
    try await respondHandler(request)
  }

  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    streamHandler(request)
  }

  public static func testDouble(
    modelIdentifier: String = "test-double",
    promptVersion: String = "test",
    respond: @escaping @Sendable (LLMRequest) async throws -> String
  ) -> Self {
    let metadata = LLMProviderMetadata(
      modelIdentifier: modelIdentifier,
      privacyMode: .localOnly,
      promptVersion: promptVersion,
      providerDisplayName: "Test Double",
      providerKind: .testDouble
    )
    return Self(metadata: metadata, capabilities: .deterministicLocal) { request in
      LLMResponse(
        text: try await respond(request),
        metadata: metadata
      )
    }
  }
}
