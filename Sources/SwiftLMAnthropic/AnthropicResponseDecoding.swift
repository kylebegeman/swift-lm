import Foundation
import SwiftLM

extension AnthropicClient {
  public func respond(to request: LMRequest) async throws -> LMResponse {
    let httpRequest = try messagesHTTPRequest(for: request, stream: false)
    let httpResponse = try await transport.send(httpRequest)
    try Self.validate(httpResponse)

    let payload: AnthropicMessageResponse
    do {
      payload = try JSONDecoder.provider.decode(AnthropicMessageResponse.self, from: httpResponse.body)
    } catch {
      throw LMClientError(
        reason: .decoding,
        debugDescription: "Anthropic response decoding failed: \(error.localizedDescription)"
      )
    }
    return try payload.lmResponse(metadata: metadata(for: request))
  }

  func metadata(for request: LMRequest) -> LMProviderMetadata {
    var metadata = self.metadata
    if let promptVersion = request.metadata["promptVersion"] {
      metadata.promptVersion = promptVersion
    }
    return metadata
  }

  static func validate(_ response: AnthropicHTTPResponse) throws {
    guard 200..<300 ~= response.statusCode else {
      throw failure(statusCode: response.statusCode, body: response.body)
    }
  }

  static func failure(statusCode: Int?, body: Data) -> LMClientError {
    let providerError = (try? JSONDecoder.provider.decode(AnthropicErrorPayload.self, from: body))?.error
    return LMClientError(
      reason: errorReason(forStatusCode: statusCode, providerError: providerError),
      statusCode: statusCode,
      debugDescription: providerError?.message
    )
  }

  static func errorReason(
    forStatusCode statusCode: Int?,
    providerError: AnthropicProviderError?
  ) -> LMClientErrorReason {
    let message = providerError?.message ?? ""
    let promptTooLong = message.lowercased().hasPrefix("prompt is too long")

    switch providerError?.type {
    case "overloaded_error", "api_error":
      return .unavailable
    case "rate_limit_error":
      return .rateLimited
    case "authentication_error", "permission_error":
      return .authentication
    case "billing_error":
      return .quotaExceeded
    case "request_too_large":
      return .contextExceeded
    case "timeout_error":
      return .timeout
    case "invalid_request_error":
      return promptTooLong ? .contextExceeded : .badRequest
    case "not_found_error":
      return .badRequest
    default:
      break
    }

    switch statusCode ?? 0 {
    case 400:
      return promptTooLong || message.range(of: "context", options: .caseInsensitive) != nil
        ? .contextExceeded
        : .badRequest
    case 401, 403:
      return .authentication
    case 402:
      return .quotaExceeded
    case 404, 422:
      return .badRequest
    case 408, 504:
      return .timeout
    case 413:
      return .contextExceeded
    case 429:
      return .rateLimited
    case 499:
      return .cancelled
    case 500...599:
      return .unavailable
    default:
      if !message.isEmpty {
        return .provider(message)
      }
      let status = statusCode.map { " with HTTP \($0)" } ?? ""
      return .provider("Anthropic request failed\(status).")
    }
  }
}

// MARK: - Response Decoding

struct AnthropicMessageResponse: Decodable {
  var content: [JSONValue]
  var id: String
  var model: String?
  var stopReason: String?
  var usage: AnthropicUsage?

  enum CodingKeys: String, CodingKey {
    case content
    case id
    case model
    case stopReason = "stop_reason"
    case usage
  }

  func lmResponse(metadata: LMProviderMetadata) throws -> LMResponse {
    try AnthropicResponseAssembler.response(
      id: id,
      model: model ?? metadata.modelIdentifier,
      blocks: content.compactMap(AnthropicContentBlock.init(json:)),
      rawBlocks: content,
      stopReason: stopReason,
      usage: usage,
      metadata: metadata
    )
  }
}

