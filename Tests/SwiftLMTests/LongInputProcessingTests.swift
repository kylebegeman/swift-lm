import Foundation
import SwiftLM
import SwiftLMEvaluation
import SwiftLMFoundationModels
import Testing

@Suite("Long input processing")
struct LongInputProcessingTests {
  // MARK: - Long Input Processing

  @Test
  func boundaryAwareChunkerPreservesSentenceBoundaries() {
    let text = "First sentence is short. Second sentence has more content. Third sentence closes."
    let chunker = BoundaryAwareTextChunker(
      boundary: .sentence,
      maxTokensPerChunk: 10,
      overlapUnitCount: 1
    )

    let chunks = chunker.chunks(for: text)

    #expect(chunks.count > 1)
    #expect(chunks.first?.text.hasSuffix(".") == true)
    #expect(chunks.allSatisfy { !$0.characterRange.isEmpty })
  }

  @Test
  func transcriptChunkerPreservesSegmentIDsAndTimes() {
    let segments = [
      TranscriptSegment(id: "1", text: "Need to follow up with Jamie tomorrow.", startTime: 0, endTime: 4),
      TranscriptSegment(id: "2", text: "We decided to keep the local version first.", startTime: 4, endTime: 9),
      TranscriptSegment(id: "3", text: "Compare prompt versions before publishing.", startTime: 9, endTime: 13),
    ]
    let chunker = TranscriptChunker(
      maxTokensPerChunk: 24,
      overlapSegmentCount: 1,
      sourceID: "recording-1"
    )

    let chunks = chunker.chunks(for: segments)

    #expect(chunks.count > 1)
    #expect(chunks[0].segmentIDs == ["1", "2"])
    #expect(chunks[1].segmentIDs.first == "2")
    #expect(chunks[0].startTime == 0)
    #expect(chunks[0].endTime == 9)
    #expect(chunks[0].evidenceSource.kind == "transcriptChunk")
  }

  @Test
  func mergePolicyDeduplicatesByNormalizedText() {
    let merged = MergePolicy<String>.normalizedText.merged([
      "Send Jamie the permissions copy",
      "send jamie the permissions copy.",
      "Review prompt versions",
    ])

    #expect(merged == [
      "Send Jamie the permissions copy",
      "Review prompt versions",
    ])
  }

  @Test
  func mapReducePipelineProcessesChunksInOrder() async throws {
    let chunks = [
      TranscriptChunk(
        id: 0,
        sourceID: "recording",
        text: "Need to follow up.",
        segmentIDs: ["1"],
        tokenCount: 5
      ),
      TranscriptChunk(
        id: 1,
        sourceID: "recording",
        text: "Review prompt versions.",
        segmentIDs: ["2"],
        tokenCount: 6
      ),
    ]
    let pipeline = MapReducePipeline<TranscriptChunk, String, String>(
      map: { chunk in
        ChunkProcessingResult(
          chunk: chunk,
          output: chunk.text.uppercased(),
          evidence: [
            EvidenceSpan(
              id: "chunk-\(chunk.id)",
              text: chunk.text,
              sourceID: chunk.evidenceSource.id
            )
          ]
        )
      },
      reduce: { partials in
        partials.map(\.output).joined(separator: " ")
      }
    )

    let result = try await pipeline.run(chunks: chunks)

    #expect(result.partials.count == 2)
    #expect(result.output == "NEED TO FOLLOW UP. REVIEW PROMPT VERSIONS.")
  }

  @Test
  func parallelMapReducePipelinePreservesInputOrder() async throws {
    let pipeline = MapReducePipeline<Int, String, String>(
      maximumConcurrentTasks: 3,
      map: { value in
        try await Task.sleep(for: .milliseconds((4 - value) * 10))
        return ChunkProcessingResult(chunk: value, output: "\(value)")
      },
      reduce: { partials in
        partials.map(\.output).joined(separator: ",")
      }
    )

    let result = try await pipeline.run(chunks: [1, 2, 3])

    #expect(result.partials.map(\.chunk) == [1, 2, 3])
    #expect(result.output == "1,2,3")
  }

  @Test
  func mapReducePipelinePropagatesCancellation() async {
    let pipeline = MapReducePipeline<Int, Int, Int>(
      map: { value in
        try await Task.sleep(for: .seconds(5))
        return ChunkProcessingResult(chunk: value, output: value)
      },
      reduce: { partials in
        partials.map(\.output).reduce(0, +)
      }
    )
    let task = Task {
      try await pipeline.run(chunks: [1, 2, 3])
    }

    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }
}
