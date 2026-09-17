import Foundation
import SwiftLM

public enum TextEvaluationAssertion: Equatable, Codable, Sendable {
  case contains(String)
  case excludes(String)
  case maximumLength(Int)
  case minimumLength(Int)
  case minimumOccurrences(String, Int)

  public func failureMessage(
    for output: String
  ) -> String? {
    switch self {
    case let .contains(value):
      guard output.containsIgnoringCaseAndDiacritics(value) else {
        return "Missing required text: \(value)"
      }
      return nil

    case let .excludes(value):
      guard !output.containsIgnoringCaseAndDiacritics(value) else {
        return "Included forbidden text: \(value)"
      }
      return nil

    case let .maximumLength(maximum):
      guard output.count <= maximum else {
        return "Expected at most \(maximum) characters but received \(output.count)."
      }
      return nil

    case let .minimumLength(minimum):
      guard output.count >= minimum else {
        return "Expected at least \(minimum) characters but received \(output.count)."
      }
      return nil

    case let .minimumOccurrences(value, minimum):
      let count = output.caseInsensitiveOccurrenceCount(of: value)
      guard count >= minimum else {
        return "Expected at least \(minimum) occurrences of \(value) but received \(count)."
      }
      return nil
    }
  }
}

public struct PromptEvaluationCase: Codable, Equatable, Identifiable, Sendable {
  public var assertions: [TextEvaluationAssertion]
  public var forbiddenSubstrings: [String]
  public var id: String
  public var input: String
  public var notes: String
  public var requiredSubstrings: [String]
  public var tags: Set<String>

  public init(
    id: String,
    input: String,
    requiredSubstrings: [String] = [],
    forbiddenSubstrings: [String] = [],
    assertions: [TextEvaluationAssertion] = [],
    tags: Set<String> = [],
    notes: String = ""
  ) {
    self.assertions = assertions
    self.forbiddenSubstrings = forbiddenSubstrings
    self.id = id
    self.input = input
    self.notes = notes
    self.requiredSubstrings = requiredSubstrings
    self.tags = tags
  }
}

public struct PromptEvaluationResult: Equatable, Sendable {
  public var caseID: String
  public var failures: [String]
  public var output: String

  public init(
    caseID: String,
    output: String,
    failures: [String]
  ) {
    self.caseID = caseID
    self.output = output
    self.failures = failures
  }

  public var passed: Bool {
    failures.isEmpty
  }
}

public struct PromptEvaluator: Sendable {
  public init() {}

  public func evaluate(
    _ evaluationCase: PromptEvaluationCase,
    output: String
  ) -> PromptEvaluationResult {
    var failures: [String] = []

    for required in evaluationCase.requiredSubstrings {
      if !output.containsIgnoringCaseAndDiacritics(required) {
        failures.append("Missing required substring: \(required)")
      }
    }

    for forbidden in evaluationCase.forbiddenSubstrings {
      if output.containsIgnoringCaseAndDiacritics(forbidden) {
        failures.append("Included forbidden substring: \(forbidden)")
      }
    }

    for assertion in evaluationCase.assertions {
      if let failure = assertion.failureMessage(for: output) {
        failures.append(failure)
      }
    }

    return PromptEvaluationResult(
      caseID: evaluationCase.id,
      output: output,
      failures: failures
    )
  }
}

private extension String {
  func caseInsensitiveOccurrenceCount(of needle: String) -> Int {
    guard !needle.isEmpty else { return 0 }

    var count = 0
    var searchRange = startIndex..<endIndex
    while let range = range(
      of: needle,
      options: [.caseInsensitive, .diacriticInsensitive],
      range: searchRange
    ) {
      count += 1
      searchRange = range.upperBound..<endIndex
    }
    return count
  }
}
