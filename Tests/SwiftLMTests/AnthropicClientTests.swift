import Foundation
import SwiftLM
import SwiftLMAnthropic
import Testing

@Suite("Anthropic client")
struct AnthropicClientTests {
  // MARK: - Requests and responses

  @Test
  func anthropicClientEncodesMessagesRequestAndParsesResponse() async throws {
    let capture = RequestCapture<AnthropicHTTPRequest>()
    let client = AnthropicClient(
      apiKey: "anthropic-test-key",
      model: "claude-test",
      baseURL: URL(string: "https://example.test/v1")!,
      defaultMaxTokens: 512,
      transport: AnthropicHTTPTransport { request in
        await capture.record(request)
        return AnthropicHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "msg_1",
              "type": "message",
              "role": "assistant",
              "model": "claude-test",
              "content": [
                {
                  "type": "text",
                  "text": "Hello from Claude."
                },
                {
                  "type": "tool_use",
                  "id": "toolu_1",
                  "name": "lookup_note",
                  "input": {
                    "id": "1"
                  }
                }
              ],
              "stop_reason": "tool_use",
              "usage": {
                "cache_creation_input_tokens": 2,
                "cache_read_input_tokens": 4,
                "input_tokens": 10,
                "output_tokens": 5
              }
            }
            """.utf8
          )
        )
      }
    )

    let response = try await client.respond(
      to: LMRequest(
        instructions: "Answer with citations.",
        messages: [
          .developer("Prefer compact output."),
          .user("Summarize this note."),
        ],
        tools: [
          LMToolDefinition(
            name: "lookup_note",
            description: "Look up a note.",
            inputSchema: [
              "type": "object",
              "properties": [
                "id": [
                  "type": "string",
                ],
              ],
            ]
          ),
        ],
        toolChoice: .required,
        parameters: LMGenerationParameters(maxOutputTokens: 80),
        metadata: [
          "promptVersion": "summary-v4",
        ]
      )
    )
    let request = try #require(await capture.value())
    let body = try request.jsonObject()

    #expect(request.url.absoluteString == "https://example.test/v1/messages")
    #expect(request.headers["x-api-key"] == "anthropic-test-key")
    #expect(request.headers["anthropic-version"] == "2023-06-01")
    #expect(body["model"] == "claude-test")
    #expect(body["max_tokens"] == 80)
    #expect(body["thinking"] == nil)
    #expect(body["output_config"] == nil)
    #expect(body["cache_control"] == nil)
    #expect(body["system"]?.stringValue?.contains("Answer with citations.") == true)
    #expect(body["system"]?.stringValue?.contains("Prefer compact output.") == true)
    #expect(body["messages"]?.arrayValue?.first?.objectValue?["role"] == "user")
    #expect(body["tools"]?.arrayValue?.first?.objectValue?["input_schema"]?.objectValue?["type"] == "object")
    #expect(body["tools"]?.arrayValue?.first?.objectValue?["strict"] == nil)
    #expect(body["tool_choice"]?.objectValue?["type"] == "any")
    #expect(response.text == "Hello from Claude.")
    #expect(response.finishReason == .toolCalls)
    #expect(response.toolCalls.first?.name == "lookup_note")
    #expect(response.message.toolCalls.first?.id == "toolu_1")
    #expect(response.message.providerContent == nil)
    #expect(response.tokenUsage?.measuredInputTokens == 16)
    #expect(response.tokenUsage?.measuredOutputTokens == 5)
    #expect(response.tokenUsage?.cachedInputTokens == 4)
    #expect(response.tokenUsage?.cacheWriteInputTokens == 2)
    #expect(response.tokenUsage?.reasoningTokens == nil)
    #expect(response.metadata.providerKind == .anthropic)
    #expect(response.metadata.promptVersion == "summary-v4")
  }

  @Test
  func anthropicClientAppliesModelFamilyRules() async throws {
    let opus = AnthropicClient(
      apiKey: "test-key",
      model: "claude-opus-5",
      transport: AnthropicHTTPTransport { _ in
        Issue.record("Unsupported parameters must be rejected before any request is sent.")
        return AnthropicHTTPResponse(statusCode: 500, body: Data())
      }
    )
    let fable = AnthropicClient(apiKey: "test-key", model: "claude-fable-5-1")
    let haiku = AnthropicClient(apiKey: "test-key", model: "claude-haiku-4-5")

    #expect(!opus.capabilities.supports(.temperature))
    #expect(!opus.capabilities.supports(.topP))
    #expect(opus.capabilities.supports(.reasoning))
    #expect(opus.capabilities.supports(.forcedToolChoice))
    #expect(!fable.capabilities.supports(.forcedToolChoice))
    #expect(haiku.capabilities.supports(.temperature))
    #expect(!haiku.capabilities.supports(.reasoning))

    #expect(AnthropicModelFamily.version(of: "claude-sonnet-4-5-20250929") == .init(family: "sonnet", major: 4, minor: 5))
    #expect(AnthropicModelFamily.version(of: "claude-opus-4-20250514") == .init(family: "opus", major: 4, minor: 0))
    #expect(AnthropicModelFamily.version(of: "claude-3-7-sonnet-20250219") == .init(family: "sonnet", major: 3, minor: 7))
    #expect(AnthropicModelFamily.version(of: "claude-test") == nil)
    #expect(AnthropicModelFamily.acceptsSamplingParameters(model: "claude-opus-4-6"))
    #expect(AnthropicModelFamily.acceptsSamplingParameters(model: "claude-3-5-haiku-latest"))
    #expect(!AnthropicModelFamily.acceptsSamplingParameters(model: "claude-opus-4-7"))
    #expect(!AnthropicModelFamily.acceptsSamplingParameters(model: "claude-haiku-5"))
    #expect(!AnthropicModelFamily.acceptsSamplingParameters(model: "custom-gateway-model"))
    #expect(AnthropicModelFamily.supportsReasoningControls(model: "claude-sonnet-4-6"))
    #expect(!AnthropicModelFamily.supportsReasoningControls(model: "claude-opus-4-5-20251101"))
    #expect(AnthropicModelFamily.acceptsThinkingDisplay(model: "claude-opus-4-7"))
    #expect(!AnthropicModelFamily.acceptsThinkingDisplay(model: "claude-opus-4-6"))
    #expect(AnthropicModelFamily.supportsForcedToolChoice(model: "claude-fable-5"))
    #expect(!AnthropicModelFamily.supportsForcedToolChoice(model: "claude-fable-5-2"))
    #expect(!AnthropicModelFamily.supportsForcedToolChoice(model: "claude-mythos-preview"))
    #expect(AnthropicModelFamily.supportsForcedToolChoice(model: "custom-gateway-model"))

    await #expect(throws: LMClientError.self) {
      _ = try await opus.respond(to: LMRequest(messages: [.user("Hi")], parameters: .deterministic))
    }
    await #expect(throws: LMClientError.self) {
      _ = try await haiku.respond(
        to: LMRequest(messages: [.user("Hi")], parameters: LMGenerationParameters(reasoningEffort: .low))
      )
    }
  }

  @Test
  func anthropicClientEncodesReasoningStructuredOutputAndCaching() async throws {
    let capture = RequestCapture<AnthropicHTTPRequest>()
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-opus-5",
      enablesPromptCaching: true,
      forwardsStrictToolSchemas: true,
      transport: AnthropicHTTPTransport { request in
        await capture.record(request)
        return AnthropicHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "msg_reasoning",
              "type": "message",
              "role": "assistant",
              "model": "claude-opus-5",
              "content": [
                {"type": "thinking", "thinking": "Weighing the options.", "signature": "sig_1"},
                {"type": "text", "text": "{\\"summary\\":\\"Done\\"}"}
              ],
              "stop_reason": "end_turn",
              "usage": {"input_tokens": 20, "output_tokens": 30}
            }
            """.utf8
          )
        )
      }
    )

    let response = try await client.respond(
      to: LMRequest(
        messages: [.user("Summarize.")],
        responseFormat: .jsonSchema(
          LMJSONSchema(
            name: "summary",
            schema: ["type": "object", "properties": ["summary": ["type": "string"]], "required": ["summary"], "additionalProperties": false]
          )
        ),
        tools: [LMToolDefinition(name: "lookup", description: "Look up.", inputSchema: ["type": "object", "additionalProperties": false])],
        parameters: LMGenerationParameters(reasoningEffort: .medium)
      )
    )
    let body = try #require(await capture.value()).jsonObject()

    #expect(body["thinking"]?.objectValue?["type"] == "adaptive")
    #expect(body["thinking"]?.objectValue?["display"] == "summarized")
    #expect(body["output_config"]?.objectValue?["effort"] == "medium")
    #expect(body["output_config"]?.objectValue?["format"]?.objectValue?["type"] == "json_schema")
    #expect(body["output_config"]?.objectValue?["format"]?.objectValue?["schema"]?.objectValue?["type"] == "object")
    #expect(body["system"] == nil)
    #expect(body["cache_control"]?.objectValue?["type"] == "ephemeral")
    #expect(body["tools"]?.arrayValue?.first?.objectValue?["strict"] == true)
    #expect(response.text == #"{"summary":"Done"}"#)
    #expect(response.reasoningText == "Weighing the options.")
    #expect(response.message.providerContent?.providerKind == .anthropic)
    #expect(response.message.providerContent?.payload.arrayValue?.first?["type"] == "thinking")
  }

  @Test
  func anthropicClientOmitsThinkingDisplayForModelsThatPredateIt() async throws {
    let capture = RequestCapture<AnthropicHTTPRequest>()
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-opus-4-6",
      transport: AnthropicHTTPTransport { request in
        await capture.record(request)
        return AnthropicHTTPResponse(
          statusCode: 200,
          body: Data(
            #"{"id": "msg_46", "type": "message", "role": "assistant", "model": "claude-opus-4-6", "content": [{"type": "text", "text": "Done."}], "stop_reason": "end_turn", "usage": {"input_tokens": 3, "output_tokens": 1}}"#.utf8
          )
        )
      }
    )

    _ = try await client.respond(
      to: LMRequest(
        messages: [.user("Think.")],
        parameters: LMGenerationParameters(temperature: 0.5, reasoningEffort: .low)
      )
    )
    let body = try #require(await capture.value()).jsonObject()

    #expect(body["thinking"]?.objectValue?["type"] == "adaptive")
    #expect(body["thinking"]?.objectValue?["display"] == nil)
    #expect(body["temperature"] == 0.5)
  }

  @Test
  func anthropicClientReplaysThinkingBlocksWithToolResults() async throws {
    let capture = RequestCapture<AnthropicHTTPRequest>()
    let thinkingBlock: JSONValue = ["type": "thinking", "thinking": "Need the note.", "signature": "sig_1"]
    let toolUseBlock: JSONValue = ["type": "tool_use", "id": "toolu_1", "name": "lookup_note", "input": ["id": "1"]]
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-opus-5",
      transport: AnthropicHTTPTransport { request in
        await capture.record(request)
        return AnthropicHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {"id": "msg_done", "type": "message", "role": "assistant", "model": "claude-opus-5", "content": [{"type": "text", "text": "Done."}], "stop_reason": "end_turn", "usage": {"input_tokens": 4, "output_tokens": 2}}
            """.utf8
          )
        )
      }
    )
    let assistantTurn = LMMessage.assistant(
      "",
      toolCalls: [LMToolCall(id: "toolu_1", name: "lookup_note", argumentsJSON: #"{"id":"1"}"#)],
      providerContent: LMProviderContent(providerKind: .anthropic, payload: [thinkingBlock, toolUseBlock])
    )

    _ = try await client.respond(
      to: LMRequest(
        messages: [
          .user("Look up note 1."),
          assistantTurn,
          .tool("Found it.", toolCallID: "toolu_1"),
        ]
      )
    )
    let replayRequest = try #require(await capture.value())
    let messages = try #require(try replayRequest.jsonObject()["messages"]?.arrayValue)
    let assistantContent = try #require(messages[1].objectValue?["content"]?.arrayValue)

    #expect(assistantContent == [thinkingBlock, toolUseBlock])
    #expect(messages[2].objectValue?["content"]?.arrayValue?.first?["tool_use_id"] == "toolu_1")
  }

  @Test
  func anthropicClientClassifiesErrorsAndRefusals() async throws {
    func reason(status: Int, body: String) async -> LMClientErrorReason? {
      let client = AnthropicClient(
        apiKey: "test-key",
        model: "claude-test",
        transport: AnthropicHTTPTransport { _ in
          AnthropicHTTPResponse(statusCode: status, body: Data(body.utf8))
        }
      )
      do {
        _ = try await client.respond(to: LMRequest(messages: [.user("Hi")]))
        return nil
      } catch let error as LMClientError {
        return error.reason
      } catch {
        return nil
      }
    }

    #expect(await reason(status: 400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"prompt is too long: 250000 tokens > 200000 maximum"}}"#) == .contextExceeded)
    #expect(await reason(status: 400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens must be positive"}}"#) == .badRequest)
    #expect(await reason(status: 413, body: #"{"type":"error","error":{"type":"request_too_large","message":"Too large"}}"#) == .contextExceeded)
    #expect(await reason(status: 402, body: #"{"type":"error","error":{"type":"billing_error","message":"Credits"}}"#) == .quotaExceeded)
    #expect(await reason(status: 529, body: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#) == .unavailable)
    #expect(await reason(status: 429, body: #"{"type":"error","error":{"type":"rate_limit_error","message":"Slow down"}}"#) == .rateLimited)
    #expect(await reason(status: 200, body: #"{"id":"msg_refusal","type":"message","role":"assistant","content":[],"stop_reason":"refusal","usage":{"input_tokens":1,"output_tokens":0}}"#) == .guardrailViolation)
  }

  // MARK: - Streaming

  @Test
  func anthropicClientStreamsThroughInjectedTransport() async throws {
    let capture = RequestCapture<AnthropicHTTPRequest>()
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-opus-5",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: AnthropicHTTPTransport(
        send: { _ in
          Issue.record("Streaming should not call the non-streaming transport.")
          return AnthropicHTTPResponse(statusCode: 500, body: Data())
        },
        stream: { request in
          await capture.record(request)
          // URLSession line streams omit blank separator lines, so none are included here.
          return AnthropicHTTPStreamResponse(
            statusCode: 200,
            lines: lineStream([
              "event: message_start",
              #"data: {"type":"message_start","message":{"id":"msg_stream","model":"claude-opus-5","usage":{"input_tokens":8,"output_tokens":1}}}"#,
              #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
              #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Plan."}}"#,
              #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig_1"}}"#,
              #"data: {"type":"content_block_stop","index":0}"#,
              #"data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
              #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello "}}"#,
              #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"stream"}}"#,
              #"data: {"type":"content_block_stop","index":1}"#,
              #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":6}}"#,
              #"data: {"type":"message_stop"}"#,
            ])
          )
        }
      )
    )

    var events: [LMStreamEvent] = []
    for try await event in client.stream(
      to: LMRequest(
        messages: [.user("Stream this.")],
        parameters: LMGenerationParameters(reasoningEffort: .low),
        metadata: ["promptVersion": "stream-v2"]
      )
    ) {
      events.append(event)
    }
    let request = try #require(await capture.value())
    let completed = try #require(events.completedResponse)

    #expect(request.url.absoluteString == "https://example.test/v1/messages")
    #expect(try request.jsonObject()["stream"] == true)
    #expect(events.reasoningDeltas == ["Plan."])
    #expect(events.textDeltas == ["Hello ", "stream"])
    #expect(completed.id == "msg_stream")
    #expect(completed.text == "Hello stream")
    #expect(completed.reasoningText == "Plan.")
    #expect(completed.finishReason == .stop)
    #expect(completed.metadata.promptVersion == "stream-v2")
    #expect(completed.tokenUsage?.measuredInputTokens == 8)
    #expect(completed.tokenUsage?.measuredOutputTokens == 6)
    #expect(completed.message.providerContent?.payload.arrayValue?.first == ["type": "thinking", "thinking": "Plan.", "signature": "sig_1"])
  }

  @Test
  func anthropicClientStreamsToolCallsThroughInjectedTransport() async throws {
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: AnthropicHTTPTransport(
        send: { _ in
          Issue.record("Streaming should not call the non-streaming transport.")
          return AnthropicHTTPResponse(statusCode: 500, body: Data())
        },
        stream: { _ in
          AnthropicHTTPStreamResponse(
            statusCode: 200,
            lines: lineStream([
              #"data: {"type":"message_start","message":{"usage":{"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"input_tokens":8,"output_tokens":1}}}"#,
              #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_stream","name":"lookup_note","input":{}}}"#,
              #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"id\":\""}}"#,
              #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"1\"}"}}"#,
              #"data: {"type":"content_block_stop","index":0}"#,
              #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":9}}"#,
              #"data: {"type":"message_stop"}"#,
            ])
          )
        }
      )
    )

    var events: [LMStreamEvent] = []
    for try await event in client.stream(
      to: LMRequest(
        messages: [.user("Lookup note 1.")],
        tools: [
          LMToolDefinition(
            name: "lookup_note",
            description: "Look up a note.",
            inputSchema: ["type": "object"]
          ),
        ]
      )
    ) {
      events.append(event)
    }

    #expect(events.toolCalls.map(\.id) == ["toolu_stream"])
    #expect(events.toolCalls.first?.name == "lookup_note")
    #expect(events.toolCalls.first?.argumentsJSON == #"{"id":"1"}"#)
    #expect(events.completedResponse?.finishReason == .toolCalls)
    #expect(events.completedResponse?.toolCalls.map(\.id) == ["toolu_stream"])
    #expect(events.completedResponse?.tokenUsage?.measuredInputTokens == 13)
    #expect(events.completedResponse?.tokenUsage?.measuredOutputTokens == 9)
    #expect(events.completedResponse?.tokenUsage?.cachedInputTokens == 3)
    #expect(events.completedResponse?.tokenUsage?.cacheWriteInputTokens == 2)
    #expect(events.completedResponse?.tokenUsage?.reasoningTokens == nil)
  }

  @Test
  func anthropicClientDropsTruncatedToolCalls() async throws {
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-test",
      transport: AnthropicHTTPTransport(
        send: { _ in AnthropicHTTPResponse(statusCode: 500, body: Data()) },
        stream: { _ in
          AnthropicHTTPStreamResponse(
            statusCode: 200,
            lines: lineStream([
              #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_cut","name":"lookup_note","input":{}}}"#,
              #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"id\":\"1"}}"#,
              #"data: {"type":"content_block_stop","index":0}"#,
              #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":9}}"#,
              #"data: {"type":"message_stop"}"#,
            ])
          )
        }
      )
    )

    var events: [LMStreamEvent] = []
    for try await event in client.stream(to: LMRequest(messages: [.user("Lookup.")])) {
      events.append(event)
    }

    #expect(events.toolCalls.isEmpty)
    #expect(events.completedResponse?.toolCalls.isEmpty == true)
    #expect(events.completedResponse?.finishReason == .length)
  }

  @Test
  func anthropicClientThrowsStreamErrorEvents() async throws {
    func reason(lines: [String]) async -> LMClientErrorReason? {
      let client = AnthropicClient(
        apiKey: "test-key",
        model: "claude-test",
        transport: AnthropicHTTPTransport(
          send: { _ in AnthropicHTTPResponse(statusCode: 500, body: Data()) },
          stream: { _ in AnthropicHTTPStreamResponse(statusCode: 200, lines: lineStream(lines)) }
        )
      )
      do {
        for try await _ in client.stream(to: LMRequest(messages: [.user("Stream.")])) {}
        return nil
      } catch let error as LMClientError {
        return error.reason
      } catch {
        return nil
      }
    }

    #expect(await reason(lines: [
      #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
    ]) == .unavailable)
    #expect(await reason(lines: [
      #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Lost"}}"#,
    ]) == .network)
  }

  @Test
  func anthropicClientReadsStreamingErrorBodies() async throws {
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-test",
      transport: AnthropicHTTPTransport(
        send: { _ in AnthropicHTTPResponse(statusCode: 500, body: Data()) },
        stream: { _ in
          AnthropicHTTPStreamResponse(
            statusCode: 400,
            lines: lineStream([#"{"type":"error","error":{"type":"invalid_request_error","message":"prompt is too long"}}"#])
          )
        }
      )
    )

    do {
      for try await _ in client.stream(to: LMRequest(messages: [.user("Stream.")])) {}
      Issue.record("Expected the streaming error body to throw.")
    } catch let error as LMClientError {
      #expect(error.reason == .contextExceeded)
      #expect(error.statusCode == 400)
    }
  }

  // MARK: - Tool history

  @Test
  func anthropicClientEncodesNativeToolHistory() async throws {
    let capture = RequestCapture<AnthropicHTTPRequest>()
    let client = AnthropicClient(
      apiKey: "test-key",
      model: "claude-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: AnthropicHTTPTransport { request in
        await capture.record(request)
        return AnthropicHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "msg_tool",
              "type": "message",
              "role": "assistant",
              "model": "claude-test",
              "content": [
                {
                  "type": "text",
                  "text": "Tool result accepted."
                }
              ],
              "stop_reason": "end_turn",
              "usage": {
                "input_tokens": 4,
                "output_tokens": 3
              }
            }
            """.utf8
          )
        )
      }
    )

    _ = try await client.respond(
      to: LMRequest(
        messages: [
          .user("Look up note 1."),
          .assistant(
            "",
            toolCalls: [
              LMToolCall(
                id: "toolu_1",
                name: "lookup_note",
                argumentsJSON: #"{"id":"1"}"#
              ),
            ]
          ),
          .tool("Not found", toolCallID: "toolu_1", isError: true),
          .tool("", toolCallID: "toolu_2"),
          .user("Continue with what you know."),
        ]
      )
    )

    let body = try #require(await capture.value()).jsonObject()
    let messages = try #require(body["messages"]?.arrayValue)
    let assistantContent = try #require(messages[1].objectValue?["content"]?.arrayValue)
    let toolResultContent = try #require(messages[2].objectValue?["content"]?.arrayValue)

    #expect(messages.count == 3)
    #expect(messages[1].objectValue?["role"] == "assistant")
    #expect(assistantContent.count == 1)
    #expect(assistantContent.first?.objectValue?["type"] == "tool_use")
    #expect(assistantContent.first?.objectValue?["id"] == "toolu_1")
    #expect(assistantContent.first?.objectValue?["input"]?.objectValue?["id"] == "1")
    #expect(messages[2].objectValue?["role"] == "user")
    #expect(toolResultContent[0].objectValue?["type"] == "tool_result")
    #expect(toolResultContent[0].objectValue?["tool_use_id"] == "toolu_1")
    #expect(toolResultContent[0].objectValue?["is_error"]?.boolValue == true)
    #expect(toolResultContent[1].objectValue?["tool_use_id"] == "toolu_2")
    #expect(toolResultContent[1].objectValue?["content"] == nil)
    #expect(toolResultContent[2].objectValue?["text"] == "Continue with what you know.")
  }
}
