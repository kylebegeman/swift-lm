import Foundation
import SwiftLM

public struct EvaluationRunMetrics: Codable, Equatable, Sendable {
  public var cacheWriteInputTokens: Int?
  public var cachedInputTokens: Int?
  public var durationMilliseconds: Double?
  public var estimatedInputTokens: Int?
  public var estimatedOutputTokens: Int?
  public var fallbackReason: String?
  public var inputChunkCount: Int?
  public var reasoningTokens: Int?
  public var retrievalSnippetCount: Int?
  public var validationIssueCount: Int?

  public init(
    estimatedInputTokens: Int? = nil,
    estimatedOutputTokens: Int? = nil,
    cachedInputTokens: Int? = nil,
    reasoningTokens: Int? = nil,
    durationMilliseconds: Double? = nil,
    inputChunkCount: Int? = nil,
    retrievalSnippetCount: Int? = nil,
    fallbackReason: String? = nil,
    validationIssueCount: Int? = nil,
    cacheWriteInputTokens: Int? = nil
  ) {
    self.cacheWriteInputTokens = cacheWriteInputTokens
    self.cachedInputTokens = cachedInputTokens
    self.durationMilliseconds = durationMilliseconds
    self.estimatedInputTokens = estimatedInputTokens
    self.estimatedOutputTokens = estimatedOutputTokens
    self.fallbackReason = fallbackReason
    self.inputChunkCount = inputChunkCount
    self.reasoningTokens = reasoningTokens
    self.retrievalSnippetCount = retrievalSnippetCount
    self.validationIssueCount = validationIssueCount
  }

  public init(
    tokenUsage: LMTokenUsage?,
    duration: TimeInterval? = nil,
    inputChunkCount: Int? = nil,
    retrievalSnippetCount: Int? = nil,
    fallbackReason: String? = nil,
    validationIssueCount: Int? = nil
  ) {
    self.init(
      estimatedInputTokens: tokenUsage?.estimatedInputTokens,
      estimatedOutputTokens: tokenUsage?.estimatedOutputTokens,
      cachedInputTokens: tokenUsage?.cachedInputTokens,
      reasoningTokens: tokenUsage?.reasoningTokens,
      durationMilliseconds: duration.map { $0 * 1_000 },
      inputChunkCount: inputChunkCount,
      retrievalSnippetCount: retrievalSnippetCount,
      fallbackReason: fallbackReason,
      validationIssueCount: validationIssueCount,
      cacheWriteInputTokens: tokenUsage?.cacheWriteInputTokens
    )
  }

  public init(
    receipt: LMRunReceipt,
    inputChunkCount: Int? = nil,
    retrievalSnippetCount: Int? = nil,
    validationIssueCount: Int? = nil
  ) {
    self.init(
      estimatedInputTokens: receipt.tokenUsage?.estimatedInputTokens,
      estimatedOutputTokens: receipt.tokenUsage?.estimatedOutputTokens,
      cachedInputTokens: receipt.tokenUsage?.cachedInputTokens,
      reasoningTokens: receipt.tokenUsage?.reasoningTokens,
      durationMilliseconds: receipt.durationMilliseconds,
      inputChunkCount: inputChunkCount,
      retrievalSnippetCount: retrievalSnippetCount,
      fallbackReason: receipt.attempts.last(where: { $0.error?.fallbackReason != nil })?.error?.fallbackReason,
      validationIssueCount: validationIssueCount,
      cacheWriteInputTokens: receipt.tokenUsage?.cacheWriteInputTokens
    )
  }
}
