import Foundation
import SwiftLM

extension OpenAIClient {
  public func respond(to request: LMRequest) async throws -> LMResponse {
    let httpRequest = try responsesHTTPRequest(for: request, stream: false)
    let httpResponse = try await transport.send(httpRequest)
    try Self.validate(httpResponse)

    let payload: OpenAIResponsePayload
    do {
      payload = try JSONDecoder.provider.decode(OpenAIResponsePayload.self, from: httpResponse.body)
    } catch {
      throw LMClientError(
        reason: .decoding,
        debugDescription: "OpenAI response decoding failed: \(error.localizedDescription)"
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

  static func validate(_ response: OpenAIHTTPResponse) throws {
    guard 200..<300 ~= response.statusCode else {
      throw failure(statusCode: response.statusCode, body: response.body)
    }
  }

  static func failure(statusCode: Int?, body: Data) -> LMClientError {
    let providerError = (try? JSONDecoder.provider.decode(OpenAIErrorPayload.self, from: body))?.error
    return LMClientError(
      reason: errorReason(forStatusCode: statusCode, providerError: providerError),
      statusCode: statusCode,
      debugDescription: providerError?.message
    )
  }

  static func errorReason(
    forStatusCode statusCode: Int?,
    providerError: OpenAIProviderError?
  ) -> LMClientErrorReason {
    let code = providerError?.code?.lowercased() ?? ""
    let message = providerError?.message ?? ""

    switch code {
    case "context_length_exceeded":
      return .contextExceeded
    case "insufficient_quota":
      return .quotaExceeded
    case "rate_limit_exceeded":
      return .rateLimited
    case "invalid_api_key", "invalid_organization", "invalid_project":
      return .authentication
    case "server_error":
      return .unavailable
    default:
      break
    }

    switch statusCode ?? 0 {
    case 400:
      if message.range(of: "context", options: .caseInsensitive) != nil {
        return .contextExceeded
      }
      return .badRequest
    case 401, 403:
      return .authentication
    case 404, 422:
      return .badRequest
    case 408, 504:
      return .timeout
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
      return .provider("OpenAI request failed\(status).")
    }
  }
}

// MARK: - Response Decoding

struct OpenAIResponsePayload: Decodable {
  var error: OpenAIProviderError?
  var id: String?
  var incompleteDetails: OpenAIIncompleteDetails?
  var model: String?
  var output: [JSONValue]?
  var status: String?
  var usage: OpenAIUsage?

  enum CodingKeys: String, CodingKey {
    case error
    case id
    case incompleteDetails = "incomplete_details"
    case model
    case output
    case status
    case usage
  }

  var outputItems: [OpenAIOutputItem] {
    (output ?? []).compactMap(OpenAIOutputItem.init(json:))
  }

  func lmResponse(metadata: LMProviderMetadata) throws -> LMResponse {
    if status == "failed" {
      let message = error?.message ?? "OpenAI response failed."
      throw LMClientError(
        reason: OpenAIClient.errorReason(forStatusCode: nil, providerError: error),
        debugDescription: message
      )
    }

    let items = outputItems
    let refusals = items.flatMap(\.refusalParts)
    if !refusals.isEmpty {
      throw LMClientError(
        reason: .guardrailViolation,
        debugDescription: refusals.joined(separator: "\n")
      )
    }

    let text = items.flatMap(\.textParts).joined()
    let toolCalls = items.compactMap(\.toolCall)
    let reasoningSummary = items.flatMap(\.reasoningSummaryParts)
    let hasReasoningItems = items.contains { $0.type == "reasoning" }
    let message = LMMessage.assistant(
      text,
      toolCalls: toolCalls,
      providerContent: hasReasoningItems
        ? LMProviderContent(providerKind: .openAI, payload: .array(output ?? []))
        : nil
    )

    return LMResponse(
      id: id ?? UUID().uuidString,
      text: text,
      message: message,
      toolCalls: toolCalls,
      finishReason: finishReason(hasToolCalls: !toolCalls.isEmpty),
      tokenUsage: usage?.tokenUsage,
      model: model ?? metadata.modelIdentifier,
      metadata: metadata,
      reasoningText: reasoningSummary.isEmpty ? nil : reasoningSummary.joined(separator: "\n")
    )
  }

  private func finishReason(hasToolCalls: Bool) -> LMFinishReason? {
    switch status {
    case "completed":
      return hasToolCalls ? .toolCalls : .stop
    case "incomplete":
      let reason = incompleteDetails?.reason ?? ""
      if reason.contains("max_output_tokens") || reason.contains("max_tokens") {
        return .length
      }
      if reason == "content_filter" {
        return .contentFilter
      }
      return .unknown
    case nil:
      return nil
    default:
      return .unknown
    }
  }
}

struct OpenAIIncompleteDetails: Decodable {
  var reason: String?
}

/// A typed view over a raw Responses output item. The raw JSON is kept so reasoning items can be
/// replayed verbatim.
struct OpenAIOutputItem {
  var arguments: String?
  var callID: String?
  var content: [JSONValue]
  var id: String?
  var name: String?
  var summary: [JSONValue]
  var type: String?

  init?(json: JSONValue) {
    guard let object = json.objectValue else { return nil }
    self.arguments = object["arguments"]?.stringValue
    self.callID = object["call_id"]?.stringValue
    self.content = object["content"]?.arrayValue ?? []
    self.id = object["id"]?.stringValue
    self.name = object["name"]?.stringValue
    self.summary = object["summary"]?.arrayValue ?? []
    self.type = object["type"]?.stringValue
  }

  var textParts: [String] {
    guard type == "message" else { return [] }
    return content.compactMap { part in
      part["type"]?.stringValue == "output_text" ? part["text"]?.stringValue : nil
    }
  }

  var refusalParts: [String] {
    content.compactMap { part in
      part["type"]?.stringValue == "refusal" ? part["refusal"]?.stringValue : nil
    }
  }

  var reasoningSummaryParts: [String] {
    guard type == "reasoning" else { return [] }
    return summary
      .compactMap { $0["text"]?.stringValue }
      .filter { !$0.isEmpty }
  }

  var toolCall: LMToolCall? {
    guard type == "function_call",
          let name,
          let arguments
    else { return nil }
    return LMToolCall(
      id: callID ?? id ?? UUID().uuidString,
      name: name,
      argumentsJSON: arguments
    )
  }
}

struct OpenAIUsage: Decodable {
  var inputTokens: Int?
  var inputTokensDetails: OpenAIInputTokensDetails?
  var outputTokens: Int?
  var outputTokensDetails: OpenAIOutputTokensDetails?

  enum CodingKeys: String, CodingKey {
    case inputTokens = "input_tokens"
    case inputTokensDetails = "input_tokens_details"
    case outputTokens = "output_tokens"
    case outputTokensDetails = "output_tokens_details"
  }

  var tokenUsage: LMTokenUsage {
    LMTokenUsage(
      estimatedInputTokens: inputTokens ?? 0,
      estimatedOutputTokens: outputTokens ?? 0,
      measuredInputTokens: inputTokens,
      measuredOutputTokens: outputTokens,
      cachedInputTokens: inputTokensDetails?.cachedTokens,
      reasoningTokens: outputTokensDetails?.reasoningTokens,
      cacheWriteInputTokens: inputTokensDetails?.cacheWriteTokens
    )
  }
}

struct OpenAIInputTokensDetails: Decodable {
  var cachedTokens: Int?
  var cacheWriteTokens: Int?

  enum CodingKeys: String, CodingKey {
    case cachedTokens = "cached_tokens"
    case cacheWriteTokens = "cache_write_tokens"
  }
}

struct OpenAIOutputTokensDetails: Decodable {
  var reasoningTokens: Int?

  enum CodingKeys: String, CodingKey {
    case reasoningTokens = "reasoning_tokens"
  }
}

struct OpenAIErrorPayload: Decodable {
  var error: OpenAIProviderError
}

struct OpenAIProviderError: Decodable {
  var code: String?
  var message: String?
  var type: String?
}
