import Foundation

public struct SourceReference: Equatable, Identifiable, Sendable {
  public var displayName: String?
  public var id: String
  public var kind: String?
  public var metadata: [String: String]
  public var updatedAt: Date?

  public init(
    id: String,
    displayName: String? = nil,
    kind: String? = nil,
    metadata: [String: String] = [:],
    updatedAt: Date? = nil
  ) {
    self.displayName = displayName
    self.id = id
    self.kind = kind
    self.metadata = metadata
    self.updatedAt = updatedAt
  }
}

public struct RetrievableDocument: Equatable, Identifiable, Sendable {
  public var id: String
  public var source: SourceReference
  public var text: String

  public init(
    id: String,
    text: String,
    displayName: String? = nil,
    kind: String? = nil,
    metadata: [String: String] = [:],
    updatedAt: Date? = nil
  ) {
    self.id = id
    self.source = SourceReference(
      id: id,
      displayName: displayName,
      kind: kind,
      metadata: metadata,
      updatedAt: updatedAt
    )
    self.text = text
  }

  public init(
    id: String,
    source: SourceReference,
    text: String
  ) {
    self.id = id
    self.source = source
    self.text = text
  }
}

public struct LocalRetrievalQuery: Equatable, Sendable {
  public var allowedSourceIDs: Set<SourceReference.ID>?
  public var excludedSourceIDs: Set<SourceReference.ID>
  public var maxResults: Int
  public var metadata: [String: String]
  public var minimumScore: Double
  public var requiredSourceIDs: Set<SourceReference.ID>
  public var text: String

  public init(
    text: String,
    maxResults: Int = 8,
    minimumScore: Double = 0,
    allowedSourceIDs: Set<SourceReference.ID>? = nil,
    excludedSourceIDs: Set<SourceReference.ID> = [],
    requiredSourceIDs: Set<SourceReference.ID> = [],
    metadata: [String: String] = [:]
  ) {
    self.allowedSourceIDs = allowedSourceIDs
    self.excludedSourceIDs = excludedSourceIDs
    self.maxResults = max(0, maxResults)
    self.metadata = metadata
    self.minimumScore = minimumScore
    self.requiredSourceIDs = requiredSourceIDs
    self.text = text
  }
}

public struct LocalRetrievalResult: Equatable, Sendable {
  public var query: LocalRetrievalQuery
  public var snippets: [RetrievedSnippet]
  public var sources: [SourceReference]

  public init(
    query: LocalRetrievalQuery,
    snippets: [RetrievedSnippet],
    sources: [SourceReference]
  ) {
    self.query = query
    self.snippets = snippets
    self.sources = sources
  }
}

public protocol LocalRetriever: Sendable {
  func retrieve(_ query: LocalRetrievalQuery) async throws -> LocalRetrievalResult
}

public struct AnyLocalRetriever: LocalRetriever {
  private var retrieveHandler:
    @Sendable (LocalRetrievalQuery) async throws -> LocalRetrievalResult

  public init(
    retrieve: @escaping @Sendable (LocalRetrievalQuery) async throws -> LocalRetrievalResult
  ) {
    self.retrieveHandler = retrieve
  }

  public init<R: LocalRetriever>(_ retriever: R) {
    self.init { query in
      try await retriever.retrieve(query)
    }
  }

  public func retrieve(_ query: LocalRetrievalQuery) async throws -> LocalRetrievalResult {
    try await retrieveHandler(query)
  }
}
