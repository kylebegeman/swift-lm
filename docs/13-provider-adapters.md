# Provider Adapters

## Purpose

SwiftLLM now has one client surface for multiple model backends:

- Apple Foundation Models through `SwiftLLMFoundationModels`
- OpenAI through `SwiftLLMOpenAI`
- Anthropic through `SwiftLLMAnthropic`
- deterministic local/test clients through `SwiftLLM`

The intent is not to pretend every provider has the same capabilities. The intent is to make common app workflows ergonomic while preserving provider-specific behavior at the adapter boundary.

## Core Types

Provider-neutral usage starts with `LLMClient`:

```swift
public protocol LLMClient: Sendable {
  var capabilities: LLMClientCapabilities { get }
  var metadata: LLMProviderMetadata { get }

  func respond(to request: LLMRequest) async throws -> LLMResponse
  func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error>
}
```

The core request model includes:

- `LLMMessage`
- `LLMGenerationParameters`
- `LLMResponseFormat`
- `LLMJSONSchema`
- `LLMToolDefinition`
- `LLMToolChoice`
- `LLMRequest`
- `LLMResponse`
- `LLMToolCall`
- `LLMClientError`
- `LLMClientCapabilities`

This keeps app code focused on the thing it is asking the model to do, not the transport shape for a particular provider.

Capability negotiation is intentionally explicit. Adapters publish support for tools, tool results, response formats, sampling options, stop sequences, native JSON schema support, streaming, and context windows where known. `LLMRouter` uses those capabilities before dispatch so a request that requires tools can skip a local adapter that cannot honor them.

## Provider Targets

### Foundation Models

`FoundationModelClient` conforms to `LLMClient`. Its provider-neutral capabilities come from the runtime profile of its `defaultExecutionTarget`: the platform-reported context window, and `reasoning` when the resolved model supports it. `FoundationModelClient.live.targeting(.privateCloudCompute)` is the same adapter pointed at Apple's server model, with `LLMPrivacyMode.privateCloudCompute` metadata.

The common `respond(to:)` API compiles an `LLMRequest` into the Foundation Models request type, passes `reasoningEffort` through as an Apple reasoning level, and returns finish reason, usage, and reasoning text. `stream(to:)` uses native Foundation Models streaming. Typed guided generation remains available through the Foundation-specific API when Apple's `FoundationModels` framework can be imported.

Native Foundation Models tool execution is available through the typed Foundation-specific API by passing `[any Tool]` to `FoundationModelClient.respond(to:tools:)`, `respond(generating:request:tools:)`, or `prewarm(_:tools:)`. The small `FoundationModelToolConfiguration` wrapper preserves tool names and approximate definition-token cost for diagnostics without moving Apple framework types into the core target.

The provider-neutral Foundation adapter rejects features it cannot honor generically, including tool calls, top-p sampling, stop sequences, and reasoning on targets that cannot reason. That keeps a request from silently producing different behavior locally than it would with a cloud provider.

This is still the preferred default for offline Apple app flows.

### OpenAI

`OpenAIClient` translates `LLMRequest` into the OpenAI Responses API:

- `instructions` and system/developer messages become Responses `instructions`
- user/assistant messages become Responses `input`
- `.jsonObject` and `.jsonSchema` become `text.format`
- tools become function tools
- tool choices are encoded as `auto`, `none`, `required`, or named function choice
- assistant tool calls and tool-result messages become native `function_call` and `function_call_output` input items; replayed calls omit the item `id`, and a tool result flagged as an error is prefixed with `Tool error:` because the API has no error flag
- `reasoningEffort` becomes `reasoning.effort`
- `store` is `false` unless `storesResponses` is set, and stateless reasoning requests ask for `reasoning.encrypted_content` so reasoning items can be replayed through `LLMMessage.providerContent`
- response parsing reads message content, refusal parts, function calls, reasoning summaries, `status`, `incomplete_details`, and token usage
- refusals throw `guardrailViolation`; incomplete responses report `length` or `contentFilter`
- failed payloads, HTTP errors, and stream `error` events classify by error code (`context_length_exceeded`, `insufficient_quota`, `rate_limit_exceeded`, `server_error`) and status
- response and streaming transports are injectable; the live transport uses a ten-minute timeout and normalizes `URLError` into `LLMClientError`

