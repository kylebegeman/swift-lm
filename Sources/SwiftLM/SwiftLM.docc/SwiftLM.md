# ``SwiftLM``

Build local-first language model features with explicit prompt, context, retrieval, validation, and fallback primitives.

## Overview

SwiftLM is the provider-neutral core target. It does not import Apple's Foundation Models framework and does not perform network access. The target is intended to stay useful even when a model is unavailable, because most production reliability work happens before and after generation.

Use this product to:

- define prompt contracts and examples
- budget and pack context
- split long text and transcript inputs
- run map/reduce pipelines
- retrieve and cite local context
- compose typed workflows for deterministic analysis, retrieval, generation, validation, and fallback
- call provider-neutral clients
- route across provider fallbacks with capability checks
- validate generated evidence
- describe fallback behavior

## Topics

### Provider Clients

- ``LMClient``
- ``AnyLMClient``
- ``LMRouter``
- ``LMClientCapabilities``
- ``LMCapability``
- ``LMRouterFallbackPolicy``
- ``LMStreamFallbackMode``
- ``LMRequest``
- ``LMResponse``
- ``LMStreamEvent``
- ``LMMessage``
- ``LMProviderContent``
- ``LMReasoningEffort``
- ``LMGenerationParameters``
- ``LMResponseFormat``
- ``LMJSONSchema``
- ``LMToolDefinition``
- ``LMToolChoice``
- ``LMToolCall``
- ``LMPipeline``
- ``LMPromptTask``

### Prompting

- ``PromptContract``
- ``PromptExample``
- ``ExampleSelector``
- ``CompiledPrompt``

### Context

- ``TokenBudget``
- ``TokenCounter``
- ``TextChunker``
- ``BoundaryAwareTextChunker``
- ``TranscriptChunker``
- ``ContextPacker``

### Local Retrieval

- ``SourceReference``
- ``RetrievableDocument``
- ``LocalRetrievalQuery``
- ``LocalRetriever``
- ``KeywordLocalRetriever``
- ``LocalRAGPipeline``
- ``CitationContextRenderer``

### Structured Generation

- ``StructuredGenerationSchema``
- ``StructuredGenerationContract``
- ``StructuredGenerationCandidate``
- ``StructuredGenerationValidator``
- ``StructuredGenerationPipeline``

### Workflow Orchestration

- ``LMWorkflow``
- ``LMStep``
- ``LMWorkflowContext``
- ``LMWorkflowResult``
- ``LMWorkflowEvent``
- ``LMWorkflowError``

### Validation And Fallback

- ``GroundingValidator``
- ``FallbackReason``
- ``FallbackDecision``
- ``GenerationCandidate``

### Metadata And Diagnostics

- ``LMProviderMetadata``
- ``LMPrivacyMode``
- ``LMTokenUsage``
- ``LMRunReceipt``
- ``LMEndpointRegistry``
- ``JSONValue``
