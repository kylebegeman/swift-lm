import Foundation
import SwiftLM

extension OpenAIClient {
  func responsesHTTPRequest(
    for request: LMRequest,
    stream: Bool
  ) throws -> OpenAIHTTPRequest {
    try validate(request)

    let url = baseURL.appendingPathComponent("responses")
    let usesReasoning = request.parameters.reasoningEffort != nil
      || OpenAIModelFamily.usesReasoningItems(model: model)
    let body = OpenAIResponsesRequest(
      model: model,
      input: try request.openAIInputItems(),
      instructions: request.openAIInstructions,
      maxOutputTokens: request.parameters.maxOutputTokens,
      temperature: request.parameters.temperature,
      topP: request.parameters.topP,
      text: request.responseFormat.openAIText,
      tools: request.tools.isEmpty ? nil : request.tools.map(OpenAITool.init),
      toolChoice: request.toolChoice.map(OpenAIToolChoice.init),
      reasoning: request.parameters.reasoningEffort.map { OpenAIReasoningConfig(effort: $0.rawValue) },
      store: storesResponses,
      // Stateless requests need encrypted reasoning items so tool loops can replay them.
      include: (!storesResponses && usesReasoning) ? ["reasoning.encrypted_content"] : nil,
      stream: stream
    )
    let data = try JSONEncoder.provider.encode(body)
    var headers = [
      "Authorization": "Bearer \(apiKey)",
      "Content-Type": "application/json",
    ]
    if let organizationID {
      headers["OpenAI-Organization"] = organizationID
    }
    if let projectID {
      headers["OpenAI-Project"] = projectID
    }
    return OpenAIHTTPRequest(url: url, headers: headers, body: data)
  }

  private func validate(_ request: LMRequest) throws {
    if !acceptsSamplingParameters,
       request.parameters.temperature != nil || request.parameters.topP != nil
    {
      throw LMClientError(
        reason: .unsupported,
        debugDescription: "\(model) does not accept temperature or top_p. Leave them nil for reasoning models."
      )
    }
    if !request.parameters.stopSequences.isEmpty {
      throw LMClientError(
        reason: .unsupported,
        debugDescription: "The OpenAI Responses API does not support stop sequences."
      )
    }
    if request.messages.allSatisfy({ $0.role == .system || $0.role == .developer }) {
      throw LMClientError(
        reason: .badRequest,
        debugDescription: "OpenAI requests need at least one user, assistant, or tool message."
      )
    }
  }
}

// MARK: - Request Encoding

private struct OpenAIResponsesRequest: Encodable {
  var model: String
  var input: [OpenAIInputItem]
  var instructions: String?
  var maxOutputTokens: Int?
  var temperature: Double?
  var topP: Double?
  var text: OpenAITextConfig?
  var tools: [OpenAITool]?
  var toolChoice: OpenAIToolChoice?
  var reasoning: OpenAIReasoningConfig?
  var store: Bool
  var include: [String]?
  var stream: Bool

  enum CodingKeys: String, CodingKey {
    case include
    case input
    case instructions
    case maxOutputTokens = "max_output_tokens"
    case model
    case reasoning
    case store
    case stream
    case temperature
    case text
    case toolChoice = "tool_choice"
    case tools
    case topP = "top_p"
  }
}

private struct OpenAIReasoningConfig: Encodable {
  var effort: String
}

private struct OpenAIInputMessage: Encodable {
  var role: String
  var content: OpenAIInputMessageContent

  init(role: String, content: String) {
    self.role = role
    self.content = .text(content)
  }

  init(role: String, parts: [OpenAIInputContentPart]) {
    self.role = role
    self.content = .parts(parts)
  }
}

private enum OpenAIInputMessageContent: Encodable {
  case parts([OpenAIInputContentPart])
  case text(String)

  func encode(to encoder: any Encoder) throws {
    switch self {
    case let .parts(parts):
      try parts.encode(to: encoder)
    case let .text(text):
      try text.encode(to: encoder)
    }
  }
}

private enum OpenAIInputContentPart: Encodable {
  case image(url: String)
  case text(String)

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .image(url):
      try container.encode("input_image", forKey: .type)
      try container.encode(url, forKey: .imageURL)
      try container.encode("auto", forKey: .detail)
    case let .text(text):
      try container.encode("input_text", forKey: .type)
      try container.encode(text, forKey: .text)
    }
  }

  enum CodingKeys: String, CodingKey {
    case detail
    case imageURL = "image_url"
    case text
    case type
  }
}

private enum OpenAIInputItem: Encodable {
  case functionCall(OpenAIFunctionCallInput)
  case functionCallOutput(OpenAIFunctionCallOutputInput)
  case message(OpenAIInputMessage)
  /// A provider-native output item replayed verbatim, such as a reasoning item.
  case raw(JSONValue)

  func encode(to encoder: any Encoder) throws {
    switch self {
    case let .functionCall(value):
      try value.encode(to: encoder)
    case let .functionCallOutput(value):
      try value.encode(to: encoder)
    case let .message(value):
      try value.encode(to: encoder)
    case let .raw(value):
      try value.encode(to: encoder)
    }
  }
}

