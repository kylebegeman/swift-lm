# Changelog

## 2.0.0 - Unreleased

Breaking: the package is now `swift-lm` with `SwiftLM*` products, and the `LLM` type prefix is now `LM` (`LMClient`, `LMRequest`, `LMRouter`, and so on). The library handles language models of every size, not only large ones. See `docs/16-2.0.0-release-notes.md` for the migration guide.

### Added

- OS 27 Foundation Models support behind an SDK gate: Private Cloud Compute as an execution target, platform-reported context size, reasoning levels, quota status, tool calling modes, usage-based token accounting, and the OS 27 error taxonomy (`LanguageModelError`, `SystemLanguageModel.Error`, `LanguageModelSession.Error`, `PrivateCloudComputeLanguageModel.Error`).
- Native Foundation Models streaming through `FoundationModelClient.stream(_:)` and `FoundationModelStreamEvent`, and a provider-neutral `stream(to:)` that uses it.
- `FoundationModelClient.availability(for:)`, `runtimeProfile(for:)`, `reportedRuntimeProfile(for:)`, `targeting(_:)`, `defaultExecutionTarget`, `defaultUseCase`, and `FoundationModelRuntimeProfile.capabilities`.
- `LMReasoningEffort` and `LMGenerationParameters.reasoningEffort`, mapped to Apple reasoning levels, OpenAI `reasoning.effort`, and Anthropic adaptive thinking with `output_config.effort`.
- `LMCapability.reasoning` and `LMCapability.forcedToolChoice`. Routers skip clients that cannot honor them.
- `LMStreamEvent.reasoningDelta` and `LMStreamEvent.usage`.
- `LMResponse.reasoningText`, `LMTokenUsage.cacheWriteInputTokens`, and `LMTokenUsage.measuredTotalTokens`.
- `LMProviderContent` and `LMMessage.providerContent`, so OpenAI reasoning items and Anthropic thinking blocks replay verbatim in tool loops.
- `LMPrivacyMode.privateCloudCompute`.
- `FallbackReason.quotaExceeded`, `FallbackReason.timeout`, `LMClientErrorReason.quotaExceeded`, and `LMClientErrorReason.timeout`. The default router policy retries both.
- `LMWorkflowError`, which carries the diagnostics accumulated before a step failed, and the `stepFailed` workflow event.
- Run receipts for `LMRouter.stream(to:)`.
- `LMEndpointRegistry.router(primaryID:usesRemainingEnabledEndpointsAsFallbacks:)`.
- OpenAI: `storesResponses` (default `false`), `acceptsSamplingParameters` with model-family defaults, reasoning effort, `response.incomplete` handling, refusal detection, flat stream `error` events, error code classification, encrypted reasoning replay, a ten-minute transport timeout, and `OpenAIHTTPTransport.live(session:)`.
- Anthropic: version-aware model-family rules (`AnthropicModelFamily`) for sampling, adaptive thinking, summarized thinking display, and forced tool choice; native structured output for strict schemas; opt-in prompt caching; opt-in strict tool schemas; thinking block capture and replay; `stop_reason` mapping for `refusal` and `model_context_window_exceeded`; error type classification; a ten-minute transport timeout; and `AnthropicHTTPTransport.live(session:)`.
- `JSONValue` accessors: `objectValue`, `arrayValue`, `stringValue`, `numberValue`, `intValue`, `boolValue`, `isNull`, and key and index subscripts.
- `Codable` on `PromptContract`, `PromptExample`, `LMProviderMetadata`, `LMTokenUsage`, `LMToolDefinition`, `LMJSONSchema`, `LMGenerationParameters`, `LMContextPlan`, `LMContextBudgetReport`, `EvidenceSource`, `EvidenceSpan`, `StructuredGenerationSourceContext`, `ValidationIssue`, `StructuredGenerationValidationResult`, and `PromptEvaluationCase`.
- `LMToolDefinition.estimatedDefinitionTokens(using:)`.
- A Private Cloud Compute panel in the showcase.
- Regression tests for every audit fix, the Foundation Models runtime behavior, and the Claude model-family rules. The suite now has 97 tests.

### Changed

