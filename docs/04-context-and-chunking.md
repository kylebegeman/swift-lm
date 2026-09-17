# Context And Chunking

## Why Context Management Is Core

Foundation Models has a small context window compared with frontier cloud models. The package should therefore treat context as a scarce resource.

Every high-level API should be able to answer:

- how many tokens are available?
- how many are reserved for output?
- how many are reserved for safety margin?
- how much do instructions cost?
- how much does the schema cost?
- how much do examples cost?
- how much context can the user input receive?

## Token Budget Model

The first budget model is:

```text
available input tokens =
  model context limit
  - reserved response tokens
  - safety margin tokens
  - fixed prompt/instruction/schema/example tokens
```

The current `TokenBudget` starts with the model limit, response reservation, and safety margin. Future versions should add measured fixed-cost accounting from Foundation Models token counting.

## Token Counting

The core target includes a heuristic counter so algorithms can run without Foundation Models.

The Foundation Models target should add an adapter around `SystemLanguageModel.tokenCount(for:)` where available. That adapter should be preferred whenever the framework is present because it reflects the actual tokenizer.

## Chunking

Long inputs should be split into chunks that fit the current budget.

Chunking should support:

- max token count
- overlap
- stable chunk IDs
- source identifiers
- source ranges when available
- sentence/paragraph-aware boundaries
- transcript timestamp ranges

The package now includes three chunking layers:

- `TextChunker` for simple word-based chunking.
- `BoundaryAwareTextChunker` for sentence- or paragraph-aware chunking.
- `TranscriptChunker` for transcript segment chunking that preserves segment IDs and timestamp ranges.

Chime In should use `TranscriptChunker` for recordings because transcript timestamps and segment IDs are essential for review, playback jumps, and evidence.

## Map/Reduce

Long tasks should usually become map/reduce pipelines:

```text
long transcript
  -> chunk transcript
  -> summarize/extract per chunk in fresh sessions
  -> merge and dedupe structured results
  -> summarize intermediate summaries
  -> validate final result against source context
```

Fresh sessions matter because the session transcript consumes context. For long work, reusing a session can create context pressure that is hard to reason about.

`MapReducePipeline` now provides the provider-neutral runner for this shape. It maps chunks into `ChunkProcessingResult` values, then reduces ordered partials into a final result. The default is sequential for deterministic debugging. Apps can opt into bounded parallel mapping with `maximumConcurrentTasks`, and the pipeline preserves input order before reduction even when chunks finish out of order.

## Context Packing

Retrieval produces candidate snippets. Context packing chooses which snippets fit.

Good packing considers:

- relevance score
- token count
- source diversity
- recency
- user-selected priority
- required snippets
- dedupe
- reserved room for instructions and schema

The current `ContextPacker` is score-first and budget-aware. Later versions should support more packing strategies.

`ContextPacker` currently supports:

- `.scoreDescending`
- `.scoreDensity`
- `.sourceDiverse`

Score-density packing is useful when small high-signal snippets should beat large slightly-higher-score snippets.

Source-diverse packing interleaves high-scoring snippets from different sources before returning to second snippets from the same source. That is useful for local RAG because it reduces the chance that one long note, transcript, or document crowds out corroborating context from nearby sources.

`RetrievedSnippet` now carries source display metadata, source kind, optional integer character ranges, and an `isRequired` flag. Required snippets are considered before optional snippets, while still respecting the token budget.

## Context Compiler

`LLMContextCompiler` is the reusable assembly step for prompt contracts,
examples, user input, retrieved snippets, tool metadata, session policy, and
Foundation Models context hints.

The compiler:

- estimates fixed input tokens for instructions, response schema text, examples, user input, tools, and app-provided context items
- reserves those fixed tokens before packing retrieved snippets
- renders packed snippets with citation markers
- returns the dropped snippets for debugging and UI feedback
- builds the `LLMContextPlan` used by provider-neutral requests
- builds a `CompiledPrompt` whose user prompt includes retrieved context when requested
- returns a context budget report and source context for structured validation

`LLMPipeline` uses `LLMContextCompiler` internally. Apps can also call the
compiler directly when they need to preview context pressure, show dropped
snippets, or preflight a request. Pass the platform-reported context window from
`FoundationModelClient.runtimeProfile(for:)` as the `TokenBudget.contextLimit`
instead of assuming 4,096 tokens.

## Chime In Implications

For Chime In, the long transcript strategy should be:

1. Split transcript segments into overlapping chunks while preserving timestamps.
2. Extract chunk-level tasks, dates, decisions, people, topics, and summary.
3. Keep source text and timestamp evidence on each item.
4. Merge duplicate tasks and date references.
5. Generate a final summary from chunk summaries.
6. Produce an editable review draft with provider metadata.
7. Persist only after user verification.

SwiftLLM should own steps 1, 2 orchestration, 4 helpers, and 5 orchestration. Chime In should own the final review draft model and persistence.

The Phase 3 implementation now covers steps 1, 2 orchestration, and generic merge helpers. Chime In still needs domain-specific merge policies for tasks, dates, and decisions.
