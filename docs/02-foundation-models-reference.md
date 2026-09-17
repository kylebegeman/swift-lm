# Foundation Models Reference

## Source Documents

This package is shaped by Apple's official Foundation Models documentation:

- [Foundation Models overview](https://developer.apple.com/documentation/FoundationModels)
- [Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)
- [Generating Swift data structures with guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
- [Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
- [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Analyzing runtime performance](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app)
- [Improving safety from generative model output](https://developer.apple.com/documentation/foundationmodels/improving-safety-from-generative-model-output)
- [Supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
- [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels)
- [Loading and using a custom adapter](https://developer.apple.com/documentation/FoundationModels/loading-and-using-a-custom-adapter-with-foundation-models)
- [WWDC26: What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
- [WWDC26: Build with the new Apple Foundation Model on Private Cloud Compute](https://developer.apple.com/videos/play/wwdc2026/319/)
- [WWDC26: Build agentic app experiences with the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/242/)
- [WWDC26: Bring an LLM provider to the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/339/)
- [SwiftLM WWDC26 Readiness](14-wwdc26-readiness.md)

## Platform Facts

Foundation Models is available on Apple platforms introduced with iOS, iPadOS, macOS, Mac Catalyst, and visionOS 26. The OS 27 releases add watchOS through Private Cloud Compute.

The package targets iOS 26, macOS 26, and visionOS 26 because the first useful version is built around Foundation Models and Apple Intelligence-era APIs.

The OS 27 generation expands Foundation Models with Private Cloud Compute, platform-reported context size, reasoning levels, usage reporting, tool calling modes, image input, Dynamic Profiles, provider packages through `LanguageModel`, a new error taxonomy, Evaluations, `fm`, Python SDK support, Core AI, and MLX integrations. SwiftLM 2.0 adopts the session-level pieces (Private Cloud Compute, context size, reasoning, usage, tool calling modes, and errors) behind an SDK gate and represents the rest with provider-neutral types.

The gate is `#if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY`, because Xcode 27 ships Swift 6.4 with the OS 27 SDKs, plus `#available` checks for the 27 releases at runtime. The package builds with Xcode 26 and runs on OS 26 devices; the OS 27 paths activate when the app is built with Xcode 27 and runs on an OS 27 device.

Two OS 27 deprecations matter for adopters: `GenerationOptions(sampling:)` became `GenerationOptions(samplingMode:...)`, and `LanguageModelSession.GenerationError` was replaced by `LanguageModelError`, `SystemLanguageModel.Error`, and `LanguageModelSession.Error`. Apps built with Xcode 27 receive the new error types on OS 27 devices, so the adapter normalizes both generations.

## Model Availability

Apps must check availability before calling the model. Availability depends on:

- device eligibility
- Apple Intelligence being enabled
- model assets being downloaded and ready
- supported locale/language
- OS and SDK availability

SwiftLM should not let app code treat the local model as guaranteed. Every high-level workflow should have a fallback path.

## Model Strengths

The on-device model is a good fit for:

- summarization
- entity extraction
- text understanding
- rewriting/refining text
- classification
- tag generation
- app-specific generation with tools
- structured output with guided generation

This maps well to Chime In's extraction needs and to many local-first Apple apps.

## Model Weaknesses

Apple's docs call out categories that are not ideal:

- basic math
- code generation
- fragile logical reasoning
- open-ended world knowledge
- large unbounded tasks

SwiftLM should bias toward narrow tasks and deterministic post-processing. It should not encourage developers to ask the local model to be a general assistant.

## Context Window

The OS 26.0 on-device foundation model has a 4,096-token context window per language model session. Newer releases and hardware report larger sizes, such as 8,192 tokens on the OS 27 releases for newer devices, and Private Cloud Compute provides a 32K context window.

Apps should not assume a fixed size. `SystemLanguageModel.contextSize` is back-deployed to the OS 26.0 releases, and `PrivateCloudComputeLanguageModel.contextSize` exists on the 27 releases. `FoundationModelClient.runtimeProfile(for:)` reads them, and the provider-neutral `capabilities.contextWindowTokens` follows the reported value. `FoundationModelDefaults.onDeviceContextWindowTokens` and `privateCloudContextWindowTokens` remain only as documented fallbacks for tests and planning.

The context window includes:

- instructions
- prompts
- tool schemas
- tool arguments
- tool outputs
- generable schemas
- model responses
- session transcript history

This is the main architectural constraint. SwiftLM treats token budgeting as a first-class runtime concern: the adapter queries the platform context size and falls back to conservative defaults only when the platform cannot report it.

Exact token counting through `SystemLanguageModel.tokenCount(for:)` is available on the 26.4 releases and later for prompts, instructions, tools, schemas, and transcript entries. The adapter exposes an async token-count API, measures instructions, prompt, and tool definitions after each on-device request, and falls back to the core heuristic counter when exact counting is unavailable. On the 27 releases, Apple's usage reports replace the measurement for every target, including Private Cloud Compute, which has no client-side tokenizer.

## Private Cloud Compute

Private Cloud Compute gives eligible apps access to a larger Apple Foundation Model through the Foundation Models API. Important properties:

- same session-style API as on-device Foundation Models
- no app-managed API key for Apple's PCC model
- Apple Intelligence availability is still required
- network connectivity is required
- per-user daily quota applies
- iCloud+ users can have higher limits
- the model has a 32K context window
- reasoning levels are available
- quota usage should be handled with persistent UI, not a dismissible alert

SwiftLM should represent PCC as a distinct model locality. It can be privacy-preserving and OS-managed while still being cloud execution. Apps should be able to express policies such as local-only, local-preferred, PCC-allowed, or external-cloud-allowed.

`SwiftLMFoundationModels` implements this layer:

- `FoundationModelExecutionTarget` distinguishes automatic, on-device, Private Cloud Compute, provider package, and custom local execution. `automatic` resolves to the on-device model; Private Cloud Compute is always an explicit choice.
- `FoundationModelClient.availability(for:)` reports Private Cloud Compute eligibility (`deviceNotEligible`, `systemNotReady`), locale support, and quota exhaustion before a request is made.
- `FoundationModelRuntimeProfile` records the reported context window, capability flags (reasoning, tool calling, guided generation, vision), and `FoundationModelQuotaStatus` (`available`, `approachingLimit`, `exhausted`, `notApplicable`, `unknown`), mapped from Apple's `quotaUsage`.
- `FoundationModelGenerationOptions` carries the execution target, `LMReasoningEffort`, and `FoundationModelToolCallingMode`.
- `FoundationModelClient.targeting(_:)` returns a client whose provider-neutral conformance uses another target, so apps can register an on-device endpoint and a Private Cloud Compute endpoint in the same `LMEndpointRegistry`.
- Quota exhaustion during a request becomes `FoundationModelFailureReason.quotaLimitReached(resetsAt:limitIncreaseSuggestionAvailable:)` and `FallbackReason.quotaExceeded`, which the default router policy treats as retryable so a local endpoint can take over.

Private Cloud Compute requires the managed entitlement from Apple. Eligibility and program membership are product decisions, not package switches.

## Reasoning

PCC reasoning lets the model spend additional generated text before producing the final answer. The reasoning segment can improve quality, but it consumes context tokens and may increase latency. Deep reasoning can use more tokens than the final answer.

SwiftLM models reasoning as:

- a provider-neutral request preference: `LMGenerationParameters.reasoningEffort` maps `low`, `medium`, and `high` to Apple's `light`, `moderate`, and `deep` levels
- a capability: on-device requests that set an effort are rejected as unsupported, so routers fall back instead of silently ignoring the request
- a token-usage field: `LMTokenUsage.reasoningTokens` comes from Apple's usage report on the 27 releases
- observable text: `FoundationModelGenerationResponse.reasoningText` and `LMResponse.reasoningText` capture the transcript's reasoning entries

Reasoning should not be treated as a free quality upgrade. It consumes context tokens and adds latency, especially at the deep level.

`LMTokenUsage`, `LMTokenUsageReceipt`, and `EvaluationRunMetrics` include optional `cachedInputTokens`, `cacheWriteInputTokens`, and `reasoningTokens` fields so every provider's usage report maps into the same metrics shape.

## Guided Generation

Guided generation lets developers define Swift structures with `@Generable` and ask the model to generate typed results.

Useful implications:

- Apps can avoid parsing free-form strings.
- Schemas constrain malformed output.
- Property names and guides consume context.
- Large nested schemas can be expensive.
- Array count limits matter for quality and token usage.

SwiftLM should help developers keep schemas compact and validate the result after generation.

`SwiftLMFoundationModels` exposes typed generation only inside `#if canImport(FoundationModels)` availability, so package tests and deterministic fallbacks can still compile on toolchains that do not ship the framework.

## Tool Calling

Tools let the model call app code to retrieve local data, perform app-specific work, or integrate with other Apple frameworks.

Tool calling is powerful but costly:

- tool descriptions consume tokens
- tool argument schemas consume tokens
- tool outputs consume tokens
- multiple tools can be called in parallel
- tool errors need explicit handling

SwiftLM should encourage a small number of task-specific tools. If a tool is always needed, app code should often run it directly and pack the result into the prompt instead of asking the model to decide.

`SwiftLMFoundationModels` exposes a typed tool path behind `#if canImport(FoundationModels)`:

- pass native `[any Tool]` values to `FoundationModelClient.respond(to:tools:)`
- pass native tools to typed guided generation through `respond(generating:request:tools:)`
- prewarm sessions with the same tool set through `prewarm(_:tools:)`
- use `FoundationModelToolConfiguration` when an app needs a small value wrapper for names and estimated definition-token cost

Provider-neutral `LMClient` calls still reject tool requests for Foundation Models. That boundary is intentional: Apple's `Tool` protocol depends on concrete Swift associated types and app-owned code, so the generic adapter should not pretend it can execute arbitrary provider-neutral tools locally.

## Conversations

Provider-neutral requests with several messages become a real Foundation Models transcript. System and developer messages join the instructions, earlier user and assistant messages become prompt and response entries, and the trailing user messages become the prompt. Consecutive messages from the same role are merged. Requests must end with a user message; assistant prefill is rejected as unsupported.

Each stateless request still opens a fresh session. For a chat-style feature, `FoundationModelSession` keeps one `LanguageModelSession` alive, so the model reuses its transcript and key-value cache between turns and native tools stay available. Requests on one session must not overlap; the framework reports overlapping requests as `concurrentRequests`.

```swift
let session = try await FoundationModelSession(
  instructions: "Help plan the trip.",
  tools: [WeatherTool()]
)
let first = try await session.respond(to: "What should I pack for Lisbon?")
let second = try await session.respond(to: "And for a day trip to Sintra?")
```

## Images

`LMImage` attaches encoded image data or a local file to a user message. On the OS 27 releases the adapter sends images as prompt attachments when the resolved model reports the vision capability, and the provider-neutral capability set includes `imageInput` only in that case. Foundation Models does not download remote images, so remote URLs are rejected as unsupported and a router can fall back to a provider that fetches them.

## Custom Language Models

On the OS 27 releases, `FoundationModelClient.live(model:executionTarget:contextWindowTokens:)` wraps any `LanguageModel`: a Core AI or MLX model, or a provider package from a model vendor. The client uses the model for every request, reads its capabilities, and describes it with the execution target you pass, so `.customLocal` models report local privacy and `.providerPackage` models report external privacy. `LanguageModel` has no context-size or availability API, so pass the context window when you know it.

SwiftLM does not publish its own clients as `LanguageModel` providers. Model vendors ship Foundation Models packages for that, and those packages plug into this initializer.

## Dynamic Profiles

Dynamic Profiles let a `LanguageModelSession` change active model, tools, instructions, generation options, and transcript treatment before each prompt. They are useful for multi-phase features that move between cheaper on-device work and higher-capability server work.

Important transcript rules from WWDC26:

- `historyTransform` applies a lossless per-request transform.
- Mutating session history is lossy and affects all profiles.
- Appending transcript entries usually preserves key-value cache behavior best.
- Rewriting history, changing instructions, or changing tools can invalidate caches.
- Tool calling can be allowed, disallowed, or required.
- Required tool calling needs an exit condition.
- Preserving transcript state after an error is advanced and requires app repair logic.

SwiftLM translates these concepts into context compiler and workflow primitives rather than copying Apple's API surface directly. `FoundationModelToolCallingMode` maps to Apple's tool calling modes on the 27 releases and is rejected on OS 26 SDKs instead of silently allowing tool calls.

SwiftLM does not wrap Dynamic Profiles. They are a result-builder API whose value comes from Apple's own session lifecycle, and a wrapper would hide it. Apps that want profiles use `LanguageModelSession` directly. Apps that want provider-neutral phases compose `LMWorkflow` steps that call different clients, such as an on-device client for extraction and a Private Cloud Compute client for synthesis. Context snapshots, compaction previews, and transcript error policy remain future work.

## Provider Packages

The OS 27 Foundation Models provider model is based on `LanguageModel` and `LanguageModelExecutor`:

- `LanguageModel` describes capabilities and configuration.
- `LanguageModelExecutor` handles prewarm, request translation, streaming, usage, metadata, and errors.
- Executors can be cached by configuration inside a session.
- Providers receive the full transcript on every request and decide whether history was appended or rewritten.
- Providers can stream metadata, usage, text, tool calls, reasoning, and custom segments.

SwiftLM's provider-neutral layer should stay compatible with that shape:

- richer endpoint descriptors
- stream events for metadata and usage deltas
- token usage fields for cached input and reasoning tokens
- provider error normalization
- explicit privacy and authentication boundaries
- no hidden app-local tool execution

## Context And Agent-Like Planning

Apple's session model gives SwiftLM enough primitives to build focused, pseudo-agent workflows
without adopting a heavyweight agent framework:

- `Instructions` define trusted role and behavior context.
- `Prompt` carries the user/app task payload.
- `Transcript` can rehydrate an existing session history when a workflow really needs continuity.
- `Tool` exposes app code for local retrieval or side-effect boundaries.
- `@Generable`/guided generation constrains structured outputs.
- `prewarm(promptPrefix:)` lets apps reduce latency for predictable prompt prefixes.

SwiftLM models this through `LMContextPlan`. A context plan records which parts of a request occupy
the model's context window, which parts are trusted, whether session transcript rehydration is
expected, whether tool definitions are available to the model, and whether the app should prefetch
context before generation. This keeps Chime In-style workflows explainable: app code can run local
search and deterministic analysis first, feed compact context to Foundation Models, and reserve native
tool calling for cases where model-directed lookup is genuinely useful.

The generic Foundation Models client deliberately treats tool items in a context plan as planning metadata. It can carry context plans, budget them, and expose required capabilities; native `Tool` execution is available only through the typed Foundation Models adapter because Apple's `Tool` protocol requires concrete Swift types.

## Safety and Guardrails

Foundation Models includes built-in safety behavior, but app-specific safety is still required.

SwiftLM should support:

- fixed-task prompt contracts
- deny lists where appropriate
- structured output boundaries
- validation hooks
- safety evaluation corpora
- local feedback capture
- refusal and guardrail error handling

The package should not bypass safety controls casually.

The adapter normalizes guardrail, refusal, unsupported-locale, context-window, decoding, rate-limit, concurrent-request, unsupported-guide, asset, tool-call, and generic provider failures into `FoundationModelFailure` and maps each to a package-level `FallbackReason`. On the 27 releases it also normalizes timeouts, unsupported capabilities, unsupported transcript content, transcript mutation during a response, Private Cloud Compute quota exhaustion, network failures, and service unavailability. Refusal explanations are captured on both generations when the model provides them.

## Streaming

`FoundationModelClient.stream(_:)` wraps `LanguageModelSession.streamResponse`, turns Apple's cumulative snapshots into text deltas, and ends with a completed response that carries the same usage, reasoning text, and runtime profile as `respond`. The provider-neutral `stream(to:)` uses it, so routers receive real incremental output from the on-device model.

## Performance

Apple's Foundation Models instrument exposes model loading, prompt processing, inference, tool calling, and token usage. The docs recommend profiling with additional CPU and power instruments.

SwiftLM should make performance easier to understand by preserving:

- prompt version
- provider metadata
- token estimates
- measured token counts when available
- request duration
- fallback reason
- validation failures

## Model Updates

Apple updates the system model with OS releases. Documentation already notes model changes aligned with OS version ranges and recommends testing prompts with new model versions.

SwiftLM should assume model behavior is not static. Prompt contracts and evaluation corpora must be versioned.
