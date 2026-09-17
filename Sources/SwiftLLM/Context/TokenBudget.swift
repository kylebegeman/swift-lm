import Foundation

public struct TokenBudget: Equatable, Sendable {
  public var contextLimit: Int
  public var reservedResponseTokens: Int
  public var safetyMarginTokens: Int

  public init(
    contextLimit: Int = 4_096,
    reservedResponseTokens: Int = 512,
    safetyMarginTokens: Int = 256
  ) {
    self.contextLimit = contextLimit
    self.reservedResponseTokens = reservedResponseTokens
    self.safetyMarginTokens = safetyMarginTokens
  }

  public var availableInputTokens: Int {
    max(0, contextLimit - reservedResponseTokens - safetyMarginTokens)
  }
}

public struct TokenCounter: Sendable {
  public var count: @Sendable (String) -> Int

  public init(count: @escaping @Sendable (String) -> Int) {
    self.count = count
  }

  public static let latinHeuristic = Self { text in
    guard !text.isEmpty else { return 0 }

    let latinScalars = text.unicodeScalars.filter { $0.value < 0x3000 }.count
    let nonLatinScalars = text.unicodeScalars.count - latinScalars
    let latinTokens = Int(ceil(Double(latinScalars) / 4.0))
    return max(1, latinTokens + nonLatinScalars)
  }
}

public struct TextChunk: Equatable, Identifiable, Sendable {
  public var characterRange: Range<String.Index>
  public var id: Int
  public var text: String
  public var tokenCount: Int

  public init(
    id: Int,
    text: String,
    characterRange: Range<String.Index>,
    tokenCount: Int
  ) {
    self.id = id
    self.text = text
    self.characterRange = characterRange
    self.tokenCount = tokenCount
  }
}

public struct TextChunker: Sendable {
  public var counter: TokenCounter
  public var maxTokensPerChunk: Int
  public var overlapTokens: Int

  /// - Parameter overlapTokens: Tokens repeated between consecutive chunks. It is clamped to half
  ///   of `maxTokensPerChunk` so a large overlap cannot degrade chunking into a one-word stride.
  public init(
    maxTokensPerChunk: Int,
    overlapTokens: Int = 64,
    counter: TokenCounter = .latinHeuristic
  ) {
    self.counter = counter
    self.maxTokensPerChunk = max(1, maxTokensPerChunk)
    self.overlapTokens = min(max(0, overlapTokens), self.maxTokensPerChunk / 2)
  }

  public func chunks(for text: String) -> [TextChunk] {
    let words = text
      .split(whereSeparator: \.isWhitespace)
      .map { word in
        (
          text: String(word),
          range: word.startIndex..<word.endIndex
        )
      }

    guard !words.isEmpty else { return [] }

    var chunks: [TextChunk] = []
    var cursor = 0

    while cursor < words.count {
      var chunkWords: [String] = []
      var tokenCount = 0
      var index = cursor

      while index < words.count {
        let candidate = chunkWords + [words[index].text]
        let candidateText = candidate.joined(separator: " ")
        let candidateTokens = counter.count(candidateText)
        guard candidateTokens <= maxTokensPerChunk || chunkWords.isEmpty else { break }
        chunkWords = candidate
        tokenCount = candidateTokens
        index += 1
      }

      let chunkText = chunkWords.joined(separator: " ")
      let chunkRange = words[cursor].range.lowerBound..<words[index - 1].range.upperBound
      chunks.append(
        TextChunk(
          id: chunks.count,
          text: chunkText,
          characterRange: chunkRange,
          tokenCount: tokenCount
        )
      )

      guard index < words.count else { break }

      if overlapTokens == 0 {
        cursor = index
      } else {
        var overlapStart = index
        var overlapWords: [String] = []
        while overlapStart > cursor {
          let candidate = [words[overlapStart - 1].text] + overlapWords
          guard counter.count(candidate.joined(separator: " ")) <= overlapTokens else { break }
          overlapWords = candidate
          overlapStart -= 1
        }
        cursor = max(cursor + 1, overlapStart)
      }
    }

    return chunks
  }
}
