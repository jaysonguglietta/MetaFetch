@preconcurrency import AVFoundation
import CoreMedia
import Foundation

protocol MetadataWriting: Sendable {
    func writeMetadata(to fileURL: URL, using result: MovieSearchResult, includeArtwork: Bool) async throws
}

struct MP4MetadataWriter: MetadataWriting {
    enum WriterError: LocalizedError {
        case exportSessionUnavailable
        case unsupportedFileType
        case exportFailed
        case exportCancelled

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
            }
        }
    }

    func writeMetadata(to fileURL: URL, using result: MovieSearchResult, includeArtwork: Bool) async throws {
        let asset = AVURLAsset(url: fileURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw WriterError.exportSessionUnavailable
        }

        guard exportSession.supportedFileTypes.contains(.mp4) else {
            throw WriterError.unsupportedFileType
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        exportSession.outputURL = temporaryURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.metadata = try await buildMetadataItems(for: result, includeArtwork: includeArtwork)

        try await export(session: exportSession)

        _ = try FileManager.default.replaceItemAt(
            fileURL,
            withItemAt: temporaryURL,
            backupItemName: nil,
            options: []
        )
    }

    private func buildMetadataItems(for result: MovieSearchResult, includeArtwork: Bool) async throws -> [AVMetadataItem] {
        var items: [AVMetadataItem] = [
            stringItem(identifier: .commonIdentifierTitle, value: result.trackName),
            stringItem(identifier: .quickTimeUserDataFullName, value: result.trackName),
        ]

        let synopsis = result.synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        if !synopsis.isEmpty {
            items.append(stringItem(identifier: .commonIdentifierDescription, value: synopsis))
            items.append(stringItem(identifier: .quickTimeUserDataInformation, value: synopsis))
        }

        if let genre = result.primaryGenreName.nilIfBlank {
            items.append(stringItem(identifier: .quickTimeUserDataGenre, value: genre))
        }

        if let creator = result.artistName.nilIfBlank {
            items.append(stringItem(identifier: .commonIdentifierCreator, value: creator))
        }

        if let rating = result.contentAdvisoryRating.nilIfBlank {
            items.append(stringItem(identifier: .quickTimeUserDataComment, value: "Rating: \(rating)"))
        }

        if let releaseDate = parsedDate(from: result.releaseDate) {
            items.append(dateItem(identifier: .commonIdentifierCreationDate, value: releaseDate))
        }

        if includeArtwork, let artworkItem = try await artworkMetadataItem(for: result.artworkURL) {
            items.append(artworkItem)
        }

        return items
    }

    private func export(session: AVAssetExportSession) async throws {
        let sessionBox = ExportSessionBox(session)

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

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}
