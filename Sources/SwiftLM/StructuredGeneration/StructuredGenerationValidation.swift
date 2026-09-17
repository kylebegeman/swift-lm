import Foundation

public enum ValidationSeverity: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case warning
  case error
}

public struct ValidationIssue: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var evidenceID: EvidenceSpan.ID?
  public var id: String
  public var message: String
  public var path: String?
  public var severity: ValidationSeverity

  public init(
    id: String,
    message: String,
    severity: ValidationSeverity = .error,
    path: String? = nil,
    evidenceID: EvidenceSpan.ID? = nil
  ) {
    self.evidenceID = evidenceID
    self.id = id
    self.message = message
    self.path = path
    self.severity = severity
  }
}

public struct StructuredGenerationValidationResult: Codable, Equatable, Sendable {
  public var issues: [ValidationIssue]

  public init(issues: [ValidationIssue] = []) {
    self.issues = issues
  }

  public var isAccepted: Bool {
    !issues.contains { $0.severity == .error }
  }

  public static let accepted = Self()

  public static func + (
    lhs: Self,
    rhs: Self
  ) -> Self {
    Self(issues: lhs.issues + rhs.issues)
  }
}

public struct StructuredGenerationValidator<Output: Sendable>: Sendable {
  public var validate:
    @Sendable (
      StructuredGenerationCandidate<Output>,
      StructuredGenerationSourceContext
    ) -> StructuredGenerationValidationResult

  public init(
    validate: @escaping @Sendable (
      StructuredGenerationCandidate<Output>,
      StructuredGenerationSourceContext
    ) -> StructuredGenerationValidationResult
  ) {
    self.validate = validate
  }

  public func callAsFunction(
    _ candidate: StructuredGenerationCandidate<Output>,
    in context: StructuredGenerationSourceContext
  ) -> StructuredGenerationValidationResult {
    validate(candidate, context)
  }

  public func combined(
    with other: Self
  ) -> Self {
    Self { candidate, context in
      self(candidate, in: context) + other(candidate, in: context)
    }
  }

  public static var acceptAll: Self {
    Self { _, _ in .accepted }
  }

  public static func all(_ validators: [Self]) -> Self {
    validators.reduce(.acceptAll) { partial, validator in
      partial.combined(with: validator)
    }
  }

  public static func groundedEvidence(
    validator: GroundingValidator = GroundingValidator()
  ) -> Self {
    Self { candidate, context in
      let issues = candidate.evidence.compactMap { evidence -> ValidationIssue? in
        let sourceText = context.sourceText(for: evidence.sourceID)
        guard validator.isGrounded(evidence.text, in: sourceText)
        else {
          return ValidationIssue(
            id: "ungrounded-evidence-\(evidence.id)",
            message: "Evidence is not grounded in the provided source context.",
            path: "evidence",
            evidenceID: evidence.id
          )
        }
        return nil
      }
      return StructuredGenerationValidationResult(issues: issues)
    }
  }

  public static func maximumCount<Element>(
    _ values: @escaping @Sendable (Output) -> [Element],
    maximum: Int,
    path: String
  ) -> Self {
    Self { candidate, _ in
      let count = values(candidate.output).count
      guard count <= maximum else {
        return StructuredGenerationValidationResult(
          issues: [
            ValidationIssue(
              id: "maximum-count-\(path)",
              message: "Expected at most \(maximum) items but received \(count).",
              path: path
            )
          ]
        )
      }
      return .accepted
    }
  }

  public static func nonEmptyString(
    _ value: @escaping @Sendable (Output) -> String,
    path: String
  ) -> Self {
    Self { candidate, _ in
      guard !value(candidate.output).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return StructuredGenerationValidationResult(
          issues: [
            ValidationIssue(
              id: "empty-string-\(path)",
              message: "Expected non-empty generated text.",
              path: path
            )
          ]
        )
      }
      return .accepted
    }
  }
}
