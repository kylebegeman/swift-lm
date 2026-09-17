# WWDC26 Readiness

SwiftLM should stay source-compatible with the currently supported SDK while preparing its abstractions for the Foundation Models changes Apple introduced at WWDC26.

This document records the durable conclusions from the WWDC26 transcript pass and official Apple source review. SwiftLM 2.0 implements the session-level OS 27 adoption described here behind an SDK gate; the status section at the end says what shipped and what remains.

## Source Material

Official Apple pages:

- [Apple Intelligence What's New](https://developer.apple.com/apple-intelligence/whats-new/)
- [Foundation Models documentation](https://developer.apple.com/documentation/foundationmodels)
- [Private Cloud Compute](https://developer.apple.com/private-cloud-compute/)
- [What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
- [Build with the new Apple Foundation Model on Private Cloud Compute](https://developer.apple.com/videos/play/wwdc2026/319/)
- [Build agentic app experiences with the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/242/)
- [Bring an LLM provider to the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/339/)
- [Build AI-powered scripts with the fm CLI and Python SDK](https://developer.apple.com/videos/play/wwdc2026/334/)

Local transcript bundle reviewed:

- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-240.txt`
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-241.txt`
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-242.txt`
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-297.txt`
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-319.txt`
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-324.txt`
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-325.txt`
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-334.txt`
- `/Users/kyle/Downloads/wwdc-foundation/wwdc2026-339.txt`

## Major Platform Changes

### Foundation Models As A Model Abstraction

Foundation Models is expanding from an Apple on-device model API into a common Swift session API for multiple language models. The new `LanguageModel` protocol and `LanguageModelExecutor` shape allow Apple on-device models, Private Cloud Compute, Core AI, MLX, third-party cloud providers, and community packages to back `LanguageModelSession`.

SwiftLM implication:

- Keep `LMClient` provider-neutral.
- Add richer endpoint descriptors that can represent locality, context size, quota, cost, health, usage, and routing policy.
- Keep Foundation Models imports isolated to `SwiftLMFoundationModels`.

### Private Cloud Compute

`PrivateCloudComputeLanguageModel` gives eligible apps access to a larger Apple Foundation Model through Private Cloud Compute. It uses the same Foundation Models session style, supports a 32K context window, supports reasoning, requires Apple Intelligence availability, and has per-user daily usage limits.

SwiftLM implication:

- Add provider-neutral types for private cloud locality, quota status, reasoning effort, and dynamic context size before importing iOS 27 symbols.
- Make routing able to prefer on-device execution for offline or low-latency tasks and PCC for larger-context or higher-reasoning tasks.
- Treat PCC as networked execution in policy and diagnostics, even though Apple provides strong privacy guarantees and OS-managed authentication.

### Reasoning And Token Accounting

PCC reasoning appears as extra generated transcript content before the final answer. It can improve quality, but it consumes context tokens and can increase latency. WWDC26 also highlights usage properties for token accounting, including cached input tokens and reasoning tokens.

SwiftLM implication:

- Extend token usage and budget reports to represent reasoning tokens and cached input tokens.
- Treat reasoning as an observable transcript or stream event where the provider supports it.
- Reserve budget for reasoning when routing to reasoning-capable models.

### Dynamic Profiles And Transcript Management

Dynamic Profiles allow a session to change model, tools, instructions, generation options, and transcript treatment before each prompt. The transcript guidance is especially relevant:

- `historyTransform` is a lossless per-request transform.
- Mutating session history is lossy and affects all profiles.
- Appending transcript entries best preserves key-value cache behavior.
- Rewriting history, changing instructions, or changing tools can invalidate caches.
- Tool calling mode can be allowed, disallowed, or required.
- Required tool calling needs an exit condition.
- Transcript error handling can revert or preserve partial state.

SwiftLM implication:

- Add a context compiler that distinguishes lossless request transforms from persisted lossy compaction.
- Add context snapshots and compaction previews.
- Add cache-aware diagnostics when context is rewritten.
- Add provider-neutral tool calling mode and transcript error policy types.

### Provider Packages

The provider session explains that `LanguageModelExecutor` should handle prewarming, request translation, streaming events, metadata, usage, transcript comparison, cache invalidation, and provider-specific errors. It also highlights custom segments and response metadata for citations, new modalities, server-side tools, and performance metrics.

SwiftLM implication:

- Expand stream events to support metadata and usage deltas before completion.
- Prefer built-in error taxonomies where possible and keep provider-specific errors typed.
- Represent server-side tools as provider capabilities and response metadata, not hidden app-local side effects.
- Keep authentication and credential persistence out of the package unless a future provider bridge has an explicit design.

### Core AI, MLX, And Custom Local Models

Core AI and MLX create a path for local custom language models that can plug into Foundation Models. Core AI also introduces model specialization, model cache behavior, key-value cache state, ahead-of-time compilation, and local debugging tools.

SwiftLM implication:

- Do not add a Core AI dependency to the core package now.
- Make endpoint descriptors capable of representing local bundled and downloaded models.
- Consider future fields for prewarm cost, specialization status, asset size, and cache readiness.

### Evaluations, fm, And Python

The Evaluations framework, `fm` CLI, and Foundation Models Python SDK create a better prompt iteration loop:

- Prototype prompts with `fm chat` or `fm respond`.
- Use schemas and images from the command line when useful.
- Use Python notebooks and data tooling for dataset generation, grading, and charts.
- Bring stable prompt versions back into Swift as `PromptContract` values.
- Track prompt regressions with `SwiftLMEvaluation`.

SwiftLM implication:

- Keep `SwiftLMEvaluation` independent of Xcode 27, but design report shapes that can align with Apple's Evaluations framework later.
- Add import/export helpers only when real datasets prove the need.

### App Intents, Visual Intelligence, And Spotlight

App Intents, Visual Intelligence, Spotlight, view annotations, and system store integrations are app-layer features. They should not become core SwiftLM dependencies.

SwiftLM implication:

- Provide context, retrieval, citation, validation, and evaluation primitives that apps can use behind App Intents and Visual Intelligence flows.
- Avoid owning Siri schemas, view annotations, or Visual Intelligence provider UX.
- Consider docs for using SwiftLM behind App Intents and Core Spotlight RAG.

## Planned SwiftLM Work

Implemented in 2.0:

- Provider-neutral execution target, quota, reasoning, and runtime profile models.
- `PrivateCloudComputeLanguageModel` support behind the SDK gate and availability checks, including locale support and quota state before a request.
- Platform-reported `contextSize` for on-device and Private Cloud Compute targets.
- Apple quota usage mapped into `FoundationModelQuotaStatus`, and quota exhaustion mapped to `FallbackReason.quotaExceeded`.
- Reasoning levels mapped from `LMReasoningEffort`, rejected where the resolved model cannot reason.
- Usage-based token accounting with cached input tokens and reasoning tokens.
- The OS 27 error taxonomy normalized alongside the OS 26 generation errors.
- Tool calling modes.
- Native streaming, plus `LMStreamEvent.reasoningDelta` and `LMStreamEvent.usage` for providers that report before completion.
- Provider-native content replay (`LMProviderContent`) so reasoning items and thinking blocks survive tool loops.
- Endpoint registry and routing plans with explicit fallbacks, and run receipts for streaming routes.
- A showcase panel for Private Cloud Compute availability, context window, reasoning support, and quota.
- Multi-turn transcripts for provider-neutral requests, and `FoundationModelSession` for reusable conversations.
- Image attachments for models that report the vision capability.
- `FoundationModelClient.live(model:executionTarget:contextWindowTokens:)` for Core AI, MLX, and provider-package `LanguageModel` values.
- Verification on GitHub's `xcode-27` image: a strict build, the full test suite on macOS 27, and the showcase build for the iOS 27 simulator.

Still planned:

- Run a Private Cloud Compute feature on a device with the managed entitlement.
- Transcript compaction, context snapshots, cache-aware diagnostics, and transcript error policy types.
- Images in earlier conversation turns, and tool calls in provider-neutral Foundation Models history.
- Private Cloud Compute on Apple Watch. The package already builds for watchOS 26 and 27; the Foundation Models adapter is excluded there until the watchOS paths avoid the on-device model and the OS 26 error types, which Apple marks unavailable on watchOS.
- Evaluations framework alignment.

Decisions:

- The package minimum stays at the OS 26 releases. OS 27 features are gated, so raising the minimum would drop OS 26 devices without adding capability.
- Dynamic Profiles are not wrapped. Apps use Apple's API directly or compose `LMWorkflow` steps across clients.
- SwiftLM consumes `LanguageModel` providers instead of publishing its OpenAI and Anthropic clients as providers, because the vendors ship their own Foundation Models packages.

## Non-Goals

- Do not turn SwiftLM into an App Intents framework.
- Do not add a Core AI dependency to `SwiftLM`.
- Do not make external providers implicit.
- Do not persist API keys, raw prompts, raw transcripts, or provider payloads by default.
- Do not promise unlimited PCC usage. Quota handling is required.
