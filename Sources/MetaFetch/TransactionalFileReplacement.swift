import Foundation

enum TransactionalFileReplacement {
    enum ReplacementError: LocalizedError {
        case verificationFailed
        case rollbackUnavailable
        case rollbackFailed
        case stagingUnavailable
        case coordinatedReplacementFailed(String)

        var errorDescription: String? {
            switch self {
            case .verificationFailed:
                return "The replacement file did not pass metadata verification."
            case .rollbackUnavailable:
                return "MetaFetch could not create the temporary rollback file needed for a safe replacement."
            case .rollbackFailed:
                return "MetaFetch could not restore the original file after a failed replacement."
            case .stagingUnavailable:
                return "MetaFetch could not create a safe replacement area on the movie’s volume."
            case .coordinatedReplacementFailed(let detail):
                return "MetaFetch could not replace the original MP4 safely. \(detail)"
            }
        }
    }

    struct StagingLocation {
        let directoryURL: URL
        let fileURL: URL

        func remove() {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    static func makeStagingLocation(
        for originalFileURL: URL,
        pathExtension: String = "mp4"
    ) throws -> StagingLocation {
        let fileManager = FileManager.default
        let directoryURL = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: originalFileURL,
            create: true
        )
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ReplacementError.stagingUnavailable
        }

        let fileURL = directoryURL
            .appendingPathComponent("metafetch-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        return StagingLocation(directoryURL: directoryURL, fileURL: fileURL)
    }

    static func install(
        preparedFileURL: URL,
        replacing originalFileURL: URL,
        verify: @Sendable () async throws -> Bool
    ) async throws {
        let fileManager = FileManager.default
        let rollbackStaging = try makeStagingLocation(
            for: originalFileURL,
            pathExtension: originalFileURL.pathExtension
        )
        defer { rollbackStaging.remove() }

        try fileManager.copyItem(at: originalFileURL, to: rollbackStaging.fileURL)
        guard fileManager.fileExists(atPath: rollbackStaging.fileURL.path) else {
            throw ReplacementError.rollbackUnavailable
        }

        try coordinatedReplace(
            originalFileURL: originalFileURL,
            preparedFileURL: preparedFileURL
        )

        do {
            guard try await verify() else {
                throw ReplacementError.verificationFailed
            }
        } catch {
            do {
                try coordinatedReplace(
                    originalFileURL: originalFileURL,
                    preparedFileURL: rollbackStaging.fileURL
                )
            } catch {
                throw ReplacementError.rollbackFailed
            }
            throw error
        }
    }

    private static func coordinatedReplace(
        originalFileURL: URL,
        preparedFileURL: URL
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var replacementResult: Result<Void, Error> = .success(())

        coordinator.coordinate(
            writingItemAt: originalFileURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedOriginalURL in
            replacementResult = Result {
                _ = try FileManager.default.replaceItemAt(
                    coordinatedOriginalURL,
                    withItemAt: preparedFileURL,
                    backupItemName: nil,
                    options: []
                )
            }
        }

        if let coordinationError {
            throw ReplacementError.coordinatedReplacementFailed(coordinationError.localizedDescription)
        }
        do {
            try replacementResult.get()
        } catch {
            throw ReplacementError.coordinatedReplacementFailed(error.localizedDescription)
        }
    }
}
