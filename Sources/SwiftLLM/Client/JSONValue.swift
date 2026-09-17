import Foundation

/// A provider-neutral JSON value used for schemas, tool arguments, and other
/// request/response shapes that must stay dependency-free in the core target.
public indirect enum JSONValue: Equatable, Sendable {
  case array([JSONValue])
  case bool(Bool)
  case null
  case number(Double)
  case object([String: JSONValue])
  case string(String)
}

extension JSONValue: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .array(value):
      try container.encode(value)
    case let .bool(value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    case let .number(value):
      try container.encode(value)
    case let .object(value):
      try container.encode(value)
    case let .string(value):
      try container.encode(value)
    }
  }
}

extension JSONValue {
  public var arrayValue: [JSONValue]? {
    if case let .array(value) = self { return value }
    return nil
  }

  public var boolValue: Bool? {
    if case let .bool(value) = self { return value }
    return nil
  }

  public var isNull: Bool {
    if case .null = self { return true }
    return false
  }

  public var numberValue: Double? {
    if case let .number(value) = self { return value }
    return nil
  }

  public var intValue: Int? {
    guard let numberValue, numberValue.rounded() == numberValue, abs(numberValue) < Double(Int.max) else { return nil }
    return Int(numberValue)
  }

  public var objectValue: [String: JSONValue]? {
    if case let .object(value) = self { return value }
    return nil
  }

  public var stringValue: String? {
    if case let .string(value) = self { return value }
    return nil
  }

  public subscript(key: String) -> JSONValue? {
    objectValue?[key]
  }

  public subscript(index: Int) -> JSONValue? {
    guard let arrayValue, arrayValue.indices.contains(index) else { return nil }
    return arrayValue[index]
  }
}

extension JSONValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: JSONValue...) {
    self = .array(elements)
  }
}

extension JSONValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}

extension JSONValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .number(value)
  }
}

extension JSONValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .number(Double(value))
  }
}

extension JSONValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) {
    self = .null
  }
}

extension JSONValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .string(value)
  }
}
