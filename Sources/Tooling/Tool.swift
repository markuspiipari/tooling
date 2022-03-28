///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

///
/// API for running a helper tool as a child process, recording the standard output & error streams, and its exit code.
///
open class Tool {
    /// Executable URL of this helper tool.
    public let url: URL

    // MARK: - Initialization
    public init(url: URL) {
        self.url = url
    }

    public convenience init(_ path: String) {
        self.init(url: URL(fileURLWithPath: path))
    }

    public init(resolving executableName: String, in locations: [ExecutableLocation]? = nil, log: Log?) throws{
        guard let url = Tool.resolveURL(for: executableName, in: locations ?? [.pathEnvironment]) else {
            throw Error.failedToResolveExecutableLocation(executableName: executableName)
        }
        self.url = url
    }

    public var name: String {
        return url.lastPathComponent
    }

    public func commandLine(with arguments: [String]?) -> String {
        return url.commandLine(with: arguments)
    }

    // MARK: - Resolving executable location

    public enum ExecutableLocation {
        case bundled(in: Bundle)
        case custom(paths: [String])
        case mainBundle /* Auxiliary executables location within the main bundle. */
        case standard /* /bin /sbin /usr/bin */
        case standardLocal /* /usr/local/bin /opt/local/bin */
        case pathEnvironment /* Parse $PATH */

        var paths: [String] {
            switch self {
            case .bundled, .mainBundle:
                return [] // Bundled executables can only be resolved by asking the bundle by name
            case .custom(let paths):
                return paths
            case .pathEnvironment:
                guard let value = ProcessInfo().environment["PATH"], !value.isEmpty else {
                    return []
                }
                return value.split(separator: ":").map { String($0) }
            case .standard:
                return ["/bin", "/sbin", "/usr/bin"]
            case .standardLocal:
                return ["/usr/local/bin", "/opt/local/bin"]
            }
        }

        func resolve(for executableName: String) -> URL? {
            switch self {
            case .mainBundle:
                return Bundle.main.url(forAuxiliaryExecutable: executableName)
            case .bundled(let bundle):
                return bundle.url(forAuxiliaryExecutable: executableName)
            case .standard, .standardLocal, .pathEnvironment, .custom:
                let fileManager = FileManager.default
                for path in paths {
                    let url = URL(fileURLWithPath: "\(path)/\(executableName)")
                    if fileManager.isExecutableFile(atPath: url.standardizedFileURL.path) {
                        return url
                    }
                }
                return nil
            }
        }
    }

    public static func resolveURL(for executableName: String, in locations: [ExecutableLocation]) -> URL? {
        for location in locations {
            if let url = location.resolve(for: executableName) {
                return url
            }
        }
        return nil
    }

    // MARK: - Running
    
    public struct Configuration {
        public let environment: [String: String]
        public let workingDirectoryURL: URL?
        public let log: Log
        public let successfulExitCodes: [Int32]
        public let options: RunOptions
        
        /// Even if `options` includes the `.logCommandLine` option, do not print out any command line arguments following the
        /// argument value following this value.
        public let redactCommandLineArgumentsFollowing: String?
        
        public static let `default` = Configuration()
        public static let debug: Configuration = .default.updating(options: .default.union(.logCommandLineAndAllOutput))
        public static let dddebug: Configuration = .default.updating(options: .default.union(.logEverything))
        
        public init(
            environment: [String: String] = [:],
            workingDirectoryURL: URL? = nil,
            log: Log = Log.shared,
            options: RunOptions = .default,
            redactCommandLineArgumentsFollowing redactAfter: String? = nil,
            successfulExitCodes: [Int32] = [0]
        ) {
            self.environment = environment
            self.workingDirectoryURL = workingDirectoryURL
            self.log = log
            self.successfulExitCodes = successfulExitCodes
            self.options = options
            self.redactCommandLineArgumentsFollowing = redactAfter
        }
        
        public func updating(
            environment: [String: String]? = nil,
            workingDirectoryURL: URL? = nil,
            log: Log? = nil,
            options: RunOptions? = nil,
            redactCommandLineArgumentsFollowing redactAfter: String? = nil,
            successfulExitCodes: [Int32]? = nil
        ) -> Configuration {
            Configuration(
                environment: environment ?? self.environment,
                workingDirectoryURL: workingDirectoryURL ?? self.workingDirectoryURL,
                log: log ?? self.log,
                options: options ?? self.options,
                redactCommandLineArgumentsFollowing: redactAfter ?? self.redactCommandLineArgumentsFollowing,
                successfulExitCodes: successfulExitCodes ?? self.successfulExitCodes
            )
        }
    }
    
    public struct RunOptions: OptionSet {
        public let rawValue: Int
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        public static let inheritEnvironment = RunOptions(rawValue: 1 << 0)
        public static let logCommandLine = RunOptions(rawValue: 1 << 1)
        public static let logEnvironment = RunOptions(rawValue: 1 << 2)
        public static let logOutput = RunOptions(rawValue: 1 << 3)
        public static let logErrorOutput = RunOptions(rawValue: 1 << 4)

