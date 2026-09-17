import Foundation

// MARK: - JSON Coding

extension JSONDecoder {
  static var provider: JSONDecoder {
    JSONDecoder()
  }
}

extension JSONEncoder {
  static var provider: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}
