///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

// MARK: -

public enum LogLevel: Int, CaseIterable, RawRepresentable {
    case dddebug
    case debug
    case verbose
    case info
    case warning
    case error
    case fatal
    case muted // Nothing is printed out when log level is set to muted.

    public init?(name: String) {
        switch name {
        case "dddebug":
            self = .dddebug
        case "debug":
            self = .debug
        case "verbose":
            self = .verbose
        case "info":
            self = .info
        case "warning":
            self = .warning
        case "error":
            self = .error
        case "fatal":
            self = .fatal
        case "muted":
            self = .muted
        default:
            return nil
        }
    }

    public var name: String {
        switch self {
        case .dddebug:
            return "dddebug"
        case .debug:
            return "debug"
        case .verbose:
            return "verbose"
        case .info:
            return "info"
        case .warning:
            return "warning"
        case .error:
            return "error"
        case .fatal:
            return "fatal"
        case .muted:
            return "muted"
        }
    }

    public var title: String {
        switch self {
        case .dddebug:
            return "Dddebug"
        case .debug:
            return "Debug"
        case .verbose:
            return "Verbose"
        case .info:
            return "Info"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        case .fatal:
            return "Fatal"
        case .muted:
            return ""
        }
    }

    static let paddedTitleLength = 7

    public var paddedTitle: String {
        return title.padding(toLength: LogLevel.paddedTitleLength, withPad: " ", startingAt: 0)
    }
}

// MARK: - Protocols
public protocol LogMessageFormatter {
    /// Format a log message for output into a log stream. The returned string must end with a line feed: `"\n"`.
    func formatOutput(
        timestamp: Date?,
        logTitle: String,
        level: LogLevel,
        messageBody: String,
        error: Error?,
        sourceFile: String,
        line: Int,
        function: String
    ) -> String
}

public protocol LogStream {
    func print(_ formattedOutput: String)
}

// MARK: - Default implementations
public struct DefaultMessageFormatter: LogMessageFormatter {
    let timestampFormatter: ISO8601DateFormatter = {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate, .withFullTime, .withSpaceBetweenDateAndTime, .withFractionalSeconds, .withTimeZone]
        return df
    }()

    public let includeCallSite: Bool

    public func formatOutput(
        timestamp: Date?,
        logTitle: String,
        level: LogLevel,
        messageBody: String,
        error: Error?,
        sourceFile: String,
        line: Int,
        function: String
    ) -> String {
        var output = String()

        if let t = timestamp {
            output.append(timestampFormatter.string(from: t))
            output.append(" ")
        }

        output.append("[\(logTitle)] \(level.paddedTitle.uppercased()) \(messageBody)")

        if let error = error {
            output.append(": ")
            output.append(error.localizedDescription)
            output.append(" ")
        }

        if includeCallSite {
            output.append(" → \(function) (\(sourceFile.split(separator: "/").last ?? "??"):\(line))")
        }

        if !output.hasSuffix("\n") {
            output.append("\n")
        }

        return output
    }
}

public struct StandardOutputLogStream: LogStream {
    public init() {
        // Has to exist for a public init to be available outside of framework
    }
    public func print(_ formattedOutput: String) {
        fputs(formattedOutput, stderr)
    }
}

public struct FileLogStream: LogStream {
    private let fileHandle: FileHandle
    private let encoding: String.Encoding

    public init(url: URL, encoding: String.Encoding = .utf8) throws {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: url.deletingLastPathComponent().path) {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil
            )
        }

        if !fileManager.fileExists(atPath: url.path) {
            try "".write(to: url, atomically: false, encoding: .utf8)
        }

        self.fileHandle = try FileHandle(forUpdating: url)
        self.fileHandle.seekToEndOfFile()
        self.encoding = encoding
    }

    public func print(_ formattedOutput: String) {
        guard let data = formattedOutput.data(using: .utf8) else {
            return
        }
        fileHandle.write(data)
    }
}

// MARK: -

public class Log {
    // MARK: Shared log instance
    private static var _shared: Log!

    public private(set) static var shared: Log = {
        if _shared == nil {
            Log.initialize()
        }
        return _shared!
    }()

    public static func initialize(sharedLogWithTitle title: String? = nil, level: LogLevel = .info, streams: [LogStream]? = nil) {
        guard _shared == nil else {
            preconditionFailure("Shared log instance is already initialized")
        }

        let log = Log(
            title: title ?? Bundle.main.bundleURL.lastPathComponent,
            streams: streams ?? [StandardOutputLogStream()]
        )
        log.level = .debug

        _shared = log
    }

    /// You will probably only want to call this in a `defer` block in a unit testing context, where consecutive tests set up
    /// logging individually.
    public static func deinitialize() {
        _shared?.debug("Deinitialize shared log instance")
        _shared = nil
    }

    // MARK: Log properties
    public let title: String

    public var fullTitle: String {
        var t = ""
        var nextLog: Log? = self
        while let log = nextLog {
            if t.isEmpty {
                t = log.title
            } else {
                t = log.title + t
            }
            nextLog = log.superlog
        }
        return t
    }

    public private(set) weak var superlog: Log? = nil
    public var level = LogLevel.warning
    private let formatter: LogMessageFormatter
    private var streams: AtomicResource<[LogStream]>
    private var sublogs = AtomicResource<[String: Log]>([:])

    // MARK: Initialisers

    public init(title: String, streams: [LogStream], formatter: LogMessageFormatter? = nil) {
        self.title = title
        self.streams = AtomicResource<[LogStream]>(streams, lockingBy: .readWriteLock)
        self.formatter = formatter ?? DefaultMessageFormatter(includeCallSite: false)
    }

