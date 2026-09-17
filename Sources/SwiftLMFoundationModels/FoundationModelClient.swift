import Foundation
import SwiftLM

/// The typed Foundation Models adapter.
///
/// Every capability is a closure so tests can supply fakes without the framework. `live` wires
/// the closures to Apple's `FoundationModels` framework when it can be imported. The adapter is
/// local-first: `automatic` resolves to the on-device model, and Private Cloud Compute runs only
/// when a request or client explicitly targets it.
public struct FoundationModelClient: Sendable {
  public typealias AvailabilityCheck =
    @Sendable (Locale?, FoundationModelUseCase) -> FoundationModelAvailability
  public typealias ExecutionTargetAvailabilityCheck =
    @Sendable (FoundationModelExecutionTarget, Locale?, FoundationModelUseCase) async
      -> FoundationModelAvailability
  public typealias RuntimeProfileResolver =
    @Sendable (FoundationModelExecutionTarget, FoundationModelUseCase) -> FoundationModelRuntimeProfile
  public typealias ReportedRuntimeProfileResolver =
    @Sendable (FoundationModelExecutionTarget, FoundationModelUseCase) async -> FoundationModelRuntimeProfile
  public typealias StreamHandler =
    @Sendable (FoundationModelGenerationRequest)
      -> AsyncThrowingStream<FoundationModelStreamEvent, any Error>

  /// Synchronous on-device availability. Use `availability(for:)` for other targets, because
  /// Private Cloud Compute locale support is an async platform call.
  public var checkAvailability: AvailabilityCheck
  public var checkExecutionTargetAvailability: ExecutionTargetAvailabilityCheck
  public var countTokens: @Sendable (FoundationModelTokenCountRequest) async throws -> Int
  /// The execution target the provider-neutral `LMClient` conformance uses.
  public var defaultExecutionTarget: FoundationModelExecutionTarget
  /// The use case the provider-neutral `LMClient` conformance uses.
  public var defaultUseCase: FoundationModelUseCase
  public var prewarm: @Sendable (FoundationModelPrewarmRequest) async throws -> Void
  /// Resolves the profile the platform reports asynchronously, such as the Private Cloud Compute
  /// context size.
  public var resolveReportedRuntimeProfile: ReportedRuntimeProfileResolver
  /// Resolves the profile the platform reports synchronously. Values that are only available
  /// asynchronously use Apple's documented defaults.
  public var resolveRuntimeProfile: RuntimeProfileResolver
  public var respond: @Sendable (FoundationModelGenerationRequest) async throws
    -> FoundationModelGenerationResponse<String>
  public var streamResponse: StreamHandler
  /// The live session source behind the typed Foundation Models APIs. `nil` means Apple's system
  /// models. It is type-erased so this file compiles without the framework.
  var sessionSource: FoundationModelSessionSourceBox?

  public init(
    checkAvailability: @escaping AvailabilityCheck,
    countTokens: @escaping @Sendable (FoundationModelTokenCountRequest) async throws -> Int,
    prewarm: @escaping @Sendable (FoundationModelPrewarmRequest) async throws -> Void,
    respond: @escaping @Sendable (FoundationModelGenerationRequest) async throws
      -> FoundationModelGenerationResponse<String>,
    checkExecutionTargetAvailability: ExecutionTargetAvailabilityCheck? = nil,
    resolveRuntimeProfile: RuntimeProfileResolver? = nil,
    resolveReportedRuntimeProfile: ReportedRuntimeProfileResolver? = nil,
    streamResponse: StreamHandler? = nil,
    defaultExecutionTarget: FoundationModelExecutionTarget = .automatic,
    defaultUseCase: FoundationModelUseCase = .general
  ) {
    self.checkAvailability = checkAvailability
    self.checkExecutionTargetAvailability = checkExecutionTargetAvailability
      ?? { _, locale, useCase in checkAvailability(locale, useCase) }
    self.countTokens = countTokens
    self.defaultExecutionTarget = defaultExecutionTarget
    self.defaultUseCase = defaultUseCase
    self.prewarm = prewarm
    let resolveRuntimeProfile = resolveRuntimeProfile ?? { target, _ in .preset(for: target) }
    self.resolveRuntimeProfile = resolveRuntimeProfile
    self.resolveReportedRuntimeProfile = resolveReportedRuntimeProfile ?? { target, useCase in
      resolveRuntimeProfile(target, useCase)
    }
    self.respond = respond
    self.streamResponse = streamResponse ?? { request in
      Self.derivedStream(for: request, respond: respond)
    }
  }

