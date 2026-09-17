# ``SwiftLMOpenAI``

OpenAI Responses API adapter for SwiftLM.

## Overview

`SwiftLMOpenAI` provides `OpenAIClient`, an `LMClient` implementation that translates SwiftLM requests into OpenAI Responses API calls.

The adapter supports:

- text generation
- JSON object and JSON schema response formats
- function tool definitions
- tool choice
- native function-call and function-call-output history
- token usage parsing
- function call parsing
- streaming text, tool-call, completion, and failure event parsing
- injectable response and streaming HTTP transport for tests and app-specific networking policy

Apps provide API keys at initialization time and own credential storage.

## Topics

### Client

- ``OpenAIClient``
- ``OpenAIHTTPTransport``
- ``OpenAIHTTPRequest``
- ``OpenAIHTTPResponse``
- ``OpenAIHTTPStreamResponse``
