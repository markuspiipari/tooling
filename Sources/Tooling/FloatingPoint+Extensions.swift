///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public extension FloatingPoint {
    func isCloseEnough(to otherValue: Self, by maximumDifference: Self) -> Bool {
        let delta = abs(self - otherValue)
        return delta <= maximumDifference
    }
}
