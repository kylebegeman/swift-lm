# Chime In Incubation

## Use When

Use this card when a change is motivated by Chime In extraction, transcription, local review, or offline structured output.

## Boundary

SwiftLM can own:

- prompt contracts
- provider metadata
- token budgets
- chunking
- context packing
- guided generation wrappers
- validation primitives
- fallback result types
- evaluation harnesses

Chime In should keep:

- recording persistence
- transcript segment schema
- capture modes
- review drafts
- tasks, dates, decisions, tags
- exports
- TCA features
- CloudKit and SQLiteData policy

## Adoption Path

1. Use SwiftLM metadata and token primitives in Chime In.
2. Route Chime prompt examples through `PromptExample` and `ExampleSelector`.
3. Use `GroundingValidator` alongside Chime-specific validators.
4. Move generic evaluation harness pieces into `SwiftLMEvaluation`.
5. Keep app-specific extraction rules in Chime In until they prove reusable.

## Source Of Truth

- `../../docs/08-chime-in-incubation.md`
- Chime In docs remain source of truth for Chime In product behavior.

## Common Failure Modes

- Pulling Chime-specific models into public SwiftLM APIs.
- Changing Chime In behavior without an integration test or evaluation case.
- Treating Chime In's current extraction corpus as a generic public fixture.

## Read Next

- `../../docs/03-reliability-patterns.md`
- `../../docs/07-evaluation-and-diagnostics.md`
