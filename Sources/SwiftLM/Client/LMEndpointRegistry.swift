import Foundation

public struct LMEndpointID: Codable, Equatable, ExpressibleByStringLiteral, Hashable, RawRepresentable, Sendable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}

public struct LMEndpoint: Identifiable, Sendable {
  public var client: AnyLMClient
  public var id: LMEndpointID
  public var isEnabled: Bool
  public var priority: Int
  public var tags: Set<String>

  public init(
    id: LMEndpointID,
    client: AnyLMClient,
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

public struct LMRoutingPlan: Sendable {
  public var fallbackIDs: [LMEndpointID]
  public var fallbackPolicy: LMRouterFallbackPolicy
  public var primaryID: LMEndpointID?
  public var runReceiptHandler: (@Sendable (LMRunReceipt) -> Void)?
  public var streamFallbackMode: LMStreamFallbackMode
  public var usesRemainingEnabledEndpointsAsFallbacks: Bool

  public init(
    primaryID: LMEndpointID? = nil,
    fallbackIDs: [LMEndpointID] = [],
    usesRemainingEnabledEndpointsAsFallbacks: Bool = true,
    fallbackPolicy: LMRouterFallbackPolicy = .retryable,
    streamFallbackMode: LMStreamFallbackMode = .beforeFirstOutput,
    runReceiptHandler: (@Sendable (LMRunReceipt) -> Void)? = nil
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

public enum LMEndpointRegistryError: Equatable, LocalizedError, Sendable {
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

public struct LMEndpointRegistry: Sendable {
  public private(set) var endpoints: [LMEndpoint]

  public init(endpoints: [LMEndpoint] = []) {
    self.endpoints = endpoints
  }

  public mutating func register(_ endpoint: LMEndpoint) {
    remove(endpoint.id)
    endpoints.append(endpoint)
  }

  @discardableResult
  public mutating func remove(_ id: LMEndpointID) -> LMEndpoint? {
    guard let index = endpoints.firstIndex(where: { $0.id == id }) else {
      return nil
    }
    return endpoints.remove(at: index)
  }

  public func endpoint(id: LMEndpointID) -> LMEndpoint? {
    endpoints.first { $0.id == id }
  }

  public func enabledEndpoints() -> [LMEndpoint] {
    endpoints
      .filter(\.isEnabled)
      .sortedByPriority()
  }

  public func client(id: LMEndpointID) throws -> AnyLMClient {
    guard let endpoint = endpoint(id: id) else {
      throw LMEndpointRegistryError.endpointNotFound(id.rawValue)
    }
    guard endpoint.isEnabled else {
      throw LMEndpointRegistryError.endpointDisabled(id.rawValue)
    }
    return endpoint.client
  }

  /// Builds a router pinned to `primaryID`.
  ///
  /// Fallbacks are explicit: pass `fallbackIDs`, or set
  /// `usesRemainingEnabledEndpointsAsFallbacks` to opt into every other enabled endpoint. A
  /// local-only primary never escalates to a cloud endpoint unless the caller asked for it.
  public func router(
    primaryID: LMEndpointID,
    fallbackIDs: [LMEndpointID] = [],
    usesRemainingEnabledEndpointsAsFallbacks: Bool = false,
    fallbackPolicy: LMRouterFallbackPolicy = .retryable,
    streamFallbackMode: LMStreamFallbackMode = .beforeFirstOutput,
    runReceiptHandler: (@Sendable (LMRunReceipt) -> Void)? = nil
  ) throws -> LMRouter {
    try router(
      plan: LMRoutingPlan(
        primaryID: primaryID,
        fallbackIDs: fallbackIDs,
        usesRemainingEnabledEndpointsAsFallbacks: usesRemainingEnabledEndpointsAsFallbacks,
        fallbackPolicy: fallbackPolicy,
        streamFallbackMode: streamFallbackMode,
        runReceiptHandler: runReceiptHandler
      )
    )
  }

  public func router(plan: LMRoutingPlan = .priorityOrder) throws -> LMRouter {
    let enabled = enabledEndpoints()
    guard !enabled.isEmpty else {
      throw LMEndpointRegistryError.noEnabledEndpoints
    }

    let primary = try primaryEndpoint(for: plan, enabledEndpoints: enabled)
    let fallbacks = try fallbackEndpoints(
      for: plan,
      primary: primary,
      enabledEndpoints: enabled
    )

    return LMRouter(
      primary: primary.client,
      fallbacks: fallbacks.map(\.client),
      fallbackPolicy: plan.fallbackPolicy,
      runReceiptHandler: plan.runReceiptHandler,
      streamFallbackMode: plan.streamFallbackMode
    )
  }

  private func primaryEndpoint(
    for plan: LMRoutingPlan,
    enabledEndpoints: [LMEndpoint]
  ) throws -> LMEndpoint {
    guard let primaryID = plan.primaryID else {
      return enabledEndpoints[0]
    }
    guard let endpoint = endpoint(id: primaryID) else {
      throw LMEndpointRegistryError.endpointNotFound(primaryID.rawValue)
    }
    guard endpoint.isEnabled else {
      throw LMEndpointRegistryError.endpointDisabled(primaryID.rawValue)
    }
    return endpoint
  }

  private func fallbackEndpoints(
    for plan: LMRoutingPlan,
    primary: LMEndpoint,
    enabledEndpoints: [LMEndpoint]
  ) throws -> [LMEndpoint] {
    if !plan.fallbackIDs.isEmpty {
      var seenIDs: Set<LMEndpointID> = [primary.id]
      return try plan.fallbackIDs.compactMap { id in
        guard seenIDs.insert(id).inserted else { return nil }
        guard let endpoint = endpoint(id: id) else {
          throw LMEndpointRegistryError.endpointNotFound(id.rawValue)
        }
        guard endpoint.isEnabled else {
          throw LMEndpointRegistryError.endpointDisabled(id.rawValue)
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

private extension Array where Element == LMEndpoint {
  func sortedByPriority() -> [LMEndpoint] {
    sorted { lhs, rhs in
      if lhs.priority != rhs.priority {
        return lhs.priority < rhs.priority
      }
      return lhs.id.rawValue < rhs.id.rawValue
    }
  }
}
