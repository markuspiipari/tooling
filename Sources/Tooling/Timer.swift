///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation
import Dispatch

///
/// Inspired by:
///    https://medium.com/over-engineering/a-background-repeating-timer-in-swift-412cecfd2ef9
///    https://gist.githubusercontent.com/danielgalasko/1da90276f23ea24cb3467c33d2c05768/raw/5ffbcfee1caf09eea8649cba94d93df469e1a609/RepeatingTimer.swift
///
public class RepeatingTimer {
    public let interval: TimeInterval
    private(set) var tickHandler: TickHandler?

    public typealias TickHandler = () -> Void

    public init(interval: TimeInterval, tickHandler: @escaping TickHandler) {
        self.interval = interval
        self.tickHandler = tickHandler
    }

    private lazy var timer: DispatchSourceTimer = {
        let t = DispatchSource.makeTimerSource()
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let tick = self?.tickHandler else {
                return
            }
            tick()
        }
        return t
    }()

    private enum State {
        case stopped
        case started
    }

    private let state = AtomicResource<State>(.stopped)

    deinit {
        state.modify {
            timer.setEventHandler {}
            timer.cancel()
            // If the timer is suspended, calling cancel without resuming triggers a crash.
            // This is documented here https://forums.developer.apple.com/thread/15902
            timer.resume()
            tickHandler = nil
            $0 = .stopped
        }
    }

    public func start() {
        state.modify {
            guard $0 == .stopped else {
                return
            }
            $0 = .started
            timer.resume()
        }
    }

    public func stop() {
        state.modify {
            guard $0 == .started else {
                return
            }
            $0 = .stopped
            timer.suspend()
        }
    }
}

