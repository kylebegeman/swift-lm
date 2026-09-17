import Foundation

extension LLMStep where Output == Input {
  /// Run local retrieval and context packing while passing the typed input through.
  public static func localRetrieval(
    id: String,
    pipeline: LocalRAGPipeline,
    query: @escaping @Sendable (
      Input,
      LLMWorkflowContext
    ) async throws -> LocalRetrievalQuery
  ) -> Self {
    Self(id: id, kind: .retrieval) { input, context in
      let result = try await pipeline.run(query: try await query(input, context))
      let contextItem = LLMContextItem(
        id: "\(id)-retrieved-context",
        surface: .retrievedContext,
        text: result.contextBlock,
        trust: .trustedApp,
        estimatedTokens: context.counter.count(result.contextBlock)
      )
      let plan = LLMContextPlan(items: [contextItem])
      let budgetReport = LLMWorkflowContextBudgetReport(
        id: "\(id)-budget",
        stepID: id,
        report: plan.budgetReport(budget: context.budget, counter: context.counter)
      )

      // Packed snippets become grounding sources, not evidence. Evidence is what the model cites.
      return LLMStepResult(
        output: input,
        events: [
          LLMWorkflowEvent(
            kind: .retrievalCompleted,
            stepID: id,
            metadata: [
              "packedSnippetCount": "\(result.packedSnippets.count)",
              "retrievedSnippetCount": "\(result.retrieval.snippets.count)",
            ]
          )
        ],
        intermediateOutput: LLMWorkflowIntermediateOutput(
          id: "\(id)-context",
          stepID: id,
          label: "Retrieved context",
          payload: .references(result.packedSnippets.map(\.id))
        ),
        budgetReports: [budgetReport],
        sourceReferences: result.retrieval.sources,
        retrievalResults: [result],
        sourceContext: result.sourceContext
      )
    }
  }
}

extension LLMStep where Output == CompiledPrompt {
  /// Build a compiled prompt and record its context plan and provider metadata.
  public static func contextPlanning(
    id: String,
    build: @escaping @Sendable (
      Input,
      LLMWorkflowContext
    ) async throws -> CompiledPrompt
  ) -> Self {
    Self(id: id, kind: .contextPlanning) { input, context in
      let prompt = try await build(input, context)
      let budgetReport = prompt.contextPlan.map { plan in
        LLMWorkflowContextBudgetReport(
          id: "\(id)-budget",
          stepID: id,
          report: plan.budgetReport(budget: context.budget, counter: context.counter)
        )
      }

      return LLMStepResult(
        output: prompt,
        events: [
          LLMWorkflowEvent(
            kind: .contextPlanned,
            stepID: id,
            metadata: [
              "contextItemCount": "\(prompt.contextPlan?.items.count ?? 0)",
              "promptID": prompt.contract.id,
              "promptVersion": prompt.contract.version,
            ]
          )
        ],
        intermediateOutput: LLMWorkflowIntermediateOutput(
          id: "\(id)-compiled-prompt",
          stepID: id,
          label: "Compiled prompt",
          payload: .json([
            "contextItemCount": .number(Double(prompt.contextPlan?.items.count ?? 0)),
            "promptID": .string(prompt.contract.id),
            "promptVersion": .string(prompt.contract.version),
          ])
        ),
        providerMetadata: [prompt.metadata],
        contextPlan: prompt.contextPlan,
        budgetReports: budgetReport.map { [$0] } ?? []
      )
    }
  }
}

extension LLMStep {
  /// Run app-supplied generation and wrap the output in a structured candidate.
  public static func modelGeneration<Generated: Sendable>(
    id: String,
    generate: @escaping @Sendable (CompiledPrompt) async throws -> GenerationCandidate<Generated>,
    evidence: @escaping @Sendable (
      Generated,
      LLMWorkflowContext
    ) -> [EvidenceSpan] = { _, _ in [] },
    rawOutputDescription: @escaping @Sendable (Generated) -> String? = {
      String(describing: $0)
    }
  ) -> LLMStep<CompiledPrompt, StructuredGenerationCandidate<Generated>> {
    LLMStep<CompiledPrompt, StructuredGenerationCandidate<Generated>>(
      id: id,
      kind: .generation
    ) { prompt, context in
      let generated = try await generate(prompt)
      let candidate = StructuredGenerationCandidate(
        generationCandidate: generated,
        evidence: evidence(generated.output, context),
        rawOutputDescription: rawOutputDescription(generated.output)
      )

      return LLMStepResult(
        output: candidate,
        events: [
          LLMWorkflowEvent(
            kind: .generationCompleted,
            stepID: id,
            metadata: [
              "provider": candidate.metadata.providerDisplayName,
              "providerKind": candidate.metadata.providerKind.rawValue,
            ]
          )
        ],
        intermediateOutput: LLMWorkflowIntermediateOutput(
          id: "\(id)-candidate",
          stepID: id,
          label: "Generated candidate",
          payload: .redacted("Structured generation candidate")
        ),
        providerMetadata: [candidate.metadata],
        tokenUsage: candidate.tokenUsage.map { [$0] } ?? [],
        evidence: candidate.evidence
      )
    }
  }