- Foundation Models context windows are read from the platform (`contextSize`, back-deployed to the OS 26.0 releases) instead of a hard-coded 4,096.
- `FoundationModelGenerationOptions` uses `LMReasoningEffort?`, gains `toolCallingMode`, and drops `requestedContextWindowTokens`.
- `FoundationModelGenerationResponse` carries `finishReason`, `reasoningText`, and `runtimeProfile`. `estimatedOutputTokens` is a heuristic count of the output rather than the response cap.
- `FoundationModelQuotaStatus` cases are `available`, `approachingLimit`, `exhausted`, `notApplicable`, and `unknown`.
- `FoundationModelRuntimeProfile` reports `isContextWindowReported`, `modelIdentifier`, and capability flags. `reasoningEffort` moved to generation options.
- `FoundationModelFailureReason.contextExceeded` and `rateLimited` carry the context size, token count, and reset date when the platform reports them. New reasons cover quota, network, service, timeout, transcript, and unsupported capability failures.
- `FoundationModelClient.prewarm` is async because Private Cloud Compute availability is an async platform call.
- `FoundationModelDefaults.contextWindowTokens` was removed. Use `runtimeProfile(for:)`.
- `LMToolChoice.none` is now `LMToolChoice.noTools`, because an optional `toolChoice: .none` silently resolved to `Optional.none`.
- Provider SSE parsing dispatches each `data:` line immediately. Live `URLSession` line streams omit blank separators, so the previous parser delivered every event in one burst after the response finished.
- Provider transports normalize `URLError` into `LMClientError` so routers can fall back on network failures and timeouts.
- OpenAI: `stop` is no longer sent (the Responses API has no such parameter) and `.stopSequences` was removed from the OpenAI capabilities; replayed `function_call` items omit `id`; text parts are concatenated without separators; HTTP 408 and 504 map to `timeout`; failed payloads and stream failures classify by error code.
- Anthropic: `defaultMaxTokens` is 8,192; measured input tokens include cache reads and writes; text blocks are concatenated without separators; empty text blocks and empty assistant turns are omitted; empty tool results omit `content`; streams must end with `message_stop`; tool calls with invalid JSON arguments are dropped; `output_tokens_details.thinking_tokens`, which the API never returned, is gone.
- `LMEndpointRegistry.router(primaryID:)` no longer adds every other enabled endpoint as an implicit fallback, and a primary listed in `fallbackIDs` is not attempted twice.
- `LMRouter.capabilities.contextWindowTokens` is `nil` when any configured client's window is unknown, and the router checks for cancellation between attempts.
- `StructuredGenerationPipeline.run` throws, rethrows `CancellationError`, and classifies `LMFallbackClassifiableError` failures. `StructuredGenerationPipelineResult.output` is `nil` for rejected candidates and `candidateOutput` exposes the raw value.
- `LMStep.repairOrFallback` throws when validation rejected the candidate and no fallback resolves, instead of returning the rejected value.
- `LMStep.localRetrieval` no longer publishes packed snippets as evidence. They remain grounding sources.
- `TextChunker` clamps `overlapTokens` to half of `maxTokensPerChunk`.
- `KeywordLocalRetriever` orders tied chunks by document position instead of lexical id order.
- `LMContextCompiler` counts tool schemas as compact JSON and counts the rendered citation block; examples are accounted on the instructions surface. `LMContextPlan.foundationModelExtraction` no longer double-counts tools.
- `LocalDebugBundle` enforces its content policy by stripping raw outputs, `PromptVersionEvaluationReport.storesRawOutputs` is derived from its records, and evaluation text matching no longer depends on the device locale.
- `ModelFallbackMatrixEntry.id` is derived rather than stored.
- `LMRunReceiptError` and `LMWorkflowError` conform to `LocalizedError`.
- `LMRequest.requiredCapabilities()` includes `instructions` when the request carries instructions.
- `RetrievedSnippet` moved to `Retrieval/`, and `ContextPacker` moved to its own file.
- CI runs a matrix: Xcode 26.6 on `macos-26`, and Xcode 27 on GitHub's `xcode-27` preview image as a non-blocking job, with a strict warnings-as-errors build in both. Checkout moved to `actions/checkout@v7`.
- `scripts/validate.sh` works on Macs with only Command Line Tools: it points `swift test` at the bundled Swift Testing framework and skips the iOS showcase build when Xcode is not selected.

### Removed

- `LLMGenerationRun` and `LLMRunStatus` from 1.x, which nothing produced or consumed.
- `FoundationModelReasoningEffort`, replaced by `LMReasoningEffort`.
- `FoundationModelGenerationRequest.runtimeProfile`. The response reports the resolved profile.
- `PromptVersionEvaluationReport.init(...storesRawOutputs:)`. The flag is derived.

## 1.0.0 - 2026-06-24

