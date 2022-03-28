///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license. See LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public struct ArrayMap<K: Hashable, V: Any> {
    private var map: Dictionary<K, [V]>

    public init(minimumCapacity: Int = 0) {
        self.map = Dictionary<K, [V]>(minimumCapacity: minimumCapacity)
    }

    public init(grouping values: [V], by keyTransform: (V) -> K) {
        self.map = Dictionary<K, [V]>(grouping: values) { keyTransform($0) }
    }

    public mutating func append(_ value: V, forKey key: K) {
        guard var array = map[key] else {
            return map[key] = [value]
        }
        array.append(value)
        map[key] = array
    }

    public var keys: Dictionary<K, [V]>.Keys {
        map.keys
    }

    public var values: Dictionary<K, [V]>.Values {
        map.values
    }

    public func values(forKey key: K) -> [V] {
        map[key] ?? []
    }

    public subscript (_ key: K) -> [V]? {
        map[key]
    }
}
