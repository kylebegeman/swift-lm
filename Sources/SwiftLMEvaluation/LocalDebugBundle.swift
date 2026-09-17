import Foundation
import SwiftLM

public enum LocalDebugBundleContentPolicy: String, Codable, Equatable, Sendable {
  case redacted
  case includesRawOutputs
}

/// A local, serializable bundle of evaluation reports, fallback matrices, and run receipts.
///
/// The content policy is enforced, not just recorded: a `redacted` bundle strips raw outputs from
/// every prompt report it stores.
public struct LocalDebugBundle: Codable, Equatable, Identifiable, Sendable {
  public var contentPolicy: LocalDebugBundleContentPolicy
  public var createdAt: Date
  public var id: String
  public var modelFallbackMatrix: ModelFallbackMatrix?
  public var notes: String
  public var promptReports: [PromptVersionEvaluationReport]
  public var runReceipts: [LMRunReceipt]

  public init(
    id: String = UUID().uuidString,
    promptReports: [PromptVersionEvaluationReport],
    modelFallbackMatrix: ModelFallbackMatrix? = nil,
    runReceipts: [LMRunReceipt] = [],
    contentPolicy: LocalDebugBundleContentPolicy = .redacted,
    notes: String = "",
    createdAt: Date = Date()
  ) {
    self.contentPolicy = contentPolicy
    self.createdAt = createdAt
    self.id = id
    self.modelFallbackMatrix = modelFallbackMatrix
    self.notes = notes
    self.promptReports = contentPolicy == .redacted ? promptReports.map { $0.redacted() } : promptReports
    self.runReceipts = runReceipts
  }

  public var passed: Bool {
    promptReports.allSatisfy(\.passed) &&
      (modelFallbackMatrix?.failedCaseCount ?? 0) == 0 &&
      runReceipts.allSatisfy { $0.outcome == .succeeded }
  }

  public func jsonData(prettyPrinted: Bool = true) throws -> Data {
    try JSONEncoder.evaluationReportEncoder(prettyPrinted: prettyPrinted).encode(self)
  }
}
