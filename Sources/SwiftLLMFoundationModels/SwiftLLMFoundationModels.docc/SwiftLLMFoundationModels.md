# ``SwiftLLMFoundationModels``

Adapt Apple Foundation Models into SwiftLLM's provider-neutral metadata, generation, token counting, and fallback shapes.

## Overview

SwiftLLMFoundationModels is the only product that should import Apple's Foundation Models framework. It normalizes framework availability, generation responses, token counts, prewarming, and errors into SwiftLLM types so app code does not need to duplicate provider-specific handling.

Use this product to:

- check on-device and Private Cloud Compute availability, including quota, before generation
- read the platform-reported context window and model capabilities through runtime profiles
- prewarm Foundation Models sessions where available
- count tokens with the system tokenizer when possible
- generate and stream strings, and generate guided typed outputs
- ask for reasoning levels on targets that support them
- pass native Foundation Models `Tool` values through the typed adapter API
- call Foundation Models through the shared `LLMClient` protocol
- publish provider-neutral capabilities for routing decisions
- map Foundation Models failures, including OS 27 quota, timeout, and network failures, into fallback reasons
- test unavailable and fake-client paths without importing Foundation Models in the app's core logic

## Topics

### Client

- ``FoundationModelClient``
- ``FoundationModelGenerationRequest``
- ``FoundationModelGenerationResponse``
- ``FoundationModelGenerationOptions``
- ``FoundationModelToolCallingMode``
- ``FoundationModelStreamEvent``

### Execution Targets

- ``FoundationModelExecutionTarget``
- ``FoundationModelRuntimeProfile``
- ``FoundationModelQuotaStatus``

### Availability

- ``FoundationModelAvailability``
- ``FoundationModelUseCase``
- ``FoundationModelDefaults``

### Token Counting And Prewarming

- ``FoundationModelTokenCountRequest``
- ``FoundationModelPrewarmRequest``

### Failures

- ``FoundationModelFailure``
- ``FoundationModelFailureReason``
- ``FoundationModelErrorNormalizer``
