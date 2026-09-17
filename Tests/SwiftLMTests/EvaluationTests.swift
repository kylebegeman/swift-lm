import Foundation
import SwiftLM
import SwiftLMEvaluation
import SwiftLMFoundationModels
import Testing

@Suite("Evaluation and diagnostics")
struct EvaluationTests {
  // MARK: - Validation And Evaluation

  @Test
  func groundingValidatorRejectsUnsupportedOutput() {
    let validator = GroundingValidator()

    #expect(
      validator.isGrounded(
        "Send Jamie the permissions copy",
        in: "I need to send Jamie the permissions copy tomorrow."
      )
    )
    #expect(
      !validator.isGrounded(
        "Book flights to Lisbon",
        in: "I need to send Jamie the permissions copy tomorrow."
      )
    )
  }

  @Test
  func groundingValidatorAcceptsExactShortEvidenceButRejectsEmptyClaims() {
    let validator = GroundingValidator()

    #expect(validator.isGrounded("Q2", in: "The Q2 roadmap is ready for review."))
    #expect(!validator.isGrounded("   ", in: "The Q2 roadmap is ready for review."))
  }

  @Test
  func promptEvaluatorChecksRequiredAndForbiddenText() {
    let evaluator = PromptEvaluator()
    let result = evaluator.evaluate(
      PromptEvaluationCase(
        id: "summary",
        input: "Summarize",
        requiredSubstrings: ["privacy"],
        forbiddenSubstrings: ["uploaded"]
      ),
      output: "The workflow keeps privacy local."
    )

    #expect(result.passed)
  }

  @Test
  func promptEvaluatorRunsTextAssertions() {
    let evaluator = PromptEvaluator()
    let result = evaluator.evaluate(
      PromptEvaluationCase(
        id: "citations",
        input: "Answer with citations.",
        assertions: [
          .contains("[1]"),
          .minimumOccurrences("local", 2),
          .maximumLength(80),
        ]
      ),
      output: "Local retrieval keeps local citations visible. [1]"
    )

    #expect(result.passed)
  }

  @Test
  func structuredOutputEvaluatorReportsTypedIssues() {
    let evaluator = StructuredOutputEvaluator<SampleExtraction>(
      assertions: [
        .nonEmptyString(\.summary, id: "summary-required", path: "summary"),
        .maximumCount(\.tasks, maximum: 2, id: "task-limit", path: "tasks"),
      ]
    )

    let result = evaluator.evaluate(
      caseID: "sample",
      output: SampleExtraction(
        summary: "",
        tasks: ["One", "Two", "Three"]
      )
    )

    #expect(!result.passed)
    #expect(result.issues.map(\.id) == ["summary-required", "task-limit"])
  }

  @Test
  func promptEvaluationReportRedactsOutputsByDefault() throws {
    let prompt = PromptContract(
      id: "review",
      version: "v2",
      instructions: "Extract."
    )
    let report = PromptVersionEvaluationReport(
      prompt: prompt,
      results: [
        PromptEvaluationResult(
          caseID: "case-1",
          output: "Raw local output",
          failures: []
        )
      ],
      metrics: EvaluationRunMetrics(
        estimatedInputTokens: 20,
        estimatedOutputTokens: 8,
        retrievalSnippetCount: 2
      ),
      createdAt: Date(timeIntervalSince1970: 0)
    )

    let json = String(decoding: try report.jsonData(), as: UTF8.self)

    #expect(report.passed)
    #expect(!report.storesRawOutputs)
    #expect(report.caseResults.first?.output == nil)
    #expect(json.contains("\"promptVersion\" : \"v2\""))
    #expect(!json.contains("Raw local output"))
  }

  @Test
  func localDebugBundleAggregatesPromptAndFallbackMatrices() throws {
    let report = PromptVersionEvaluationReport(
      id: "report",
      promptID: "review",
      promptVersion: "v1",
      caseResults: [
        PromptEvaluationResultRecord(
          caseID: "case-1",
          passed: true,
          failures: []
        )
      ],
      createdAt: Date(timeIntervalSince1970: 0)
    )
    let fallbackMatrix = ModelFallbackMatrix(
      entries: [
        ModelFallbackMatrixEntry(
          providerKind: "appleFoundationModels",
          availability: "available",
          passedCaseCount: 1,
          failedCaseCount: 0,
          modelIdentifier: "system"
        )
      ]
    )
    let receipt = LMRunReceipt(
      id: "run",
      request: LMRunRequestSummary(
        contextItemCount: 1,
        estimatedContextTokens: 32,
        messageCount: 1,
        promptID: "review",
        promptVersion: "v1",
        requiredCapabilities: ["instructions"],
        responseFormat: "text",
        toolCount: 0,
        toolResultCount: 0
      ),
      startedAt: Date(timeIntervalSince1970: 0),
      completedAt: Date(timeIntervalSince1970: 1),
      outcome: .succeeded,
      attempts: [
        LMRunAttemptReceipt(
          id: "attempt",
          provider: LMProviderReceiptSnapshot(
            modelIdentifier: "system",
            privacyMode: "localOnly",
            promptVersion: "v1",
            providerDisplayName: "Apple Foundation Models",
            providerKind: "appleFoundationModels"
          ),
          startedAt: Date(timeIntervalSince1970: 0),
          completedAt: Date(timeIntervalSince1970: 1),
          status: .succeeded,
          tokenUsage: LMTokenUsageReceipt(
            estimatedInputTokens: 20,
            estimatedOutputTokens: 8
          )
        ),
      ],
      finalProvider: LMProviderReceiptSnapshot(
        modelIdentifier: "system",
        privacyMode: "localOnly",
        promptVersion: "v1",
        providerDisplayName: "Apple Foundation Models",
        providerKind: "appleFoundationModels"
      ),
      tokenUsage: LMTokenUsageReceipt(
        estimatedInputTokens: 20,
        estimatedOutputTokens: 8
      )
    )
    let metrics = EvaluationRunMetrics(receipt: receipt)
    let bundle = LocalDebugBundle(
      id: "bundle",
      promptReports: [report],
      modelFallbackMatrix: fallbackMatrix,
      runReceipts: [receipt],
      createdAt: Date(timeIntervalSince1970: 0)
    )
    let json = String(decoding: try bundle.jsonData(), as: UTF8.self)

    #expect(bundle.passed)
    #expect(metrics.durationMilliseconds == 1_000)
    #expect(metrics.estimatedInputTokens == 20)
    #expect(bundle.contentPolicy == .redacted)
    #expect(json.contains("\"contentPolicy\" : \"redacted\""))
    #expect(json.contains("\"providerKind\" : \"appleFoundationModels\""))
    #expect(json.contains("\"runReceipts\""))
  }
}
