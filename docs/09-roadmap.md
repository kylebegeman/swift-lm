# Roadmap

## Phase 0: Private Scaffold

Status: completed.

- Create package targets.
- Add XcodeGen showcase shell.
- Add durable docs and agent docs.
- Add initial token budget, chunking, prompt, metadata, validation, and evaluation primitives.

## Phase 1: Foundation Models Adapter

Status: completed for the first usable adapter slice.

Build a real adapter around Foundation Models:

- availability and locale normalization: implemented
- token counter adapter: implemented with exact counting when available and heuristic fallback otherwise
- prewarm API: implemented
- typed guided generation wrapper: implemented behind `canImport(FoundationModels)`
- typed tool-call wrapper: implemented behind `canImport(FoundationModels)`
- text generation wrapper: implemented
- error normalization: implemented
- context-window handling: normalized into fallback metadata
- refusal/guardrail handling: normalized, with refusal explanation capture when available
- response metadata capture: implemented

Acceptance criteria:

- Chime In can call Foundation Models through SwiftLLM without owning framework-specific error handling.
- Tests can exercise unavailable/fallback behavior without importing Foundation Models.

Remaining refinements can happen in later phases: feedback attachment capture, richer token accounting for instructions/schemas/tools, typed diagnostics reports, and live-device tests for native tool-heavy sessions.

## Phase 2: Structured Generation Toolkit

Status: completed for the first provider-neutral toolkit slice.

Add generic structured generation support:

- prompt contracts: implemented through `PromptContract` and `StructuredGenerationContract`
- schema descriptors: implemented through `StructuredGenerationSchema` and `StructuredGenerationField`
- candidate wrappers: implemented through `StructuredGenerationCandidate`
- validation hooks: implemented through `StructuredGenerationValidator`
- repair policy: implemented as declarative `StructuredGenerationRepairPolicy`
- fallback policy: implemented through `StructuredGenerationFallbackPolicy`
- evidence fields: implemented through `EvidenceSource`, `EvidenceSpan`, and `StructuredGenerationSourceContext`

Acceptance criteria:

- Chime In extraction prompt compilation can be expressed using SwiftLLM primitives.
- Generated candidates can be validated before becoming Chime In review drafts.

Remaining refinements can happen in later phases: automatic repair loops, richer structured assertion DSLs, source-range helpers for transcript timestamps, and provider-specific schema cost accounting.

## Phase 3: Context Pipeline

Status: completed for the first context pipeline slice.

Improve long-input handling:

- sentence/paragraph-aware chunker: implemented through `BoundaryAwareTextChunker`
- transcript-segment chunker: implemented through `TranscriptSegment`, `TranscriptChunk`, and `TranscriptChunker`
- overlap policies: implemented for text units and transcript segments
- map/reduce orchestration: implemented through `MapReducePipeline`
- bounded concurrent map execution: implemented with input-order preservation
- merge and dedupe helpers: implemented through `MergePolicy`
- context packing strategies: implemented through `.scoreDescending` and `.scoreDensity`

Acceptance criteria:

- Long Chime In recordings can be processed without prefix/suffix truncation.
- Intermediate chunk outputs preserve source evidence.

Remaining refinements can happen in later phases: richer transcript timestamp evidence helpers, chunk diagnostics, domain-specific merge policies, and automatic repair loops over failed chunks.

## Phase 4: Local RAG

Status: completed for the first dependency-free retrieval slice.

Add local retrieval abstractions:

- retriever protocol: implemented through `LocalRetriever` and `AnyLocalRetriever`
- retrieved snippet model: expanded with source metadata, ranges, and required-snippet handling
- source references: implemented through `SourceReference` and `RetrievableDocument`
- packer strategies: implemented through `.sourceDiverse`
- citation output helpers: implemented through `SnippetCitation` and `CitationContextRenderer`
- local RAG pipeline: implemented through `LocalRAGPipeline` and `LocalRAGResult`
- optional GRDB/SQLite integration target if needed: deferred until a real app integration needs it

Acceptance criteria:

- Apps can plug in their own local index without depending on a server.
- The showcase demonstrates query -> snippets -> packed prompt.

