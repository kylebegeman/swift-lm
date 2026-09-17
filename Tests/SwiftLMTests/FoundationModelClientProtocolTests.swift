import Foundation
import SwiftLM
import SwiftLMFoundationModels
import Testing

@Suite("Foundation Models protocol adapter")
struct FoundationModelClientProtocolTests {
  // MARK: - Foundation Models

  @Test
  func foundationModelClientCanRespondThroughCommonProtocol() async throws {
    let capture = RequestCapture<FoundationModelGenerationRequest>()
    let client = FoundationModelClient(
      checkAvailability: { _, _ in .available },
      countTokens: { request in TokenCounter.latinHeuristic.count(request.text) },
      prewarm: { _ in },
      respond: { request in
        await capture.record(request)
        return FoundationModelGenerationResponse(
          content: "Foundation response for \(request.prompt.userPrompt)",
          metadata: request.prompt.metadata,
          tokenUsage: LMTokenUsage(
            estimatedInputTokens: 6,
            estimatedOutputTokens: 5
          ),
          startedAt: Date(timeIntervalSince1970: 1),
          completedAt: Date(timeIntervalSince1970: 2)
        )
      }
    )
    let contextPlan = LMContextPlan(
      items: [
        LMContextItem(
          id: "prompt",
          surface: .prompt,
          text: "a private transcript",
          trust: .userProvided
        )
      ],
      prewarmPromptPrefix: "a private"
    )

    let response = try await client.respond(
      to: LMRequest(
        instructions: "Summarize locally.",
        messages: [.user("a private transcript")],
        parameters: LMGenerationParameters(maxOutputTokens: 48),
        contextPlan: contextPlan,
        metadata: [
          "promptVersion": "local-summary-v2",
        ]
      )
    )
    let capturedRequest = await capture.value()

    #expect(response.text == "Foundation response for a private transcript")
    #expect(response.metadata.providerKind == .appleFoundationModels)
    #expect(response.metadata.promptVersion == "local-summary-v2")
    #expect(response.tokenUsage?.estimatedOutputTokens == 5)
    #expect(capturedRequest?.prompt.contextPlan == contextPlan)
    #expect(capturedRequest?.prewarmPromptPrefix == "a private")
  }

  @Test
  func foundationModelClientRejectsUnsupportedProviderNeutralFeatures() async {
    let client = FoundationModelClient(
      checkAvailability: { _, _ in .available },
      countTokens: { request in TokenCounter.latinHeuristic.count(request.text) },
      prewarm: { _ in },
      respond: { request in
        FoundationModelGenerationResponse(
          content: request.prompt.userPrompt,
          metadata: request.prompt.metadata,
          tokenUsage: LMTokenUsage(
            estimatedInputTokens: 1,
            estimatedOutputTokens: 1
          ),
          startedAt: Date(timeIntervalSince1970: 1),
          completedAt: Date(timeIntervalSince1970: 2)
        )
      }
    )

    #expect(!client.capabilities.supports(.tools))
    #expect(!client.capabilities.supports(.toolResults))

    do {
      _ = try await client.respond(
        to: LMRequest(
          messages: [.user("Use a tool.")],
          tools: [
            LMToolDefinition(
              name: "lookup_note",
              description: "Look up a note.",
              inputSchema: [
                "type": "object",
              ]
            ),
          ]
        )
      )
      Issue.record("Expected FoundationModelClient to reject unsupported tool requests.")
    } catch let error as LMClientError {
      #expect(error.reason == .unsupported)
    } catch {
      Issue.record("Expected LMClientError, got \(error).")
    }
  }
}
