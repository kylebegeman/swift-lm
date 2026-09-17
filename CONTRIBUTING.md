# Contributing

Thanks for helping improve SwiftLM. This package is meant to stay small, app-neutral, local-first by default, and explicit about every provider boundary.

## Project Shape

SwiftLM is split into focused products:

- `SwiftLM`: core prompt, context, retrieval, validation, workflow, routing, and metadata primitives
- `SwiftLMFoundationModels`: the only target that imports Apple's Foundation Models framework
- `SwiftLMOpenAI`: OpenAI Responses API adapter
- `SwiftLMAnthropic`: Anthropic Messages API adapter
- `SwiftLMEvaluation`: prompt evaluation, report, and diagnostics utilities

Keep app-specific models, product workflows, UI, account state, and credential storage outside this package unless a durable design doc promotes a generic primitive into SwiftLM.

## Local Setup

Requirements:

- Swift 6.2 or newer
- Xcode 26 with the iOS, macOS, and visionOS 26 SDKs; Xcode 27 to compile the OS 27 paths
- XcodeGen for the optional showcase app

Useful commands:

```sh
swift build
swift test
swift build -Xswiftc -warnings-as-errors
./scripts/validate.sh
```

`./scripts/validate.sh` validates the Swift package, agent manifest, and showcase project when local tools are available.

## Development Rules

- Keep `SwiftLM` free of app-specific concepts.
- Keep `SwiftLMFoundationModels` as the only target that imports `FoundationModels`.
- Keep provider HTTP translation inside provider adapter targets.
- Do not add API key persistence, token refresh, sign-in flows, or credential policy to the package. Apps own that boundary.
- Do not add telemetry or background network behavior.
- Do not add a production dependency without clear need and a design note.
- Do not commit generated `.xcodeproj` files, local build artifacts, credentials, `.env` values, transcripts with private data, provider payloads, or debug bundles.
- Add evaluation coverage when changing prompt contracts, validators, context packing, chunking, retrieval, fallback, or provider routing behavior.
- Preserve useful diagnostic context in errors, but do not leak secrets or raw private content by default.

## Swift And Concurrency

- Prefer Swift 6 style and strict data-race safety.
- Prefer value types, `Sendable`, structured concurrency, and cancellation-aware async code.
- Do not blanket library APIs with `@MainActor`.
- Avoid `Task.detached`, global mutable state, locks, and unsafe concurrency escape hatches unless there is a measured need and tests around the boundary.
- Keep streaming APIs cancellation-aware.
- Run warnings-as-errors before publishing API changes.

## Foundation Models And OS 27 Work

SwiftLM keeps iOS, macOS, and visionOS 26 as the package minimum and adopts OS 27 APIs behind a gate:

- OS 27 symbols live inside `#if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY` blocks with `#available` checks for the 27 releases, because Xcode 27 ships Swift 6.4 with the OS 27 SDKs. Pass `-Xswiftc -DSWIFTLM_OS26_SDK_ONLY` to build with a Swift 6.4 toolchain that still uses an OS 26 SDK.
- Keep source compiling on the OS 26 SDKs and keep every OS 26 code path in place; apps built with Xcode 27 still run on OS 26 devices.
- Normalize both error generations. Apps built with Xcode 27 receive `LanguageModelError`, `SystemLanguageModel.Error`, and `LanguageModelSession.Error` on OS 27 devices and `LanguageModelSession.GenerationError` on OS 26 devices.
- Represent new concepts in provider-neutral SwiftLM types before importing new SDK symbols.
- Do not hard-code context windows when the platform can report `contextSize`.
- Treat Private Cloud Compute as networked model execution in policy and diagnostics, and never let `automatic` escalate to it.
- Add tests with fake clients before requiring live Apple Intelligence availability.
- Build with Xcode 27 before changing the gated code. Until it is installed, `scratch/os27-stub-check` compiles the gated path against a stub of Apple's documented API.

Remaining OS 27 concepts include Dynamic Profiles, `LanguageModel` provider packages, Core AI and MLX local language models, image attachments, system tools, watchOS 27, and the Evaluations framework.

## Documentation Rules

- Durable decisions belong in `docs/`.
- Agent routing belongs in `llm/`.
- Temporary notes belong in `scratch/`.
- Public-facing examples must use placeholder API keys and synthetic data.
- Keep privacy claims tied to implementation.
- When an idea graduates from `scratch/`, move the durable parts into `docs/` and remove or rewrite stale scratch notes.

## Pull Requests

Every PR should include:

- a short description of the developer or user problem
- the implementation approach
- tests or a clear reason tests do not apply
- documentation updates for architecture or API changes
- prompt or evaluation updates for generation behavior changes
- the verification command output or the exact local blocker

Before opening a PR, run the narrowest meaningful verification. For package-wide changes, run:

```sh
swift test
swift build -Xswiftc -warnings-as-errors
./scripts/validate.sh
```

## Issue Types

Good issues include:

- API boundary problems
- Foundation Models availability or error-normalization gaps
- provider adapter decoding or streaming bugs
- context packing and token budgeting failures
- structured generation validation gaps
- evaluation or diagnostics improvements
- documentation mismatches

For security or privacy issues, use [SECURITY.md](SECURITY.md) instead of a public issue.

## Release Discipline

SwiftLM follows semantic versioning from `1.0.0` onward. Source-breaking changes should be reserved for major versions unless a security or platform compatibility issue leaves no practical alternative.

Follow:

- [API Stability](docs/11-api-stability.md)
- [Release Process](docs/12-release-process.md)
- [Open Source Readiness](docs/10-open-source-readiness.md)