Remaining refinements can happen in later phases: SQLite/GRDB adapters, embedding-backed retrievers where platform APIs make sense, richer citation formatting, query rewriting, source-diversity budget controls, and retrieval diagnostics.

## Phase 5: Evaluation And Diagnostics

Status: completed for the first reportable evaluation slice.

Make evals a first-class product:

- structured assertion DSL: implemented through `TextEvaluationAssertion`, `StructuredEvaluationAssertion`, and `StructuredOutputEvaluator`
- prompt version matrix: implemented through `PromptVersionEvaluationReport` and `PromptVersionEvaluationMatrix`
- model availability/fallback matrix: implemented through `ModelFallbackMatrix`
- safety probe support: partially covered through text/structured assertions and fallback metadata; richer probe types remain future work
- token and latency report models: implemented through `EvaluationRunMetrics`
- JSON report output: implemented on prompt reports and debug bundles
- local-only debug bundle format: implemented through `LocalDebugBundle`

Acceptance criteria:

- Chime In can run extraction regression cases against local model output and deterministic fallbacks.
- Prompt changes produce reviewable reports.

Remaining refinements can happen in later phases: first-class safety probe models, richer structured assertion helpers, file-writing helpers with explicit redaction policy, report diffing, JUnit/CI output, and DocC examples.

## Phase 6: Provider-Neutral Client Layer

Status: completed for the first public adapter slice.

Add Swift-native provider access that can support local Foundation Models plus explicitly configured external providers:

- provider-neutral `LLMClient` protocol: implemented
- `LLMRequest`, `LLMResponse`, `LLMMessage`, response formats, tools, tool calls, streaming events, and normalized client errors: implemented
- provider capability negotiation: implemented through `LLMClientCapabilities`
- type-erased `AnyLLMClient`: implemented
- fallback `LLMRouter`: implemented with retryable error policy and before-output streaming fallback
- high-level `LLMPipeline` over prompt contracts and optional local RAG: implemented
- Foundation Models conformance to `LLMClient`: implemented
- OpenAI Responses API adapter: implemented
- Anthropic Messages API adapter: implemented
- injectable response and streaming HTTP transports for provider tests: implemented
- provider-native tool result message mapping: implemented for OpenAI `function_call_output` and Anthropic `tool_result`

Acceptance criteria:

- A Swift app can initialize Foundation Models, OpenAI, Anthropic, or a router from the same core API.
- Provider adapter tests do not require real API keys or network calls.
- API key storage remains an app concern.

Remaining refinements can happen in later phases: provider-specific structured output affordances, stricter schema validation, request/response trace redaction, retry/backoff policy hooks, and richer token/cost accounting for tool-heavy conversations.

## Phase 6.5: Workflow Orchestration

Status: completed for the first Chime In adoption slice.

Add a small production orchestration layer over the existing primitives:

- typed sequential workflow runner: implemented through `LLMWorkflow`
- composable steps: implemented through `LLMStep`
- deterministic analysis step helper: implemented
- local retrieval/context packing step helper: implemented through `LocalRAGPipeline`
- context planning step helper: implemented through `CompiledPrompt` and `LLMContextPlan`
- structured generation step helper: implemented through `GenerationCandidate` and `StructuredGenerationCandidate`
- validation step helper: implemented through `StructuredGenerationValidator`
- repair/fallback step helper: implemented through `StructuredGenerationRepairPolicy`, `StructuredGenerationFallbackPolicy`, and `FallbackReason`
- workflow diagnostics: implemented through `LLMWorkflowResult`, `LLMWorkflowEvent`, intermediate output capture, provider metadata, token/context reports, validation issues, evidence spans, and source references

Acceptance criteria:

- Chime In can express its extraction path without creating a broad public agent framework.
- Hosted Plus prompt shaping can remain backend-owned because the workflow layer only runs app-provided closures.
- Local-first fallback remains explicit and testable.

Remaining refinements can happen after Chime In integration: better dynamic fallback closures,
typed timestamp evidence helpers, richer repair-loop policies, and DocC examples.

## Phase 6.75: WWDC26 Readiness And Production Polish

