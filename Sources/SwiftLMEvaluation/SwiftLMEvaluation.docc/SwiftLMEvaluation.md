# ``SwiftLMEvaluation``

Run local prompt regression checks and produce redacted evaluation reports for model-backed features.

## Overview

SwiftLMEvaluation provides deterministic evaluation helpers that can run in unit tests, local scripts, and future CI. It is designed for prompt changes, structured-output validation, fallback coverage, and local-only diagnostics.

Reports redact raw outputs by default. Apps must explicitly opt in before storing raw model output in evaluation artifacts.

Use this product to:

- check required and forbidden text signals
- write small structured output assertions
- compare prompt contract versions
- summarize fallback behavior across provider states
- emit local JSON debug bundles

## Topics

### Text Evaluation

- ``PromptEvaluationCase``
- ``PromptEvaluationResult``
- ``PromptEvaluator``
- ``TextEvaluationAssertion``

### Structured Output Evaluation

- ``StructuredEvaluationAssertion``
- ``StructuredOutputEvaluator``
- ``StructuredOutputEvaluationResult``
- ``EvaluationIssue``

### Reports

- ``PromptVersionEvaluationReport``
- ``PromptVersionEvaluationMatrix``
- ``ModelFallbackMatrix``
- ``ModelFallbackMatrixEntry``
- ``EvaluationRunMetrics``
- ``LocalDebugBundle``
- ``LocalDebugBundleContentPolicy``
