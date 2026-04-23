@preconcurrency import AVFoundation
import CoreMedia
import Foundation

struct MetadataWriteProgress: Sendable {
    let fractionCompleted: Double
    let message: String
}

protocol MetadataWriting: Sendable {
    func writeMetadata(
        to fileURL: URL,
        using result: MediaSearchResult,
        includeArtwork: Bool,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)?
    ) async throws
}

struct MP4MetadataWriter: MetadataWriting {
    enum WriterError: LocalizedError {
        case exportSessionUnavailable
        case unsupportedFileType
        case exportFailed
        case exportCancelled
        case metadataVerificationFailed

        var errorDescription: String? {
            switch self {
            case .exportSessionUnavailable:
                return "AVFoundation could not create an export session for this MP4."
            case .unsupportedFileType:
                return "This MP4 could not be exported back to an `.mp4` file."
            case .exportFailed:
                return "AVFoundation failed to export the tagged MP4."
            case .exportCancelled:
                return "The MP4 export was cancelled."
            case .metadataVerificationFailed:
                return "MetaFetch could not verify that the metadata was written to the MP4."
            }
        }
    }

    private let outputFileType: AVFileType = .mp4
    private let atomWriter = MP4AtomMetadataWriter()

    func writeMetadata(
        to fileURL: URL,
        using result: MediaSearchResult,
        includeArtwork: Bool,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)? = nil
    ) async throws {
        let artworkData = includeArtwork
            ? try await ArtworkPipeline.shared.preparedArtwork(for: result.artworkURL)
            : nil
        let verificationExpectation = MetadataVerificationExpectation(result: result)

        if await attemptNativeAtomWrite(
            to: fileURL,
            using: result,
            artworkData: artworkData,
            verificationExpectation: verificationExpectation,
            progressHandler: progressHandler
        ) {
            return
        }

        let metadataItems = try await buildMetadataItems(for: result, includeArtwork: includeArtwork)

        if !includeArtwork {
            let usedFastPath = await attemptMetadataOnlyFastPath(
                to: fileURL,
                metadataItems: metadataItems,
                verificationExpectation: verificationExpectation,
                progressHandler: progressHandler
            )

            if usedFastPath {
                return
            }
        }

        let asset = AVURLAsset(url: fileURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw WriterError.exportSessionUnavailable
        }

        guard exportSession.supportedFileTypes.contains(outputFileType) else {
            throw WriterError.unsupportedFileType
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.metadata = metadataItems

        await progressHandler?(makeProgressUpdate(
            fractionCompleted: 0,
            message: "Starting MP4 container rewrite"
        ))

        try await export(
            session: exportSession,
            to: temporaryURL,
            fileType: outputFileType,
            progressHandler: progressHandler
        )

        await progressHandler?(makeProgressUpdate(
            fractionCompleted: 0.98,
            message: "Replacing the original file with the tagged copy"
        ))

        _ = try FileManager.default.replaceItemAt(
            fileURL,
            withItemAt: temporaryURL,
            backupItemName: nil,
            options: []
        )

        await progressHandler?(makeProgressUpdate(
            fractionCompleted: 0.99,
            message: "Verifying saved metadata"
        ))

        guard await metadataWasPersisted(
            at: fileURL,
            expectation: verificationExpectation
        ) else {
            throw WriterError.metadataVerificationFailed
        }
    }

    private func attemptNativeAtomWrite(
        to fileURL: URL,
        using result: MediaSearchResult,
        artworkData: Data?,
        verificationExpectation: MetadataVerificationExpectation,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)?
    ) async -> Bool {
        await progressHandler?(makeProgressUpdate(
            fractionCompleted: 0.04,
            message: "Preparing native MP4 metadata writer"
        ))

        do {
            try await atomWriter.writeMetadata(
                to: fileURL,
                using: result,
                artworkData: artworkData,
                progressHandler: progressHandler
            )

            await progressHandler?(makeProgressUpdate(
                fractionCompleted: 0.9,
                message: "Verifying native MP4 metadata"
            ))

            guard await metadataWasPersisted(
                at: fileURL,
                expectation: verificationExpectation
            ) else {
                await progressHandler?(makeProgressUpdate(
                    fractionCompleted: 0.08,
                    message: "Native MP4 metadata did not verify, falling back to AVFoundation"
                ))
                return false
            }

            await progressHandler?(makeProgressUpdate(
                fractionCompleted: 1,
                message: "Finished MP4 metadata atom save"
            ))
            return true
        } catch {
            await progressHandler?(makeProgressUpdate(
                fractionCompleted: 0.08,
                message: "Native MP4 writer could not update this file, falling back to AVFoundation"
            ))
            return false
        }
    }

    private func attemptMetadataOnlyFastPath(
        to fileURL: URL,
        metadataItems: [AVMetadataItem],
        verificationExpectation: MetadataVerificationExpectation,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)?
    ) async -> Bool {
        await progressHandler?(makeProgressUpdate(
            fractionCompleted: 0.04,
            message: "Trying metadata-only fast path"
        ))

        do {
            let movie = try loadMutableMovie(at: fileURL)

            guard movie.is(compatibleWithFileType: outputFileType) else {
                await progressHandler?(makeProgressUpdate(
                    fractionCompleted: 0.08,
                    message: "Fast path not supported for this MP4, falling back to full rewrite"
                ))
                return false
            }

            await progressHandler?(makeProgressUpdate(
                fractionCompleted: 0.16,
                message: "Applying metadata to the movie header"
            ))

            movie.metadata = metadataItems

            await progressHandler?(makeProgressUpdate(
                fractionCompleted: 0.72,
                message: "Writing updated movie header without rewriting media"
            ))

            try movie.writeHeader(
                to: fileURL,
                fileType: outputFileType,
                options: .addMovieHeaderToDestination
            )

            await progressHandler?(makeProgressUpdate(
                fractionCompleted: 0.88,
                message: "Verifying metadata-only save"
            ))

            guard await metadataWasPersisted(
                at: fileURL,
                expectation: verificationExpectation
            ) else {
                await progressHandler?(makeProgressUpdate(
                    fractionCompleted: 0.08,
                    message: "Metadata-only save did not verify, falling back to full rewrite"
                ))
                return false
            }

            await progressHandler?(makeProgressUpdate(
                fractionCompleted: 1,
                message: "Finished metadata-only fast save"
            ))
            return true
        } catch {
            await progressHandler?(makeProgressUpdate(
                fractionCompleted: 0.08,
                message: "Fast path failed, falling back to full container rewrite"
            ))
            return false
        }
    }

    private func metadataWasPersisted(
        at fileURL: URL,
        expectation: MetadataVerificationExpectation
    ) async -> Bool {
        let asset = AVURLAsset(url: fileURL)
        var metadataItems: [AVMetadataItem] = []

        if let commonMetadata = try? await asset.load(.commonMetadata) {
            metadataItems.append(contentsOf: commonMetadata)
        }

        if let metadata = try? await asset.load(.metadata) {
            metadataItems.append(contentsOf: metadata)
        }

        if let quickTimeMetadata = try? await asset.loadMetadata(for: .quickTimeMetadata) {
            metadataItems.append(contentsOf: quickTimeMetadata)
        }

        if let iTunesMetadata = try? await asset.loadMetadata(for: .iTunesMetadata) {
            metadataItems.append(contentsOf: iTunesMetadata)
        }

        if let quickTimeUserData = try? await asset.loadMetadata(for: .quickTimeUserData) {
            metadataItems.append(contentsOf: quickTimeUserData)
        }

        return await expectation.isSatisfied(by: metadataItems)
    }

    private func buildMetadataItems(for result: MediaSearchResult, includeArtwork: Bool) async throws -> [AVMetadataItem] {
        var items: [AVMetadataItem] = [
            stringItem(identifier: .commonIdentifierTitle, value: result.trackName),
            stringItem(identifier: .quickTimeUserDataFullName, value: result.trackName),
            stringItem(identifier: .iTunesMetadataSongName, value: result.trackName),
        ]

        let synopsis = result.synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        if !synopsis.isEmpty {
            items.append(stringItem(identifier: .commonIdentifierDescription, value: synopsis))
            items.append(stringItem(identifier: .quickTimeUserDataInformation, value: synopsis))
            items.append(stringItem(identifier: .iTunesMetadataDescription, value: synopsis))
        }

        if let genre = result.primaryGenreName.nilIfBlank {
            items.append(stringItem(identifier: .quickTimeUserDataGenre, value: genre))
            items.append(stringItem(identifier: .iTunesMetadataUserGenre, value: genre))
        }

        if let creator = result.artistName.nilIfBlank {
            switch result.mediaKind {
            case .movie:
                items.append(stringItem(identifier: .commonIdentifierCreator, value: creator))
                items.append(stringItem(identifier: .iTunesMetadataDirector, value: creator))
            case .tvEpisode, .tvSeries:
                items.append(stringItem(identifier: .commonIdentifierPublisher, value: creator))
                items.append(stringItem(identifier: .quickTimeUserDataPublisher, value: creator))
                items.append(stringItem(identifier: .iTunesMetadataAlbumArtist, value: creator))
            }
        }

        var commentLines: [String] = []

        if let rating = result.contentAdvisoryRating.nilIfBlank {
            commentLines.append("Rating: \(rating)")
        }

        if let releaseDate = parsedDate(from: result.releaseDate),
           result.mediaKind == .movie {
            items.append(dateItem(identifier: .commonIdentifierCreationDate, value: releaseDate))
        }

        switch result.mediaKind {
        case .movie:
            break
        case .tvEpisode:
            if let seriesName = result.seriesName.nilIfBlank {
                items.append(stringItem(identifier: .commonIdentifierAlbumName, value: seriesName))
                items.append(stringItem(identifier: .quickTimeUserDataAlbum, value: seriesName))
                items.append(stringItem(identifier: .iTunesMetadataAlbum, value: seriesName))
            }

            if let seasonEpisodeLabel = result.seasonEpisodeLabel {
                items.append(stringItem(identifier: .iTunesMetadataTrackSubTitle, value: seasonEpisodeLabel))
                commentLines.append("Episode: \(seasonEpisodeLabel)")
            }
        case .tvSeries:
            items.append(stringItem(identifier: .commonIdentifierAlbumName, value: result.trackName))
            items.append(stringItem(identifier: .quickTimeUserDataAlbum, value: result.trackName))
            items.append(stringItem(identifier: .iTunesMetadataAlbum, value: result.trackName))
        }

        if !commentLines.isEmpty {
            items.append(stringItem(identifier: .quickTimeUserDataComment, value: commentLines.joined(separator: "\n")))
        }

        if includeArtwork, let artworkItem = try await artworkMetadataItem(for: result.artworkURL) {
            items.append(artworkItem)
        }

        return items
    }

    private func loadMutableMovie(at fileURL: URL) throws -> AVMutableMovie {
        AVMutableMovie(url: fileURL, options: nil)
    }

    private func export(
        session: AVAssetExportSession,
        to outputURL: URL,
        fileType: AVFileType,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)?
    ) async throws {
        if #available(macOS 15, *) {
            try await exportWithStateMonitoring(
                session: session,
                to: outputURL,
                fileType: fileType,
                progressHandler: progressHandler
            )
            return
        }

        try await exportLegacy(
            session: session,
            to: outputURL,
            fileType: fileType,
            progressHandler: progressHandler
        )
    }

    @available(macOS 15, *)
    private func exportWithStateMonitoring(
        session: AVAssetExportSession,
        to outputURL: URL,
        fileType: AVFileType,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)?
    ) async throws {
        nonisolated(unsafe) let monitoredSession = session
        async let exportOperation: Void = monitoredSession.export(to: outputURL, as: fileType)

        if let progressHandler {
            for await state in monitoredSession.states(updateInterval: 0.15) {
                switch state {
                case .pending:
                    await progressHandler(makeProgressUpdate(
                        fractionCompleted: 0.02,
                        message: "Preparing MP4 container rewrite"
                    ))
                case .waiting:
                    await progressHandler(makeProgressUpdate(
                        fractionCompleted: 0.04,
                        message: "Waiting for export resources"
                    ))
                case .exporting(let progress):
                    let fractionCompleted = progress.fractionCompleted
                    let percent = Int(fractionCompleted * 100)
                    await progressHandler(makeProgressUpdate(
                        fractionCompleted: fractionCompleted,
                        message: "Writing tagged MP4 (\(percent)%)"
                    ))
                @unknown default:
                    break
                }
            }
        }

        try await exportOperation
    }

    private func exportLegacy(
        session: AVAssetExportSession,
        to outputURL: URL,
        fileType: AVFileType,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)?
    ) async throws {
        let sessionBox = ExportSessionBox(session)
        session.outputURL = outputURL
        session.outputFileType = fileType

        let progressMonitor = Task {
            guard let progressHandler else {
                return
            }

            while !Task.isCancelled {
                switch sessionBox.session.status {
                case .unknown:
                    await progressHandler(makeProgressUpdate(
                        fractionCompleted: 0.02,
                        message: "Preparing MP4 container rewrite"
                    ))
                case .waiting:
                    await progressHandler(makeProgressUpdate(
                        fractionCompleted: 0.04,
                        message: "Waiting for export resources"
                    ))
                case .exporting:
                    let fractionCompleted = Double(sessionBox.session.progress)
                    let percent = Int(fractionCompleted * 100)
                    await progressHandler(makeProgressUpdate(
                        fractionCompleted: fractionCompleted,
                        message: "Writing tagged MP4 (\(percent)%)"
                    ))
                case .completed, .failed, .cancelled:
                    return
                @unknown default:
                    return
                }

                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        defer {
            progressMonitor.cancel()
        }

        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch sessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: sessionBox.session.error ?? WriterError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: WriterError.exportCancelled)
                default:
                    continuation.resume(throwing: sessionBox.session.error ?? WriterError.exportFailed)
                }
            }
        }
    }

    private func makeProgressUpdate(
        fractionCompleted: Double,
        message: String
    ) -> MetadataWriteProgress {
        MetadataWriteProgress(
            fractionCompleted: min(max(fractionCompleted, 0), 1),
            message: message
        )
    }

    private func parsedDate(from rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        return ISO8601DateFormatter().date(from: rawValue)
    }

    private func stringItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.locale = Locale.current
        item.value = value as NSString
        return item
    }

    private func dateItem(identifier: AVMetadataIdentifier, value: Date) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSDate
        return item
    }

    private func artworkMetadataItem(for artworkURL: URL?) async throws -> AVMetadataItem? {
        guard let data = try await ArtworkPipeline.shared.preparedArtwork(for: artworkURL) else {
            return nil
        }

        guard !data.isEmpty else {
            return nil
        }

        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierArtwork
        item.dataType = artworkDataType(for: data)
        item.value = data as NSData
        return item
    }

    private func artworkDataType(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return kCMMetadataBaseDataType_PNG as String
        }

        return kCMMetadataBaseDataType_JPEG as String
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