        public static let `default`: RunOptions = [.inheritEnvironment, .logOutput, .logErrorOutput]
        public static let logCommandLineAndAllOutput: RunOptions = [.logCommandLine, .logOutput, .logErrorOutput]
        public static let logEverything: RunOptions = [.logCommandLine, .logOutput, .logErrorOutput, .logEnvironment]
        
        public func updating(with options: RunOptions) -> RunOptions {
            var t = self
            t.update(with: options)
            return t
        }
    }
    
    public struct ExitStatus {
        public enum Outcome {
            case success
            case failure
            case uncaughtSignal
            case unknownCondition
        }

        public let outcome: Outcome
        public let exitCode: Int32
        public let output: Data
        public let errorOutput: Data

        public init(outcome: Outcome, exitCode: Int32, output: Data, errorOutput: Data) {
            self.outcome = outcome
            self.exitCode = exitCode
            self.output = output
            self.errorOutput = errorOutput
        }
        
        public var utf8Output: String? {
            return output(inEncoding: .utf8)
        }

        public var utf8ErrorOutput: String? {
            return errorOutput(inEncoding: .utf8)
        }

        public func output(inEncoding encoding: String.Encoding) -> String? {
            return String(data: output, encoding: encoding)
        }

        public func errorOutput(inEncoding encoding: String.Encoding) -> String? {
            return String(data: errorOutput, encoding: encoding)
        }
    }

    /// Run tool synchronously.
    public func run(
        arguments: [String] = [],
        configuration: Configuration = .default,
        input: Data? = nil
    ) throws -> ExitStatus {

        try validateExecutable()

        let process = Process()
        let output = NSMutableData()
        let errorOutput = NSMutableData()
        let log = configuration.log

        //
        // See https://stackoverflow.com/questions/47315066/nstask-process-deprecated-methods-and-properties
        // for Process API changes in 10.13, so far undocumented by Apple.
        //
        process.executableURL = url
        process.currentDirectoryURL = configuration.workingDirectoryURL ?? url.deletingLastPathComponent()
        process.arguments = arguments
        process.environment = {
            if configuration.options.contains(.inheritEnvironment) {
                return ProcessInfo().environment.union(configuration.environment)
            } else {
                return configuration.environment
            }
        }()

        // Capture & log stdout
        let outputPipe = Pipe()
        outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            output.append(data)
            if configuration.options.contains(.logOutput), let text = data.utf8String(), text.isNonEmpty {
                log.info(text)
            }
        }
        process.standardOutput = outputPipe

