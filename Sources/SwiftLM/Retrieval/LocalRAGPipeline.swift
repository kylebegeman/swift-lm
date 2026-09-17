import Foundation

public struct LocalRAGPipeline: Sendable {
  public var packer: ContextPacker
  public var renderer: CitationContextRenderer
  public var reservedInputTokens: Int
  public var retriever: AnyLocalRetriever

  public init<R: LocalRetriever>(
    retriever: R,
    packer: ContextPacker,
    reservedInputTokens: Int = 0,
    renderer: CitationContextRenderer = CitationContextRenderer()
  ) {
    self.packer = packer
    self.renderer = renderer
    self.reservedInputTokens = max(0, reservedInputTokens)
    self.retriever = AnyLocalRetriever(retriever)
  }

  public func run(
    query: LocalRetrievalQuery
  ) async throws -> LocalRAGResult {
    let retrieval = try await retriever.retrieve(query)
    let packed = packer.pack(
      snippets: retrieval.snippets,
      reservedInputTokens: reservedInputTokens
    )

    return LocalRAGResult(
      query: query,
      retrieval: retrieval,
      packedSnippets: packed,
      contextBlock: renderer.render(snippets: packed),
      citations: renderer.citations(for: packed)
    )
  }
}

public struct LocalRAGResult: Equatable, Sendable {
  public var citations: [SnippetCitation]
  public var contextBlock: String
  public var packedSnippets: [RetrievedSnippet]
  public var query: LocalRetrievalQuery
  public var retrieval: LocalRetrievalResult

  public init(
    query: LocalRetrievalQuery,
    retrieval: LocalRetrievalResult,
    packedSnippets: [RetrievedSnippet],
    contextBlock: String,
    citations: [SnippetCitation]
  ) {
    self.citations = citations
    self.contextBlock = contextBlock
    self.packedSnippets = packedSnippets
    self.query = query
    self.retrieval = retrieval
  }

  public var sourceContext: StructuredGenerationSourceContext {
    StructuredGenerationSourceContext(
      sources: packedSnippets.map(\.evidenceSource)
    )
  }
}
