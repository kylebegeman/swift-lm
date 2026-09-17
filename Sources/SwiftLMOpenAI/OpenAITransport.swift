import Foundation
import SwiftLM

// MARK: - Public Transport

/// HTTP request shape used by `OpenAIHTTPTransport`.
public struct OpenAIHTTPRequest: Sendable {
  public var body: Data
  public var headers: [String: String]
  public var method: String
  public var url: URL

  public init(
    url: URL,
    method: String = "POST",
    headers: [String: String] = [:],
    body: Data = Data()
  ) {
    self.body = body
    self.headers = headers
    self.method = method
    self.url = url
  }

  public func urlRequest() -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    for (field, value) in headers {
      request.setValue(value, forHTTPHeaderField: field)
    }
    return request
  }
}

/// HTTP response shape returned by `OpenAIHTTPTransport`.
public struct OpenAIHTTPResponse: Sendable {
  public var body: Data
  public var headers: [String: String]
  public var statusCode: Int

  public init(
    statusCode: Int,
    headers: [String: String] = [:],
    body: Data
  ) {
    self.body = body
    self.headers = headers
    self.statusCode = statusCode
  }
}

/// Streaming HTTP response that yields server-sent-event lines.
///
/// Lines are delivered one at a time. Blank separator lines may be omitted, so consumers must
/// dispatch each `data:` line as it arrives rather than waiting for a blank line.
public struct OpenAIHTTPStreamResponse: Sendable {
  public var headers: [String: String]
  public var lines: AsyncThrowingStream<String, any Error>
  public var statusCode: Int

  public init(
    statusCode: Int,
    headers: [String: String] = [:],
    lines: AsyncThrowingStream<String, any Error>
  ) {
    self.headers = headers
    self.lines = lines
    self.statusCode = statusCode
  }
}

/// Injectable OpenAI transport for production networking, tests, and app-specific policy.
public struct OpenAIHTTPTransport: Sendable {
  public var send: @Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPResponse
  public var stream: @Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPStreamResponse

  public init(
    send: @escaping @Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPResponse,
    stream: (@Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPStreamResponse)? = nil
  ) {
    self.send = send
    self.stream = stream ?? { _ in
      throw LMClientError(
        reason: .unsupported,
        debugDescription: "OpenAI streaming transport was not configured."
      )
    }
  }

  /// A `URLSession` transport with a ten-minute request timeout, matching the official SDK default.
  public static let live = live(session: .providerDefault)

  /// A `URLSession` transport using the given session. Network and timeout failures are normalized
  /// into `LMClientError` so routers can fall back.
  public static func live(session: URLSession) -> Self {
    Self(
      send: { request in
        try await liveSend(request, session: session)
      },
      stream: { request in
        try await liveStream(request, session: session)
      }
    )
  }

  private static func liveSend(
    _ request: OpenAIHTTPRequest,
    session: URLSession
  ) async throws -> OpenAIHTTPResponse {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request.urlRequest())
    } catch {
      throw ProviderTransportError.normalize(error, provider: "OpenAI")
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LMClientError(reason: .network, debugDescription: "OpenAI returned a non-HTTP response.")
    }
    return OpenAIHTTPResponse(
      statusCode: httpResponse.statusCode,
      headers: stringHeaders(from: httpResponse),
      body: data
    )
  }

  private static func liveStream(
    _ request: OpenAIHTTPRequest,
    session: URLSession
  ) async throws -> OpenAIHTTPStreamResponse {
    let bytes: URLSession.AsyncBytes
    let response: URLResponse
    do {
      (bytes, response) = try await session.bytes(for: request.urlRequest())
    } catch {
      throw ProviderTransportError.normalize(error, provider: "OpenAI")
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LMClientError(reason: .network, debugDescription: "OpenAI returned a non-HTTP response.")
    }
    let lines = AsyncThrowingStream<String, any Error> { continuation in
      let task = Task {
        do {
          for try await line in bytes.lines {
            continuation.yield(line)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: ProviderTransportError.normalize(error, provider: "OpenAI"))
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
    return OpenAIHTTPStreamResponse(
      statusCode: httpResponse.statusCode,
      headers: stringHeaders(from: httpResponse),
      lines: lines
    )
  }
}

private func stringHeaders(from response: HTTPURLResponse) -> [String: String] {
  response.allHeaderFields.reduce(into: [:]) { headers, field in
    if let key = field.key as? String,
       let value = field.value as? String
    {
      headers[key] = value
    }
  }
}

enum ProviderTransportError {
  /// Maps `URLError` values into `LMClientError` so the router's fallback policy can classify them.
  static func normalize(_ error: any Error, provider: String) -> any Error {
    if error is CancellationError || error is LMClientError {
      return error
    }
    guard let urlError = error as? URLError else {
      return LMClientError(
        reason: .network,
        debugDescription: "\(provider) request failed: \(error.localizedDescription)"
      )
    }
    switch urlError.code {
    case .cancelled:
      return LMClientError(reason: .cancelled, debugDescription: urlError.localizedDescription)
    case .timedOut:
      return LMClientError(reason: .timeout, debugDescription: urlError.localizedDescription)
    default:
      return LMClientError(reason: .network, debugDescription: urlError.localizedDescription)
    }
  }
}

extension URLSession {
  /// A session whose request and resource timeouts allow long generations. The default
  /// `URLSession.shared` request timeout of 60 seconds is too short for large reasoning responses.
  static let providerDefault: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 600
    configuration.timeoutIntervalForResource = 600
    return URLSession(configuration: configuration)
  }()
}