Stop sequences are not supported: the Responses API has no `stop` parameter, so `.stopSequences` is absent from the OpenAI capabilities and routers skip OpenAI for requests that need them.

Reasoning model families (`gpt-5`, `gpt-6`, and the `o` series) reject `temperature` and `top_p`. `OpenAIModelFamily.acceptsSamplingParameters(model:)` decides the default, `OpenAIClient(acceptsSamplingParameters:)` overrides it, and the client's capabilities drop `temperature` and `topP` when the model rejects them.

The adapter follows the public OpenAI Responses and Structured Outputs documentation:

- https://platform.openai.com/docs/api-reference/responses
- https://platform.openai.com/docs/guides/structured-outputs
- https://platform.openai.com/docs/guides/streaming-responses

### Anthropic

`AnthropicClient` translates `LLMRequest` into the Anthropic Messages API:

- `instructions` and system/developer messages become the Anthropic `system` field
- user/assistant messages become Anthropic `messages`; empty text blocks and empty assistant turns are omitted
- strict `.jsonSchema` formats become native `output_config.format`; non-strict schemas and `.jsonObject` are appended to system instructions
- tools become Anthropic tool definitions; `strict` is forwarded only when `forwardsStrictToolSchemas` is on
- tool choices map to `auto`, `none`, `any`, or a named tool
- assistant tool calls and tool-result messages become native `tool_use` and `tool_result` content blocks; thinking blocks captured on a previous response replay verbatim through `LLMMessage.providerContent`
- `reasoningEffort` becomes adaptive thinking with `output_config.effort`, and asks for summarized thinking on models that accept `thinking.display`
- `enablesPromptCaching` adds a top-level ephemeral `cache_control` marker
- response parsing reads text, thinking, and tool use blocks, stop reasons (including `refusal` and `model_context_window_exceeded`), and token usage; measured input tokens include cache reads and writes
- streaming parsing handles text deltas, thinking deltas, signature deltas, tool-use JSON deltas, stop reasons, token usage, and provider error events, and requires `message_stop`
- tool calls whose streamed arguments are not valid JSON are dropped rather than emitted
- HTTP and stream errors classify by error type (`overloaded_error`, `rate_limit_error`, `billing_error`, `request_too_large`, `prompt is too long`) and status
- response and streaming transports are injectable; the live transport uses a ten-minute timeout and normalizes `URLError` into `LLMClientError`

Model families change the request shape. `AnthropicModelFamily` decides the defaults and `AnthropicClient` accepts overrides:

- models released after Claude Opus 4.6 reject `temperature` and `top_p`, so those capabilities are dropped
- Claude 4.6 and later accept adaptive thinking with an effort level; older models need a thinking token budget the adapter does not manage, so `reasoning` is dropped
- Claude Fable 5.1 and later Fable releases, and Claude Mythos, reject forced tool choice, so `forcedToolChoice` is dropped
- identifiers the parser does not recognize are treated as current models: no sampling parameters and no reasoning controls

The adapter follows Anthropic's Messages API documentation:

- https://platform.claude.com/docs/en/api/messages
- https://platform.claude.com/docs/en/build-with-claude/streaming
- https://platform.claude.com/docs/en/build-with-claude/structured-outputs

## Routing And Fallback

`LLMRouter` lets an app express a fallback ladder:

```swift
let client = LLMRouter(
  primary: AnyLLMClient(FoundationModelClient.live),
  fallbacks: [
    .openAI(apiKey: openAIKey, model: "your-openai-model"),
    .anthropic(apiKey: anthropicKey, model: "your-anthropic-model"),
  ]
)
```

Routing is capability-aware. Before calling a provider, the router checks whether the request requires unsupported features such as tool calling, forced tool choice, tool results, reasoning, temperature or top-p sampling, stop sequences, JSON response formats, or streaming.

