import Foundation
import SwiftLM
import SwiftLMEvaluation
import SwiftLMFoundationModels
import Testing

@Suite("Audit regressions")
struct AuditRegressionTests {
  @Test
  func textChunkerClampsOverlapToHalfOfChunkSize() {
    let chunker = TextChunker(maxTokensPerChunk: 40)
    let text = Array(
      repeating: "Follow up with Jamie tomorrow after the launch review.",
      count: 50
    ).joined(separator: " ")

    let chunks = chunker.chunks(for: text)

    #expect(chunker.overlapTokens == 20)
    #expect(chunks.count < 60)
    #expect(chunks.allSatisfy { $0.tokenCount <= 40 })
  }

  @Test
  func repairOrFallbackThrowsWhenValidationRejectsWithoutFallback() async {
    let step: LMStep<StructuredGenerationPipelineResult<SampleExtraction>, SampleExtraction> =
      .repairOrFallback(id: "repair")
    let candidate = StructuredGenerationCandidate(
      output: SampleExtraction(summary: "", tasks: ["One", "Two", "Three"]),
      metadata: reviewMetadata
    )
    let result = StructuredGenerationPipelineResult(
      status: .rejected,
      candidate: candidate,
      validation: StructuredGenerationValidationResult(
        issues: [ValidationIssue(id: "too-many", message: "Too many tasks.")]
      )
    )

    #expect(result.output == nil)
    #expect(result.candidateOutput?.tasks.count == 3)
    await #expect(throws: LMError.self) {
      _ = try await step.run(result, context: LMWorkflowContext())
    }
  }

  @Test
  func workflowErrorCarriesAccumulatedDiagnostics() async {
    let first: LMStep<Int, Int> = .deterministicTransform(id: "first") { input, _ in input + 1 }
    let failing: LMStep<Int, Int> = .deterministicTransform(id: "failing") { _, _ in
      throw LMClientError(reason: .rateLimited)
    }
    let workflow = LMWorkflow(first).then(failing)

    do {
      _ = try await workflow.run(1)
      Issue.record("Expected the workflow to throw.")
    } catch let error as LMWorkflowError {
      #expect(error.stepID == "failing")
      #expect((error.underlyingError as? LMClientError)?.reason == .rateLimited)
      #expect(error.context.events.map(\.kind).contains(.stepFailed))
      #expect(error.context.events.filter { $0.kind == .stepFinished }.map(\.stepID) == ["first"])
      #expect(error.errorDescription == LMClientError(reason: .rateLimited).errorDescription)
    } catch {
      Issue.record("Expected LMWorkflowError, got \(error).")
    }
  }

  @Test
  func structuredPipelineClassifiesClientErrorsAndRethrowsCancellation() async throws {
    let prompt = CompiledPrompt(
      contract: PromptContract(id: "sample", version: "v1", instructions: "Extract."),
      metadata: reviewMetadata,
      userPrompt: "Input"
    )
    let fallback = SampleExtraction(summary: "fallback", tasks: [])
    let failing = StructuredGenerationPipeline<SampleExtraction>(
      generate: { _ in throw LMClientError(reason: .contextExceeded) },
      fallbackPolicy: .fixed(fallback)
    )

    let result = try await failing.run(prompt: prompt)

    #expect(result.status == .fellBack)
    #expect(result.fallbackDecision?.reason == .contextExceeded)

    let slow = StructuredGenerationPipeline<SampleExtraction>(
      generate: { prompt in
        try await Task.sleep(for: .seconds(5))
        return GenerationCandidate(output: fallback, metadata: prompt.metadata)
      },
      fallbackPolicy: .fixed(fallback)
    )
    let task = Task {
      try await slow.run(prompt: prompt)
    }
    task.cancel()

    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }
  }

  @Test
  func endpointRegistryPrimaryConvenienceKeepsFallbacksExplicit() throws {
    let registry = LMEndpointRegistry(
      endpoints: [
        LMEndpoint(id: "local", client: .testDouble(modelIdentifier: "local") { _ in "local" }, priority: 10),
        LMEndpoint(id: "cloud", client: .testDouble(modelIdentifier: "cloud") { _ in "cloud" }, priority: 20),
      ]
    )

    let localOnly = try registry.router(primaryID: "local")
    let explicit = try registry.router(primaryID: "local", fallbackIDs: ["local", "cloud", "cloud"])
    let optedIn = try registry.router(primaryID: "local", usesRemainingEnabledEndpointsAsFallbacks: true)

    #expect(localOnly.fallbacks.isEmpty)
    #expect(explicit.fallbacks.map(\.metadata.modelIdentifier) == ["cloud"])
    #expect(optedIn.fallbacks.map(\.metadata.modelIdentifier) == ["cloud"])
  }

  @Test
  func localDebugBundleEnforcesRedaction() throws {
    let report = PromptVersionEvaluationReport(
      prompt: PromptContract(id: "review", version: "v1", instructions: "Extract."),
      results: [PromptEvaluationResult(caseID: "case", output: "Raw private output", failures: [])],
      includeOutputs: true
    )
    let redactedBundle = LocalDebugBundle(promptReports: [report])
    let rawBundle = LocalDebugBundle(promptReports: [report], contentPolicy: .includesRawOutputs)
    let json = String(decoding: try redactedBundle.jsonData(), as: UTF8.self)

    #expect(report.storesRawOutputs)
    #expect(redactedBundle.promptReports.first?.storesRawOutputs == false)
    #expect(!json.contains("Raw private output"))
    #expect(rawBundle.promptReports.first?.storesRawOutputs == true)
  }

  @Test
  func keywordRetrieverKeepsRequiredChunksInDocumentOrder() async throws {
    let paragraphs = (0..<12).map { "Paragraph number \($0) of the required note." }
    let retriever = KeywordLocalRetriever(
      documents: [RetrievableDocument(id: "note", text: paragraphs.joined(separator: "\n\n"))],
      maxTokensPerSnippet: 12
    )

    let result = try await retriever.retrieve(
      LocalRetrievalQuery(text: "", maxResults: 11, requiredSourceIDs: ["note"])
    )

    #expect(result.snippets.map(\.id) == (0..<11).map { "note#\($0)" })
  }

  @Test
  func routerStreamEmitsReceipts() async throws {
    let recorder = ReceiptRecorder()
    let failingMetadata = LMProviderMetadata(
      privacyMode: .externalOptIn,
      promptVersion: "v1",
      providerDisplayName: "Primary",
      providerKind: .external
    )
    let router = LMRouter(
      primary: AnyLMClient(metadata: failingMetadata) { _ in
        throw LMClientError(reason: .unavailable)
      },
      fallbacks: [.testDouble { _ in "streamed" }],
      runReceiptHandler: { receipt in
        recorder.record(receipt)
      }
    )

    var events: [LMStreamEvent] = []
    for try await event in router.stream(to: LMRequest(messages: [.user("Stream.")])) {
      events.append(event)
    }
    let receipt = recorder.value()

    #expect(events.completedResponse?.text == "streamed")
    #expect(receipt?.outcome == .succeeded)
    #expect(receipt?.attempts.map(\.status) == [.failed, .succeeded])
    #expect(receipt?.finalProvider?.providerKind == "testDouble")
  }

  @Test
  func routerRequiresReasoningCapabilityForReasoningRequests() async throws {
    let localMetadata = LMProviderMetadata(
      privacyMode: .localOnly,
      promptVersion: "v1",
      providerDisplayName: "Local",
      providerKind: .appleFoundationModels
    )
    let cloudMetadata = LMProviderMetadata(
      privacyMode: .externalOptIn,
      promptVersion: "v1",
      providerDisplayName: "Cloud",
      providerKind: .openAI
    )
    let router = LMRouter(
      primary: AnyLMClient(metadata: localMetadata, capabilities: .foundationModelsProviderNeutral) { _ in
        Issue.record("A client without reasoning support must be skipped.")
        return LMResponse(text: "unexpected", metadata: localMetadata)
      },
      fallbacks: [
        AnyLMClient(metadata: cloudMetadata, capabilities: .openAIResponses) { _ in
          LMResponse(text: "reasoned", metadata: cloudMetadata)
        },
      ]
    )

    let result = try await router.respondWithReceipt(
      to: LMRequest(
        messages: [.user("Think hard.")],
        parameters: LMGenerationParameters(reasoningEffort: .high)
      )
    )

    #expect(result.response.text == "reasoned")
    #expect(result.receipt.attempts.first?.unsupportedCapabilities == ["reasoning"])
  }

  @Test
  func providerContentRoundTripsThroughCodable() throws {
    let message = LMMessage.assistant(
      "Answer",
      toolCalls: [LMToolCall(id: "call", name: "lookup", argumentsJSON: "{}")],
      providerContent: LMProviderContent(providerKind: .anthropic, payload: [["type": "thinking"]])
    )

    let decoded = try JSONDecoder().decode(LMMessage.self, from: try JSONEncoder().encode(message))

    #expect(decoded == message)
  }
}

