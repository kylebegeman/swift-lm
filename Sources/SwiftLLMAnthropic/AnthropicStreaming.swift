import Foundation
import SwiftLLM

extension AnthropicClient {
  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let metadata = metadata(for: request)
      continuation.yield(.started(metadata))
      let task = Task {
        do {
          let httpRequest = try messagesHTTPRequest(for: request, stream: true)
          let streamResponse = try await transport.stream(httpRequest)
          guard 200..<300 ~= streamResponse.statusCode else {
            throw await Self.streamFailure(streamResponse)
          }

          var state = AnthropicStreamState(model: model)
          // Each SSE event carries one JSON object on its `data:` line, so every line is dispatched
          // as it arrives. Blank separator lines are not required: `URLSession` line streams omit them.
          for try await line in streamResponse.lines {
            try Task.checkCancellation()
            guard let payload = Self.dataPayload(from: line) else { continue }
            try Self.process(payload, state: &state, continuation: continuation)
            if state.receivedMessageStop {
              break
            }
          }

          guard state.receivedMessageStop || state.stopReason != nil else {
            throw LLMClientError(
              reason: .network,
              debugDescription: "The Anthropic stream ended before message_stop."
            )
          }
          let response = try state.response(metadata: metadata)
          if let usage = response.tokenUsage {
            continuation.yield(.usage(usage))
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

  private static func streamFailure(_ response: AnthropicHTTPStreamResponse) async -> LLMClientError {
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
    state: inout AnthropicStreamState,
    continuation: AsyncThrowingStream<LLMStreamEvent, any Error>.Continuation
  ) throws {
    let event: AnthropicStreamEvent
    do {
      event = try JSONDecoder.provider.decode(AnthropicStreamEvent.self, from: Data(payload.utf8))
    } catch {
      throw LLMClientError(
        reason: .decoding,
        debugDescription: "Anthropic stream event decoding failed: \(error.localizedDescription)"
      )
    }

    switch event.type {
    case "message_start":
      state.usage.merge(event.message?.usage)
      if let id = event.message?.id {
        state.id = id
      }
      if let model = event.message?.model {
        state.model = model
      }

    case "content_block_start":
      guard let index = event.index, let block = event.contentBlock else { break }
      state.startBlock(block, at: index)

    case "content_block_delta":
      guard let index = event.index, let delta = event.delta else { break }
      switch delta.type {
      case "text_delta":
        if let text = delta.text, !text.isEmpty {
          state.appendText(text, at: index)
          continuation.yield(.textDelta(text))
        }
      case "thinking_delta":
        if let thinking = delta.thinking, !thinking.isEmpty {
          state.appendThinking(thinking, at: index)
          continuation.yield(.reasoningDelta(thinking))
        }
      case "signature_delta":
        if let signature = delta.signature {
          state.appendSignature(signature, at: index)
        }
      case "input_json_delta":
        if let partialJSON = delta.partialJSON {
          state.appendToolInput(partialJSON, at: index)
        }
      default:
        break
      }

    case "content_block_stop":
      if let index = event.index,
         let toolCall = state.finishBlock(at: index)
      {
        continuation.yield(.toolCall(toolCall))
      }

    case "message_delta":
      state.usage.merge(event.usage)
      if let stopReason = event.delta?.stopReason {
        state.stopReason = stopReason
      }

    case "message_stop":
      state.receivedMessageStop = true

    case "error":
      let providerError = event.error
      throw LLMClientError(
        reason: errorReason(forStatusCode: nil, providerError: providerError),
        debugDescription: providerError?.message ?? "Anthropic stream failed."
      )

    default:
      break
    }
  }
}

// MARK: - Stream State

/// Accumulates streamed content blocks so the completed response matches the non-streaming shape,
/// including the raw blocks needed to replay thinking on the next turn.
private struct AnthropicStreamState {
  var id = UUID().uuidString
  var model: String
  var receivedMessageStop = false
  var stopReason: String?
  var usage = AnthropicUsage()
  private var blocks: [Int: AnthropicStreamedBlock] = [:]

  init(model: String) {
    self.model = model
  }

  mutating func startBlock(_ block: AnthropicStreamEventBlock, at index: Int) {
    var streamedBlock = AnthropicStreamedBlock(type: block.type ?? "text")
    streamedBlock.id = block.id
    streamedBlock.name = block.name
    streamedBlock.text = block.text ?? ""
    streamedBlock.thinking = block.thinking ?? ""
    streamedBlock.data = block.data
    if let input = block.input, let data = try? JSONEncoder.provider.encode(input) {
      streamedBlock.initialInputJSON = String(decoding: data, as: UTF8.self)
    }
    blocks[index] = streamedBlock
  }

  mutating func appendText(_ text: String, at index: Int) {
    blocks[index, default: AnthropicStreamedBlock(type: "text")].text += text
  }

  mutating func appendThinking(_ thinking: String, at index: Int) {
    blocks[index, default: AnthropicStreamedBlock(type: "thinking")].thinking += thinking
  }

  mutating func appendSignature(_ signature: String, at index: Int) {
    blocks[index, default: AnthropicStreamedBlock(type: "thinking")].signature += signature
  }

  mutating func appendToolInput(_ partialJSON: String, at index: Int) {
    blocks[index, default: AnthropicStreamedBlock(type: "tool_use")].partialInputJSON += partialJSON
  }

  /// Completes a block. Tool calls whose arguments are not valid JSON, such as arguments truncated
  /// by `max_tokens`, are dropped so callers never run a tool with partial input.
  mutating func finishBlock(at index: Int) -> LLMToolCall? {
    guard var block = blocks[index], block.type == "tool_use" else { return nil }
    let argumentsJSON = block.partialInputJSON.isEmpty ? block.initialInputJSON : block.partialInputJSON
    guard let data = argumentsJSON.data(using: .utf8),
          let input = try? JSONDecoder.provider.decode(JSONValue.self, from: data)
    else {
      block.isInvalid = true
      blocks[index] = block
      return nil
    }
    block.input = input
    blocks[index] = block
    return block.contentBlock.toolCall
  }

  func response(metadata: LLMProviderMetadata) throws -> LLMResponse {
    let ordered = blocks.keys.sorted().compactMap { blocks[$0] }.filter { !$0.isInvalid }
    return try AnthropicResponseAssembler.response(
      id: id,
      model: model,
      blocks: ordered.map(\.contentBlock),
      rawBlocks: ordered.map(\.rawJSON),
      stopReason: stopReason,
      usage: usage.inputTokens == nil && usage.outputTokens == nil ? nil : usage,
      metadata: metadata
    )
  }
}

private struct AnthropicStreamedBlock {
  var data: String?
  var id: String?
  var initialInputJSON = "{}"
  var input: JSONValue?
  var isInvalid = false
  var name: String?
  var partialInputJSON = ""
  var signature = ""
  var text = ""
  var thinking = ""
  var type: String

  init(type: String) {
    self.type = type
  }

  var contentBlock: AnthropicContentBlock {
    AnthropicContentBlock(
      type: type,
      id: id,
      input: input,
      name: name,
      text: type == "text" ? text : nil,
      thinking: type == "thinking" ? thinking : nil
    )
  }

  /// The block in the API's own shape, suitable for replaying on the next turn.
  var rawJSON: JSONValue {
    switch type {
    case "thinking":
      return .object(["type": .string("thinking"), "thinking": .string(thinking), "signature": .string(signature)])
    case "redacted_thinking":
      return .object(["type": .string("redacted_thinking"), "data": .string(data ?? "")])
    case "tool_use":
      return .object([
        "type": .string("tool_use"),
        "id": .string(id ?? ""),
        "name": .string(name ?? ""),
        "input": input ?? .object([:]),
      ])
    default:
      return .object(["type": .string("text"), "text": .string(text)])
    }
  }
}

// MARK: - Stream Events

struct AnthropicStreamEvent: Decodable {
  var contentBlock: AnthropicStreamEventBlock?
  var delta: AnthropicStreamDelta?
  var error: AnthropicProviderError?
  var index: Int?
  var message: AnthropicStreamMessage?
  var type: String?
  var usage: AnthropicUsage?

  enum CodingKeys: String, CodingKey {
    case contentBlock = "content_block"
    case delta
    case error
    case index
    case message
    case type
    case usage
  }
}

struct AnthropicStreamEventBlock: Decodable {
  var data: String?
  var id: String?
  var input: JSONValue?
  var name: String?
  var text: String?
  var thinking: String?
  var type: String?
}

struct AnthropicStreamDelta: Decodable {
  var partialJSON: String?
  var signature: String?
  var stopReason: String?
  var text: String?
  var thinking: String?
  var type: String?

  enum CodingKeys: String, CodingKey {
    case partialJSON = "partial_json"
    case signature
    case stopReason = "stop_reason"
    case text
    case thinking
    case type
  }
}

struct AnthropicStreamMessage: Decodable {
  var id: String?
  var model: String?
  var usage: AnthropicUsage?
}
