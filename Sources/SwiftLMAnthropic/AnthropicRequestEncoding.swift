import Foundation
import SwiftLM

extension AnthropicClient {
  func messagesHTTPRequest(
    for request: LMRequest,
    stream: Bool
  ) throws -> AnthropicHTTPRequest {
    try validate(request)

    let nativeSchema = request.responseFormat.anthropicNativeSchema
    let body = AnthropicMessageRequest(
      model: model,
      maxTokens: request.parameters.maxOutputTokens ?? defaultMaxTokens,
      messages: try request.anthropicMessages(),
      system: request.anthropicSystem(usesNativeSchema: nativeSchema != nil),
      temperature: request.parameters.temperature,
      topP: request.parameters.topP,
      stopSequences: request.parameters.stopSequences.isEmpty ? nil : request.parameters.stopSequences,
      tools: request.tools.isEmpty
        ? nil
        : request.tools.map { AnthropicTool($0, forwardsStrict: forwardsStrictToolSchemas) },
      toolChoice: request.toolChoice.map(AnthropicToolChoice.init),
      thinking: request.parameters.reasoningEffort.map { _ in
        // Ask for a readable summary where the model hides thinking by default, so reasoning
        // deltas and `reasoningText` carry content.
        AnthropicThinkingConfig(
          display: AnthropicModelFamily.acceptsThinkingDisplay(model: model) ? "summarized" : nil
        )
      },
      outputConfig: AnthropicOutputConfig(
        effort: request.parameters.reasoningEffort?.rawValue,
        format: nativeSchema.map(AnthropicOutputFormat.init)
      ).nilIfEmpty,
      cacheControl: enablesPromptCaching ? AnthropicCacheControl() : nil,
      stream: stream
    )
    let data = try JSONEncoder.provider.encode(body)
    return AnthropicHTTPRequest(
      url: baseURL.appendingPathComponent("messages"),
      headers: [
        "anthropic-version": apiVersion,
        "content-type": "application/json",
        "x-api-key": apiKey,
      ],
      body: data
    )
  }

  private func validate(_ request: LMRequest) throws {
    if !acceptsSamplingParameters,
       request.parameters.temperature != nil || request.parameters.topP != nil
    {
      throw LMClientError(
        reason: .unsupported,
        debugDescription: "\(model) does not accept temperature or top_p. Leave them nil for models released after Claude Opus 4.6."
      )
    }
    if request.parameters.reasoningEffort != nil, !supportsReasoningControls {
      throw LMClientError(
        reason: .unsupported,
        debugDescription: "\(model) does not support adaptive thinking with an effort level."
      )
    }
    if request.toolChoice?.requiresToolSupport == true, !supportsForcedToolChoice {
      throw LMClientError(
        reason: .unsupported,
        debugDescription: "\(model) does not support forced tool choice. Use .auto with an instruction instead."
      )
    }
    if request.messages.allSatisfy({ $0.role == .system || $0.role == .developer }) {
      throw LMClientError(
        reason: .badRequest,
        debugDescription: "Anthropic requests need at least one user, assistant, or tool message."
      )
    }
  }
}

// MARK: - Request Encoding

private struct AnthropicMessageRequest: Encodable {
  var model: String
  var maxTokens: Int
  var messages: [AnthropicMessage]
  var system: String?
  var temperature: Double?
  var topP: Double?
  var stopSequences: [String]?
  var tools: [AnthropicTool]?
  var toolChoice: AnthropicToolChoice?
  var thinking: AnthropicThinkingConfig?
  var outputConfig: AnthropicOutputConfig?
  var cacheControl: AnthropicCacheControl?
  var stream: Bool

  enum CodingKeys: String, CodingKey {
    case cacheControl = "cache_control"
    case maxTokens = "max_tokens"
    case messages
    case model
    case outputConfig = "output_config"
    case stopSequences = "stop_sequences"
    case stream
    case system
    case temperature
    case thinking
    case toolChoice = "tool_choice"
    case tools
    case topP = "top_p"
  }
}

private struct AnthropicThinkingConfig: Encodable {
  var type = "adaptive"
  var display: String?
}

private struct AnthropicOutputConfig: Encodable {
  var effort: String?
  var format: AnthropicOutputFormat?

  var nilIfEmpty: Self? {
    effort == nil && format == nil ? nil : self
  }
}

private struct AnthropicOutputFormat: Encodable {
  var schema: JSONValue
  var type = "json_schema"

  init(_ schema: LMJSONSchema) {
    self.schema = schema.schema
  }
}

