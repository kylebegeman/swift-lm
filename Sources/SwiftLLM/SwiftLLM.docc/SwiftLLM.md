# ``SwiftLLM``

Build local-first language model features with explicit prompt, context, retrieval, validation, and fallback primitives.

## Overview

SwiftLLM is the provider-neutral core target. It does not import Apple's Foundation Models framework and does not perform network access. The target is intended to stay useful even when a model is unavailable, because most production reliability work happens before and after generation.

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

- ``LLMClient``
- ``AnyLLMClient``
- ``LLMRouter``
- ``LLMClientCapabilities``
- ``LLMCapability``
- ``LLMRouterFallbackPolicy``
- ``LLMStreamFallbackMode``
- ``LLMRequest``
- ``LLMResponse``
- ``LLMStreamEvent``
- ``LLMMessage``
- ``LLMProviderContent``
- ``LLMReasoningEffort``
- ``LLMGenerationParameters``
- ``LLMResponseFormat``
- ``LLMJSONSchema``
- ``LLMToolDefinition``
- ``LLMToolChoice``
- ``LLMToolCall``
- ``LLMPipeline``
- ``LLMPromptTask``

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

- ``LLMWorkflow``
- ``LLMStep``
- ``LLMWorkflowContext``
- ``LLMWorkflowResult``
- ``LLMWorkflowEvent``
- ``LLMWorkflowError``

### Validation And Fallback

- ``GroundingValidator``
- ``FallbackReason``
- ``FallbackDecision``
- ``GenerationCandidate``

### Metadata And Diagnostics

- ``LLMProviderMetadata``
- ``LLMPrivacyMode``
- ``LLMTokenUsage``
- ``LLMRunReceipt``
- ``LLMEndpointRegistry``
- ``JSONValue``
