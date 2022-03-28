///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public protocol Emptiness {
    var isEmpty: Bool { get }
}

public extension Emptiness {
    var isNonEmpty: Bool {
        !isEmpty
    }
}
