import Foundation

public enum StructuredGenerationRepairAction: Equatable, Sendable {
  case none
  case retryWithShorterContext
  case retryWithFewerExamples
  case retryWithSimplerSchema
  case retryWithMaximumResponseTokens(Int)
  case fallback(FallbackReason)
}

public struct StructuredGenerationRepairPlan: Equatable, Sendable {
  public var action: StructuredGenerationRepairAction
  public var notes: String?
  public var validationIssues: [ValidationIssue]

  public init(
    action: StructuredGenerationRepairAction,
    validationIssues: [ValidationIssue] = [],
    notes: String? = nil
  ) {
    self.action = action
    self.notes = notes
    self.validationIssues = validationIssues
  }

  public static let none = Self(action: .none)
}

public struct StructuredGenerationRepairPolicy<Output: Sendable>: Sendable {
  public var plan:
    @Sendable (
      StructuredGenerationCandidate<Output>?,
      StructuredGenerationValidationResult,
      FallbackReason?
    ) -> StructuredGenerationRepairPlan

  public init(
    plan: @escaping @Sendable (
      StructuredGenerationCandidate<Output>?,
      StructuredGenerationValidationResult,
      FallbackReason?
    ) -> StructuredGenerationRepairPlan
  ) {
    self.plan = plan
  }

  public static var none: Self {
    Self { _, _, _ in .none }
  }

  public static func fallbackOnValidationFailure(
    notes: String? = nil
  ) -> Self {
    Self { _, validation, failureReason in
      if let failureReason {
        return StructuredGenerationRepairPlan(
          action: .fallback(failureReason),
          validationIssues: validation.issues,
          notes: notes
        )
      }
      guard !validation.isAccepted else { return .none }
      return StructuredGenerationRepairPlan(
        action: .fallback(.validationFailed),
        validationIssues: validation.issues,
        notes: notes
      )
    }
  }
}

public struct StructuredGenerationFallbackPolicy<Output: Sendable>: Sendable {
  public var resolve:
    @Sendable (
      FallbackReason,
      StructuredGenerationCandidate<Output>?,
      StructuredGenerationValidationResult
    ) -> Output?

  public init(
    resolve: @escaping @Sendable (
      FallbackReason,
      StructuredGenerationCandidate<Output>?,
      StructuredGenerationValidationResult
    ) -> Output?
  ) {
    self.resolve = resolve
  }

  public static var none: Self {
    Self { _, _, _ in nil }
  }

  public static func fixed(_ output: Output) -> Self {
    Self { _, _, _ in output }
  }
}
