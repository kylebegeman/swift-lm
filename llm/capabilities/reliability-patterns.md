# Reliability Patterns

## Use When

Use this card for token budgeting, chunking, context packing, local RAG, validation, fallback, diagnostics, and eval work.

## Core Flow

```text
input
  -> retrieve/pack context
  -> compile prompt contract
  -> budget tokens
  -> generate typed candidate
  -> validate and ground
  -> repair or fall back
  -> return app-owned draft/result with metadata
```

## Current Primitives

- `PromptContract`
- `PromptExample`
- `ExampleSelector`
- `CompiledPrompt`
- `TokenBudget`
- `TokenCounter`
- `TextChunker`
- `BoundaryAwareTextChunker`
- `TranscriptSegment`
- `TranscriptChunk`
- `TranscriptChunker`
- `RetrievedSnippet`
- `ContextPacker`
- `SourceReference`
- `RetrievableDocument`
- `LocalRetrievalQuery`
- `LocalRetriever`
- `KeywordLocalRetriever`
- `CitationContextRenderer`
- `LocalRAGPipeline`
- `LMWorkflow`
- `LMStep`
- `LMWorkflowContext`
- `LMWorkflowResult`
- `LMWorkflowEvent`
- `LMClientCapabilities`
- `LMRouterFallbackPolicy`
- `MapReducePipeline`
- `MergePolicy`
- `GroundingValidator`
- `FallbackReason`
- `GenerationCandidate`
- `StructuredGenerationSchema`
- `StructuredGenerationContract`
- `EvidenceSource`
- `EvidenceSpan`
- `StructuredGenerationCandidate`
- `StructuredGenerationValidator`
- `StructuredGenerationRepairPolicy`
- `StructuredGenerationFallbackPolicy`
- `StructuredGenerationPipeline`
- `TextEvaluationAssertion`
- `StructuredEvaluationAssertion`
- `StructuredOutputEvaluator`
- `PromptEvaluationCase`
- `PromptEvaluator`
- `PromptVersionEvaluationReport`
- `PromptVersionEvaluationMatrix`
- `ModelFallbackMatrix`
- `EvaluationRunMetrics`
- `LocalDebugBundle`

## Source Of Truth

- `../../docs/03-reliability-patterns.md`
- `../../docs/04-context-and-chunking.md`
- `../../docs/05-structured-generation.md`
- `../../docs/06-local-rag.md`
- `../../docs/07-evaluation-and-diagnostics.md`

## Common Failure Modes

- Treating generated output as final state.
- Forgetting provider metadata.
- Adding prompt examples without checking token cost.
- Creating validators that silently discard everything without diagnostics.
- Adding fallback behavior that hides product-impacting errors.

## Read Next

- `../../docs/09-roadmap.md`
- `../../docs/10-open-source-readiness.md`
