import SwiftLLM
import SwiftLLMAnthropic
import SwiftLLMEvaluation
import SwiftLLMFoundationModels
import SwiftLLMOpenAI
import SwiftUI

struct ShowcaseView: View {
  @State private var ragResult: LocalRAGResult?

  private let modelAvailability = FoundationModelClient.live.availability()
  private let runtimeProfile = FoundationModelClient.live.runtimeProfile()
  private let privateCloudProfile = FoundationModelClient.live.runtimeProfile(for: .privateCloudCompute)
  @State private var privateCloudAvailability: FoundationModelAvailability?
  private let providerRows = [
    ProviderRow(
      name: FoundationModelClient.live.metadata.providerDisplayName,
      model: FoundationModelDefaults.metadata().modelIdentifier ?? "SystemLanguageModel.default",
      privacy: "Local only",
      role: "Default offline route"
    ),
    ProviderRow(
      name: "Apple Foundation Models on Private Cloud Compute",
      model: FoundationModelExecutionTarget.privateCloudCompute.defaultModelIdentifier,
      privacy: "Private Cloud Compute",
      role: "Opt-in server model on the OS 27 releases"
    ),
    ProviderRow(
      name: OpenAIClient(apiKey: "provided-at-runtime", model: "configured-openai-model").metadata.providerDisplayName,
      model: "configured-openai-model",
      privacy: "External opt-in",
      role: "Optional cloud fallback"
    ),
    ProviderRow(
      name: AnthropicClient(apiKey: "provided-at-runtime", model: "configured-anthropic-model").metadata.providerDisplayName,
      model: "configured-anthropic-model",
      privacy: "External opt-in",
      role: "Optional cloud fallback"
    ),
  ]
  private let sampleSchema = StructuredGenerationSchema(
    id: "review-draft",
    name: "Review draft",
    description: "Extract a compact review draft from a transcript.",
    fields: [
      StructuredGenerationField(
        name: "summary",
        typeDescription: "String",
        guide: "One or two grounded sentences."
      ),
      StructuredGenerationField(
        name: "tasks",
        typeDescription: "[String]",
        isRequired: false,
        maximumCount: 6
      ),
    ],
    maximumResponseTokens: 500
  )
  private let sampleTranscript = """
    We decided to keep the first version local only. I need to test the extraction pipeline in Chime In tomorrow and compare the prompt versions before publishing anything.
    """
  private let sampleSegments = [
    TranscriptSegment(
      id: "1",
      text: "We decided to keep the first version local only.",
      startTime: 0,
      endTime: 4
    ),
    TranscriptSegment(
      id: "2",
      text: "I need to test the extraction pipeline in Chime In tomorrow.",
      startTime: 4,
      endTime: 9
    ),
    TranscriptSegment(
      id: "3",
      text: "Compare the prompt versions before publishing anything.",
      startTime: 9,
      endTime: 13
    ),
  ]
  private let sampleDocuments = [
    RetrievableDocument(
      id: "transcript",
      text: "We decided to keep the first version local only. Test extraction in Chime In tomorrow.",
      displayName: "Planning transcript",
      kind: "transcript"
    ),
    RetrievableDocument(
      id: "prompt-plan",
      text: "Prompt versions should include compact citation context and local retrieval diagnostics.",
      displayName: "Prompt plan",
      kind: "note"
    ),
    RetrievableDocument(
      id: "release",
      text: "Open-source readiness needs docs, evaluation cases, and a clean package API.",
      displayName: "Release notes",
      kind: "doc"
    ),
  ]
  private let sampleEvaluationReport = PromptVersionEvaluationReport(
    promptID: "review-draft",
    promptVersion: "v1",
    caseResults: [
      PromptEvaluationResultRecord(
        caseID: "grounded-summary",
        passed: true,
        failures: []
      ),
      PromptEvaluationResultRecord(
        caseID: "citation-context",
        passed: true,
        failures: []
      ),
    ],
    metrics: EvaluationRunMetrics(
      estimatedInputTokens: 220,
      estimatedOutputTokens: 90,
      retrievalSnippetCount: 2
    )
  )

