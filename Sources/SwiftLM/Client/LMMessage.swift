import Foundation

public enum LMMessageRole: String, Codable, Equatable, Sendable {
  case assistant
  case developer
  case system
  case tool
  case user
}

/// Opaque provider-native content an adapter needs to replay verbatim on later turns.
///
/// Reasoning models require their reasoning items or thinking blocks to be sent back with tool
/// results. Adapters store that payload here when they decode a response and replay it when the
/// same provider encodes the message again. Other providers ignore it and rebuild the message from
/// `content` and `toolCalls`.
public struct LMProviderContent: Codable, Equatable, Sendable {
  public var payload: JSONValue
  public var providerKind: LMProviderKind

  public init(providerKind: LMProviderKind, payload: JSONValue) {
    self.payload = payload
    self.providerKind = providerKind
  }
}

/// A single provider-neutral conversation message.
///
/// The type carries both normal chat content and native tool-call history so
/// adapters can round-trip provider tool messages without app code learning each
/// provider's transport shape.
public struct LMMessage: Codable, Equatable, Sendable {
  public var content: String
  public var name: String?
  /// Provider-native content to replay verbatim, such as reasoning items or thinking blocks.
  public var providerContent: LMProviderContent?
  public var role: LMMessageRole
  public var toolCalls: [LMToolCall]
  public var toolCallID: String?
  public var toolResultIsError: Bool

  public init(
    role: LMMessageRole,
    content: String,
    name: String? = nil,
    toolCallID: String? = nil,
    toolCalls: [LMToolCall] = [],
    toolResultIsError: Bool = false,
    providerContent: LMProviderContent? = nil
  ) {
    self.content = content
    self.name = name
    self.providerContent = providerContent
    self.role = role
    self.toolCalls = toolCalls
    self.toolCallID = toolCallID
    self.toolResultIsError = toolResultIsError
  }

  public static func assistant(
    _ content: String,
    toolCalls: [LMToolCall] = [],
    providerContent: LMProviderContent? = nil
  ) -> Self {
    Self(role: .assistant, content: content, toolCalls: toolCalls, providerContent: providerContent)
  }

  public static func developer(_ content: String) -> Self {
    Self(role: .developer, content: content)
  }

  public static func system(_ content: String) -> Self {
    Self(role: .system, content: content)
  }

  public static func tool(
    _ content: String,
    toolCallID: String,
    isError: Bool = false
  ) -> Self {
    Self(
      role: .tool,
      content: content,
      toolCallID: toolCallID,
      toolResultIsError: isError
    )
  }

  public static func user(_ content: String) -> Self {
    Self(role: .user, content: content)
  }

  // Keep default tool fields optional on the wire so older persisted messages remain decodable.
  enum CodingKeys: String, CodingKey {
    case content
    case name
    case providerContent
    case role
    case toolCallID
    case toolCalls
    case toolResultIsError
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.content = try container.decode(String.self, forKey: .content)
    self.name = try container.decodeIfPresent(String.self, forKey: .name)
    self.providerContent = try container.decodeIfPresent(LMProviderContent.self, forKey: .providerContent)
    self.role = try container.decode(LMMessageRole.self, forKey: .role)
    self.toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
    self.toolCalls = try container.decodeIfPresent([LMToolCall].self, forKey: .toolCalls) ?? []
    self.toolResultIsError = try container.decodeIfPresent(Bool.self, forKey: .toolResultIsError) ?? false
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(content, forKey: .content)
    try container.encodeIfPresent(name, forKey: .name)
    try container.encodeIfPresent(providerContent, forKey: .providerContent)
    try container.encode(role, forKey: .role)
    try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
    if !toolCalls.isEmpty {
      try container.encode(toolCalls, forKey: .toolCalls)
    }
    if toolResultIsError {
      try container.encode(toolResultIsError, forKey: .toolResultIsError)
    }
  }
}
