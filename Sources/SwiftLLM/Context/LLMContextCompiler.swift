import Foundation

public struct LLMContextCompilationInput: Sendable {
  public var additionalItems: [LLMContextItem]
  public var contract: PromptContract
  public var examples: [PromptExample]
  public var includeGeneratedSchemaInPrompt: Bool
  public var includeRetrievedContextInPrompt: Bool
  public var metadata: LLMProviderMetadata
  public var prewarmPromptPrefix: String?
  public var retrievedSnippets: [RetrievedSnippet]
  public var schemaSurface: LLMContextSurface
  public var sessionPolicy: LLMSessionPolicy
  public var toolExecutionPolicy: LLMToolExecutionPolicy?
  public var tools: [LLMToolDefinition]
  public var userPrompt: String

  public init(
    contract: PromptContract,
    metadata: LLMProviderMetadata,
    userPrompt: String,
    examples: [PromptExample] = [],
    retrievedSnippets: [RetrievedSnippet] = [],
    tools: [LLMToolDefinition] = [],
    sessionPolicy: LLMSessionPolicy = .statelessPerRequest,
    toolExecutionPolicy: LLMToolExecutionPolicy? = nil,
    schemaSurface: LLMContextSurface = .instructions,
    includeGeneratedSchemaInPrompt: Bool = true,
    includeRetrievedContextInPrompt: Bool = true,
    prewarmPromptPrefix: String? = nil,
    additionalItems: [LLMContextItem] = []
  ) {
    self.additionalItems = additionalItems
    self.contract = contract
    self.examples = examples
    self.includeGeneratedSchemaInPrompt = includeGeneratedSchemaInPrompt
    self.includeRetrievedContextInPrompt = includeRetrievedContextInPrompt
    self.metadata = metadata
    self.prewarmPromptPrefix = prewarmPromptPrefix
    self.retrievedSnippets = retrievedSnippets
    self.schemaSurface = schemaSurface
    self.sessionPolicy = sessionPolicy
    self.toolExecutionPolicy = toolExecutionPolicy
    self.tools = tools
    self.userPrompt = userPrompt
  }
}

public struct LLMContextCompilationResult: Sendable {
  public var budgetReport: LLMContextBudgetReport
  public var citations: [SnippetCitation]
  public var compiledPrompt: CompiledPrompt
  public var contextBlock: String
  public var droppedSnippets: [RetrievedSnippet]
  public var fixedInputTokens: Int
  public var packedSnippets: [RetrievedSnippet]
  public var plan: LLMContextPlan

  public init(
    compiledPrompt: CompiledPrompt,
    plan: LLMContextPlan,
    packedSnippets: [RetrievedSnippet],
    droppedSnippets: [RetrievedSnippet],
    contextBlock: String,
    citations: [SnippetCitation],
    fixedInputTokens: Int,
    budgetReport: LLMContextBudgetReport
  ) {
    self.budgetReport = budgetReport
    self.citations = citations
    self.compiledPrompt = compiledPrompt
    self.contextBlock = contextBlock
    self.droppedSnippets = droppedSnippets
    self.fixedInputTokens = fixedInputTokens
    self.packedSnippets = packedSnippets
    self.plan = plan
  }

  public var sourceContext: StructuredGenerationSourceContext {
    StructuredGenerationSourceContext(
      sources: packedSnippets.map(\.evidenceSource)
    )
  }
}

public struct LLMContextCompiler: Sendable {
  public var additionalReservedInputTokens: Int
  public var budget: TokenBudget
  public var counter: TokenCounter
  public var packingStrategy: ContextPackingStrategy
  public var renderer: CitationContextRenderer

  public init(
    budget: TokenBudget = TokenBudget(),
    counter: TokenCounter = .latinHeuristic,
    packingStrategy: ContextPackingStrategy = .scoreDescending,
    renderer: CitationContextRenderer = CitationContextRenderer(),
    additionalReservedInputTokens: Int = 0
  ) {
    self.additionalReservedInputTokens = max(0, additionalReservedInputTokens)
    self.budget = budget
    self.counter = counter
    self.packingStrategy = packingStrategy
    self.renderer = renderer
  }

