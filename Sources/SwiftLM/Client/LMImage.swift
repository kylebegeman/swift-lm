import Foundation
import UniformTypeIdentifiers

/// An image attached to a user message.
///
/// Adapters send images in each provider's native format. Providers that fetch images themselves
/// receive remote URLs as URLs; local file URLs are read and sent as data.
public struct LMImage: Codable, Equatable, Hashable, Sendable {
  public enum Source: Codable, Equatable, Hashable, Sendable {
    /// Encoded image bytes, such as PNG or JPEG, with their media type, such as `image/png`.
    case data(Data, mediaType: String)
    /// A remote `https` URL or a local file URL.
    case url(URL)
  }

  public var source: Source

  public init(source: Source) {
    self.source = source
  }

  public static func data(_ data: Data, mediaType: String) -> Self {
    Self(source: .data(data, mediaType: mediaType))
  }

  public static func url(_ url: URL) -> Self {
    Self(source: .url(url))
  }

  /// The URL for images a provider can fetch itself. `nil` for data and local files.
  public var remoteURL: URL? {
    guard case let .url(url) = source, !url.isFileURL else { return nil }
    return url
  }

  /// The encoded bytes and media type, reading local files when needed. Returns `nil` for remote
  /// URLs, which this package never downloads.
  public func loadData() throws -> (data: Data, mediaType: String)? {
    switch source {
    case let .data(data, mediaType):
      return (data, mediaType)
    case let .url(url):
      guard url.isFileURL else { return nil }
      guard let type = UTType(filenameExtension: url.pathExtension),
            type.conforms(to: .image),
            let mediaType = type.preferredMIMEType
      else {
        throw LMClientError(
          reason: .badRequest,
          debugDescription: "The file \(url.lastPathComponent) does not have an image file extension."
        )
      }
      do {
        return (try Data(contentsOf: url), mediaType)
      } catch {
        throw LMClientError(
          reason: .badRequest,
          debugDescription: "The image file \(url.lastPathComponent) could not be read: \(error.localizedDescription)"
        )
      }
    }
  }

  /// A `data:` URL for providers that accept inline images as URLs. Returns `nil` for remote URLs.
  public func dataURL() throws -> String? {
    guard let (data, mediaType) = try loadData() else { return nil }
    return "data:\(mediaType);base64,\(data.base64EncodedString())"
  }
}
