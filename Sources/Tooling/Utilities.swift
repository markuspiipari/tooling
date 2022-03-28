///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Cocoa

// MARK: - Beeping

public func beep() {
    NSSound.beep()
}

/**
 If assertions are on, trigger an assertion failure, optionally with a message.
 If assertions are off, make a beep.
 */
public func failureBeep(_ message: String? = nil) {
    if let msg = message {
        assertionFailure(msg)
    } else {
        assertionFailure()
    }
    NSSound.beep()
}

// MARK: - Recurring closure types

public typealias VoidClosure = () -> Void
public typealias TestClosure = () -> Bool

// MARK: - Debug drawing

public func strokeRect(_ r: NSRect, color: NSColor = NSColor.red) {
    color.set()
    NSBezierPath.stroke(r)
}
