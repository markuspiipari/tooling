///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation


/// Represents an individual change notification received by `DirectoryChangeObserver` via the file presenter API.
public struct DirectoryChange {
    public enum Kind {
        case change
        case removal
    }

    public let kind: Kind
    public let url: URL
    public let previousURL: URL?
    public let isSubdirectory: Bool

    public init(kind: Kind, url: URL, previousURL: URL? = nil, isSubdirectory: Bool) {
        self.kind = kind
        self.url = url
        self.previousURL = previousURL
        self.isSubdirectory = isSubdirectory
    }
}

/// Groups URLs of individual `DirectoryChange` instances, gathered over an observation period, into a combined set,
/// to be processed by a `DirectoryChangeObserverDelegate` at once.
public struct DirectoryChangeSet: CustomDebugStringConvertible {
    public let observedURL: URL
    public let changedFileURLs: [URL]
    public let changedSubdirectoryURLs: [URL]
    public let removedFileURLs: [URL]
    public let removedSubdirectoryURLs: [URL]

    public init(observedURL: URL, changes: [DirectoryChange]) {
        self.observedURL = observedURL

        // We filter out multiple changes to the same URLs via the Array(Set()) calls.
        // This obviously mixes up the order of the URLs.
        self.changedFileURLs = Array(Set(changes.compactMap {
            ($0.kind == .change && !$0.isSubdirectory) ? $0.url : nil
        }))
        self.changedSubdirectoryURLs = Array(Set(changes.compactMap {
            ($0.kind == .change && $0.isSubdirectory) ? $0.url : nil
        }))
        self.removedFileURLs = Array(Set(changes.compactMap {
            ($0.kind == .removal && !$0.isSubdirectory) ? $0.url : nil
        }))
        self.removedSubdirectoryURLs = Array(Set(changes.compactMap {
            ($0.kind == .removal && $0.isSubdirectory) ? $0.url : nil
        }))
    }

    public var didSubdirectoriesChange: Bool {
        changedSubdirectoryURLs.isNonEmpty || removedSubdirectoryURLs.isNonEmpty
    }

    public var debugDescription: String {
        """

        Changes under \(observedURL.path):

               Changed files: \(changedFileURLs.map { $0.pathRelativeTo(observedURL) ?? "??" }.joined(separator: ", "))
          Changed subfolders: \(changedSubdirectoryURLs.map { $0.pathRelativeTo(observedURL) ?? "??" }.joined(separator: ", "))
               Deleted files: \(removedFileURLs.map { $0.pathRelativeTo(observedURL) ?? "??" }.joined(separator: ", "))
          Deleted subfolders: \(removedSubdirectoryURLs.map { $0.pathRelativeTo(observedURL) ?? "??" }.joined(separator: ", "))

        """
    }
}

public typealias DirectoryChangeSetHandler = (DirectoryChangeSet?) -> Void
public typealias DirectoryChangeSetProcessingCompletionHandler = () -> Void
public typealias DirectoryChangeSetProcessingErrorHandler = (Error) -> Void

/// Delegate protocol for the owner of a `DirectoryChangeObserver` to implement.
public protocol DirectoryChangeObserverDelegate: AnyObject {
    /**

     Attributes of the observed directory have changed.

     Note that this method will be called in the specific case where the directory was renamed
     such that its name didn't change in case-insensitive terms ("Holiday photos" → "Holiday Photos"),
     so the rename does not warrant a `directoryDidMove()` call, but refreshing any UI that displays
     the directory name would still be appropriate.

     */
    func directoryAttributesDidChange()

    /**

     Observed directory was renamed or moved to a new location. The directory change observer will have
     stopped observing changes before calling this method.

     Note that it will be this method (rather than `directoryWillBeDeleted()`) that gets called if the
     user moves the observed directory into Trash in Finder.

     Also see documentation for `directoryAttributesDidChange()` for the special case where a rename
     results in a case-insensitively insignificant name change.

     */
    func directoryDidMove(to newURL: URL)

    /**
     Observed directory is about to be deleted. The directory change observer will have
     stopped observing changes before calling this method.
     */
    func directoryWillBeDeleted()

    /**

     Whether or not the delegate is interested in a particular regular file URL. For efficiency,
     the implementation is expected to only consider the properties of the given URL (such as its path,
     or the path extension) and not, for example, read its contents or file system attributes.

     @param url         Current URL of file
     @param previousURL In the case of, for example, a move or a removal, the previous known URL
                        of the file

     */
    func shouldProcessFile(at url: URL, previousURL: URL?) -> Bool

    /**
     Whether the delegate is interested in a particular subdirectory URL. See `shouldProcessFile()`
     above for more.
     */
    func shouldProcessSubdirectory(at url: URL, previousURL: URL?) -> Bool

    /**

     Process a set of changes that have occurred within the observed directory hierarchy, over
     the last `timerInterval`.

     @param changes    Set of changes to process
     @param completion Completion handler to call when processing is completed succesfully, and
                       the delegate is ready for the next observation & processing period.
     */
    func processChanges(_ changes: DirectoryChangeSet,
                        completion: @escaping DirectoryChangeSetProcessingCompletionHandler,
                        error errorHandler: @escaping DirectoryChangeSetProcessingErrorHandler)
}

/// File presenter implementation that observes changes within the hierarchy of a root directory URL, and periodically asks the
/// interested owner/delegate to process them.
public final class DirectoryChangeObserver: NSObject, NSFilePresenter {
    public weak var delegate: DirectoryChangeObserverDelegate?
    public private(set) var directoryURL: URL
    public let timerInterval: TimeInterval

