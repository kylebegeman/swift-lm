import Foundation
import SwiftLM
import SwiftLMEvaluation
import SwiftLMFoundationModels
import Testing

@Suite("Prompting")
struct PromptingTests {
  // MARK: - Prompting

  @Test
  func compiledPromptIncludesResponseSchemaDescription() {
    let prompt = CompiledPrompt(
      contract: PromptContract(
        id: "review",
        version: "v1",
        instructions: "Extract grounded fields.",
        responseSchemaDescription: "Return JSON with summary and tasks."
      ),
      metadata: FoundationModelDefaults.metadata(promptVersion: "v1"),
      userPrompt: "Transcript"
    )

    #expect(prompt.systemInstructions.contains("Extract grounded fields."))
    #expect(prompt.systemInstructions.contains("Return JSON with summary and tasks."))
  }

  @Test
  func exampleSelectorPrefersMatchingTags() {
    let examples = [
      PromptExample(id: "general", input: "A", output: "B", tags: ["general"]),
      PromptExample(id: "meeting", input: "C", output: "D", tags: ["meeting"]),
    ]

    let selected = ExampleSelector(limit: 1, preferredTags: ["meeting"])
      .select(from: examples)

    #expect(selected.map(\.id) == ["meeting"])
  }
}
