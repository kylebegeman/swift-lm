import Foundation

public struct ModelFallbackMatrixEntry: Codable, Equatable, Identifiable, Sendable {
  public var availability: String
  public var failedCaseCount: Int
  public var fallbackReason: String?
  public var modelIdentifier: String?
  public var passedCaseCount: Int
  public var providerKind: String

  public init(
    providerKind: String,
    availability: String,
    passedCaseCount: Int,
    failedCaseCount: Int,
    modelIdentifier: String? = nil,
    fallbackReason: String? = nil
  ) {
    self.availability = availability
    self.failedCaseCount = failedCaseCount
    self.fallbackReason = fallbackReason
    self.modelIdentifier = modelIdentifier
    self.passedCaseCount = passedCaseCount
    self.providerKind = providerKind
  }

  /// Derived from the entry's fields so it never goes stale after mutation.
  public var id: String {
    [providerKind, modelIdentifier, availability, fallbackReason]
      .compactMap { $0 }
      .joined(separator: ":")
  }
}

public struct ModelFallbackMatrix: Codable, Equatable, Sendable {
  public var entries: [ModelFallbackMatrixEntry]

  public init(entries: [ModelFallbackMatrixEntry]) {
    self.entries = entries
  }

  public var failedCaseCount: Int {
    entries.reduce(0) { $0 + $1.failedCaseCount }
  }

  public var passedCaseCount: Int {
    entries.reduce(0) { $0 + $1.passedCaseCount }
  }
}
