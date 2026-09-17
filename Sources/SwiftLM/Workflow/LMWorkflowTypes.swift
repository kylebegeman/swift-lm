import Foundation

/// Runtime options for a workflow run.
public struct LMWorkflowOptions: Equatable, Sendable {
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
public enum LMStepKind: Equatable, Sendable {
  case contextPlanning
  case custom(String)
  case deterministic
  case generation
  case repairFallback
  case retrieval
  case validation
}

/// A compact, type-erased representation of an intermediate step output.
public enum LMWorkflowOutputPayload: Equatable, Sendable {
  case json(JSONValue)
  case redacted(String)
  case references([String])
  case text(String)
}

/// A captured intermediate output. Workflows only keep these when
/// `LMWorkflowOptions.captureIntermediateOutputs` is enabled.
public struct LMWorkflowIntermediateOutput: Equatable, Identifiable, Sendable {
  public var id: String
  public var label: String
  public var metadata: [String: String]
  public var payload: LMWorkflowOutputPayload
  public var stepID: String

  public init(
    id: String,
    stepID: String,
    label: String,
    payload: LMWorkflowOutputPayload,
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.label = label
    self.metadata = metadata
    self.payload = payload
    self.stepID = stepID
  }
}

public enum LMWorkflowEventKind: String, Equatable, Sendable {
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
public struct LMWorkflowError: Error, LocalizedError {
  public var context: LMWorkflowContext
  public var stepID: String?
  public var underlyingError: any Error

  public init(
    underlyingError: any Error,
    stepID: String? = nil,
    context: LMWorkflowContext
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
public struct LMWorkflowEvent: Equatable, Identifiable, Sendable {
  public var fallbackReason: FallbackReason?
  public var kind: LMWorkflowEventKind
  public var message: String?
  public var metadata: [String: String]
  public var sequence: Int
  public var stepID: String?

  public var id: Int { sequence }

  public init(
    sequence: Int = 0,
    kind: LMWorkflowEventKind,
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

public struct LMWorkflowContextBudgetReport: Equatable, Identifiable, Sendable {
  public var id: String
  public var report: LMContextBudgetReport
  public var stepID: String

  public init(
    id: String,
    stepID: String,
    report: LMContextBudgetReport
  ) {
    self.id = id
    self.report = report
    self.stepID = stepID
  }
}

public struct LMWorkflowBudgetReport: Equatable, Sendable {
  public var contextReports: [LMWorkflowContextBudgetReport]
  public var tokenUsage: [LMTokenUsage]

  public init(
    contextReports: [LMWorkflowContextBudgetReport] = [],
    tokenUsage: [LMTokenUsage] = []
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

  private func sumMeasured(_ keyPath: KeyPath<LMTokenUsage, Int?>) -> Int? {
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
public struct LMWorkflowContext: Sendable {
  public var budget: TokenBudget
  public var budgetReports: [LMWorkflowContextBudgetReport]
  public var contextPlan: LMContextPlan?
  public var counter: TokenCounter
  public var events: [LMWorkflowEvent]
  public var evidence: [EvidenceSpan]
  public var fallbackReason: FallbackReason?
  public var intermediateOutputs: [LMWorkflowIntermediateOutput]
  public var metadata: [String: String]
  public var options: LMWorkflowOptions
  public var providerMetadata: [LMProviderMetadata]
  public var retrievalResults: [LocalRAGResult]
  public var sourceContext: StructuredGenerationSourceContext
  public var sourceReferences: [SourceReference]
  public var tokenUsage: [LMTokenUsage]
  public var validationIssues: [ValidationIssue]

  public init(
    options: LMWorkflowOptions = .default,
    budget: TokenBudget = TokenBudget(),
    counter: TokenCounter = .latinHeuristic,
    contextPlan: LMContextPlan? = nil,
    sourceContext: StructuredGenerationSourceContext = StructuredGenerationSourceContext(),
    metadata: [String: String] = [:],
    events: [LMWorkflowEvent] = [],
    intermediateOutputs: [LMWorkflowIntermediateOutput] = [],
    providerMetadata: [LMProviderMetadata] = [],
    tokenUsage: [LMTokenUsage] = [],
    budgetReports: [LMWorkflowContextBudgetReport] = [],
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
public struct LMWorkflowResult<Output: Sendable>: Sendable {
  public var budgetReport: LMWorkflowBudgetReport
  public var contextPlan: LMContextPlan?
  public var events: [LMWorkflowEvent]
  public var evidence: [EvidenceSpan]
  public var fallbackReason: FallbackReason?
  public var intermediateOutputs: [LMWorkflowIntermediateOutput]
  public var output: Output
  public var providerMetadata: [LMProviderMetadata]
  public var retrievalResults: [LocalRAGResult]
  public var sourceReferences: [SourceReference]
  public var validationIssues: [ValidationIssue]

  public init(
    output: Output,
    intermediateOutputs: [LMWorkflowIntermediateOutput] = [],
    providerMetadata: [LMProviderMetadata] = [],
    budgetReport: LMWorkflowBudgetReport = LMWorkflowBudgetReport(),
    fallbackReason: FallbackReason? = nil,
    validationIssues: [ValidationIssue] = [],
    evidence: [EvidenceSpan] = [],
    sourceReferences: [SourceReference] = [],
    retrievalResults: [LocalRAGResult] = [],
    contextPlan: LMContextPlan? = nil,
    events: [LMWorkflowEvent] = []
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

extension LMWorkflowResult: Equatable where Output: Equatable {}

/// A typed result emitted by one workflow step.
public struct LMStepResult<Output: Sendable>: Sendable {
  public var budgetReports: [LMWorkflowContextBudgetReport]
  public var contextPlan: LMContextPlan?
  public var events: [LMWorkflowEvent]
  public var evidence: [EvidenceSpan]
  public var fallbackReason: FallbackReason?
  public var intermediateOutput: LMWorkflowIntermediateOutput?
  public var output: Output
  public var providerMetadata: [LMProviderMetadata]
  public var retrievalResults: [LocalRAGResult]
  public var sourceContext: StructuredGenerationSourceContext?
  public var sourceReferences: [SourceReference]
  public var tokenUsage: [LMTokenUsage]
  public var validationIssues: [ValidationIssue]

  public init(
    output: Output,
    events: [LMWorkflowEvent] = [],
    intermediateOutput: LMWorkflowIntermediateOutput? = nil,
    providerMetadata: [LMProviderMetadata] = [],
    tokenUsage: [LMTokenUsage] = [],
    contextPlan: LMContextPlan? = nil,
    budgetReports: [LMWorkflowContextBudgetReport] = [],
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
