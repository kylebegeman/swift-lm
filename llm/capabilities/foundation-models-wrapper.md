# Foundation Models Wrapper

## Use When

Use this card for availability, locale support, guided generation, tool calling, token counts, safety, guardrails, or performance work.

## Quick Facts

- Apple Foundation Models are available on iOS/iPadOS/macOS/Mac Catalyst/visionOS 26-era platforms; the 27 releases add Private Cloud Compute (and watchOS through it).
- The system model must be checked for availability before use; Private Cloud Compute availability is async and includes quota state.
- The context window is platform-reported (`contextSize`) and varies by target, release, and hardware, so token budgeting must read the runtime profile.
- Guided generation schemas consume context.
- Tool definitions and tool outputs consume context.
- Model behavior can change with OS updates.

## Current Package Shape

`SwiftLMFoundationModels` currently owns:

- `FoundationModelAvailability`
- `FoundationModelClient` (closures for availability, target availability, runtime profile, token counting, prewarm, respond, and stream)
- `FoundationModelDefaults`
- `FoundationModelGenerationOptions` and `FoundationModelToolCallingMode`
- `FoundationModelGenerationRequest`
- `FoundationModelGenerationResponse` and `FoundationModelStreamEvent`
- `FoundationModelExecutionTarget`
- `FoundationModelRuntimeProfile`
- `FoundationModelQuotaStatus`
- `FoundationModelToolConfiguration` when `FoundationModels` is importable
- `FoundationModelFailure`
- `FoundationModelErrorNormalizer`
- core `LMContextPlan` metadata for instructions, prompt payloads, guided generation schemas,
  transcript rehydration, prewarm prefixes, and tool definitions

It is the typed adapter layer for availability, runtime profiles, token counting, prewarming, text
generation, streaming, guided generation and native tool calls where `FoundationModels` is
importable, context-plan budgeting, error normalization for both the OS 26 and OS 27 error
generations, and Private Cloud Compute execution with quota and reasoning mapping. OS 27 symbols
sit behind `#if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY` in `FoundationModelLive.swift`.
Dynamic Profiles, session reuse, and the provider bridge are future work.

## Source Of Truth

- Durable package docs: `../../docs/02-foundation-models-reference.md`
- Current code: `Sources/SwiftLMFoundationModels/`

## Common Failure Modes

- Assuming the model is available.
- Assuming a 4,096-token context window instead of reading the runtime profile.
- Routing to Private Cloud Compute without checking availability and quota, or letting `automatic` escalate to it.
- Editing the gated OS 27 code without building it with Xcode 27.
- Reusing one session for long tasks until context overflows.
- Putting untrusted user text into instructions.
- Creating schemas or tools that are too verbose.
- Retrying the same failed prompt without narrowing the task.

## Read Next

- `reliability-patterns.md`
- `../../docs/04-context-and-chunking.md`
- `../../docs/05-structured-generation.md`
