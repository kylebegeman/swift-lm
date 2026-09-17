import Foundation

public struct LMContextCompilationInput: Sendable {
  public var additionalItems: [LMContextItem]
  public var contract: PromptContract
  public var examples: [PromptExample]
  public var includeGeneratedSchemaInPrompt: Bool
  public var includeRetrievedContextInPrompt: Bool
  public var metadata: LMProviderMetadata
  public var prewarmPromptPrefix: String?
  public var retrievedSnippets: [RetrievedSnippet]
  public var schemaSurface: LMContextSurface
  public var sessionPolicy: LMSessionPolicy
  public var toolExecutionPolicy: LMToolExecutionPolicy?
  public var tools: [LMToolDefinition]
  public var userPrompt: String

  public init(
    contract: PromptContract,
    metadata: LMProviderMetadata,
    userPrompt: String,
    examples: [PromptExample] = [],
    retrievedSnippets: [RetrievedSnippet] = [],
    tools: [LMToolDefinition] = [],
    sessionPolicy: LMSessionPolicy = .statelessPerRequest,
    toolExecutionPolicy: LMToolExecutionPolicy? = nil,
    schemaSurface: LMContextSurface = .instructions,
    includeGeneratedSchemaInPrompt: Bool = true,
    includeRetrievedContextInPrompt: Bool = true,
    prewarmPromptPrefix: String? = nil,
    additionalItems: [LMContextItem] = []
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

public struct LMContextCompilationResult: Sendable {
  public var budgetReport: LMContextBudgetReport
  public var citations: [SnippetCitation]
  public var compiledPrompt: CompiledPrompt
  public var contextBlock: String
  public var droppedSnippets: [RetrievedSnippet]
  public var fixedInputTokens: Int
  public var packedSnippets: [RetrievedSnippet]
  public var plan: LMContextPlan

  public init(
    compiledPrompt: CompiledPrompt,
    plan: LMContextPlan,
    packedSnippets: [RetrievedSnippet],
    droppedSnippets: [RetrievedSnippet],
    contextBlock: String,
    citations: [SnippetCitation],
    fixedInputTokens: Int,
    budgetReport: LMContextBudgetReport
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

public struct LMContextCompiler: Sendable {
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

  public func compile(_ input: LMContextCompilationInput) -> LMContextCompilationResult {
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
    let plan = LMContextPlan(
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

    return LMContextCompilationResult(
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

  private func makeFixedItems(_ input: LMContextCompilationInput) -> [LMContextItem] {
    var items: [LMContextItem] = []

    if !input.contract.instructions.isEmpty {
      items.append(
        LMContextItem(
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
        LMContextItem(
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
        LMContextItem(
          id: "examples",
          surface: .instructions,
          text: examples,
          trust: .trustedApp,
          estimatedTokens: counter.count(examples)
        )
      )
    }

    items.append(
      LMContextItem(
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
  ) -> [LMContextItem] {
    guard !contextBlock.isEmpty else { return [] }

    // Count the rendered block, which includes citation headers, rather than the raw snippets.
    return [
      LMContextItem(
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
