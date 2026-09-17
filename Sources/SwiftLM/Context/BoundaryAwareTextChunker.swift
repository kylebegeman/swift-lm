import Foundation

public enum TextChunkBoundary: Equatable, Sendable {
  case word
  case sentence
  case paragraph
}

public struct BoundaryAwareTextChunker: Sendable {
  public var boundary: TextChunkBoundary
  public var counter: TokenCounter
  public var maxTokensPerChunk: Int
  public var overlapUnitCount: Int

  public init(
    boundary: TextChunkBoundary,
    maxTokensPerChunk: Int,
    overlapUnitCount: Int = 0,
    counter: TokenCounter = .latinHeuristic
  ) {
    self.boundary = boundary
    self.counter = counter
    self.maxTokensPerChunk = max(1, maxTokensPerChunk)
    self.overlapUnitCount = max(0, overlapUnitCount)
  }

  public func chunks(for text: String) -> [TextChunk] {
    let units = text.units(splitBy: boundary)
    guard !units.isEmpty else { return [] }

    var chunks: [TextChunk] = []
    var cursor = 0

    while cursor < units.count {
      var chunkUnits: [(text: String, range: Range<String.Index>)] = []
      var tokenCount = 0
      var index = cursor

      while index < units.count {
        let candidateUnits = chunkUnits + [units[index]]
        let candidateText = candidateUnits.map(\.text).joined(separator: " ").normalizedWhitespace
        let candidateTokens = counter.count(candidateText)
        guard candidateTokens <= maxTokensPerChunk || chunkUnits.isEmpty else { break }
        chunkUnits = candidateUnits
        tokenCount = candidateTokens
        index += 1
      }

      let chunkText = chunkUnits.map(\.text).joined(separator: " ").normalizedWhitespace
      let chunkRange = chunkUnits[0].range.lowerBound..<chunkUnits[chunkUnits.count - 1].range.upperBound
      chunks.append(
        TextChunk(
          id: chunks.count,
          text: chunkText,
          characterRange: chunkRange,
          tokenCount: tokenCount
        )
      )

      guard index < units.count else { break }
      cursor = max(cursor + 1, index - overlapUnitCount)
    }

    return chunks
  }
}
