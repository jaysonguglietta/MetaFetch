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
        let seriesName: String?
        let sortSeriesName: String?
        switch result.mediaKind {
        case .movie:
            seriesName = nil
            sortSeriesName = nil
        case .tvEpisode:
            seriesName = result.seriesName
            sortSeriesName = result.sortSeriesName ?? result.seriesName
        case .tvSeries:
            seriesName = result.trackName
            sortSeriesName = result.sortSeriesName ?? result.trackName
        }

        self.init(
            title: result.trackName,
            seriesName: seriesName,
            creator: result.creatorValue,
            genre: result.primaryGenreName,
            year: result.releaseYear,
            synopsis: result.persistableSynopsis,
            sortTitle: result.sortTitle ?? result.trackName,
            sortSeriesName: sortSeriesName,
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

struct MetadataVerificationResult: Equatable, Sendable {
    let verifiedFieldCount: Int
    let discrepancies: [String]

    var isVerified: Bool {
        discrepancies.isEmpty
    }

    var failureDescription: String {
        guard !discrepancies.isEmpty else {
            return "All requested metadata fields were verified."
        }
        return "Metadata verification failed for: \(discrepancies.joined(separator: ", "))."
    }
}

extension MP4CurrentMetadataSnapshot {
    func verification(
        against result: MediaSearchResult,
        expectsArtwork: Bool
    ) -> MetadataVerificationResult {
        var verifiedFieldCount = 0
        var discrepancies: [String] = []

        compare("title", expected: result.trackName, actual: title, count: &verifiedFieldCount, failures: &discrepancies)
        compare("creator", expected: result.creatorValue, actual: creator, count: &verifiedFieldCount, failures: &discrepancies)
        compare("genre", expected: result.primaryGenreName, actual: genre, count: &verifiedFieldCount, failures: &discrepancies)
        compare("release date", expected: result.releaseYear, actual: year, count: &verifiedFieldCount, failures: &discrepancies)
        compare("description", expected: result.persistableSynopsis, actual: synopsis, count: &verifiedFieldCount, failures: &discrepancies)

        let expectedSeriesName: String?
        let expectedSortTitle: String?
        let expectedSortSeriesName: String?
        switch result.mediaKind {
        case .movie:
            expectedSeriesName = nil
            expectedSortTitle = result.sortTitle ?? result.trackName
            expectedSortSeriesName = nil
        case .tvEpisode:
            expectedSeriesName = result.seriesName
            expectedSortTitle = result.sortTitle ?? result.trackName
            expectedSortSeriesName = result.sortSeriesName ?? result.seriesName
        case .tvSeries:
            expectedSeriesName = result.trackName
            expectedSortTitle = result.sortTitle ?? result.trackName
            expectedSortSeriesName = result.sortSeriesName ?? result.trackName
        }

        compare("series", expected: expectedSeriesName, actual: seriesName, count: &verifiedFieldCount, failures: &discrepancies)
        compare("sort title", expected: expectedSortTitle, actual: sortTitle, count: &verifiedFieldCount, failures: &discrepancies)
        compare("sort series", expected: expectedSortSeriesName, actual: sortSeriesName, count: &verifiedFieldCount, failures: &discrepancies)
        compare("season", expected: result.seasonNumber.map(String.init), actual: seasonNumber, count: &verifiedFieldCount, failures: &discrepancies)
        compare("episode", expected: result.episodeNumber.map(String.init), actual: episodeNumber, count: &verifiedFieldCount, failures: &discrepancies)

        if expectsArtwork {
            if hasArtwork {
                verifiedFieldCount += 1
            } else {
                discrepancies.append("artwork")
            }
        }

        return MetadataVerificationResult(
            verifiedFieldCount: verifiedFieldCount,
            discrepancies: discrepancies
        )
    }

    private func compare(
        _ label: String,
        expected: String?,
        actual: String?,
        count: inout Int,
        failures: inout [String]
    ) {
        if normalized(expected) == normalized(actual) {
            count += 1
        } else {
            failures.append(label)
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.precomposedStringWithCanonicalMapping
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