- Split core client, router, context, retrieval, workflow, structured generation, Foundation Models, evaluation, and test coverage into smaller feature-focused files without changing behavior.
- Added bounded parallel map-reduce execution with input-order preservation for chunk pipelines.
- Added `LLMRunReceipt`, `LLMInstrumentedResponse`, router receipt callbacks, and redacted receipt support in `LocalDebugBundle`.
- Added `LLMContextCompiler` for fixed-cost context accounting, retrieved-snippet packing, dropped-snippet diagnostics, citation rendering, context plans, and compiled prompts.
- Updated `LLMPipeline` to use `LLMContextCompiler` internally and expose context compilation diagnostics.
- Added `LLMEndpointRegistry`, `LLMEndpoint`, and `LLMRoutingPlan` for provider-neutral endpoint registration and router construction.
- Added Foundation Models pre-SDK readiness types for execution targets, Private Cloud Compute runtime profiles, quota status, reasoning effort, and dynamic context-size hints.
- Added cached-input and reasoning-token accounting to `LLMTokenUsage`, OpenAI and Anthropic adapters, run receipts, and evaluation metrics.
- Fixed required local retrieval source precedence so user-required sources override allow-list omissions while explicit exclusions still win.
- Replaced the initial license stub with Apache-2.0.
- Replaced the initial security stub with a public vulnerability reporting policy and LLM-specific security scope.
- Reworked the README with badges, diagrams, quick-start examples, provider boundaries, evaluation guidance, and WWDC26 readiness notes.
- Updated contributing guidance for public package boundaries, Swift concurrency expectations, verification, and OS 27 SDK gating.
- Added durable WWDC26 readiness documentation covering Private Cloud Compute, reasoning, Dynamic Profiles, provider packages, Core AI, MLX, Evaluations, fm, and Python SDK implications.
- Updated the Foundation Models reference, roadmap, and open-source readiness docs for OS 27 planning and public-release polish.

## 0.1.0-rc.2

- Split the OpenAI and Anthropic adapters into transport, request encoding, response decoding, streaming, and support files without changing their public client APIs.
- Added typed Foundation Models native tool wrappers for text generation, guided generation, and prewarming behind `canImport(FoundationModels)`.
- Documented the release-candidate tag flow for private incubation deploys.

## 0.1.0-rc.1

- Initial private package scaffold.
- Added `SwiftLLM`, `SwiftLLMFoundationModels`, `SwiftLLMOpenAI`, `SwiftLLMAnthropic`, and `SwiftLLMEvaluation` products.
- Added XcodeGen showcase shell.
- Added durable docs, scratch policy, and agent routing docs.
- Completed the first Foundation Models adapter slice with availability normalization, token counting, prewarming, text generation, typed guided generation entrypoints, error normalization, fallback mapping, and SDK-independent fake-client tests.
- Completed the first structured generation toolkit slice with schema descriptors, structured contracts, evidence sources/spans, candidate wrappers, validation issues/results, generic validators, repair/fallback policies, and a provider-neutral pipeline.
- Completed the first context pipeline slice with boundary-aware text chunking, transcript segment chunking with timestamps, score-density context packing, map/reduce orchestration, and merge/dedupe policy helpers.
- Completed the first local RAG slice with source references, async retriever abstractions, deterministic keyword retrieval, source-diverse packing, citation rendering, and a provider-neutral local RAG pipeline.
- Completed the first evaluation and diagnostics slice with text assertions, structured output assertions, prompt-version reports, fallback matrices, run metrics, JSON output, and redacted local debug bundles.
- Completed the first provider-neutral client slice with `LLMClient`, `AnyLLMClient`, `LLMRouter`, shared request/response/tool/schema types, Foundation Models conformance, OpenAI Responses adapter, Anthropic Messages adapter, injectable HTTP transports, and provider adapter tests.
- Hardened the provider-neutral layer by preserving prompt-version metadata across adapters, rejecting unsupported Foundation Models features instead of silently ignoring them, routing provider streaming through injectable transports, keeping API keys out of public stored properties, and allowing required local retrieval sources for empty queries.
- Added first-class provider capabilities, retryable router fallback policy, before-output streaming fallback, native OpenAI/Anthropic tool-result history mapping, and shared provider test support.
- Fixed audit findings around persisted message decoding, exact short grounding evidence, required local retrieval priority, OpenAI failed response/stream errors, and Anthropic streamed tool-call events.
- Added Foundation Models context planning through `LLMContextPlan`, context surfaces, trust levels, session policy, tool execution policy, and context budget reporting.
- Added workflow orchestration through `LLMWorkflow`, `LLMStep`, workflow events, intermediate outputs, budget reports, and step helpers for deterministic transforms, retrieval, context planning, model generation, validation, and repair/fallback.
- Polished production-readiness docs, provider file organization, public API comments, issue templates, and agent doc links.
