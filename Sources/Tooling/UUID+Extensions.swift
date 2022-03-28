///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public extension UUID {
    var shortString: String {
        uuidString.split(separator: "-").first?.lowercased() ?? ""
    }
}