    private var changes: [DirectoryChange] = []
    private var started: Bool = false
    private var processing: Bool = false

    fileprivate lazy var filesystemChangeQueue: OperationQueue = {
        OperationQueue.serialOperationQueue(named: "DirectoryChangeObserver.filesystemChangeQueue")
    }()

    // MARK: Initialization

    public init(directoryURL: URL, timerInterval: TimeInterval) {
        self.directoryURL = directoryURL
        precondition(timerInterval >= 0.5)
        self.timerInterval = timerInterval
    }

    deinit {
        stop()
    }

    // MARK: - Change observation toggling

    public func start() {
        if started {
            return
        }
        started = true

        NSFileCoordinator.addFilePresenter(self)
        startProcessingTimer()
    }

    public func stop() {
        if !started {
            return
        }
        started = false

        stopProcessingTimer()
        NSFileCoordinator.removeFilePresenter(self)
    }

    // MARK: — File presenter implementation

    public var presentedItemURL: URL? {
        directoryURL
    }

    public var presentedItemOperationQueue: OperationQueue {
        filesystemChangeQueue
    }

    // MARK: - Changes to directory itself

    public func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        Log.debug("Directory at '\(directoryURL.path)' is about to be deleted")
        delegate?.directoryWillBeDeleted()
        completionHandler(nil)
    }

    public func presentedItemDidMove(to newURL: URL) {
        Log.debug("Directory at '\(directoryURL.path)' moved to new location '\(newURL)'")
        stop()
        directoryURL = newURL
        delegate?.directoryDidMove(to: newURL)
    }

    public func presentedItemDidChange() {
        Log.debug("Directory at '\(directoryURL.path)' changed; attributes only?")
        delegate?.directoryAttributesDidChange()
    }

    // MARK: - Changes to contained hierarchy

    public func presentedSubitemDidAppear(at url: URL) {
        // So far we've never actually seen this method getting invoked. Instead, presentedSubitemDidChange()
        // appears to get the call when a new file is added under directoryURL. Anyhow, just in case, we make
        // the identical recordSubitemChange() call here anyhow.
        recordSubitemChange(at: url, previousURL: nil)
    }

    public func presentedSubitemDidChange(at url: URL) {
        recordSubitemChange(at: url, previousURL: nil)
    }

    public func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        recordSubitemChange(at: newURL, previousURL: oldURL)
    }

    public func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        recordSubitemChange(at: url, previousURL: nil)
        completionHandler(nil)
    }

    func recordSubitemChange(at url: URL, previousURL: URL?) {
        var isDirectoryObjC: ObjCBool = false
        let subitemExists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectoryObjC)
        let isSubdirectory: Bool = {
            if subitemExists {
                return isDirectoryObjC.boolValue
            }
            do {
                let values = try url.resourceValues(forKeys: Set<URLResourceKey>([.isDirectoryKey]))
                return values.isDirectory ?? url.hasDirectoryPath
            } catch {
                return url.hasDirectoryPath
            }
        }()

        if let delegate = delegate {
            if isSubdirectory, !delegate.shouldProcessSubdirectory(at: url, previousURL: previousURL) {
                return // Delegate not interested in subdirectory
            }
            if !isSubdirectory, !delegate.shouldProcessFile(at: url, previousURL: previousURL) {
                return // Delegate not interested in regular file
            }
        }

        let urlIsInHierarchy = directoryURL.isAncestorOf(url: url)

        if urlIsInHierarchy {
            if subitemExists {
                // Current URL exists, and is contained by observed directory — record as a change
                changes.append(DirectoryChange(kind: .change, url: url, previousURL: previousURL, isSubdirectory: isSubdirectory))
            } else {
                // Current URL does not exist, or isn't observable by us — record as a removal
                changes.append(DirectoryChange(kind: .removal, url: url, isSubdirectory: isSubdirectory))
            }
        } else {
            if let previousURL = previousURL {
                let previousURLWasInHierarchy = directoryURL.isAncestorOf(url: previousURL)
                if previousURLWasInHierarchy {
                    // Previous URL was contained by observed directory; current URL is not — record as a removal
                    changes.append(DirectoryChange(kind: .removal, url: previousURL, isSubdirectory: isSubdirectory))
                }
            }
        }
    }

    // MARK: Batch processing

    private func processPendingChanges() {
        if processing {
            return
        }
        processing = true

        filesystemChangeQueue.addOperation { [weak self] in
            guard let observer = self else {
                self?.processChangeSet(nil)
                return
            }
            if observer.changes.count > 0 {
                let changes = observer.changes
                observer.changes = []
                let changeSet = DirectoryChangeSet(observedURL: observer.directoryURL, changes: changes)
                self?.processChangeSet(changeSet)
            } else {
                self?.processChangeSet(nil)
            }
        }
    }

    private func processChangeSet(_ changeSet: DirectoryChangeSet?) {
        // There are no changes to process this time, or no delegate to *do* the processing
        guard let changes = changeSet, let delegate = self.delegate else {
            processing = false
            return
        }

        // Prompt delegate to process changes
        delegate.processChanges(changes, completion: {
            self.processing = false
        }, error: {
            self.processing = false
            Log.error("Failed to process filesystem changes at \(self.directoryURL.path)", error: $0)
        })
    }

    private lazy var timer: RepeatingTimer = {
        RepeatingTimer(interval: timerInterval) { [weak self] in
            self?.processPendingChanges()
        }
    }()

    private func startProcessingTimer() {
        timer.start()
    }

    private func stopProcessingTimer() {
        timer.stop()
    }
}
