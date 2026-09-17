import Foundation

public struct GroundingValidator: Sendable {
  public var minimumContentWordOverlap: Double

  public init(minimumContentWordOverlap: Double = 0.55) {
    self.minimumContentWordOverlap = minimumContentWordOverlap
  }

  public func isGrounded(
    _ generatedText: String,
    in sourceText: String
  ) -> Bool {
    let trimmedGeneratedText = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedGeneratedText.isEmpty else { return false }
    if sourceText.range(of: trimmedGeneratedText, options: .caseInsensitive) != nil {
      return true
    }

    let generated = trimmedGeneratedText.normalizedContentWords
    let source = Set(sourceText.normalizedContentWords)

    guard !generated.isEmpty, !source.isEmpty else { return false }

    let overlap = generated.filter { source.contains($0) }.count
    return Double(overlap) / Double(generated.count) >= minimumContentWordOverlap
  }
}

extension String {
  var normalizedContentWords: [String] {
    lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { word in
        word.count > 2 && !Self.stopWords.contains(word)
      }
  }

  private static let stopWords: Set<String> = [
    "and", "are", "but", "can", "for", "had", "has", "have", "her", "him",
    "his", "not", "our", "she", "that", "the", "their", "then", "there",
    "this", "was", "were", "with", "you", "your",
  ]
}
