# Add Generation Primitive

## Use When

Use this playbook when adding a new prompt, context, validation, fallback, generation, or metadata primitive.

## Steps

1. Decide the target.
   - app-neutral: `SwiftLM`
   - Foundation Models-specific: `SwiftLMFoundationModels`
   - evaluation/testing helper: `SwiftLMEvaluation`
   - showcase-only UI: `Examples/LMShowcase`

2. Add the smallest public type that expresses the concept.

3. Preserve metadata and fallback visibility.

4. Add unit tests for deterministic behavior.

5. Update durable docs if the primitive changes architecture or usage guidance.

6. Update `llm/` only if future agents need a new routing hint.

## API Rules

- Avoid provider-specific names in core.
- Avoid Chime In-specific names in package APIs.
- Prefer values over global mutable state.
- Prefer explicit failure/fallback cases over silent nils.
- Keep raw prompts and raw outputs out of stored diagnostics by default.
- Prefer structured generation APIs over app-specific candidate wrappers when a primitive can apply across apps.
- Keep app final-draft models outside SwiftLM.

## Read Next

- `../capabilities/repo-map.md`
- `../../docs/01-architecture.md`
