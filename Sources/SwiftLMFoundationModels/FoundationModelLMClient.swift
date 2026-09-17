import Foundation
import SwiftLM

extension FoundationModelClient: LMClient {
  /// Capabilities for the client's default execution target, including the platform-reported
  /// context window and reasoning support when the resolved model offers it.
  public var capabilities: LMClientCapabilities {
    runtimeProfile().capabilities
  }

  public var metadata: LMProviderMetadata {
    FoundationModelDefaults.metadata(executionTarget: defaultExecutionTarget)
  }

  public func respond(to request: LMRequest) async throws -> LMResponse {
    let generationRequest = try generationRequest(for: request)
    let response = try await respond(generationRequest)
    return Self.response(from: response)
  }

  public func stream(to request: LMRequest) -> AsyncThrowingStream<LMStreamEvent, any Error> {
    let metadata = metadata(for: request)
    return AsyncThrowingStream { continuation in
      continuation.yield(.started(metadata))
      let task = Task {
        do {
          let generationRequest = try generationRequest(for: request)
          for try await event in streamResponse(generationRequest) {
            switch event {
            case let .textDelta(delta):
              continuation.yield(.textDelta(delta))
            case let .completed(response):
              let completed = Self.response(from: response)
              if let usage = completed.tokenUsage {
                continuation.yield(.usage(usage))
              }
              continuation.yield(.completed(completed))
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func generationRequest(for request: LMRequest) throws -> FoundationModelGenerationRequest {
    try Self.validateSupportedFeatures(for: request)
    let conversation = try FoundationModelConversation(messages: request.messages)

    let profile = runtimeProfile()
    if request.parameters.reasoningEffort != nil, !profile.supportsReasoning {
      throw LMClientError(
        reason: .unsupported,
        debugDescription: "\(profile.modelIdentifier) does not support reasoning. Leave reasoningEffort nil or target Private Cloud Compute."
      )
    }
    if !conversation.images.isEmpty {
      guard profile.supportsVision else {
        throw LMClientError(
          reason: .unsupported,
          debugDescription: "\(profile.modelIdentifier) does not accept images."
        )
      }
      if conversation.images.contains(where: { $0.remoteURL != nil }) {
        throw LMClientError(
          reason: .unsupported,
          debugDescription: "Foundation Models reads images from data or local files, not remote URLs."
        )
      }
    }

    let responseMetadata = metadata(for: request)
    let prompt = CompiledPrompt(
      contract: PromptContract(
        id: request.metadata["promptID"] ?? "llm-request",
        version: responseMetadata.promptVersion,
        instructions: Self.instructions(for: request),
        responseSchemaDescription: request.responseFormat.foundationPromptDescription ?? ""
      ),
      contextPlan: request.contextPlan,
      metadata: responseMetadata,
      userPrompt: conversation.prompt
    )
    return FoundationModelGenerationRequest(
      prompt: prompt,
      options: FoundationModelGenerationOptions(
        sampling: request.parameters.temperature == 0 ? .greedy : .systemDefault,
        temperature: request.parameters.temperature,
        maximumResponseTokens: request.parameters.maxOutputTokens,
        includeSchemaInPrompt: true,
        executionTarget: defaultExecutionTarget,
        reasoningEffort: request.parameters.reasoningEffort
      ),
      useCase: defaultUseCase,
      history: conversation.history,
      images: conversation.images
    )
  }

  private static func response(from response: FoundationModelGenerationResponse<String>) -> LMResponse {
    LMResponse(
      text: response.content,
      finishReason: response.finishReason,
      tokenUsage: response.tokenUsage,
      model: response.metadata.modelIdentifier,
      metadata: response.metadata,
      reasoningText: response.reasoningText
    )
  }

  private func metadata(for request: LMRequest) -> LMProviderMetadata {
    var metadata = self.metadata
    if let promptVersion = request.metadata["promptVersion"] {
      metadata.promptVersion = promptVersion
    }
    return metadata
  }

  private static func validateSupportedFeatures(for request: LMRequest) throws {
    if !request.tools.isEmpty ||
      request.toolChoice?.requiresToolSupport == true ||
      request.messages.contains(where: { $0.role == .tool || !$0.toolCalls.isEmpty })
    {
      throw LMClientError(
        reason: .unsupported,
        debugDescription: "FoundationModelClient's provider-neutral LMClient adapter describes tool-call context, but native FoundationModels tool execution still requires typed Tool wrappers."
      )
    }

    if request.parameters.topP != nil {
      throw LMClientError(
        reason: .unsupported,
        debugDescription: "FoundationModelClient's provider-neutral LMClient adapter does not support top-p sampling."
      )
    }

    if !request.parameters.stopSequences.isEmpty {
      throw LMClientError(
        reason: .unsupported,
        debugDescription: "FoundationModelClient's provider-neutral LMClient adapter does not support stop sequences."
      )
    }
  }

  private static func instructions(for request: LMRequest) -> String {
    let roleInstructions = request.messages
      .filter { $0.role == .system || $0.role == .developer }
      .map(\.content)
      .joined(separator: "\n\n")
    return [request.instructions, roleInstructions, request.responseFormat.foundationPromptDescription]
      .compactMap { text in
        guard let text, !text.isEmpty else { return nil }
        return text
      }
      .joined(separator: "\n\n")
  }
}

/// Maps provider-neutral messages onto a Foundation Models transcript. Earlier user and assistant
/// messages become history turns, and the trailing user messages become the prompt.
struct FoundationModelConversation: Equatable {
  var history: [FoundationModelTranscriptTurn]
  var images: [LMImage]
  var prompt: String

  init(messages: [LMMessage]) throws {
    let turns = messages.filter { $0.role == .user || $0.role == .assistant }
    guard let last = turns.last else {
      throw LMClientError(
        reason: .badRequest,
        debugDescription: "Foundation Models requests need at least one user message."
      )
    }
    guard last.role == .user else {
      throw LMClientError(
        reason: .unsupported,
        debugDescription: "Foundation Models requests must end with a user message. Assistant prefill is not supported."
      )
    }

    let promptStart = turns.lastIndex { $0.role != .user }.map { $0 + 1 } ?? 0
    let promptMessages = turns[promptStart...]
    self.prompt = promptMessages.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n\n")
    self.images = promptMessages.flatMap(\.images)

    var history: [FoundationModelTranscriptTurn] = []
    for message in turns[..<promptStart] {
      guard message.images.isEmpty else {
        throw LMClientError(
          reason: .unsupported,
          debugDescription: "Foundation Models accepts images only in the latest user message."
        )
      }
      guard !message.content.isEmpty else { continue }
      let role: FoundationModelTranscriptTurn.Role = message.role == .user ? .prompt : .response
      if let lastTurn = history.last, lastTurn.role == role {
        history[history.count - 1].text += "\n\n" + message.content
      } else {
        history.append(FoundationModelTranscriptTurn(role: role, text: message.content))
      }
    }
    self.history = history
  }
}

private extension LMResponseFormat {
  var foundationPromptDescription: String? {
    switch self {
    case .text:
      return nil
    case .jsonObject:
      return "Return only valid JSON."
    case let .jsonSchema(schema):
      let encodedSchema = (try? JSONEncoder.foundationPromptEncoder.encode(schema.schema))
        .map { String(decoding: $0, as: UTF8.self) }
        ?? "{}"
      return """
      Return only valid JSON matching this schema.
      Schema name: \(schema.name)
      \(schema.description.map { "Description: \($0)\n" } ?? "")Schema:
      \(encodedSchema)
      """
    }
  }
}

private extension JSONEncoder {
  static var foundationPromptEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