The default fallback policy retries only failures that are reasonable to recover from by trying another provider:

- unavailable providers, including network failures
- rate limits and timeouts
- exhausted quotas, such as a Private Cloud Compute daily limit or a prepaid balance
- exceeded context windows
- unsupported capabilities
- unsupported local model guides or locales
- unavailable local model assets
- concurrent local model requests

The default policy does not retry bad requests, authentication failures, guardrail/refusal failures, decoding bugs, validation failures, cancellations, or unknown provider errors. Apps can opt into `.always`, `.never`, or a custom `LLMRouterFallbackPolicy`.

Streaming uses `LLMStreamFallbackMode.beforeFirstOutput` by default. If a provider fails before yielding text, tool calls, or a completion event, the router can continue with a fallback provider. Once output starts, the stream fails rather than silently splicing two providers into one partial response.

Use `respondWithReceipt(to:)` when a call site needs a redacted diagnostic
receipt for provider attempts, unsupported capability skips, fallback reasons,
duration, and token usage:

```swift
let result = try await client.respondWithReceipt(to: request)
let response = result.response
let receipt = result.receipt
```

Existing `respond(to:)` and `stream(to:)` call sites can emit the same receipts through
`LLMRouter(runReceiptHandler:)`. Receipts intentionally store request shape and
provider metadata, not prompt text, context text, tool arguments, or response
text.

## Endpoint Registry

`LLMEndpointRegistry` lets apps register already-created clients under stable
IDs and then build routers from a routing plan:

```swift
let registry = LLMEndpointRegistry(
  endpoints: [
    LLMEndpoint(id: "local", client: AnyLLMClient(FoundationModelClient.live), priority: 10),
    LLMEndpoint(id: "openai", client: openAI, priority: 20),
    LLMEndpoint(id: "anthropic", client: anthropic, priority: 30),
  ]
)

let client = try registry.router()
```

Lower priority values run first. Disabled endpoints are ignored by priority
routing and rejected when requested explicitly. `LLMRoutingPlan` can pin a
primary endpoint, choose explicit fallback IDs, opt into automatic fallbacks, or
attach the same run-receipt handler that `LLMRouter` accepts.

`router(primaryID:)` keeps fallbacks explicit. A local-only primary never escalates
to a cloud endpoint unless the plan lists it or sets
`usesRemainingEnabledEndpointsAsFallbacks`.

Register the on-device and Private Cloud Compute targets as separate endpoints
when an app wants both:

```swift
let local = FoundationModelClient.live
let registry = LLMEndpointRegistry(
  endpoints: [
    LLMEndpoint(id: "on-device", client: AnyLLMClient(local), priority: 10),
    LLMEndpoint(id: "private-cloud", client: AnyLLMClient(local.targeting(.privateCloudCompute)), priority: 20),
  ]
)
```

The registry intentionally stores `AnyLLMClient` values, endpoint IDs, priority,
enabled state, and tags. It does not serialize API keys, provider secrets, or
transport configuration. Apps should keep credential storage in Keychain,
environment configuration, or their own settings layer.

## Prompt/RAG Pipeline

`LLMPipeline` combines:

- a provider-neutral client
- a prompt contract
- optional few-shot examples
- optional local retrieval
- optional tools and response formats

This is the high-level ergonomic API for app features that should feel the same whether they run locally or against a configured provider.

## Credential Policy

SwiftLLM accepts API keys at initialization time and does not persist them or define a credential storage policy.

Apps own:

- Keychain storage
- developer settings
- environment variable loading
- test fixture keys
- enterprise proxy policy
- user-facing disclosure and consent

That keeps SwiftLLM useful for private projects without baking in a public-library security stance too early.

## Testing Policy

Provider adapters use injectable HTTP transports. Tests should verify:

- request shape
- required headers
- response parsing
- streaming event parsing
- error normalization
- tool-call conversion
- native tool-result conversion
- capability-based routing behavior
- token usage conversion

Tests should not call real provider APIs by default.
