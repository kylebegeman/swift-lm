import Foundation

public struct EvidenceSource: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var displayName: String?
  public var id: String
  public var kind: String?
  public var text: String

  public init(
    id: String,
    text: String,
    displayName: String? = nil,
    kind: String? = nil
  ) {
    self.displayName = displayName
    self.id = id
    self.kind = kind
    self.text = text
  }
}

public struct EvidenceSpan: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var characterRange: Range<Int>?
  public var confidence: Double?
  public var id: String
  public var sourceID: EvidenceSource.ID?
  public var text: String

  public init(
    id: String,
    text: String,
    sourceID: EvidenceSource.ID? = nil,
    characterRange: Range<Int>? = nil,
    confidence: Double? = nil
  ) {
    self.characterRange = characterRange
    self.confidence = confidence
    self.id = id
    self.sourceID = sourceID
    self.text = text
  }
}

public struct StructuredGenerationSourceContext: Codable, Equatable, Sendable {
  public var sources: [EvidenceSource]

  public init(sources: [EvidenceSource] = []) {
    self.sources = sources
  }

  public init(sourceText: String, sourceID: String = "source") {
    self.sources = [
      EvidenceSource(id: sourceID, text: sourceText)
    ]
  }

  public func sourceText(for sourceID: EvidenceSource.ID?) -> String {
    guard let sourceID,
      let source = sources.first(where: { $0.id == sourceID })
    else {
      return sources.map(\.text).joined(separator: "\n\n")
    }

    return source.text
  }
}

public struct StructuredGenerationCandidate<Output: Sendable>: Sendable {
  public var evidence: [EvidenceSpan]
  public var metadata: LMProviderMetadata
  public var output: Output
  public var rawOutputDescription: String?
  public var tokenUsage: LMTokenUsage?

  public init(
    output: Output,
    metadata: LMProviderMetadata,
    evidence: [EvidenceSpan] = [],
    tokenUsage: LMTokenUsage? = nil,
    rawOutputDescription: String? = nil
  ) {
    self.evidence = evidence
    self.metadata = metadata
    self.output = output
    self.rawOutputDescription = rawOutputDescription
    self.tokenUsage = tokenUsage
  }

  public init(
    generationCandidate: GenerationCandidate<Output>,
    evidence: [EvidenceSpan] = [],
    rawOutputDescription: String? = nil
  ) {
    self.init(
      output: generationCandidate.output,
      metadata: generationCandidate.metadata,
      evidence: evidence,
      tokenUsage: generationCandidate.tokenUsage,
      rawOutputDescription: rawOutputDescription
    )
  }

  public var generationCandidate: GenerationCandidate<Output> {
    GenerationCandidate(
      output: output,
      metadata: metadata,
      tokenUsage: tokenUsage
    )
  }
}

extension StructuredGenerationCandidate: Equatable where Output: Equatable {}
