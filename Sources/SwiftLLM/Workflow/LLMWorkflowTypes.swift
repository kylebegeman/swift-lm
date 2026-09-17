import Foundation

/// Runtime options for a workflow run.
public struct LLMWorkflowOptions: Equatable, Sendable {
  public var captureEvents: Bool
  public var captureIntermediateOutputs: Bool

  public init(
    captureIntermediateOutputs: Bool = false,
    captureEvents: Bool = true
  ) {
    self.captureEvents = captureEvents
    self.captureIntermediateOutputs = captureIntermediateOutputs
  }

  public static let `default` = Self()
}

/// The broad role a step plays in a workflow.
public enum LLMStepKind: Equatable, Sendable {
  case contextPlanning
  case custom(String)
  case deterministic
  case generation
  case repairFallback
  case retrieval
  case validation
}

/// A compact, type-erased representation of an intermediate step output.
public enum LLMWorkflowOutputPayload: Equatable, Sendable {
  case json(JSONValue)
  case redacted(String)
  case references([String])
  case text(String)
}

/// A captured intermediate output. Workflows only keep these when
/// `LLMWorkflowOptions.captureIntermediateOutputs` is enabled.
public struct LLMWorkflowIntermediateOutput: Equatable, Identifiable, Sendable {
  public var id: String
  public var label: String
  public var metadata: [String: String]
  public var payload: LLMWorkflowOutputPayload
  public var stepID: String

  public init(
    id: String,
    stepID: String,
    label: String,
    payload: LLMWorkflowOutputPayload,
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.label = label
    self.metadata = metadata
    self.payload = payload
    self.stepID = stepID
  }
}

public enum LLMWorkflowEventKind: String, Equatable, Sendable {
  case contextPlanned
  case fallbackApplied
  case generationCompleted
  case retrievalCompleted
  case stepFailed
  case stepFinished
  case stepStarted
  case validationCompleted
}

/// The error a workflow throws when a step fails.
///
/// It carries the diagnostics accumulated before the failure, so callers can log events, provider
/// metadata, token usage, and budget reports the same way they would after a successful run.
/// Task cancellation is rethrown as `CancellationError` without wrapping.
public struct LLMWorkflowError: Error, LocalizedError {
  public var context: LLMWorkflowContext
  public var stepID: String?
  public var underlyingError: any Error

  public init(
    underlyingError: any Error,
    stepID: String? = nil,
    context: LLMWorkflowContext
  ) {
    self.context = context
    self.stepID = stepID
    self.underlyingError = underlyingError
  }

  public var errorDescription: String? {
    (underlyingError as? any LocalizedError)?.errorDescription ?? underlyingError.localizedDescription
  }
}

/// A deterministic event emitted by workflow orchestration.
public struct LLMWorkflowEvent: Equatable, Identifiable, Sendable {
  public var fallbackReason: FallbackReason?
  public var kind: LLMWorkflowEventKind
  public var message: String?
  public var metadata: [String: String]
  public var sequence: Int
  public var stepID: String?

  public var id: Int { sequence }

  public init(
    sequence: Int = 0,
    kind: LLMWorkflowEventKind,
    stepID: String? = nil,
    message: String? = nil,
    metadata: [String: String] = [:],
    fallbackReason: FallbackReason? = nil
  ) {
    self.fallbackReason = fallbackReason
    self.kind = kind
    self.message = message
    self.metadata = metadata
    self.sequence = sequence
    self.stepID = stepID
  }
}

public struct LLMWorkflowContextBudgetReport: Equatable, Identifiable, Sendable {
  public var id: String
  public var report: LLMContextBudgetReport
  public var stepID: String

  public init(
    id: String,
    stepID: String,
    report: LLMContextBudgetReport
  ) {
    self.id = id
    self.report = report
    self.stepID = stepID
  }
}

public struct LLMWorkflowBudgetReport: Equatable, Sendable {
  public var contextReports: [LLMWorkflowContextBudgetReport]
  public var tokenUsage: [LLMTokenUsage]

  public init(
    contextReports: [LLMWorkflowContextBudgetReport] = [],
    tokenUsage: [LLMTokenUsage] = []
  ) {
    self.contextReports = contextReports
    self.tokenUsage = tokenUsage
  }

  public var estimatedInputTokens: Int {
    tokenUsage.reduce(0) { $0 + $1.estimatedInputTokens }
  }

  public var estimatedOutputTokens: Int {
    tokenUsage.reduce(0) { $0 + $1.estimatedOutputTokens }
  }

  public var measuredInputTokens: Int? {
    sumMeasured(\.measuredInputTokens)
  }

  public var measuredOutputTokens: Int? {
    sumMeasured(\.measuredOutputTokens)
  }

  public var exceedsContextBudget: Bool {
    contextReports.contains { $0.report.exceedsBudget }
  }

  private func sumMeasured(_ keyPath: KeyPath<LLMTokenUsage, Int?>) -> Int? {
    var total = 0
    for usage in tokenUsage {
      guard let value = usage[keyPath: keyPath] else { return nil }
      total += value
    }
    return total
  }
}

/// Accumulated workflow state that steps can inspect when building prompts,
/// retrieval queries, validators, and fallback output.
public struct LLMWorkflowContext: Sendable {
  public var budget: TokenBudget
  public var budgetReports: [LLMWorkflowContextBudgetReport]
  public var contextPlan: LLMContextPlan?
  public var counter: TokenCounter
  public var events: [LLMWorkflowEvent]
  public var evidence: [EvidenceSpan]
  public var fallbackReason: FallbackReason?
  public var intermediateOutputs: [LLMWorkflowIntermediateOutput]
  public var metadata: [String: String]
  public var options: LLMWorkflowOptions
  public var providerMetadata: [LLMProviderMetadata]
  public var retrievalResults: [LocalRAGResult]
  public var sourceContext: StructuredGenerationSourceContext
  public var sourceReferences: [SourceReference]
  public var tokenUsage: [LLMTokenUsage]
  public var validationIssues: [ValidationIssue]