  /// On-device availability for the given locale and use case.
  public func availability(
    locale: Locale? = nil,
    useCase: FoundationModelUseCase = .general
  ) -> FoundationModelAvailability {
    checkAvailability(locale, useCase)
  }

  /// Availability for any execution target, including Private Cloud Compute quota state.
  public func availability(
    for target: FoundationModelExecutionTarget,
    locale: Locale? = nil,
    useCase: FoundationModelUseCase = .general
  ) async -> FoundationModelAvailability {
    await checkExecutionTargetAvailability(target, locale, useCase)
  }

  /// The runtime facts the platform reports synchronously: context window, capabilities, and
  /// quota. Private Cloud Compute reports its context size only asynchronously, so this profile
  /// uses Apple's documented 32K window for it; use `reportedRuntimeProfile(for:useCase:)` for the
  /// platform value.
  public func runtimeProfile(
    for target: FoundationModelExecutionTarget? = nil,
    useCase: FoundationModelUseCase? = nil
  ) -> FoundationModelRuntimeProfile {
    resolveRuntimeProfile(target ?? defaultExecutionTarget, useCase ?? defaultUseCase)
  }

  /// The runtime facts including values the platform reports asynchronously.
  public func reportedRuntimeProfile(
    for target: FoundationModelExecutionTarget? = nil,
    useCase: FoundationModelUseCase? = nil
  ) async -> FoundationModelRuntimeProfile {
    await resolveReportedRuntimeProfile(target ?? defaultExecutionTarget, useCase ?? defaultUseCase)
  }

  /// Streams a text response as deltas followed by the completed response.
  public func stream(
    _ request: FoundationModelGenerationRequest
  ) -> AsyncThrowingStream<FoundationModelStreamEvent, any Error> {
    streamResponse(request)
  }

  /// A copy of this client whose provider-neutral conformance targets a different model.
  public func targeting(_ target: FoundationModelExecutionTarget) -> Self {
    var copy = self
    copy.defaultExecutionTarget = target
    return copy
  }

  public func tokenCounter(
    useCase: FoundationModelUseCase = .general
  ) -> TokenCounter {
    TokenCounter { text in
      // TokenCounter is synchronous. Use the live async `countTokens` API when exact
      // Foundation Models accounting is required.
      TokenCounter.latinHeuristic.count(text)
    }
  }

  public static let unavailable = Self(
    checkAvailability: { _, _ in .unavailableInBuild },
    countTokens: { request in
      TokenCounter.latinHeuristic.count(request.text)
    },
    prewarm: { _ in
      throw FoundationModelFailure(reason: .unavailable(.unavailableInBuild))
    },
    respond: { _ in
      throw FoundationModelFailure(reason: .unavailable(.unavailableInBuild))
    }
  )

  /// A client for Apple's system models: the on-device model and, on the OS 27 releases, Private
  /// Cloud Compute.
  public static let live: Self = {
    #if canImport(FoundationModels)
    Self.makeLive(source: .system)
    #else
    Self.unavailable
    #endif
  }()

  static func derivedStream(
    for request: FoundationModelGenerationRequest,
    respond: @escaping @Sendable (FoundationModelGenerationRequest) async throws
      -> FoundationModelGenerationResponse<String>
  ) -> AsyncThrowingStream<FoundationModelStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let response = try await respond(request)
          continuation.yield(.textDelta(response.content))
          continuation.yield(.completed(response))
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
}

/// Type-erased storage for a live session source, so the framework-independent client can carry it.
struct FoundationModelSessionSourceBox: Sendable {
  var value: any Sendable
}
