// A stub of the OS 27 FoundationModels API surface used by SwiftLMFoundationModels, transcribed
// from Apple's documentation. Only the declarations the adapter touches are present.
import Foundation

public protocol PromptRepresentable {}
public protocol InstructionsRepresentable {}
public protocol ConvertibleToGeneratedContent: Sendable {}
extension String: PromptRepresentable, InstructionsRepresentable, ConvertibleToGeneratedContent {}

public protocol Generable: Sendable {
  associatedtype PartiallyGenerated: Sendable = Self
}
extension String: Generable {}

public struct Prompt: Sendable, PromptRepresentable {
  public init(_ content: some PromptRepresentable) {}
}

public struct Instructions: Sendable, InstructionsRepresentable {
  public init(_ content: some InstructionsRepresentable) {}
}

public protocol Tool: Sendable {
  var name: String { get }
  var description: String { get }
}

public struct LanguageModelCapabilities: Sendable {
  public struct Capability: Sendable, Hashable {
    public static var guidedGeneration: Capability { Capability() }
    public static var reasoning: Capability { Capability() }
    public static var toolCalling: Capability { Capability() }
    public static var vision: Capability { Capability() }
  }
  public func contains(_ capability: Capability) -> Bool { true }
}

public protocol LanguageModel: Sendable {
  var capabilities: LanguageModelCapabilities { get }
}

public final class SystemLanguageModel: LanguageModel, Sendable {
  public struct UseCase: Sendable, Equatable {
    public static let general = UseCase()
    public static let contentTagging = UseCase()
  }
  public enum Availability: Sendable {
    public enum UnavailableReason: Sendable { case appleIntelligenceNotEnabled, deviceNotEligible, modelNotReady }
    case available
    case unavailable(UnavailableReason)
  }
  public enum Error: Swift.Error {
    public struct AssetsUnavailable: Sendable { public var debugDescription: String }
    case assetsUnavailable(AssetsUnavailable)
    case futureCase
  }

  public static let `default` = SystemLanguageModel()
  public init() {}
  public convenience init(useCase: UseCase) { self.init() }
  public var availability: Availability { .available }
  public var capabilities: LanguageModelCapabilities { LanguageModelCapabilities() }
  public var contextSize: Int { 8_192 }
  public func supportsLocale(_ locale: Locale) -> Bool { true }
  public func tokenCount(for prompt: some PromptRepresentable) async throws -> Int { 0 }
  public func tokenCount(for instructions: Instructions) async throws -> Int { 0 }
  public func tokenCount(for tools: [any Tool]) async throws -> Int { 0 }
}

public final class PrivateCloudComputeLanguageModel: LanguageModel, Sendable {
  public enum Availability: Sendable {
    public enum UnavailableReason: Sendable { case deviceNotEligible, systemNotReady }
    case available
    case unavailable(UnavailableReason)
  }
  public struct QuotaUsage: Sendable {
    public struct LimitIncreaseSuggestion: Sendable { public func show() {} }
    public struct Info: Sendable { public var isApproachingLimit: Bool }
    public enum Status: Sendable { case belowLimit(Info), limitReached }
    public var isLimitReached: Bool
    public var limitIncreaseSuggestion: LimitIncreaseSuggestion?
    public var resetDate: Date?
    public var status: Status
  }
  public enum Error: Swift.Error {
    public struct QuotaLimitReached: Sendable {
      public var limitIncreaseSuggestion: QuotaUsage.LimitIncreaseSuggestion?
      public var resetDate: Date?
      public var debugDescription: String
    }
    public struct NetworkFailure: Sendable { public var debugDescription: String }
    public struct ServiceUnavailable: Sendable { public var debugDescription: String }
    case quotaLimitReached(QuotaLimitReached)
    case networkFailure(NetworkFailure)
    case serviceUnavailable(ServiceUnavailable)
    case futureCase
  }

  public init() {}
  public var availability: Availability { .available }
  public var capabilities: LanguageModelCapabilities { LanguageModelCapabilities() }
  public var contextSize: Int { 32_768 }
  public var quotaUsage: QuotaUsage {
    QuotaUsage(isLimitReached: false, limitIncreaseSuggestion: nil, resetDate: nil, status: .belowLimit(.init(isApproachingLimit: false)))
  }
  public func supportsLocale(_ locale: Locale = .current) async throws -> Bool { true }
}

public struct GenerationOptions: Sendable {
  public struct SamplingMode: Sendable {
    public static var greedy: SamplingMode { SamplingMode() }
    public static func random(top: Int, seed: UInt64?) -> SamplingMode { SamplingMode() }
    public static func random(probabilityThreshold: Double, seed: UInt64?) -> SamplingMode { SamplingMode() }
  }
  public struct ToolCallingMode: Sendable {
    public static let allowed = ToolCallingMode()
    public static let disallowed = ToolCallingMode()
    public static let required = ToolCallingMode()
  }
  public init(sampling: SamplingMode? = nil, temperature: Double? = nil, maximumResponseTokens: Int? = nil) {}
  public init(samplingMode: SamplingMode?, temperature: Double?, maximumResponseTokens: Int?, toolCallingMode: ToolCallingMode?) {}
}

public struct ContextOptions: Sendable {
  public enum ReasoningLevel: Sendable { case light, moderate, deep, custom(String) }
  public init(includeSchemaInPrompt: Bool?, reasoningLevel: ReasoningLevel?) {}
}

