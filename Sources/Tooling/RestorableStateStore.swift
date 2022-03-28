///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public typealias SequentialStoreItem = Codable & Equatable

public protocol SequentialStoreObserver: AnyObject {
    func didStoreItem(notification: Notification)
    func didUpdateItem(notification: Notification)
    func didRemoveItem(notification: Notification)
}

public struct SequentialStoreNotifications {
    public static let didStoreItem = Notification.Name(rawValue: "didStoreItem")
    public static let didUpdateItem = Notification.Name(rawValue: "didUpdateItem")
    public static let didRemoveItem = Notification.Name(rawValue: "didRemoveItem")
}

public enum RestorableStateStoreAccessMode {
    case readWrite
    case readOnly
    
    fileprivate func checkCanWrite() throws {
        switch self {
        case .readWrite:
            break
        case .readOnly:
            throw RestorableStateStoreError.stateStoreIsReadOnly
        }
    }
}

public class SequentialStore<T: SequentialStoreItem> {
    /// Location of backing storage file for this sequential store.
    public let url: URL
    public let accessMode: RestorableStateStoreAccessMode

    private var items: AtomicResource<[T]>

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    public init(
        url: URL,
        accessMode: RestorableStateStoreAccessMode = .readWrite,
        decoderUserInfo: [CodingUserInfoKey: Any]? = nil,
        fileManager: FileManager? = nil
    ) throws {
        require(url.isFileURL, "Backing storage location for SequentialStore must be a file URL")

        self.url = url
        self.accessMode = accessMode
        self.fileManager = fileManager ?? FileManager.default
        
        if let t = decoderUserInfo {
            for k in t.keys {
                decoder.userInfo[k] = t[k]
            }
        }

        let data: Data
        let items: [T]
        do {
            data = try Data(contentsOf: url)
            items = try decoder.decode([T].self, from: data)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            /// This specific error is not a problem: it just means that no items have been previously persisted to disk.
            /// The backing storage file will be created in the future by the first `store()` call, and here we will
            /// merely initialize an empty bookmark data dictionary.
            items = [T]()
            Log.shared.dddebug("Sequential store file does not exist yet at \(url.path). Will create on first save")
        } catch {
            throw error
        }

        self.items = AtomicResource<[T]>(items)
    }

    public var count: Int {
        items.read { $0.count }
    }

    /// Return a copy of all items in this sequential store.
    public var allItems: [T] {
        items.read { [T]($0) }
    }

    public func filter(_ test: (T) throws -> Bool) rethrows -> [T] {
        let filtered = try items.read {
            try $0.filter(test)
        }
        return filtered
    }

    public func item(at i: Int) -> T {
        items.read {
            return $0[i]
        }
    }
    
    @discardableResult public func remove(_ item: T) throws -> Bool {
        try accessMode.checkCanWrite()
        
        return try items.modify {
            guard let i = $0.firstIndex(of: item) else {
                return false
            }
            $0.remove(at: i)
            try write(items: $0)
            observations.postNotification(Notification(store: self, removedItem: item))
            return true
        }
    }

    private func write(items: [T]) throws {
        try accessMode.checkCanWrite()
        
        // Save store file:
        // Ensure backing storage directory exists
        let directoryURL = url.deletingLastPathComponent()
        if !fileManager.directoryExists(at: directoryURL) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            Log.shared.dddebug("Created backing storage directory for sequential store at \(directoryURL.path)")
        }

        // Encode & write out
        let data = try encoder.encode(items)
        try data.write(to: url)

