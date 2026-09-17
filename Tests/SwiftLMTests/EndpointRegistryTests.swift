import Foundation
import SwiftLM
import Testing

@Suite("Endpoint registry")
struct EndpointRegistryTests {
  @Test
  func registryBuildsPriorityRouterFromEnabledEndpoints() async throws {
    let local = AnyLMClient(metadata: Self.metadata(name: "Local")) { _ in
      throw LMClientError(reason: .unavailable)
    }
    let cloud = AnyLMClient(metadata: Self.metadata(name: "Cloud", providerKind: .testDouble)) { _ in
      LMResponse(
        text: "cloud fallback",
        metadata: Self.metadata(name: "Cloud", providerKind: .testDouble)
      )
    }
    let registry = LMEndpointRegistry(
      endpoints: [
        LMEndpoint(id: "cloud", client: cloud, priority: 20),
        LMEndpoint(id: "local", client: local, priority: 10),
      ]
    )

    let router = try registry.router()
    let response = try await router.respond(
      to: LMRequest(messages: [.user("route")])
    )

    #expect(router.primary.metadata.providerDisplayName == "Local")
    #expect(router.fallbacks.map(\.metadata.providerDisplayName) == ["Cloud"])
    #expect(response.text == "cloud fallback")
    #expect(response.metadata.providerKind == .testDouble)
  }

  @Test
  func registryUsesExplicitFallbackOrder() throws {
    let registry = LMEndpointRegistry(
      endpoints: [
        LMEndpoint(id: "primary", client: Self.client(name: "Primary")),
        LMEndpoint(id: "second", client: Self.client(name: "Second"), priority: 1),
        LMEndpoint(id: "first", client: Self.client(name: "First"), priority: 2),
      ]
    )

    let router = try registry.router(
      primaryID: "primary",
      fallbackIDs: ["first", "second"]
    )

    #expect(router.primary.metadata.providerDisplayName == "Primary")
    #expect(router.fallbacks.map(\.metadata.providerDisplayName) == ["First", "Second"])
  }

  @Test
  func registryRejectsDisabledExplicitEndpoints() throws {
    let registry = LMEndpointRegistry(
      endpoints: [
        LMEndpoint(id: "local", client: Self.client(name: "Local"), isEnabled: false),
        LMEndpoint(id: "cloud", client: Self.client(name: "Cloud")),
      ]
    )

    #expect(throws: LMEndpointRegistryError.endpointDisabled("local")) {
      _ = try registry.router(primaryID: "local")
    }
  }

  private static func client(name: String) -> AnyLMClient {
    AnyLMClient(metadata: metadata(name: name)) { _ in
      LMResponse(text: name, metadata: metadata(name: name))
    }
  }

  private static func metadata(
    name: String,
    providerKind: LMProviderKind = .external
  ) -> LMProviderMetadata {
    LMProviderMetadata(
      privacyMode: .externalOptIn,
      promptVersion: "test-v1",
      providerDisplayName: name,
      providerKind: providerKind
    )
  }
}
