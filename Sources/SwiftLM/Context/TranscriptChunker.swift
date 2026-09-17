import Foundation

public struct TranscriptSegment: Equatable, Identifiable, Sendable {
  public var confidence: Double?
  public var endTime: TimeInterval
  public var id: String
  public var speakerID: String?
  public var startTime: TimeInterval
  public var text: String

  public init(
    id: String,
    text: String,
    startTime: TimeInterval,
    endTime: TimeInterval,
    speakerID: String? = nil,
    confidence: Double? = nil
  ) {
    self.confidence = confidence
    self.endTime = endTime
    self.id = id
    self.speakerID = speakerID
    self.startTime = startTime
    self.text = text
  }
}

public struct TranscriptChunk: Equatable, Identifiable, Sendable {
  public var endTime: TimeInterval?
  public var id: Int
  public var segmentIDs: [TranscriptSegment.ID]
  public var sourceID: String
  public var startTime: TimeInterval?
  public var text: String
  public var tokenCount: Int

  public init(
    id: Int,
    sourceID: String,
    text: String,
    segmentIDs: [TranscriptSegment.ID],
    tokenCount: Int,
    startTime: TimeInterval? = nil,
    endTime: TimeInterval? = nil
  ) {
    self.endTime = endTime
    self.id = id
    self.segmentIDs = segmentIDs
    self.sourceID = sourceID
    self.startTime = startTime
    self.text = text
    self.tokenCount = tokenCount
  }

  public var evidenceSource: EvidenceSource {
    EvidenceSource(
      id: "\(sourceID)-chunk-\(id)",
      text: text,
      displayName: "Chunk \(id + 1)",
      kind: "transcriptChunk"
    )
  }
}

public struct TranscriptChunker: Sendable {
  public var counter: TokenCounter
  public var maxTokensPerChunk: Int
  public var overlapSegmentCount: Int
  public var sourceID: String

  public init(
    maxTokensPerChunk: Int,
    overlapSegmentCount: Int = 1,
    sourceID: String = "transcript",
    counter: TokenCounter = .latinHeuristic
  ) {
    self.counter = counter
    self.maxTokensPerChunk = max(1, maxTokensPerChunk)
    self.overlapSegmentCount = max(0, overlapSegmentCount)
    self.sourceID = sourceID
  }

  public func chunks(for segments: [TranscriptSegment]) -> [TranscriptChunk] {
    guard !segments.isEmpty else { return [] }

    var chunks: [TranscriptChunk] = []
    var cursor = 0

    while cursor < segments.count {
      var chunkSegments: [TranscriptSegment] = []
      var tokenCount = 0
      var index = cursor

      while index < segments.count {
        let candidateSegments = chunkSegments + [segments[index]]
        let candidateText = candidateSegments.map(\.text).joined(separator: " ").normalizedWhitespace
        let candidateTokens = counter.count(candidateText)
        guard candidateTokens <= maxTokensPerChunk || chunkSegments.isEmpty else { break }
        chunkSegments = candidateSegments
        tokenCount = candidateTokens
        index += 1
      }

      chunks.append(
        TranscriptChunk(
          id: chunks.count,
          sourceID: sourceID,
          text: chunkSegments.map(\.text).joined(separator: " ").normalizedWhitespace,
          segmentIDs: chunkSegments.map(\.id),
          tokenCount: tokenCount,
          startTime: chunkSegments.first?.startTime,
          endTime: chunkSegments.last?.endTime
        )
      )

      guard index < segments.count else { break }
      cursor = max(cursor + 1, index - overlapSegmentCount)
    }

    return chunks
  }
}
