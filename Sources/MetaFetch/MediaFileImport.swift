import Foundation

struct ValidatedMediaFile: Sendable {
    let url: URL
    let identity: MediaFileIdentity?
}

struct ExpandedImportURLs: Sendable {
    let urls: [URL]
    let rejectedCount: Int
    let scannedFolderCount: Int
}

enum MediaImportURLExpander {
    static func expandedMediaFileURLs(from urls: [URL]) -> ExpandedImportURLs {
        var expandedURLs: [URL] = []
        var rejectedCount = 0
        var scannedFolderCount = 0

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard standardizedURL.isFileURL else {
                rejectedCount += 1
                continue
            }

            if isDirectory(standardizedURL) {
                scannedFolderCount += 1
                expandedURLs.append(contentsOf: mp4Files(in: standardizedURL))
            } else if standardizedURL.pathExtension.caseInsensitiveCompare("mp4") == .orderedSame {
                expandedURLs.append(standardizedURL)
            } else {
                rejectedCount += 1
            }
        }

        let uniqueSortedURLs = Array(Set(expandedURLs.map(\.standardizedFileURL)))
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return ExpandedImportURLs(
            urls: uniqueSortedURLs,
            rejectedCount: rejectedCount,
            scannedFolderCount: scannedFolderCount
        )
    }

    private static func isDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isReadableKey,
            .isSymbolicLinkKey,
        ]) else {
            return false
        }
        return values.isDirectory == true &&
            values.isReadable == true &&
            values.isSymbolicLink != true
    }

    private static func mp4Files(in folderURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isReadableKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ]), values.isDirectory == true {
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard fileURL.pathExtension.caseInsensitiveCompare("mp4") == .orderedSame,
                  MediaFileImportValidator.validatedImport(fileURL) != nil else {
                continue
            }
            files.append(fileURL.standardizedFileURL)
        }
        return files
    }
}

struct MediaFileIdentity: Equatable, Sendable {
    let systemNumber: UInt64
    let fileNumber: UInt64
}

enum MediaFileImportValidator {
    enum ValidationError: LocalizedError {
        case unsafeFile
        case fileChanged

        var errorDescription: String? {
            switch self {
            case .unsafeFile:
                return "MetaFetch stopped before saving because the file is no longer a local, writable `.mp4` file."
            case .fileChanged:
                return "MetaFetch stopped before saving because this file changed after it was imported. Remove it and add it again before tagging."
            }
        }
    }

    static func validatedImportURL(_ url: URL) -> URL? {
        validatedImport(url)?.url
    }

    static func validatedImport(_ url: URL) -> ValidatedMediaFile? {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.isFileURL,
              standardizedURL.pathExtension.caseInsensitiveCompare("mp4") == .orderedSame,
              let resourceValues = try? standardizedURL.resourceValues(forKeys: [
                .isReadableKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isWritableKey,
              ]),
              resourceValues.isRegularFile == true,
              resourceValues.isReadable == true,
              resourceValues.isWritable == true,
              resourceValues.isSymbolicLink != true else {
            return nil
        }

        return ValidatedMediaFile(
            url: standardizedURL,
            identity: identity(for: standardizedURL)
        )
    }

    static func validateStillSafeToWrite(
        _ url: URL,
        expectedIdentity: MediaFileIdentity?
    ) throws {
        guard let validatedFile = validatedImport(url) else {
            throw ValidationError.unsafeFile
        }

        if let expectedIdentity,
           let currentIdentity = validatedFile.identity,
           currentIdentity != expectedIdentity {
            throw ValidationError.fileChanged
        }
    }

    static func identity(for url: URL) -> MediaFileIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.standardizedFileURL.path),
              let systemNumber = unsignedIntegerAttribute(attributes[.systemNumber]),
              let fileNumber = unsignedIntegerAttribute(attributes[.systemFileNumber]) else {
            return nil
        }
        return MediaFileIdentity(systemNumber: systemNumber, fileNumber: fileNumber)
    }

    private static func unsignedIntegerAttribute(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        if let value = value as? UInt64 {
            return value
        }
        if let value = value as? UInt {
            return UInt64(value)
        }
        if let value = value as? Int, value >= 0 {
            return UInt64(value)
        }
        return nil
    }
}
