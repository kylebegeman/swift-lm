import Foundation
import SwiftLM
import Testing

@Suite("Workflow orchestration")
struct WorkflowTests {
  @Test
  func successfulWorkflowPreservesPlanRetrievalMetadataAndProvenance() async throws {
    let input = ReviewWorkflowInput(
      transcript: """
        I need to follow up with Jamie tomorrow about the permissions copy.
        We decided to keep local-first extraction as the default.
        """,
      annotations: ["User marked this as a launch follow-up."]
    )
    let generatedDraft = ReviewDraft(
      summary: "Jamie follow-up and local-first extraction decision.",
      tasks: ["Send Jamie the permissions copy"],
      decisions: ["Keep local-first extraction as the default"],
      dates: ["tomorrow"],
      relatedSnippetIDs: ["permissions#0"],
      needsReview: false
    )
    let workflow = makeReviewWorkflow(generatedDraft: generatedDraft)

    let result = try await workflow.run(
      input,
      options: LMWorkflowOptions(captureIntermediateOutputs: true),
      context: workflowContext(for: input)
    )

    #expect(result.output == generatedDraft)
    #expect(result.fallbackReason == nil)
    #expect(result.validationIssues.isEmpty)
    #expect(result.providerMetadata.map(\.providerKind).contains(.testDouble))
    #expect(result.budgetReport.estimatedInputTokens == 128)
    #expect(result.budgetReport.estimatedOutputTokens == 44)
    #expect(result.retrievalResults.first?.packedSnippets.map(\.id) == ["permissions#0"])
    #expect(result.sourceReferences.map(\.id) == ["permissions"])
    #expect(result.evidence.map(\.id).contains("task-0"))
    #expect(result.evidence.map(\.id).contains("retrieved-0"))
    #expect(result.intermediateOutputs.map(\.stepID).contains("detect-hints"))
    #expect(result.intermediateOutputs.map(\.stepID).contains("plan-context"))
    #expect(result.contextPlan?.items.map(\.surface).contains(.retrievedContext) == true)
    #expect(result.contextPlan?.items.first(where: { $0.surface == .prompt })?.text.contains("User marked") == true)
    #expect(result.events.map(\.kind).contains(.retrievalCompleted))
    #expect(result.events.map(\.kind).contains(.validationCompleted))
  }

  @Test
  func validationFailureFallsBackToDeterministicOutput() async throws {
    let input = ReviewWorkflowInput(
      transcript: "I need to follow up with Jamie tomorrow about the permissions copy.",
      annotations: []
    )
    let generatedDraft = ReviewDraft(
      summary: "Travel booking.",
      tasks: ["Book flights to Lisbon"],
      decisions: [],
      dates: [],
      relatedSnippetIDs: [],
      needsReview: false
    )
    let fallbackDraft = ReviewDraft(
      summary: "Deterministic fallback from transcript hints.",
      tasks: ["follow up with Jamie tomorrow"],
      decisions: [],
      dates: ["tomorrow"],
      relatedSnippetIDs: [],
      needsReview: true
    )
    let workflow = makeReviewWorkflow(
      generatedDraft: generatedDraft,
      fallbackDraft: fallbackDraft,
      evidence: { _, _ in
        [
          EvidenceSpan(
            id: "task-0",
            text: "Book flights to Lisbon",
            sourceID: "transcript"
          )
        ]
      }
    )

    let result = try await workflow.run(input, context: workflowContext(for: input))

    #expect(result.output == fallbackDraft)
    #expect(result.fallbackReason == .validationFailed)
    #expect(result.validationIssues.map(\.id) == ["ungrounded-evidence-task-0"])
    #expect(result.providerMetadata.map(\.providerKind).contains(.testDouble))
    #expect(result.events.map(\.kind).contains(.fallbackApplied))
  }

  @Test
  func retrievalContextPackingIsIncludedInContextPlan() async throws {
    let input = ReviewWorkflowInput(
      transcript: "Please follow up with Jamie about permissions tomorrow.",
      annotations: []
    )
    let workflow = makeReviewWorkflow(
      generatedDraft: ReviewDraft(
        summary: "Jamie follow-up.",
        tasks: ["Follow up with Jamie"],
        decisions: [],
        dates: ["tomorrow"],
        relatedSnippetIDs: ["permissions#0"],
        needsReview: false
      )
    )

    let result = try await workflow.run(input, context: workflowContext(for: input))
    let retrievedContext = result.contextPlan?.items.first {
      $0.surface == .retrievedContext
    }

    #expect(retrievedContext?.text.contains("Permissions note") == true)
    #expect(retrievedContext?.text.contains("Jamie owns the permissions copy") == true)
    #expect(result.budgetReport.contextReports.map(\.stepID).contains("retrieve-notes"))
    #expect(result.budgetReport.contextReports.map(\.stepID).contains("plan-context"))
  }

  @Test
  func workflowPropagatesCancellation() async {
    let slowStep: LMStep<Int, Int> = .deterministicTransform(id: "slow") { input, _ in
      try await Task.sleep(for: .seconds(5))
      return input
    }
    let workflow = LMWorkflow(slowStep)
    let task = Task {
      try await workflow.run(1)
    }

    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }
}