private struct MetadataVerificationExpectation {
    struct RequiredString {
        let value: String
        let identifiers: Set<AVMetadataIdentifier>
    }

    let requiredStrings: [RequiredString]

    init(result: MediaSearchResult) {
        // Keep verification conservative: long descriptions and specialty atoms can be normalized
        // differently by AVFoundation, but title/album atoms should survive every successful save.
        var requiredStrings = [
            RequiredString(
                value: result.trackName,
                identifiers: [
                    .commonIdentifierTitle,
                    .quickTimeUserDataFullName,
                    .iTunesMetadataSongName,
                ]
            ),
        ]

        switch result.mediaKind {
        case .movie:
            break
        case .tvEpisode:
            if let seriesName = result.seriesName.nilIfBlank {
                requiredStrings.append(RequiredString(
                    value: seriesName,
                    identifiers: [
                        .commonIdentifierAlbumName,
                        .quickTimeUserDataAlbum,
                        .iTunesMetadataAlbum,
                    ]
                ))
            }
        case .tvSeries:
            requiredStrings.append(RequiredString(
                value: result.trackName,
                identifiers: [
                    .commonIdentifierAlbumName,
                    .quickTimeUserDataAlbum,
                    .iTunesMetadataAlbum,
                ]
            ))
        }

        self.requiredStrings = requiredStrings
    }

    func isSatisfied(by metadataItems: [AVMetadataItem]) async -> Bool {
        for requiredString in requiredStrings {
            var foundMatch = false

            for item in metadataItems {
                guard let identifier = item.identifier,
                      requiredString.identifiers.contains(identifier)
                else {
                    continue
                }

                guard let value = try? await item.load(.stringValue) else {
                    continue
                }

                if normalize(value) == normalize(requiredString.value) {
                    foundMatch = true
                    break
                }
            }

            if !foundMatch {
                return false
            }
        }

        return true
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}
