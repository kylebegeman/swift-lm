# Chime In Incubation

## Role

Chime In is the first real-world proving ground for SwiftLM.

The product promise is private, offline voice capture with structured understanding. That makes it an ideal stress test for local model orchestration:

- long messy transcripts
- structured extraction
- user verification
- local-only fallback
- no backend requirement
- no default telemetry
- Apple-native platform integrations

## What To Extract From Chime In

Chime In currently has app-specific versions of several concepts that can become package primitives:

- provider metadata
- prompt compiler
- example corpus
- evaluation corpus
- Foundation Models availability handling
- structured candidate normalization
- source grounding
- heuristic fallback
- prompt versioning

The migration should be incremental. Do not yank app code into the package wholesale.

## Proposed First Adoption Path

1. Add SwiftLM as a local package dependency in Chime In.
2. Replace Chime In's generic provider metadata with `LMProviderMetadata`.
3. Use `TokenBudget`, `TokenCounter`, and `TextChunker` for long transcript planning.
4. Move recording transcript segmentation through `TranscriptSegment` and `TranscriptChunker` at the extraction boundary.
5. Use `PromptContract`, `PromptExample`, and `ExampleSelector` underneath Chime In's extraction prompt compiler.
6. Use `GroundingValidator` where Chime In currently checks whether generated candidates are supported by transcript text.
7. Wrap model output in `StructuredGenerationCandidate` with Chime transcript evidence spans.
8. Run generic validators from SwiftLM before applying Chime-specific task/date/decision validation.
9. Use `MapReducePipeline` for long recordings once per-chunk extraction is wired.
10. Use `LocalRetriever` and `LocalRAGPipeline` at the boundary for local question-answering or cross-recording recall, while keeping the actual Chime storage/index implementation in Chime In.
11. Compose the extraction path with `LMWorkflow`:
    deterministic transcript hints -> local retrieval -> context plan -> structured generation ->
    grounding validation -> deterministic fallback.
12. Move reusable evaluation harness logic into `SwiftLMEvaluation`, using `PromptVersionEvaluationReport` and `LocalDebugBundle` for local prompt-change reviews.
13. Keep `RecordingReviewDraft` and Chime-specific validators in Chime In.

## Keep In Chime In

These should not move into SwiftLM:

- recording persistence
- transcript segment schema
- capture modes
- task/date/decision final models
- Reminders/Calendar/Notes export
- CloudKit sync
- TCA reducers
- Chime In design system
- product-specific privacy copy

## Graduate To SwiftLM

These can move when they are app-neutral:

- prompt contract structure
- prompt metadata
- example selection
- token-aware transcript chunking
- transcript segment chunking and timestamp-preserving chunk metadata
- structured candidate and evidence wrappers
- map/reduce orchestration primitives
- typed workflow orchestration for deterministic analysis, retrieval, context planning, generation,
  validation, and fallback
- local retrieval value types
- local retrieval protocol and citation rendering
- deterministic grounding validators
- fallback result types
- evaluation case formats
- prompt-version report and local debug bundle formats

## Testing Live In Chime In

The package should be tested against:

- short voice notes
- long meetings
- filler recordings
- task dumps
- reflective journaling
- lecture notes
- unsupported model availability states
- unsupported locale states
- model-ready delays
- validation failures

Every package primitive that Chime In adopts should have a unit test in SwiftLM and an integration or feature test in Chime In when product behavior changes.
