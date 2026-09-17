import Foundation

public struct MergePolicy<Item: Sendable>: Sendable {
  public var key: @Sendable (Item) -> String
  public var merge: @Sendable (Item, Item) -> Item

  public init(
    key: @escaping @Sendable (Item) -> String,
    merge: @escaping @Sendable (Item, Item) -> Item
  ) {
    self.key = key
    self.merge = merge
  }

  public func merged(_ items: [Item]) -> [Item] {
    var orderedKeys: [String] = []
    var values: [String: Item] = [:]

    for item in items {
      let key = normalizedMergeKey(self.key(item))
      if let existing = values[key] {
        values[key] = merge(existing, item)
      } else {
        orderedKeys.append(key)
        values[key] = item
      }
    }

    return orderedKeys.compactMap { values[$0] }
  }
}

extension MergePolicy where Item == String {
  public static let normalizedText = Self(
    key: { $0 },
    merge: { existing, _ in existing }
  )
}
