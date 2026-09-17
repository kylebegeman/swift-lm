import Foundation

public struct RetrievedSnippet: Equatable, Identifiable, Sendable {
  public var characterRange: Range<Int>?
  public var id: String
  public var isRequired: Bool
  public var sourceDisplayName: String?
  public var sourceID: String
  public var sourceKind: String?
  public var text: String
  public var tokenCount: Int
  public var score: Double

  public init(
    id: String,
    sourceID: String,
    text: String,
    tokenCount: Int,
    score: Double,
    sourceDisplayName: String? = nil,
    sourceKind: String? = nil,
    characterRange: Range<Int>? = nil,
    isRequired: Bool = false
  ) {
    self.characterRange = characterRange
    self.id = id
    self.isRequired = isRequired
    self.sourceDisplayName = sourceDisplayName
    self.sourceID = sourceID
    self.sourceKind = sourceKind
    self.text = text
    self.tokenCount = tokenCount
    self.score = score
  }

  public var sourceReference: SourceReference {
    SourceReference(
      id: sourceID,
      displayName: sourceDisplayName,
      kind: sourceKind
    )
  }

  public var evidenceSource: EvidenceSource {
    EvidenceSource(
      id: id,
      text: text,
      displayName: sourceDisplayName,
      kind: sourceKind
    )
  }
}
