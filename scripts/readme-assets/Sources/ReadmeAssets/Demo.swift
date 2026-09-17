import Foundation
import SwiftLM
import SwiftLMAnthropic
import SwiftLMEvaluation
import SwiftLMFoundationModels

/// The offline world behind the README images.
///
/// Model output is scripted, and nothing touches the network. Routing, capability checks, provider
/// request encoding and response decoding, receipts, context compilation, and evaluation are the
/// package's own code. Run IDs, timestamps, and durations are fixed afterward so the images only
/// change when behavior does.
enum Demo {
  static let meetingNote = """
    Kestrel launch sync, September 15. Maya Chen, Luis Ortega, Priya Natarajan, and Sam Okafor \
    attended. The team agreed to ship the Kestrel beta to the first 500 testers on October 6 \
    instead of September 29, because the sync conflict fix needs another week of soak time. \
    Maya owns the release checklist and will circulate it by Friday. Luis will finish the sync \
    conflict fix and hand it to QA by Wednesday. Priya will draft the tester welcome email and \
    share it for review on Thursday. Sam raised that the support rotation has a gap during launch \
    week; the team decided that Luis covers the gap on October 7 and 8. The team also agreed to \
    keep the pricing page unchanged until the beta ends. Open question: whether offline mode ships \
    in the beta or waits for the general release. Priya will ask the three largest design partners \
    and report back at the next sync. Maya noted that the App Store description still mentions \
    the old name and will fix it before the beta build is submitted. Everyone agreed to move the \
    weekly sync to Tuesdays at 10:00 starting next week.
    """

  static let contract = PromptContract(
    id: "meeting-actions",
    version: "2026-09-17",
    instructions: "List each decision and action item. Use only facts from the note.",
    responseSchemaDescription: "JSON: decisions, and actions with an owner and a due date."
  )

  static let runStart = Date(timeIntervalSince1970: 1_789_661_400)  // 2026-09-17 16:10:00 UTC
  static let quotaReset = Date(timeIntervalSince1970: 1_789_689_600)  // 2026-09-18 00:00:00 UTC

  // MARK: - Scripted models

  /// Apple's system models. The on-device model answers every request it receives, and Private
  /// Cloud Compute reports that the person's daily quota is used up.
  static func appleModels() -> FoundationModelClient {
    FoundationModelClient(
      checkAvailability: { _, _ in .available },
      countTokens: { request in TokenCounter.latinHeuristic.count(request.text) },
      prewarm: { _ in },
      respond: { request in
        if request.options.executionTarget == .privateCloudCompute {
          throw FoundationModelFailure(reason: .quotaLimitReached(resetsAt: quotaReset))
        }
        return FoundationModelGenerationResponse(
          content: #"{"decisions": [], "actions": []}"#,
          metadata: FoundationModelDefaults.metadata(executionTarget: .onDevice),
          tokenUsage: LMTokenUsage(estimatedInputTokens: 0, estimatedOutputTokens: 0),
          startedAt: runStart,
          completedAt: runStart
        )
      },
      checkExecutionTargetAvailability: { target, _, _ in
        target == .privateCloudCompute ? .quotaLimitReached(resetsAt: quotaReset) : .available
      }
    )
  }

  /// Anthropic's adapter with a transport that returns a recorded Messages API response.
  static func claude() -> AnthropicClient {
    AnthropicClient(
      apiKey: "offline",
      model: "claude-sonnet-5",
      transport: AnthropicHTTPTransport { _ in
        AnthropicHTTPResponse(statusCode: 200, body: Data(claudeResponse.utf8))
      }
    )
  }

  static let claudeAnswer = """
    {"decisions":["Ship the beta to 500 testers on October 6","Keep the pricing page unchanged \
    until the beta ends","Move the weekly sync to Tuesdays at 10:00"],"actions":[{"owner":"Maya",\
    "task":"Circulate the release checklist","due":"Friday"},{"owner":"Luis","task":"Hand the sync \
    conflict fix to QA","due":"Wednesday"},{"owner":"Priya","task":"Share the tester welcome email",\
    "due":"Thursday"}]}
    """

  static var claudeResponse: String {
    let text = String(decoding: try! JSONEncoder().encode(claudeAnswer), as: UTF8.self)
    return """
      {
        "id": "msg_offline",
        "type": "message",
        "role": "assistant",
        "model": "claude-sonnet-5",
        "content": [
          {"type": "thinking", "thinking": "Three decisions and three owned actions.", "signature": "offline"},
          {"type": "text", "text": \(text)}
        ],
        "stop_reason": "end_turn",
        "usage": {"input_tokens": 431, "output_tokens": 318}
      }
      """
  }

