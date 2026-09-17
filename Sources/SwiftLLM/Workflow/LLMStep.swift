import Foundation

/// A typed, composable unit of work. Steps may transform the typed value and
/// may also add workflow diagnostics such as provenance, validation issues, and
/// token reports.
public struct LLMStep<Input: Sendable, Output: Sendable>: Sendable {
  public var id: String
  public var kind: LLMStepKind
  private var operation:
    @Sendable (Input, LLMWorkflowContext) async throws -> LLMStepResult<Output>

  public init(
    id: String,
    kind: LLMStepKind,
    operation: @escaping @Sendable (
      Input,
      LLMWorkflowContext
    ) async throws -> LLMStepResult<Output>
  ) {
    self.id = id
    self.kind = kind
    self.operation = operation
  }

  public func run(
    _ input: Input,
    context: LLMWorkflowContext
  ) async throws -> LLMStepResult<Output> {
    try await operation(input, context)
  }

  func execute(
    _ input: Input,
    context: LLMWorkflowContext
  ) async throws -> (Output, LLMWorkflowContext) {
    var context = context
    context.appendEvent(
      LLMWorkflowEvent(
        kind: .stepStarted,
        stepID: id,
        metadata: ["kind": kind.diagnosticName]
      )
    )

    try Task.checkCancellation()
    let result: LLMStepResult<Output>
    do {
      result = try await operation(input, context)
    } catch let error as CancellationError {
      throw error
    } catch let error as LLMWorkflowError {
      throw error
    } catch {
      context.appendEvent(
        LLMWorkflowEvent(
          kind: .stepFailed,
          stepID: id,
          metadata: [
            "errorType": String(reflecting: type(of: error)),
            "kind": kind.diagnosticName,
          ]
        )
      )
      throw LLMWorkflowError(underlyingError: error, stepID: id, context: context)
    }
    try Task.checkCancellation()

    context.apply(result, from: self)
    context.appendEvent(
      LLMWorkflowEvent(
        kind: .stepFinished,
        stepID: id,
        metadata: ["kind": kind.diagnosticName]
      )
    )

    return (result.output, context)
  }
}

extension LLMStep {
  /// Build a deterministic transform or analysis step.
  public static func deterministicTransform(
    id: String,
    captureIntermediateOutput: (@Sendable (Output) -> LLMWorkflowIntermediateOutput?)? = nil,
    transform: @escaping @Sendable (
      Input,
      LLMWorkflowContext
    ) async throws -> Output
  ) -> Self {
    Self(id: id, kind: .deterministic) { input, context in
      let output = try await transform(input, context)
      return LLMStepResult(
        output: output,
        intermediateOutput: captureIntermediateOutput?(output)
      )
    }
  }
}
