import Foundation

extension JSONEncoder {
  static func evaluationReportEncoder(prettyPrinted: Bool) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if prettyPrinted {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    } else {
      encoder.outputFormatting = [.sortedKeys]
    }
    return encoder
  }
}
