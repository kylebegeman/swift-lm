import Foundation

public struct LMPromptTask: Sendable {
  public var contract: PromptContract
  public var examples: [PromptExample]
  public var exampleSelector: ExampleSelector
  public var parameters: LMGenerationParameters
  public var responseFormat: LMResponseFormat
  public var retrievalQuery: (@Sendable (String) -> LocalRetrievalQuery?)?
  public var toolChoice: LMToolChoice?
  public var tools: [LMToolDefinition]

  public init(
    contract: PromptContract,
    examples: [PromptExample] = [],
    exampleSelector: ExampleSelector = ExampleSelector(),
    responseFormat: LMResponseFormat = .text,
    tools: [LMToolDefinition] = [],
    toolChoice: LMToolChoice? = nil,
    parameters: LMGenerationParameters = LMGenerationParameters(),
    retrievalQuery: (@Sendable (String) -> LocalRetrievalQuery?)? = nil
  ) {
    self.contract = contract
    self.examples = examples
    self.exampleSelector = exampleSelector
    self.parameters = parameters
    self.responseFormat = responseFormat
    self.retrievalQuery = retrievalQuery
    self.toolChoice = toolChoice
    self.tools = tools
  }
}

public struct LMPipelineResult: Sendable {
  public var compiledPrompt: CompiledPrompt
  public var contextCompilation: LMContextCompilationResult?
  public var ragResult: LocalRAGResult?
  public var request: LMRequest
  public var response: LMResponse

  public init(
    compiledPrompt: CompiledPrompt,
    request: LMRequest,
    response: LMResponse,
    ragResult: LocalRAGResult? = nil,
    contextCompilation: LMContextCompilationResult? = nil
  ) {
    self.compiledPrompt = compiledPrompt
    self.contextCompilation = contextCompilation
    self.ragResult = ragResult
    self.request = request
    self.response = response
  }
}

public struct LMPipeline: Sendable {
  public var client: AnyLMClient
  public var ragPipeline: LocalRAGPipeline?

  public init(
    client: AnyLMClient,
    ragPipeline: LocalRAGPipeline? = nil
  ) {
    self.client = client
    self.ragPipeline = ragPipeline
  }

  public func run(
    task: LMPromptTask,
    input: String
  ) async throws -> LMPipelineResult {
    var metadata = client.metadata
    metadata.promptVersion = task.contract.version

    var ragResult: LocalRAGResult?
    var retrieval: LocalRetrievalResult?
    var retrievalQuery: LocalRetrievalQuery?
    if let query = task.retrievalQuery?(input),
       let ragPipeline
    {
      retrievalQuery = query
      retrieval = try await ragPipeline.retriever.retrieve(query)
    }

    let compiler = LMContextCompiler(
      budget: ragPipeline?.packer.budget ?? TokenBudget(),
      packingStrategy: ragPipeline?.packer.strategy ?? .scoreDescending,
      renderer: ragPipeline?.renderer ?? CitationContextRenderer(),
      additionalReservedInputTokens: ragPipeline?.reservedInputTokens ?? 0
    )
    let contextCompilation = compiler.compile(
      LMContextCompilationInput(
        contract: task.contract,
        metadata: metadata,
        userPrompt: input,
        examples: task.exampleSelector.select(from: task.examples),
        retrievedSnippets: retrieval?.snippets ?? [],
        tools: task.tools
      )
    )
    let compiledPrompt = contextCompilation.compiledPrompt
    if let retrievalQuery,
       let retrieval
    {
      ragResult = LocalRAGResult(
        query: retrievalQuery,
        retrieval: retrieval,
        packedSnippets: contextCompilation.packedSnippets,
        contextBlock: contextCompilation.contextBlock,
        citations: contextCompilation.citations
      )
    }
    let request = LMRequest(
      prompt: compiledPrompt,
      responseFormat: task.responseFormat,
      tools: task.tools,
      toolChoice: task.toolChoice,
      parameters: task.parameters,
      metadata: ragResult.map { ["retrievalSnippetCount": "\($0.packedSnippets.count)"] } ?? [:]
    )
    let response = try await client.respond(to: request)

    return LMPipelineResult(
      compiledPrompt: compiledPrompt,
      request: request,
      response: response,
      ragResult: ragResult,
      contextCompilation: contextCompilation
    )
  }
}
