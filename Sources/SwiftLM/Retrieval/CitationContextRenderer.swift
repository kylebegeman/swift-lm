import Foundation

public struct SnippetCitation: Equatable, Identifiable, Sendable {
  public var characterRange: Range<Int>?
  public var id: String
  public var marker: String
  public var snippetID: RetrievedSnippet.ID
  public var sourceDisplayName: String?
  public var sourceID: SourceReference.ID
  public var sourceKind: String?

  public init(
    id: String,
    marker: String,
    snippetID: RetrievedSnippet.ID,
    sourceID: SourceReference.ID,
    sourceDisplayName: String? = nil,
    sourceKind: String? = nil,
    characterRange: Range<Int>? = nil
  ) {
    self.characterRange = characterRange
    self.id = id
    self.marker = marker
    self.snippetID = snippetID
    self.sourceDisplayName = sourceDisplayName
    self.sourceID = sourceID
    self.sourceKind = sourceKind
  }
}

public enum CitationMarkerStyle: Equatable, Sendable {
  case numeric
  case snippetID
}

public struct CitationContextRenderer: Sendable {
  public var markerStyle: CitationMarkerStyle

  public init(markerStyle: CitationMarkerStyle = .numeric) {
    self.markerStyle = markerStyle
  }

  public func citations(for snippets: [RetrievedSnippet]) -> [SnippetCitation] {
    snippets.enumerated().map { index, snippet in
      let marker = marker(for: snippet, index: index)
      return SnippetCitation(
        id: marker,
        marker: marker,
        snippetID: snippet.id,
        sourceID: snippet.sourceID,
        sourceDisplayName: snippet.sourceDisplayName,
        sourceKind: snippet.sourceKind,
        characterRange: snippet.characterRange
      )
    }
  }

  public func render(snippets: [RetrievedSnippet]) -> String {
    snippets.enumerated().map { index, snippet in
      let marker = marker(for: snippet, index: index)
      let sourceName = snippet.sourceDisplayName ?? snippet.sourceID
      let sourceKind = snippet.sourceKind.map { " (\($0))" } ?? ""
      return """
      [\(marker)] \(sourceName)\(sourceKind)
      \(snippet.text)
      """
    }
    .joined(separator: "\n\n")
  }

  private func marker(
    for snippet: RetrievedSnippet,
    index: Int
  ) -> String {
    switch markerStyle {
    case .numeric:
      return "\(index + 1)"
    case .snippetID:
      return snippet.id
    }
  }
}
