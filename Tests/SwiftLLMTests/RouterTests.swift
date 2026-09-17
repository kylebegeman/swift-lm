import Foundation
import SwiftLLM
import Testing

@Suite("Router")
struct RouterTests {
  // MARK: - Router

  @Test
  func routerFallsBackWhenPrimaryClientThrows() async throws {
    let failingMetadata = LLMProviderMetadata(
      modelIdentifier: "primary",
      privacyMode: .externalOptIn,
      promptVersion: "v1",
      providerDisplayName: "Primary",
      providerKind: .external
    )
    let primary = AnyLLMClient(metadata: failingMetadata) { _ in
      throw LLMClientError(reason: .unavailable)
    }
    let fallback = AnyLLMClient.testDouble { request in
      "Fallback handled \(request.messages.first?.content ?? "")"
    }
    let router = LLMRouter(primary: primary, fallbacks: [fallback])

    let response = try await router.respond(
      to: LLMRequest(messages: [.user("offline work")])
    )

    #expect(response.text == "Fallback handled offline work")
    #expect(response.metadata.providerKind == .testDouble)
  }

  @Test
  func routerDoesNotFallbackForBadRequestsByDefault() async throws {
    let fallback = AnyLLMClient.testDouble { _ in
      Issue.record("Fallback should not run for bad requests.")
      return "unexpected"
    }
    let router = LLMRouter(
      primary: AnyLLMClient(metadata: Self.metadata(name: "Primary")) { _ in
        throw LLMClientError(reason: .badRequest)
      },
      fallbacks: [fallback]
    )

    do {
      _ = try await router.respond(to: LLMRequest(messages: [.user("Bad request")]))
      Issue.record("Expected the router to preserve the bad request error.")
    } catch let error as LLMClientError {
      #expect(error.reason == .badRequest)
    }
  }

  @Test
  func routerUsesCapabilitiesToSkipIncompatibleProviders() async throws {
    let primary = AnyLLMClient(
      metadata: Self.metadata(name: "Local"),
      capabilities: LLMClientCapabilities(
        supportedFeatures: [.jsonObjectResponse, .jsonSchemaResponse, .streaming, .temperature]
      )
    ) { _ in
      Issue.record("Router should not call a provider that lacks required tool support.")
      return LLMResponse(text: "unexpected", metadata: Self.metadata(name: "Local"))
    }
    let router = LLMRouter(
      primary: primary,
      fallbacks: [
        .testDouble { _ in "Tool-capable fallback" },
      ]
    )

    let response = try await router.respond(
      to: LLMRequest(
        messages: [.user("Use a tool.")],
        tools: [
          LLMToolDefinition(
            name: "lookup_note",
            description: "Look up a note.",
            inputSchema: ["type": "object"]
          ),
        ],
        toolChoice: .required
      )
    )

    #expect(response.text == "Tool-capable fallback")
  }

  @Test
  func routerStreamsFromFallbackWhenPrimaryFailsBeforeOutput() async throws {
    let primary = AnyLLMClient(
      metadata: Self.metadata(name: "Primary"),
      respond: { _ in
        throw LLMClientError(reason: .unavailable)
      },
      stream: { _ in
        AsyncThrowingStream { continuation in
          continuation.yield(.started(Self.metadata(name: "Primary")))
          continuation.finish(throwing: LLMClientError(reason: .unavailable))
        }
      }
    )
    let fallback = AnyLLMClient(
      metadata: Self.metadata(name: "Fallback", providerKind: .testDouble),
      respond: { _ in
        LLMResponse(text: "Fallback stream", metadata: Self.metadata(name: "Fallback", providerKind: .testDouble))
      },
      stream: { _ in
        AsyncThrowingStream { continuation in
          let metadata = Self.metadata(name: "Fallback", providerKind: .testDouble)
          continuation.yield(.started(metadata))
          continuation.yield(.textDelta("Fallback stream"))
          continuation.yield(.completed(LLMResponse(text: "Fallback stream", metadata: metadata)))
          continuation.finish()
        }
      }
    )
    let router = LLMRouter(primary: primary, fallbacks: [fallback])

    var events: [LLMStreamEvent] = []
    for try await event in router.stream(to: LLMRequest(messages: [.user("Stream.")])) {
      events.append(event)
    }

    #expect(events.startedProviders == [.external, .testDouble])
    #expect(events.textDeltas == ["Fallback stream"])
    #expect(events.completedResponse?.metadata.providerKind == .testDouble)
  }

  @Test
  func routerDoesNotStreamFallbackAfterOutputStarts() async throws {
    let primary = AnyLLMClient(
      metadata: Self.metadata(name: "Primary"),
      respond: { _ in
        throw LLMClientError(reason: .unavailable)
      },
      stream: { _ in
        AsyncThrowingStream { continuation in
          continuation.yield(.started(Self.metadata(name: "Primary")))
          continuation.yield(.textDelta("partial"))
          continuation.finish(throwing: LLMClientError(reason: .unavailable))
        }
      }
    )
    let fallback = AnyLLMClient.testDouble { _ in
      Issue.record("Fallback should not run after output has started.")
      return "unexpected"
    }
    let router = LLMRouter(primary: primary, fallbacks: [fallback])

    var events: [LLMStreamEvent] = []
    do {
      for try await event in router.stream(to: LLMRequest(messages: [.user("Stream.")])) {
        events.append(event)
      }
      Issue.record("Expected stream to fail without fallback after output started.")
    } catch let error as LLMClientError {
      #expect(error.reason == .unavailable)
    }

    #expect(events.textDeltas == ["partial"])
  }

