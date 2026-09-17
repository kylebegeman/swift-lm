import Foundation

public enum StructuredGenerationPipelineStatus: String, Equatable, Sendable {
  case accepted
  case rejected
  case fellBack
  case failed
}

public struct StructuredGenerationPipelineResult<Output: Sendable>: Sendable {
  public var candidate: StructuredGenerationCandidate<Output>?
  public var errorMessage: String?
  public var fallbackDecision: FallbackDecision<Output>?
  public var repairPlan: StructuredGenerationRepairPlan
  public var status: StructuredGenerationPipelineStatus
  public var validation: StructuredGenerationValidationResult

  public init(
    status: StructuredGenerationPipelineStatus,
    candidate: StructuredGenerationCandidate<Output>? = nil,
    validation: StructuredGenerationValidationResult = .accepted,
    repairPlan: StructuredGenerationRepairPlan = .none,
    fallbackDecision: FallbackDecision<Output>? = nil,
    errorMessage: String? = nil
  ) {
    self.candidate = candidate
    self.errorMessage = errorMessage
    self.fallbackDecision = fallbackDecision
    self.repairPlan = repairPlan
    self.status = status
    self.validation = validation
  }

  /// The value an app may use: the accepted candidate or a resolved fallback. `nil` when
  /// validation rejected the candidate or generation failed without a fallback.
  public var output: Output? {
    if let fallbackOutput = fallbackDecision?.output {
      return fallbackOutput
    }
    return status == .accepted ? candidate?.output : nil
  }

  /// The generated value even when validation rejected it. Use it for review UI, never as final
  /// app state.
  public var candidateOutput: Output? {
    candidate?.output
  }
}

extension StructuredGenerationPipelineResult: Equatable where Output: Equatable {}

public struct StructuredGenerationPipeline<Output: Sendable>: Sendable {
  public var errorToFallbackReason: @Sendable (any Error) -> FallbackReason
  public var fallbackPolicy: StructuredGenerationFallbackPolicy<Output>
  public var generate: @Sendable (CompiledPrompt) async throws -> GenerationCandidate<Output>
  public var repairPolicy: StructuredGenerationRepairPolicy<Output>
  public var validator: StructuredGenerationValidator<Output>

  public init(
    generate: @escaping @Sendable (CompiledPrompt) async throws -> GenerationCandidate<Output>,
    validator: StructuredGenerationValidator<Output> = .acceptAll,
    repairPolicy: StructuredGenerationRepairPolicy<Output> = .none,
    fallbackPolicy: StructuredGenerationFallbackPolicy<Output> = .none,
    errorToFallbackReason: @escaping @Sendable (any Error) -> FallbackReason = { error in
      if let error = error as? any LLMFallbackClassifiableError {
        return error.fallbackReason
      }
      if let error = error as? LLMError {
        return .providerError(error.message)
      }
      return .providerError(error.localizedDescription)
    }
  ) {
    self.errorToFallbackReason = errorToFallbackReason
    self.fallbackPolicy = fallbackPolicy
    self.generate = generate
    self.repairPolicy = repairPolicy
    self.validator = validator
  }

  /// Generates, validates, and resolves fallbacks. Every generation error becomes a result status
  /// except task cancellation, which is rethrown so callers never persist a fallback for a
  /// request the user abandoned.
  public func run(
    prompt: CompiledPrompt,
    context: StructuredGenerationSourceContext = StructuredGenerationSourceContext(),
    evidence: @Sendable (Output) -> [EvidenceSpan] = { _ in [] },
    rawOutputDescription: @Sendable (Output) -> String? = { output in String(describing: output) }
  ) async throws -> StructuredGenerationPipelineResult<Output> {
    do {
      let generated = try await generate(prompt)
      let candidate = StructuredGenerationCandidate(
        generationCandidate: generated,
        evidence: evidence(generated.output),
        rawOutputDescription: rawOutputDescription(generated.output)
      )
      let validation = validator(candidate, in: context)

      guard validation.isAccepted else {
        let repairPlan = repairPolicy.plan(candidate, validation, .validationFailed)
        if let fallbackOutput = fallbackPolicy.resolve(.validationFailed, candidate, validation) {
          return StructuredGenerationPipelineResult(
            status: .fellBack,
            candidate: candidate,
            validation: validation,
            repairPlan: repairPlan,
            fallbackDecision: FallbackDecision(output: fallbackOutput, reason: .validationFailed)
          )
        }

        return StructuredGenerationPipelineResult(
          status: .rejected,
          candidate: candidate,
          validation: validation,
          repairPlan: repairPlan
        )
      }

      return StructuredGenerationPipelineResult(
        status: .accepted,
        candidate: candidate,
        validation: validation
      )
    } catch let error as CancellationError {
      throw error
    } catch {
      try Task.checkCancellation()
      let fallbackReason = errorToFallbackReason(error)
      let validation = StructuredGenerationValidationResult(
        issues: [
          ValidationIssue(
            id: "generation-failed",
            message: error.localizedDescription,
            severity: .error
          )
        ]
      )
      let repairPlan = repairPolicy.plan(nil, validation, fallbackReason)
      if let fallbackOutput = fallbackPolicy.resolve(fallbackReason, nil, validation) {
        return StructuredGenerationPipelineResult(
          status: .fellBack,
          validation: validation,
          repairPlan: repairPlan,
          fallbackDecision: FallbackDecision(output: fallbackOutput, reason: fallbackReason),
          errorMessage: error.localizedDescription
        )
      }

      return StructuredGenerationPipelineResult(
        status: .failed,
        validation: validation,
        repairPlan: repairPlan,
        errorMessage: error.localizedDescription
      )
    }
  }
}
