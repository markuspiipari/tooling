///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

/// Build-time default for whether a requirement failure results in a fatal error, or a precondition failure.
public let failRequirementsWithFatalError = true

/// Conditional on a test result, raise a requirement failure.
public func require(
    _ test: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String,
    isFatal: Bool? = nil,
    function: StaticString = #function,
    sourceFile: StaticString = #file,
    line: UInt = #line
) {
    guard test() else {
        requirementFailure(message(), isFatal: isFatal, sourceFile: sourceFile, line: line)
    }
}

/// Raise a requirement failure.
public func requirementFailure(
    _ message: @autoclosure () -> String,
    isFatal: Bool? = nil,
    sourceFile: StaticString = #file,
    line: UInt = #line
) -> Never {
    if isFatal ?? failRequirementsWithFatalError {
        fatalError(message(), file: sourceFile, line: line)
    } else {
        preconditionFailure(message(), file: sourceFile, line: line)
    }
}

// MARK: - Concurrency requirements

/// Build-time default for whether a failing concurrency requirement results in a fatal error, or a precondition failure.
public let failConcurrencyRequirementsWithFatalError = true

/// Require current code to execute on the main thread.
public func requireMainThread(sourceFile: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
    require(
        Thread.isMainThread,
        "Must execute \(function) on the main thread",
        isFatal: failConcurrencyRequirementsWithFatalError,
        sourceFile: sourceFile,
        line: line
    )
}

/// Require current code to execute off the main thread.
public func requireNonMainThread(sourceFile: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
    require(
        !Thread.isMainThread,
        "Must execute \(function) off the main thread",
        isFatal: failConcurrencyRequirementsWithFatalError,
        sourceFile: sourceFile,
        line: line
    )
}

// MARK: - Programming errors

/// Require a successful typecast to the expected type.
public func requireTypecast<T, U>(_ t: T, sourceFile: StaticString = #file, line: UInt = #line) -> U {
    guard let result = t as? U else {
        requirementFailure("Programming error: \(t) must be a \(U.self)", sourceFile: sourceFile, line: line)
    }
    return result
}

public extension Swift.Optional {
    func unwrappedAs<T>(_ t: T.Type, sourceFile: StaticString = #file, line: UInt = #line) -> T {
        let u: T = requireTypecast(self, sourceFile: sourceFile, line: line)
        return u
    }
}

/// Raise a requirement failure for a method that is missing an implementation.
public func requireImplementation<T>(
    _ t: T.Type,
    sourceFile: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
) -> Never {
    requirementFailure("\(t) must implement \(function)", sourceFile: sourceFile, line: line)
}


/// Raise a requirement failure for a method override missing from a subclass.
public func requireOverride<T>(
    _ t: T.Type,
    sourceFile: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
) -> Never {
    requirementFailure("\(t) must override \(function)", sourceFile: sourceFile, line: line)
}

/// Raise a requirement failure when an intentionally unimplemented method is called.
public func intentionallyNotImplemented<T>(
    _ t: T.Type,
    sourceFile: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
) -> Never {
    requirementFailure("\(t) does not implement \(function)", sourceFile: sourceFile, line: line)
}

