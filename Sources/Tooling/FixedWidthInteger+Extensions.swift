///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public enum ByteSizeScheme {
    case decimal
    case binary

    public func kiloValue<T: FixedWidthInteger>() -> T {
        thousand()
    }

    public func megaValue<T: FixedWidthInteger>() -> T {
        let t: T = thousand()
        return t * t
    }

    public func gigaValue<T: FixedWidthInteger>() -> T {
        let t: T = thousand()
        return t * t * t
    }

    public func teraValue<T: FixedWidthInteger>() -> T {
        let t: T = thousand()
        return t * t * t * t
    }

    public func localizedTeraUnitString() -> String {
        switch self {
        case .decimal:
            return NSLocalizedString("TB", comment: "Unit string for terabytes")
        case .binary:
            return NSLocalizedString("TiB", comment: "Unit string for terabytes")
        }
    }

    public func localizedGigaUnitString() -> String {
        switch self {
        case .decimal:
            return NSLocalizedString("GB", comment: "Unit string for gigabytes")
        case .binary:
            return NSLocalizedString("GiB", comment: "Unit string for gibibytes")
        }
    }

    public func localizedMegaUnitString() -> String {
        switch self {
        case .decimal:
            return NSLocalizedString("MB", comment: "Unit string for megabytes")
        case .binary:
            return NSLocalizedString("MiB", comment: "Unit string for mebibytes")
        }
    }

    public func localizedKiloUnitString() -> String {
        switch self {
        case .decimal:
            return NSLocalizedString("kB", comment: "Unit string for kilobytes")
        case .binary:
            return NSLocalizedString("kiB", comment: "Unit string for kibibytes")
        }
    }

    public func localizedByteUnitString() -> String {
        NSLocalizedString("bytes", comment: "Unit string for bytes")
    }

    private func thousand<T: FixedWidthInteger>() -> T {
        switch self {
        case .decimal:
            return 1000
        case .binary:
            return 1024
        }
    }
}

// MARK: -

public extension FixedWidthInteger {
    // MARK: 10-base byte quantities

    // See Definition at https://en.wikipedia.org/wiki/Gigabyte
    static var kilobyte: Self {
        ByteSizeScheme.decimal.kiloValue()
    }

    static var megabyte: Self {
        ByteSizeScheme.decimal.megaValue()
    }

    static var gigabyte: Self {
        ByteSizeScheme.decimal.gigaValue()
    }

    static var terabyte: Self {
        ByteSizeScheme.decimal.teraValue()
    }

    // MARK: 2-base byte quantities

    static var kibibyte: Self {
        ByteSizeScheme.binary.kiloValue()
    }

    static var mebibyte: Self {
        ByteSizeScheme.binary.megaValue()
    }

    static var gibibyte: Self {
        ByteSizeScheme.binary.gigaValue()
    }

    static var tebibyte: Self {
        ByteSizeScheme.binary.teraValue()
    }

    // MARK: Human-readable string representation

    func localizedByteSizeString(scheme: ByteSizeScheme = .decimal) -> String {
        let t: Self = scheme.teraValue()
        if self >= t {
            let sz = (Double(self) / Double(t)).localizedByteSizeString()
            return "\(sz)\(scheme.localizedTeraUnitString())"
        }

        let gig: Self = scheme.gigaValue()
        if self >= gig {
            let sz = (Double(self) / Double(gig)).localizedByteSizeString()
            return "\(sz)\(scheme.localizedGigaUnitString())"
        }

        let meg: Self = scheme.megaValue()
        if self >= meg {
            let sz = (Double(self) / Double(meg)).localizedByteSizeString()
            return "\(sz)\(scheme.localizedMegaUnitString())"
        }

        let k: Self = scheme.kiloValue()
        if self >= k {
            let sz = (Double(self) / Double(k)).localizedByteSizeString()
            return "\(sz)\(scheme.localizedKiloUnitString())"
        }

        let sz = Double(self).localizedByteSizeString()
        return "\(sz) \(scheme.localizedByteUnitString())"
    }
}

private extension Double {
    func localizedByteSizeString() -> String {
        String(format: "%.2f", self)
    }
}

public extension Comparable {
    func boundedTo(_ minimum: Self, _ maximum: Self) -> Self {
        if self < minimum {
            return minimum
        }
        if self > maximum {
            return maximum
        }
        return self
    }
}