private struct AnthropicCacheControl: Encodable {
  var type = "ephemeral"
}

private struct AnthropicMessage: Encodable {
  var role: String
  var content: [AnthropicMessageContent]
}

private enum AnthropicMessageContent: Encodable {
  case image(AnthropicImageContent)
  case raw(JSONValue)
  case text(String)
  case toolResult(AnthropicToolResultContent)
  case toolUse(AnthropicToolUseContent)

  func encode(to encoder: any Encoder) throws {
    switch self {
    case let .image(image):
      try image.encode(to: encoder)
    case let .raw(value):
      try value.encode(to: encoder)
    case let .text(text):
      try AnthropicTextContent(text: text).encode(to: encoder)
    case let .toolResult(result):
      try result.encode(to: encoder)
    case let .toolUse(toolUse):
      try toolUse.encode(to: encoder)
    }
  }
}

private struct AnthropicTextContent: Encodable {
  var text: String
  var type = "text"
}

private struct AnthropicImageContent: Encodable {
  enum Source: Encodable {
    case base64(mediaType: String, data: String)
    case url(String)

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case let .base64(mediaType, data):
        try container.encode("base64", forKey: .type)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(data, forKey: .data)
      case let .url(url):
        try container.encode("url", forKey: .type)
        try container.encode(url, forKey: .url)
      }
    }

    enum CodingKeys: String, CodingKey {
      case data
      case mediaType = "media_type"
      case type
      case url
    }
  }

  var source: Source
  var type = "image"

  init(_ image: LMImage) throws {
    if let url = image.remoteURL {
      self.source = .url(url.absoluteString)
    } else if let (data, mediaType) = try image.loadData() {
      self.source = .base64(mediaType: mediaType, data: data.base64EncodedString())
    } else {
      throw LMClientError(reason: .badRequest, debugDescription: "The image could not be encoded.")
    }
  }
}

private struct AnthropicToolUseContent: Encodable {
  var id: String
  var input: JSONValue
  var name: String
  var type = "tool_use"

  init(_ toolCall: LMToolCall) throws {
    self.id = toolCall.id
    self.input = try toolCall.argumentsValue()
    self.name = toolCall.name
  }
}

private struct AnthropicToolResultContent: Encodable {
  var content: String?
  var isError: Bool?
  var toolUseID: String
  var type = "tool_result"

  init(message: LMMessage) throws {
    guard let toolCallID = message.toolCallID,
          !toolCallID.isEmpty
    else {
      throw LMClientError(
        reason: .badRequest,
        debugDescription: "Anthropic tool result messages require a non-empty toolCallID."
      )
    }
    self.content = message.content.isEmpty ? nil : message.content
    self.isError = message.toolResultIsError ? true : nil
    self.toolUseID = toolCallID
  }

  enum CodingKeys: String, CodingKey {
    case content
    case isError = "is_error"
    case toolUseID = "tool_use_id"
    case type
  }
}

private struct AnthropicTool: Encodable {
  var name: String
  var description: String
  var inputSchema: JSONValue
  var strict: Bool?

  init(_ definition: LMToolDefinition, forwardsStrict: Bool) {
    self.description = definition.description
    self.inputSchema = definition.inputSchema
    self.name = definition.name
    self.strict = forwardsStrict && definition.strict ? true : nil
  }

  enum CodingKeys: String, CodingKey {
    case description
    case inputSchema = "input_schema"
    case name
    case strict
  }
}

private enum AnthropicToolChoice: Encodable {
  case auto
  case none
  case required
  case tool(String)

  init(_ choice: LMToolChoice) {
    switch choice {
    case .auto:
      self = .auto
    case .noTools:
      self = .none
    case .required:
      self = .required
    case let .tool(name):
      self = .tool(name)
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .auto:
      try container.encode("auto", forKey: .type)
    case .none:
      try container.encode("none", forKey: .type)
    case .required:
      try container.encode("any", forKey: .type)
    case let .tool(name):
      try container.encode("tool", forKey: .type)
      try container.encode(name, forKey: .name)
    }
  }

  enum CodingKeys: String, CodingKey {
    case name
    case type
  }
}

// MARK: - Request Mapping

