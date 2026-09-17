# Repo Map

## Use When

Use this card when deciding where a new API, test, doc, or showcase change belongs.

## Package Targets

| Target | Purpose |
|---|---|
| `SwiftLM` | Core app-neutral primitives for prompts, context, validation, fallback, and metadata |
| `SwiftLMFoundationModels` | Integration layer for Apple Foundation Models |
| `SwiftLMOpenAI` | OpenAI Responses API adapter |
| `SwiftLMAnthropic` | Anthropic Messages API adapter |
| `SwiftLMEvaluation` | Prompt and output evaluation helpers |
| `SwiftLMTests` | Unit tests for core behavior, provider adapters, and evaluation primitives |

## Ownership Rules

- Put app-neutral value types in `SwiftLM`.
- Put provider-neutral capabilities, routing policy, and fallback behavior in `SwiftLM`.
- Put anything importing `FoundationModels` in `SwiftLMFoundationModels`.
- Put OpenAI HTTP translation in `SwiftLMOpenAI`.
- Put Anthropic HTTP translation in `SwiftLMAnthropic`.
- Put test/eval harness utilities in `SwiftLMEvaluation`.
- Put demo UI only in `Examples/LMShowcase`.
- Put durable docs in `docs/`.
- Put compact agent docs in `llm/`.
- Put temporary notes in `scratch/`.

## Files Likely Involved

- `Package.swift`
- `Sources/SwiftLM/Core/`
- `Sources/SwiftLM/Prompting/`
- `Sources/SwiftLM/Context/`
- `Sources/SwiftLM/Retrieval/`
- `Sources/SwiftLM/Validation/`
- `Sources/SwiftLM/Generation/`
- `Sources/SwiftLM/StructuredGeneration/`
- `Sources/SwiftLMFoundationModels/`
- `Sources/SwiftLMOpenAI/`
- `Sources/SwiftLMAnthropic/`
- `Sources/SwiftLMEvaluation/`

## Common Failure Modes

- Moving Chime In-specific concepts into the package too early.
- Importing Foundation Models in `SwiftLM`.
- Hiding provider-specific behavior behind the core target instead of adapter targets.
- Adding API key storage policy to SwiftLM instead of leaving it to the app.
- Adding a dependency to the core target before a real need appears.
- Updating package behavior without updating docs or evals.

## Read Next

- `../../docs/01-architecture.md`
- `../../docs/13-provider-adapters.md`
- `foundation-models-wrapper.md`
- `reliability-patterns.md`
