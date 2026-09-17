# Architecture

## Repository Structure

```text
swift-lm/
├── Package.swift
├── Sources/
│   ├── SwiftLM/                    # Core app-neutral primitives
│   ├── SwiftLMFoundationModels/    # Apple Foundation Models integration
│   ├── SwiftLMOpenAI/              # OpenAI Responses API integration
│   ├── SwiftLMAnthropic/           # Anthropic Messages API integration
│   └── SwiftLMEvaluation/          # Prompt and output evaluation
├── Tests/
│   └── SwiftLMTests/
├── Examples/
│   └── LMShowcase/                 # XcodeGen iOS showcase app
├── docs/                            # Durable human docs
├── llm/                             # Compact agent routing docs
└── scratch/                         # Expendable working notes
```

## Target Dependency Graph

```text
SwiftLMEvaluation
    └── SwiftLM

SwiftLMFoundationModels
    └── SwiftLM
    └── FoundationModels when available

SwiftLMOpenAI
    └── SwiftLM

SwiftLMAnthropic
    └── SwiftLM

SwiftLM
    └── Foundation
```

The core package does not import Foundation Models. That keeps the core abstractions testable, portable across Apple SDK configurations, and usable in deterministic fallback paths.

## `SwiftLM`

`SwiftLM` owns primitives that should be useful even if the model is unavailable:

- provider and run metadata
- provider-neutral request, response, streaming event, tool, and response-format types
- `LMClient`, `AnyLMClient`, provider capabilities, and `LMRouter`
- prompt contracts
- examples and example selection
- token budgeting
- token estimation
- text chunking
- retrieved snippet packing
- local retrieval query/result abstractions
- source references and citation rendering
- dependency-free keyword retrieval for tests and demos
- local RAG pipeline composition
- high-level prompt/RAG pipeline composition
- typed workflow orchestration over deterministic analysis, retrieval, context planning, generation,
  validation, and fallback
- structured generation schemas and contracts
- evidence sources and spans
- structured candidate wrappers
- validation issues and validators
- repair and fallback policies
- capability-aware provider routing
- provider-neutral structured generation pipelines
- fallback reasons
- generated candidate wrappers
- grounding validation

This target must stay app-neutral. It should not know about Chime In recordings, Reminders, Calendar, SQLiteData, TCA, or external provider keys.

## `SwiftLMFoundationModels`

`SwiftLMFoundationModels` is the only package target that should import Apple's `FoundationModels` framework.

It should grow into:

- availability and locale helpers
- model version metadata
- prewarming helpers
- guided generation wrappers
- tool-call wrappers
- error normalization
- context-window error handling
- refusal/guardrail handling
- token-count adapters

The first adapter slice now includes availability normalization, a token-count API with heuristic fallback when exact token counting is unavailable, prewarming, text generation, a typed guided generation entrypoint when `FoundationModels` can be imported, normalized error/fallback types, and fakeable closures for tests.

This target should continue to normalize Foundation Models behavior into core SwiftLM types instead of leaking every framework detail into app code.

## `SwiftLMOpenAI`

`SwiftLMOpenAI` adapts the OpenAI Responses API into the core `LMClient` protocol.

It includes:

- `OpenAIClient`
- request translation from `LMRequest`
- text, JSON object, JSON schema, tool definition, and tool choice encoding
- response parsing for `output_text`, message content, function calls, and token usage
- native tool-call and `function_call_output` history encoding
- SSE streaming for text deltas, provider completion events, and provider failure events
- injectable `OpenAIHTTPTransport` for tests and app-specific networking policy

This target does not persist API keys or define credential policy. Apps provide credentials at initialization time and own any Keychain, environment, or settings behavior.

## `SwiftLMAnthropic`

`SwiftLMAnthropic` adapts the Anthropic Messages API into the core `LMClient` protocol.

It includes:

- `AnthropicClient`
- system/developer instruction folding into Anthropic `system`
- user/assistant message translation
- tool definition and tool choice encoding
- native `tool_use` and `tool_result` history encoding
- response parsing for text blocks, tool use blocks, stop reasons, and token usage
- SSE streaming for text deltas, tool-use JSON deltas, stop reasons, token usage, and provider failure events
- injectable `AnthropicHTTPTransport` for tests and app-specific networking policy

This target is intentionally parallel to the OpenAI adapter so provider behavior stays visible instead of becoming a hidden abstraction layer.

## `SwiftLMEvaluation`

`SwiftLMEvaluation` owns test and QA primitives:

- golden corpus records
- required/forbidden substring assertions
- structured output assertions
- safety probes
- latency and token budget thresholds
- report models

The first evaluation slice includes text assertions, structured output assertion closures, prompt-version reports, fallback matrices, metrics, JSON output, and redacted local debug bundles. Over time this should become the package's strongest differentiator because model behavior changes across OS releases.

## Example App

`Examples/LMShowcase` is generated with XcodeGen. It should demonstrate package primitives in small, inspectable workflows:

- model availability
- provider metadata and routing options
- context budget visualization
- prompt contract previews
- chunking previews
- local retrieval, packing, and citation previews
- evaluation results
- Foundation Models request traces when available

Generated `.xcodeproj` files are ignored.

## Public API Rules

- Prefer small value types over global singletons.
- Keep closures explicit when behavior is app-provided.
- Preserve provider metadata through every generation result.
- Make fallback behavior visible.
- Prefer capability negotiation before trial-and-error provider dispatch.
- Avoid storing raw prompts or outputs by default.
- Keep validation deterministic where possible.
- Keep names app-neutral.
- Do not introduce dependencies until they remove real complexity.

## Boundary With Chime In

Chime In should own:

- recording IDs
- transcript segment persistence
- review drafts
- task/date/decision entities
- capture modes
- export workflows
- SQLiteData and CloudKit wiring

SwiftLM should own:

- prompt and model-run metadata
- chunking and context packing
- schema/generation orchestration
- app-composed workflow primitives
- grounding and validation primitives
- evaluation harnesses
- local diagnostics models

If a Chime In helper can be explained without saying "recording", "task", "date", "decision", or "capture mode", it may be a candidate for SwiftLM.
