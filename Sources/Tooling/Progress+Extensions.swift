///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public extension Progress {
    /// Increment completed unit count either by a given amount, or defaulting to 1.
    func increment(by increment: Int = 1) {
        completedUnitCount += Int64(increment)
    }

    /// Mark determinate progress as completed via setting `completedUnitCount` to the value of `totalUnitCount`.
    func markCompleted() {
        completedUnitCount = totalUnitCount
    }

    ///
    /// Check whether the operation represented by a determinate `Progress` is completed, by testing if
    /// `completedUnitCount` is equal to, or greater than, `totalUnitCount`.
    ///
    /// For a `Progress` in the indeterminate state, will return `false`.
    ///
    var isCompleted: Bool {
        if isIndeterminate {
            return false
        }
        return completedUnitCount >= totalUnitCount
    }
}