  // MARK: - Routing

  /// The hero run: the same router the README shows, with scripted models.
  static func route() async throws -> LMRunReceipt {
    let apple = appleModels()
    let router = LMRouter(
      primary: AnyLMClient(apple),
      fallbacks: [
        AnyLMClient(apple.targeting(.privateCloudCompute)),
        AnyLMClient(claude()),
      ]
    )
    let run = try await router.respondWithReceipt(
      to: LMRequest(
        instructions: "List the decisions and owners.",
        messages: [.user(meetingNote)],
        responseFormat: .jsonObject,
        parameters: .init(reasoningEffort: .medium)
      )
    )
    guard run.response.text == claudeAnswer else {
      throw DemoError("The routed answer did not come from the scripted Claude response.")
    }
    return stabilized(run.receipt, durations: [0, 184, 2_760])
  }

  /// Replaces the run ID, timestamps, and durations with fixed values. Everything else is what the
  /// router recorded.
  static func stabilized(_ receipt: LMRunReceipt, durations: [Double]) -> LMRunReceipt {
    var receipt = receipt
    receipt.id = "5E0C2D7A-9B41-4F2E-8C6D-3A1B7F904E12"
    receipt.startedAt = runStart
    var clock = runStart
    for (index, attempt) in receipt.attempts.enumerated() {
      let duration = index < durations.count ? durations[index] : 0
      receipt.attempts[index] = LMRunAttemptReceipt(
        id: "\(receipt.id)-attempt-\(index)",
        provider: attempt.provider,
        startedAt: clock,
        completedAt: clock.addingTimeInterval(duration / 1_000),
        status: attempt.status,
        unsupportedCapabilities: attempt.unsupportedCapabilities,
        error: attempt.error,
        tokenUsage: attempt.tokenUsage
      )
      // Dates are whole milliseconds apart, but Date arithmetic is not exact in binary.
      receipt.attempts[index].durationMilliseconds = duration
      clock = clock.addingTimeInterval(duration / 1_000)
    }
    receipt.completedAt = clock
    return receipt
  }

  // MARK: - Context budgets

  struct Source: Sendable {
    var id: String
    var title: String
    var score: Double
    var sentences: [String]
    var targetTokens: Int
  }

  static let sources: [Source] = [
    Source(
      id: "kestrel-checklist",
      title: "Kestrel launch checklist",
      score: 0.94,
      sentences: [
        "The beta build needs a signed privacy manifest and a refreshed App Store description.",
        "QA signs off on sync, offline edits, and account deletion before the build is submitted.",
        "Support gets the known issues list two days before testers receive invitations.",
      ],
      targetTokens: 880
    ),
    Source(
      id: "previous-sync",
      title: "Kestrel sync, September 8",
      score: 0.88,
      sentences: [
        "The sync conflict fix was blocked on a server change that landed on September 11.",
        "Priya proposed a welcome email that explains how to send feedback from the app.",
        "Design partners asked for offline mode before they widen the beta inside their teams.",
      ],
      targetTokens: 760
    ),
    Source(
      id: "beta-feedback",
      title: "Alpha feedback summary",
      score: 0.81,
      sentences: [
        "Alpha testers reported duplicate notes after editing the same note on two devices.",
        "Most testers found sharing easy, and two asked for read-only links.",
        "Crash reports dropped after the September 4 build, with none from sync since.",
      ],
      targetTokens: 700
    ),
    Source(
      id: "support-rotation",
      title: "Support rotation, Q4",
      score: 0.62,
      sentences: [
        "The rotation lists one primary and one backup for each weekday through December.",
        "Swaps are recorded in the rotation document at least two days ahead.",
      ],
      targetTokens: 520
    ),
    Source(
      id: "office-move",
      title: "Office move plan",
      score: 0.38,
      sentences: [
        "The team moves to the fourth floor on October 20, and desks are assigned by project.",
        "Packing crates arrive on October 16.",
      ],
      targetTokens: 460
    ),
  ]

  static func snippets() -> [RetrievedSnippet] {
    sources.map { source in
      var text = ""
      var index = 0
      while TokenCounter.latinHeuristic.count(text) < source.targetTokens {
        text += (text.isEmpty ? "" : " ") + source.sentences[index % source.sentences.count]
        index += 1
      }
      return RetrievedSnippet(
        id: source.id,
        sourceID: source.id,
        text: text,
        tokenCount: TokenCounter.latinHeuristic.count(text),
        score: source.score,
        sourceDisplayName: source.title
      )
    }
  }

