# Local RAG

## Purpose

Retrieval-augmented generation is how small context windows become practical. For Apple apps, local RAG should retrieve private user data from local stores and provide only the relevant snippets to the on-device model.

SwiftLM should provide local-first RAG primitives, not a server-dependent framework.

## Recommended Architecture

```text
local documents / notes / transcripts
  -> chunker
  -> local index
  -> query
  -> ranked snippets
  -> context packer
  -> prompt contract
  -> model
  -> grounded response with citations
```

## Indexing Options

Initial options:

- SQLite FTS
- GRDB-backed search
- NaturalLanguage embeddings where available and appropriate
- precomputed app-specific indexes

SwiftLM should not force a database dependency in the core target. It should define small protocols and value types so apps can plug in SQLiteData, GRDB, Core Data, or custom stores.

## Retrieval Result Shape

A retrieved snippet should preserve:

- snippet ID
- source ID
- source display label
- source type
- text
- token count
- relevance score
- optional date/recency metadata
- optional source range

`RetrievedSnippet` now preserves the core shape:

- `id`
- `sourceID`
- `sourceDisplayName`
- `sourceKind`
- `text`
- `tokenCount`
- `score`
- optional integer `characterRange`
- `isRequired`

It can also become an `EvidenceSource` for structured generation validation.

## Current Toolkit

The first local RAG slice is dependency-free and lives in `SwiftLM`:

- `SourceReference`
- `RetrievableDocument`
- `LocalRetrievalQuery`
- `LocalRetrievalResult`
- `LocalRetriever`
- `AnyLocalRetriever`
- `KeywordLocalRetriever`
- `SnippetCitation`
- `CitationContextRenderer`
- `LocalRAGPipeline`
- `LocalRAGResult`

The important boundary is `LocalRetriever`. Apps can plug in SQLite FTS, GRDB, Core Data, CloudKit-local mirrors, file indexes, or their own transcript stores without changing generation code.

`KeywordLocalRetriever` is intentionally simple. It is useful for tests, demos, and deterministic fallback behavior. It is not meant to be the final production search engine for every app.

When a query supplies required source IDs, the keyword retriever keeps matching required snippets ahead of optional snippets before applying `maxResults`. This is important for user-selected notes, transcripts, or attachments because an exact user selection should not be crowded out by higher-scoring incidental keyword matches.

## Pipeline Shape

The current package pipeline is:

```text
LocalRetrievalQuery
  -> LocalRetriever
  -> LocalRetrievalResult
  -> ContextPacker
  -> CitationContextRenderer
  -> LocalRAGResult
```

`LocalRAGResult` carries:

- retrieved snippets
- packed snippets
- rendered context block
- citation markers
- structured-generation source context

That makes it easy to build a prompt from local context and then validate generated evidence against the exact snippets that were packed.

## Citation Rendering

`CitationContextRenderer` renders compact prompt context:

```text
[1] Planning transcript (transcript)
We decided to keep the first version local only.

[2] Prompt plan (note)
Prompt versions should include compact citation context.
```

Apps can show `SnippetCitation` values in review UI and map them back to local source IDs, snippet IDs, and character ranges.

## Tool Calling vs. Pre-Retrieval

Use tool calling when the model must decide whether to retrieve or which tool arguments to generate.

Use pre-retrieval when the app already knows retrieval is required.

For Chime In, most extraction flows should pre-pack transcript context rather than expose a search tool. Interactive question-answering over a library may use a retrieval tool later.

## Offline Requirement

Local RAG must work without a backend.

This means:

- indexes live on device
- snippets are pulled from local app stores
- no external embedding service is required
- no network access is hidden behind retrieval APIs

External providers are adapter targets. Retrieval itself should remain local unless an app explicitly builds a different retriever.

## Community Value

A small, idiomatic Swift local RAG package layer would be useful beyond Chime In:

- notes apps
- journaling apps
- document readers
- email clients
- research tools
- personal knowledge bases
- health/fitness apps with user-approved local records
- education apps

The hard part is not the acronym. The hard part is the boring Swift API that keeps context small, citations intact, and privacy obvious.

The Phase 4 slice is the first useful contribution shape: a protocol-first retrieval layer and citation-preserving context pipeline that can work with any local index.
