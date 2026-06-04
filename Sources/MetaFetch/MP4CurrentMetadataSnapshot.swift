@preconcurrency import AVFoundation
import Foundation

struct MP4CurrentMetadataSnapshot: Equatable, Sendable {
    var title: String?
    var seriesName: String?
    var creator: String?
    var genre: String?
    var year: String?
    var synopsis: String?
    var sortTitle: String?
    var sortSeriesName: String?
    var seasonNumber: String?
    var episodeNumber: String?
    var hasArtwork: Bool

    init(
        title: String? = nil,
        seriesName: String? = nil,
        creator: String? = nil,
        genre: String? = nil,
        year: String? = nil,
        synopsis: String? = nil,
        sortTitle: String? = nil,
        sortSeriesName: String? = nil,
        seasonNumber: String? = nil,
        episodeNumber: String? = nil,
        hasArtwork: Bool = false
    ) {
        self.title = title
        self.seriesName = seriesName
        self.creator = creator
        self.genre = genre
        self.year = year
        self.synopsis = synopsis
        self.sortTitle = sortTitle
        self.sortSeriesName = sortSeriesName
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.hasArtwork = hasArtwork
    }

    init(result: MediaSearchResult, hasArtwork: Bool) {
        self.init(
            title: result.trackName,
            seriesName: result.seriesName,
            creator: result.creatorValue,
            genre: result.primaryGenreName,
            year: result.releaseYear,
            synopsis: result.synopsis,
            sortTitle: result.sortTitle,
            sortSeriesName: result.sortSeriesName,
            seasonNumber: result.seasonNumber.map(String.init),
            episodeNumber: result.episodeNumber.map(String.init),
            hasArtwork: hasArtwork
        )
    }

    var hasReadableValues: Bool {
        [
            title,
            seriesName,
            creator,
            genre,
            year,
            synopsis,
            sortTitle,
            sortSeriesName,
            seasonNumber,
            episodeNumber,
        ].contains { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } || hasArtwork
    }
}

struct MP4CurrentMetadataReader: Sendable {
    func read(from fileURL: URL) async throws -> MP4CurrentMetadataSnapshot {
        let atomSnapshot = try await Task.detached(priority: .utility) {
            try MP4AtomMetadataWriter().currentMetadataSnapshot(at: fileURL)
        }.value

        if atomSnapshot.hasReadableValues {
            return atomSnapshot
        }

        return try await avFoundationSnapshot(from: fileURL)
    }

    private func avFoundationSnapshot(from fileURL: URL) async throws -> MP4CurrentMetadataSnapshot {
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

        return MP4CurrentMetadataSnapshot(
            title: await firstString(in: metadataItems, identifiers: [
                .commonIdentifierTitle,
                .quickTimeUserDataFullName,
                .iTunesMetadataSongName,
            ]),
            seriesName: await firstString(in: metadataItems, identifiers: [
                .commonIdentifierAlbumName,
                .quickTimeUserDataAlbum,
                .iTunesMetadataAlbum,
            ]),
            creator: await firstString(in: metadataItems, identifiers: [
                .commonIdentifierCreator,
                .commonIdentifierPublisher,
                .quickTimeUserDataPublisher,
                .iTunesMetadataDirector,
                .iTunesMetadataAlbumArtist,
            ]),
            genre: await firstString(in: metadataItems, identifiers: [
                .quickTimeUserDataGenre,
                .iTunesMetadataUserGenre,
            ]),
            year: firstYear(in: await firstString(in: metadataItems, identifiers: [
                .commonIdentifierCreationDate,
                .iTunesMetadataReleaseDate,
            ])),
            synopsis: await firstString(in: metadataItems, identifiers: [
                .commonIdentifierDescription,
                .quickTimeUserDataInformation,
                .iTunesMetadataDescription,
            ]),
            hasArtwork: await hasArtwork(in: metadataItems)
        )
    }

    private func firstString(
        in metadataItems: [AVMetadataItem],
        identifiers: Set<AVMetadataIdentifier>
    ) async -> String? {
        for item in metadataItems {
            guard let identifier = item.identifier,
                  identifiers.contains(identifier) else {
                continue
            }

            if let value = try? await item.load(.stringValue),
               let trimmed = value.trimmedNilIfBlank {
                return trimmed
            }
        }

        return nil
    }

    private func hasArtwork(in metadataItems: [AVMetadataItem]) async -> Bool {
        let artworkIdentifiers: Set<AVMetadataIdentifier> = [
            .commonIdentifierArtwork,
            .quickTimeMetadataArtwork,
            .iTunesMetadataCoverArt,
        ]

        for item in metadataItems {
            guard let identifier = item.identifier,
                  artworkIdentifiers.contains(identifier) else {
                continue
            }

            if let dataValue = try? await item.load(.dataValue), !dataValue.isEmpty {
                return true
            }

            if let value = try? await item.load(.value) as? Data, !value.isEmpty {
                return true
            }
        }

        return false
    }

    private func firstYear(in value: String?) -> String? {
        guard let value,
              let range = value.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) else {
            return nil
        }

        return String(value[range])
    }
}

private extension String {
    var trimmedNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
