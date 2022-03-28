///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

// MARK: - Timing measurements

public struct Measurement {
    /// By default, print out measured durations at tenths of a millisecond precision.
    public static var defaultPrecision: Int = 4
}

public struct MeasurementToken {
    let startedAt: TimeInterval
    let logLevel: LogLevel
    let description: String
}

/// **Note**: you will almost certainly want to use `measure()` instead of separately calling `startMeasuring()` and
/// `stopMeasuring()`.
public func startMeasuring(
    _ description: () -> String,
    logLevel: LogLevel = .dddebug,
    logStart: Bool = false,
    sourceFile: String = #file,
    function: String = #function,
    line: Int = #line
) -> MeasurementToken {
    let t = Date()

    let description = Log.shared.canLog(atLevel: logLevel) ? description() : ""

    if logStart {
        Log.shared.log(atLevel: logLevel, "⏱ Start: \(description)", sourceFile: sourceFile, line: line, function: function)
    }

    return MeasurementToken(
        startedAt: t.timeIntervalSinceReferenceDate,
        logLevel: logLevel,
        description: description
    )
}

/// **Note**: you will almost certainly want to use `measure()` instead of separately calling `startMeasuring()` and
/// `stopMeasuring()`.
@discardableResult public func stopMeasuring(
    _ token: MeasurementToken,
    outcome: String = "",
    minimumDuration: TimeInterval? = nil,
    precision: Int? = nil,
    numberOfItems: Int? = nil,
    itemName: String? = nil,
    sourceFile: String = #file,
    function: String = #function,
    line: Int = #line
) -> TimeInterval {
    let t = Date().timeIntervalSinceReferenceDate - token.startedAt
    let precision = precision ?? Measurement.defaultPrecision
    let format = ".\(precision)"
    let formattedDuration = String(format: "%\(format)f", t)

    if Log.shared.canLog(atLevel: token.logLevel), minimumDuration == nil || t >= minimumDuration! {
        let resultMessage = outcome.isEmpty ? "" : " (\(outcome))"
        let message: String = {
            let perItem: String = {
                if let n = numberOfItems {
                    let formattedPerItemDuration = String(format: "%\(format)f", t / TimeInterval(n))
                    return "\(formattedPerItemDuration)s/\(itemName ?? "item")"
                }
                return ""
            }()
            let s = "⏱ \(formattedDuration)s: \(token.description)\(resultMessage) (\(perItem))"
            return s
        }()
        Log.shared.log(atLevel: token.logLevel, force: true, message, sourceFile: sourceFile, line: line, function: function)
    }

    return t
}

#if MEASURE_TIMINGS

public func measure<T>(
    _ description: @autoclosure () -> String,
    logLevel: LogLevel = .dddebug,
    numberOfItems n: Int? = nil,
    itemName: String? = nil,
    sourceFile: String = #file,
    function: String = #function,
    line: Int = #line,
    work: () throws -> T
) rethrows -> T {
    let t = startMeasuring(description, logLevel: logLevel, sourceFile: sourceFile, function: function, line: line)
    defer {
        stopMeasuring(t, numberOfItems: n, itemName: itemName, sourceFile: sourceFile, function: function, line: line)
    }
    return try work()
}

#else

public func measure<T>(
    _ description: @autoclosure () -> String,
    logLevel: LogLevel = .dddebug,
    numberOfItems n: Int? = nil,
    itemName: String? = nil,
    sourceFile: String = #file,
    function: String = #function,
    line: Int = #line,
    work: () throws -> T
) rethrows -> T {
    return try work()
}

#endif
