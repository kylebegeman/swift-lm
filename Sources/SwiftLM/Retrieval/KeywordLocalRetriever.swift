import Foundation

public struct KeywordLocalRetriever: LocalRetriever {
  public var boundary: TextChunkBoundary
  public var counter: TokenCounter
  public var documents: [RetrievableDocument]
  public var maxTokensPerSnippet: Int

  public init(
    documents: [RetrievableDocument],
    maxTokensPerSnippet: Int = 180,
    boundary: TextChunkBoundary = .paragraph,
    counter: TokenCounter = .latinHeuristic
  ) {
    self.boundary = boundary
    self.counter = counter
    self.documents = documents
    self.maxTokensPerSnippet = max(1, maxTokensPerSnippet)
  }

  public func retrieve(_ query: LocalRetrievalQuery) async throws -> LocalRetrievalResult {
    let queryScoring = LocalRetrievalScorer.Query(text: query.text)
    guard query.maxResults > 0,
          !queryScoring.terms.isEmpty || !query.requiredSourceIDs.isEmpty
    else {
      return LocalRetrievalResult(query: query, snippets: [], sources: [])
    }

    let chunker = BoundaryAwareTextChunker(
      boundary: boundary,
      maxTokensPerChunk: maxTokensPerSnippet,
      overlapUnitCount: 0,
      counter: counter
    )
    var snippets: [(snippet: RetrievedSnippet, chunkIndex: Int)] = []
    var sourcesByID: [SourceReference.ID: SourceReference] = [:]

    for document in documents where query.allows(sourceID: document.source.id) {
      let chunks = chunker.chunks(for: document.text)
      let documentChunks = chunks.isEmpty
        ? [
          TextChunk(
            id: 0,
            text: document.text,
            characterRange: document.text.startIndex..<document.text.endIndex,
            tokenCount: counter.count(document.text)
          )
        ]
        : chunks

      for chunk in documentChunks {
        let score = LocalRetrievalScorer.score(text: chunk.text, query: queryScoring)
        guard (score > 0 && score >= query.minimumScore)
          || query.requiredSourceIDs.contains(document.source.id)
        else { continue }

        sourcesByID[document.source.id] = document.source
        snippets.append(
          (
            snippet: RetrievedSnippet(
              id: "\(document.id)#\(chunk.id)",
              sourceID: document.source.id,
              text: chunk.text,
              tokenCount: chunk.tokenCount,
              score: score,
              sourceDisplayName: document.source.displayName,
              sourceKind: document.source.kind,
              characterRange: document.text.intRange(for: chunk.characterRange),
              isRequired: query.requiredSourceIDs.contains(document.source.id)
            ),
            chunkIndex: chunk.id
          )
        )
      }
    }

    // User-selected sources are stronger intent than incidental keyword score. Ties keep document
    // order by chunk index so a required note is never returned out of sequence.
    let ranked = snippets
      .sorted { lhs, rhs in
        if lhs.snippet.isRequired != rhs.snippet.isRequired {
          return lhs.snippet.isRequired
        }
        if lhs.snippet.score != rhs.snippet.score {
          return lhs.snippet.score > rhs.snippet.score
        }
        if lhs.snippet.sourceID != rhs.snippet.sourceID {
          return lhs.snippet.sourceID < rhs.snippet.sourceID
        }
        return lhs.chunkIndex < rhs.chunkIndex
      }
      .prefix(query.maxResults)

    let resultSnippets = ranked.map(\.snippet)
    let sources = resultSnippets
      .compactMap { sourcesByID[$0.sourceID] }
      .uniquedByID()

    return LocalRetrievalResult(
      query: query,
      snippets: resultSnippets,
      sources: sources
    )
  }
}

enum LocalRetrievalScorer {
  struct Query {
    var normalizedText: String
    var terms: [String]

    init(text: String) {
      self.terms = LocalRetrievalScorer.terms(in: text)
      self.normalizedText = terms.joined(separator: " ")
    }
  }

  static func score(
    text: String,
    query: Query
  ) -> Double {
    let textTerms = self.terms(in: text)
    guard !textTerms.isEmpty else { return 0 }

    let querySet = Set(query.terms)
    let textSet = Set(textTerms)
    let matchedUnique = querySet.intersection(textSet).count
    let totalMatches = textTerms.filter { querySet.contains($0) }.count
    guard matchedUnique > 0 else { return 0 }

    let coverage = Double(matchedUnique) / Double(max(1, querySet.count))
    let frequency = log(Double(totalMatches) + 1)
    let phraseBonus = text.normalizedForRetrieval.contains(query.normalizedText) ? 0.5 : 0
    return coverage + frequency + phraseBonus
  }

  static func terms(in text: String) -> [String] {
    text
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count > 1 }
  }
}

private extension LocalRetrievalQuery {
  func allows(sourceID: SourceReference.ID) -> Bool {
    guard !excludedSourceIDs.contains(sourceID) else { return false }
    if requiredSourceIDs.contains(sourceID) {
      return true
    }
    if let allowedSourceIDs {
      return allowedSourceIDs.contains(sourceID)
    }
    return true
  }
}

private extension Array where Element == SourceReference {
  func uniquedByID() -> [SourceReference] {
    var seenIDs = Set<SourceReference.ID>()
    var result: [SourceReference] = []
    for source in self where !seenIDs.contains(source.id) {
      seenIDs.insert(source.id)
      result.append(source)
    }
    return result
  }
}

private extension String {
  var normalizedForRetrieval: String {
    LocalRetrievalScorer.terms(in: self).joined(separator: " ")
  }

  func intRange(for range: Range<String.Index>) -> Range<Int> {
    distance(from: startIndex, to: range.lowerBound)..<distance(from: startIndex, to: range.upperBound)
  }
}
