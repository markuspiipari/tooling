///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public extension Swift.Optional {
    /// If this optional is non-nil, return the substituting value `t`, otherwise `nil`.
    func substituted<T: Any>(by t: T) -> T? {
        guard self != nil else {
            return nil
        }
        return t
    }

    /// Force-unwrap an optional value, raising a requirement failure if it is `nil`.
    func unwrapped(_ message: String? = nil, sourceFile: StaticString = #file, line: UInt = #line) -> Wrapped {
        guard let value = self else {
            requirementFailure(
                message ?? "Programming error: attempting to unwrap a nil optional value", sourceFile: sourceFile, line: line
            )
        }
        return value
    }
}
