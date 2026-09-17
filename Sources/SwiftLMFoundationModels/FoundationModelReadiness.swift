import Foundation
import SwiftLM

/// Where a Foundation Models request executes.
public enum FoundationModelExecutionTarget: Equatable, Hashable, Sendable {
  /// Resolves to the on-device system model. The package is local-first, so `automatic` never
  /// escalates to Private Cloud Compute on its own; apps choose that target explicitly.
  case automatic
  /// Apple's on-device system language model.
  case onDevice
  /// Apple's server model on Private Cloud Compute. It requires the OS 27 releases, Apple
  /// Intelligence, a network connection, the managed entitlement, and a per-user daily quota.
  case privateCloudCompute
  /// A third-party `LanguageModel` provider package. Reserved for a future bridge.
  case providerPackage(String)
  /// A custom on-device model such as Core AI or MLX. Reserved for a future bridge.
  case customLocal(String)

  public var diagnosticName: String {
    switch self {
    case .automatic:
      return "automatic"
    case .onDevice:
      return "onDevice"
    case .privateCloudCompute:
      return "privateCloudCompute"
    case let .providerPackage(identifier):
      return "providerPackage:\(identifier)"
    case let .customLocal(identifier):
      return "customLocal:\(identifier)"
    }
  }

  /// The model identifier the adapter reports in provider metadata for this target.
  public var defaultModelIdentifier: String {
    switch self {
    case .automatic, .onDevice:
      return "SystemLanguageModel.default"
    case .privateCloudCompute:
      return "PrivateCloudComputeLanguageModel"
    case let .providerPackage(identifier), let .customLocal(identifier):
      return identifier
    }
  }

  public var privacyMode: LMPrivacyMode {
    switch self {
    case .automatic, .onDevice, .customLocal:
      return .localOnly
    case .privateCloudCompute:
      return .privateCloudCompute
    case .providerPackage:
      return .externalOptIn
    }
  }

  /// A conservative context window used only when the platform cannot report `contextSize`.
  public var fallbackContextWindowTokens: Int? {
    switch self {
    case .automatic, .onDevice:
      return FoundationModelDefaults.onDeviceContextWindowTokens
    case .privateCloudCompute:
      return FoundationModelDefaults.privateCloudContextWindowTokens
    case .providerPackage, .customLocal:
      return nil
    }
  }

  public var requiresNetworkExecution: Bool {
    switch self {
    case .privateCloudCompute, .providerPackage:
      return true
    case .automatic, .customLocal, .onDevice:
      return false
    }
  }

  /// Whether the live adapter can execute this target. Provider packages and custom local models
  /// are descriptive today and need a future bridge before the live adapter can run them.
  public var isSupportedByLiveAdapter: Bool {
    switch self {
    case .automatic, .onDevice, .privateCloudCompute:
      return true
    case .providerPackage, .customLocal:
      return false
    }
  }
}

/// Quota state for metered execution targets such as Private Cloud Compute.
public enum FoundationModelQuotaStatus: Equatable, Sendable {
  case available
  /// Generation still works, but the app should show persistent usage UI.
  case approachingLimit(resetsAt: Date? = nil)
  /// Generation fails until the quota resets or the person upgrades their allotment.
  case exhausted(resetsAt: Date? = nil, limitIncreaseSuggestionAvailable: Bool = false)
  /// The target is not metered, such as the on-device model.
  case notApplicable
  case unknown

  public var permitsGeneration: Bool {
    switch self {
    case .available, .approachingLimit, .notApplicable, .unknown:
      return true
    case .exhausted:
      return false
    }
  }

  public var isApproachingLimit: Bool {
    if case .approachingLimit = self { return true }
    return false
  }

  public var isLimitReached: Bool {
    if case .exhausted = self { return true }
    return false
  }

  public var resetsAt: Date? {
    switch self {
    case let .approachingLimit(resetsAt), let .exhausted(resetsAt, _):
      return resetsAt
    case .available, .notApplicable, .unknown:
      return nil
    }
  }

  /// Whether the platform can present an upgrade path, such as an iCloud+ offer, for more usage.
  public var limitIncreaseSuggestionAvailable: Bool {
    if case let .exhausted(_, available) = self { return available }
    return false
  }
}

/// The runtime facts the adapter resolved for one execution target.
///
/// The live adapter fills this from the platform: `contextSize`, model capabilities, and Private
/// Cloud Compute quota. Presets describe Apple's documented defaults for tests and planning.
public struct FoundationModelRuntimeProfile: Equatable, Sendable {
  public var contextWindowTokens: Int?
  public var executionTarget: FoundationModelExecutionTarget
  /// `true` when `contextWindowTokens` came from the platform rather than a documented default.
  public var isContextWindowReported: Bool
  public var modelIdentifier: String
  public var quotaStatus: FoundationModelQuotaStatus
  public var supportsGuidedGeneration: Bool
  public var supportsReasoning: Bool
  public var supportsToolCalling: Bool
  public var supportsVision: Bool

  public init(
    executionTarget: FoundationModelExecutionTarget = .automatic,
    modelIdentifier: String? = nil,
    contextWindowTokens: Int? = nil,
    isContextWindowReported: Bool = false,
    supportsReasoning: Bool = false,
    supportsToolCalling: Bool = true,
    supportsGuidedGeneration: Bool = true,
    supportsVision: Bool = false,
    quotaStatus: FoundationModelQuotaStatus = .unknown
  ) {
    self.contextWindowTokens = contextWindowTokens ?? executionTarget.fallbackContextWindowTokens
    self.executionTarget = executionTarget
    self.isContextWindowReported = isContextWindowReported
    self.modelIdentifier = modelIdentifier ?? executionTarget.defaultModelIdentifier
    self.quotaStatus = quotaStatus
    self.supportsGuidedGeneration = supportsGuidedGeneration
    self.supportsReasoning = supportsReasoning
    self.supportsToolCalling = supportsToolCalling
    self.supportsVision = supportsVision
  }

  /// Apple's documented on-device defaults for the OS 26.0 releases.
  public static let onDevice = Self(
    executionTarget: .onDevice,
    contextWindowTokens: FoundationModelDefaults.onDeviceContextWindowTokens,
    supportsReasoning: false,
    quotaStatus: .notApplicable
  )

  /// Apple's documented Private Cloud Compute defaults for the OS 27 releases.
  public static let privateCloudCompute = Self(
    executionTarget: .privateCloudCompute,
    contextWindowTokens: FoundationModelDefaults.privateCloudContextWindowTokens,
    supportsReasoning: true,
    quotaStatus: .unknown
  )

  public static func preset(for target: FoundationModelExecutionTarget) -> Self {
    switch target {
    case .automatic, .onDevice:
      return .onDevice
    case .privateCloudCompute:
      return .privateCloudCompute
    case .providerPackage, .customLocal:
      return Self(executionTarget: target)
    }
  }

  public var privacyMode: LMPrivacyMode {
    executionTarget.privacyMode
  }

  /// The provider-neutral capabilities routers can use for this target.
  public var capabilities: LMClientCapabilities {
    var capabilities = LMClientCapabilities.foundationModelsProviderNeutral
    if supportsReasoning {
      capabilities.supportedFeatures.insert(.reasoning)
    }
    capabilities.contextWindowTokens = contextWindowTokens
    return capabilities
  }
}