public struct Transcript: Sendable {
  public struct TextSegment: Sendable { public var content: String }
  public struct StructuredSegment: Sendable {}
  public enum Segment: Sendable { case text(TextSegment), structure(StructuredSegment) }
  public struct Reasoning: Sendable { public var segments: [Segment] }
  public struct Other: Sendable {}
  public enum Entry: Sendable {
    case instructions(Other), prompt(Other), response(Other), reasoning(Reasoning), toolCalls(Other), toolOutput(Other), data(Other)
  }
}

public enum LanguageModelError: Swift.Error {
  public struct ContextSizeExceeded: Sendable { public var contextSize: Int; public var tokenCount: Int; public var debugDescription: String }
  public struct RateLimited: Sendable { public var resetDate: Date?; public var debugDescription: String }
  public struct Refusal: Sendable {
    public var debugDescription: String
    public var explanation: LanguageModelSession.Response<String> { get async throws { LanguageModelSession.Response(content: "") } }
  }
  public struct Timeout: Sendable { public var debugDescription: String }
  public struct GuardrailViolation: Sendable { public var debugDescription: String }
  public struct UnsupportedCapability: Sendable { public var debugDescription: String }
  public struct UnsupportedTranscriptContent: Sendable { public var debugDescription: String }
  public struct UnsupportedGenerationGuide: Sendable { public var debugDescription: String }
  public struct UnsupportedLanguageOrLocale: Sendable { public var debugDescription: String }
  case contextSizeExceeded(ContextSizeExceeded)
  case rateLimited(RateLimited)
  case refusal(Refusal)
  case timeout(Timeout)
  case guardrailViolation(GuardrailViolation)
  case unsupportedCapability(UnsupportedCapability)
  case unsupportedTranscriptContent(UnsupportedTranscriptContent)
  case unsupportedGenerationGuide(UnsupportedGenerationGuide)
  case unsupportedLanguageOrLocale(UnsupportedLanguageOrLocale)
  case futureCase
}

public final class LanguageModelSession: @unchecked Sendable {
  public struct Usage: Sendable {
    public struct Input: Sendable { public var totalTokenCount: Int; public var cachedTokenCount: Int }
    public struct Output: Sendable { public var totalTokenCount: Int; public var reasoningTokenCount: Int }
    public var input = Input(totalTokenCount: 0, cachedTokenCount: 0)
    public var output = Output(totalTokenCount: 0, reasoningTokenCount: 0)
  }
  public struct Response<Content: Sendable>: Sendable {
    public var content: Content
    public var usage = Usage()
    public var transcriptEntries: ArraySlice<Transcript.Entry> = []
    public init(content: Content) { self.content = content }
  }
  public struct ResponseStream<Content: Generable>: AsyncSequence, Sendable {
    public struct Snapshot: Sendable {
      public var content: Content.PartiallyGenerated
      public var usage = Usage()
      public var transcriptEntries: ArraySlice<Transcript.Entry> = []
    }
    public typealias Element = Snapshot
    public struct AsyncIterator: AsyncIteratorProtocol {
      public mutating func next() async throws -> Snapshot? { nil }
    }
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
  }
  public enum GenerationError: Swift.Error {
    public struct Context: Sendable { public var debugDescription: String }
    public struct Refusal: Sendable {
      public var explanation: Response<String> { get async throws { Response(content: "") } }
    }
    case assetsUnavailable(Context)
    case decodingFailure(Context)
    case exceededContextWindowSize(Context)
    case guardrailViolation(Context)
    case rateLimited(Context)
    case refusal(Refusal, Context)
    case concurrentRequests(Context)
    case unsupportedGuide(Context)
    case unsupportedLanguageOrLocale(Context)
  }
  public struct ToolCallError: Swift.Error, LocalizedError {
    public var tool: any Tool
    public var underlyingError: any Swift.Error
    public var errorDescription: String? { nil }
  }
  public enum Error: Swift.Error {
    case concurrentRequests
    case transcriptMutationWhileResponding
    case futureCase
  }

  public convenience init(model: some LanguageModel = SystemLanguageModel.default, tools: [any Tool] = [], instructions: String? = nil) { self.init() }
  public init() {}
  public func prewarm(promptPrefix: Prompt?) {}
  public func respond(to prompt: Prompt, options: GenerationOptions = GenerationOptions()) async throws -> Response<String> { Response(content: "") }
  public func respond<Content: Generable>(to prompt: Prompt, generating type: Content.Type, includeSchemaInPrompt: Bool = true, options: GenerationOptions = GenerationOptions()) async throws -> Response<Content> { fatalError() }
  public func respond(to prompt: Prompt, options: GenerationOptions, contextOptions: ContextOptions, metadata: [String: any ConvertibleToGeneratedContent]) async throws -> Response<String> { Response(content: "") }
  public func respond<Content: Generable>(to prompt: Prompt, generating type: Content.Type, options: GenerationOptions, contextOptions: ContextOptions, metadata: [String: any ConvertibleToGeneratedContent]) async throws -> Response<Content> { fatalError() }
  public func streamResponse(to prompt: Prompt, options: GenerationOptions = GenerationOptions()) -> ResponseStream<String> { ResponseStream() }
  public func streamResponse(to prompt: Prompt, options: GenerationOptions, contextOptions: ContextOptions, metadata: [String: any ConvertibleToGeneratedContent]) -> ResponseStream<String> { ResponseStream() }
}
