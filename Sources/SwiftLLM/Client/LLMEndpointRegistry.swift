import Foundation

public struct LLMEndpointID: Codable, Equatable, ExpressibleByStringLiteral, Hashable, RawRepresentable, Sendable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}

public struct LLMEndpoint: Identifiable, Sendable {
  public var client: AnyLLMClient
  public var id: LLMEndpointID
  public var isEnabled: Bool
  public var priority: Int
  public var tags: Set<String>

  public init(
    id: LLMEndpointID,
    client: AnyLLMClient,
    priority: Int = 0,
    isEnabled: Bool = true,
    tags: Set<String> = []
  ) {
    self.client = client
    self.id = id
    self.isEnabled = isEnabled
    self.priority = priority
    self.tags = tags
  }
}

public struct LLMRoutingPlan: Sendable {
  public var fallbackIDs: [LLMEndpointID]
  public var fallbackPolicy: LLMRouterFallbackPolicy
  public var primaryID: LLMEndpointID?
  public var runReceiptHandler: (@Sendable (LLMRunReceipt) -> Void)?
  public var streamFallbackMode: LLMStreamFallbackMode
  public var usesRemainingEnabledEndpointsAsFallbacks: Bool

  public init(
    primaryID: LLMEndpointID? = nil,
    fallbackIDs: [LLMEndpointID] = [],
    usesRemainingEnabledEndpointsAsFallbacks: Bool = true,
    fallbackPolicy: LLMRouterFallbackPolicy = .retryable,
    streamFallbackMode: LLMStreamFallbackMode = .beforeFirstOutput,
    runReceiptHandler: (@Sendable (LLMRunReceipt) -> Void)? = nil
  ) {
    self.fallbackIDs = fallbackIDs
    self.fallbackPolicy = fallbackPolicy
    self.primaryID = primaryID
    self.runReceiptHandler = runReceiptHandler
    self.streamFallbackMode = streamFallbackMode
    self.usesRemainingEnabledEndpointsAsFallbacks = usesRemainingEnabledEndpointsAsFallbacks
  }

  public static let priorityOrder = Self()
}

public enum LLMEndpointRegistryError: Equatable, LocalizedError, Sendable {
  case endpointDisabled(String)
  case endpointNotFound(String)
  case noEnabledEndpoints

  public var errorDescription: String? {
    switch self {
    case let .endpointDisabled(id):
      return "The endpoint \(id) is disabled."
    case let .endpointNotFound(id):
      return "The endpoint \(id) was not registered."
    case .noEnabledEndpoints:
      return "No enabled endpoints were registered."
    }
  }
}

public struct LLMEndpointRegistry: Sendable {
  public private(set) var endpoints: [LLMEndpoint]

  public init(endpoints: [LLMEndpoint] = []) {
    self.endpoints = endpoints
  }

  public mutating func register(_ endpoint: LLMEndpoint) {
    remove(endpoint.id)
    endpoints.append(endpoint)
  }

  @discardableResult
  public mutating func remove(_ id: LLMEndpointID) -> LLMEndpoint? {
    guard let index = endpoints.firstIndex(where: { $0.id == id }) else {
      return nil
    }
    return endpoints.remove(at: index)
  }

  public func endpoint(id: LLMEndpointID) -> LLMEndpoint? {
    endpoints.first { $0.id == id }
  }

  public func enabledEndpoints() -> [LLMEndpoint] {
    endpoints
      .filter(\.isEnabled)
      .sortedByPriority()
  }

  public func client(id: LLMEndpointID) throws -> AnyLLMClient {
    guard let endpoint = endpoint(id: id) else {
      throw LLMEndpointRegistryError.endpointNotFound(id.rawValue)
    }
    guard endpoint.isEnabled else {
      throw LLMEndpointRegistryError.endpointDisabled(id.rawValue)
    }
    return endpoint.client
  }

  /// Builds a router pinned to `primaryID`.
  ///
  /// Fallbacks are explicit: pass `fallbackIDs`, or set
  /// `usesRemainingEnabledEndpointsAsFallbacks` to opt into every other enabled endpoint. A
  /// local-only primary never escalates to a cloud endpoint unless the caller asked for it.
  public func router(
    primaryID: LLMEndpointID,
    fallbackIDs: [LLMEndpointID] = [],
    usesRemainingEnabledEndpointsAsFallbacks: Bool = false,
    fallbackPolicy: LLMRouterFallbackPolicy = .retryable,
    streamFallbackMode: LLMStreamFallbackMode = .beforeFirstOutput,
    runReceiptHandler: (@Sendable (LLMRunReceipt) -> Void)? = nil
  ) throws -> LLMRouter {
    try router(
      plan: LLMRoutingPlan(
        primaryID: primaryID,
        fallbackIDs: fallbackIDs,
        usesRemainingEnabledEndpointsAsFallbacks: usesRemainingEnabledEndpointsAsFallbacks,
        fallbackPolicy: fallbackPolicy,
        streamFallbackMode: streamFallbackMode,
        runReceiptHandler: runReceiptHandler
      )
    )
  }

  public func router(plan: LLMRoutingPlan = .priorityOrder) throws -> LLMRouter {
    let enabled = enabledEndpoints()
    guard !enabled.isEmpty else {
      throw LLMEndpointRegistryError.noEnabledEndpoints
    }

    let primary = try primaryEndpoint(for: plan, enabledEndpoints: enabled)
    let fallbacks = try fallbackEndpoints(
      for: plan,
      primary: primary,
      enabledEndpoints: enabled
    )

    return LLMRouter(
      primary: primary.client,
      fallbacks: fallbacks.map(\.client),
      fallbackPolicy: plan.fallbackPolicy,
      runReceiptHandler: plan.runReceiptHandler,
      streamFallbackMode: plan.streamFallbackMode
    )
  }

  private func primaryEndpoint(
    for plan: LLMRoutingPlan,
    enabledEndpoints: [LLMEndpoint]
  ) throws -> LLMEndpoint {
    guard let primaryID = plan.primaryID else {
      return enabledEndpoints[0]
    }
    guard let endpoint = endpoint(id: primaryID) else {
      throw LLMEndpointRegistryError.endpointNotFound(primaryID.rawValue)
    }
    guard endpoint.isEnabled else {
      throw LLMEndpointRegistryError.endpointDisabled(primaryID.rawValue)
    }
    return endpoint
  }

  private func fallbackEndpoints(
    for plan: LLMRoutingPlan,
    primary: LLMEndpoint,
    enabledEndpoints: [LLMEndpoint]
  ) throws -> [LLMEndpoint] {
    if !plan.fallbackIDs.isEmpty {
      var seenIDs: Set<LLMEndpointID> = [primary.id]
      return try plan.fallbackIDs.compactMap { id in
        guard seenIDs.insert(id).inserted else { return nil }
        guard let endpoint = endpoint(id: id) else {
          throw LLMEndpointRegistryError.endpointNotFound(id.rawValue)
        }
        guard endpoint.isEnabled else {
          throw LLMEndpointRegistryError.endpointDisabled(id.rawValue)
        }
        return endpoint
      }
    }

    guard plan.usesRemainingEnabledEndpointsAsFallbacks else {
      return []
    }

    return enabledEndpoints.filter { $0.id != primary.id }
  }
}

private extension Array where Element == LLMEndpoint {
  func sortedByPriority() -> [LLMEndpoint] {
    sorted { lhs, rhs in
      if lhs.priority != rhs.priority {
        return lhs.priority < rhs.priority
      }
      return lhs.id.rawValue < rhs.id.rawValue
    }
  }
}
