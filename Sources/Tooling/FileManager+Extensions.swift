///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public extension FileManager {
    // MARK: Conveniences

    /**

     Determine if a directory exists at a given URL. Note that if the URL points to a symlink
     to a directory, this method will return `true`.

     You should only use this method in scenarios where it is a better user experience to
     proactively inform the user that an action will fail due to an expected directory missing,
     than trying & presenting a standard error dialog.

     */
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
    
    /**
     Determine if a regular file exists at a given URL. Note that if the URL points to a symlink
     to a regular file, this method will return `true`.
     */
    func regularFileExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }
    
    // MARK: - Cache directories
    
    /// Return the Application Support subdirectory for this application's main bundle.
    func applicationSupportDirectoryURL() throws -> URL {
        guard let identifier = Bundle.main.bundleIdentifier ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String else {
            throw FileManagerExtensionError.bundleNotIdentifiable(Bundle.main)
        }
        return try self.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(identifier)
    }
    
    ///
    /// Return and create, if needed, the user-domain `Caches` subdirectory for a bundle.
    /// Defaults to attempting to determine the identifier of a main bundle, if applicable.
    /// - Throws: `FileManagerExtensionError.bundleNotIdentifiable` if all avenues to determine a bundle identifier are exhausted
    ///           withou success.
    func cachesDirectoryURL(identifiedBy bundleIdentifier: String? = nil) throws -> URL {
        guard let identifier = bundleIdentifier
                ?? Bundle.main.bundleIdentifier
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        else {
            throw FileManagerExtensionError.bundleNotIdentifiable(Bundle.main)
        }
        return try self.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(identifier)
    }
    
    /// Return the UTI for a path extension.
    class func fileType(forPathExtension pathExtension: String) -> String? {
        if let UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension.lowercased() as CFString, nil) {
            return String(UTI.takeUnretainedValue())
        }
        return nil
    }
    
    // MARK: - Temporary directories

    /// Initialize a unique temporary directory, of the form ~/Library/Caches/useCase/UUID
    func createUniqueTemporaryDirectory(named subdirectoryName: String = "") throws -> URL {
        let url = temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(subdirectoryName, isDirectory: true)
        try createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    // MARK: - Trashing and deleting

    func trashDirectoryURL(forURL url: URL) -> URL? {
        do {
            let trashURL = try self.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false)
            return trashURL
        } catch {
            Log.shared.error("Failed to determine trash directory URL appropriate for URL \(url)", error: error)
        }
        return nil
    }

    /** Move given URLs to trash and return their new URLs (in trash.) */
    func trashItems(atURLs URLs: [URL]) throws -> [URL: URL?] {
        var resultURLs = [URL: URL?]()

        for URL in URLs {
            var resultURL: NSURL?

            do {
                try trashItem(at: URL as URL, resultingItemURL: &resultURL)
            } catch {
                Log.shared.error("Failed to trash item at \(URL.absoluteURL.path)", error: error)
                throw error
            }

            if let u = resultURL, let s = u.absoluteString {
                resultURLs[URL] = Foundation.URL(string: s)
            }
        }
        return resultURLs
    }

    /// Delete entire directory hierarchy at a given URL (as the standard `removeItem(atURL:)` will not do it for non-empty
    /// directories.
    func deleteDirectoryContents(atURL url: URL) throws {
        require(url.isFileURL, "Cannot delete contents at non-file URL \(url)")

        Log.shared.dddebug("Delete directory contents at \(url.path):")

        // Traverse directory hierarchy, deleting regular files within, collecting subdirectory URLs to delete afterwards.
        // Encountering any error, stop and throw it.
        var subdirectoryURLs = [URL]()
        var traversalError: Swift.Error?

        let _: [URL] = try compactMapRegularFileURLs(
            at: url,
            enteringSubdirectories: true,
            includingPackages: true,
            includingHiddenFiles: true,
            prefetchingValuesFor: nil,
            filteringSubdirectoriesBy: {
                subdirectoryURLs.append($0)
                return true
            }, transform: {
                Log.shared.dddebug("→ Delete regular file at \($0.path)")
                try self.removeItem(at: $0)
                return nil
            },
            error: { _, error in
                traversalError = error
                return false // Stop enumeration
            }
        )

        if let error = traversalError {
            throw error
        }

        // Delete now-empty subdirectories, in reverse order such that nested directories get deleted before their ancestors.
        try subdirectoryURLs.lazy.reversed().forEach {
            Log.shared.dddebug("→ Delete subdirectory at \($0.path)")
            try removeItem(at: $0)
        }

        // Delete directory itself
        Log.shared.dddebug("→ Delete directory at \(url.path)")
        try removeItem(at: url)
    }

    // MARK: - Shenanigans

    /// Determine the URL of the current user's real (i.e. *not* under the sandbox container) home directory.
    func realHomeDirectoryURL() throws -> URL {
        // Adapted from https://stackoverflow.com/a/46789483
        let pw = getpwuid(getuid())
        guard let home = pw?.pointee.pw_dir else {
            throw FileManagerExtensionError.unknownCurrentUser
        }
        let path = string(withFileSystemRepresentation: home, length: Int(strlen(home)))
        return URL(fileURLWithPath: path)
    }

    /// Resolve the URL of one of the current user's real (i.e. *not* enclosed by the sandbox container) folders.
    func realUserDomainURL(for searchPath: FileManager.SearchPathDirectory) throws -> URL {
        let sandboxedHomeURL = homeDirectoryForCurrentUser
        let realHomeURL = try realHomeDirectoryURL()
        let userDomainURL = try url(for: searchPath, in: .userDomainMask, appropriateFor: nil, create: false)
        
        guard sandboxedHomeURL != realHomeURL,
           sandboxedHomeURL.isAncestorOf(url: userDomainURL),
           let relativePath = userDomainURL.pathRelativeTo(sandboxedHomeURL)
        else {
            return userDomainURL
        }
        
        return realHomeURL.appendingPathComponent(relativePath)
    }
    
    // MARK: - File & directory enumeration
    
    typealias URLFilter = (URL) -> Bool
    
    ///
    /// Walk a directory hierarchy, transforming all encountered regular file URLs into a result type.
    ///
    /// Subdirectories and regular file URLs can be prefiltered. Performance can be finetuned by prefetching URL resource values
    /// that the trannsform closure will look up for each regular file URL anyway.
    ///
    /// - parameters:
    ///    - baseDirectoryURL: Root directory to enumerate.
    ///    - deep: Whether to traverse subdirectories. Defaults to `true`.
    ///    - includePackages: Whether to examine file package contents. Defaults to `true`.
    ///    - includeHiddenFiles: Whether to include hidden regular files. Defaults to `true`.
    ///    - prefetchKeys: Array of `URLResourceKey`s to prefetch as part of directory hierarchy enumeration. This will markedly
    ///                    improve performance in use cases that examine thousands or more file URLs.
    ///    - subdirectoryFilter: Filter for determining whether a particular subdirectory should be entered.
    ///    - regularFileFilter: Filter for determining whether a particular regular file URL is of interest.
    ///    - transform: Closure for doing the actual per-regular-file-URL work. Note that whereas the subdirectory and regular
    ///                 file URL filters are executed synchronously as part of directory hierarchy enumeration, this one is
    ///                 marked `@escaping`, to parallelize the potentially expensive work performed for each regular file URL.
    ///    - errorHandler: Optional error handler that should return `true` to ignore an error and continue enumerating files,
    ///                    `false` to stop the file mapping & throw the error. If not provided, default behaviour is to stop at
    ///                    any error, as if an error handler returned `false` (which is the opposite of how
    ///                    `FileManager.enumerator()` works.)
    ///
    func compactMapRegularFileURLs<T>(
        at baseDirectoryURL: URL,
        enteringSubdirectories deep: Bool = true,
        includingPackages includePackages: Bool = true,
        includingHiddenFiles includeHiddenFiles: Bool = true,
        prefetchingValuesFor prefetchKeys: [URLResourceKey]? = nil,
        filteringSubdirectoriesBy subdirectoryFilter: URLFilter? = nil,
        filteringRegularFilesBy regularFileFilter: URLFilter? = nil,
        transform: @escaping (URL) throws -> T?,
        error errorHandler: ((URL, Swift.Error) -> Bool)? = nil
    ) throws -> [T] {
        var options: FileManager.DirectoryEnumerationOptions = []

        if !deep {
            options.insert(.skipsSubdirectoryDescendants)
        }
        if !includePackages {
            options.insert(.skipsPackageDescendants)
        }
        if !includeHiddenFiles {
            options.insert(.skipsHiddenFiles)
        }

        var resourceKeySet = Set<URLResourceKey>()
        resourceKeySet.insert(contentsOf: [.isDirectoryKey, .isRegularFileKey])
        if let keys = prefetchKeys {
            resourceKeySet.insert(contentsOf: keys)
        }

        guard let enumerator = enumerator(
            at: baseDirectoryURL,
            includingPropertiesForKeys: Array(resourceKeySet),
            options: options,
            errorHandler: { url, error in
                if let handler = errorHandler {
                    return handler(url, error)
                }
                return false
            }
        ) else {
            throw FileManagerExtensionError.locationNotEnumerable(url: baseDirectoryURL)
        }

        let applicableURLs: [URL] = try enumerator.compactMap {
            guard let url = $0 as? URL else {
                return nil
            }

            let resourceValues = try url.resourceValues(forKeys: resourceKeySet)

            guard
                let isDirectory = resourceValues.isDirectory,
                let isRegularFile = resourceValues.isRegularFile,
                isDirectory || isRegularFile
            else {
                return nil
            }

            if isDirectory, let filter = subdirectoryFilter, !filter(url) {
                enumerator.skipDescendants()
            } else if isRegularFile {
                if let filter = regularFileFilter {
                    return filter(url) ? url : nil
                }
                return url
            }

            return nil
        }

        let result: [T] = try applicableURLs.parallelCompactMap {
            try transform($0)
        }

        return result
    }

    // MARK: - Directory size on disk

    /// Calculate the allocated size of a directory's regular file contents.
    func totalAllocatedSizeOfRegularFilesContained(
        at directoryURL: URL,
        filteringRegularFileURLsBy filter: URLFilter?
    ) throws -> Int {
        var enumerationError: Swift.Error?

        guard let enumerator = self.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
                options: [],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }) else {
            throw FileManagerExtensionError.locationNotEnumerable(url: directoryURL)
        }

        return try enumerator.reduce(0) { accumulatedSize, item in
            guard let url = item as? URL else {
                preconditionFailure()
            }

            if let error = enumerationError {
                throw FileManagerExtensionError.failedToEnumerateDirectoryItem(url: url, underlyingError: error)
            }

            let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile ?? false else {
                return accumulatedSize
            }

            if let filter = filter, !filter(url) {
                return accumulatedSize
            }

            let fileSize = try url.regularFileAllocatedSize()
            return accumulatedSize + fileSize
        }
    }
}

