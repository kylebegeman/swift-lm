import Foundation
import SwiftLLM

extension OpenAIClient {
  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let metadata = metadata(for: request)
      continuation.yield(.started(metadata))
      let task = Task {
        do {
          let httpRequest = try responsesHTTPRequest(for: request, stream: true)
          let streamResponse = try await transport.stream(httpRequest)
          guard 200..<300 ~= streamResponse.statusCode else {
            throw await Self.streamFailure(streamResponse)
          }

          var state = OpenAIStreamState()
          // Each SSE event carries one JSON object on its `data:` line, so every line is dispatched
          // as it arrives. Blank separator lines are not required: `URLSession` line streams omit them.
          for try await line in streamResponse.lines {
            try Task.checkCancellation()
            guard let payload = Self.dataPayload(from: line) else { continue }
            try Self.process(
              payload,
              state: &state,
              continuation: continuation,
              metadata: metadata
            )
            if state.completedResponse != nil {
              break
            }
          }

          guard let response = state.completedResponse else {
            throw LLMClientError(
              reason: .network,
              debugDescription: "The OpenAI stream ended before a terminal response event."
            )
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

  static func dataPayload(from line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("data:") else { return nil }
    let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
    guard !payload.isEmpty, payload != "[DONE]" else { return nil }
    return payload
  }

  private static func streamFailure(_ response: OpenAIHTTPStreamResponse) async -> LLMClientError {
    var body = ""
    do {
      for try await line in response.lines {
        body += line
      }
    } catch {
      // The status code already describes the failure; the body is only supplementary.
    }
    return failure(statusCode: response.statusCode, body: Data(body.utf8))
  }

  private static func process(
    _ payload: String,
    state: inout OpenAIStreamState,
    continuation: AsyncThrowingStream<LLMStreamEvent, any Error>.Continuation,
    metadata: LLMProviderMetadata
  ) throws {
    let event: OpenAIStreamEvent
    do {
      event = try JSONDecoder.provider.decode(OpenAIStreamEvent.self, from: Data(payload.utf8))
    } catch {
      throw LLMClientError(
        reason: .decoding,
        debugDescription: "OpenAI stream event decoding failed: \(error.localizedDescription)"
      )
    }

    switch event.type {
    case "response.output_text.delta":
      if let delta = event.delta?.stringValue, !delta.isEmpty {
        continuation.yield(.textDelta(delta))
      }
    case "response.reasoning_summary_text.delta":
      if let delta = event.delta?.stringValue, !delta.isEmpty {
        continuation.yield(.reasoningDelta(delta))
      }
    case "response.output_item.done":
      if let toolCall = event.outputItem?.toolCall {
        continuation.yield(.toolCall(toolCall))
      }
    case "response.completed", "response.incomplete":
      guard let response = event.response else {
        throw LLMClientError(
          reason: .decoding,
          debugDescription: "OpenAI \(event.type ?? "terminal") event did not include a response."
        )
      }
      state.completedResponse = try response.llmResponse(metadata: metadata)
    case "response.failed":
      let providerError = event.response?.error ?? event.error
      throw LLMClientError(
        reason: errorReason(forStatusCode: nil, providerError: providerError),
        debugDescription: providerError?.message ?? "OpenAI response failed."
      )
    case "error":
      let providerError = OpenAIProviderError(code: event.code, message: event.message, type: nil)
      throw LLMClientError(
        reason: errorReason(forStatusCode: nil, providerError: providerError),
        debugDescription: event.message ?? "OpenAI stream failed."
      )
    default:
      break
    }
  }
}

private struct OpenAIStreamState {
  var completedResponse: LLMResponse?
}

/// A leniently decoded Responses stream event. `delta` is kept as JSON because some event types
/// carry object deltas rather than text.
struct OpenAIStreamEvent: Decodable {
  var code: String?
  var delta: JSONValue?
  var error: OpenAIProviderError?
  var item: JSONValue?
  var message: String?
  var response: OpenAIResponsePayload?
  var type: String?

  var outputItem: OpenAIOutputItem? {
    item.flatMap(OpenAIOutputItem.init(json:))
  }
}
