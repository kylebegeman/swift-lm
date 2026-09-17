# Overview

## Purpose

SwiftLM is a Swift package for building reliable, local-first language model features on Apple platforms, with optional provider-backed generation when an app explicitly configures it.

The goal is not to turn Apple Foundation Models into frontier cloud models. The goal is to apply production AI system techniques around the on-device model so it becomes more useful, more predictable, and easier to ship inside real Apple apps.

Those techniques include:

- prompt contracts and prompt versioning
- compact few-shot examples
- token budgeting
- chunking and map/reduce processing
- source-aware local retrieval-augmented generation
- typed guided generation
- evidence-preserving structured output
- validation and post-processing
- capability-aware fallback ladders
- provider-neutral request/response routing
- prompt-version regression reports
- redacted local-only diagnostics

## Why This Exists

Apple Foundation Models provide an on-device language model that is strongest at language understanding, text generation, structured output, classification, tagging, summarization, and tool-assisted app-specific tasks.

The raw framework is intentionally low-level. It gives apps access to sessions, prompts, guided generation, tools, availability checks, guardrails, token counts, and performance instrumentation. It does not give every app a ready-made production reliability layer.

SwiftLM should become that reliability layer.

For private app work, the same reliability layer is also useful when switching between Foundation Models, OpenAI, and Anthropic. The package now treats provider access as an adapter concern: the core API speaks in messages, tools, schemas, responses, and fallback reasons; each provider target translates that shape into its native HTTP or framework API.

## Core Thesis

Small local models can become much more useful when the application gives them:

- a narrow task
- a compact schema
- only relevant context
- trusted instructions
- a few high-quality examples
- deterministic validation
- explicit fallback behavior
- repeatable evaluation

The package should optimize for that pattern.

## Initial Incubation App

Chime In is the first live testbed. Chime In needs private, offline transcription review and structured extraction from messy voice transcripts:

- summary
- tasks
- dates
- decisions
- questions
- follow-ups
- people
- topics
- tags

Those needs are app-specific, but the underlying primitives are generic. SwiftLM should own the generic machinery. Chime In should own the domain model and product workflow.

## Current Products

| Product | Responsibility |
|---|---|
| `SwiftLM` | app-neutral client, prompt, context, retrieval, fallback, validation, router, and metadata primitives |
| `SwiftLMFoundationModels` | Apple Foundation Models availability, token counting, generation, defaults, and adapter behavior |
| `SwiftLMOpenAI` | OpenAI Responses API adapter |
| `SwiftLMAnthropic` | Anthropic Messages API adapter |
| `SwiftLMEvaluation` | prompt regression, structured assertions, reports, and local debug bundle utilities |

## Non-Goals

SwiftLM should not:

- host a backend
- add telemetry by default
- store user prompts or outputs by default
- hide network calls inside local APIs
- become a generic multi-provider LangChain clone
- store API keys or decide credential policy for apps
- define Chime In's recording/review domain models
- promise frontier-model reasoning quality
- bypass Apple safety mechanisms

## Success Criteria

The package is succeeding when a developer can:

1. Define a typed model-backed task.
2. Budget context before calling the model.
3. Pack only useful local context.
4. Generate structured output.
5. Validate and ground the result.
6. Fall back when the model is unavailable or wrong.
7. Skip providers that cannot honor required request capabilities.
8. Run a local evaluation corpus after prompt or OS/model changes.
9. Inspect local diagnostics without shipping user data anywhere.

## Design Tone

SwiftLM should be boring in the best way: explicit types, predictable defaults, small abstractions, and no magic provider behavior.

When in doubt, prefer APIs that make the model's uncertainty visible instead of hiding it behind a too-smooth helper.
