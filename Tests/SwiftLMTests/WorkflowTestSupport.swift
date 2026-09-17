import Foundation
import SwiftLM
import Testing

func makeReviewWorkflow(
  generatedDraft: ReviewDraft,
  fallbackDraft: ReviewDraft = ReviewDraft(
    summary: "Deterministic fallback from transcript hints.",
    tasks: ["follow up with Jamie tomorrow"],
    decisions: [],
    dates: ["tomorrow"],
    relatedSnippetIDs: [],
    needsReview: true
  ),
  evidence: @escaping @Sendable (
    ReviewDraft,
    LMWorkflowContext
  ) -> [EvidenceSpan] = defaultReviewEvidence
) -> LMWorkflow<ReviewWorkflowInput, ReviewDraft> {
  let detectHints: LMStep<ReviewWorkflowInput, ReviewWorkflowState> =
    .deterministicTransform(
      id: "detect-hints",
      captureIntermediateOutput: { state in
        LMWorkflowIntermediateOutput(
          id: "detect-hints-output",
          stepID: "detect-hints",
          label: "Deterministic hints",
          payload: .json([
            "dateHintCount": .number(Double(state.hints.dateHints.count)),
            "decisionHintCount": .number(Double(state.hints.decisionHints.count)),
            "taskHintCount": .number(Double(state.hints.taskHints.count)),
          ])
        )
      }
    ) { input, _ in
      ReviewWorkflowState(
        input: input,
        hints: TranscriptHints(transcript: input.transcript)
      )
    }

  let retrievalPipeline = LocalRAGPipeline(
    retriever: KeywordLocalRetriever(
      documents: [
        RetrievableDocument(
          id: "permissions",
          text: "Jamie owns the permissions copy. Local extraction should cite this related note.",
          displayName: "Permissions note",
          kind: "note"
        ),
      ],
      maxTokensPerSnippet: 48
    ),
    packer: ContextPacker(
      budget: TokenBudget(
        contextLimit: 256,
        reservedResponseTokens: 64,
        safetyMarginTokens: 16
      ),
      strategy: .sourceDiverse
    )
  )
  let retrieveNotes: LMStep<ReviewWorkflowState, ReviewWorkflowState> =
    .localRetrieval(id: "retrieve-notes", pipeline: retrievalPipeline) { state, _ in
      LocalRetrievalQuery(
        text: ([state.input.transcript] + state.hints.taskHints).joined(separator: " "),
        maxResults: 3
      )
    }

  let planContext: LMStep<ReviewWorkflowState, CompiledPrompt> =
    .contextPlanning(id: "plan-context") { state, context in
      let contract = PromptContract(
        id: "review-draft",
        version: "workflow-v1",
        instructions: "Extract only grounded summary, tasks, dates, and decisions.",
        responseSchemaDescription: "Return compact structured review data with evidence."
      )
      let examples = ExampleSelector(limit: 1, preferredTags: ["task"]).select(
        from: [
          PromptExample(
            id: "task-example",
            input: "I need to email Jamie tomorrow.",
            output: #"{"tasks":["email Jamie"],"dates":["tomorrow"]}"#,
            tags: ["task"]
          ),
          PromptExample(
            id: "decision-example",
            input: "We decided to ship local first.",
            output: #"{"decisions":["ship local first"]}"#,
            tags: ["decision"]
          ),
        ]
      )
      let retrievedContext = context.retrievalResults.last?.contextBlock ?? ""
      let userPrompt = """
        Transcript:
        \(state.input.transcript)

        Annotations:
        \(state.input.annotations.joined(separator: "\n"))

        Deterministic hints:
        tasks=\(state.hints.taskHints)
        decisions=\(state.hints.decisionHints)
        dates=\(state.hints.dateHints)
        """
      let plan = LMContextPlan(
        items: [
          LMContextItem(
            id: "instructions",
            surface: .instructions,
            text: contract.instructions,
            trust: .trustedSystem
          ),
          LMContextItem(
            id: "prompt",
            surface: .prompt,
            text: userPrompt,
            trust: .userProvided
          ),
          LMContextItem(
            id: "schema",
            surface: .generatedSchema,
            text: contract.responseSchemaDescription,
            trust: .trustedApp
          ),
          LMContextItem(
            id: "deterministic-hints",
            surface: .prompt,
            text: state.hints.promptFragment,
            trust: .trustedApp
          ),
          LMContextItem(
            id: "retrieved-notes",
            surface: .retrievedContext,
            text: retrievedContext,
            trust: .trustedApp,
            estimatedTokens: context.counter.count(retrievedContext)
          ),
        ],
        sessionPolicy: .statelessPerRequest,
        toolExecutionPolicy: .appPrefetches
      )

      return CompiledPrompt(
        contract: contract,
        examples: examples,
        contextPlan: plan,
        metadata: reviewMetadata,
        userPrompt: userPrompt
      )
    }

  let generateDraft:
    LMStep<CompiledPrompt, StructuredGenerationCandidate<ReviewDraft>> =
      .modelGeneration(
        id: "generate-draft",
        generate: { prompt in
          GenerationCandidate(
            output: generatedDraft,
            metadata: prompt.metadata,
            tokenUsage: LMTokenUsage(
              estimatedInputTokens: 128,
              estimatedOutputTokens: 44,
              measuredInputTokens: 121,
              measuredOutputTokens: 38
            )
          )
        },
        evidence: evidence
      )

  let validateDraft:
    LMStep<
      StructuredGenerationCandidate<ReviewDraft>,
      StructuredGenerationPipelineResult<ReviewDraft>
    > = .structuredValidation(
      id: "validate-grounding",
      validator: .groundedEvidence()
    )

  let fallback:
    LMStep<StructuredGenerationPipelineResult<ReviewDraft>, ReviewDraft> =
      .repairOrFallback(
        id: "repair-or-fallback",
        repairPolicy: .fallbackOnValidationFailure(notes: "Use deterministic hints."),
        fallbackPolicy: .fixed(fallbackDraft)
      )

  return LMWorkflow(detectHints)
    .then(retrieveNotes)
    .then(planContext)
    .then(generateDraft)
    .then(validateDraft)
    .then(fallback)
}

