# Evaluation And Diagnostics

## Why Evaluation Is Mandatory

Foundation Models behavior can change with OS updates. Prompt changes can also create regressions that are hard to see manually.

SwiftLM should make prompt evaluation cheap enough that every serious app can keep a small golden corpus.

## Evaluation Corpus

An evaluation case should include:

- ID
- input
- expected signals
- forbidden signals
- task type
- locale when relevant
- prompt contract version
- notes explaining the failure mode

For structured output, expected signals should support:

- required item counts
- required substrings
- forbidden substrings
- required enum cases
- date parse expectations
- grounding expectations
- safety/refusal expectations

The first `SwiftLMEvaluation` target now supports:

- required and forbidden substring checks
- deterministic text assertions through `TextEvaluationAssertion`
- structured output assertions through `StructuredEvaluationAssertion`
- typed issue records through `EvaluationIssue`
- prompt-version reports through `PromptVersionEvaluationReport`
- prompt-version matrices through `PromptVersionEvaluationMatrix`
- model availability/fallback summaries through `ModelFallbackMatrix`
- redacted provider run receipts through `LMRunReceipt`
- token/latency/retrieval metrics through `EvaluationRunMetrics`
- local JSON debug bundles through `LocalDebugBundle`

Reports are redacted by default. Raw model outputs are only included when an app explicitly asks for them.

## Structured Assertions

Structured assertions are closure-based and app-owned. SwiftLM provides common helpers:

- `nonEmptyString`
- `maximumCount`
- `requiredText`
- `predicate`

That lets Chime In keep domain-specific task/date/decision rules in its own app target while still using a shared evaluator and shared report format.

## Prompt Version Reports

Prompt changes should produce a report per prompt contract version:

```text
PromptContract v2
  -> evaluation cases
  -> PromptEvaluationResult values
  -> PromptVersionEvaluationReport
```

The report records pass/fail status, failures, metrics, prompt ID, prompt version, and whether raw outputs were stored.

Multiple reports can be grouped in `PromptVersionEvaluationMatrix` so prompt revisions can be compared before shipping.

## Chime In Evaluation Seeds

Chime In should seed cases for:

- task splitting
- negative task examples
- explicit decisions
- tentative thoughts that are not decisions
- dates with unresolved month-only references
- recording tests/filler
- reflection mode with no forced actions
- lecture mode with no forced tasks
- long transcript chunk merging

The package should provide the evaluation harness. Chime In should own the domain corpus.

## Safety Tests

Safety tests should cover:

- nonsensical input
- prompt injection attempts
- sensitive content relevant to the app domain
- out-of-scope requests
- malformed documents
- unsupported locale behavior
- refusal and guardrail handling

The package should help record whether a case:

- succeeded
- refused
- hit guardrails
- fell back
- exceeded context
- failed validation

## Local Diagnostics

Diagnostics should be local-only by default.

Useful metadata:

- provider kind
- provider display name
- model identifier
- OS/model version when available
- prompt version
- prompt contract ID
- token estimates
- measured token counts when available
- input chunk count
- retrieval snippet count
- generation duration
- fallback reason
- validation failures

`EvaluationRunMetrics` covers the first version of this metadata shape. It intentionally stores counts, durations, and identifiers rather than raw private content.

`LMRunReceipt` is the package-level receipt for one generation request. A
receipt records:

- prompt ID and prompt version from request metadata
- request shape, including message counts, tool counts, context item counts, and required capabilities
- provider attempts, including unsupported capability skips and retryable failures
- final provider metadata
- token usage when the provider reports it
- duration fields for the run and each attempt

Receipts are redacted by construction. They do not include user prompts, context
item text, model response text, tool arguments, API keys, or user identifiers.
Use `LMRouter.respondWithReceipt(to:)` when call sites need the receipt
alongside a response. Use `LMRouter(runReceiptHandler:)` when existing
`respond(to:)` call sites should emit receipts without changing their return
type. Failed `respondWithReceipt(to:)` calls throw `LMRunReceiptError`, which
contains both the underlying error and the redacted receipt.

`EvaluationRunMetrics` can be initialized from a receipt when evaluation reports
need the same token and duration fields. `LocalDebugBundle` can also include run
receipts, still under the default redacted content policy.

Do not store by default:

- raw user transcript
- raw prompt
- raw model response
- API keys
- user identifiers
- synced debug payloads

If an app needs raw prompt capture for debugging, it should be explicit, local-only, and easy to purge.

`LocalDebugBundle` is the first package-level debug bundle format. It is designed for local files, manual inspection, or developer-only export. It should not be uploaded automatically.

## Instruments

Apple provides a Foundation Models instrument for profiling asset loading, prompt processing, inference, tool calling, and token usage.

SwiftLM should complement Instruments with app-level metadata and OSLog signposts so developers can line up package runs with system traces.
