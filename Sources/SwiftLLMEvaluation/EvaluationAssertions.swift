import Foundation
import SwiftLLM

public enum EvaluationSeverity: String, Codable, Equatable, Sendable {
  case warning
  case error
}

public struct EvaluationIssue: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var message: String
  public var path: String?
  public var severity: EvaluationSeverity

  public init(
    id: String,
    message: String,
    severity: EvaluationSeverity = .error,
    path: String? = nil
  ) {
    self.id = id
    self.message = message
    self.path = path
    self.severity = severity
  }
}

public struct StructuredEvaluationAssertion<Output: Sendable>: Sendable {
  public var evaluate: @Sendable (Output) -> [EvaluationIssue]
  public var id: String

  public init(
    id: String,
    evaluate: @escaping @Sendable (Output) -> [EvaluationIssue]
  ) {
    self.evaluate = evaluate
    self.id = id
  }

  public func callAsFunction(_ output: Output) -> [EvaluationIssue] {
    evaluate(output)
  }
}

extension StructuredEvaluationAssertion {
  public static func predicate(
    id: String,
    message: String,
    path: String? = nil,
    severity: EvaluationSeverity = .error,
    isSatisfied: @escaping @Sendable (Output) -> Bool
  ) -> Self {
    Self(id: id) { output in
      guard isSatisfied(output) else {
        return [
          EvaluationIssue(
            id: id,
            message: message,
            severity: severity,
            path: path
          )
        ]
      }
      return []
    }
  }

  public static func nonEmptyString(
    _ value: @escaping @Sendable (Output) -> String,
    id: String,
    path: String
  ) -> Self {
    predicate(
      id: id,
      message: "Expected non-empty text.",
      path: path
    ) { output in
      !value(output).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  public static func maximumCount<Element>(
    _ values: @escaping @Sendable (Output) -> [Element],
    maximum: Int,
    id: String,
    path: String
  ) -> Self {
    Self(id: id) { output in
      let count = values(output).count
      guard count <= maximum else {
        return [
          EvaluationIssue(
            id: id,
            message: "Expected at most \(maximum) items but received \(count).",
            path: path
          )
        ]
      }
      return []
    }
  }

  public static func requiredText(
    _ value: @escaping @Sendable (Output) -> String,
    contains requiredText: String,
    id: String,
    path: String
  ) -> Self {
    predicate(
      id: id,
      message: "Expected text to contain \(requiredText).",
      path: path
    ) { output in
      value(output).containsIgnoringCaseAndDiacritics(requiredText)
    }
  }
}

public struct StructuredOutputEvaluationResult<Output: Sendable>: Sendable {
  public var caseID: String
  public var issues: [EvaluationIssue]
  public var output: Output

  public init(
    caseID: String,
    output: Output,
    issues: [EvaluationIssue]
  ) {
    self.caseID = caseID
    self.issues = issues
    self.output = output
  }

  public var passed: Bool {
    !issues.contains { $0.severity == .error }
  }
}

extension StructuredOutputEvaluationResult: Equatable where Output: Equatable {}

public struct StructuredOutputEvaluator<Output: Sendable>: Sendable {
  public var assertions: [StructuredEvaluationAssertion<Output>]

  public init(assertions: [StructuredEvaluationAssertion<Output>]) {
    self.assertions = assertions
  }

  public func evaluate(
    caseID: String,
    output: Output
  ) -> StructuredOutputEvaluationResult<Output> {
    StructuredOutputEvaluationResult(
      caseID: caseID,
      output: output,
      issues: assertions.flatMap { $0(output) }
    )
  }
}
