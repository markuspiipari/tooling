///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license. See LICENSE.md for details.
/// File status: Experimental
///

import Foundation

///
/// For rationale, see:
///
///   https://www.vadimbulavin.com/atomic-properties/
///   https://www.vadimbulavin.com/benchmarking-locking-apis/
///   https://www.cocoawithlove.com/blog/2016/06/02/threads-and-mutexes.html
///
/// Notes:
///
/// * Should you wonder about it in the future: we used to implement the public API here (`AtomicInteger`, `AtomicResource` and
///   `AtomicLock`) by wrapping a `DispatchSemaphore`, which _seemingly_ worked just fine. That approach, however, is not quite
///   the correct use of a signalling API, and also it's effectively equivalent to always locking with a mutex, without the option
///   of allowing multiple concurrent readers on a resource.
///
/// * There are implementations on the interwebs that further wrap this stuff in a property wrapper. As of this writing (for
///   https://gitlab.com/sashimiapp/sashimi/-/issues/344) I am however of the mind that this would make the locking too implicit,
///   and make one not give each case the proper thought they deserve. The need for this type of locking should be the exception,
///   when the default approach of performing standalone background tasks on an operation/dispatch queue isn't enough.
///

/// Models available ways of locking.
public enum LockingMechanism {
    /// Multiple concurrent reader, single writer access, using a Pthreads read-write lock.
    case readWriteLock

    /// Single reader or writer access, using a Pthreads mutex.
    case mutex

    fileprivate func makeLock() -> Lock {
        switch self {
        case .readWriteLock:
            return ReadWriteLock()
        case .mutex:
            return Mutex()
        }
    }
}

// MARK: -

/// Encapsulate an integer value for thread-safe, atomic manipulation.
/// Defaults to a Pthreads read-write lock as the locking mechanism.
public class AtomicInteger<T: FixedWidthInteger> {
    private let lock: Lock
    private var _value: T

    public init(_ initialValue: T, lockingBy locking: LockingMechanism = .readWriteLock) {
        self._value = initialValue
        self.lock = locking.makeLock()
    }

    public var value: T {
        get {
            lock.lock(for: .reading)
            defer {
                lock.unlock()
            }
            return _value
        }
        set {
            lock.lock(for: .writing)
            defer {
                lock.unlock()
            }
            _value = newValue
        }
    }

    public func increment(by amount: T = 1) -> T {
        lock.lock(for: .writing)
        defer {
            lock.unlock()
        }
        _value += amount
        return _value
    }
}

/// Encapsulate a boolean value for thread-safe, atomic manipulation.
/// Defaults to a Pthreads read-write lock as the locking mechanism.
public class AtomicBoolean {
    private let lock: Lock
    private var _value: Bool

    public init(_ initialValue: Bool, lockingBy locking: LockingMechanism = .readWriteLock) {
        self._value = initialValue
        self.lock = locking.makeLock()
    }

    public var value: Bool {
        get {
            lock.lock(for: .reading)
            defer {
                lock.unlock()
            }
            return _value
        }
        set {
            lock.lock(for: .writing)
            defer {
                lock.unlock()
            }
            _value = newValue
        }
    }
}

// MARK: -

/// Encapsulate a resource for atomic, thread-safe manipulation.
/// Defaults to a Pthreads read-write lock as the locking mechanism.
public class AtomicResource<T: Any> {
    private let lock: Lock
    private var resource: T

    public init(_ resource: T, lockingBy locking: LockingMechanism = .readWriteLock) {
        self.resource = resource
        self.lock = locking.makeLock()
    }

    public func read<U>(_ closure: (_ resource: T) throws -> U) rethrows -> U {
        lock.lock(for: .reading)
        defer {
            lock.unlock()
        }
        return try closure(resource)
    }

    @discardableResult public func modify<U>(_ closure: (_ resource: inout T) throws -> U) rethrows -> U {
        lock.lock(for: .writing)
        defer {
            lock.unlock()
        }
        return try closure(&resource)
    }
}

// MARK: -

/// Provides an atomic, thread-safe lock to use when a resource cannot be encapsulated by an `AtomicResource`.
/// Defaults to a Pthreads read-write lock as the locking mechanism.
public struct AtomicLock {
    private let lock: Lock

    init(lockingBy locking: LockingMechanism = .readWriteLock) {
        self.lock = locking.makeLock()
    }

    public func read<T>(_ closure: () -> T) -> T {
        lock.lock(for: .reading)
        defer {
            lock.unlock()
        }
        return closure()
    }

    @discardableResult public func modify<T>(_ closure: () -> T) -> T {
        lock.lock(for: .writing)
        defer {
            lock.unlock()
        }
        return closure()
    }
}

// MARK: - Private bits

fileprivate enum AtomicOperation {
    case reading
    case writing
}

/// Protocol implemented by available atomic locking variants.
fileprivate protocol Lock {
    func lock(for operation: AtomicOperation)
    func unlock()
}

/// Locking variant wrapping a Pthreads read-write lock.
fileprivate final class ReadWriteLock: Lock {
    private var lock: pthread_rwlock_t

    init() {
        self.lock = pthread_rwlock_t()
        pthread_rwlock_init(&lock, nil)
    }

    deinit {
        pthread_rwlock_destroy(&lock)
    }

    func lock(for operation: AtomicOperation) {
        switch operation {
        case .reading:
            pthread_rwlock_rdlock(&lock)
        case .writing:
            pthread_rwlock_wrlock(&lock)
        }
    }

    func unlock() {
        pthread_rwlock_unlock(&lock)
    }
}

/// Locking variant wrapping a Pthreads mutex.
fileprivate final class Mutex: Lock {
    private var mutex: pthread_mutex_t

    init() {
        self.mutex = pthread_mutex_t()
        pthread_mutex_init(&mutex, nil)
    }

    deinit {
        pthread_mutex_destroy(&mutex)
    }

    func lock(for operation: AtomicOperation) {
        pthread_mutex_lock(&mutex)
    }

    func unlock() {
        pthread_mutex_unlock(&mutex)
    }
}
