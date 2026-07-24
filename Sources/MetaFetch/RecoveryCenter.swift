import Foundation

struct RecoveryRecord: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case safetyBackup = "Safety Backup"
        case interruptedWrite = "Interrupted Write"
    }

    let recoveryURL: URL
    let originalURL: URL
    let kind: Kind
    let modifiedAt: Date?
    let byteCount: Int64

    var id: String { recoveryURL.standardizedFileURL.path }
}

enum RecoveryCenterService {
    enum RecoveryError: LocalizedError {
        case unsafeRecoveryFile
        case originalOutsideRecoveryFolder
        case recoveryValidationFailed

        var errorDescription: String? {
            switch self {
            case .unsafeRecoveryFile: "The recovery copy is not a safe local regular file."
            case .originalOutsideRecoveryFolder: "Recovery is limited to the original file in the same folder."
            case .recoveryValidationFailed: "The restored MP4 did not pass container validation; the existing file was put back."
            }
        }
    }

    static func discover(near fileURLs: [URL]) -> [RecoveryRecord] {
        let directories = Set(fileURLs.map { $0.deletingLastPathComponent().standardizedFileURL })
        return directories.flatMap(discover(in:)).sorted {
            ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
        }
    }

    static func restore(_ record: RecoveryRecord) async throws {
        try validate(record)
        let stagingLocation = try TransactionalFileReplacement.makeStagingLocation(
            for: record.originalURL,
            pathExtension: "mp4"
        )
        let preparedURL = stagingLocation.fileURL
        defer { stagingLocation.remove() }

        try FileManager.default.copyItem(at: record.recoveryURL, to: preparedURL)
        try await TransactionalFileReplacement.install(
            preparedFileURL: preparedURL,
            replacing: record.originalURL
        ) {
            do {
                _ = try MP4AtomMetadataWriter().currentMetadataSnapshot(at: record.originalURL)
                return true
            } catch {
                return false
            }
        }
    }

    private static func discover(in directory: URL) -> [RecoveryRecord] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return discoverInterruptedWrites(in: directory, keys: keys)
        }

        let backups = candidates.compactMap { candidate -> RecoveryRecord? in
            guard candidate.lastPathComponent.contains(".metafetch-backup-") else { return nil }
            return record(for: candidate, kind: .safetyBackup)
        }
        return backups + discoverInterruptedWrites(in: directory, keys: keys)
    }

    private static func discoverInterruptedWrites(in directory: URL, keys: Set<URLResourceKey>) -> [RecoveryRecord] {
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return [] }
        return candidates.compactMap { candidate in
            guard candidate.lastPathComponent.contains(".metafetch-rollback-") else { return nil }
            return record(for: candidate, kind: .interruptedWrite)
        }
    }

    private static func record(for recoveryURL: URL, kind: RecoveryRecord.Kind) -> RecoveryRecord? {
        let values = try? recoveryURL.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
        ])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true,
              let originalURL = originalURL(for: recoveryURL, kind: kind) else { return nil }
        return RecoveryRecord(
            recoveryURL: recoveryURL,
            originalURL: originalURL,
            kind: kind,
            modifiedAt: values?.contentModificationDate,
            byteCount: Int64(values?.fileSize ?? 0)
        )
    }

    private static func originalURL(for recoveryURL: URL, kind: RecoveryRecord.Kind) -> URL? {
        let filename = recoveryURL.lastPathComponent
        switch kind {
        case .safetyBackup:
            guard let marker = filename.range(of: ".metafetch-backup-") else { return nil }
            let prefix = String(filename[..<marker.lowerBound])
            return recoveryURL.deletingLastPathComponent().appendingPathComponent(prefix).appendingPathExtension("mp4")
        case .interruptedWrite:
            guard filename.hasPrefix("."), let marker = filename.range(of: ".metafetch-rollback-") else { return nil }
            let prefix = String(filename[filename.index(after: filename.startIndex)..<marker.lowerBound])
            return recoveryURL.deletingLastPathComponent().appendingPathComponent(prefix)
        }
    }

    private static func validate(_ record: RecoveryRecord) throws {
        let recoveryValues = try record.recoveryURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard record.recoveryURL.isFileURL,
              recoveryValues.isRegularFile == true,
              recoveryValues.isSymbolicLink != true,
              (recoveryValues.fileSize ?? 0) > 0 else {
            throw RecoveryError.unsafeRecoveryFile
        }
        guard record.recoveryURL.deletingLastPathComponent().standardizedFileURL ==
                record.originalURL.deletingLastPathComponent().standardizedFileURL else {
            throw RecoveryError.originalOutsideRecoveryFolder
        }
        if FileManager.default.fileExists(atPath: record.originalURL.path) {
            let originalValues = try record.originalURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard originalValues.isRegularFile == true, originalValues.isSymbolicLink != true else {
                throw RecoveryError.unsafeRecoveryFile
            }
        }
    }
}
