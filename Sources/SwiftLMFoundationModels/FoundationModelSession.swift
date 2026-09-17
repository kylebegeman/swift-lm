import Foundation
import SwiftLM

#if canImport(FoundationModels)
import FoundationModels

/// A reusable Foundation Models conversation.
///
/// Every request adds to the same `LanguageModelSession`, so the model keeps its transcript and
/// key-value cache between turns, and native tools stay available across turns. Requests must not
/// overlap: a request made while another is running fails with
/// `FoundationModelFailureReason.concurrentRequests`.
///
/// Use `FoundationModelClient` for independent, stateless requests.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
public final class FoundationModelSession: Sendable {
  public let executionTarget: FoundationModelExecutionTarget
  public let metadata: LMProviderMetadata
  public let runtimeProfile: FoundationModelRuntimeProfile
  public let useCase: FoundationModelUseCase
  private let instructions: String
  private let live: FoundationModelLiveSession

  /// Opens a session after checking that the target is available.
  ///
  /// - Parameters:
  ///   - client: The client whose models to use. A client created with
  ///     `FoundationModelClient.live(model:executionTarget:contextWindowTokens:)` opens the session
  ///     on its custom model.
  ///   - executionTarget: The target to run on. Defaults to the client's default target.
  ///   - history: Earlier turns to continue from, such as a restored conversation.
  ///   - tools: Native tools the model may call during any turn.
  public init(
    client: FoundationModelClient = .live,
    executionTarget: FoundationModelExecutionTarget? = nil,
    useCase: FoundationModelUseCase? = nil,
    instructions: String? = nil,
    history: [FoundationModelTranscriptTurn] = [],
    tools: [any Tool] = [],
    promptVersion: String = FoundationModelDefaults.defaultPromptVersion
  ) async throws {
    let executionTarget = executionTarget ?? client.defaultExecutionTarget
    let useCase = useCase ?? client.defaultUseCase
    let live = try await foundationModelOpenSession(
      source: client.liveSessionSource,
      configuration: FoundationModelSessionConfiguration(
        history: history,
        instructions: instructions?.nilIfEmpty,
        target: executionTarget,
        tools: tools,
        useCase: useCase
      )
    )
    self.executionTarget = executionTarget
    self.instructions = instructions ?? ""
    self.live = live
    self.metadata = FoundationModelDefaults.metadata(
      promptVersion: promptVersion,
      modelIdentifier: live.profile.modelIdentifier,
      executionTarget: executionTarget
    )
    self.runtimeProfile = live.profile
    self.useCase = useCase
  }

  /// Whether the session is producing a response.
  public var isResponding: Bool {
    live.session.isResponding
  }

  /// The conversation so far, including instructions, tool calls, and tool output.
  public var transcript: Transcript {
    live.session.transcript
  }

  /// Loads the model ahead of the next request, optionally caching a known prompt prefix.
  public func prewarm(promptPrefix: String? = nil) {
    live.session.prewarm(promptPrefix: promptPrefix.map { Prompt($0) })
  }

  /// Responds to the next turn. The session's execution target replaces `options.executionTarget`.
  public func respond(
    to prompt: String,
    images: [LMImage] = [],
    options: FoundationModelGenerationOptions = .deterministic
  ) async throws -> FoundationModelGenerationResponse<String> {
    let request = generationRequest(prompt: prompt, images: images, options: options)
    return try await foundationModelGenerate(
      request: request,
      live: live,
      estimatedInputTokens: estimatedInputTokens(prompt: prompt),
      measureInput: foundationModelSessionInputMeasurement(
        model: live.systemModel,
        transcript: live.session.transcript
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

  /// Generates a typed value for the next turn.
  public func respond<Content: Generable & Sendable>(
    generating type: Content.Type,
    to prompt: String,
    images: [LMImage] = [],
    options: FoundationModelGenerationOptions = .deterministic
  ) async throws -> FoundationModelGenerationResponse<Content> {
    let request = generationRequest(prompt: prompt, images: images, options: options)
    return try await foundationModelGenerate(
      request: request,
      live: live,
      estimatedInputTokens: estimatedInputTokens(prompt: prompt),
      measureInput: foundationModelSessionInputMeasurement(
        model: live.systemModel,
        transcript: live.session.transcript
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

  /// Streams the next turn as text deltas followed by the completed response.
  public func stream(
    _ prompt: String,
    images: [LMImage] = [],
    options: FoundationModelGenerationOptions = .deterministic
  ) -> AsyncThrowingStream<FoundationModelStreamEvent, any Error> {
    let request = generationRequest(prompt: prompt, images: images, options: options)
    let live = live
    return foundationModelStreamEvents(
      request: request,
      estimatedInputTokens: estimatedInputTokens(prompt: prompt)
    ) {
      let measureInput = foundationModelSessionInputMeasurement(
        model: live.systemModel,
        transcript: live.session.transcript
      )
      return (live, measureInput)
    }
  }

  private func generationRequest(
    prompt: String,
    images: [LMImage],
    options: FoundationModelGenerationOptions
  ) -> FoundationModelGenerationRequest {
    var options = options
    options.executionTarget = executionTarget
    return FoundationModelGenerationRequest(
      prompt: CompiledPrompt(
        contract: PromptContract(
          id: "foundation-model-session",
          version: metadata.promptVersion,
          instructions: instructions
        ),
        metadata: metadata,
        userPrompt: prompt
      ),
      options: options,
      useCase: useCase,
      images: images
    )
  }

  private func estimatedInputTokens(prompt: String) -> Int {
    TokenCounter.latinHeuristic.count(
      foundationModelTranscriptText(live.session.transcript) + "\n\n" + prompt
    )
  }
}
#endif
