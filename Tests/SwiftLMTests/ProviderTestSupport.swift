import Foundation
import SwiftLM
import SwiftLMAnthropic
import SwiftLMOpenAI

// MARK: - Request Capture

actor RequestCapture<Request: Sendable> {
  private var request: Request?

  func record(_ request: Request) {
    self.request = request
  }

  func value() -> Request? {
    request
  }
}

// MARK: - Request JSON

extension OpenAIHTTPRequest {
  func jsonObject() throws -> [String: JSONValue] {
    try JSONDecoder().decode(JSONValue.self, from: body).objectValue ?? [:]
  }
}

extension AnthropicHTTPRequest {
  func jsonObject() throws -> [String: JSONValue] {
    try JSONDecoder().decode(JSONValue.self, from: body).objectValue ?? [:]
  }
}

// MARK: - Stream Events

extension Array where Element == LMStreamEvent {
  var completedResponse: LMResponse? {
    compactMap { event -> LMResponse? in
      guard case let .completed(response) = event else { return nil }
      return response
    }
    .last
  }

  var startedProviders: [LMProviderKind] {
    compactMap { event -> LMProviderKind? in
      guard case let .started(metadata) = event else { return nil }
      return metadata.providerKind
    }
  }

  var reasoningDeltas: [String] {
    compactMap { event -> String? in
      guard case let .reasoningDelta(delta) = event else { return nil }
      return delta
    }
  }

  var textDeltas: [String] {
    compactMap { event -> String? in
      guard case let .textDelta(delta) = event else { return nil }
      return delta
    }
  }

  var toolCalls: [LMToolCall] {
    compactMap { event -> LMToolCall? in
      guard case let .toolCall(toolCall) = event else { return nil }
      return toolCall
    }
  }
}

// MARK: - Stream Fixtures

func lineStream(_ lines: [String]) -> AsyncThrowingStream<String, any Error> {
  AsyncThrowingStream { continuation in
    for line in lines {
      continuation.yield(line)
    }
    continuation.finish()
  }
}
