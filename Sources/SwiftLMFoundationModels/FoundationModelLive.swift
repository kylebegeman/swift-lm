import Foundation
import SwiftLM

#if canImport(FoundationModels)
import FoundationModels
import ImageIO

// MARK: - SDK gate
//
// OS 27 symbols (Private Cloud Compute, custom `LanguageModel` sessions, image attachments,
// `LanguageModelError`, `ContextOptions`, tool calling modes, and usage reporting) exist only in
// the OS 27 SDKs that ship with Xcode 27 and Swift 6.4. `compiler(>=6.4)` keeps them out of OS 26
// SDK builds, and `#available` checks keep them off OS 26 devices at runtime. Define
// `SWIFTLM_OS26_SDK_ONLY` to build with a Swift 6.4 toolchain that still uses an OS 26 SDK.

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
    try await foundationModelPrewarm(for: request, source: liveSessionSource, tools: tools)
  }

  public func respond(
    to request: FoundationModelGenerationRequest,
    tools: [any Tool]
  ) async throws -> FoundationModelGenerationResponse<String> {
    try await foundationModelStringResponse(for: request, source: liveSessionSource, tools: tools)
  }

  public func respond<Content: Generable & Sendable>(
    generating type: Content.Type,
    request: FoundationModelGenerationRequest,
    tools: [any Tool] = []
  ) async throws -> FoundationModelGenerationResponse<Content> {
    try await foundationModelGeneratedResponse(
      generating: type,
      for: request,
      source: liveSessionSource,
      tools: tools
    )
  }

  public func stream(
    _ request: FoundationModelGenerationRequest,
    tools: [any Tool]
  ) -> AsyncThrowingStream<FoundationModelStreamEvent, any Error> {
    foundationModelStream(for: request, source: liveSessionSource, tools: tools)
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

/// The runtime profile the platform can report synchronously. Private Cloud Compute reports its
/// context size only asynchronously, so this profile uses Apple's documented 32K window for it;
/// `foundationModelReportedRuntimeProfile` replaces that with the reported value.
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

/// The runtime profile including values the platform reports asynchronously, such as the Private
/// Cloud Compute context size.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelReportedRuntimeProfile(
  target: FoundationModelExecutionTarget,
  useCase: FoundationModelUseCase
) async -> FoundationModelRuntimeProfile {
  var profile = foundationModelRuntimeProfile(target: target, useCase: useCase)
  #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
  if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *),
     target == .privateCloudCompute,
     let contextSize = try? await PrivateCloudComputeLanguageModel().contextSize
  {
    profile.contextWindowTokens = contextSize
    profile.isContextWindowReported = true
  }
  #endif
  return profile
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
  source: FoundationModelSessionSource,
  tools: [any Tool]
) async throws {
  let live = try await foundationModelOpenSession(
    source: source,
    configuration: FoundationModelSessionConfiguration(
      instructions: request.instructions.nilIfEmpty,
      target: request.executionTarget,
      tools: tools,
      useCase: request.useCase
    )
  )
  live.session.prewarm(promptPrefix: request.promptPrefix.map(Prompt.init))
}

// MARK: - Session sources

/// Where live sessions come from: Apple's system models, or an app-supplied `LanguageModel` on the
/// OS 27 releases.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct FoundationModelSessionSource: Sendable {
  var availability:
    @Sendable (FoundationModelExecutionTarget, Locale?, FoundationModelUseCase) async
      -> FoundationModelAvailability
  var countTokens: @Sendable (FoundationModelTokenCountRequest) async throws -> Int
  var makeSession: @Sendable (FoundationModelSessionConfiguration) throws -> FoundationModelSessionHandle
  var onDeviceAvailability: @Sendable (Locale?, FoundationModelUseCase) -> FoundationModelAvailability
  var reportedRuntimeProfile:
    @Sendable (FoundationModelExecutionTarget, FoundationModelUseCase) async
      -> FoundationModelRuntimeProfile
  var runtimeProfile:
    @Sendable (FoundationModelExecutionTarget, FoundationModelUseCase) -> FoundationModelRuntimeProfile

  static let system = Self(
    availability: { target, locale, useCase in
      await foundationModelAvailability(target: target, locale: locale, useCase: useCase)
    },
    countTokens: { request in
      try await foundationModelTokenCount(for: request)
    },
    makeSession: { configuration in
      try foundationModelSystemSession(configuration)
    },
    onDeviceAvailability: { locale, useCase in
      foundationModelAvailability(locale: locale, useCase: useCase)
    },
    reportedRuntimeProfile: { target, useCase in
      await foundationModelReportedRuntimeProfile(target: target, useCase: useCase)
    },
    runtimeProfile: { target, useCase in
      foundationModelRuntimeProfile(target: target, useCase: useCase)
    }
  )
}

