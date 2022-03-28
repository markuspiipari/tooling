///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public class SashimiError: Error {
    let message: String

    init(message: String) {
        self.message = message
    }
}
