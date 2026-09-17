import Foundation
import SwiftLM

// MARK: - Client

/// Anthropic Messages API adapter for the provider-neutral `LMClient` protocol.
public struct AnthropicClient: LMClient {
  var apiKey: String
  /// Whether the configured model accepts `temperature` and `top_p`. Models released after
  /// Claude Opus 4.6 reject non-default values with HTTP 400, so the adapter drops those
  /// capabilities and routers skip it for requests that set them.
  public var acceptsSamplingParameters: Bool
  public var apiVersion: String
  public var baseURL: URL
  /// The `max_tokens` sent when a request does not set `maxOutputTokens`. Thinking tokens count
  /// toward this limit on reasoning models, so keep it generous.
  public var defaultMaxTokens: Int
  /// Adds a top-level ephemeral `cache_control` marker so Anthropic caches the stable prefix.
  public var enablesPromptCaching: Bool
  /// Forwards `LMToolDefinition.strict` to Anthropic. Strict schemas must declare
  /// `additionalProperties: false` and list every property as required, so this is opt-in.
  public var forwardsStrictToolSchemas: Bool
  public var model: String
  public var promptVersion: String
  /// Whether the model honors `tool_choice` values that force a tool call.
  public var supportsForcedToolChoice: Bool
  /// Whether the model accepts adaptive thinking with an `output_config.effort` level.
  public var supportsReasoningControls: Bool
  public var transport: AnthropicHTTPTransport

  public init(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
    apiVersion: String = "2023-06-01",
    defaultMaxTokens: Int = 8_192,
    promptVersion: String = "anthropic-messages-v1",
    enablesPromptCaching: Bool = false,
    forwardsStrictToolSchemas: Bool = false,
    acceptsSamplingParameters: Bool? = nil,
    supportsReasoningControls: Bool? = nil,
    supportsForcedToolChoice: Bool? = nil,
    transport: AnthropicHTTPTransport = .live
  ) {
    self.acceptsSamplingParameters = acceptsSamplingParameters
      ?? AnthropicModelFamily.acceptsSamplingParameters(model: model)
    self.apiKey = apiKey
    self.apiVersion = apiVersion
    self.baseURL = baseURL
    self.defaultMaxTokens = defaultMaxTokens
    self.enablesPromptCaching = enablesPromptCaching
    self.forwardsStrictToolSchemas = forwardsStrictToolSchemas
    self.model = model
    self.promptVersion = promptVersion
    self.supportsForcedToolChoice = supportsForcedToolChoice
      ?? AnthropicModelFamily.supportsForcedToolChoice(model: model)
    self.supportsReasoningControls = supportsReasoningControls
      ?? AnthropicModelFamily.supportsReasoningControls(model: model)
    self.transport = transport
  }

  public var metadata: LMProviderMetadata {
    LMProviderMetadata(
      modelIdentifier: model,
      privacyMode: .externalOptIn,
      promptVersion: promptVersion,
      providerDisplayName: "Anthropic",
      providerKind: .anthropic
    )
  }

  public var capabilities: LMClientCapabilities {
    var capabilities = LMClientCapabilities.anthropicMessages
    if !acceptsSamplingParameters {
      capabilities.supportedFeatures.subtract([.temperature, .topP])
    }
    if !supportsReasoningControls {
      capabilities.supportedFeatures.remove(.reasoning)
    }
    if !supportsForcedToolChoice {
      capabilities.supportedFeatures.remove(.forcedToolChoice)
    }
    return capabilities
  }
}

/// Model-family facts that change the request shape. Update these as Anthropic changes model behavior.
public enum AnthropicModelFamily {
  /// A parsed Claude model identifier.
  public struct Version: Equatable, Sendable {
    public var family: String
    public var major: Int
    public var minor: Int

    public init(family: String, major: Int, minor: Int) {
      self.family = family
      self.major = major
      self.minor = minor
    }

    public func isAtLeast(_ major: Int, _ minor: Int) -> Bool {
      (self.major, self.minor) >= (major, minor)
    }
  }

  /// Parses identifiers such as `claude-opus-4-6`, `claude-sonnet-4-5-20250929`, `claude-fable-5-1`,
  /// and the older `claude-3-7-sonnet-20250219` form. Returns `nil` for anything else.
  public static func version(of model: String) -> Version? {
    let parts = model.lowercased().split(separator: "-").map(String.init)
    guard parts.count >= 2, parts[0] == "claude" else { return nil }

    if let major = Int(parts[1]) {
      var index = 2
      var minor = 0
      if index < parts.count, parts[index].count <= 2, let value = Int(parts[index]) {
        minor = value
        index += 1
      }
      guard index < parts.count, parts[index].allSatisfy(\.isLetter) else { return nil }
      return Version(family: parts[index], major: major, minor: minor)
    }

    guard parts[1].allSatisfy(\.isLetter),
          parts.count >= 3,
          parts[2].count <= 2,
          let major = Int(parts[2])
    else { return nil }
    var minor = 0
    if parts.count >= 4, parts[3].count <= 2, let value = Int(parts[3]) {
      minor = value
    }
    return Version(family: parts[1], major: major, minor: minor)
  }

  /// Models released after Claude Opus 4.6 reject `temperature` and `top_p`. Unrecognized
  /// identifiers are treated as current models; pass `acceptsSamplingParameters` to override.
  public static func acceptsSamplingParameters(model: String) -> Bool {
    guard let version = version(of: model) else { return false }
    if version.major <= 3 {
      return true
    }
    switch version.family {
    case "haiku", "opus", "sonnet":
      return !version.isAtLeast(4, 7)
    default:
      return false
    }
  }

  /// Claude Opus and Sonnet 4.6 and every later model take adaptive thinking with an effort level.
  /// Older models need a thinking token budget the adapter does not manage.
  public static func supportsReasoningControls(model: String) -> Bool {
    guard let version = version(of: model) else { return false }
    switch version.family {
    case "opus", "sonnet":
      return version.isAtLeast(4, 6)
    case "haiku":
      return version.isAtLeast(5, 0)
    default:
      return version.major >= 5
    }
  }

  /// Whether the model accepts `thinking.display`. Claude Opus 4.7 introduced the field and made
  /// omitted thinking the default; Opus and Sonnet 4.6 summarize by default and predate it.
  public static func acceptsThinkingDisplay(model: String) -> Bool {
    guard supportsReasoningControls(model: model), let version = version(of: model) else { return false }
    switch version.family {
    case "opus":
      return version.isAtLeast(4, 7)
    case "sonnet":
      return version.isAtLeast(5, 0)
    default:
      return true
    }
  }

  /// Claude Fable 5.1 and later Fable releases, and Claude Mythos, reject `tool_choice` values of
  /// `any` and `tool`.
  public static func supportsForcedToolChoice(model: String) -> Bool {
    guard let version = version(of: model) else {
      return !model.lowercased().hasPrefix("claude-mythos")
    }
    switch version.family {
    case "fable":
      return !version.isAtLeast(5, 1)
    case "mythos":
      return false
    default:
      return true
    }
  }
}

// MARK: - AnyLMClient Convenience

extension AnyLMClient {
  public static func anthropic(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
    apiVersion: String = "2023-06-01",
    defaultMaxTokens: Int = 8_192
  ) -> Self {
    Self(
      AnthropicClient(
        apiKey: apiKey,
        model: model,
        baseURL: baseURL,
        apiVersion: apiVersion,
        defaultMaxTokens: defaultMaxTokens
      )
    )
  }
}
