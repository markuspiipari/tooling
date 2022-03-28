///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license. See LICENSE.md for details.
/// File status: Experimental
///

import Foundation

/**

 Abstract base class for cancellable, failable asynchronous operations executed on an `OperationQueue`.

 Subclasses must override the `run()` method to implement their asynchronous work.

 */
open class AsynchronousOperation: Operation {
    public let label: String

    public init(label: String) {
        self.label = label
        super.init()
    }

    // MARK: Override points for subclasses

    /**

     Subclasses _must_ override to implement the work they want performed. The method is called by
     the base class `start()` implementation.

     The overridden implementation _must not_ change operation state to `.executing`, because this
     is done by the base class `start()` implementation before calling `run()`.

     _If_ the operation subclass performs all work synchronously in its `run()` implementation, it
     also _need not_ change `state` to `.competed` at the end.

     The overridden implementation _should_ change `state` to `.completed`

     */
    open func run() throws {
        preconditionFailure("\(type(of: self)) subclasses must override \(#function)")
    }

    /**
     Subclasses SHOULD override to indicate that the operation must not be automatically
     marked as completed after `run()` finishes, because it dispatches asynchronous work,
     rather than performing all of it in one synchronous pass of executing `run()`.
     */
    open var runsSynchronously: Bool {
        true
    }

    // MARK: Override behaviour for asynchronous operation

    //       ...as documented under "Subclassing Notes" at: https://developer.apple.com/documentation/foundation/operation

    @objc override public var isAsynchronous: Bool {
        true
    }

    @objc override public var isExecuting: Bool {
        switch state {
        case .executing:
            return true
        default:
            return false
        }
    }

    @objc override public var isFinished: Bool {
        state.isDone
    }

    override public func start() {
        guard state.canTransition(to: .executing) else {
            return // Operation has been cancelled before starting
        }

        state = .executing

        do {
            try run()
            if runsSynchronously, state.canTransition(to: .completed) {
                state = .completed
            }
        } catch {
            if runsSynchronously {
                let newState = State.failed(error: error)
                if state.canTransition(to: newState) {
                    state = newState
                }
            }
        }
    }

    override open func cancel() {
        super.cancel()
        if !state.isDone {
            state = .cancelled
        }
    }

    // MARK: Operation state

    public enum State {
        case initialized
        case executing
        case cancelled
        case completed
        case failed(error: Swift.Error)

        public var isDone: Bool {
            switch self {
            case .initialized, .executing:
                return false
            case .completed, .cancelled, .failed:
                return true
            }
        }

        public func canTransition(to newState: State) -> Bool {
            switch newState {
            case .initialized:
                return false // Must never set state to initialized anew

            case .executing:
                switch self {
                case .initialized:
                    return true
                default:
                    return false
                }

            case .cancelled, .completed, .failed:
                switch self {
                case .initialized, .executing:
                    return true
                default:
                    return false
                }
            }
        }
    }

    public var state = State.initialized {
        willSet {
            guard state.canTransition(to: newValue) else {
                preconditionFailure("An asynchronous operation cannot transition from \(state) to \(newValue)")
            }

            willChangeValue(for: \AsynchronousOperation.isExecuting)

            switch newValue {
            case .cancelled, .completed, .failed:
                willChangeValue(for: \AsynchronousOperation.isFinished)
            default: ()
            }
        }

        didSet {
            didChangeValue(for: \AsynchronousOperation.isExecuting)

            switch state {
            case .cancelled, .completed, .failed:
                willChangeValue(for: \AsynchronousOperation.isFinished)
            default: ()
            }
        }
    }
}
