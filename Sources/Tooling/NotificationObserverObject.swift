///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Cocoa

@objc internal class NotificationObserverObject: NSObject {
    static var observerObjects = [NotificationObserverObject]()

    let notificationName: NSNotification.Name
    weak var owner: AnyObject?
    weak var object: AnyObject?

    init(notificationName: NSNotification.Name, object: AnyObject, owner: AnyObject) {
        self.notificationName = notificationName
        self.object = object
        self.owner = owner
    }

    class func stopObserving(notification notificationName: NSNotification.Name, of object: AnyObject,
                             forOwner owner: AnyObject) {
        let observerObjects = self.observerObjects.filter { (object: NotificationObserverObject) -> Bool in
            object.notificationName == notificationName && object.object === object && object.owner === owner
        }

        for object in observerObjects {
            NotificationCenter.default.removeObserver(object, name: notificationName, object: object)
            if let i = self.observerObjects.firstIndex(of: object) {
                self.observerObjects.remove(at: i)
            }
        }
    }
}

public typealias ViewNotificationObserver = (_ view: NSView) -> Void

internal class ViewNotificationObserverObject: NotificationObserverObject {
    let observer: ViewNotificationObserver

    init(notificationName: NSNotification.Name, view: NSView, owner: AnyObject, observer: @escaping ViewNotificationObserver) {
        self.observer = observer
        super.init(notificationName: notificationName, object: view, owner: owner)
    }

    class func startObserving(
        notification notificationName: NSNotification.Name,
        ofView view: NSView,
        forOwner owner: AnyObject,
        observer: @escaping ViewNotificationObserver
    ) {
        let observerObject = ViewNotificationObserverObject(
            notificationName: notificationName,
            view: view,
            owner: owner,
            observer: observer
        )
        NotificationCenter.default.addObserver(
            observerObject,
            selector: #selector(handleViewNotification),
            name: notificationName,
            object: view
        )
        NotificationObserverObject.observerObjects.append(observerObject)
    }

    class func stopObserving(notification notificationName: NSNotification.Name, ofView view: NSView, forOwner owner: AnyObject) {
        NotificationObserverObject.stopObserving(notification: notificationName, of: view, forOwner: owner)
    }

    @objc func handleViewNotification(notification _: NSNotification) {
        if let _ = owner, let view = object as? NSView {
            observer(view)
        }
    }
}

public typealias WindowNotificationObserver = (_ window: NSWindow) -> Void

internal class WindowNotificationObserverObject: NotificationObserverObject {
    let observer: WindowNotificationObserver

    init(
        notificationName: NSNotification.Name,
        window: NSWindow,
        owner: AnyObject,
        observer: @escaping WindowNotificationObserver
    ) {
        self.observer = observer
        super.init(notificationName: notificationName, object: window, owner: owner)
    }

    class func startObserving(
        notification notificationName: NSNotification.Name,
        ofWindow window: NSWindow,
        forOwner owner: AnyObject,
        observer: @escaping WindowNotificationObserver
    ) {
        let observerObject = WindowNotificationObserverObject(
            notificationName: notificationName,
            window: window,
            owner: owner,
            observer: observer
        )
        NotificationCenter.default.addObserver(
            observerObject,
            selector: #selector(handleWindowNotification),
            name: notificationName,
            object: window
        )
        NotificationObserverObject.observerObjects.append(observerObject)
    }

    class func stopObserving(
        notification notificationName: NSNotification.Name,
        ofWindow window: NSWindow,
        forOwner owner: AnyObject
    ) {
        NotificationObserverObject.stopObserving(notification: notificationName, of: window, forOwner: owner)
    }

    @objc func handleWindowNotification(notification _: NSNotification) {
        if let _ = owner, let window = object as? NSWindow {
            observer(window)
        }
    }
}
