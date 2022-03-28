///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license. See LICENSE.md for details.
/// File status: Experimental
///

import Foundation

/**

 Wraps a dispatch semaphore for use cases where a method needs to synchronously wait
 for a result being produced by an operation executing in another thread/queue.

 Either the waiting, or the producing, can be restricted to occur *on* the main thread,
 while the other must then execute *off* it.

 For the avoidance of doubt, the point of using this struct rather than `DispatchSemaphore`
 directly is:

 - The encapsulated on/off main thread preconditioning, to catch programming errors early
 - The `BinarySemaphores` struct that provides an equivalent API for waiting on multiple
   `Hashable` targets

 */
public struct BinarySemaphore<R: Any> {
    private var result: R?

    private lazy var semaphore: DispatchSemaphore = {
        DispatchSemaphore(value: 0)
    }()

    public let scheme: WaitingScheme

    public init(_ scheme: WaitingScheme) {
        self.scheme = scheme
    }

    /**
     Wait until this semaphore is unlocked, by a related asynchronous operation calling `unlock()`
     on this binary semaphore.
     @param message Optional debug message to print out to the console.
     @param timeout Optional maximum time to wait for. If `nil` (the default), will wait indefinitely.
     @return If semaphore was succesfully unlocked, `true`. If the operation timed out, `false`.
     */
    @discardableResult public mutating func wait(_ message: String? = nil, timeout: TimeInterval? = nil) -> Bool {
        scheme.validateWaiting()
        
        if let message = message {
            Log.shared.debug(message)
        }
        
        if let t = timeout {
            switch semaphore.wait(wallTimeout: .now() + t) {
            case .success:
                if let message = message {
                    Log.shared.debug("'\(message)' did NOT time out")
                }
                return true
            case .timedOut:
                if let message = message {
                    Log.shared.debug("'\(message)' did TIME OUT")
                }
                return false
            }
        } else {
            semaphore.wait()
            return true
        }
    }

    public mutating func waitForResult(_ message: String? = nil, timeout: TimeInterval? = nil) -> R? {
        guard wait(message, timeout: timeout) else {
            return nil
        }
        return result
    }

    /**
     Unlock this binary semaphore, letting code currently waiting (on a `wait()` call)
     continue executing.
     */
    public mutating func unlock(result: R? = nil) {
        scheme.validateUnlocking()
        self.result = result
        semaphore.signal()
    }

    public mutating func consumeResult() -> R? {
        let result = self.result
        self.result = nil
        return result
    }
}

/**
 Wraps binary semaphores for multiple targets being waited on.
 */
public struct BinarySemaphores<T: Hashable, R: Any> {
    let scheme: WaitingScheme

    /** Serial queue for modifying the semaphore and result dictionaries. */
    private let serialQueue = DispatchQueue(label: "com.sashimiapp.BinarySemaphoresQueue")
    private var semaphores = [T: DispatchSemaphore]()
    private var results = [T: R]()

    public init(_ scheme: WaitingScheme) {
        self.scheme = scheme
    }

    @discardableResult public mutating func wait(for target: T) -> R? {
        scheme.validateWaiting()

        let semaphore: DispatchSemaphore = serialQueue.sync {
            let semaphore = DispatchSemaphore(value: 0)
            semaphores[target] = semaphore
            return semaphore
        }

        semaphore.wait()

        return serialQueue.sync {
            results.removeValue(forKey: target)
        }
    }

    public mutating func unlock(for target: T, result: R? = nil) {
        scheme.validateUnlocking()

        guard let semaphore: DispatchSemaphore = serialQueue.sync(execute: {
            let semaphore = semaphores[target]
            semaphores.removeValue(forKey: target)
            if let result = result {
                results[target] = result
            }
            return semaphore
        }) else {
            return
        }

        semaphore.signal()
    }
}

/**
 Scheme for enforcing `wait()` and `unlock()` calls to take place appropriately on & off
 the main thread, such that one is preconditioned to occur *on*, the other *off* the main
 thread.
 */
public enum WaitingScheme {
    case waitOnMainThread
    case waitOffMainThread
    case waitAndUnlockOffMainThread
    case waitWherever

    func validateWaiting() {
        switch self {
        case .waitOnMainThread:
            requireMainThread()
        case .waitOffMainThread, .waitAndUnlockOffMainThread:
            requireNonMainThread()
        case .waitWherever:
            break
        }
    }

    func validateUnlocking() {
        switch self {
        case .waitOnMainThread, .waitAndUnlockOffMainThread:
            requireNonMainThread()
        case .waitOffMainThread:
            requireMainThread()
        case .waitWherever:
            break
        }
    }
}
