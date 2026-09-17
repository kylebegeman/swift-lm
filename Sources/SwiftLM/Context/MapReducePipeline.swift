import Foundation

public struct ChunkProcessingResult<Chunk: Sendable, Partial: Sendable>: Sendable {
  public var chunk: Chunk
  public var evidence: [EvidenceSpan]
  public var output: Partial
  public var tokenUsage: LMTokenUsage?

  public init(
    chunk: Chunk,
    output: Partial,
    evidence: [EvidenceSpan] = [],
    tokenUsage: LMTokenUsage? = nil
  ) {
    self.chunk = chunk
    self.evidence = evidence
    self.output = output
    self.tokenUsage = tokenUsage
  }
}

extension ChunkProcessingResult: Equatable where Chunk: Equatable, Partial: Equatable {}

public struct MapReducePipeline<Chunk: Sendable, Partial: Sendable, Final: Sendable>: Sendable {
  public var map:
    @Sendable (Chunk) async throws -> ChunkProcessingResult<Chunk, Partial>
  public var maximumConcurrentTasks: Int
  public var reduce:
    @Sendable ([ChunkProcessingResult<Chunk, Partial>]) async throws -> Final

  public init(
    maximumConcurrentTasks: Int = 1,
    map: @escaping @Sendable (Chunk) async throws -> ChunkProcessingResult<Chunk, Partial>,
    reduce: @escaping @Sendable ([ChunkProcessingResult<Chunk, Partial>]) async throws -> Final
  ) {
    self.map = map
    self.maximumConcurrentTasks = max(1, maximumConcurrentTasks)
    self.reduce = reduce
  }

  public func run(
    chunks: [Chunk]
  ) async throws -> MapReduceResult<Chunk, Partial, Final> {
    let partials = maximumConcurrentTasks == 1
      ? try await runSequentially(chunks: chunks)
      : try await runConcurrently(chunks: chunks)

    try Task.checkCancellation()
    return MapReduceResult(
      partials: partials,
      output: try await reduce(partials)
    )
  }

  private func runSequentially(
    chunks: [Chunk]
  ) async throws -> [ChunkProcessingResult<Chunk, Partial>] {
    var partials: [ChunkProcessingResult<Chunk, Partial>] = []
    partials.reserveCapacity(chunks.count)

    for chunk in chunks {
      try Task.checkCancellation()
      partials.append(try await map(chunk))
    }

    return partials
  }

  private func runConcurrently(
    chunks: [Chunk]
  ) async throws -> [ChunkProcessingResult<Chunk, Partial>] {
    guard !chunks.isEmpty else { return [] }

    return try await withThrowingTaskGroup(
      of: (Int, ChunkProcessingResult<Chunk, Partial>).self
    ) { group in
      let limit = min(maximumConcurrentTasks, chunks.count)
      var nextIndex = 0
      var partials = Array<ChunkProcessingResult<Chunk, Partial>?>(repeating: nil, count: chunks.count)

      func enqueueNext() {
        guard nextIndex < chunks.count else { return }
        let index = nextIndex
        let chunk = chunks[index]
        nextIndex += 1
        group.addTask {
          try Task.checkCancellation()
          return (index, try await map(chunk))
        }
      }

      for _ in 0..<limit {
        enqueueNext()
      }

      while let (index, result) = try await group.next() {
        partials[index] = result
        enqueueNext()
      }

      return partials.compactMap { $0 }
    }
  }
}

public struct MapReduceResult<Chunk: Sendable, Partial: Sendable, Final: Sendable>: Sendable {
  public var output: Final
  public var partials: [ChunkProcessingResult<Chunk, Partial>]

  public init(
    partials: [ChunkProcessingResult<Chunk, Partial>],
    output: Final
  ) {
    self.output = output
    self.partials = partials
  }
}

extension MapReduceResult: Equatable where Chunk: Equatable, Partial: Equatable, Final: Equatable {}
