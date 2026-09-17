import Foundation
import SwiftLLM
import SwiftLLMEvaluation
import SwiftLLMFoundationModels
import Testing

@Suite("Structured generation")
struct StructuredGenerationTests {
  // MARK: - Structured Generation

  @Test
  func structuredSchemaProducesPromptDescription() {
    let schema = StructuredGenerationSchema(
      id: "sample",
      name: "Sample extraction",
      description: "Return a short summary and tasks.",
      fields: [
        StructuredGenerationField(
          name: "summary",
          typeDescription: "String",
          guide: "One sentence."
        ),
        StructuredGenerationField(
          name: "tasks",
          typeDescription: "[String]",
          isRequired: false,
          maximumCount: 3
        ),
      ],
      maximumResponseTokens: 120
    )

    #expect(schema.promptDescription.contains("summary"))
    #expect(schema.promptDescription.contains("maximum count 3"))
    #expect(schema.promptDescription.contains("Maximum response tokens: 120"))
  }

  @Test
  func structuredValidatorCombinesCountAndGroundedEvidenceRules() {
    let metadata = FoundationModelDefaults.metadata(promptVersion: "test")
    let candidate = StructuredGenerationCandidate(
      output: SampleExtraction(
        summary: "Review local extraction",
        tasks: ["One", "Two", "Three"]
      ),
      metadata: metadata,
      evidence: [
        EvidenceSpan(
          id: "summary",
          text: "Review local extraction",
          sourceID: "transcript"
        )
      ]
    )
    let validator = StructuredGenerationValidator<SampleExtraction>.all([
      .maximumCount(\.tasks, maximum: 2, path: "tasks"),
      .groundedEvidence(),
    ])
    let result = validator(
      candidate,
      in: StructuredGenerationSourceContext(
        sources: [
          EvidenceSource(
            id: "transcript",
            text: "We need to review local extraction tomorrow."
          )
        ]
      )
    )

    #expect(!result.isAccepted)
    #expect(result.issues.map(\.id).contains("maximum-count-tasks"))
  }

  @Test
  func structuredPipelineAcceptsValidCandidate() async throws {
    let prompt = CompiledPrompt(
      contract: PromptContract(id: "sample", version: "v1", instructions: "Extract."),
      metadata: FoundationModelDefaults.metadata(promptVersion: "test"),
      userPrompt: "Need to review local extraction."
    )
    let pipeline = StructuredGenerationPipeline<SampleExtraction>(
      generate: { prompt in
        GenerationCandidate(
          output: SampleExtraction(
            summary: "Review local extraction",
            tasks: ["Review local extraction"]
          ),
          metadata: prompt.metadata
        )
      },
      validator: .all([
        .nonEmptyString(\.summary, path: "summary"),
        .maximumCount(\.tasks, maximum: 2, path: "tasks"),
        .groundedEvidence(),
      ])
    )

    let result = try await pipeline.run(
      prompt: prompt,
      context: StructuredGenerationSourceContext(
        sourceText: "Need to review local extraction."
      ),
      evidence: { output in
        [EvidenceSpan(id: "summary", text: output.summary, sourceID: "source")]
      }
    )

    #expect(result.status == .accepted)
    #expect(result.output?.summary == "Review local extraction")
    #expect(result.validation.isAccepted)
  }

  @Test
  func structuredPipelineFallsBackOnValidationFailure() async throws {
    let prompt = CompiledPrompt(
      contract: PromptContract(id: "sample", version: "v1", instructions: "Extract."),
      metadata: FoundationModelDefaults.metadata(promptVersion: "test"),
      userPrompt: "Need to review local extraction."
    )
    let fallback = SampleExtraction(summary: "Fallback summary", tasks: [])
    let pipeline = StructuredGenerationPipeline<SampleExtraction>(
      generate: { prompt in
        GenerationCandidate(
          output: SampleExtraction(
            summary: "",
            tasks: ["One", "Two", "Three"]
          ),
          metadata: prompt.metadata
        )
      },
      validator: .all([
        .nonEmptyString(\.summary, path: "summary"),
        .maximumCount(\.tasks, maximum: 2, path: "tasks"),
      ]),
      repairPolicy: .fallbackOnValidationFailure(notes: "Use deterministic fallback."),
      fallbackPolicy: .fixed(fallback)
    )

    let result = try await pipeline.run(prompt: prompt)

    #expect(result.status == .fellBack)
    #expect(result.output == fallback)
    #expect(result.fallbackDecision?.reason == .validationFailed)
    #expect(result.repairPlan.action == .fallback(.validationFailed))
  }
}
