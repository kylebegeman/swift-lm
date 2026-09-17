# Structured Generation

## Goal

Structured generation should convert messy text into predictable Swift values while preserving enough evidence for validation and review.

Apple's guided generation gives the package the typed response mechanism. SwiftLM should provide the reliability layer around it.

## Current Toolkit

The first app-neutral structured generation slice includes:

- `StructuredGenerationSchema`
- `StructuredGenerationField`
- `StructuredGenerationContract`
- `EvidenceSource`
- `EvidenceSpan`
- `StructuredGenerationSourceContext`
- `StructuredGenerationCandidate`
- `ValidationIssue`
- `StructuredGenerationValidationResult`
- `StructuredGenerationValidator`
- `StructuredGenerationRepairPolicy`
- `StructuredGenerationFallbackPolicy`
- `StructuredGenerationPipeline`

The package does not define Chime In's final review draft. Instead, it validates provider output before the app maps accepted or fallback output into its own domain.

## Schema Design

Schemas should be compact.

Prefer:

- short property names that are still semantic
- flat structures when possible
- capped arrays
- enums for bounded choices
- optional evidence fields
- clear but short guides

Avoid:

- deeply nested objects
- verbose property guides everywhere
- large arrays without maximum counts
- schemas that combine unrelated tasks
- asking for long generated prose and many structured items in one call

## Evidence Fields

For extraction tasks, each generated item should carry evidence:

- source text
- source ID
- source range
- timestamp range
- unresolved date text
- confidence or validation score when useful

The evidence field is often more important than the generated label. It lets the app reject unsupported items and helps users verify what happened.

The generic `EvidenceSpan` supports source IDs, evidence text, optional integer character ranges, and optional confidence. `StructuredGenerationSourceContext` holds the source documents used for grounding checks.

## Candidate To Draft

Do not persist raw generated output as final user data.

Preferred flow:

```text
generated candidate
  -> deterministic normalization
  -> validation
  -> grounded item filtering
  -> duplicate merge
  -> app-owned review draft
  -> user verification
  -> persistence/export
```

SwiftLM should own candidate metadata, validation primitives, and generic filtering. Apps should own final draft types.

`StructuredGenerationPipeline` now provides this shape for any `Sendable` output. A generator closure produces a `GenerationCandidate<Output>`, the pipeline wraps it with evidence, runs validators, and returns accepted, rejected, failed, or fallback status with metadata intact.

## Validation Examples

Generic validation rules:

- text is not empty
- output count does not exceed product limit
- source evidence is grounded
- generated item does not contain prompt instructions
- generated item does not contain example-only facts
- date text can be parsed or preserved as unresolved text
- classification result is in an allowed set

Chime In-specific validation:

- task titles are verb-led
- decisions require explicit decision language
- date references require real date/time language
- recording-test narration should not become a task or decision
- lecture notes should not force action items

Those Chime-specific checks should stay in Chime In unless generalized.

## Repair Strategy

When validation fails, the package can support repair, but repair should be constrained:

- regenerate only failed fields
- ask for fewer items
- remove optional sections
- reduce examples
- provide validation failures as trusted app text

If repair still fails, fall back or return a partial draft.

The first repair policy is declarative. It records what should happen next, such as fallback, retry with shorter context, retry with fewer examples, retry with a simpler schema, or retry with a lower response-token limit. It does not automatically loop yet; automatic repair should wait until Phase 3 context orchestration is more mature.

## Prompt Injection

Untrusted user or document text must not be placed in instructions. It belongs in the prompt as quoted or delimited input.

Instructions are trusted policy. User content is data.

SwiftLM prompt APIs should keep this distinction visible.
