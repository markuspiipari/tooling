///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public extension Array {
    func appending(_ element: Element) -> [Element] {
        var array = self
        array.append(element)
        return array
    }

    func appending(contentsOf other: [Element]) -> [Element] {
        var array = self
        array.append(contentsOf: other)
        return array
    }

    func inserting(_ element: Element, at index: Int) -> [Element] {
        var array = self
        array.insert(element, at: index)
        return array
    }

    ///
    /// Return a string with all elements of this array converted to `String` representations, then joined by a separator string.
    /// - Parameters:
    ///    separator: Separator string to join element string representations with. Defaults to `", "`.
    ///    transform: Optional transform closure for converting a single array element into a string. If `nil`, defaults to
    ///               calling `String(describing:)` for each array element.
    ///
    func debugString(separator: String = ", ", transform: ((Element) -> String)? = nil) -> String {
        if let t = transform {
            return self.map({ t($0) }).joined(separator: separator)
        } else {
            return self.map({ String(describing: $0) }).joined(separator: separator)
        }
    }
}

public extension Array where Element: Hashable {
    /// Return any elements that appear more than once in this array.
    /// Adapted from: https://stackoverflow.com/a/55341578
    func duplicates() -> [Element] {
        [Element](Dictionary(grouping: self, by: { $0 }).filter { $1.count > 1 }.keys)
    }

    /// Return this array with duplicate elements removed, while maintaining existing order.
    /// Adapted from: https://www.avanderlee.com/swift/unique-values-removing-duplicates-array/#removing-duplicate-elements-from-an-array-with-an-extension
    func removingDuplicates() -> [Element] {
        var seen: Set<Iterator.Element> = []
        return filter { seen.insert($0).inserted }
    }

    /// Return this array's contents as a `Set`.
    func set() -> Set<Element> {
        Set<Element>(self)
    }
}

public extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

public extension Array where Element: FloatingPoint {
    func isEqual(to array: [Element], tolerance: Element) -> Bool {
        guard self.count == array.count else {
            return false
        }

        return !enumerated().contains { i, val in
            abs(val - array[i]) > tolerance
        }
    }

    func difference(with array: [Element]) -> [Element] {
        enumerated().map {
            array[$0.offset] - $0.element
        }
    }

    func sumHistogram(byRatio ratio: Int) -> [Element] {
        chunked(into: ratio).map { $0.reduce(0, +) }
    }
}

public extension Array {
    /// Return this array wrapped in a type-erasing collection wrapper.
    func wrapped() -> AnyCollection<Element> {
        AnyCollection<Element>(self)
    }

    static func arrayOfNumberArrays(arrayOfFloatArrays arrays: [[Float]]) -> [[NSNumber]] {
        arrays.map { $0.map { NSNumber(value: $0) } }
    }
}

public extension AnyCollection {
    /// Return this collection's contents as an array.
    func unwrapped() -> [Element] {
        [Element](self)
    }
}

public extension AnyCollection where Element: Hashable {
    /// Return this collection's contents as a `Set`.
    func set() -> Set<Element> {
        Set<Element>(self)
    }
}

public extension Sequence {
    ///
    /// Transform this sequence of elements into an array of elements of another type, via a transform closure that returns one
    /// or more elements of that type in an array.
    ///
    /// The point of using this method is to avoid having to assign the result of a mapping step to a local constant like so:
    /// ```
    /// let arrays: [[T]] = sequence.map { // Transform $0 to array of n elements }
    /// let result = arrays.flatMap { $0 }
    /// ```
    func flattening<T>(_ transform: (Element) -> [T]) -> [T] {
        let arrays: [[T]] = self.map { transform($0) }
        return arrays.flatMap { $0 }
    }

    ///
    /// Transform this sequence into a dictionary with keys produced by a key transform closure.
    ///
    /// It is the caller's responsibility to ensure uniqueness of keys, to not unintentionally exclude any values contained by
    /// this array from the resulting dictionary due to a key clash.
    ///
    func mapped<K: Hashable>(by keyTransform: (Element) -> K) -> [K: Element] {
        var result: [K: Element]
        if let array = self as? [Element] {
            result = [K: Element](minimumCapacity: array.count)
        } else {
            result = [K:Element]()
        }
        forEach {
            result[keyTransform($0)] = $0
        }
        return result
    }

    /// Transform this sequence into a dictionary based on key/value pairs produced by a closure.
    func remapped<K: Hashable, V: Any>(by transform: (Element) -> (K, V)?) -> [K: V] {
        var result: [K: V]

        if let array = self as? [Element] {
            result = [K: V](minimumCapacity: array.count)
        } else {
            result = [K:V]()
        }

        forEach {
            if let t = transform($0) {
                result[t.0] = t.1
            }
        }

        return result
    }
}
