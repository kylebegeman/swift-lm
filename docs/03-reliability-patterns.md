# Reliability Patterns

## The Pattern

Production AI systems improve reliability by surrounding models with deterministic systems:

```text
user/app input
  -> classify the task
  -> retrieve only relevant context
  -> compile a prompt contract
  -> budget tokens
  -> call the model with schema/tools
  -> validate and ground output
  -> repair or retry when useful
  -> fall back deterministically when needed
  -> record metadata and evaluate over time
```

SwiftLM should adapt that pattern to Apple-native, offline workflows.

## Workflow Orchestration

`LMWorkflow` and `LMStep` provide a small sequential orchestration layer for this pattern.

The workflow layer is intentionally not an autonomous agent framework. It does not decide which tools
to call, store provider credentials, create background workers, or perform hidden model calls. Apps
compose typed steps and provide every model-generation or retrieval closure explicitly.

Useful step shapes are:

- deterministic analysis before generation
- local retrieval and context packing through `LocalRAGPipeline`
- context-plan construction through `LMContextPlan` and `CompiledPrompt`
- model generation that returns `GenerationCandidate` or `StructuredGenerationCandidate`
- validation and grounding through `StructuredGenerationValidator` and `GroundingValidator`
- repair or deterministic fallback through existing structured-generation policies

`LMWorkflowResult` preserves final output plus diagnostics needed for production review:

- captured intermediate outputs when requested
- provider metadata and token usage
- context budget reports
- fallback reason
- validation issues
- source references, retrieval results, and evidence spans

This is the package-level shape Chime In should adopt around its app-owned extraction draft.

## Narrow Tasks

The on-device model should receive one clear job at a time.

Good:

- "Extract action items from this transcript."
- "Summarize this chunk in two sentences."
- "Classify whether this note contains a follow-up."

Bad:

- "Analyze this entire meeting and make a complete project plan with timelines."
- "Act as a general personal assistant."
- "Figure out everything important."

Narrow tasks reduce latency, context usage, hallucination, and refusal risk.

## Prompt Contracts

A prompt contract should include:

- stable ID
- version
- trusted instructions
- response schema description
- expected behavior boundaries
- example selection rules
- evaluation corpus references

The contract is more important than an ad hoc prompt string. It gives teams something to version, test, and debug.

## Few-Shot Examples

Examples help define style and edge behavior, but they are expensive.

SwiftLM should support compact example selection:

- use only examples relevant to the current task
- prefer negative examples for common false positives
- cap example count
- keep example outputs short
- do not include examples if the schema and instructions are enough

Chime In already has this shape in its extraction example corpus. SwiftLM should generalize the selection mechanism, not the Chime-specific examples.

## Retrieval Before Generation

When the model needs app data, the app should retrieve relevant snippets before generation whenever possible.

This avoids asking the model to choose from too many tools and keeps the context window predictable.

Good local sources:

- SQLite FTS
- recent notes
- selected transcript segments
- user-approved documents
- app state summaries
- deterministic search results

Native Foundation Models tools remain useful for model-directed lookup, but SwiftLM keeps them on the typed `SwiftLMFoundationModels` API. Provider-neutral workflows should run local retrieval explicitly, add the result to the context plan, and use native tools only when the model genuinely needs to decide whether a lookup is relevant.

## Validation After Generation

Every model-backed output that affects product state should be validated.

Validation can check:

- required fields
- maximum counts
- enum values
- date parseability
- evidence spans
- source grounding
- duplicate items
- out-of-scope content
- unsafe output
- app-specific constraints

Validation should normalize the candidate into an app-owned draft. The model output is not the final product state.

The first structured generation toolkit now models this path explicitly:

```text
GenerationCandidate<Output>
  -> StructuredGenerationCandidate<Output>
  -> StructuredGenerationValidator<Output>
  -> StructuredGenerationRepairPolicy
  -> StructuredGenerationFallbackPolicy
  -> StructuredGenerationPipelineResult<Output>
```

Apps still own their final domain drafts. SwiftLM owns the generic candidate, evidence, validation, repair, and fallback machinery.

## Grounding

Grounding means generated claims should be supported by the source context.

SwiftLM should support simple deterministic grounding first:

- exact phrase containment
- content-word overlap
- source span preservation
- evidence fields in generated schemas
- per-item rejection

Later versions can add more advanced semantic grounding, but the first version should stay explainable.

## Repair and Retry

Retries are useful only when they are targeted.

Useful retry patterns:

- smaller schema
- fewer requested fields
- lower maximum output count
- shorter input chunk
- stricter prompt
- string refusal explanation after guided generation refusal

Bad retry patterns:

- repeat the same prompt three times
- raise temperature to "get something"
- discard validation failures silently

## Fallbacks

Fallbacks should be part of the design, not an error catch-all.

For provider routing, fallback should be selective. SwiftLM's router retries retryable conditions such as unavailable providers, rate limits, context limits, unsupported capabilities, unavailable local assets, unsupported local guides/locales, and concurrent local model requests. It intentionally avoids retrying bad requests, authentication failures, guardrail/refusal failures, validation failures, and unknown provider errors by default.

Common fallback reasons:

- model unavailable
- unsupported provider capability
- unsupported locale
- context exceeded
- guardrail violation
- refusal
- validation failure
- provider error

Fallback outputs may be:

- deterministic heuristic extraction
- partial structured draft
- empty result with clear metadata
- "needs review" state
- local search result with no model summary

## Human Verification

For workflows like Chime In, generated output should enter an editable verification surface before export.

This is especially important for:

- tasks
- calendar dates
- reminders
- decisions
- summaries that might be shared

SwiftLM should make it easy to preserve provenance and validation reasons so the app can show appropriate review UI.