  /// Validate a structured generation candidate against the accumulated source context.
  public static func structuredValidation<Generated: Sendable>(
    id: String,
    validator: StructuredGenerationValidator<Generated>,
    sourceContext: @escaping @Sendable (
      StructuredGenerationCandidate<Generated>,
      LLMWorkflowContext
    ) -> StructuredGenerationSourceContext = { _, context in context.sourceContext }
  ) -> LLMStep<
    StructuredGenerationCandidate<Generated>,
    StructuredGenerationPipelineResult<Generated>
  > {
    LLMStep<
      StructuredGenerationCandidate<Generated>,
      StructuredGenerationPipelineResult<Generated>
    >(id: id, kind: .validation) { candidate, context in
      let validation = validator(candidate, in: sourceContext(candidate, context))
      let status: StructuredGenerationPipelineStatus = validation.isAccepted
        ? .accepted
        : .rejected
      let result = StructuredGenerationPipelineResult(
        status: status,
        candidate: candidate,
        validation: validation
      )

      return LLMStepResult(
        output: result,
        events: [
          LLMWorkflowEvent(
            kind: .validationCompleted,
            stepID: id,
            metadata: [
              "accepted": "\(validation.isAccepted)",
              "issueCount": "\(validation.issues.count)",
            ]
          )
        ],
        validationIssues: validation.issues,
        evidence: candidate.evidence
      )
    }
  }

  /// Convert validation/generation pipeline status into final output, using a
  /// deterministic fallback when the supplied policy can resolve one.
  ///
  /// The step throws when validation rejected the candidate and no fallback resolves, so a
  /// contract-violating value never becomes the workflow's final output. Apps that want to show
  /// rejected candidates in review UI should stop at `structuredValidation` and read
  /// `StructuredGenerationPipelineResult.candidateOutput`.
  public static func repairOrFallback<Generated: Sendable>(
    id: String,
    repairPolicy: StructuredGenerationRepairPolicy<Generated> = .none,
    fallbackPolicy: StructuredGenerationFallbackPolicy<Generated> = .none
  ) -> LLMStep<StructuredGenerationPipelineResult<Generated>, Generated> {
    LLMStep<StructuredGenerationPipelineResult<Generated>, Generated>(
      id: id,
      kind: .repairFallback
    ) { result, _ in
      if let output = result.output,
        result.status == .accepted
      {
        return LLMStepResult(output: output)
      }

      if let fallbackDecision = result.fallbackDecision,
        let output = fallbackDecision.output
      {
        return LLMStepResult(
          output: output,
          events: [
            LLMWorkflowEvent(
              kind: .fallbackApplied,
              stepID: id,
              fallbackReason: fallbackDecision.reason
            )
          ],
          fallbackReason: fallbackDecision.reason,
          validationIssues: result.validation.issues
        )
      }

      let reason: FallbackReason = result.status == .failed
        ? .providerError(result.errorMessage ?? "Generation failed.")
        : .validationFailed
      let repairPlan = repairPolicy.plan(result.candidate, result.validation, reason)
      let plannedReason: FallbackReason
      switch repairPlan.action {
      case let .fallback(reason):
        plannedReason = reason
      case .none,
          .retryWithFewerExamples,
          .retryWithMaximumResponseTokens,
          .retryWithShorterContext,
          .retryWithSimplerSchema:
        plannedReason = reason
      }

      if let output = fallbackPolicy.resolve(
        plannedReason,
        result.candidate,
        result.validation
      ) {
        return LLMStepResult(
          output: output,
          events: [
            LLMWorkflowEvent(
              kind: .fallbackApplied,
              stepID: id,
              fallbackReason: plannedReason
            )
          ],
          fallbackReason: plannedReason,
          validationIssues: result.validation.issues,
          evidence: result.candidate?.evidence ?? []
        )
      }

      switch result.status {
      case .rejected:
        throw LLMError(
          "Workflow step \(id) rejected the generated candidate with \(result.validation.issues.count) validation issue(s) and no fallback resolved."
        )
      case .accepted, .failed, .fellBack:
        throw LLMError("Workflow step \(id) could not repair or fall back.")
      }
    }
  }
}
