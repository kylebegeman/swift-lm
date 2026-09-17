import Foundation
import SwiftLLM
import SwiftLLMEvaluation
import SwiftLLMFoundationModels
import Testing

@Suite("Context")
struct ContextTests {
  // MARK: - Context

  @Test
  func tokenBudgetReservesResponseAndSafetyMargin() {
    let budget = TokenBudget(
      contextLimit: 4_096,
      reservedResponseTokens: 700,
      safetyMarginTokens: 300
    )

    #expect(budget.availableInputTokens == 3_096)
  }

  @Test
  func textChunkerSplitsLargeInput() {
    let chunker = TextChunker(
      maxTokensPerChunk: 16,
      overlapTokens: 4
    )
    let text = Array(repeating: "Follow up with Jamie tomorrow after the launch review.", count: 8)
      .joined(separator: " ")

    let chunks = chunker.chunks(for: text)

    #expect(chunks.count > 1)
    #expect(chunks.allSatisfy { $0.tokenCount <= 16 })
    #expect(chunks.allSatisfy { !$0.characterRange.isEmpty })
  }

  @Test
  func contextPackerSelectsHighestScoringSnippetsWithinBudget() {
    let packer = ContextPacker(
      budget: TokenBudget(
        contextLimit: 20,
        reservedResponseTokens: 4,
        safetyMarginTokens: 1
      )
    )
    let snippets = [
      RetrievedSnippet(id: "low", sourceID: "a", text: "Low", tokenCount: 4, score: 0.1),
      RetrievedSnippet(id: "high", sourceID: "b", text: "High", tokenCount: 10, score: 0.9),
      RetrievedSnippet(id: "too-large", sourceID: "c", text: "Large", tokenCount: 20, score: 1.0),
    ]

    let packed = packer.pack(snippets: snippets)

    #expect(packed.map(\.id) == ["high", "low"])
  }

  @Test
  func contextPackerCanPreferScoreDensity() {
    let packer = ContextPacker(
      budget: TokenBudget(
        contextLimit: 12,
        reservedResponseTokens: 1,
        safetyMarginTokens: 1
      ),
      strategy: .scoreDensity
    )
    let snippets = [
      RetrievedSnippet(id: "big", sourceID: "a", text: "Big", tokenCount: 10, score: 0.9),
      RetrievedSnippet(id: "dense", sourceID: "b", text: "Dense", tokenCount: 2, score: 0.4),
      RetrievedSnippet(id: "small", sourceID: "c", text: "Small", tokenCount: 2, score: 0.3),
    ]

    let packed = packer.pack(snippets: snippets)

    #expect(packed.map(\.id) == ["dense", "small"])
  }

  @Test
  func contextPackerCanDiversifySources() {
    let packer = ContextPacker(
      budget: TokenBudget(
        contextLimit: 20,
        reservedResponseTokens: 1,
        safetyMarginTokens: 1
      ),
      strategy: .sourceDiverse
    )
    let snippets = [
      RetrievedSnippet(id: "a1", sourceID: "a", text: "A1", tokenCount: 3, score: 0.9),
      RetrievedSnippet(id: "a2", sourceID: "a", text: "A2", tokenCount: 3, score: 0.8),
      RetrievedSnippet(id: "b1", sourceID: "b", text: "B1", tokenCount: 3, score: 0.7),
      RetrievedSnippet(id: "c1", sourceID: "c", text: "C1", tokenCount: 3, score: 0.6),
    ]

    let packed = packer.pack(snippets: snippets)

    #expect(packed.map(\.id) == ["a1", "b1", "c1", "a2"])
  }