  public func compile(_ input: LLMContextCompilationInput) -> LLMContextCompilationResult {
    let fixedItems = makeFixedItems(input)
    let fixedInputTokens = fixedItems.reduce(0) { $0 + $1.tokenCount(using: counter) } +
      input.tools.reduce(0) { $0 + $1.estimatedDefinitionTokens(using: counter) }

    let packedSnippets = ContextPacker(
      budget: budget,
      strategy: packingStrategy
    )
    .pack(
      snippets: input.retrievedSnippets,
      reservedInputTokens: fixedInputTokens + additionalReservedInputTokens
    )
    let packedIDs = Set(packedSnippets.map(\.id))
    let droppedSnippets = input.retrievedSnippets.filter { !packedIDs.contains($0.id) }
    let contextBlock = renderer.render(snippets: packedSnippets)
    let citations = renderer.citations(for: packedSnippets)
    let retrievedItems = makeRetrievedItems(
      contextBlock: contextBlock,
      packedSnippets: packedSnippets
    )
    let plan = LLMContextPlan(
      items: fixedItems + retrievedItems,
      sessionPolicy: input.sessionPolicy,
      toolExecutionPolicy: input.toolExecutionPolicy ?? (input.tools.isEmpty ? .noTools : .modelMayCall),
      tools: input.tools,
      includeGeneratedSchemaInPrompt: input.includeGeneratedSchemaInPrompt,
      prewarmPromptPrefix: input.prewarmPromptPrefix
    )
    let compiledPrompt = CompiledPrompt(
      contract: input.contract,
      examples: input.examples,
      contextPlan: plan,
      metadata: input.metadata,
      userPrompt: compiledUserPrompt(
        input.userPrompt,
        contextBlock: contextBlock,
        includeRetrievedContextInPrompt: input.includeRetrievedContextInPrompt
      )
    )

    return LLMContextCompilationResult(
      compiledPrompt: compiledPrompt,
      plan: plan,
      packedSnippets: packedSnippets,
      droppedSnippets: droppedSnippets,
      contextBlock: contextBlock,
      citations: citations,
      fixedInputTokens: fixedInputTokens,
      budgetReport: plan.budgetReport(budget: budget, counter: counter)
    )
  }

  private func makeFixedItems(_ input: LLMContextCompilationInput) -> [LLMContextItem] {
    var items: [LLMContextItem] = []

    if !input.contract.instructions.isEmpty {
      items.append(
        LLMContextItem(
          id: "instructions",
          surface: .instructions,
          text: input.contract.instructions,
          trust: .trustedSystem,
          estimatedTokens: counter.count(input.contract.instructions)
        )
      )
    }

    if !input.contract.responseSchemaDescription.isEmpty {
      items.append(
        LLMContextItem(
          id: "response-schema-description",
          surface: input.schemaSurface,
          text: input.contract.responseSchemaDescription,
          trust: .trustedApp,
          estimatedTokens: counter.count(input.contract.responseSchemaDescription)
        )
      )
    }

    if !input.examples.isEmpty {
      let examples = input.examples.map(\.promptFragment).joined(separator: "\n\n")
      // Examples travel with the instructions, so they are accounted on that surface.
      items.append(
        LLMContextItem(
          id: "examples",
          surface: .instructions,
          text: examples,
          trust: .trustedApp,
          estimatedTokens: counter.count(examples)
        )
      )
    }

    items.append(
      LLMContextItem(
        id: "prompt",
        surface: .prompt,
        text: input.userPrompt,
        trust: .userProvided,
        estimatedTokens: counter.count(input.userPrompt)
      )
    )

    items.append(contentsOf: input.additionalItems)
    return items
  }

  private func makeRetrievedItems(
    contextBlock: String,
    packedSnippets: [RetrievedSnippet]
  ) -> [LLMContextItem] {
    guard !contextBlock.isEmpty else { return [] }

    // Count the rendered block, which includes citation headers, rather than the raw snippets.
    return [
      LLMContextItem(
        id: "retrieved-context",
        surface: .retrievedContext,
        text: contextBlock,
        trust: .trustedApp,
        estimatedTokens: max(counter.count(contextBlock), packedSnippets.reduce(0) { $0 + $1.tokenCount })
      ),
    ]
  }

  private func compiledUserPrompt(
    _ userPrompt: String,
    contextBlock: String,
    includeRetrievedContextInPrompt: Bool
  ) -> String {
    guard includeRetrievedContextInPrompt,
          !contextBlock.isEmpty
    else { return userPrompt }

    return """
    User input:
    \(userPrompt)

    Retrieved context:
    \(contextBlock)
    """
  }
}
