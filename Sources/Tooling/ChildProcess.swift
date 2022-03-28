///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license. see LICENSE.md for details.
/// File status: Experimental
///

import AppKit

/// Service for executing a child process synchronously, recording the standard output and error streams and exit code.
public enum ChildProcess {
    public enum Outcome {
        case success(stdout: Data, stderr: Data)
        case failure(exitCode: Int32, stdout: Data, stderr: Data)
        case uncaughtSignal(exitCode: Int32, stdout: Data, stderr: Data)
    }

    public static func execute(fileURL: URL, arguments: [String]) -> Outcome {
        let task = Process()

        let outData = NSMutableData()
        let errData = NSMutableData()

        task.launchPath = fileURL.path
        task.currentDirectoryPath = fileURL.deletingLastPathComponent().path
        task.arguments = arguments

        let stdoutPipe = Pipe()
        task.standardOutput = stdoutPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { file in
            let data = file.availableData
            outData.append(data)
        }

        let stderrPipe = Pipe()
        task.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { file in
            let data = file.availableData
            errData.append(data)
        }

        let semaphore = DispatchSemaphore(value: 0)

        task.terminationHandler = { _ in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            semaphore.signal()
        }

        task.launch()
        semaphore.wait()

        guard task.terminationReason != .uncaughtSignal else {
            return .uncaughtSignal(exitCode: task.terminationStatus,
                                   stdout: outData as Data,
                                   stderr: errData as Data)
        }

        guard task.terminationStatus == 0 else {
            return .failure(exitCode: task.terminationStatus,
                            stdout: outData as Data,
                            stderr: errData as Data)
        }

        return .success(stdout: outData as Data, stderr: errData as Data)
    }
}