  var body: some View {
    NavigationStack {
      List {
        Section("Model") {
          LabeledContent("Provider", value: "Apple Foundation Models")
          LabeledContent(
            "Context window",
            value: runtimeProfile.contextWindowTokens.map { "\($0) tokens" } ?? "Unknown"
          )
          LabeledContent("Availability", value: modelAvailability.diagnosticMessage)
          LabeledContent("Privacy", value: "Local only")
        }

        Section("Private Cloud Compute") {
          LabeledContent(
            "Context window",
            value: privateCloudProfile.contextWindowTokens.map { "\($0) tokens" } ?? "Unknown"
          )
          LabeledContent("Reasoning", value: privateCloudProfile.supportsReasoning ? "Supported" : "Unsupported")
          LabeledContent(
            "Quota",
            value: privateCloudProfile.quotaStatus.permitsGeneration ? "Permits generation" : "Exhausted"
          )
          LabeledContent(
            "Availability",
            value: privateCloudAvailability?.diagnosticMessage ?? "Checking"
          )
        }

        Section("Provider Routing") {
          ForEach(providerRows) { provider in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(provider.name)
                Spacer()
                Text(provider.privacy)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Text(provider.model)
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(provider.role)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }
        }

        Section("Context") {
          let budget = TokenBudget(reservedResponseTokens: 700, safetyMarginTokens: 256)
          LabeledContent("Available input", value: "\(budget.availableInputTokens) tokens")
          LabeledContent("Sample estimate", value: "\(TokenCounter.latinHeuristic.count(sampleTranscript)) tokens")
        }

        Section("Structured Generation") {
          LabeledContent("Schema", value: sampleSchema.name)
          LabeledContent("Fields", value: "\(sampleSchema.fields.count)")
          LabeledContent("Max response", value: "\(sampleSchema.maximumResponseTokens ?? 0) tokens")
        }

        Section("Chunk Preview") {
          ForEach(TextChunker(maxTokensPerChunk: 28, overlapTokens: 6).chunks(for: sampleTranscript)) { chunk in
            VStack(alignment: .leading, spacing: 6) {
              Text("Chunk \(chunk.id + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(chunk.text)
            }
          }
        }

        Section("Transcript Pipeline") {
          ForEach(TranscriptChunker(maxTokensPerChunk: 22).chunks(for: sampleSegments)) { chunk in
            VStack(alignment: .leading, spacing: 6) {
              Text("Chunk \(chunk.id + 1) · \(chunk.segmentIDs.count) segments")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(chunk.text)
              if let start = chunk.startTime, let end = chunk.endTime {
                Text("\(start.formatted(.number.precision(.fractionLength(0))))s-\(end.formatted(.number.precision(.fractionLength(0))))s")
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
              }
            }
          }
        }

        Section("Local Retrieval") {
          if let ragResult {
            LabeledContent("Query", value: ragResult.query.text)
            LabeledContent("Packed", value: "\(ragResult.packedSnippets.count) snippets")
            ForEach(ragResult.citations) { citation in
              VStack(alignment: .leading, spacing: 6) {
                Text("[\(citation.marker)] \(citation.sourceDisplayName ?? citation.sourceID)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Text(ragResult.packedSnippets.first(where: { $0.id == citation.snippetID })?.text ?? "")
              }
            }
          } else {
            ProgressView()
          }
        }

        Section("Evaluation") {
          LabeledContent("Prompt", value: "\(sampleEvaluationReport.promptID) \(sampleEvaluationReport.promptVersion)")
          LabeledContent("Cases", value: "\(sampleEvaluationReport.caseResults.count)")
          LabeledContent("Status", value: sampleEvaluationReport.passed ? "Passing" : "Failing")
          LabeledContent("Outputs", value: sampleEvaluationReport.storesRawOutputs ? "Stored" : "Redacted")
        }
      }
      .navigationTitle("SwiftLLM")
      .task {
        privateCloudAvailability = await FoundationModelClient.live.availability(for: .privateCloudCompute)
        await loadRetrievalPreview()
      }
    }
  }

  @MainActor
  private func loadRetrievalPreview() async {
    guard ragResult == nil else { return }

    let retriever = KeywordLocalRetriever(
      documents: sampleDocuments,
      maxTokensPerSnippet: 48
    )
    let pipeline = LocalRAGPipeline(
      retriever: retriever,
      packer: ContextPacker(
        budget: TokenBudget(
          contextLimit: 96,
          reservedResponseTokens: 24,
          safetyMarginTokens: 8
        ),
        strategy: .sourceDiverse
      )
    )

    ragResult = try? await pipeline.run(
      query: LocalRetrievalQuery(
        text: "local citation prompt versions",
        maxResults: 4
      )
    )
  }
}

private struct ProviderRow: Identifiable {
  var id: String { name }
  var name: String
  var model: String
  var privacy: String
  var role: String
}
