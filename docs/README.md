# Docs Index

Start here for the durable, human-oriented explanation of SwiftLM.

## Recommended Read Order

1. `00-overview.md`
2. `01-architecture.md`
3. `02-foundation-models-reference.md`
4. `03-reliability-patterns.md`
5. `04-context-and-chunking.md`
6. `05-structured-generation.md`
7. `06-local-rag.md`
8. `07-evaluation-and-diagnostics.md`
9. `08-chime-in-incubation.md`
10. `09-roadmap.md`
11. `10-open-source-readiness.md`
12. `11-api-stability.md`
13. `12-release-process.md`
14. `13-provider-adapters.md`
15. `14-wwdc26-readiness.md`
16. `15-1.0.0-release-notes.md`
17. `16-2.0.0-release-notes.md`

If you are an agent or want the cheapest route to the right files, use [`../llm/START_HERE.md`](../llm/START_HERE.md).

## Durable vs. Scratch

Durable docs live here. They should be kept accurate and reviewed when APIs or architecture decisions change.

Temporary notes live in [`../scratch/`](../scratch/). Scratch files are expendable and should not be treated as source of truth.

## Guides

| File | Purpose |
|---|---|
| `00-overview.md` | package mission, scope, and non-goals |
| `01-architecture.md` | target layout, public product boundaries, and ownership rules |
| `02-foundation-models-reference.md` | platform constraints from Apple documentation and how they shape the package |
| `03-reliability-patterns.md` | production AI techniques adapted to small on-device models |
| `04-context-and-chunking.md` | token budgets, context packing, and long-input processing |
| `05-structured-generation.md` | guided generation, schemas, validation, grounding, and repair |
| `06-local-rag.md` | offline retrieval-augmented generation architecture |
| `07-evaluation-and-diagnostics.md` | golden corpora, prompt regression, safety tests, and local diagnostics |
| `08-chime-in-incubation.md` | how Chime In should consume and pressure-test the package |
| `09-roadmap.md` | phased implementation plan |
| `10-open-source-readiness.md` | publication criteria, licensing, API stability, and repo hygiene |
| `11-api-stability.md` | semantic versioning and public API stability policy |
| `12-release-process.md` | release branch and tagging process |
| `13-provider-adapters.md` | provider-neutral client API plus Foundation Models, OpenAI, and Anthropic adapter behavior |
| `14-wwdc26-readiness.md` | WWDC26 Foundation Models, Private Cloud Compute, Dynamic Profiles, provider packages, and Evaluations readiness |
| `15-1.0.0-release-notes.md` | 1.0.0 release notes, limitations, and validation summary |
| `16-2.0.0-release-notes.md` | 2.0.0 rename, OS 27 Foundation Models adoption, provider fixes, and validation summary |