Status: completed for pre-SDK readiness.

Prepare SwiftLLM for the OS 27 Foundation Models generation and public package adoption without breaking the current SDK baseline:

- provider-neutral endpoint descriptors for locality and routing policy: implemented through `LLMEndpointRegistry`, `LLMEndpoint`, and `LLMRoutingPlan`
- Private Cloud Compute readiness through provider-neutral quota, reasoning, and cloud locality types: implemented in `SwiftLLMFoundationModels`
- context compiler v2 with fixed-cost accounting, retrieved-context packing, dropped snippets, citations, budget reports, and compiled prompts: implemented through `LLMContextCompiler`
- run receipts for generation routing, fallback, unsupported capability skips, timing, redaction, and token usage: implemented through `LLMRunReceipt`
- token usage expansion for cached input tokens and reasoning tokens: implemented
- file organization pass for large source and test files: completed for core client, router, context, retrieval, workflow, structured generation, Foundation Models, evaluation, provider tests, and broad core tests
- docs and README examples that distinguish shipping APIs from planned SDK-gated work: updated
- context snapshots, compaction previews, omitted-source reasons, and cache-aware diagnostics
- stream event expansion for metadata and usage deltas
- tool calling mode and transcript error policy types
- Foundation Models OS 27 adapter work after the local SDK is installed
- Evaluations framework alignment while keeping `SwiftLLMEvaluation` useful without Xcode 27
- DocC examples

Acceptance criteria:

- SwiftLLM can describe on-device, PCC, external cloud, and local custom-model endpoints without app-specific concepts.
- Context decisions are inspectable through snapshots and receipts.
- The package remains buildable with the supported SDK until OS 27 symbols are guarded.
- Apps can make local-first vs cloud-allowed routing decisions with explicit policy.

Reference:

- [WWDC26 Readiness](14-wwdc26-readiness.md)

## Phase 8: OS 27 Adoption And 2.0 Audit

Status: implemented, pending Xcode 27 verification.

- Private Cloud Compute execution target, availability, quota, and reasoning levels: implemented behind the OS 27 SDK gate
- platform-reported context size for on-device and Private Cloud Compute targets: implemented
- OS 27 error taxonomy and deprecation handling: implemented
- native Foundation Models streaming and usage-based token accounting: implemented
- provider-neutral reasoning effort, reasoning stream events, and provider content replay: implemented
- provider adapter fixes for incremental SSE, sampling rejection on reasoning models, Responses API `stop`, refusals, incomplete responses, error classification, and transport normalization: implemented
- workflow, structured generation, chunking, retrieval, registry, and evaluation fixes from the 2.0 audit: implemented
- verify the gated path with Xcode 27 on a device that supports Private Cloud Compute: pending
- Dynamic Profiles, session reuse, transcript compaction, provider bridge, image attachments, and watchOS 27: not started

Reference:

- [2.0.0 Release Notes](16-2.0.0-release-notes.md)

## Phase 7: Open Source Preparation

Status: completed for local `1.0.0` release prep.

Completed:

- choose license: completed with Apache-2.0
- replace initial security stub: completed with GitHub Security Advisory reporting path
- expand README: completed for the first public-facing pass
- finalize contribution guide details: completed for the first public-facing pass
- audit docs for private Chime In details: completed with synthetic examples retained where useful
- finalize API stability policy: completed for semantic versioning from `1.0.0`
- expand DocC documentation: completed enough for local DocC build, with examples to grow over time
- split large source files and tests: completed for current release scope
- prepare `1.0.0` tag: completed after final validation

Post-release polish:

- harden CI across additional supported Xcode versions as they become available
- add sample screenshots or terminal/demo visuals after the showcase UI has enough surface area

## Later: Custom Adapters

Custom adapters may become useful, but they should not lead the package.

A future adapter manager could handle:

- entitlement checks
- adapter availability
- adapter version compatibility
- download/asset status
- base model version compatibility
- fallback to base model
- Foundation Models `LanguageModel` provider-package bridging
- Core AI or MLX-backed local language model descriptors

This should wait until the core orchestration layer is useful.