@Suite("Foundation Models runtime")
struct FoundationModelRuntimeTests {
  @Test
  func executionTargetsDriveProviderNeutralCapabilitiesAndMetadata() async {
    let client = Self.fakeClient()
    let privateCloud = client.targeting(.privateCloudCompute)

    #expect(!client.capabilities.supports(.reasoning))
    #expect(client.capabilities.contextWindowTokens == 4_096)
    #expect(client.metadata.privacyMode == .localOnly)
    #expect(privateCloud.capabilities.supports(.reasoning))
    #expect(privateCloud.capabilities.contextWindowTokens == 32_768)
    #expect(privateCloud.metadata.privacyMode == .privateCloudCompute)
    #expect(privateCloud.metadata.modelIdentifier == "PrivateCloudComputeLanguageModel")
    #expect(await client.availability(for: .privateCloudCompute) == .available)
    #expect(await FoundationModelClient.unavailable.availability(for: .onDevice) == .unavailableInBuild)
    #expect(FoundationModelExecutionTarget.customLocal("mlx").isSupportedByLiveAdapter == false)
  }

  @Test
  func reportedRuntimeProfileDefaultsToTheSynchronousProfileAndCanBeOverridden() async {
    let defaultClient = Self.fakeClient()
    let reportingClient = FoundationModelClient(
      checkAvailability: { _, _ in .available },
      countTokens: { _ in 1 },
      prewarm: { _ in },
      respond: { request in Self.response(for: request) },
      resolveReportedRuntimeProfile: { target, _ in
        FoundationModelRuntimeProfile(
          executionTarget: target,
          contextWindowTokens: 30_000,
          isContextWindowReported: true,
          supportsReasoning: true
        )
      }
    )

    let fallback = await defaultClient.reportedRuntimeProfile(for: .privateCloudCompute)
    let reported = await reportingClient.reportedRuntimeProfile(for: .privateCloudCompute)

    #expect(fallback == defaultClient.runtimeProfile(for: .privateCloudCompute))
    #expect(!fallback.isContextWindowReported)
    #expect(reported.contextWindowTokens == 30_000)
    #expect(reported.isContextWindowReported)
    #expect(reportingClient.runtimeProfile(for: .privateCloudCompute).contextWindowTokens == 32_768)
  }

