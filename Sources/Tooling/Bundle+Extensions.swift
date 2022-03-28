///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license. See LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public extension Bundle {
    var name: String {
        let name: String = requiredValueForInfoDictionaryKey(kCFBundleNameKey as String)
        return name
    }

    var version: String {
        let version: String = requiredValueForInfoDictionaryKey(kCFBundleVersionKey as String)
        return version
    }

    func valueForInfoDictionaryKey<T>(_ key: String) -> T? {
        infoDictionary?[key] as? T
    }

    func requiredValueForInfoDictionaryKey<T>(_ key: String) -> T {
        guard let value = infoDictionary?[key] as? T else {
            preconditionFailure(
                """
                No \(String(describing: T.self)) value for key '\(key)' available in info dictionary: \
                \(String(describing: infoDictionary))
                """
            )
        }
        return value
    }
}
