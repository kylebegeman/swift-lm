import Foundation
import SwiftLM
import SwiftLMOpenAI
import Testing

@Suite("OpenAI client")
struct OpenAIClientTests {
  // MARK: - Requests and responses

  @Test
  func openAIClientEncodesResponsesRequestAndParsesResponse() async throws {
    let capture = RequestCapture<OpenAIHTTPRequest>()
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      baseURL: URL(string: "https://example.test/v1")!,
      organizationID: "org-test",
      projectID: "proj-test",
      transport: OpenAIHTTPTransport { request in
        await capture.record(request)
        return OpenAIHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "resp_1",
              "model": "gpt-test",
              "status": "completed",
              "output": [
                {
                  "type": "message",
                  "id": "msg_1",
                  "role": "assistant",
                  "content": [
                    {"type": "output_text", "text": "Hello from ", "annotations": []},
                    {"type": "output_text", "text": "OpenAI.", "annotations": []}
                  ]
                },
                {
                  "type": "function_call",
                  "id": "fc_1",
                  "call_id": "call_1",
                  "name": "lookup_note",
                  "arguments": "{\\"id\\":\\"1\\"}"
                }
              ],
              "usage": {
                "input_tokens": 12,
                "input_tokens_details": {
                  "cached_tokens": 6
                },
                "output_tokens": 4,
                "output_tokens_details": {
                  "reasoning_tokens": 2
                }
              }
            }
            """.utf8
          )
        )
      }
    )

    let response = try await client.respond(
      to: LMRequest(
        instructions: "Be concise.",
        messages: [
          .system("Keep private context private."),
          .user("Summarize this note."),
        ],
        responseFormat: .jsonSchema(
          LMJSONSchema(
            name: "summary",
            schema: [
              "type": "object",
              "properties": [
                "summary": [
                  "type": "string",
                ],
              ],
              "required": ["summary"],
              "additionalProperties": false,
            ]
          )
        ),
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
        toolChoice: .tool("lookup_note"),
        parameters: LMGenerationParameters(
          temperature: 0.2,
          maxOutputTokens: 120,
          topP: 0.9
        ),
        metadata: [
          "promptVersion": "summary-v3",
        ]
      )
    )
    let request = try #require(await capture.value())
    let body = try request.jsonObject()

    #expect(request.url.absoluteString == "https://example.test/v1/responses")
    #expect(request.headers["Authorization"] == "Bearer test-key")
    #expect(request.headers["OpenAI-Organization"] == "org-test")
    #expect(request.headers["OpenAI-Project"] == "proj-test")
    #expect(body["model"] == "gpt-test")
    #expect(body["max_output_tokens"] == 120)
    #expect(body["temperature"] == 0.2)
    #expect(body["store"] == false)
    #expect(body["stop"] == nil)
    #expect(body["reasoning"] == nil)
    #expect(body["instructions"]?.stringValue?.contains("Be concise.") == true)
    #expect(body["instructions"]?.stringValue?.contains("Keep private context private.") == true)
    #expect(body["input"]?.arrayValue?.first?.objectValue?["role"] == "user")
    #expect(body["text"]?.objectValue?["format"]?.objectValue?["type"] == "json_schema")
    #expect(body["tools"]?.arrayValue?.first?.objectValue?["name"] == "lookup_note")
    #expect(body["tool_choice"]?.objectValue?["name"] == "lookup_note")
    #expect(response.text == "Hello from OpenAI.")
    #expect(response.finishReason == .toolCalls)
    #expect(response.toolCalls.first?.name == "lookup_note")
    #expect(response.message.toolCalls.first?.id == "call_1")
    #expect(response.message.providerContent == nil)
    #expect(response.tokenUsage?.measuredInputTokens == 12)
    #expect(response.tokenUsage?.cachedInputTokens == 6)
    #expect(response.tokenUsage?.reasoningTokens == 2)
    #expect(response.metadata.providerKind == .openAI)
    #expect(response.metadata.promptVersion == "summary-v3")
  }

  @Test
  func openAIClientRejectsStopSequencesAndSamplingOnReasoningModels() async throws {
    let reasoningClient = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-5-mini",
      transport: OpenAIHTTPTransport { _ in
        Issue.record("Unsupported parameters must be rejected before any request is sent.")
        return OpenAIHTTPResponse(statusCode: 500, body: Data())
      }
    )

    #expect(!reasoningClient.capabilities.supports(.temperature))
    #expect(!reasoningClient.capabilities.supports(.topP))
    #expect(!reasoningClient.capabilities.supports(.stopSequences))
    #expect(reasoningClient.capabilities.supports(.reasoning))

    await #expect(throws: LMClientError.self) {
      _ = try await reasoningClient.respond(
        to: LMRequest(messages: [.user("Hi")], parameters: .deterministic)
      )
    }
    await #expect(throws: LMClientError.self) {
      _ = try await reasoningClient.respond(
        to: LMRequest(
          messages: [.user("Hi")],
          parameters: LMGenerationParameters(stopSequences: ["END"])
        )
      )
    }
  }

  @Test
  func openAIClientEncodesReasoningEffortAndReplaysReasoningItems() async throws {
    let capture = RequestCapture<OpenAIHTTPRequest>()
    let reasoningItem: JSONValue = [
      "type": "reasoning",
      "id": "rs_1",
      "encrypted_content": "opaque",
      "summary": [["type": "summary_text", "text": "Considered the note."]],
    ]
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-5-mini",
      transport: OpenAIHTTPTransport { request in
        await capture.record(request)
        return OpenAIHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "resp_reasoning",
              "status": "completed",
              "output": [
                {"type": "reasoning", "id": "rs_1", "encrypted_content": "opaque", "summary": [{"type": "summary_text", "text": "Considered the note."}]},
                {"type": "function_call", "id": "fc_1", "call_id": "call_1", "name": "lookup_note", "arguments": "{}"}
              ]
            }
            """.utf8
          )
        )
      }
    )

    let response = try await client.respond(
      to: LMRequest(
        messages: [.user("Look up the note.")],
        tools: [LMToolDefinition(name: "lookup_note", description: "Look up a note.", inputSchema: ["type": "object"])],
        parameters: LMGenerationParameters(reasoningEffort: .high)
      )
    )
    let firstBody = try #require(await capture.value()).jsonObject()

    #expect(firstBody["reasoning"]?.objectValue?["effort"] == "high")
    #expect(firstBody["include"]?.arrayValue?.first == "reasoning.encrypted_content")
    #expect(response.reasoningText == "Considered the note.")
    #expect(response.message.providerContent?.providerKind == .openAI)
    #expect(response.message.providerContent?.payload.arrayValue?.first == reasoningItem)

    _ = try await client.respond(
      to: LMRequest(
        messages: [
          .user("Look up the note."),
          response.message,
          .tool("Found it.", toolCallID: "call_1"),
        ]
      )
    )
    let replayRequest = try #require(await capture.value())
    let replayInput = try #require(try replayRequest.jsonObject()["input"]?.arrayValue)

    #expect(replayInput[1] == reasoningItem)
    #expect(replayInput[2].objectValue?["type"] == "function_call")
    #expect(replayInput[2].objectValue?["id"] == "fc_1")
    #expect(replayInput[3].objectValue?["type"] == "function_call_output")
  }

  @Test
  func openAIClientSurfacesRefusalsAndIncompleteResponses() async throws {
    let refusingClient = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      transport: OpenAIHTTPTransport { _ in
        OpenAIHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {"id": "resp_refusal", "status": "completed", "output": [{"type": "message", "role": "assistant", "content": [{"type": "refusal", "refusal": "I cannot help with that."}]}]}
            """.utf8
          )
        )
      }
    )
    do {
      _ = try await refusingClient.respond(to: LMRequest(messages: [.user("Do something unsafe.")]))
      Issue.record("Expected a refusal to throw.")
    } catch let error as LMClientError {
      #expect(error.reason == .guardrailViolation)
      #expect(error.debugDescription == "I cannot help with that.")
    }

    let truncatedClient = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      transport: OpenAIHTTPTransport { _ in
        OpenAIHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {"id": "resp_truncated", "status": "incomplete", "incomplete_details": {"reason": "max_output_tokens"}, "output": [{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "Partial"}]}]}
            """.utf8
          )
        )
      }
    )
    let truncated = try await truncatedClient.respond(to: LMRequest(messages: [.user("Long answer.")]))

    #expect(truncated.text == "Partial")
    #expect(truncated.finishReason == .length)
  }

  @Test
  func openAIClientClassifiesHTTPErrors() async throws {
    func client(status: Int, body: String) -> OpenAIClient {
      OpenAIClient(
        apiKey: "test-key",
        model: "gpt-test",
        transport: OpenAIHTTPTransport { _ in
          OpenAIHTTPResponse(statusCode: status, body: Data(body.utf8))
        }
      )
    }
    func reason(status: Int, body: String) async -> LMClientErrorReason? {
      do {
        _ = try await client(status: status, body: body).respond(to: LMRequest(messages: [.user("Hi")]))
        return nil
      } catch let error as LMClientError {
        return error.reason
      } catch {
        return nil
      }
    }

    #expect(await reason(status: 400, body: #"{"error":{"code":"context_length_exceeded","message":"Too long."}}"#) == .contextExceeded)
    #expect(await reason(status: 429, body: #"{"error":{"code":"insufficient_quota","message":"Quota."}}"#) == .quotaExceeded)
    #expect(await reason(status: 429, body: #"{"error":{"code":"rate_limit_exceeded","message":"Slow down."}}"#) == .rateLimited)
    #expect(await reason(status: 401, body: #"{"error":{"message":"Bad key."}}"#) == .authentication)
    #expect(await reason(status: 408, body: "") == .timeout)
    #expect(await reason(status: 503, body: "") == .unavailable)
  }

  // MARK: - Streaming

  @Test
  func openAIClientStreamsThroughInjectedTransport() async throws {
    let capture = RequestCapture<OpenAIHTTPRequest>()
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: OpenAIHTTPTransport(
        send: { _ in
          Issue.record("Streaming should not call the non-streaming transport.")
          return OpenAIHTTPResponse(statusCode: 500, body: Data())
        },
        stream: { request in
          await capture.record(request)
          // URLSession line streams omit blank separator lines, so none are included here.
          return OpenAIHTTPStreamResponse(
            statusCode: 200,
            lines: lineStream([
              "event: response.created",
              #"data: {"type":"response.created","response":{"id":"resp_stream","status":"in_progress"}}"#,
              #"data: {"type":"response.reasoning_summary_text.delta","delta":"Thinking."}"#,
              #"data: {"type":"response.output_text.delta","delta":"Hello "}"#,
              #"data: {"type":"response.output_text.delta","delta":"stream"}"#,
              #"data: {"type":"response.output_item.done","item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup_note","arguments":"{}"}}"#,
              #"data: {"type":"response.completed","response":{"id":"resp_stream","status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello stream"}]},{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup_note","arguments":"{}"}],"usage":{"input_tokens":3,"input_tokens_details":{"cached_tokens":1},"output_tokens":2,"output_tokens_details":{"reasoning_tokens":1}}}}"#,
              "data: [DONE]",
            ])
          )
        }
      )
    )

    var events: [LMStreamEvent] = []
    for try await event in client.stream(
      to: LMRequest(
        messages: [.user("Stream this.")],
        metadata: ["promptVersion": "stream-v1"]
      )
    ) {
      events.append(event)
    }
    let request = try #require(await capture.value())

    #expect(request.url.absoluteString == "https://example.test/v1/responses")
    #expect(try request.jsonObject()["stream"] == true)
    #expect(events.reasoningDeltas == ["Thinking."])
    #expect(events.textDeltas == ["Hello ", "stream"])
    #expect(events.toolCalls.map(\.id) == ["call_1"])
    #expect(events.completedResponse?.text == "Hello stream")
    #expect(events.completedResponse?.finishReason == .toolCalls)
    #expect(events.completedResponse?.metadata.promptVersion == "stream-v1")
    #expect(events.completedResponse?.tokenUsage?.measuredOutputTokens == 2)
    #expect(events.completedResponse?.tokenUsage?.cachedInputTokens == 1)
    #expect(events.completedResponse?.tokenUsage?.reasoningTokens == 1)
  }

  @Test
  func openAIClientStreamsIncompleteResponsesAsTruncated() async throws {
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      transport: OpenAIHTTPTransport(
        send: { _ in OpenAIHTTPResponse(statusCode: 500, body: Data()) },
        stream: { _ in
          OpenAIHTTPStreamResponse(
            statusCode: 200,
            lines: lineStream([
              #"data: {"type":"response.output_text.delta","delta":"Partial"}"#,
              #"data: {"type":"response.incomplete","response":{"id":"resp_incomplete","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Partial"}]}]}}"#,
            ])
          )
        }
      )
    )

    var events: [LMStreamEvent] = []
    for try await event in client.stream(to: LMRequest(messages: [.user("Stream.")])) {
      events.append(event)
    }

    #expect(events.textDeltas == ["Partial"])
    #expect(events.completedResponse?.finishReason == .length)
  }

  @Test
  func openAIClientThrowsFailedResponsePayloads() async throws {
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: OpenAIHTTPTransport { _ in
        OpenAIHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "resp_failed",
              "model": "gpt-test",
              "status": "failed",
              "error": {
                "code": "server_error",
                "message": "The model failed to generate a response."
              }
            }
            """.utf8
          )
        )
      }
    )

    do {
      _ = try await client.respond(to: LMRequest(messages: [.user("Fail.")]))
      Issue.record("Expected failed OpenAI response payload to throw.")
    } catch let error as LMClientError {
      #expect(error.reason == .unavailable)
      #expect(error.debugDescription == "The model failed to generate a response.")
    }
  }

  @Test
  func openAIClientThrowsStreamErrorEvents() async throws {
    func client(lines: [String]) -> OpenAIClient {
      OpenAIClient(
        apiKey: "test-key",
        model: "gpt-test",
        transport: OpenAIHTTPTransport(
          send: { _ in OpenAIHTTPResponse(statusCode: 500, body: Data()) },
          stream: { _ in OpenAIHTTPStreamResponse(statusCode: 200, lines: lineStream(lines)) }
        )
      )
    }
    func reason(lines: [String]) async -> LMClientErrorReason? {
      do {
        for try await _ in client(lines: lines).stream(to: LMRequest(messages: [.user("Stream.")])) {}
        return nil
      } catch let error as LMClientError {
        return error.reason
      } catch {
        return nil
      }
    }

    #expect(await reason(lines: [
      #"data: {"type":"response.failed","response":{"id":"resp_failed","status":"failed","error":{"code":"server_error","message":"Stream failed."}}}"#,
    ]) == .unavailable)
    #expect(await reason(lines: [
      #"data: {"type":"error","code":"rate_limit_exceeded","message":"Too fast.","sequence_number":3}"#,
    ]) == .rateLimited)
    #expect(await reason(lines: [
      #"data: {"type":"response.output_text.delta","delta":"Lost"}"#,
    ]) == .network)
  }

  @Test
  func openAIClientReadsStreamingErrorBodies() async throws {
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      transport: OpenAIHTTPTransport(
        send: { _ in OpenAIHTTPResponse(statusCode: 500, body: Data()) },
        stream: { _ in
          OpenAIHTTPStreamResponse(
            statusCode: 400,
            lines: lineStream([#"{"error":{"code":"context_length_exceeded","message":"Too long."}}"#])
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
  func openAIClientEncodesNativeToolHistory() async throws {
    let capture = RequestCapture<OpenAIHTTPRequest>()
    let client = OpenAIClient(
      apiKey: "test-key",
      model: "gpt-test",
      baseURL: URL(string: "https://example.test/v1")!,
      transport: OpenAIHTTPTransport { request in
        await capture.record(request)
        return OpenAIHTTPResponse(
          statusCode: 200,
          body: Data(
            """
            {
              "id": "resp_tool",
              "model": "gpt-test",
              "status": "completed",
              "output": [{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "Tool result accepted."}]}]
            }
            """.utf8
          )
        )
      }
    )

    let response = try await client.respond(
      to: LMRequest(
        messages: [
          .user("Look up note 1."),
          .assistant(
            "",
            toolCalls: [
              LMToolCall(
                id: "call_1",
                name: "lookup_note",
                argumentsJSON: #"{"id":"1"}"#
              ),
            ]
          ),
          .tool("Not found", toolCallID: "call_1", isError: true),
        ]
      )
    )

    let body = try #require(await capture.value()).jsonObject()
    let input = try #require(body["input"]?.arrayValue)

    #expect(response.text == "Tool result accepted.")
    #expect(response.finishReason == .stop)
    #expect(input[0].objectValue?["role"] == "user")
    #expect(input[1].objectValue?["type"] == "function_call")
    #expect(input[1].objectValue?["call_id"] == "call_1")
    #expect(input[1].objectValue?["id"] == nil)
    #expect(input[1].objectValue?["arguments"] == #"{"id":"1"}"#)
    #expect(input[2].objectValue?["type"] == "function_call_output")
    #expect(input[2].objectValue?["call_id"] == "call_1")
    #expect(input[2].objectValue?["output"] == "Tool error: Not found")
  }
}