  @Test
  func onDeviceClientRejectsReasoningButPrivateCloudPassesItThrough() async throws {
    let capture = RequestCapture<FoundationModelGenerationRequest>()
    let client = Self.fakeClient(capture: capture)

    do {
      _ = try await client.respond(
        to: LMRequest(
          messages: [.user("Think.")],
          parameters: LMGenerationParameters(reasoningEffort: .high)
        )
      )
      Issue.record("Expected the on-device client to reject reasoning requests.")
    } catch let error as LMClientError {
      #expect(error.reason == .unsupported)
    }

    let response = try await client.targeting(.privateCloudCompute).respond(
      to: LMRequest(
        messages: [.user("Think.")],
        parameters: LMGenerationParameters(reasoningEffort: .high)
      )
    )
    let captured = await capture.value()

    #expect(response.reasoningText == "Considered options.")
    #expect(response.finishReason == .stop)
    #expect(captured?.options.reasoningEffort == .high)
    #expect(captured?.options.executionTarget == .privateCloudCompute)
  }

  @Test
  func providerNeutralStreamMapsFoundationModelEvents() async throws {
    let client = FoundationModelClient(
      checkAvailability: { _, _ in .available },
      countTokens: { _ in 1 },
      prewarm: { _ in },
      respond: { request in Self.response(for: request) },
      streamResponse: { request in
        AsyncThrowingStream { continuation in
          continuation.yield(.textDelta("Hel"))
          continuation.yield(.textDelta("lo"))
          continuation.yield(.completed(Self.response(for: request)))
          continuation.finish()
        }
      }
    )

    var events: [LMStreamEvent] = []
    for try await event in client.stream(to: LMRequest(messages: [.user("Hi")])) {
      events.append(event)
    }

    #expect(events.textDeltas == ["Hel", "lo"])
    #expect(events.completedResponse?.text == "Hello")
    #expect(events.completedResponse?.reasoningText == "Considered options.")
    #expect(events.completedResponse?.tokenUsage?.reasoningTokens == 3)
    #expect(events.contains { if case .usage = $0 { return true } else { return false } })
  }