/// Builds `LMResponse` values identically for the non-streaming and streaming paths.
enum AnthropicResponseAssembler {
  static func response(
    id: String,
    model: String?,
    blocks: [AnthropicContentBlock],
    rawBlocks: [JSONValue],
    stopReason: String?,
    usage: AnthropicUsage?,
    metadata: LMProviderMetadata
  ) throws -> LMResponse {
    if stopReason == "refusal" {
      throw LMClientError(
        reason: .guardrailViolation,
        debugDescription: "Anthropic declined the request (stop_reason refusal)."
      )
    }

    let text = blocks.compactMap(\.text).joined()
    let toolCalls = blocks.compactMap(\.toolCall)
    let reasoning = blocks.compactMap(\.thinking).filter { !$0.isEmpty }
    let hasThinkingBlocks = blocks.contains { $0.type == "thinking" || $0.type == "redacted_thinking" }
    let message = LMMessage.assistant(
      text,
      toolCalls: toolCalls,
      providerContent: hasThinkingBlocks
        ? LMProviderContent(providerKind: .anthropic, payload: .array(rawBlocks))
        : nil
    )

    return LMResponse(
      id: id,
      text: text,
      message: message,
      toolCalls: toolCalls,
      finishReason: stopReason.map(LMFinishReason.init(anthropicStopReason:)),
      tokenUsage: usage?.tokenUsage,
      model: model,
      metadata: metadata,
      reasoningText: reasoning.isEmpty ? nil : reasoning.joined(separator: "\n")
    )
  }
}

extension LMFinishReason {
  init(anthropicStopReason stopReason: String) {
    switch stopReason {
    case "end_turn", "stop_sequence":
      self = .stop
    case "max_tokens", "model_context_window_exceeded":
      self = .length
    case "tool_use":
      self = .toolCalls
    case "refusal":
      self = .contentFilter
    default:
      self = .unknown
    }
  }
}

/// A typed view over a raw Messages content block. The raw JSON is kept so thinking blocks can be
/// replayed verbatim with their signatures.
struct AnthropicContentBlock {
  var id: String?
  var input: JSONValue?
  var name: String?
  var text: String?
  var thinking: String?
  var type: String

  init?(json: JSONValue) {
    guard let object = json.objectValue, let type = object["type"]?.stringValue else { return nil }
    self.id = object["id"]?.stringValue
    self.input = object["input"]
    self.name = object["name"]?.stringValue
    self.text = type == "text" ? object["text"]?.stringValue : nil
    self.thinking = type == "thinking" ? object["thinking"]?.stringValue : nil
    self.type = type
  }

  init(
    type: String,
    id: String? = nil,
    input: JSONValue? = nil,
    name: String? = nil,
    text: String? = nil,
    thinking: String? = nil
  ) {
    self.id = id
    self.input = input
    self.name = name
    self.text = text
    self.thinking = thinking
    self.type = type
  }

  var toolCall: LMToolCall? {
    guard type == "tool_use",
          let id,
          let name
    else { return nil }
    let argumentsData = (try? JSONEncoder.provider.encode(input ?? .object([:]))) ?? Data("{}".utf8)
    return LMToolCall(
      id: id,
      name: name,
      argumentsJSON: String(decoding: argumentsData, as: UTF8.self)
    )
  }
}

struct AnthropicUsage: Decodable {
  var cacheCreationInputTokens: Int?
  var cacheReadInputTokens: Int?
  var inputTokens: Int?
  var outputTokens: Int?

  enum CodingKeys: String, CodingKey {
    case cacheCreationInputTokens = "cache_creation_input_tokens"
    case cacheReadInputTokens = "cache_read_input_tokens"
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
  }

  /// Anthropic reports `input_tokens` after the cache breakpoint, so the measured input is the sum
  /// of fresh, cache-read, and cache-write tokens. Thinking is billed inside `output_tokens` and has
  /// no separate count.
  var tokenUsage: LMTokenUsage {
    let measuredInput = (inputTokens ?? 0) + (cacheReadInputTokens ?? 0) + (cacheCreationInputTokens ?? 0)
    return LMTokenUsage(
      estimatedInputTokens: measuredInput,
      estimatedOutputTokens: outputTokens ?? 0,
      measuredInputTokens: inputTokens == nil ? nil : measuredInput,
      measuredOutputTokens: outputTokens,
      cachedInputTokens: cacheReadInputTokens,
      reasoningTokens: nil,
      cacheWriteInputTokens: cacheCreationInputTokens
    )
  }

  mutating func merge(_ other: AnthropicUsage?) {
    guard let other else { return }
    cacheCreationInputTokens = other.cacheCreationInputTokens ?? cacheCreationInputTokens
    cacheReadInputTokens = other.cacheReadInputTokens ?? cacheReadInputTokens
    inputTokens = other.inputTokens ?? inputTokens
    outputTokens = other.outputTokens ?? outputTokens
  }
}

struct AnthropicErrorPayload: Decodable {
  var error: AnthropicProviderError
}

struct AnthropicProviderError: Decodable {
  var message: String?
  var type: String?
}