func workflowContext(for input: ReviewWorkflowInput) -> LMWorkflowContext {
  LMWorkflowContext(
    budget: TokenBudget(
      contextLimit: 256,
      reservedResponseTokens: 64,
      safetyMarginTokens: 16
    ),
    sourceContext: StructuredGenerationSourceContext(
      sources: [
        EvidenceSource(
          id: "transcript",
          text: input.transcript,
          displayName: "Transcript",
          kind: "transcript"
        )
      ]
    )
  )
}

let reviewMetadata = LMProviderMetadata(
  modelIdentifier: "fake-structured-generator",
  privacyMode: .localOnly,
  promptVersion: "workflow-v1",
  providerDisplayName: "Fake Structured Generator",
  providerKind: .testDouble
)

func defaultReviewEvidence(
  _ draft: ReviewDraft,
  _ context: LMWorkflowContext
) -> [EvidenceSpan] {
  [
    EvidenceSpan(
      id: "task-0",
      text: "follow up with Jamie tomorrow",
      sourceID: "transcript"
    ),
    EvidenceSpan(
      id: "decision-0",
      text: "decided to keep local-first extraction",
      sourceID: "transcript"
    ),
    EvidenceSpan(
      id: "retrieved-0",
      text: "Jamie owns the permissions copy",
      sourceID: context.retrievalResults.first?.packedSnippets.first?.id
    ),
  ]
}

struct ReviewWorkflowInput: Equatable, Sendable {
  var transcript: String
  var annotations: [String]
}

struct ReviewWorkflowState: Equatable, Sendable {
  var input: ReviewWorkflowInput
  var hints: TranscriptHints
}

struct TranscriptHints: Equatable, Sendable {
  var dateHints: [String]
  var decisionHints: [String]
  var taskHints: [String]

  init(transcript: String) {
    let lowercased = transcript.lowercased()
    self.dateHints = lowercased.contains("tomorrow") ? ["tomorrow"] : []
    self.decisionHints = lowercased.contains("decided")
      ? ["decided to keep local-first extraction"]
      : []
    self.taskHints = lowercased.contains("follow up")
      ? ["follow up with Jamie tomorrow"]
      : []
  }

  var promptFragment: String {
    """
    Task hints: \(taskHints.joined(separator: ", "))
    Decision hints: \(decisionHints.joined(separator: ", "))
    Date hints: \(dateHints.joined(separator: ", "))
    """
  }
}

struct ReviewDraft: Equatable, Sendable {
  var summary: String
  var tasks: [String]
  var decisions: [String]
  var dates: [String]
  var relatedSnippetIDs: [String]
  var needsReview: Bool
}
