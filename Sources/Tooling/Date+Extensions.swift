///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license. see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public extension Int {
    static let minute = 60
    static let hour = minute * 60
}

public enum TimeFormatters {
    public static let hours: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .brief
        return formatter
    }()

    public static let minutesOnly: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute]
        formatter.unitsStyle = .full
        return formatter
    }()

    public static let minutesAndSeconds: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .full
        return formatter
    }()

    public static let seconds: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.second]
        formatter.unitsStyle = .full
        return formatter
    }()
}

public extension TimeInterval {
    static let minute = TimeInterval(Int.minute)
    static let hour = TimeInterval(Int.hour)

    func humanReadableWaitingTimeString() -> String {
        let formatter: DateComponentsFormatter = {
            let seconds = Int(Double(self))

            let hours = seconds / Int.hour
            if hours >= 1 {
                return TimeFormatters.hours
            }

            let minutes = seconds / Int.minute
            if minutes >= 3 {
                return TimeFormatters.minutesOnly
            }
            if minutes >= 1 {
                return TimeFormatters.minutesAndSeconds
            }

            return TimeFormatters.seconds
        }()

        return formatter.string(from: self)!
    }
}