/// What a session source needs to open a session.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct FoundationModelSessionConfiguration: Sendable {
  var history: [FoundationModelTranscriptTurn] = []
  var instructions: String?
  var target: FoundationModelExecutionTarget
  var tools: [any Tool] = []
  var useCase: FoundationModelUseCase
}

/// A session a source created, with the on-device model when there is one.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct FoundationModelSessionHandle: Sendable {
  var session: LanguageModelSession
  /// The on-device model, used for exact token counting. `nil` for server and custom models.
  var systemModel: SystemLanguageModel?
}

/// An open session and the runtime facts the adapter reports for it.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct FoundationModelLiveSession: Sendable {
  var handle: FoundationModelSessionHandle
  var profile: FoundationModelRuntimeProfile

  var session: LanguageModelSession {
    handle.session
  }

  var systemModel: SystemLanguageModel? {
    handle.systemModel
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension FoundationModelClient {
  /// The session source behind the typed APIs: Apple's system models unless the client wraps a
  /// custom `LanguageModel`.
  var liveSessionSource: FoundationModelSessionSource {
    (sessionSource?.value as? FoundationModelSessionSource) ?? .system
  }

  /// Builds a live client whose closures and typed APIs all use `source`.
  static func makeLive(
    source: FoundationModelSessionSource,
    defaultExecutionTarget: FoundationModelExecutionTarget = .automatic
  ) -> Self {
    var client = Self(
      checkAvailability: { locale, useCase in
        source.onDeviceAvailability(locale, useCase)
      },
      countTokens: { request in
        try await source.countTokens(request)
      },
      prewarm: { request in
        try await foundationModelPrewarm(for: request, source: source, tools: [])
      },
      respond: { request in
        try await foundationModelStringResponse(for: request, source: source, tools: [])
      },
      checkExecutionTargetAvailability: { target, locale, useCase in
        await source.availability(target, locale, useCase)
      },
      resolveRuntimeProfile: { target, useCase in
        source.runtimeProfile(target, useCase)
      },
      resolveReportedRuntimeProfile: { target, useCase in
        await source.reportedRuntimeProfile(target, useCase)
      },
      streamResponse: { request in
        foundationModelStream(for: request, source: source, tools: [])
      },
      defaultExecutionTarget: defaultExecutionTarget
    )
    client.sessionSource = FoundationModelSessionSourceBox(value: source)
    return client
  }
}

/// Checks availability for the target, then opens a session and reports its runtime profile.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelOpenSession(
  source: FoundationModelSessionSource,
  configuration: FoundationModelSessionConfiguration
) async throws -> FoundationModelLiveSession {
  let availability = await source.availability(configuration.target, nil, configuration.useCase)
  guard availability.isAvailable
  else { throw FoundationModelFailure(reason: .unavailable(availability)) }

  let handle = try source.makeSession(configuration)
  let profile = await source.reportedRuntimeProfile(configuration.target, configuration.useCase)
  return FoundationModelLiveSession(handle: handle, profile: profile)
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelSystemSession(
  _ configuration: FoundationModelSessionConfiguration
) throws -> FoundationModelSessionHandle {
  switch configuration.target {
  case .automatic, .onDevice:
    let model = foundationModel(useCase: configuration.useCase)
    let session: LanguageModelSession
    if configuration.history.isEmpty {
      session = LanguageModelSession(
        model: model,
        tools: configuration.tools,
        instructions: configuration.instructions
      )
    } else {
      session = LanguageModelSession(
        model: model,
        tools: configuration.tools,
        transcript: foundationModelTranscript(for: configuration)
      )
    }
    return FoundationModelSessionHandle(session: session, systemModel: model)
  case .privateCloudCompute:
    #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
      return FoundationModelSessionHandle(
        session: foundationModelSession(
          model: PrivateCloudComputeLanguageModel(),
          configuration: configuration
        ),
        systemModel: nil
      )
    }
    #endif
    throw FoundationModelFailure(reason: .unavailable(.unsupportedOS))
  case .providerPackage, .customLocal:
    throw FoundationModelFailure(
      reason: .unavailable(.unsupportedExecutionTarget(configuration.target.diagnosticName))
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
  _ request: FoundationModelGenerationRequest,
  against profile: FoundationModelRuntimeProfile
) throws {
  if request.options.reasoningEffort != nil, !profile.supportsReasoning {
    throw FoundationModelFailure(
      reason: .unsupportedCapability,
      debugDescription: "\(profile.modelIdentifier) does not support reasoning. Leave reasoningEffort nil or target Private Cloud Compute."
    )
  }
  if !request.images.isEmpty, !profile.supportsVision {
    throw FoundationModelFailure(
      reason: .unsupportedCapability,
      debugDescription: "\(profile.modelIdentifier) does not accept images."
    )
  }
}

// MARK: - Transcripts

/// Rebuilds a session transcript: an instructions entry that describes the tools, followed by the
/// earlier turns.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelTranscript(
  for configuration: FoundationModelSessionConfiguration
) -> Transcript {
  var entries: [Transcript.Entry] = []
  if configuration.instructions != nil || !configuration.tools.isEmpty {
    let segments: [Transcript.Segment] = configuration.instructions.map {
      [.text(Transcript.TextSegment(content: $0))]
    } ?? []
    entries.append(
      .instructions(
        Transcript.Instructions(
          segments: segments,
          toolDefinitions: configuration.tools.map { Transcript.ToolDefinition(tool: $0) }
        )
      )
    )
  }
  entries.append(contentsOf: foundationModelTranscriptEntries(for: configuration.history))
  return Transcript(entries: entries)
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelTranscriptEntries(
  for history: [FoundationModelTranscriptTurn]
) -> [Transcript.Entry] {
  history.map { turn in
    let segments: [Transcript.Segment] = [.text(Transcript.TextSegment(content: turn.text))]
    switch turn.role {
    case .prompt:
      return .prompt(Transcript.Prompt(segments: segments))
    case .response:
      return .response(Transcript.Response(assetIDs: [], segments: segments))
    }
  }
}

/// The text of the instructions, prompts, and responses in a transcript, for heuristic estimates.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelTranscriptText(_ entries: some Sequence<Transcript.Entry>) -> String {
  entries.compactMap { entry -> String? in
    let segments: [Transcript.Segment]
    switch entry {
    case let .instructions(instructions):
      segments = instructions.segments
    case let .prompt(prompt):
      segments = prompt.segments
    case let .response(response):
      segments = response.segments
    default:
      return nil
    }
    return segments.compactMap { segment -> String? in
      guard case let .text(text) = segment else { return nil }
      return text.content
    }
    .joined(separator: "\n")
  }
  .joined(separator: "\n\n")
}

// MARK: - Prompts

/// Builds the prompt for one request. Images need the OS 27 releases.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelPrompt(text: String, images: [LMImage]) throws -> Prompt {
  guard !images.isEmpty else { return Prompt(text) }
  #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
  if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
    let attachments = try images.map(foundationModelAttachmentPrompt)
    return Prompt {
      text
      attachments
    }
  }
  #endif
  throw FoundationModelFailure(
    reason: .unsupportedCapability,
    debugDescription: "Image prompts require the OS 27 releases."
  )
}