  @Test
  func foundationModelContextPlanCapturesSessionSchemaAndToolCosts() {
    let tool = LLMToolDefinition(
      name: "lookup_related_notes",
      description: "Return transcript-only related note snippets.",
      inputSchema: [
        "type": "object",
        "properties": [
          "query": [
            "type": "string",
          ],
        ],
      ]
    )
    let plan = LLMContextPlan.foundationModelExtraction(
      instructions: "Extract grounded review data.",
      userPrompt: "Transcript: I need to email Jamie tomorrow.",
      schemaDescription: "Generate summary, tasks, dates, and decisions.",
      tools: [tool],
      sessionPolicy: .rehydrateTranscript,
      prewarmPromptPrefix: "Transcript:"
    )

    #expect(plan.toolExecutionPolicy == .modelMayCall)
    #expect(plan.requiredCapabilities.isSuperset(of: [
      .guidedGeneration,
      .instructions,
      .prewarm,
      .sessionTranscript,
      .tools,
    ]))
    #expect(plan.budgetReport(budget: TokenBudget(contextLimit: 128, reservedResponseTokens: 16, safetyMarginTokens: 8)).estimatedInputTokens > 0)
  }

  @Test
  func emptyContextPlanDoesNotRequireGuidedGeneration() {
    let plan = LLMContextPlan()

    #expect(plan.requiredCapabilities.isEmpty)
  }

  @Test
  func promptCarriesContextPlanIntoProviderRequestCapabilities() {
    let contextPlan = LLMContextPlan(
      items: [
        LLMContextItem(
          id: "instructions",
          surface: .instructions,
          text: "Use a narrow extraction role.",
          trust: .trustedSystem,
          estimatedTokens: 6
        ),
        LLMContextItem(
          id: "schema",
          surface: .generatedSchema,
          text: "summary/tasks",
          trust: .trustedApp,
          estimatedTokens: 4
        ),
      ],
      sessionPolicy: .statelessPerRequest,
      includeGeneratedSchemaInPrompt: true
    )
    let prompt = CompiledPrompt(
      contract: PromptContract(id: "review", version: "v5", instructions: "Extract."),
      contextPlan: contextPlan,
      metadata: LLMProviderMetadata(
        privacyMode: .localOnly,
        promptVersion: "v5",
        providerDisplayName: "Apple Foundation Models",
        providerKind: .appleFoundationModels
      ),
      userPrompt: "Transcript"
    )
    let request = LLMRequest(prompt: prompt)

    #expect(request.contextPlan == contextPlan)
    #expect(request.requiredCapabilities().contains(.guidedGeneration))
    #expect(request.requiredCapabilities().contains(.instructions))
  }

  @Test
  func contextCompilerReservesFixedTokensBeforePackingRetrieval() {
    let counter = TokenCounter { text in
      text.split(whereSeparator: \.isWhitespace).count
    }
    let compiler = LLMContextCompiler(
      budget: TokenBudget(
        contextLimit: 20,
        reservedResponseTokens: 4,
        safetyMarginTokens: 2
      ),
      counter: counter,
      packingStrategy: .scoreDescending
    )
    let result = compiler.compile(
      LLMContextCompilationInput(
        contract: PromptContract(
          id: "review",
          version: "v1",
          instructions: "Extract tasks",
          responseSchemaDescription: "Return JSON"
        ),
        metadata: LLMProviderMetadata(
          privacyMode: .localOnly,
          promptVersion: "v1",
          providerDisplayName: "Local",
          providerKind: .deterministicLocal
        ),
        userPrompt: "Need private summary",
        retrievedSnippets: [
          RetrievedSnippet(
            id: "required",
            sourceID: "note",
            text: "Required source stays within budget.",
            tokenCount: 6,
            score: 0.2,
            sourceDisplayName: "Required Source",
            isRequired: true
          ),
          RetrievedSnippet(
            id: "high",
            sourceID: "doc",
            text: "High score but too large.",
            tokenCount: 4,
            score: 0.9
          ),
          RetrievedSnippet(
            id: "small",
            sourceID: "memo",
            text: "Small optional.",
            tokenCount: 3,
            score: 0.4
          ),
        ],
        schemaSurface: .generatedSchema
      )
    )

    #expect(result.fixedInputTokens == 7)
    #expect(result.packedSnippets.map(\.id) == ["required"])
    #expect(result.droppedSnippets.map(\.id) == ["high", "small"])
    // 7 fixed tokens plus the rendered citation block, which is larger than the raw snippet.
    #expect(result.budgetReport.estimatedInputTokens == 15)
    #expect(result.plan.requiredCapabilities.contains(.guidedGeneration))
    #expect(result.compiledPrompt.userPrompt.contains("Retrieved context:"))
    #expect(result.compiledPrompt.userPrompt.contains("[1] Required Source"))
    #expect(result.plan.items.map(\.surface).contains(.retrievedContext))
  }
}
