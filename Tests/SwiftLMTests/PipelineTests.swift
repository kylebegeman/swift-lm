import Foundation
import SwiftLM
import Testing

@Suite("Pipeline")
struct PipelineTests {
  // MARK: - Pipeline

  @Test
  func pipelineInjectsLocalRetrievalContextBeforeGeneration() async throws {
    let retriever = KeywordLocalRetriever(
      documents: [
        RetrievableDocument(
          id: "note",
          text: "Local retrieval should keep citations visible.",
          displayName: "Private note",
          kind: "note"
        ),
      ],
      maxTokensPerSnippet: 32
    )
    let pipeline = LMPipeline(
      client: .testDouble { request in
        request.messages.first?.content ?? ""
      },
      ragPipeline: LocalRAGPipeline(
        retriever: retriever,
        packer: ContextPacker(
          budget: TokenBudget(
            contextLimit: 64,
            reservedResponseTokens: 8,
            safetyMarginTokens: 4
          )
        )
      )
    )

    let result = try await pipeline.run(
      task: LMPromptTask(
        contract: PromptContract(
          id: "answer",
          version: "v2",
          instructions: "Answer from local context.",
          responseSchemaDescription: "Return a concise answer with citations when evidence is available."
        ),
        retrievalQuery: { input in
          LocalRetrievalQuery(text: input, maxResults: 2)
        }
      ),
      input: "How should local retrieval handle citations?"
    )

    #expect(result.ragResult?.packedSnippets.count == 1)
    #expect(result.contextCompilation?.packedSnippets.count == 1)
    #expect(result.contextCompilation?.budgetReport.estimatedInputTokens ?? 0 > 0)
    #expect(result.response.text.contains("Retrieved context:"))
    #expect(result.response.text.contains("Private note (note)"))
    #expect(result.compiledPrompt.contextPlan == result.request.contextPlan)
    #expect(result.request.contextPlan?.items.map(\.surface).contains(.retrievedContext) == true)
    #expect(
      result.request.contextPlan?.items.first(where: { $0.surface == .prompt })?.text
        == "How should local retrieval handle citations?"
    )
    #expect(result.request.instructions?.contains("Return a concise answer with citations") == true)
    #expect(!result.request.requiredCapabilities().contains(.guidedGeneration))
    #expect(result.request.metadata["promptID"] == "answer")
    #expect(result.compiledPrompt.metadata.promptVersion == "v2")
  }
}
