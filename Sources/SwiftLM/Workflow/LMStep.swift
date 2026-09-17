import Foundation

/// A typed, composable unit of work. Steps may transform the typed value and
/// may also add workflow diagnostics such as provenance, validation issues, and
/// token reports.
public struct LMStep<Input: Sendable, Output: Sendable>: Sendable {
  public var id: String
  public var kind: LMStepKind
  private var operation:
    @Sendable (Input, LMWorkflowContext) async throws -> LMStepResult<Output>

  public init(
    id: String,
    kind: LMStepKind,
    operation: @escaping @Sendable (
      Input,
      LMWorkflowContext
    ) async throws -> LMStepResult<Output>
  ) {
    self.id = id
    self.kind = kind
    self.operation = operation
  }

  public func run(
    _ input: Input,
    context: LMWorkflowContext
  ) async throws -> LMStepResult<Output> {
    try await operation(input, context)
  }

  func execute(
    _ input: Input,
    context: LMWorkflowContext
  ) async throws -> (Output, LMWorkflowContext) {
    var context = context
    context.appendEvent(
      LMWorkflowEvent(
        kind: .stepStarted,
        stepID: id,
        metadata: ["kind": kind.diagnosticName]
      )
    )

    try Task.checkCancellation()
    let result: LMStepResult<Output>
    do {
      result = try await operation(input, context)
    } catch let error as CancellationError {
      throw error
    } catch let error as LMWorkflowError {
      throw error
    } catch {
      context.appendEvent(
        LMWorkflowEvent(
          kind: .stepFailed,
          stepID: id,
          metadata: [
            "errorType": String(reflecting: type(of: error)),
            "kind": kind.diagnosticName,
          ]
        )
      )
      throw LMWorkflowError(underlyingError: error, stepID: id, context: context)
    }
    try Task.checkCancellation()

    context.apply(result, from: self)
    context.appendEvent(
      LMWorkflowEvent(
        kind: .stepFinished,
        stepID: id,
        metadata: ["kind": kind.diagnosticName]
      )
    )

    return (result.output, context)
  }
}

extension LMStep {
  /// Build a deterministic transform or analysis step.
  public static func deterministicTransform(
    id: String,
    captureIntermediateOutput: (@Sendable (Output) -> LMWorkflowIntermediateOutput?)? = nil,
    transform: @escaping @Sendable (
      Input,
      LMWorkflowContext
    ) async throws -> Output
  ) -> Self {
    Self(id: id, kind: .deterministic) { input, context in
      let output = try await transform(input, context)
      return LMStepResult(
        output: output,
        intermediateOutput: captureIntermediateOutput?(output)
      )
    }
  }
}
