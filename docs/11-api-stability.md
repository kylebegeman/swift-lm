# API Stability

## Current Stability Level

SwiftLM follows semantic versioning from `1.0.0` onward. Public APIs are expected to remain source-compatible across patch and minor releases unless a security or platform compatibility issue leaves no practical alternative.

`2.0.0` is the first major release. It renames the package and every `LLM*` type to `LM*`, adopts the OS 27 Foundation Models framework, and changes the behaviors listed in `CHANGELOG.md`. The migration is mechanical; see `docs/16-2.0.0-release-notes.md`.

The package is still young. New functionality should prefer additive APIs, small value types, and explicit provider boundaries so later releases can grow without forcing adopters through broad migrations.

## Versioning Policy

- follow semantic versioning
- reserve source-breaking changes for major versions
- keep deprecations around for at least one minor release when practical
- document migration steps for removed or renamed APIs

## Public API Categories

### Stable Candidates

These APIs are treated as stable public surface in `1.0.0`:

- provider metadata
- prompt contracts
- token budget and token counter
- simple chunking
- grounding validation
- fallback reasons
- evaluation result records
- provider-neutral request, response, message, tool, schema, and stream-event value types

They are small value types and already have tests.

### Incubating APIs

These are useful but should remain easy to revise:

- Foundation Models generation wrappers
- Foundation Models native tool wrappers
- Foundation Models runtime readiness models for PCC, quota, reasoning, and dynamic context hints
- OpenAI and Anthropic adapters
- endpoint registry and routing plans
- provider capabilities and router fallback policy
- router and high-level LLM pipeline
- redacted run receipts
- context compiler
- structured generation pipeline
- workflow orchestration primitives (`LMWorkflow`, `LMStep`, `LMWorkflowResult`, and workflow diagnostics)
- transcript chunking
- local RAG pipeline
- context packing strategies
- structured output assertions
- debug bundle format

They are public and tested, but their convenience layers may grow through additive APIs as real apps exercise them.

### Experimental Future APIs

These should not be promised publicly until implemented and tested:

- provider retry/backoff policy hooks
- SQLite/GRDB retrieval adapters
- embedding-backed retrieval
- automatic repair loops
- custom Foundation Models adapter management

## Naming Rules

- Prefer behavior names over implementation trend names.
- Keep app-specific language out of public API names.
- Keep provider-specific names inside provider-specific targets.
- Do not use "magic", "agent", or "chain" terminology unless the API genuinely models that concept.
- Prefer "workflow" and "step" for deterministic app-composed orchestration. Reserve "agent" for a
  future API only if the package actually owns autonomous planning, tool choice, and execution loops.

## Deprecation Rules

When replacing a public API:

1. Add the new API.
2. Add tests for the new behavior.
3. Mark the old API deprecated when the migration is clear.
4. Document migration notes in `CHANGELOG.md`.
5. Remove the old API only at an allowed breaking-change boundary.

Direct replacement without deprecation should be reserved for major versions or unreleased branch-only APIs.

## Compatibility Checks

Before tagging a public release:

- run `./scripts/validate.sh`
- build DocC documentation
- scan `Sources/` for public symbols added without docs or tests
- scan docs for private Chime In details
- verify generated Xcode projects and build artifacts are not staged