// MARK: - Generation

/// Measures a request's input tokens when the platform does not report usage.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
typealias FoundationModelInputMeasurement = @Sendable (Prompt) async -> Int?

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelStringResponse(
  for request: FoundationModelGenerationRequest,
  source: FoundationModelSessionSource,
  tools: [any Tool]
) async throws -> FoundationModelGenerationResponse<String> {
  let live = try await foundationModelOpenRequestSession(for: request, source: source, tools: tools)
  return try await foundationModelGenerate(
    request: request,
    live: live,
    estimatedInputTokens: foundationModelEstimatedInputTokens(for: request, tools: tools),
    measureInput: foundationModelRequestInputMeasurement(
      request: request,
      model: live.systemModel,
      tools: tools
    )
  ) { session, prompt, options in
    let response = try await foundationModelRespondText(
      session: session,
      prompt: prompt,
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
  source: FoundationModelSessionSource,
  tools: [any Tool]
) async throws -> FoundationModelGenerationResponse<Content> {
  let live = try await foundationModelOpenRequestSession(for: request, source: source, tools: tools)
  return try await foundationModelGenerate(
    request: request,
    live: live,
    estimatedInputTokens: foundationModelEstimatedInputTokens(for: request, tools: tools),
    measureInput: foundationModelRequestInputMeasurement(
      request: request,
      model: live.systemModel,
      tools: tools
    )
  ) { session, prompt, options in
    let response = try await foundationModelRespondGenerating(
      session: session,
      prompt: prompt,
      generating: type,
      options: options,
      request: request
    )
    return (response.content, foundationModelFacts(from: response))
  }
}

/// Opens a single-use session for a stateless request and prewarms its prompt prefix.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelOpenRequestSession(
  for request: FoundationModelGenerationRequest,
  source: FoundationModelSessionSource,
  tools: [any Tool]
) async throws -> FoundationModelLiveSession {
  let live = try await foundationModelOpenSession(
    source: source,
    configuration: FoundationModelSessionConfiguration(
      history: request.history,
      instructions: request.prompt.systemInstructions.nilIfEmpty,
      target: request.options.executionTarget,
      tools: tools,
      useCase: request.useCase
    )
  )
  if let prewarmPromptPrefix = request.prewarmPromptPrefix {
    live.session.prewarm(promptPrefix: Prompt(prewarmPromptPrefix))
  }
  return live
}

/// Runs one request on an open session and reports usage, reasoning, and the runtime profile.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelGenerate<Content: Sendable>(
  request: FoundationModelGenerationRequest,
  live: FoundationModelLiveSession,
  estimatedInputTokens: Int,
  measureInput: FoundationModelInputMeasurement,
  perform: (LanguageModelSession, Prompt, GenerationOptions) async throws
    -> (Content, FoundationModelResponseFacts)
) async throws -> FoundationModelGenerationResponse<Content> {
  do {
    try foundationModelValidate(request, against: live.profile)
    let prompt = try foundationModelPrompt(text: request.prompt.userPrompt, images: request.images)
    let options = try request.options.foundationGenerationOptions()
    let startedAt = Date()
    let (content, facts) = try await perform(live.session, prompt, options)
    return await foundationModelResponse(
      content: content,
      renderedOutput: String(describing: content),
      request: request,
      live: live,
      facts: facts,
      prompt: prompt,
      estimatedInputTokens: estimatedInputTokens,
      measureInput: measureInput,
      startedAt: startedAt
    )
  } catch is CancellationError {
    throw CancellationError()
  } catch {
    throw await foundationModelFailure(from: error)
  }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelResponse<Content: Sendable>(
  content: Content,
  renderedOutput: String,
  request: FoundationModelGenerationRequest,
  live: FoundationModelLiveSession,
  facts: FoundationModelResponseFacts,
  prompt: Prompt,
  estimatedInputTokens: Int,
  measureInput: FoundationModelInputMeasurement,
  startedAt: Date
) async -> FoundationModelGenerationResponse<Content> {
  let completedAt = Date()
  let measuredInputTokens: Int?
  if let measured = facts.measuredInputTokens {
    measuredInputTokens = measured
  } else {
    measuredInputTokens = await measureInput(prompt)
  }
  let measuredOutputTokens: Int?
  if let measured = facts.measuredOutputTokens {
    measuredOutputTokens = measured
  } else {
    measuredOutputTokens = await foundationModelMeasuredTokenCount(
      renderedOutput,
      model: live.systemModel
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
    runtimeProfile: live.profile
  )
}

// MARK: - Streaming

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelStream(
  for request: FoundationModelGenerationRequest,
  source: FoundationModelSessionSource,
  tools: [any Tool]
) -> AsyncThrowingStream<FoundationModelStreamEvent, any Error> {
  foundationModelStreamEvents(
    request: request,
    estimatedInputTokens: foundationModelEstimatedInputTokens(for: request, tools: tools)
  ) {
    let live = try await foundationModelOpenRequestSession(for: request, source: source, tools: tools)
    let measureInput = foundationModelRequestInputMeasurement(
      request: request,
      model: live.systemModel,
      tools: tools
    )
    return (live, measureInput)
  }
}

/// Streams one request as text deltas followed by the completed response. `open` runs inside the
/// stream's task, so a reused session's transcript is read when the request starts.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelStreamEvents(
  request: FoundationModelGenerationRequest,
  estimatedInputTokens: Int,
  open: @escaping @Sendable () async throws
    -> (FoundationModelLiveSession, FoundationModelInputMeasurement)
) -> AsyncThrowingStream<FoundationModelStreamEvent, any Error> {
  AsyncThrowingStream { continuation in
    let task = Task {
      do {
        let (live, measureInput) = try await open()
        try foundationModelValidate(request, against: live.profile)
        let prompt = try foundationModelPrompt(text: request.prompt.userPrompt, images: request.images)
        let options = try request.options.foundationGenerationOptions()
        let startedAt = Date()
        let stream = foundationModelStreamText(
          session: live.session,
          prompt: prompt,
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

        let response = await foundationModelResponse(
          content: emittedText,
          renderedOutput: emittedText,
          request: request,
          live: live,
          facts: facts,
          prompt: prompt,
          estimatedInputTokens: estimatedInputTokens,
          measureInput: measureInput,
          startedAt: startedAt
        )
        continuation.yield(.completed(response))
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

// MARK: - Request translation

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelRespondText(
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
func foundationModelRespondGenerating<Content: Generable>(
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
func foundationModelStreamText(
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
    try requireDefaultToolCallingMode()
    // The OS 27 SDK back-deploys this initializer to the OS 26 releases and deprecates
    // `init(sampling:)`.
    return GenerationOptions(
      samplingMode: sampling.foundationSamplingMode,
      temperature: temperature,
      maximumResponseTokens: maximumResponseTokens
    )
    #else
    try requireDefaultToolCallingMode()
    return GenerationOptions(
      sampling: sampling.foundationSamplingMode,
      temperature: temperature,
      maximumResponseTokens: maximumResponseTokens
    )
    #endif
  }

  private func requireDefaultToolCallingMode() throws {
    guard toolCallingMode == .allowed else {
      throw FoundationModelFailure(
        reason: .unsupportedCapability,
        debugDescription: "Tool calling mode \(toolCallingMode.rawValue) requires the OS 27 releases."
      )
    }
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
struct FoundationModelResponseFacts: Sendable {
  var cachedInputTokens: Int?
  var measuredInputTokens: Int?
  var measuredOutputTokens: Int?
  var reasoningText: String?
  var reasoningTokens: Int?
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelFacts<Content>(
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
func foundationModelFacts(
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
func foundationModelEstimatedInputTokens(
  for request: FoundationModelGenerationRequest,
  tools: [any Tool]
) -> Int {
  let text = [
    request.prompt.systemInstructions,
    request.history.map(\.text).joined(separator: "\n\n"),
    request.prompt.userPrompt,
  ]
  .filter { !$0.isEmpty }
  .joined(separator: "\n\n")
  return TokenCounter.latinHeuristic.count(text)
    + FoundationModelToolConfiguration(tools: tools).estimatedDefinitionTokens
}

/// Measures instructions, tool definitions, history, and the prompt of a stateless request.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private func foundationModelRequestInputMeasurement(
  request: FoundationModelGenerationRequest,
  model: SystemLanguageModel?,
  tools: [any Tool]
) -> FoundationModelInputMeasurement {
  { prompt in
    guard let model, #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) else { return nil }

    do {
      var total = try await model.tokenCount(for: prompt)
      if let instructions = request.prompt.systemInstructions.nilIfEmpty {
        total += try await model.tokenCount(for: Instructions(instructions))
      }
      if !tools.isEmpty {
        total += try await model.tokenCount(for: tools)
      }
      if !request.history.isEmpty {
        total += try await model.tokenCount(
          for: foundationModelTranscriptEntries(for: request.history)
        )
      }
      return total
    } catch {
      return nil
    }
  }
}

/// Measures a reused session's transcript before the request plus the new prompt.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
func foundationModelSessionInputMeasurement(
  model: SystemLanguageModel?,
  transcript: Transcript
) -> FoundationModelInputMeasurement {
  { prompt in
    guard let model, #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) else { return nil }

    do {
      return try await model.tokenCount(for: transcript) + model.tokenCount(for: prompt)
    } catch {
      return nil
    }
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
func foundationModelSession(
  model: some LanguageModel,
  configuration: FoundationModelSessionConfiguration
) -> LanguageModelSession {
  if configuration.history.isEmpty {
    return LanguageModelSession(
      model: model,
      tools: configuration.tools,
      instructions: configuration.instructions
    )
  }
  return LanguageModelSession(
    model: model,
    tools: configuration.tools,
    transcript: foundationModelTranscript(for: configuration)
  )
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
private func foundationModelAttachmentPrompt(_ image: LMImage) throws -> Prompt {
  switch image.source {
  case let .url(url):
    guard url.isFileURL else {
      throw FoundationModelFailure(
        reason: .unsupportedCapability,
        debugDescription: "Foundation Models reads images from data or local files, not remote URLs."
      )
    }
    return Prompt(Attachment(imageURL: url, orientation: nil))
  case let .data(data, _):
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
      throw FoundationModelFailure(
        reason: .invalidImage,
        debugDescription: "The image data could not be decoded."
      )
    }
    return Prompt(Attachment(cgImage))
  }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension FoundationModelClient {
  /// A client backed by any Foundation Models `LanguageModel`, such as a Core AI or MLX model or a
  /// third-party provider package.
  ///
  /// Every request runs on `model`. `executionTarget` describes the model for routing, privacy
  /// metadata, and diagnostics: use `.customLocal` for on-device models and `.providerPackage` for
  /// models that call a network service. `LanguageModel` does not report a context size, so pass
  /// `contextWindowTokens` when you know it.
  public static func live(
    model: some LanguageModel,
    executionTarget: FoundationModelExecutionTarget,
    contextWindowTokens: Int? = nil
  ) -> Self {
    makeLive(
      source: .languageModel(
        model,
        target: executionTarget,
        contextWindowTokens: contextWindowTokens
      ),
      defaultExecutionTarget: executionTarget
    )
  }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension FoundationModelSessionSource {
  static func languageModel(
    _ model: some LanguageModel,
    target: FoundationModelExecutionTarget,
    contextWindowTokens: Int?
  ) -> Self {
    @Sendable func accepts(_ requested: FoundationModelExecutionTarget) -> Bool {
      requested == .automatic || requested == target
    }

    @Sendable func profile() -> FoundationModelRuntimeProfile {
      var profile = FoundationModelRuntimeProfile(
        executionTarget: target,
        contextWindowTokens: contextWindowTokens,
        quotaStatus: .notApplicable
      )
      profile.applyCapabilities(model.capabilities)
      return profile
    }

    return Self(
      availability: { requested, _, _ in
        accepts(requested) ? .available : .unsupportedExecutionTarget(requested.diagnosticName)
      },
      countTokens: { request in
        TokenCounter.latinHeuristic.count(request.text)
      },
      makeSession: { configuration in
        guard accepts(configuration.target) else {
          throw FoundationModelFailure(
            reason: .unavailable(.unsupportedExecutionTarget(configuration.target.diagnosticName))
          )
        }
        return FoundationModelSessionHandle(
          session: foundationModelSession(model: model, configuration: configuration),
          systemModel: nil
        )
      },
      onDeviceAvailability: { _, _ in
        .available
      },
      reportedRuntimeProfile: { _, _ in
        profile()
      },
      runtimeProfile: { _, _ in
        profile()
      }
    )
  }
}

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

extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
#endif
