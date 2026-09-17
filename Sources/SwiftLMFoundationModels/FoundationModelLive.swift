import Foundation
import SwiftLM

#if canImport(FoundationModels)
import FoundationModels

// MARK: - SDK gate
//
// OS 27 symbols (Private Cloud Compute, `LanguageModelError`, `ContextOptions`, tool calling
// modes, and usage reporting) exist only in the OS 27 SDKs that ship with Xcode 27 and Swift 6.4.
// `compiler(>=6.4)` keeps them out of OS 26 SDK builds, and `#available` checks keep them off
// OS 26 devices at runtime. Define `SWIFTLM_OS26_SDK_ONLY` to build with a Swift 6.4 toolchain
// that still uses an OS 26 SDK.

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
public struct FoundationModelToolConfiguration: Sendable {
  public var tools: [any Tool]

  public init(tools: [any Tool] = []) {
    self.tools = tools
  }

  public static var none: Self {
    Self()
  }

  public var isEmpty: Bool {
    tools.isEmpty
  }

  public var toolNames: [String] {
    tools.map { $0.name }
  }

  public var estimatedDefinitionTokens: Int {
    guard !tools.isEmpty else { return 0 }
    let renderedTools = tools
      .map { "\($0.name)\n\($0.description)" }
      .joined(separator: "\n\n")
    return TokenCounter.latinHeuristic.count(renderedTools)
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension FoundationModelClient {
  public func prewarm(
    _ request: FoundationModelPrewarmRequest,
    tools: [any Tool]
  ) async throws {
    try await foundationModelPrewarm(
      for: request,
      toolConfiguration: FoundationModelToolConfiguration(tools: tools)
    )
  }

  public func respond(
    to request: FoundationModelGenerationRequest,
    tools: [any Tool]
  ) async throws -> FoundationModelGenerationResponse<String> {
    try await foundationModelStringResponse(
      for: request,
      toolConfiguration: FoundationModelToolConfiguration(tools: tools)
    )
  }

  public func respond<Content: Generable & Sendable>(
    generating type: Content.Type,
    request: FoundationModelGenerationRequest,
    tools: [any Tool] = []
  ) async throws -> FoundationModelGenerationResponse<Content> {
    try await foundationModelGeneratedResponse(
      generating: type,
      for: request,
      toolConfiguration: FoundationModelToolConfiguration(tools: tools)
    )
  }

  public func stream(
    _ request: FoundationModelGenerationRequest,
    tools: [any Tool]
  ) -> AsyncThrowingStream<FoundationModelStreamEvent, any Error> {
    foundationModelStream(
      for: request,
      toolConfiguration: FoundationModelToolConfiguration(tools: tools)
    )
  }
}

// MARK: - Availability

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelAvailability(
  locale: Locale?,
  useCase: FoundationModelUseCase
) -> FoundationModelAvailability {
  let model = foundationModel(useCase: useCase)
  let locale = locale ?? .current
  guard model.supportsLocale(locale)
  else { return .unsupportedLocale(locale.identifier) }

  switch model.availability {
  case .available:
    return .available
  case .unavailable(.appleIntelligenceNotEnabled):
    return .appleIntelligenceNotEnabled
  case .unavailable(.deviceNotEligible):
    return .deviceNotEligible
  case .unavailable(.modelNotReady):
    return .modelNotReady
  case .unavailable:
    return .unknown("The local language model is unavailable.")
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelAvailability(
  target: FoundationModelExecutionTarget,
  locale: Locale?,
  useCase: FoundationModelUseCase
) async -> FoundationModelAvailability {
  switch target {
  case .automatic, .onDevice:
    return foundationModelAvailability(locale: locale, useCase: useCase)
  case .privateCloudCompute:
    #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
      return await foundationModelPrivateCloudComputeAvailability(locale: locale)
    }
    #endif
    return .unsupportedOS
  case .providerPackage, .customLocal:
    return .unsupportedExecutionTarget(target.diagnosticName)
  }
}

// MARK: - Runtime profile

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelRuntimeProfile(
  target: FoundationModelExecutionTarget,
  useCase: FoundationModelUseCase
) -> FoundationModelRuntimeProfile {
  switch target {
  case .automatic, .onDevice:
    let model = foundationModel(useCase: useCase)
    var profile = FoundationModelRuntimeProfile(
      executionTarget: .onDevice,
      contextWindowTokens: model.contextSize,
      isContextWindowReported: true,
      quotaStatus: .notApplicable
    )
    #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
      profile.applyCapabilities(model.capabilities)
    }
    #endif
    return profile
  case .privateCloudCompute:
    #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
      let model = PrivateCloudComputeLanguageModel()
      var profile = FoundationModelRuntimeProfile(
        executionTarget: .privateCloudCompute,
        contextWindowTokens: model.contextSize,
        isContextWindowReported: true,
        supportsReasoning: true,
        quotaStatus: FoundationModelQuotaStatus(quotaUsage: model.quotaUsage)
      )
      profile.applyCapabilities(model.capabilities)
      return profile
    }
    #endif
    return .privateCloudCompute
  case .providerPackage, .customLocal:
    return FoundationModelRuntimeProfile(executionTarget: target)
  }
}

// MARK: - Token counting and prewarming

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelTokenCount(
  for request: FoundationModelTokenCountRequest
) async throws -> Int {
  let model = foundationModel(useCase: request.useCase)
  guard #available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
  else { return TokenCounter.latinHeuristic.count(request.text) }

  do {
    return try await model.tokenCount(for: Prompt(request.text))
  } catch {
    throw FoundationModelErrorNormalizer.failure(from: error)
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelPrewarm(
  for request: FoundationModelPrewarmRequest,
  toolConfiguration: FoundationModelToolConfiguration = .none
) async throws {
  let resolved = try await foundationModelResolvedSession(
    target: request.executionTarget,
    useCase: request.useCase,
    tools: toolConfiguration.tools,
    instructions: request.instructions.nilIfEmpty
  )
  resolved.session.prewarm(promptPrefix: request.promptPrefix.map(Prompt.init))
}

// MARK: - Generation

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelStringResponse(
  for request: FoundationModelGenerationRequest,
  toolConfiguration: FoundationModelToolConfiguration = .none
) async throws -> FoundationModelGenerationResponse<String> {
  try await foundationModelResponse(
    for: request,
    toolConfiguration: toolConfiguration
  ) { session, options in
    let response = try await foundationModelRespondText(
      session: session,
      prompt: Prompt(request.prompt.userPrompt),
      options: options,
      request: request
    )
    return (response.content, foundationModelFacts(from: response))
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelGeneratedResponse<Content: Generable & Sendable>(
  generating type: Content.Type,
  for request: FoundationModelGenerationRequest,
  toolConfiguration: FoundationModelToolConfiguration = .none
) async throws -> FoundationModelGenerationResponse<Content> {
  try await foundationModelResponse(
    for: request,
    toolConfiguration: toolConfiguration
  ) { session, options in
    let response = try await foundationModelRespondGenerating(
      session: session,
      prompt: Prompt(request.prompt.userPrompt),
      generating: type,
      options: options,
      request: request
    )
    return (response.content, foundationModelFacts(from: response))
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelResponse<Content: Sendable>(
  for request: FoundationModelGenerationRequest,
  toolConfiguration: FoundationModelToolConfiguration,
  perform: (LanguageModelSession, GenerationOptions) async throws -> (Content, FoundationModelResponseFacts)
) async throws -> FoundationModelGenerationResponse<Content> {
  let resolved = try await foundationModelResolvedSession(
    target: request.options.executionTarget,
    useCase: request.useCase,
    tools: toolConfiguration.tools,
    instructions: request.prompt.systemInstructions.nilIfEmpty
  )
  try foundationModelValidate(request.options, against: resolved.profile)
  if let prewarmPromptPrefix = request.prewarmPromptPrefix {
    resolved.session.prewarm(promptPrefix: Prompt(prewarmPromptPrefix))
  }

  let options = try request.options.foundationGenerationOptions()
  let startedAt = Date()
  let estimatedInputTokens = foundationModelEstimatedInputTokens(
    for: request,
    toolConfiguration: toolConfiguration
  )

  do {
    let (content, facts) = try await perform(resolved.session, options)
    let completedAt = Date()
    let renderedOutput = String(describing: content)
    let measuredInputTokens: Int?
    if let measured = facts.measuredInputTokens {
      measuredInputTokens = measured
    } else {
      measuredInputTokens = await foundationModelMeasuredInputTokens(
        model: resolved.systemModel,
        request: request,
        tools: toolConfiguration.tools
      )
    }
    let measuredOutputTokens: Int?
    if let measured = facts.measuredOutputTokens {
      measuredOutputTokens = measured
    } else {
      measuredOutputTokens = await foundationModelMeasuredTokenCount(
        renderedOutput,
        model: resolved.systemModel
      )
    }

    return FoundationModelGenerationResponse(
      content: content,
      metadata: request.prompt.metadata,
      tokenUsage: LMTokenUsage(
        estimatedInputTokens: estimatedInputTokens,
        estimatedOutputTokens: TokenCounter.latinHeuristic.count(renderedOutput),
        measuredInputTokens: measuredInputTokens,
        measuredOutputTokens: measuredOutputTokens,
        cachedInputTokens: facts.cachedInputTokens,
        reasoningTokens: facts.reasoningTokens
      ),
      startedAt: startedAt,
      completedAt: completedAt,
      finishReason: foundationModelFinishReason(
        measuredOutputTokens: measuredOutputTokens,
        maximumResponseTokens: request.options.maximumResponseTokens
      ),
      reasoningText: facts.reasoningText,
      runtimeProfile: resolved.profile
    )
  } catch is CancellationError {
    throw CancellationError()
  } catch {
    throw await foundationModelFailure(from: error)
  }
}

// MARK: - Streaming

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelStream(
  for request: FoundationModelGenerationRequest,
  toolConfiguration: FoundationModelToolConfiguration = .none
) -> AsyncThrowingStream<FoundationModelStreamEvent, any Error> {
  AsyncThrowingStream { continuation in
    let task = Task {
      do {
        let resolved = try await foundationModelResolvedSession(
          target: request.options.executionTarget,
          useCase: request.useCase,
          tools: toolConfiguration.tools,
          instructions: request.prompt.systemInstructions.nilIfEmpty
        )
        try foundationModelValidate(request.options, against: resolved.profile)
        if let prewarmPromptPrefix = request.prewarmPromptPrefix {
          resolved.session.prewarm(promptPrefix: Prompt(prewarmPromptPrefix))
        }

        let options = try request.options.foundationGenerationOptions()
        let startedAt = Date()
        let estimatedInputTokens = foundationModelEstimatedInputTokens(
          for: request,
          toolConfiguration: toolConfiguration
        )
        let stream = foundationModelStreamText(
          session: resolved.session,
          prompt: Prompt(request.prompt.userPrompt),
          options: options,
          request: request
        )

        var emittedText = ""
        var facts = FoundationModelResponseFacts()
        for try await snapshot in stream {
          try Task.checkCancellation()
          let content = snapshot.content
          if content.hasPrefix(emittedText) {
            let delta = String(content.dropFirst(emittedText.count))
            if !delta.isEmpty {
              continuation.yield(.textDelta(delta))
            }
          } else if !content.isEmpty {
            continuation.yield(.textDelta(content))
          }
          emittedText = content
          facts = foundationModelFacts(from: snapshot)
        }

        let completedAt = Date()
        let measuredInputTokens: Int?
        if let measured = facts.measuredInputTokens {
          measuredInputTokens = measured
        } else {
          measuredInputTokens = await foundationModelMeasuredInputTokens(
            model: resolved.systemModel,
            request: request,
            tools: toolConfiguration.tools
          )
        }
        let measuredOutputTokens: Int?
        if let measured = facts.measuredOutputTokens {
          measuredOutputTokens = measured
        } else {
          measuredOutputTokens = await foundationModelMeasuredTokenCount(
            emittedText,
            model: resolved.systemModel
          )
        }

        continuation.yield(
          .completed(
            FoundationModelGenerationResponse(
              content: emittedText,
              metadata: request.prompt.metadata,
              tokenUsage: LMTokenUsage(
                estimatedInputTokens: estimatedInputTokens,
                estimatedOutputTokens: TokenCounter.latinHeuristic.count(emittedText),
                measuredInputTokens: measuredInputTokens,
                measuredOutputTokens: measuredOutputTokens,
                cachedInputTokens: facts.cachedInputTokens,
                reasoningTokens: facts.reasoningTokens
              ),
              startedAt: startedAt,
              completedAt: completedAt,
              finishReason: foundationModelFinishReason(
                measuredOutputTokens: measuredOutputTokens,
                maximumResponseTokens: request.options.maximumResponseTokens
              ),
              reasoningText: facts.reasoningText,
              runtimeProfile: resolved.profile
            )
          )
        )
        continuation.finish()
      } catch is CancellationError {
        continuation.finish(throwing: CancellationError())
      } catch {
        continuation.finish(throwing: await foundationModelFailure(from: error))
      }
    }
    continuation.onTermination = { _ in
      task.cancel()
    }
  }
}

// MARK: - Session resolution

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct FoundationModelResolvedSession: Sendable {
  var profile: FoundationModelRuntimeProfile
  var session: LanguageModelSession
  /// The on-device model, used for exact token counting. `nil` for server models.
  var systemModel: SystemLanguageModel?
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelResolvedSession(
  target: FoundationModelExecutionTarget,
  useCase: FoundationModelUseCase,
  tools: [any Tool],
  instructions: String?
) async throws -> FoundationModelResolvedSession {
  let availability = await foundationModelAvailability(target: target, locale: nil, useCase: useCase)
  guard availability.isAvailable
  else { throw FoundationModelFailure(reason: .unavailable(availability)) }

  let profile = foundationModelRuntimeProfile(target: target, useCase: useCase)
  switch target {
  case .automatic, .onDevice:
    let model = foundationModel(useCase: useCase)
    return FoundationModelResolvedSession(
      profile: profile,
      session: LanguageModelSession(model: model, tools: tools, instructions: instructions),
      systemModel: model
    )
  case .privateCloudCompute:
    #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
      let session = LanguageModelSession(
        model: PrivateCloudComputeLanguageModel(),
        tools: tools,
        instructions: instructions
      )
      return FoundationModelResolvedSession(profile: profile, session: session, systemModel: nil)
    }
    #endif
    throw FoundationModelFailure(reason: .unavailable(.unsupportedOS))
  case .providerPackage, .customLocal:
    throw FoundationModelFailure(
      reason: .unavailable(.unsupportedExecutionTarget(target.diagnosticName))
    )
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModel(
  useCase: FoundationModelUseCase
) -> SystemLanguageModel {
  switch useCase {
  case .general:
    return .default
  case .contentTagging:
    return SystemLanguageModel(useCase: .contentTagging)
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelValidate(
  _ options: FoundationModelGenerationOptions,
  against profile: FoundationModelRuntimeProfile
) throws {
  if options.reasoningEffort != nil, !profile.supportsReasoning {
    throw FoundationModelFailure(
      reason: .unsupportedCapability,
      debugDescription: "\(profile.modelIdentifier) does not support reasoning. Leave reasoningEffort nil or target Private Cloud Compute."
    )
  }
}

// MARK: - Request translation

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelRespondText(
  session: LanguageModelSession,
  prompt: Prompt,
  options: GenerationOptions,
  request: FoundationModelGenerationRequest
) async throws -> LanguageModelSession.Response<String> {
  #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
  if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *),
     let reasoningEffort = request.options.reasoningEffort
  {
    return try await session.respond(
      to: prompt,
      options: options,
      contextOptions: ContextOptions(
        includeSchemaInPrompt: nil,
        reasoningLevel: reasoningEffort.foundationReasoningLevel
      ),
      metadata: [:]
    )
  }
  #endif
  return try await session.respond(to: prompt, options: options)
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelRespondGenerating<Content: Generable>(
  session: LanguageModelSession,
  prompt: Prompt,
  generating type: Content.Type,
  options: GenerationOptions,
  request: FoundationModelGenerationRequest
) async throws -> LanguageModelSession.Response<Content> {
  #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
  if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *),
     let reasoningEffort = request.options.reasoningEffort
  {
    return try await session.respond(
      to: prompt,
      generating: type,
      options: options,
      contextOptions: ContextOptions(
        includeSchemaInPrompt: request.options.includeSchemaInPrompt,
        reasoningLevel: reasoningEffort.foundationReasoningLevel
      ),
      metadata: [:]
    )
  }
  #endif
  return try await session.respond(
    to: prompt,
    generating: type,
    includeSchemaInPrompt: request.options.includeSchemaInPrompt,
    options: options
  )
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelStreamText(
  session: LanguageModelSession,
  prompt: Prompt,
  options: GenerationOptions,
  request: FoundationModelGenerationRequest
) -> LanguageModelSession.ResponseStream<String> {
  #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
  if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *),
     let reasoningEffort = request.options.reasoningEffort
  {
    return session.streamResponse(
      to: prompt,
      options: options,
      contextOptions: ContextOptions(
        includeSchemaInPrompt: nil,
        reasoningLevel: reasoningEffort.foundationReasoningLevel
      ),
      metadata: [:]
    )
  }
  #endif
  return session.streamResponse(to: prompt, options: options)
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension FoundationModelGenerationOptions {
  fileprivate func foundationGenerationOptions() throws -> GenerationOptions {
    #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
      return GenerationOptions(
        samplingMode: sampling.foundationSamplingMode,
        temperature: temperature,
        maximumResponseTokens: maximumResponseTokens,
        toolCallingMode: toolCallingMode.foundationToolCallingMode
      )
    }
    #endif
    guard toolCallingMode == .allowed else {
      throw FoundationModelFailure(
        reason: .unsupportedCapability,
        debugDescription: "Tool calling mode \(toolCallingMode.rawValue) requires the OS 27 releases."
      )
    }
    return GenerationOptions(
      sampling: sampling.foundationSamplingMode,
      temperature: temperature,
      maximumResponseTokens: maximumResponseTokens
    )
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension FoundationModelSamplingMode {
  fileprivate var foundationSamplingMode: GenerationOptions.SamplingMode? {
    switch self {
    case .systemDefault:
      return nil
    case .greedy:
      return .greedy
    case let .randomTop(top, seed):
      return .random(top: top, seed: seed)
    case let .randomProbabilityThreshold(probabilityThreshold, seed):
      return .random(probabilityThreshold: probabilityThreshold, seed: seed)
    }
  }
}

// MARK: - Response facts and token measurement

/// Provider-reported facts about one response. Fields stay `nil` when the platform did not report them.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct FoundationModelResponseFacts: Sendable {
  var cachedInputTokens: Int?
  var measuredInputTokens: Int?
  var measuredOutputTokens: Int?
  var reasoningText: String?
  var reasoningTokens: Int?
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelFacts<Content>(
  from response: LanguageModelSession.Response<Content>
) -> FoundationModelResponseFacts {
  var facts = FoundationModelResponseFacts()
  #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
  if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
    facts.apply(response.usage)
    facts.reasoningText = foundationModelReasoningText(in: response.transcriptEntries)
  }
  #endif
  return facts
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelFacts(
  from snapshot: LanguageModelSession.ResponseStream<String>.Snapshot
) -> FoundationModelResponseFacts {
  var facts = FoundationModelResponseFacts()
  #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
  if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
    facts.apply(snapshot.usage)
    facts.reasoningText = foundationModelReasoningText(in: snapshot.transcriptEntries)
  }
  #endif
  return facts
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelEstimatedInputTokens(
  for request: FoundationModelGenerationRequest,
  toolConfiguration: FoundationModelToolConfiguration
) -> Int {
  TokenCounter.latinHeuristic.count(
    request.prompt.systemInstructions + "\n\n" + request.prompt.userPrompt
  ) + toolConfiguration.estimatedDefinitionTokens
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelMeasuredInputTokens(
  model: SystemLanguageModel?,
  request: FoundationModelGenerationRequest,
  tools: [any Tool]
) async -> Int? {
  guard let model, #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) else { return nil }

  do {
    var total = try await model.tokenCount(for: Prompt(request.prompt.userPrompt))
    if let instructions = request.prompt.systemInstructions.nilIfEmpty {
      total += try await model.tokenCount(for: Instructions(instructions))
    }
    if !tools.isEmpty {
      total += try await model.tokenCount(for: tools)
    }
    return total
  } catch {
    return nil
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelMeasuredTokenCount(
  _ text: String,
  model: SystemLanguageModel?
) async -> Int? {
  guard let model, #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) else { return nil }

  return try? await model.tokenCount(for: Prompt(text))
}

private func foundationModelFinishReason(
  measuredOutputTokens: Int?,
  maximumResponseTokens: Int?
) -> LMFinishReason {
  if let measuredOutputTokens,
     let maximumResponseTokens,
     measuredOutputTokens >= maximumResponseTokens
  {
    return .length
  }
  return .stop
}

// MARK: - Error normalization

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelFailure(from error: any Error) async -> FoundationModelFailure {
  if let failure = error as? FoundationModelFailure {
    return failure
  }

  #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
  if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *),
     case let .refusal(refusal)? = error as? LanguageModelError
  {
    let explanation = try? await refusal.explanation.content
    return FoundationModelFailure(
      reason: .refusal,
      debugDescription: explanation ?? refusal.debugDescription
    )
  }
  #endif

  if case let .refusal(refusal, context)? = error as? LanguageModelSession.GenerationError {
    let explanation = try? await refusal.explanation.content
    return FoundationModelFailure(
      reason: .refusal,
      debugDescription: explanation ?? context.debugDescription
    )
  }

  return FoundationModelErrorNormalizer.failure(from: error)
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelFailure(
  from error: LanguageModelSession.GenerationError
) -> FoundationModelFailure {
  switch error {
  case let .assetsUnavailable(context):
    return FoundationModelFailure(reason: .assetsUnavailable, debugDescription: context.debugDescription)
  case let .concurrentRequests(context):
    return FoundationModelFailure(reason: .concurrentRequests, debugDescription: context.debugDescription)
  case let .decodingFailure(context):
    return FoundationModelFailure(reason: .decodingFailure, debugDescription: context.debugDescription)
  case let .exceededContextWindowSize(context):
    return FoundationModelFailure(reason: .contextExceeded(), debugDescription: context.debugDescription)
  case let .guardrailViolation(context):
    return FoundationModelFailure(reason: .guardrailViolation, debugDescription: context.debugDescription)
  case let .rateLimited(context):
    return FoundationModelFailure(reason: .rateLimited(), debugDescription: context.debugDescription)
  case let .refusal(_, context):
    return FoundationModelFailure(reason: .refusal, debugDescription: context.debugDescription)
  case let .unsupportedGuide(context):
    return FoundationModelFailure(reason: .unsupportedGuide, debugDescription: context.debugDescription)
  case let .unsupportedLanguageOrLocale(context):
    return FoundationModelFailure(
      reason: .unsupportedLanguageOrLocale,
      debugDescription: context.debugDescription
    )
  @unknown default:
    return FoundationModelFailure(
      reason: .providerError,
      debugDescription: error.localizedDescription
    )
  }
}

// MARK: - OS 27 mappings

#if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
private func foundationModelPrivateCloudComputeAvailability(
  locale: Locale?
) async -> FoundationModelAvailability {
  let model = PrivateCloudComputeLanguageModel()
  switch model.availability {
  case .available:
    break
  case .unavailable(.deviceNotEligible):
    return .deviceNotEligible
  case .unavailable(.systemNotReady):
    return .systemNotReady
  case .unavailable:
    return .unknown("Private Cloud Compute is unavailable.")
  }

  let locale = locale ?? .current
  if let supportsLocale = try? await model.supportsLocale(locale), !supportsLocale {
    return .unsupportedLocale(locale.identifier)
  }

  let quotaUsage = model.quotaUsage
  if quotaUsage.isLimitReached {
    return .quotaLimitReached(resetsAt: quotaUsage.resetDate)
  }
  return .available
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension FoundationModelQuotaStatus {
  init(quotaUsage: PrivateCloudComputeLanguageModel.QuotaUsage) {
    if quotaUsage.isLimitReached {
      self = .exhausted(
        resetsAt: quotaUsage.resetDate,
        limitIncreaseSuggestionAvailable: quotaUsage.limitIncreaseSuggestion != nil
      )
    } else if case let .belowLimit(info) = quotaUsage.status, info.isApproachingLimit {
      self = .approachingLimit(resetsAt: quotaUsage.resetDate)
    } else {
      self = .available
    }
  }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension FoundationModelRuntimeProfile {
  fileprivate mutating func applyCapabilities(_ capabilities: LanguageModelCapabilities) {
    supportsGuidedGeneration = capabilities.contains(.guidedGeneration)
    supportsReasoning = capabilities.contains(.reasoning)
    supportsToolCalling = capabilities.contains(.toolCalling)
    supportsVision = capabilities.contains(.vision)
  }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension FoundationModelResponseFacts {
  fileprivate mutating func apply(_ usage: LanguageModelSession.Usage) {
    cachedInputTokens = usage.input.cachedTokenCount
    measuredInputTokens = usage.input.totalTokenCount
    measuredOutputTokens = usage.output.totalTokenCount
    reasoningTokens = usage.output.reasoningTokenCount
  }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
private func foundationModelReasoningText(
  in entries: some Sequence<Transcript.Entry>
) -> String? {
  let reasoning = entries.compactMap { entry -> String? in
    guard case let .reasoning(reasoning) = entry else { return nil }
    let text = reasoning.segments.compactMap { segment -> String? in
      guard case let .text(textSegment) = segment else { return nil }
      return textSegment.content
    }
    return text.isEmpty ? nil : text.joined(separator: "\n")
  }
  return reasoning.isEmpty ? nil : reasoning.joined(separator: "\n\n")
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension LMReasoningEffort {
  fileprivate var foundationReasoningLevel: ContextOptions.ReasoningLevel {
    switch self {
    case .low:
      return .light
    case .medium:
      return .moderate
    case .high:
      return .deep
    }
  }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension FoundationModelToolCallingMode {
  fileprivate var foundationToolCallingMode: GenerationOptions.ToolCallingMode? {
    switch self {
    case .allowed:
      return nil
    case .disallowed:
      return .disallowed
    case .required:
      return .required
    }
  }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
func foundationModelFailure(fromOS27Error error: any Error) -> FoundationModelFailure? {
  if let error = error as? LanguageModelError {
    switch error {
    case let .contextSizeExceeded(info):
      return FoundationModelFailure(
        reason: .contextExceeded(contextSize: info.contextSize, tokenCount: info.tokenCount),
        debugDescription: info.debugDescription
      )
    case let .rateLimited(info):
      return FoundationModelFailure(
        reason: .rateLimited(resetsAt: info.resetDate),
        debugDescription: info.debugDescription
      )
    case let .refusal(info):
      return FoundationModelFailure(reason: .refusal, debugDescription: info.debugDescription)
    case let .timeout(info):
      return FoundationModelFailure(reason: .timeout, debugDescription: info.debugDescription)
    case let .guardrailViolation(info):
      return FoundationModelFailure(reason: .guardrailViolation, debugDescription: info.debugDescription)
    case let .unsupportedCapability(info):
      return FoundationModelFailure(reason: .unsupportedCapability, debugDescription: info.debugDescription)
    case let .unsupportedTranscriptContent(info):
      return FoundationModelFailure(
        reason: .unsupportedTranscriptContent,
        debugDescription: info.debugDescription
      )
    case let .unsupportedGenerationGuide(info):
      return FoundationModelFailure(reason: .unsupportedGuide, debugDescription: info.debugDescription)
    case let .unsupportedLanguageOrLocale(info):
      return FoundationModelFailure(
        reason: .unsupportedLanguageOrLocale,
        debugDescription: info.debugDescription
      )
    default:
      return FoundationModelFailure(reason: .providerError, debugDescription: error.localizedDescription)
    }
  }

  if let error = error as? SystemLanguageModel.Error {
    switch error {
    case let .assetsUnavailable(info):
      return FoundationModelFailure(reason: .assetsUnavailable, debugDescription: info.debugDescription)
    default:
      return FoundationModelFailure(reason: .providerError, debugDescription: error.localizedDescription)
    }
  }

  if let error = error as? LanguageModelSession.Error {
    switch error {
    case .concurrentRequests:
      return FoundationModelFailure(reason: .concurrentRequests)
    case .transcriptMutationWhileResponding:
      return FoundationModelFailure(reason: .transcriptMutationWhileResponding)
    default:
      return FoundationModelFailure(reason: .providerError, debugDescription: error.localizedDescription)
    }
  }

  if let error = error as? PrivateCloudComputeLanguageModel.Error {
    switch error {
    case let .quotaLimitReached(info):
      return FoundationModelFailure(
        reason: .quotaLimitReached(
          resetsAt: info.resetDate,
          limitIncreaseSuggestionAvailable: info.limitIncreaseSuggestion != nil
        ),
        debugDescription: info.debugDescription
      )
    case let .networkFailure(info):
      return FoundationModelFailure(reason: .networkUnavailable, debugDescription: info.debugDescription)
    case let .serviceUnavailable(info):
      return FoundationModelFailure(reason: .serviceUnavailable, debugDescription: info.debugDescription)
    default:
      return FoundationModelFailure(reason: .providerError, debugDescription: error.localizedDescription)
    }
  }

  return nil
}
#endif

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
#endif