    private init(superlog: Log, title: String) {
        self.superlog = superlog
        self.title = title
        let superstreams = superlog.streams.read { $0 }
        self.streams = AtomicResource<[LogStream]>(superstreams, lockingBy: .readWriteLock)
        self.formatter = superlog.formatter
    }

    public func sublog(withTitle title: String, level: LogLevel? = nil) -> Log {
        if let sublog = sublogs.read({ $0[title] }) {
            if let level = level, sublog.level != level {
                sublog.level = level
            }
            return sublog
        }
        let sublog = Log(superlog: self, title: title)
        sublog.level = level ?? self.level
        sublogs.modify { $0[title] = sublog }
        return sublog
    }

    // MARK: Log output

    public func canLog(atLevel level: LogLevel) -> Bool {
        guard level != .muted && self.level != .muted else {
            return false
        }
        return level.rawValue >= self.level.rawValue
    }

    @discardableResult public func log(
        atLevel level: LogLevel,
        force: Bool = false,
        _ messageBody: String,
        error: Error? = nil,
        sourceFile: String,
        line: Int,
        function: String
    ) -> Bool {
        guard force || canLog(atLevel: level) else {
            return false
        }

        let formattedOutput = formatter.formatOutput(
            timestamp: Date(),
            logTitle: title,
            level: level,
            messageBody: messageBody,
            error: error,
            sourceFile: sourceFile,
            line: line,
            function: function
        )

        streams.read { $0.forEach {
            $0.print(formattedOutput)
        }}

        return true
    }

    /// Print raw/preformatted output to log, bypassing log formatter.
    @discardableResult public func print(atLevel level: LogLevel, _ rawOutput: String) -> Bool {
        guard canLog(atLevel: level) else {
            return false
        }

        streams.read { $0.forEach {
            if rawOutput.hasSuffix("\n") {
                $0.print(rawOutput)
            } else {
                $0.print("\(rawOutput)\n")
            }
        }}

        return true
    }

    public func dddebug(_ message: String, sourceFile: String = #file, line: Int = #line, function: String = #function) {
        log(atLevel: .dddebug, message, sourceFile: sourceFile, line: line, function: function)
    }

    public func debug(_ message: String, sourceFile: String = #file, line: Int = #line, function: String = #function) {
        log(atLevel: .debug, message, sourceFile: sourceFile, line: line, function: function)
    }

    public func verbose(_ message: String, sourceFile: String = #file, line: Int = #line, function: String = #function) {
        log(atLevel: .verbose, message, sourceFile: sourceFile, line: line, function: function)
    }

    public func info(_ message: String, sourceFile: String = #file, line: Int = #line, function: String = #function) {
        log(atLevel: .info, message, sourceFile: sourceFile, line: line, function: function)
    }

    public func warning(_ message: String, sourceFile: String = #file, line: Int = #line, function: String = #function) {
        log(atLevel: .warning, message, sourceFile: sourceFile, line: line, function: function)
    }

    public func error(
        _ message: String, error: Error? = nil, sourceFile: String = #file, line: Int = #line, function: String = #function
    ) {
        log(atLevel: .error, message, error: error, sourceFile: sourceFile, line: line, function: function)
    }
    
    public func fatal(
        _ message: String, error: Error? = nil, sourceFile: String = #file, line: Int = #line, function: String = #function
    ) {
        log(atLevel: .fatal, message, error: error, sourceFile: sourceFile, line: line, function: function)
    }
    
    // MARK: Log streams
    
    public func appendLogStream(_ stream: LogStream) {
        streams.modify {
            $0.append(stream)
            sublogs.read {
                $0.values.forEach { sublog in
                    sublog.appendLogStream(stream)
                }
            }
        }
    }
}

// MARK: - Static convenience API

/// For convenience, provide static `Log.info()` etc. methods that delegate to the corresponding `Log.shared.info()` etc.
public extension Log {
    static func dddebug(_ message: String, sourceFile: String = #file, line: Int = #line, function: String = #function) {
        Self.shared.dddebug(message, sourceFile: sourceFile, line: line, function: function)
    }

    static func debug(_ message: String, sourceFile: String = #file, line: Int = #line, function: String = #function) {
        Self.shared.debug(message, sourceFile: sourceFile, line: line, function: function)
    }

    static func verbose(_ message: String, sourceFile: String = #file, line: Int = #line, function: String = #function) {
        Self.shared.verbose(message, sourceFile: sourceFile, line: line, function: function)
    }

    static func info(_ message: String, sourceFile: String = #file, line: Int = #line, function: String = #function) {
        Self.shared.info(message, sourceFile: sourceFile, line: line, function: function)
    }

    static func warning(_ message: String, sourceFile: String = #file, line: Int = #line, function: String = #function) {
        Self.shared.warning(message, sourceFile: sourceFile, line: line, function: function)
    }

    static func error(
        _ message: String, error: Error? = nil, sourceFile: String = #file, line: Int = #line, function: String = #function
    ) {
        Self.shared.error(message, error: error, sourceFile: sourceFile, line: line, function: function)
    }

    static func fatal(
        _ message: String, error: Error? = nil, sourceFile: String = #file, line: Int = #line, function: String = #function
    ) {
        Self.shared.fatal(message, error: error, sourceFile: sourceFile, line: line, function: function)
    }
}

// MARK: - Hashable

extension Log: Hashable {
    public static func == (lhs: Log, rhs: Log) -> Bool {
        return lhs === rhs || lhs.fullTitle == rhs.fullTitle
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(fullTitle)
    }
}

