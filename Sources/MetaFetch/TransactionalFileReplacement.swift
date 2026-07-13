import Foundation

enum TransactionalFileReplacement {
    enum ReplacementError: LocalizedError {
        case verificationFailed
        case rollbackUnavailable
        case rollbackFailed

        var errorDescription: String? {
            switch self {
            case .verificationFailed:
                return "The replacement file did not pass metadata verification."
            case .rollbackUnavailable:
                return "MetaFetch could not create the temporary rollback file needed for a safe replacement."
            case .rollbackFailed:
                return "MetaFetch could not restore the original file after a failed replacement."
            }
        }
    }

    static func install(
        preparedFileURL: URL,
        replacing originalFileURL: URL,
        verify: @Sendable () async throws -> Bool
    ) async throws {
        let fileManager = FileManager.default

        let rollbackName = ".\(originalFileURL.lastPathComponent).metafetch-rollback-\(UUID().uuidString)"
        let rollbackURL = originalFileURL.deletingLastPathComponent().appendingPathComponent(rollbackName)

        _ = try fileManager.replaceItemAt(
            originalFileURL,
            withItemAt: preparedFileURL,
            backupItemName: rollbackName,
            options: [.withoutDeletingBackupItem]
        )

        guard fileManager.fileExists(atPath: rollbackURL.path) else {
            throw ReplacementError.rollbackUnavailable
        }

        do {
            guard try await verify() else {
                throw ReplacementError.verificationFailed
            }

            try fileManager.removeItem(at: rollbackURL)
        } catch {
            do {
                if fileManager.fileExists(atPath: originalFileURL.path) {
                    try fileManager.removeItem(at: originalFileURL)
                }
                try fileManager.moveItem(at: rollbackURL, to: originalFileURL)
            } catch {
                throw ReplacementError.rollbackFailed
            }
            throw error
        }
    }
}