  public init(
    options: LLMWorkflowOptions = .default,
    budget: TokenBudget = TokenBudget(),
    counter: TokenCounter = .latinHeuristic,
    contextPlan: LLMContextPlan? = nil,
    sourceContext: StructuredGenerationSourceContext = StructuredGenerationSourceContext(),
    metadata: [String: String] = [:],
    events: [LLMWorkflowEvent] = [],
    intermediateOutputs: [LLMWorkflowIntermediateOutput] = [],
    providerMetadata: [LLMProviderMetadata] = [],
    tokenUsage: [LLMTokenUsage] = [],
    budgetReports: [LLMWorkflowContextBudgetReport] = [],
    fallbackReason: FallbackReason? = nil,
    validationIssues: [ValidationIssue] = [],
    evidence: [EvidenceSpan] = [],
    sourceReferences: [SourceReference] = [],
    retrievalResults: [LocalRAGResult] = []
  ) {
    self.budget = budget
    self.budgetReports = budgetReports
    self.contextPlan = contextPlan
    self.counter = counter
    self.events = events
    self.evidence = evidence
    self.fallbackReason = fallbackReason
    self.intermediateOutputs = intermediateOutputs
    self.metadata = metadata
    self.options = options
    self.providerMetadata = providerMetadata
    self.retrievalResults = retrievalResults
    self.sourceContext = sourceContext
    self.sourceReferences = sourceReferences
    self.tokenUsage = tokenUsage
    self.validationIssues = validationIssues
  }
}

/// The final output and diagnostics from a workflow run.
public struct LLMWorkflowResult<Output: Sendable>: Sendable {
  public var budgetReport: LLMWorkflowBudgetReport
  public var contextPlan: LLMContextPlan?
  public var events: [LLMWorkflowEvent]
  public var evidence: [EvidenceSpan]
  public var fallbackReason: FallbackReason?
  public var intermediateOutputs: [LLMWorkflowIntermediateOutput]
  public var output: Output
  public var providerMetadata: [LLMProviderMetadata]
  public var retrievalResults: [LocalRAGResult]
  public var sourceReferences: [SourceReference]
  public var validationIssues: [ValidationIssue]

  public init(
    output: Output,
    intermediateOutputs: [LLMWorkflowIntermediateOutput] = [],
    providerMetadata: [LLMProviderMetadata] = [],
    budgetReport: LLMWorkflowBudgetReport = LLMWorkflowBudgetReport(),
    fallbackReason: FallbackReason? = nil,
    validationIssues: [ValidationIssue] = [],
    evidence: [EvidenceSpan] = [],
    sourceReferences: [SourceReference] = [],
    retrievalResults: [LocalRAGResult] = [],
    contextPlan: LLMContextPlan? = nil,
    events: [LLMWorkflowEvent] = []
  ) {
    self.budgetReport = budgetReport
    self.contextPlan = contextPlan
    self.events = events
    self.evidence = evidence
    self.fallbackReason = fallbackReason
    self.intermediateOutputs = intermediateOutputs
    self.output = output
    self.providerMetadata = providerMetadata
    self.retrievalResults = retrievalResults
    self.sourceReferences = sourceReferences
    self.validationIssues = validationIssues
  }
}

extension LLMWorkflowResult: Equatable where Output: Equatable {}

/// A typed result emitted by one workflow step.
public struct LLMStepResult<Output: Sendable>: Sendable {
  public var budgetReports: [LLMWorkflowContextBudgetReport]
  public var contextPlan: LLMContextPlan?
  public var events: [LLMWorkflowEvent]
  public var evidence: [EvidenceSpan]
  public var fallbackReason: FallbackReason?
  public var intermediateOutput: LLMWorkflowIntermediateOutput?
  public var output: Output
  public var providerMetadata: [LLMProviderMetadata]
  public var retrievalResults: [LocalRAGResult]
  public var sourceContext: StructuredGenerationSourceContext?
  public var sourceReferences: [SourceReference]
  public var tokenUsage: [LLMTokenUsage]
  public var validationIssues: [ValidationIssue]

  public init(
    output: Output,
    events: [LLMWorkflowEvent] = [],
    intermediateOutput: LLMWorkflowIntermediateOutput? = nil,
    providerMetadata: [LLMProviderMetadata] = [],
    tokenUsage: [LLMTokenUsage] = [],
    contextPlan: LLMContextPlan? = nil,
    budgetReports: [LLMWorkflowContextBudgetReport] = [],
    fallbackReason: FallbackReason? = nil,
    validationIssues: [ValidationIssue] = [],
    evidence: [EvidenceSpan] = [],
    sourceReferences: [SourceReference] = [],
    retrievalResults: [LocalRAGResult] = [],
    sourceContext: StructuredGenerationSourceContext? = nil
  ) {
    self.budgetReports = budgetReports
    self.contextPlan = contextPlan
    self.events = events
    self.evidence = evidence
    self.fallbackReason = fallbackReason
    self.intermediateOutput = intermediateOutput
    self.output = output
    self.providerMetadata = providerMetadata
    self.retrievalResults = retrievalResults
    self.sourceContext = sourceContext
    self.sourceReferences = sourceReferences
    self.tokenUsage = tokenUsage
    self.validationIssues = validationIssues
  }
}