        // Capture & log stderr
        let errorPipe = Pipe()
        errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            errorOutput.append(data)
            if configuration.options.contains(.logErrorOutput), let text = data.utf8String(), text.isNonEmpty {
                log.error(text)
            }
        }
        process.standardError = errorPipe

        if configuration.options.contains(.logEnvironment), let environment = process.environment {
            log.debug("Environment:")
            for key in environment.keys.sorted() {
                log.print(atLevel: .debug, "  \(key) = \(environment[key] ?? "")")
            }
        }

        if configuration.options.contains(.logCommandLine) {
            let arguments: [String]?
            
            if let redactAfter = configuration.redactCommandLineArgumentsFollowing,
               let args = process.arguments,
               let i = args.firstIndex(of: redactAfter) {
                arguments = args.prefix(through: i) + ["…"]
            } else {
                arguments = process.arguments
            }
            
            log.debug("Command line:\n  \(commandLine(with: arguments))")
        }

        // Run tool:
        let semaphore = DispatchSemaphore(value: 0)

        //
        process.terminationHandler = { process in
            let outputHandle = outputPipe.fileHandleForReading
            outputHandle.readabilityHandler?(outputHandle) // Ensure every byte of stdout data gets read
            outputHandle.readabilityHandler = nil

            let errorHandle = errorPipe.fileHandleForReading
            errorHandle.readabilityHandler?(errorHandle)  // Ensure every byte of stderr data gets read
            errorHandle.readabilityHandler = nil

            semaphore.signal()
        }

        // ▸ Optionally, pass data to the tool via standard input
        if let input = input, input.isNonEmpty {
            let inputPipe = Pipe()
            process.standardInput = inputPipe.fileHandleForReading
            inputPipe.fileHandleForWriting.write(input)
            inputPipe.fileHandleForWriting.closeFile()
        }
        
        do {
            try process.run()
        } catch {
            throw Error.failedToRun(underlyingError: error)
        }

        // Wait until terminated
        semaphore.wait()

        // Return exit status
        let exitCode = process.terminationStatus
        
        switch process.terminationReason {
        case .exit:
            guard configuration.successfulExitCodes.contains(exitCode) else {
                return ExitStatus(outcome: .failure, exitCode: exitCode, output: output as Data, errorOutput: errorOutput as Data)
            }
            return ExitStatus(outcome: .success, exitCode: exitCode, output: output as Data, errorOutput: errorOutput as Data)

        case .uncaughtSignal:
            return ExitStatus(
                outcome: .uncaughtSignal, exitCode: exitCode, output: output as Data, errorOutput: errorOutput as Data
            )

        default:
            return ExitStatus(
                outcome: .unknownCondition, exitCode: exitCode, output: output as Data, errorOutput: errorOutput as Data
            )
        }
    }

    public func validateExecutable() throws {
        let path = url.standardizedFileURL.path
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw Error.invalidExecutable(standardizedPath: path)
        }
    }

    /**
     Run this tool, throwing an error for any other exit status outcome than `.success`.
     Intended to be useful for command line tools that run other tool processes.
     */
    @discardableResult public func summon(
        arguments: [String] = [],
        configuration: Configuration,
        input: Data? = nil
    ) throws -> ExitStatus {
        let exitStatus = try run(arguments: arguments, configuration: configuration, input: input)

        switch exitStatus.outcome {
        case .success:
            return exitStatus
        default:
            throw Error.unsuccesful(exitStatus: exitStatus)
        }
    }

    @discardableResult public func callAsFunction(
        arguments: [String] = [],
        configuration: Configuration = .default
    ) throws -> ExitStatus {
        try summon(arguments: arguments, configuration: configuration)
    }

    // MARK: - Commands
    
    open class Command {
        public let tool: Tool
        public let supercommand: Command?
        public let name: String
        public let environment: [String: String]
        public let arguments: [String]
        public let options: RunOptions

        public init(
            tool: Tool,
            supercommand: Command? = nil,
            name: String,
            environment: [String: String] = [:],
            arguments: [String] = [],
            options: RunOptions = .default
        ) {
            self.tool = tool
            self.supercommand = supercommand
            self.name = name
            self.environment = environment
            self.arguments = arguments
            self.options = options
        }

        func resolveArguments(_ arguments: [String] = []) -> [String] {
            return [name] + self.arguments + arguments
        }

        private var commandChain: [Command] {
            var chain = [Command]()
            var nextCommand: Command? = self
            while let command = nextCommand {
                chain.insert(command, at: 0)
                nextCommand = command.supercommand
            }
            return chain
        }
        
        func resolveToolArguments(_ arguments: [String] = []) -> [String] {
            let resolved = commandChain.flattening {
                $0.resolveArguments($0 === self ? arguments : [])
            }
            return resolved
        }
        
        func resolveToolConfiguration(_ configuration: Tool.Configuration) throws -> Configuration {
            var configuration = configuration
            for command in commandChain.reversed() {
                configuration = configuration.updating(
                    environment: configuration.environment.union(command.environment),
                    options: configuration.options.updating(with: configuration.options)
                )
            }
            return configuration
        }

        public func run(arguments: [String] = [], configuration: Tool.Configuration = .default) throws -> ExitStatus {
            try tool.run(
                arguments: resolveToolArguments(arguments),
                configuration: resolveToolConfiguration(configuration)
            )
        }

        @discardableResult public func summon(
            arguments: [String] = [],
            configuration: Tool.Configuration = .default
        ) throws -> ExitStatus {
            try tool.summon(
                arguments: resolveToolArguments(arguments),
                configuration: resolveToolConfiguration(configuration)
            )
        }

        @discardableResult public func callAsFunction() throws -> ExitStatus {
            try summon(
                arguments: arguments,
                configuration: Configuration(environment: environment, options: options)
            )
        }

        public func commandLine(with arguments: [String]) -> String {
            return resolveToolArguments(arguments).joined(separator: " ")
        }
    }

    // MARK: - Errors

    public enum Error: LocalizedError {
        /// Tool executable with permission to run not found at the URL specified.
        case invalidExecutable(standardizedPath: String)

        /// Launching tool process failed.
        case failedToRun(underlyingError: Swift.Error)

        /// Tool binary was not found within the location options specified.
        case failedToResolveExecutableLocation(executableName: String)

        /// Summoning resulted in an outcome other than `.success`.
        case unsuccesful(exitStatus: ExitStatus)

        public var errorDescription: String? {
            switch self {
            case let .invalidExecutable(path):
                return String(format: NSLocalizedString("File at %@ is not executable", comment: ""), path)
            case let .failedToRun(underlyingError):
                return String(format: NSLocalizedString("Failed to run: %@", comment: ""), underlyingError.localizedDescription)
            case let .failedToResolveExecutableLocation(executableName):
                return String(format: NSLocalizedString("Failed to locate executable by name '%@'", comment: ""), executableName)
            case let .unsuccesful(exitStatus):
                return String(format: NSLocalizedString("Execution failed with status %i", comment: ""), exitStatus.exitCode)
            }
        }
    }
}

// MARK: - Utilities

public extension URL {
    func commandLine(with arguments: [String]?) -> String {
        guard isFileURL, !path.isEmpty else {
            return ""
        }
        var result = "\(path)"
        if let arguments = arguments, !arguments.isEmpty {
            result.append(" ")
            result.append(arguments.joined(separator: " "))
        }
        return result
    }
}

public extension Process {
    var commandLine: String {
        return executableURL?.commandLine(with: arguments) ?? ""
    }
}

public extension Data {
    func utf8String() -> String? {
        return String(data: self, encoding: .utf8)
    }
}

public extension NSData {
    func utf8String() -> String? {
        return (self as Data).utf8String()
    }
}
