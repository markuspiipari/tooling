///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

// MARK: Universal type identifier helpers

public struct UTI {
    public static let genericData = UTI(identifier: kUTTypeData as String)
    public static let folder = UTI(identifier: kUTTypeFolder as String)
    public static let volume = UTI(identifier: kUTTypeVolume as String)
    public static let mountPoint = UTI(identifier: kUTTypeMountPoint as String)

    public static let image = UTI(identifier: kUTTypeImage as String)
    public static let jpegImage = UTI(identifier: kUTTypeJPEG as String)
    public static let tiffImage = UTI(identifier: kUTTypeTIFF as String)
    public static let pngImage = UTI(identifier: kUTTypePNG as String)

    // Why HEIC rather than HEIF? HEIC is a HEIF file whose main image was encoded using
    // the HEVC codec. This is the only format Apple support for writing out HEIF images.
    // For more, see:
    //   https://developer.apple.com/videos/play/wwdc2017-511/?time=1579
    public static let heicImage = UTI(identifier: "public.heic")

    public static let fileURL = UTI(identifier: kUTTypeFileURL as String)

    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    public init?(pathExtension: String) {
        guard let uti = UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            pathExtension.lowercased() as CFString,
            nil
        ) else {
            return nil
        }
        self.identifier = String(uti.takeUnretainedValue())
    }

    public init?(url: URL) {
        self.init(pathExtension: url.pathExtension.lowercased())
    }

    public init?(filename: String) {
        guard let url = URL(string: filename) else {
            return nil
        }
        self.init(url: url)
    }

    public var preferredPathExtension: String? {
        guard let ext = UTTypeCopyPreferredTagWithClass(identifier as CFString, kUTTagClassFilenameExtension) else {
            return nil
        }
        return String(ext.takeUnretainedValue())
    }

    public func preferredFilename(forFilename filename: String) -> String {
        UTI.preferredFilename(forFilename: filename, pathExtension: preferredPathExtension)
    }

    public static func preferredFilename(forFilename filename: String, pathExtension: String? = nil) -> String {
        if let url = URL(string: filename), let uti = UTI(url: url), let conversionUTI: UTI = {
            if let pathExtension = pathExtension {
                return UTI(pathExtension: pathExtension)
            } else {
                return uti
            }
        }() {
            return url.deletingPathExtension().appendingPathExtension(conversionUTI.preferredPathExtension ?? "")
                .lastPathComponent
        }

        if let pathExtension = pathExtension {
            return "\(filename.split(separator: ".").dropLast().joined()).\(pathExtension)"
        } else {
            return filename
        }
    }
}

extension UTI: Hashable {
    public static func == (lhs: UTI, rhs: UTI) -> Bool {
        lhs.identifier == rhs.identifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

extension UTI: CustomDebugStringConvertible {
    public var debugDescription: String {
        identifier
    }
}
