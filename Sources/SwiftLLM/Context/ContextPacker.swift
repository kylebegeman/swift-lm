import Foundation

public struct ContextPacker: Sendable {
  public var budget: TokenBudget
  public var strategy: ContextPackingStrategy

  public init(
    budget: TokenBudget,
    strategy: ContextPackingStrategy = .scoreDescending
  ) {
    self.budget = budget
    self.strategy = strategy
  }

  public func pack(
    snippets: [RetrievedSnippet],
    reservedInputTokens: Int = 0
  ) -> [RetrievedSnippet] {
    var remaining = max(0, budget.availableInputTokens - reservedInputTokens)
    var packed: [RetrievedSnippet] = []
    var packedIDs = Set<RetrievedSnippet.ID>()

    let required = strategy.sort(snippets.filter(\.isRequired))
    let optional = strategy.sort(snippets.filter { !$0.isRequired })

    for snippet in required + optional {
      guard !packedIDs.contains(snippet.id) else { continue }
      guard snippet.tokenCount <= remaining else { continue }
      packed.append(snippet)
      packedIDs.insert(snippet.id)
      remaining -= snippet.tokenCount
    }

    return packed
  }
}

public enum ContextPackingStrategy: Equatable, Sendable {
  case scoreDescending
  case scoreDensity
  case sourceDiverse

  func sort(_ snippets: [RetrievedSnippet]) -> [RetrievedSnippet] {
    switch self {
    case .scoreDescending:
      return snippets.sorted { lhs, rhs in
        if lhs.score != rhs.score {
          return lhs.score > rhs.score
        }
        return lhs.tokenCount < rhs.tokenCount
      }
    case .scoreDensity:
      return snippets.sorted { lhs, rhs in
        let lhsDensity = lhs.score / Double(max(1, lhs.tokenCount))
        let rhsDensity = rhs.score / Double(max(1, rhs.tokenCount))
        if lhsDensity != rhsDensity {
          return lhsDensity > rhsDensity
        }
        return lhs.score > rhs.score
      }
    case .sourceDiverse:
      var groups = Dictionary(grouping: snippets, by: \.sourceID)
        .mapValues { snippets in
          snippets.sorted { lhs, rhs in
            if lhs.score != rhs.score {
              return lhs.score > rhs.score
            }
            return lhs.tokenCount < rhs.tokenCount
          }
        }
      var ordered: [RetrievedSnippet] = []

      while !groups.isEmpty {
        let sourceIDs = groups.keys.sorted { lhs, rhs in
          let lhsScore = groups[lhs]?.first?.score ?? -.infinity
          let rhsScore = groups[rhs]?.first?.score ?? -.infinity
          if lhsScore != rhsScore {
            return lhsScore > rhsScore
          }
          return lhs < rhs
        }

        for sourceID in sourceIDs {
          guard var snippets = groups[sourceID],
            !snippets.isEmpty
          else {
            groups[sourceID] = nil
            continue
          }
          ordered.append(snippets.removeFirst())
          groups[sourceID] = snippets.isEmpty ? nil : snippets
        }
      }

      return ordered
    }
  }
}
