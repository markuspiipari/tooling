///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public extension Dictionary {
  /// Create a dictionary by mapping an array of values to keys provided by a value-to-key transform closure.
  /// Note: be careful to return unique keys from the transform, unless you actually intend to drop all but the last value that
  /// maps to the same key.
  init(mapping values: [Value], by keyTransform: (Value) -> Key) {
    self.init(minimumCapacity: values.count)
    for value in values {
      self[keyTransform(value)] = value
    }
  }

  /// Convert an array of (key, value) pair tuples into a dictionary. Again, be careful about the uniqueness of the keys,
  /// if maintaining all keys and values in the resulting dictionary is your goal!
  init(pairs: [(Key, Value)]) {
    self.init(minimumCapacity: pairs.count)
    for pair in pairs {
      self[pair.0] = pair.1
    }
  }

  /// Create a new dictionary mapping this dictionary's values to new, transformed keys.
  /// Note that this operation will be destructive for any key that the transform produces for multiple values; only the last
  /// value will survive in that scenario.
  func mapKeys<T: Hashable>(_ keyTransform: (Key) -> T) -> [T: Value] {
    var newDictionary = [T: Value](minimumCapacity: self.count)
    for key in keys {
      newDictionary[keyTransform(key)] = self[key]
    }
    return newDictionary
  }

  // MARK: - Unioning

  enum UnionStrategy {
    case this
    case other
  }

  func union(_ other: [Key: Value], preserving strategy: UnionStrategy = .other) -> [Key: Value] {
    // Adapted from https://stackoverflow.com/a/43615143
    switch strategy {
    case .this:
      return merging(other) { (this, _) in this }
    case .other:
      return merging(other) { (_, other) in other }
    }
  }
}
