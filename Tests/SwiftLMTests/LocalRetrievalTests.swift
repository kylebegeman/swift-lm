import Foundation
import SwiftLM
import SwiftLMEvaluation
import SwiftLMFoundationModels
import Testing

@Suite("Local retrieval")
struct LocalRetrievalTests {
  // MARK: - Local Retrieval

  @Test
  func keywordLocalRetrieverRanksMatchingLocalDocuments() async throws {
    let meetingText = "We need local extraction with grounded citations for Chime In."
    let retriever = KeywordLocalRetriever(
      documents: [
        RetrievableDocument(
          id: "meeting",
          text: meetingText,
          displayName: "Launch meeting",
          kind: "transcript"
        ),
        RetrievableDocument(
          id: "unrelated",
          text: "The design review covered colors and spacing.",
          displayName: "Design review",
          kind: "note"
        ),
      ],
      maxTokensPerSnippet: 40
    )

    let result = try await retriever.retrieve(
      LocalRetrievalQuery(text: "local extraction citations", maxResults: 4)
    )

    #expect(result.snippets.map(\.sourceID) == ["meeting"])
    #expect(result.snippets.first?.sourceDisplayName == "Launch meeting")
    #expect(result.snippets.first?.sourceKind == "transcript")
    #expect(result.snippets.first?.characterRange == 0..<meetingText.count)
    #expect(result.sources.map(\.id) == ["meeting"])
  }

  @Test
  func keywordLocalRetrieverIncludesRequiredSourcesForEmptyQueries() async throws {
    let retriever = KeywordLocalRetriever(
      documents: [
        RetrievableDocument(
          id: "required",
          text: "Always include this local policy note.",
          displayName: "Policy note",
          kind: "note"
        ),
        RetrievableDocument(
          id: "optional",
          text: "Only include this note when query terms match.",
          displayName: "Optional note",
          kind: "note"
        ),
      ],
      maxTokensPerSnippet: 32
    )

    let result = try await retriever.retrieve(
      LocalRetrievalQuery(
        text: "",
        maxResults: 4,
        requiredSourceIDs: ["required"]
      )
    )

    #expect(result.snippets.map(\.sourceID) == ["required"])
    #expect(result.snippets.first?.isRequired == true)
    #expect(result.sources.map(\.id) == ["required"])
  }

  @Test
  func keywordLocalRetrieverPrioritizesRequiredSourcesBeforeOptionalMatches() async throws {
    let retriever = KeywordLocalRetriever(
      documents: [
        RetrievableDocument(
          id: "optional",
          text: "meeting meeting meeting launch plan",
          displayName: "Optional note",
          kind: "note"
        ),
        RetrievableDocument(
          id: "required",
          text: "Policy note that should remain visible.",
          displayName: "Policy note",
          kind: "note"
        ),
      ],
      maxTokensPerSnippet: 32
    )

    let result = try await retriever.retrieve(
      LocalRetrievalQuery(
        text: "meeting",
        maxResults: 1,
        requiredSourceIDs: ["required"]
      )
    )

    #expect(result.snippets.map(\.sourceID) == ["required"])
    #expect(result.snippets.first?.isRequired == true)
  }

  @Test
  func requiredSourcesOverrideAllowedSourcesButNotExclusions() async throws {
    let retriever = KeywordLocalRetriever(
      documents: [
        RetrievableDocument(
          id: "allowed",
          text: "Allowed source mentions meeting notes.",
          displayName: "Allowed note",
          kind: "note"
        ),
        RetrievableDocument(
          id: "required",
          text: "Required source should remain available.",
          displayName: "Required note",
          kind: "note"
        ),
        RetrievableDocument(
          id: "excluded",
          text: "Excluded source should stay hidden.",
          displayName: "Excluded note",
          kind: "note"
        ),
      ],
      maxTokensPerSnippet: 32
    )

    let result = try await retriever.retrieve(
      LocalRetrievalQuery(
        text: "",
        maxResults: 4,
        allowedSourceIDs: ["allowed"],
        excludedSourceIDs: ["excluded"],
        requiredSourceIDs: ["required", "excluded"]
      )
    )

    #expect(result.snippets.map(\.sourceID) == ["required"])
    #expect(result.sources.map(\.id) == ["required"])
  }

  @Test
  func localRAGPipelinePacksContextAndBuildsCitations() async throws {
    let retriever = KeywordLocalRetriever(
      documents: [
        RetrievableDocument(
          id: "one",
          text: "Local retrieval keeps private notes on device.",
          displayName: "Private note",
          kind: "note"
        ),
        RetrievableDocument(
          id: "two",
          text: "Prompt contracts should include compact citation context.",
          displayName: "Prompt plan",
          kind: "doc"
        ),
      ],
      maxTokensPerSnippet: 32
    )
    let pipeline = LocalRAGPipeline(
      retriever: retriever,
      packer: ContextPacker(
        budget: TokenBudget(
          contextLimit: 64,
          reservedResponseTokens: 8,
          safetyMarginTokens: 4
        ),
        strategy: .sourceDiverse
      )
    )

    let result = try await pipeline.run(
      query: LocalRetrievalQuery(text: "local citation context", maxResults: 4)
    )

    #expect(result.packedSnippets.count == 2)
    #expect(result.citations.map(\.marker) == ["1", "2"])
    #expect(result.contextBlock.contains("Private note (note)"))
    #expect(result.contextBlock.contains("Prompt plan (doc)"))
    #expect(result.sourceContext.sources.map(\.id) == result.packedSnippets.map(\.id))
  }
}
