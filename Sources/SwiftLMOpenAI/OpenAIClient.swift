import Foundation
import SwiftLM

// MARK: - Client

/// OpenAI Responses API adapter for the provider-neutral `LMClient` protocol.
public struct OpenAIClient: LMClient {
  var apiKey: String
  /// Whether the configured model accepts `temperature` and `top_p`. Reasoning model families
  /// reject them with HTTP 400, so the adapter drops those capabilities and routers skip it for
  /// requests that set them instead of failing mid-request.
  public var acceptsSamplingParameters: Bool
  public var baseURL: URL
  public var model: String
  public var organizationID: String?
  public var projectID: String?
  public var promptVersion: String
  /// Whether OpenAI may retain the response server-side (`store`). Off by default so prompts and
  /// outputs are not kept by the provider beyond the request.
  public var storesResponses: Bool
  public var transport: OpenAIHTTPTransport

  public init(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.openai.com/v1")!,
    organizationID: String? = nil,
    projectID: String? = nil,
    promptVersion: String = "openai-responses-v1",
    storesResponses: Bool = false,
    acceptsSamplingParameters: Bool? = nil,
    transport: OpenAIHTTPTransport = .live
  ) {
    self.acceptsSamplingParameters = acceptsSamplingParameters
      ?? OpenAIModelFamily.acceptsSamplingParameters(model: model)
    self.apiKey = apiKey
    self.baseURL = baseURL
    self.model = model
    self.organizationID = organizationID
    self.projectID = projectID
    self.promptVersion = promptVersion
    self.storesResponses = storesResponses
    self.transport = transport
  }

  public var metadata: LMProviderMetadata {
    LMProviderMetadata(
      modelIdentifier: model,
      privacyMode: .externalOptIn,
      promptVersion: promptVersion,
      providerDisplayName: "OpenAI",
      providerKind: .openAI
    )
  }

  public var capabilities: LMClientCapabilities {
    var capabilities = LMClientCapabilities.openAIResponses
    if !acceptsSamplingParameters {
      capabilities.supportedFeatures.subtract([.temperature, .topP])
    }
    return capabilities
  }
}

/// Model-family facts that change the request shape. Update these as OpenAI changes model behavior.
public enum OpenAIModelFamily {
  /// Reasoning model families (`gpt-5`, `gpt-6`, and the `o` series) reject `temperature` and `top_p`.
  public static func acceptsSamplingParameters(model: String) -> Bool {
    let normalized = model.lowercased()
    let reasoningPrefixes = ["gpt-5", "gpt-6", "o1", "o3", "o4", "o5"]
    return !reasoningPrefixes.contains { normalized.hasPrefix($0) }
  }

  /// Whether the model family emits reasoning items that must be replayed with tool results.
  public static func usesReasoningItems(model: String) -> Bool {
    !acceptsSamplingParameters(model: model)
  }
}

// MARK: - AnyLMClient Convenience

extension AnyLMClient {
  public static func openAI(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.openai.com/v1")!,
    organizationID: String? = nil,
    projectID: String? = nil,
    storesResponses: Bool = false
  ) -> Self {
    Self(
      OpenAIClient(
        apiKey: apiKey,
        model: model,
        baseURL: baseURL,
        organizationID: organizationID,
        projectID: projectID,
        storesResponses: storesResponses
      )
    )
  }
}