private extension LMRequest {
  func anthropicMessages() throws -> [AnthropicMessage] {
    let conversationalMessages = messages.filter { $0.role != .system && $0.role != .developer }
    var anthropicMessages: [AnthropicMessage] = []
    var index = conversationalMessages.startIndex

    while index < conversationalMessages.endIndex {
      let message = conversationalMessages[index]

      if message.role == .tool {
        var content = try message.anthropicToolResultContent
        index = conversationalMessages.index(after: index)

        while index < conversationalMessages.endIndex,
              conversationalMessages[index].role == .tool
        {
          content.append(contentsOf: try conversationalMessages[index].anthropicToolResultContent)
          index = conversationalMessages.index(after: index)
        }

        if index < conversationalMessages.endIndex,
           conversationalMessages[index].role == .user
        {
          content.append(contentsOf: try conversationalMessages[index].anthropicContent)
          index = conversationalMessages.index(after: index)
        }

        anthropicMessages.append(AnthropicMessage(role: "user", content: content))
      } else {
        let content = try message.anthropicContent
        // The API rejects empty text blocks, so a message with nothing to say is skipped.
        if !content.isEmpty {
          anthropicMessages.append(
            AnthropicMessage(role: message.role.anthropicRole, content: content)
          )
        }
        index = conversationalMessages.index(after: index)
      }
    }

    guard !anthropicMessages.isEmpty else {
      throw LMClientError(
        reason: .badRequest,
        debugDescription: "Anthropic requests need at least one non-empty message."
      )
    }
    return anthropicMessages
  }

  func anthropicSystem(usesNativeSchema: Bool) -> String? {
    let messageInstructions = messages
      .filter { $0.role == .system || $0.role == .developer }
      .map(\.content)
      .joined(separator: "\n\n")
    let responseInstructions = usesNativeSchema ? nil : responseFormat.anthropicSystemInstructions
    let system = [instructions, messageInstructions, responseInstructions]
      .compactMap { value in
        guard let value, !value.isEmpty else { return nil }
        return value
      }
      .joined(separator: "\n\n")
    return system.isEmpty ? nil : system
  }
}

private extension LMMessage {
  var anthropicContent: [AnthropicMessageContent] {
    get throws {
      guard images.isEmpty || role == .user else {
        throw LMClientError(
          reason: .badRequest,
          debugDescription: "Only user messages can carry images."
        )
      }
      switch role {
      case .assistant:
        if let providerContent,
           providerContent.providerKind == .anthropic,
           let blocks = providerContent.payload.arrayValue,
           !blocks.isEmpty
        {
          return blocks.map(AnthropicMessageContent.raw)
        }
        var content: [AnthropicMessageContent] = []
        if !self.content.isEmpty {
          content.append(.text(self.content))
        }
        content.append(contentsOf: try toolCalls.map { .toolUse(try AnthropicToolUseContent($0)) })
        return content
      case .tool:
        return try anthropicToolResultContent
      case .user:
        // Anthropic recommends placing images before the text that refers to them.
        let imageContent = try images.map { AnthropicMessageContent.image(try AnthropicImageContent($0)) }
        return imageContent + (content.isEmpty ? [] : [.text(content)])
      case .developer, .system:
        return content.isEmpty ? [] : [.text(content)]
      }
    }
  }

  var anthropicToolResultContent: [AnthropicMessageContent] {
    get throws {
      [.toolResult(try AnthropicToolResultContent(message: self))]
    }
  }
}

private extension LMToolCall {
  func argumentsValue() throws -> JSONValue {
    guard !argumentsJSON.isEmpty,
          let data = argumentsJSON.data(using: .utf8)
    else { return .object([:]) }

    do {
      return try JSONDecoder.provider.decode(JSONValue.self, from: data)
    } catch {
      throw LMClientError(
        reason: .badRequest,
        debugDescription: "Anthropic tool call arguments must be valid JSON."
      )
    }
  }
}

private extension LMMessageRole {
  var anthropicRole: String {
    switch self {
    case .assistant:
      return "assistant"
    case .developer, .system, .tool, .user:
      return "user"
    }
  }
}

private extension LMResponseFormat {
  /// The schema to send as native structured output. Only strict schemas use the native path,
  /// because Anthropic enforces the same schema subset as strict tools.
  var anthropicNativeSchema: LMJSONSchema? {
    if case let .jsonSchema(schema) = self, schema.strict {
      return schema
    }
    return nil
  }

  var anthropicSystemInstructions: String? {
    switch self {
    case .text:
      return nil
    case .jsonObject:
      return "Return only valid JSON."
    case let .jsonSchema(schema):
      let encodedSchema = (try? JSONEncoder.provider.encode(schema.schema))
        .map { String(decoding: $0, as: UTF8.self) }
        ?? "{}"
      return """
      Return only valid JSON matching this schema.
      Schema name: \(schema.name)
      \(schema.description.map { "Description: \($0)\n" } ?? "")Schema:
      \(encodedSchema)
      """
    }
  }
}