  struct BudgetRun {
    var title: String
    var budget: TokenBudget
    var result: LMContextCompilationResult
  }

  /// The same input compiled for the on-device window and for Private Cloud Compute, which also
  /// reserves room for reasoning.
  static func budgets() -> [BudgetRun] {
    let apple = appleModels()
    return [
      budgetRun(title: "On-device model", client: apple, reservedResponseTokens: 600),
      budgetRun(
        title: "Private Cloud Compute",
        client: apple.targeting(.privateCloudCompute),
        reservedResponseTokens: 4_096
      ),
    ]
  }

  private static func budgetRun(
    title: String,
    client: FoundationModelClient,
    reservedResponseTokens: Int
  ) -> BudgetRun {
    let budget = TokenBudget(
      contextLimit: client.capabilities.contextWindowTokens ?? 4_096,
      reservedResponseTokens: reservedResponseTokens
    )
    let result = LMContextCompiler(budget: budget).compile(
      LMContextCompilationInput(
        contract: contract,
        metadata: client.metadata,
        userPrompt: meetingNote,
        retrievedSnippets: snippets()
      )
    )
    return BudgetRun(title: title, budget: budget, result: result)
  }

  // MARK: - Evaluation

  static let evaluationCases = [
    PromptEvaluationCase(
      id: "keeps-owners",
      input: "Maya owns the release checklist and will circulate it by Friday.",
      requiredSubstrings: ["Maya", "Friday"]
    ),
    PromptEvaluationCase(
      id: "no-invented-dates",
      input: "Luis will finish the sync conflict fix soon.",
      forbiddenSubstrings: ["Monday", "Friday"]
    ),
    PromptEvaluationCase(
      id: "stays-short",
      input: meetingNote,
      assertions: [.maximumLength(420)]
    ),
  ]

  /// What each prompt version's scripted model returns for each case.
  static let evaluationOutputs: [String: [String: String]] = [
    "2026-09-02": [
      "keeps-owners": #"{"actions":[{"owner":"Maya","task":"Circulate the release checklist","due":"Friday"}]}"#,
      "no-invented-dates": #"{"actions":[{"owner":"Luis","task":"Finish the sync conflict fix","due":"Monday"}]}"#,
      "stays-short": #"{"decisions":["The team agreed to ship the Kestrel beta to the first 500 testers on October 6 instead of September 29 because the sync conflict fix needs another week of soak time","The team agreed to keep the pricing page unchanged until the beta ends","Everyone agreed to move the weekly sync to Tuesdays at 10:00 starting next week"],"actions":[{"owner":"Maya","task":"Circulate the release checklist","due":"Friday"}]}"#,
    ],
    "2026-09-17": [
      "keeps-owners": #"{"actions":[{"owner":"Maya","task":"Circulate the release checklist","due":"Friday"}]}"#,
      "no-invented-dates": #"{"actions":[{"owner":"Luis","task":"Finish the sync conflict fix","due":null}]}"#,
      "stays-short": claudeAnswer,
    ],
  ]

  /// Runs each prompt version's cases through a client and the package's evaluator.
  static func evaluations() async throws -> [PromptVersionEvaluationReport] {
    var reports: [PromptVersionEvaluationReport] = []
    for version in evaluationOutputs.keys.sorted() {
      var versionContract = contract
      versionContract.version = version
      let outputs = evaluationOutputs[version] ?? [:]
      let client = AnyLMClient.testDouble(promptVersion: version) { request in
        let caseInput = request.messages.last?.content ?? ""
        guard let evaluationCase = evaluationCases.first(where: { $0.input == caseInput }),
              let output = outputs[evaluationCase.id]
        else {
          throw DemoError("No scripted output for \(caseInput.prefix(40)).")
        }
        return output
      }

      let evaluator = PromptEvaluator()
      var results: [PromptEvaluationResult] = []
      for evaluationCase in evaluationCases {
        let prompt = CompiledPrompt(
          contract: versionContract,
          metadata: client.metadata,
          userPrompt: evaluationCase.input
        )
        let response = try await client.respond(to: LMRequest(prompt: prompt))
        results.append(evaluator.evaluate(evaluationCase, output: response.text))
      }
      reports.append(
        PromptVersionEvaluationReport(
          prompt: versionContract,
          results: results,
          createdAt: runStart
        )
      )
    }
    return reports
  }
}

struct DemoError: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}