        Log.shared.dddebug("Succesfully wrote sequential store items out to \(url.path)")
    }

    public func store(_ item: T) throws {
        try accessMode.checkCanWrite()
        
        try items.modify {
            if let i = $0.firstIndex(of: item) {
                $0.remove(at: i)
                $0.insert(item, at: i)
            } else {
                $0.append(item)
            }

            try write(items: $0)

            observations.postNotification(Notification(store: self, storedItem: item))
        }
    }

    public func update(_ item: T, modifier: (T) -> T) throws -> T? {
        try accessMode.checkCanWrite()
        
        return try items.modify {
            guard let i = $0.firstIndex(of: item) else {
                return nil
            }

            $0.remove(at: i)
            let updatedItem = modifier($0[i])
            $0.insert(updatedItem, at: i)
            try write(items: $0)

            observations.postNotification(Notification(store: self, updatedItem: item))

            return updatedItem
        }
    }

    // MARK: - Notifications
    
    private lazy var observations = Observations(observee: self, notificationCenter: NotificationCenter.default)
    
    public func addObserver(_ observer: SequentialStoreObserver) {
        weak var weakObserver = observer
        
        observations.addObserver(observer, notificationName: SequentialStoreNotifications.didStoreItem) {
            weakObserver?.didStoreItem(notification: $0)
        }
        observations.addObserver(observer, notificationName: SequentialStoreNotifications.didUpdateItem) {
            weakObserver?.didUpdateItem(notification: $0)
        }
    }
    
    public func removeObserver(_ observer: SequentialStoreObserver) {
        observations.removeObserver(observer)
    }
    
    public func removeObservers() {
        observations.removeAll()
    }
}

public extension Notification {
    init<T: SequentialStoreItem>(store: SequentialStore<T>, storedItem item: T) {
        self.init(name: SequentialStoreNotifications.didStoreItem, object: store, userInfo: ["storedItem": item])
    }

    init<T: SequentialStoreItem>(store: SequentialStore<T>, updatedItem item: T) {
        self.init(name: SequentialStoreNotifications.didUpdateItem, object: store, userInfo: ["updatedItem": item])
    }

    init<T: SequentialStoreItem>(store: SequentialStore<T>, removedItem item: T) {
        self.init(name: SequentialStoreNotifications.didRemoveItem, object: store, userInfo: ["removedItem": item])
    }

    func storedItem<T: SequentialStoreItem>() -> T? {
        userInfo?["storedItem"] as? T
    }

    func updatedItem<T: SequentialStoreItem>() -> T? {
        userInfo?["updatedItem"] as? T
    }

    func removedItem<T: SequentialStoreItem>() -> T? {
        userInfo?["removedItem"] as? T
    }
}

// MARK: -

public typealias KeyedStoreKey = Hashable & Codable

/// **Note:** this implementation isn't as complete yet as `SequentialStore`.
public class KeyedStore<K: KeyedStoreKey, T: Codable> {
    /// Location of backing storage file for this keyed state store.
    public let url: URL
    public let accessMode: RestorableStateStoreAccessMode

    private var items: AtomicResource<[K: T]>

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        url: URL,
        accessMode: RestorableStateStoreAccessMode = .readWrite,
        fileManager: FileManager? = nil
    ) throws {
        require(url.isFileURL, "Backing storage for KeyedStore must be a file URL")

        self.url = url
        self.accessMode = accessMode
        self.fileManager = fileManager ?? FileManager.default

        let data: Data
        let items: [K: T]
        do {
            data = try Data(contentsOf: url)
            items = try decoder.decode([K: T].self, from: data)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            /// This specific error is not a problem: it just means that no items have been previously persisted to disk.
            /// The backing storage file will be created in the future by the first `store()` call, and here we will
            /// merely initialize an empty bookmark data dictionary.
            items = [K: T]()
            Log.shared.dddebug("Keyed store file does not exist yet at \(url.path). Will create on first save")
        } catch {
            throw error
        }

        self.items = AtomicResource<[K: T]>(items)
    }

    public func store(_ item: T, forKey key: K) throws {
        try accessMode.checkCanWrite()
        
        try items.modify {
            $0[key] = item

            // Save store file:
            // Ensure backing storage directory exists
            let directoryURL = url.deletingLastPathComponent()
            if !fileManager.directoryExists(at: directoryURL) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                Log.shared.dddebug("Created backing storage directory for keyed store at \(directoryURL.path)")
            }

            // Encode & write out
            let data = try encoder.encode($0)
            try data.write(to: url)

            Log.shared.dddebug("Succesfully wrote keyed store items out to \(url.path)")
        }
    }

    public func restoreItem(forKey key: K) throws -> T? {
        items.read {
            return $0[key]
        }
    }
}

// MARK: - Errors

public enum RestorableStateStoreError: LocalizedError {
    case stateStoreIsReadOnly
    
    public var errorDescription: String? {
        switch self {
        case .stateStoreIsReadOnly:
            return "Restorable state store is read only"
        }
    }
}
