# ``SwiftLMAnthropic``

Anthropic Messages API adapter for SwiftLM.

## Overview

`SwiftLMAnthropic` provides `AnthropicClient`, an `LMClient` implementation that translates SwiftLM requests into Anthropic Messages API calls.

The adapter supports:

- text generation
- system/developer instruction folding
- JSON response-format instructions
- tool definitions
- tool choice
- native tool-use and tool-result history
- token usage parsing
- tool use parsing
- streaming text, tool-use JSON delta, stop-reason, token-usage, and failure event parsing
- injectable response and streaming HTTP transport for tests and app-specific networking policy

Apps provide API keys at initialization time and own credential storage.

## Topics

### Client

- ``AnthropicClient``
- ``AnthropicHTTPTransport``
- ``AnthropicHTTPRequest``
- ``AnthropicHTTPResponse``
- ``AnthropicHTTPStreamResponse``