private struct OpenAIFunctionCallInput: Encodable {
  var arguments: String
  var callID: String
  var name: String
  var type = "function_call"

  init(_ toolCall: LMToolCall) {
    self.arguments = toolCall.argumentsJSON
    self.callID = toolCall.id
    self.name = toolCall.name
  }

  // The item `id` is intentionally omitted: OpenAI rejects replayed `call_…` values there.
  enum CodingKeys: String, CodingKey {
    case arguments
    case callID = "call_id"
    case name
    case type
  }
}

private struct OpenAIFunctionCallOutputInput: Encodable {
  var callID: String
  var output: String
  var type = "function_call_output"

  init(message: LMMessage) throws {
    guard let toolCallID = message.toolCallID,
          !toolCallID.isEmpty
    else {
      throw LMClientError(
        reason: .badRequest,
        debugDescription: "OpenAI tool result messages require a non-empty toolCallID."
      )
    }
    self.callID = toolCallID
    // The Responses API has no error flag for tool output, so the failure is stated in the text.
    self.output = message.toolResultIsError ? "Tool error: \(message.content)" : message.content
  }

  enum CodingKeys: String, CodingKey {
    case callID = "call_id"
    case output
    case type
  }
}

private struct OpenAITextConfig: Encodable {
  var format: OpenAITextFormat
}

private enum OpenAITextFormat: Encodable {
  case jsonObject
  case jsonSchema(LMJSONSchema)

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .jsonObject:
      try container.encode("json_object", forKey: .type)
    case let .jsonSchema(schema):
      try container.encode("json_schema", forKey: .type)
      try container.encode(schema.name, forKey: .name)
      try container.encodeIfPresent(schema.description, forKey: .description)
      try container.encode(schema.schema, forKey: .schema)
      try container.encode(schema.strict, forKey: .strict)
    }
  }

  enum CodingKeys: String, CodingKey {
    case description
    case name
    case schema
    case strict
    case type
  }
}

private struct OpenAITool: Encodable {
  var name: String
  var description: String
  var parameters: JSONValue
  var strict: Bool
  var type = "function"

  init(_ definition: LMToolDefinition) {
    self.description = definition.description
    self.name = definition.name
    self.parameters = definition.inputSchema
    self.strict = definition.strict
  }
}

private enum OpenAIToolChoice: Encodable {
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
    switch self {
    case .auto:
      var container = encoder.singleValueContainer()
      try container.encode("auto")
    case .none:
      var container = encoder.singleValueContainer()
      try container.encode("none")
    case .required:
      var container = encoder.singleValueContainer()
      try container.encode("required")
    case let .tool(name):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("function", forKey: .type)
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
  func openAIInputItems() throws -> [OpenAIInputItem] {
    try messages
      .filter { $0.role != .system && $0.role != .developer }
      .flatMap { message in
        try message.openAIInputItems
      }
  }
}

private extension LMMessage {
  var openAIInputItems: [OpenAIInputItem] {
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
           providerContent.providerKind == .openAI,
           let items = providerContent.payload.arrayValue,
           !items.isEmpty
        {
          return items.map(OpenAIInputItem.raw)
        }
        var inputItems: [OpenAIInputItem] = []
        if !content.isEmpty {
          inputItems.append(.message(OpenAIInputMessage(role: role.openAIRole, content: content)))
        }
        inputItems.append(contentsOf: toolCalls.map { .functionCall(OpenAIFunctionCallInput($0)) })
        return inputItems
      case .tool:
        return [.functionCallOutput(try OpenAIFunctionCallOutputInput(message: self))]
      case .user where !images.isEmpty:
        var parts: [OpenAIInputContentPart] = []
        if !content.isEmpty {
          parts.append(.text(content))
        }
        for image in images {
          guard let url = try image.remoteURL?.absoluteString ?? image.dataURL() else { continue }
          parts.append(.image(url: url))
        }
        return [.message(OpenAIInputMessage(role: role.openAIRole, parts: parts))]
      case .developer, .system, .user:
        return [.message(OpenAIInputMessage(role: role.openAIRole, content: content))]
      }
    }
  }
}

private extension LMMessageRole {
  var openAIRole: String {
    switch self {
    case .assistant:
      return "assistant"
    case .developer:
      return "developer"
    case .system:
      return "system"
    case .tool:
      return "user"
    case .user:
      return "user"
    }
  }
}

private extension LMRequest {
  var openAIInstructions: String? {
    let messageInstructions = messages
      .filter { $0.role == .system || $0.role == .developer }
      .map(\.content)
      .joined(separator: "\n\n")
    let instructions = [instructions, messageInstructions]
      .compactMap { value in
        guard let value, !value.isEmpty else { return nil }
        return value
      }
      .joined(separator: "\n\n")
    return instructions.isEmpty ? nil : instructions
  }
}

private extension LMResponseFormat {
  var openAIText: OpenAITextConfig? {
    switch self {
    case .text:
      return nil
    case .jsonObject:
      return OpenAITextConfig(format: .jsonObject)
    case let .jsonSchema(schema):
      return OpenAITextConfig(format: .jsonSchema(schema))
    }
  }
}