  @Test
  func routerRespondWithReceiptRecordsFallbackAttemptsAndRedactsPayloads() async throws {
    let primary = AnyLLMClient(metadata: Self.metadata(name: "Primary")) { _ in
      throw LLMClientError(reason: .unavailable, statusCode: 503)
    }
    let fallbackMetadata = Self.metadata(name: "Fallback", providerKind: .testDouble)
    let fallback = AnyLLMClient(metadata: fallbackMetadata) { _ in
      LLMResponse(
        text: "Fallback handled private transcript",
        tokenUsage: LLMTokenUsage(
          estimatedInputTokens: 12,
          estimatedOutputTokens: 4,
          measuredInputTokens: 10,
          measuredOutputTokens: 3
        ),
        metadata: fallbackMetadata
      )
    }
    let router = LLMRouter(primary: primary, fallbacks: [fallback])

    let result = try await router.respondWithReceipt(
      to: LLMRequest(
        messages: [.user("private transcript")],
        metadata: [
          "promptID": "review",
          "promptVersion": "v3",
        ]
      )
    )
    let json = String(decoding: try result.receipt.jsonData(), as: UTF8.self)

    #expect(result.response.text == "Fallback handled private transcript")
    #expect(result.receipt.outcome == .succeeded)
    #expect(result.receipt.request.promptID == "review")
    #expect(result.receipt.request.promptVersion == "v3")
    #expect(result.receipt.attempts.map(\.status) == [.failed, .succeeded])
    #expect(result.receipt.attempts.first?.error?.fallbackReason == "unavailable")
    #expect(result.receipt.attempts.first?.error?.statusCode == 503)
    #expect(result.receipt.finalProvider?.providerKind == "testDouble")
    #expect(result.receipt.tokenUsage?.measuredOutputTokens == 3)
    #expect(!json.contains("private transcript"))
    #expect(!json.contains("Fallback handled private transcript"))
  }

  @Test
  func routerReceiptRecordsUnsupportedCapabilitySkip() async throws {
    let primary = AnyLLMClient(
      metadata: Self.metadata(name: "Limited"),
      capabilities: LLMClientCapabilities(supportedFeatures: [.instructions])
    ) { _ in
      Issue.record("Router should skip a provider that cannot run tools.")
      return LLMResponse(text: "unexpected", metadata: Self.metadata(name: "Limited"))
    }
    let router = LLMRouter(
      primary: primary,
      fallbacks: [
        .testDouble { _ in "Tool-capable fallback" },
      ]
    )

    let result = try await router.respondWithReceipt(
      to: LLMRequest(
        messages: [.user("Use lookup.")],
        tools: [
          LLMToolDefinition(
            name: "lookup",
            description: "Lookup local data.",
            inputSchema: ["type": "object"]
          ),
        ],
        toolChoice: .required
      )
    )

    #expect(result.response.text == "Tool-capable fallback")
    #expect(result.receipt.attempts.first?.status == .skippedUnsupportedCapabilities)
    #expect(result.receipt.attempts.first?.unsupportedCapabilities == ["forcedToolChoice", "tools"])
    #expect(result.receipt.attempts.first?.error?.providerReason == "unsupported")
    #expect(result.receipt.attempts.last?.status == .succeeded)
  }

  @Test
  func routerRespondEmitsReceiptHandlerAndPreservesOriginalError() async {
    let receiptBox = ReceiptBox()
    let router = LLMRouter(
      primary: AnyLLMClient(metadata: Self.metadata(name: "Primary")) { _ in
        throw LLMClientError(reason: .badRequest)
      },
      runReceiptHandler: { receipt in
        receiptBox.record(receipt)
      }
    )

    do {
      _ = try await router.respond(to: LLMRequest(messages: [.user("Bad request")]))
      Issue.record("Expected the router to throw the original client error.")
    } catch let error as LLMClientError {
      #expect(error.reason == .badRequest)
    } catch {
      Issue.record("Expected LLMClientError, got \(error).")
    }

    let receipt = receiptBox.value()
    #expect(receipt?.outcome == .failed)
    #expect(receipt?.attempts.first?.error?.providerReason == "badRequest")
  }

  // MARK: - Helpers

  private static func metadata(
    name: String,
    providerKind: LLMProviderKind = .external
  ) -> LLMProviderMetadata {
    LLMProviderMetadata(
      privacyMode: .externalOptIn,
      promptVersion: "test-v1",
      providerDisplayName: name,
      providerKind: providerKind
    )
  }
}

private final class ReceiptBox: @unchecked Sendable {
  private let lock = NSLock()
  private var receipt: LLMRunReceipt?

  func record(_ receipt: LLMRunReceipt) {
    lock.withLock {
      self.receipt = receipt
    }
  }

  func value() -> LLMRunReceipt? {
    lock.withLock {
      receipt
    }
  }
}