  @Test
  func quotaAvailabilityAndFailureMappingsFeedFallbackPolicy() {
    let quotaFailure = FoundationModelFailure(
      reason: .quotaLimitReached(resetsAt: Date(timeIntervalSince1970: 1), limitIncreaseSuggestionAvailable: true)
    )
    let context = LMRouterFallbackContext(
      attemptIndex: 0,
      client: FoundationModelDefaults.metadata(),
      remainingFallbackCount: 1,
      request: LMRequest(messages: [.user("x")])
    )

    #expect(!FoundationModelQuotaStatus.exhausted().permitsGeneration)
    #expect(FoundationModelQuotaStatus.exhausted(limitIncreaseSuggestionAvailable: true).limitIncreaseSuggestionAvailable)
    #expect(FoundationModelQuotaStatus.approachingLimit().permitsGeneration)
    #expect(FoundationModelQuotaStatus.approachingLimit().isApproachingLimit)
    #expect(quotaFailure.fallbackReason == .quotaExceeded)
    #expect(FoundationModelFailure(reason: .timeout).fallbackReason == .timeout)
    #expect(FoundationModelFailure(reason: .networkUnavailable).fallbackReason == .unavailable)
    #expect(FoundationModelFailure(reason: .unsupportedCapability).fallbackReason == .unsupported)
    #expect(FoundationModelAvailability.quotaLimitReached(resetsAt: nil).fallbackReason == .quotaExceeded)
    #expect(
      FoundationModelFailure(reason: .contextExceeded(contextSize: 4_096, tokenCount: 5_000))
        .errorDescription?.contains("5000") == true
    )
    #expect(LMRouterFallbackPolicy.retryable.shouldAttemptFallback(quotaFailure, context))
    #expect(LMRouterFallbackPolicy.retryable.shouldAttemptFallback(FoundationModelFailure(reason: .timeout), context))
  }

  private static func fakeClient(
    capture: RequestCapture<FoundationModelGenerationRequest>? = nil
  ) -> FoundationModelClient {
    FoundationModelClient(
      checkAvailability: { _, _ in .available },
      countTokens: { request in TokenCounter.latinHeuristic.count(request.text) },
      prewarm: { _ in },
      respond: { request in
        await capture?.record(request)
        return response(for: request)
      }
    )
  }

  private static func response(
    for request: FoundationModelGenerationRequest
  ) -> FoundationModelGenerationResponse<String> {
    FoundationModelGenerationResponse(
      content: "Hello",
      metadata: request.prompt.metadata,
      tokenUsage: LMTokenUsage(
        estimatedInputTokens: 2,
        estimatedOutputTokens: 1,
        measuredInputTokens: 2,
        measuredOutputTokens: 1,
        reasoningTokens: 3
      ),
      startedAt: Date(timeIntervalSince1970: 1),
      completedAt: Date(timeIntervalSince1970: 2),
      finishReason: .stop,
      reasoningText: "Considered options."
    )
  }
}

private final class ReceiptRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var receipt: LMRunReceipt?

  func record(_ receipt: LMRunReceipt) {
    lock.withLock { self.receipt = receipt }
  }

  func value() -> LMRunReceipt? {
    lock.withLock { receipt }
  }
}
