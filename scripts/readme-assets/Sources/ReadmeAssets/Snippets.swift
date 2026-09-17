import Foundation
import SwiftLM
import SwiftLMAnthropic
import SwiftLMEvaluation
import SwiftLMFoundationModels
import SwiftLMOpenAI

#if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
import FoundationModels
#endif

// Every Swift block in the README is one of the marked regions below, so the README only shows
// code that compiles against the current package. The generator checks that each README block
// matches a region exactly. Lines that start with `//> ` are shown without that prefix and are not
// compiled, which is how a snippet shows its imports; a bare `//>` is a blank line.
//
// These functions exist to be type-checked. Nothing calls them.

enum Snippets {
  static func route(key: String, meetingNote: String) async throws {
    // snippet: route
    //> import SwiftLM
    //> import SwiftLMAnthropic
    //> import SwiftLMFoundationModels
    //>
    let apple = FoundationModelClient.live

    let router = LMRouter(
      primary: AnyLMClient(apple),
      fallbacks: [
        AnyLMClient(apple.targeting(.privateCloudCompute)),
        .anthropic(apiKey: key, model: "claude-sonnet-5"),
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
    // snippet-end
    _ = run
  }

  static func onDevice(noteText: String) async throws {
    // snippet: on-device
    //> import SwiftLM
    //> import SwiftLMFoundationModels
    //>
    let client = FoundationModelClient.live

    guard client.availability().isAvailable else {
      throw LMClientError(reason: .unavailable)
    }

    let response = try await client.respond(
      to: LMRequest(
        instructions: "Summarize the note in one sentence.",
        messages: [.user(noteText)],
        parameters: .init(maxOutputTokens: 120)
      )
    )
    print(response.text)
    // snippet-end
  }

  static func stream(client: LMRouter, request: LMRequest) async throws {
    // snippet: stream
    for try await event in client.stream(to: request) {
      switch event {
      case let .textDelta(text):
        print(text, terminator: "")
      case let .completed(response):
        print("\n", response.tokenUsage?.measuredTotalTokens ?? 0)
      default:
        break
      }
    }
    // snippet-end
  }

  static func privateCloud(documentText: String) async throws {
    // snippet: private-cloud
    let privateCloud = FoundationModelClient.live.targeting(.privateCloudCompute)
    let availability = await privateCloud.availability(for: .privateCloudCompute)
    let profile = await privateCloud.reportedRuntimeProfile()

    if availability.isAvailable, profile.quotaStatus.permitsGeneration {
      let response = try await privateCloud.respond(
        to: LMRequest(
          instructions: "Analyze the document and list the open questions.",
          messages: [.user(documentText)],
          parameters: .init(maxOutputTokens: 800, reasoningEffort: .medium)
        )
      )
      print(response.text, response.tokenUsage?.reasoningTokens ?? 0)
    }
    // snippet-end
  }

  static func session() async throws {
    // snippet: session
    let session = try await FoundationModelSession(instructions: "Help plan the trip.")
    _ = try await session.respond(to: "What should I pack for Lisbon?")
    let followUp = try await session.respond(to: "And for a day trip to Sintra?")
    print(followUp.content)
    // snippet-end
  }

  static func image(receiptPNG: Data, client: AnyLMClient) async throws {
    // snippet: image
    let image = LMImage.data(receiptPNG, mediaType: "image/png")
    let request = LMRequest(messages: [.user("Summarize this receipt.", images: [image])])
    let summary = try await client.respond(to: request)
    // snippet-end
    _ = summary
  }

  #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
  @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
  static func customModel(model: some LanguageModel) async throws {
    // snippet: custom-model
    let local = FoundationModelClient.live(
      model: model,
      executionTarget: .customLocal("kestrel-mlx"),
      contextWindowTokens: 8_192
    )
    let reply = try await local.respond(to: LMRequest(messages: [.user("Draft a reply.")]))
    // snippet-end
    _ = reply
  }
  #endif

  static func registry(key: String, userAllowsCloud: Bool) throws {
    // snippet: registry
    var registry = LMEndpointRegistry()
    registry.register(
      LMEndpoint(id: "on-device", client: AnyLMClient(FoundationModelClient.live))
    )
    registry.register(
      LMEndpoint(
        id: "claude",
        client: .anthropic(apiKey: key, model: "claude-sonnet-5"),
        priority: 10,
        isEnabled: userAllowsCloud
      )
    )

    let router = try registry.router()
    // snippet-end
    _ = router
  }

  static func compile(note: String, found: LocalRAGResult, client: AnyLMClient) async throws {
    // snippet: compile
    let contract = PromptContract(
      id: "meeting-actions",
      version: "2026-09-17",
      instructions: "List each decision and action item. Use only facts from the note.",
      responseSchemaDescription: "JSON: decisions, and actions with an owner and a due date."
    )

    let budget = TokenBudget(
      contextLimit: client.capabilities.contextWindowTokens ?? 4_096,
      reservedResponseTokens: 600
    )

    let compiled = LMContextCompiler(budget: budget).compile(
      LMContextCompilationInput(
        contract: contract,
        metadata: client.metadata,
        userPrompt: note,
        retrievedSnippets: found.packedSnippets
      )
    )

    print(compiled.budgetReport.remainingInputTokens, compiled.droppedSnippets.map(\.id))
    let response = try await client.respond(to: LMRequest(prompt: compiled.compiledPrompt))
    // snippet-end
    _ = response
  }

  static func retrieval(notes: [(id: String, title: String, body: String)]) async throws {
    // snippet: rag
    let documents = notes.map { note in
      RetrievableDocument(id: note.id, text: note.body, displayName: note.title)
    }
    let retriever = KeywordLocalRetriever(documents: documents)
    let rag = LocalRAGPipeline(
      retriever: retriever,
      packer: ContextPacker(budget: TokenBudget(), strategy: .sourceDiverse)
    )

    let found = try await rag.run(query: LocalRetrievalQuery(text: "launch blockers"))
    print(found.contextBlock, found.citations.map(\.marker))
    // snippet-end
  }

  static func structured(note: String, compiled: LMContextCompilationResult, client: AnyLMClient) async throws {
    // snippet: structured
    struct MeetingActions: Codable, Sendable {
      var summary: String
      var owners: [String]
    }

    let pipeline = StructuredGenerationPipeline<MeetingActions>(
      generate: { prompt in
        let request = LMRequest(prompt: prompt, responseFormat: .jsonObject)
        let response = try await client.respond(to: request)
        let data = Data(response.text.utf8)
        let output = try JSONDecoder().decode(MeetingActions.self, from: data)
        return GenerationCandidate(output: output, metadata: response.metadata)
      },
      validator: .all([
        .nonEmptyString(\.summary, path: "summary"),
        .maximumCount(\.owners, maximum: 8, path: "owners"),
        .groundedEvidence(),
      ]),
      repairPolicy: .fallbackOnValidationFailure(),
      fallbackPolicy: .fixed(MeetingActions(summary: "", owners: []))
    )

    let result = try await pipeline.run(
      prompt: compiled.compiledPrompt,
      context: StructuredGenerationSourceContext(sourceText: note),
      evidence: { [EvidenceSpan(id: "summary", text: $0.summary, sourceID: "source")] }
    )
    print(result.status, result.validation.issues.map(\.message))
    // snippet-end
  }

  static func evaluation(contract: PromptContract, client: AnyLMClient, reportURL: URL) async throws {
    // snippet: evaluation
    //> import SwiftLMEvaluation
    //>
    let cases = [
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
    ]

    let evaluator = PromptEvaluator()
    var results: [PromptEvaluationResult] = []
    for evaluationCase in cases {
      let prompt = CompiledPrompt(
        contract: contract,
        metadata: client.metadata,
        userPrompt: evaluationCase.input
      )
      let response = try await client.respond(to: LMRequest(prompt: prompt))
      results.append(evaluator.evaluate(evaluationCase, output: response.text))
    }

    let report = PromptVersionEvaluationReport(prompt: contract, results: results)
    try report.jsonData().write(to: reportURL)
    // snippet-end
  }
}

/// Reads the marked regions of this file.
enum SnippetSource {
  struct Region {
    var name: String
    var code: String
  }

  static let fileURL = URL(fileURLWithPath: #filePath)

  static func regions() throws -> [Region] {
    let lines = try String(contentsOf: fileURL, encoding: .utf8).components(separatedBy: "\n")
    var regions: [Region] = []
    var name: String?
    var body: [String] = []
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("// snippet: ") {
        name = String(trimmed.dropFirst("// snippet: ".count))
        body = []
      } else if trimmed == "// snippet-end", let current = name {
        regions.append(Region(name: current, code: dedent(body)))
        name = nil
      } else if name != nil {
        body.append(line)
      }
    }
    return regions
  }

  /// Removes the shared indentation and turns `//> ` lines into shown code.
  static func dedent(_ lines: [String]) -> String {
    let indentation = lines
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      .map { $0.prefix { $0 == " " }.count }
      .min() ?? 0
    return lines.map { line -> String in
      let stripped = String(line.dropFirst(min(indentation, line.prefix { $0 == " " }.count)))
      if stripped == "//>" { return "" }
      if stripped.hasPrefix("//> ") { return String(stripped.dropFirst(4)) }
      return stripped
    }
    .joined(separator: "\n")
  }
}
