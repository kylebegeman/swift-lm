import Foundation
import SwiftLM
import SwiftLMAnthropic
import SwiftLMFoundationModels
import SwiftLMOpenAI
import Testing

#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Images and conversations")
struct MultimodalConversationTests {
  private static let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

  // MARK: - Core

  @Test
  func imagesRoundTripAndRequireImageInput() throws {
    let message = LMMessage.user(
      "Describe these.",
      images: [
        .data(Self.pngBytes, mediaType: "image/png"),
        .url(URL(string: "https://example.test/photo.jpg")!),
      ]
    )
    let request = LMRequest(messages: [message])

    let decoded = try JSONDecoder().decode(LMMessage.self, from: try JSONEncoder().encode(message))
    let legacy = try JSONDecoder().decode(
      LMMessage.self,
      from: Data(#"{"role":"user","content":"Old message."}"#.utf8)
    )
    let plainJSON = String(decoding: try JSONEncoder().encode(LMMessage.user("Text only.")), as: UTF8.self)

    #expect(decoded == message)
    #expect(legacy.images.isEmpty)
    #expect(!plainJSON.contains(#""images""#))
    #expect(request.requiredCapabilities().contains(.imageInput))
    #expect(!LMRequest(messages: [.user("Text only.")]).requiredCapabilities().contains(.imageInput))
    #expect(!LMClientCapabilities.foundationModelsProviderNeutral.supports(.imageInput))
    #expect(LMClientCapabilities.openAIResponses.supports(.imageInput))
    #expect(LMClientCapabilities.anthropicMessages.supports(.imageInput))
  }

  @Test
  func imagesLoadFromDataAndLocalFiles() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-lm-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let imageFile = directory.appendingPathComponent("chart.png")
    let textFile = directory.appendingPathComponent("notes.txt")
    try Self.pngBytes.write(to: imageFile)
    try Data("notes".utf8).write(to: textFile)

    let fileImage = try #require(try LMImage.url(imageFile).loadData())
    let dataURL = try LMImage.data(Self.pngBytes, mediaType: "image/png").dataURL()

    #expect(fileImage.data == Self.pngBytes)
    #expect(fileImage.mediaType == "image/png")
    #expect(dataURL == "data:image/png;base64,\(Self.pngBytes.base64EncodedString())")
    #expect(try LMImage.url(URL(string: "https://example.test/a.png")!).loadData() == nil)
    #expect(LMImage.url(URL(string: "https://example.test/a.png")!).remoteURL != nil)
    #expect(LMImage.url(imageFile).remoteURL == nil)
    #expect(throws: LMClientError.self) {
      _ = try LMImage.url(textFile).loadData()
    }
    #expect(throws: LMClientError.self) {
      _ = try LMImage.url(directory.appendingPathComponent("missing.png")).loadData()
    }
  }

  @Test
  func routerSkipsClientsWithoutImageInput() async throws {
    let localMetadata = FoundationModelDefaults.metadata()
    let router = LMRouter(
      primary: AnyLMClient(metadata: localMetadata, capabilities: .foundationModelsProviderNeutral) { _ in
        Issue.record("A client without image input must be skipped.")
        return LMResponse(text: "unexpected", metadata: localMetadata)
      },
      fallbacks: [.testDouble { _ in "described" }]
    )

    let result = try await router.respondWithReceipt(
      to: LMRequest(messages: [.user("Describe.", images: [.data(Self.pngBytes, mediaType: "image/png")])])
    )

    #expect(result.response.text == "described")
    #expect(result.receipt.attempts.first?.unsupportedCapabilities == ["imageInput"])
  }

  // MARK: - OpenAI

  @Test
  func openAIEncodesImagesAsInputImageParts() async throws {
    let capture = RequestCapture<OpenAIHTTPRequest>()
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      transport: OpenAIHTTPTransport { request in
        await capture.record(request)
        return OpenAIHTTPResponse(
          statusCode: 200,
          body: Data(#"{"id":"resp_image","status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"A chart."}]}]}"#.utf8)
        )
      }
    )

    let response = try await client.respond(
      to: LMRequest(
        messages: [
          .user(
            "What is this?",
            images: [
              .data(Self.pngBytes, mediaType: "image/png"),
              .url(URL(string: "https://example.test/photo.jpg")!),
            ]
          ),
        ]
      )
    )
    let body = try #require(await capture.value()).jsonObject()
    let parts = try #require(body["input"]?[0]?["content"]?.arrayValue)

    #expect(response.text == "A chart.")
    #expect(parts.count == 3)
    #expect(parts[0] == ["type": "input_text", "text": "What is this?"])
    #expect(parts[1]["type"] == "input_image")
    #expect(parts[1]["image_url"] == .string("data:image/png;base64,\(Self.pngBytes.base64EncodedString())"))
    #expect(parts[1]["detail"] == "auto")
    #expect(parts[2]["image_url"] == "https://example.test/photo.jpg")

    await #expect(throws: LMClientError.self) {
      _ = try await client.respond(
        to: LMRequest(
          messages: [
            .user("Hi"),
            LMMessage(role: .assistant, content: "Here.", images: [.data(Self.pngBytes, mediaType: "image/png")]),
            .user("Thanks"),
          ]
        )
      )
    }
  }

  // MARK: - Anthropic

  @Test
  func anthropicEncodesImagesBeforeText() async throws {
    let capture = RequestCapture<AnthropicHTTPRequest>()
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-test",
      transport: AnthropicHTTPTransport { request in
        await capture.record(request)
        return AnthropicHTTPResponse(
          statusCode: 200,
          body: Data(#"{"id":"msg_image","type":"message","role":"assistant","content":[{"type":"text","text":"A chart."}],"stop_reason":"end_turn","usage":{"input_tokens":5,"output_tokens":2}}"#.utf8)
        )
      }
    )

    _ = try await client.respond(
      to: LMRequest(
        messages: [
          .user("Look up the chart."),
          .assistant("", toolCalls: [LMToolCall(id: "toolu_1", name: "chart", argumentsJSON: "{}")]),
          .tool("Found.", toolCallID: "toolu_1"),
          .user(
            "What does it show?",
            images: [
              .data(Self.pngBytes, mediaType: "image/png"),
              .url(URL(string: "https://example.test/photo.jpg")!),
            ]
          ),
        ]
      )
    )
    let captured = try #require(await capture.value())
    let messages = try #require(try captured.jsonObject()["messages"]?.arrayValue)
    let content = try #require(messages[2]["content"]?.arrayValue)

    #expect(messages.count == 3)
    #expect(content.map { $0["type"] } == ["tool_result", "image", "image", "text"])
    #expect(content[1]["source"] == [
      "type": "base64",
      "media_type": "image/png",
      "data": .string(Self.pngBytes.base64EncodedString()),
    ])
    #expect(content[2]["source"] == ["type": "url", "url": "https://example.test/photo.jpg"])
    #expect(content[3]["text"] == "What does it show?")
  }

  // MARK: - Foundation Models

  @Test
  func foundationModelsReplaysConversationTurnsAsHistory() async throws {
    let capture = RequestCapture<FoundationModelGenerationRequest>()
    let client = Self.foundationClient(capture: capture)

    _ = try await client.respond(
      to: LMRequest(
        messages: [
          .system("Answer briefly."),
          .user("My name is Sam."),
          .user("I like tea."),
          .assistant("Nice to meet you, Sam."),
          .user("What is my name?"),
          .user("Answer in one word."),
        ]
      )
    )
    let captured = try #require(await capture.value())

    #expect(captured.history == [
      .prompt("My name is Sam.\n\nI like tea."),
      .response("Nice to meet you, Sam."),
    ])
    #expect(captured.prompt.userPrompt == "What is my name?\n\nAnswer in one word.")
    #expect(captured.prompt.systemInstructions.contains("Answer briefly."))
    #expect(captured.images.isEmpty)
  }

  @Test
  func foundationModelsRejectsConversationsItCannotRepresent() async {
    let client = Self.foundationClient()

    await #expect(throws: LMClientError(reason: .badRequest, debugDescription: "Foundation Models requests need at least one user message.")) {
      _ = try await client.respond(to: LMRequest(instructions: "Only instructions.", messages: []))
    }
    do {
      _ = try await client.respond(to: LMRequest(messages: [.user("Hi"), .assistant("Sure, ")]))
      Issue.record("Expected assistant prefill to be rejected.")
    } catch let error as LMClientError {
      #expect(error.reason == .unsupported)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func foundationModelsPassesImagesOnlyToModelsThatAcceptThem() async throws {
    let image = LMImage.data(Self.pngBytes, mediaType: "image/png")
    let textOnly = Self.foundationClient()
    let capture = RequestCapture<FoundationModelGenerationRequest>()
    let vision = Self.foundationClient(capture: capture, supportsVision: true)

    #expect(!textOnly.capabilities.supports(.imageInput))
    #expect(vision.capabilities.supports(.imageInput))
    await #expect(throws: LMClientError.self) {
      _ = try await textOnly.respond(to: LMRequest(messages: [.user("Describe.", images: [image])]))
    }

    _ = try await vision.respond(to: LMRequest(messages: [.user("Describe.", images: [image])]))
    let captured = try #require(await capture.value())
    #expect(captured.images == [image])

    for messages in [
      [LMMessage.user("Describe.", images: [.url(URL(string: "https://example.test/a.png")!)])],
      [LMMessage.user("Earlier.", images: [image]), .assistant("Seen."), .user("Now describe.")],
    ] {
      do {
        _ = try await vision.respond(to: LMRequest(messages: messages))
        Issue.record("Expected an unsupported image placement to be rejected.")
      } catch let error as LMClientError {
        #expect(error.reason == .unsupported)
      } catch {
        Issue.record("Unexpected error \(error)")
      }
    }
  }

  #if canImport(FoundationModels)
  @Test
  func foundationModelSessionOpensOrReportsUnavailability() async throws {
    do {
      let session = try await FoundationModelSession(instructions: "Answer briefly.")
      #expect(session.runtimeProfile.executionTarget == .onDevice)
      #expect(session.metadata.privacyMode == .localOnly)
      #expect(!session.isResponding)
    } catch let failure as FoundationModelFailure {
      guard case .unavailable = failure.reason else {
        Issue.record("Expected an availability failure, got \(failure.reason).")
        return
      }
    }
  }
  #endif

  // MARK: - Helpers

  private static func foundationClient(
    capture: RequestCapture<FoundationModelGenerationRequest>? = nil,
    supportsVision: Bool = false
  ) -> FoundationModelClient {
    FoundationModelClient(
      checkAvailability: { _, _ in .available },
      countTokens: { request in TokenCounter.latinHeuristic.count(request.text) },
      prewarm: { _ in },
      respond: { request in
        await capture?.record(request)
        return FoundationModelGenerationResponse(
          content: "ok",
          metadata: request.prompt.metadata,
          tokenUsage: LMTokenUsage(estimatedInputTokens: 1, estimatedOutputTokens: 1),
          startedAt: Date(timeIntervalSince1970: 1),
          completedAt: Date(timeIntervalSince1970: 2)
        )
      },
      resolveRuntimeProfile: { target, _ in
        FoundationModelRuntimeProfile(executionTarget: target, supportsVision: supportsVision)
      }
    )
  }
}
