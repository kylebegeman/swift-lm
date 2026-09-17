# SwiftLM Start Here

## Use When

Read this before working in SwiftLM. It gives the shortest route to the relevant docs and package targets.

## Quick Facts

- Repo type: Swift package plus XcodeGen iOS showcase app.
- Package name: `swift-lm`.
- Public products:
  - `SwiftLM`
  - `SwiftLMFoundationModels`
  - `SwiftLMOpenAI`
  - `SwiftLMAnthropic`
  - `SwiftLMEvaluation`
- Primary language: Swift 6.2 or newer. Xcode 26 builds the package; Xcode 27 (Swift 6.4) compiles the gated OS 27 paths.
- Platforms: iOS 26, macOS 26, visionOS 26, and watchOS 26, with OS 27 Foundation Models features behind `#if compiler(>=6.4)`. The Foundation Models adapter is excluded on watchOS.
- Mission: reliability primitives for local-first Apple language model features, from the on-device model to Private Cloud Compute and explicit cloud providers.
- Naming: package `swift-lm`, products `SwiftLM*`, types `LM*`. The `llm/` folder is agent guidance, not the package name.
- First incubation app: Chime In.
- Durable docs: `docs/`.
- Expendable notes: `scratch/`.

## Recommended Read Order

1. `../docs/README.md`
2. `capabilities/repo-map.md`
3. `../docs/13-provider-adapters.md` for provider-neutral client work
4. `capabilities/foundation-models-wrapper.md`
5. `capabilities/reliability-patterns.md`
6. `capabilities/chime-in-incubation.md` when work is driven by Chime In
7. One focused playbook based on the task

## Recommended Playbooks

- Build, test, or regenerate the showcase:
  `playbooks/build-and-verify.md`
- Add a core package primitive:
  `playbooks/add-generation-primitive.md`
- Change prompts, validation, or quality behavior:
  `playbooks/evaluate-prompt-change.md`
- Update the showcase or docs:
  `playbooks/refresh-showcase-and-docs.md`

## Files Likely Involved

- `Package.swift`
- `Sources/SwiftLM/`
- `Sources/SwiftLMFoundationModels/`
- `Sources/SwiftLMOpenAI/`
- `Sources/SwiftLMAnthropic/`
- `Sources/SwiftLMEvaluation/`
- `Tests/SwiftLMTests/`
- `Examples/LMShowcase/project.yml`
- `docs/`
- `llm/`

## Source Of Truth

- Package structure and public targets: `Package.swift`.
- Long-term architecture and product direction: `docs/`.
- Agent routing: `llm/`.
- Scratch notes: `scratch/`, not source of truth.

## Escalate To Code When

- you know whether the change belongs in core, a provider adapter, evaluation, or the showcase
- you know whether a Chime In-driven idea is app-specific or package-general
- a doc or playbook points to a specific target or file
