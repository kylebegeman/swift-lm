# Security Policy

SwiftLM is a local-first Swift package. The core target has no network access, no telemetry, and no credential persistence. Security issues still matter because this package can sit near prompts, transcripts, local documents, provider adapters, and debug output.

## Supported Versions

| Version | Supported |
|---|---|
| `2.0.x` | Yes |
| `1.0.x` | Security fixes only until 2.1.0 |
| `master` / `next` | Best effort before the next release |
| Older pre-release tags | No |

## Reporting a Vulnerability

Please report vulnerabilities through GitHub Security Advisories:

https://github.com/kylebegeman/swift-lm/security/advisories/new

Do not open a public issue for a vulnerability until it has been triaged.

Useful reports include:

- affected package version or commit
- target product, such as `SwiftLM`, `SwiftLMFoundationModels`, `SwiftLMOpenAI`, or `SwiftLMAnthropic`
- platform and toolchain
- reproduction steps
- expected impact
- whether any prompt, transcript, provider key, user document, or debug bundle data may be exposed

## Security Scope

Please report:

- accidental network access from core targets
- leaked provider credentials, tokens, or authorization headers
- raw prompts, transcripts, outputs, or user documents included in diagnostics without an explicit opt-in
- provider adapter behavior that sends more context than requested
- request, response, or debug serialization that bypasses redaction policy
- unsafe handling of tool outputs, tool errors, or provider streamed events
- dependency or build-system changes that introduce supply-chain risk
- examples or tests that include real credentials, private data, or production user content

Generally out of scope:

- model hallucinations or low-quality output without a security or privacy impact
- expected provider rate limits or availability failures
- vulnerabilities in OpenAI, Anthropic, Apple, Xcode, SwiftPM, or platform SDKs
- app-specific credential storage outside this package

## Security Principles

- No telemetry by default.
- No network access in `SwiftLM`.
- Provider adapters must be explicit opt-in products.
- API keys are app-owned runtime inputs and should not be committed, logged, or persisted by SwiftLM.
- Raw prompts, transcripts, outputs, tool results, and provider payloads should not be stored by default.
- Debug bundles should be local and redacted unless the caller explicitly chooses a less restrictive content policy.
- Foundation Models behavior should remain isolated to `SwiftLMFoundationModels`.
- Private Cloud Compute and external cloud usage should be represented as networked execution in app policy, even when the provider offers strong privacy guarantees. The Foundation Models adapter never routes a request to Private Cloud Compute unless the app targets it explicitly.
- OpenAI responses are not stored server-side unless the app opts in with `storesResponses`.

## Disclosure Process

1. A maintainer acknowledges the report.
2. The issue is triaged for severity and affected versions.
3. A fix is prepared privately when needed.
4. A release is published with a changelog entry.
5. The advisory is published after users have a reasonable update path.

## Safe Examples

Examples, tests, docs, and issue reports should use placeholders for credentials:

```swift
let client = AnyLMClient.openAI(
  apiKey: "<runtime-api-key>",
  model: "example-model"
)
```

Never include `.env` values, private keys, production prompts, real transcripts, user documents, provider request bodies, or full debug bundles in public issues.