private extension URL {
    func regularFileAllocatedSize() throws -> Int {
        let resourceValues = try self
            .resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey])

        guard resourceValues.isRegularFile ?? false else {
            return 0
        }

        return resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0
    }
}

// MARK: - Errors

public enum FileManagerExtensionError: LocalizedError, CustomNSError {
    case bundleNotIdentifiable(Bundle)
    case locationNotEnumerable(url: URL)
    case failedToEnumerateDirectoryItem(url: URL, underlyingError: Swift.Error)
    case locationVolumeNotIdentifiable(url: URL)
    case unknownCurrentUser

    public var localizedDescription: String {
        switch self {
        case .bundleNotIdentifiable(let bundle):
            return "Bundle at ${url} is not identifiable".localized.substituting("url", with: bundle.bundleURL.path)
        case let .locationNotEnumerable(url):
            return NSLocalizedString("Cannot list contents of source location: ${url}", comment: "")
                .substituting("url", with: url.absoluteString)
        case let .failedToEnumerateDirectoryItem(url, underlyingError):
            return NSLocalizedString("Cannot read ${url}: ${error}", comment: "")
                .substituting(["url": url.absoluteString, "error": underlyingError.localizedDescription])
        case let .locationVolumeNotIdentifiable(url):
            return NSLocalizedString("Source location is not persistently identifiable: ${url}", comment: "")
                .substituting("url", with: url.absoluteString)
        case .unknownCurrentUser:
            return "Failed to determine current user".localized
        }
    }

    public var errorCode: Int {
        switch self {
        case .bundleNotIdentifiable:
            return 100
        case .locationNotEnumerable:
            return 200
        case .failedToEnumerateDirectoryItem:
            return 201
        case .locationVolumeNotIdentifiable:
            return 300
        case .unknownCurrentUser:
            return 400
        }
    }
}
