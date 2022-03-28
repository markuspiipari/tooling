///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

// MARK: -

public extension String {
    /**
     Treating this string as a file path, return the last component separated by "/".
     See documentation for the same property of `NSString` for more.
     */
    var lastPathComponent: String {
        if isEmpty {
            return self
        }
        if let s = split(separator: "/", omittingEmptySubsequences: true).last {
            return String(s)
        }
        return ""
    }

    var isAbsolutePathString: Bool {
        hasPrefix("/")
    }

    /// Note: for now, don't use this for any serious path manipulation code. Stick to `URL` intead!
    /// There are unit tests, but this is still intended for harmless UI display purposes only.
    var pathExtension: String {
        // Path extension is the last path component's last string component after the last "."
        let filename = lastPathComponent.trimmingWhitespace()
        let components = filename.split(separator: ".", omittingEmptySubsequences: false)

        // Special cases:
        // 1) There is no path extension
        guard components.count >= 2 else {
            return ""
        }

        // 2) Filenames of the form ".hidden" have no path extension
        if filename.hasPrefix("."), components.count <= 2 {
            return ""
        }

        // Normal operations:
        guard let t = components.last, t.isNonEmpty else {
            return ""
        }
        return String(t)
    }

    /// See note about `pathExtension` and `URL` above, or suffer the consequences.
    func deletingPathExtension() -> String {
        let path = self
        let components = path.split(separator: ".", omittingEmptySubsequences: true)
        guard components.count > 1 else {
            return self
        }
        return components.dropLast().joined(separator: ".")
    }

    /**

     Treating this string as an absolute path string (of a file, or the path component of a URL),
     return the relative tail portion of a path string, as evaluated against an absolute ancestor
     path string.

     If this path is equal to ancestor path, or the only difference is a trailing `/`, returns `""`.

     If this path string is in fact not relative to the given ancestor path string, returns `nil`.

     */
    // TODO: This implementation should be made case-insensitive
    func pathRelativeTo(_ ancestorPath: String) -> String? {
        let canonicalAncestorPath = ancestorPath.precomposedStringWithCanonicalMapping
        let canonicalSelf = precomposedStringWithCanonicalMapping
        let prefix: String

        if ancestorPath.hasSuffix("/") {
            prefix = canonicalAncestorPath
        } else {
            prefix = "\(canonicalAncestorPath)/"
        }

        if !canonicalSelf.hasPrefix(prefix) {
            if canonicalSelf == prefix || prefix == "\(canonicalSelf)/" {
                // We are comparing this path to itself (possibly suffixed by "/"). Return "".
                return ""
            }
            return nil
        }

        return canonicalSelf.trimmingPrefix(prefix).trimmingLeadingPathSeparator()
    }

    // Adapted from: https://stackoverflow.com/a/52016010
    func headPadded(toLength length: Int, truncate: Bool = false) -> String {
        guard length > count else {
            return truncate ? String(suffix(length)) : self
        }
        return String(repeating: " ", count: length - count) + self
    }

    func tailPadded(toLength length: Int, truncate: Bool = false) -> String {
        guard length > count else {
            return truncate ? String(prefix(length)) : self
        }
        return self + String(repeating: " ", count: length - count)
    }

    func splitStrings(separator: Character) -> [String] {
        split(separator: separator).map { String($0) }
    }

    func substituting(_ key: String, with value: String) -> String {
        replacingOccurrences(of: "${\(key)}", with: value)
    }

    func substituting(_ substitutions: [String: String]) -> String {
        var result: String = self
        for key in substitutions.keys {
            result = result.substituting(key, with: substitutions[key]!)
        }
        return result
    }

    func trimmingWhitespace() -> String {
        trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    /// If this string has a given prefix, return the rest of the string following the prefix.
    /// If prefix is empty, or this string does not have the prefix, return self.
    func trimmingPrefix(_ prefix: String) -> String {
        guard !prefix.isEmpty, hasPrefix(prefix) else {
            return self
        }
        return String(dropFirst(prefix.count))
    }

    /// If this string has a given suffix, return the portion of this string preceding the suffix.
    /// If suffix is empty, or this string does not have the suffix, return self.
    func trimmingSuffix(_ suffix: String) -> String {
        guard !suffix.isEmpty, hasSuffix(suffix) else {
            return self
        }
        return String(dropLast(suffix.count))
    }

    func trimmingLeadingPathSeparator() -> String {
        trimmingPrefix("/")
    }

    func trimmingTrailingPathSeparator() -> String {
        trimmingSuffix("/")
    }

    var base64StringFromBase64URLString: String {
        var base64 = replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        base64 += String(repeating: "=", count: base64.count % 4)
        return base64
    }

    var base64URLStringFromBase64String: String {
        var base64 = replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "_", with: "/")

        base64 += String(repeating: "=", count: base64.count % 4)
        return base64
    }
}

// MARK: - Localization support

public extension String {
    var localized: String {
        localized(comment: "")
    }

    func localized(comment: String) -> String {
        NSLocalizedString(self, comment: comment)
    }

    ///
    /// Given a number of items, pick the string corresponding to either zero, one or multiple items.
    ///
    /// @param n Number of items
    /// @param zero: String to return for no items.
    /// @param singular: String to return for exactly one item.
    /// @param plural: String to return for two or more items.
    ///
    static func pick(
        _ n: Int,
        zero: @autoclosure () -> String,
        singular: @autoclosure () -> String,
        plural: @autoclosure () -> String
    ) -> String {
        if n > 1 {
            return plural()
        }

        if n == 0 {
            return zero()
        }

        if n == 1 {
            return singular()
        }

        return ""
    }

    static func pick(_ n: Int, singular: @autoclosure () -> String, plural: @autoclosure () -> String) -> String {
        pick(n, zero: "", singular: singular(), plural: plural())
    }
}

// MARK: -

public extension Bool {
    var humanReadableValue: String {
        switch self {
        case true:
            return "yes"
        case false:
            return "no"
        }
    }
}
