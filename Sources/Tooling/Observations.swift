///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

/**
 Encapsulates observer management and posting notifications for an owning observee object
 that posts multiple kinds of notifications.
 */
public class Observations {
    /** Notification center to use. */
    let notificationCenter: NotificationCenter

    /** The object whose notifications this `Observations` instance manages. */
    public private(set) weak var observee: AnyObject?

    public init(observee: AnyObject, notificationCenter: NotificationCenter? = nil) {
        self.observee = observee
        self.notificationCenter = notificationCenter ?? NotificationCenter.default
    }

    deinit {
        tokens.forEach { notificationCenter.removeObserver($0.opaque) }
        tokens.removeAll()
    }

    // MARK: Tokens

    /** Struct for information necessary to add an observer, and later remove it. */
    private struct Token: Hashable, CustomDebugStringConvertible {
        let uuid = UUID()
        let observer: AnyObject
        let notificationName: Notification.Name
        let opaque: Any

        static func == (lhs: Token, rhs: Token) -> Bool {
            lhs.observer === rhs.observer && lhs.uuid == rhs.uuid && lhs.notificationName == rhs.notificationName
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(uuid)
            hasher.combine(notificationName)
        }

        var debugDescription: String {
            "\(notificationName as NSString as String) → \(observer) (\(uuid.shortString))"
        }
    }

    private var tokens = Set<Token>()

    private func existingToken(forObserver observer: AnyObject, notificationName: Notification.Name) -> Token? {
        tokens.first { $0.notificationName == notificationName && $0.observer === observer }
    }

    private func existingTokens(forObserver observer: AnyObject) -> [Token]? {
        tokens.filter { $0.observer === observer }
    }

    // MARK: Observer management

    public func addObserver(
        _ observer: AnyObject,
        notificationName: Notification.Name,
        lenient beLenient: Bool = true,
        handler: @escaping (Notification) -> Void
    ) {
        assert(Thread.isMainThread)

        guard let observee = self.observee else {
            return
        }

        guard existingToken(forObserver: observer, notificationName: notificationName) == nil else {
            guard beLenient else {
                Log.shared.warning("Will not add \(observer) as observer of '\(notificationName.rawValue)' for \(observee) more than once")
                return assertionFailure()
            }
            return
        }

        let opaque = notificationCenter.addObserver(forName: notificationName, object: observee, queue: nil, using: handler)
        let token = Token(observer: observer, notificationName: notificationName, opaque: opaque)
        tokens.insert(token)
    }

    public func removeObserver(_ observer: AnyObject, notificationName: Notification.Name? = nil) {
        assert(Thread.isMainThread)
        if let name = notificationName {
            if let token = existingToken(forObserver: observer, notificationName: name) {
                notificationCenter.removeObserver(token.opaque)
                tokens.remove(token)
            }
        } else {
            existingTokens(forObserver: observer)?.forEach {
                notificationCenter.removeObserver($0.opaque)
                tokens.remove($0)
            }
        }
    }

    public func removeAll() {
        assert(Thread.isMainThread)
        tokens.forEach {
            notificationCenter.removeObserver($0.opaque)
        }
        tokens.removeAll()
    }

    // MARK: Posting notifications

    private var deferNotifications = false {
        willSet {
            precondition(Thread.isMainThread)
        }
    }

    private var deferredNotifications = [Notification]()

    /**
     Post a notification either immediately, or deferredly if that's the current state of things.
     */
    public func postNotification(_ notification: Notification) {
        precondition(Thread.isMainThread)

        if deferNotifications {
            deferredNotifications.append(notification)
        } else {
            notificationCenter.post(notification)
        }
    }

    /*

     Instead of immediately posting notifications, wait until a given block of work is done.
     The closure is executed synchronously.

     This gives you the change to enclose changes to multiple observee properties into a single
     block of work, after which the observee is in a consistent state, safe for observers to
     examine in response to notifications.

     */
    public func deferringNotifications(untilCompleted work: () -> Void) {
        precondition(Thread.isMainThread)

        let alreadyDeferring = deferNotifications
        deferNotifications = true
        work()
        deferNotifications = alreadyDeferring

        // If all levels of deferring are done, post any accumulated pending notifications
        if !deferNotifications {
            deferredNotifications.forEach {
                notificationCenter.post($0)
            }
            deferredNotifications.removeAll()
        }
    }
}

extension Observations: CustomDebugStringConvertible {
    public var debugDescription: String {
        let sortedTokens: [Token] = tokens.sorted(by: {
            (($0.notificationName as NSString) as String)
                .localizedCaseInsensitiveCompare(($1.notificationName as NSString) as String) == .orderedAscending
        })
        let lastPrefixValue = sortedTokens.count
        let paddingLength = "#\(lastPrefixValue)".count
        var tokenList = ""
        for (n, t) in sortedTokens.enumerated() {
            let prefix = "#\(n + 1)".headPadded(toLength: paddingLength)
            tokenList.append("\(prefix): \(t.debugDescription)\n")
        }
        return "Observations for '\((observee as Any?) ?? "??")':\n\(tokenList)"
    }
}
