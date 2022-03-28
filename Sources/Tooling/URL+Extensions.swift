///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public typealias URLFilter = (URL) -> Bool

// MARK: - URL conversions

public protocol URLConvertible {
    func asURL() throws -> URL
}

extension URL: URLConvertible {
    public func asURL() throws -> URL {
        self
    }
}

extension String: URLConvertible {
    public func asURL() throws -> URL {
        guard let url = URL(string: self) else {
            throw URLError.invalidURLString(self)
        }
        return url
    }
}

public protocol FileURLConvertible {
    func asFileURL() -> URL
}

extension URL: FileURLConvertible {
    public func asFileURL() -> URL {
        guard self.scheme == "file" else {
            return URL(fileURLWithPath: self.path)
        }
        return self
    }
}

extension String: FileURLConvertible {
    public func asFileURL() -> URL {
        return URL(fileURLWithPath: self)
    }
}

public enum URLError: LocalizedError {
    case invalidURLString(_ value: String)
    case notAFileURL(_ value: URL)
    
    public var errorDescription: String? {
        switch self {
        case let .invalidURLString(value):
            return "Invalid URL string '\(value)'"
        case let .notAFileURL(value):
            return "Not a file URL: \(value.absoluteString)"
        }
    }
}

// MARK: - Directories & relative paths

public extension URL {
    var displayValue: String {
        if isFileURL {
            return path
        } else {
            return absoluteString
        }
    }
    
    var normalizedPath: String {
        standardized.path.precomposedStringWithCanonicalMapping
    }
    
    /// Return a standardized, symlink-resolved copy of this URL.
    var fullyResolved: URL {
        standardized.resolvingSymlinksInPath().standardized
    }

    func isAncestorOf(url: URL) -> Bool {
        scheme == url.scheme
        && host == url.host
        && url.normalizedPath.hasPrefix(self.normalizedPath)
    }

    /// If an URL is an ancestor of this URL, replace the ancestor portion with a new ancestor URL.
    /// Otherwise, return this URL as-is.
    func rewritingAncestorURL(from oldAncestorURL: URL, to newAncestorURL: URL) -> URL {
        if oldAncestorURL.isAncestorOf(url: self), let movedURL = self.moved(from: oldAncestorURL, to: newAncestorURL) {
            return movedURL
        }
        return self
    }

    func trimmingTrailingPathSeparator() -> URL {
        guard hasDirectoryPath else {
            return self
        }
        let lpc = lastPathComponent
        return deletingLastPathComponent().appendingPathComponent(lpc, isDirectory: false)
    }

    /// If this URL is a descendant of the given ancestor URL, return the relative path; `nil` if not.
    func pathRelativeTo(_ ancestorURL: URL) -> String? {
        path.pathRelativeTo(ancestorURL.path)
    }

    func moved(from oldAncestorURL: URL, to newAncestorURL: URL) -> URL? {
        guard let relativePath = pathRelativeTo(oldAncestorURL) else {
            return nil
        }
        // TODO: This could be a single appendPathComponent() call. Just not changing it right now, #389 being massive already.
        let relativeComponents = relativePath.split(separator: "/")
        var newURL = newAncestorURL
        relativeComponents.forEach {
            newURL.appendPathComponent(String($0))
        }
        return newURL
    }

    func updating(query: [String: CustomStringConvertible]) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
            return nil
        }
        components.queryItems = query.map { URLQueryItem(name: $0, value: "\($1)") }
        return components.url
    }
}

// MARK: - Extended file attributes

// Adapted from: https://stackoverflow.com/a/38343753

public extension URL {
    func readExtendedFileAttributeData(for attributeName: String) throws -> Data {
        try withUnsafeFileSystemRepresentation { fileSystemPath -> Data in
            // Determine attribute size
            let length = getxattr(fileSystemPath, attributeName, nil, 0, 0, 0)
            guard length >= 0 else {
                throw URL.posixError(errno)
            }

            // Retrieve attribute data
            var data = Data(count: length)
            let result = data.withUnsafeMutableBytes { [count = data.count] in
                getxattr(fileSystemPath, attributeName, $0.baseAddress, count, 0, 0)
            }
            guard result >= 0 else {
                throw URL.posixError(errno)
            }
            return data
        }
    }

    func writeExtendedFileAttributeData(_ data: Data, for attributeName: String) throws {
        try withUnsafeFileSystemRepresentation { fileSystemPath in
            let result = data.withUnsafeBytes {
                setxattr(fileSystemPath, attributeName, $0.baseAddress, data.count, 0, 0)
            }
            guard result >= 0 else {
                throw URL.posixError(errno)
            }
        }
    }

    func removeExtendedFileAttribute(named attributeName: String) throws {
        try withUnsafeFileSystemRepresentation { fileSystemPath in
            let result = removexattr(fileSystemPath, attributeName, 0)
            guard result >= 0 else {
                throw URL.posixError(errno)
            }
        }
    }

    func extendedFileAttributeNames() throws -> [String] {
        try withUnsafeFileSystemRepresentation { fileSystemPath -> [String] in
            let length = listxattr(fileSystemPath, nil, 0, 0)
            guard length >= 0 else {
                throw URL.posixError(errno)
            }

            // Create buffer with required size
            var namebuf = [CChar](repeating: 0, count: length)

            // Retrieve attribute list
            let result = listxattr(fileSystemPath, &namebuf, namebuf.count, 0)
            guard result >= 0 else {
                throw URL.posixError(errno)
            }

            // Extract attribute names
            let names = namebuf.split(separator: 0).compactMap {
                $0.withUnsafeBufferPointer {
                    $0.withMemoryRebound(to: UInt8.self) {
                        String(bytes: $0, encoding: .utf8)
                    }
                }
            }
            return names
        }
    }

    /** Helper function to create an NSError from a Unix errno. */
    private static func posixError(_ err: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(err))])
    }
}

// MARK: Volume information

public struct VolumeIdentification {
    public let url: URL
    public let uuid: UUID?
    public let name: String?
    /// If the volume is a network share, the URL for remounting in the future.
    public let remountURL: URL?
    public let isLocal: Bool
}

public extension URL {
    func volumeIdentification() throws -> VolumeIdentification {
        guard isFileURL else {
            throw FileManagerExtensionError.locationVolumeNotIdentifiable(url: self)
        }

        let values = try resourceValues(
            forKeys: Set<URLResourceKey>([
                URLResourceKey.volumeUUIDStringKey,
                URLResourceKey.volumeURLKey,
                URLResourceKey.volumeNameKey,
                URLResourceKey.volumeURLForRemountingKey,
                URLResourceKey.volumeIsLocalKey
            ])
        )

        guard let volumeURL = values.volume, let isLocal = values.volumeIsLocal else {
            throw FileManagerExtensionError.locationVolumeNotIdentifiable(url: self)
        }

        let uuidString = values.volumeUUIDString
        let remountURL = values.volumeURLForRemounting
        let name = values.volumeName

        if let t = uuidString, let uuid = UUID(uuidString: t) {
            return VolumeIdentification(url: volumeURL, uuid: uuid, name: name, remountURL: remountURL, isLocal: isLocal)
        } else if let url = remountURL {
            return VolumeIdentification(url: volumeURL, uuid: nil, name: name, remountURL: url, isLocal: isLocal)
        }

        throw FileManagerExtensionError.locationVolumeNotIdentifiable(url: self)
    }
}
