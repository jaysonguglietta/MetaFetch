import Foundation

struct MetadataDraft: Equatable, Sendable {
    var title: String = ""
    var seriesName: String = ""
    var creator: String = ""
    var genre: String = ""
    var year: String = ""
    var synopsis: String = ""
    var sortTitle: String = ""
    var sortSeriesName: String = ""
    var seasonNumber: String = ""
    var episodeNumber: String = ""

    init() {}

    init(result: MediaSearchResult) {
        title = result.trackName
        seriesName = result.seriesName ?? ""
        creator = result.creatorValue ?? ""
        genre = result.primaryGenreName ?? ""
        year = result.releaseYear ?? ""
        synopsis = result.synopsis
        sortTitle = result.sortTitle ?? result.trackName
        sortSeriesName = result.sortSeriesName ?? result.seriesName ?? ""
        seasonNumber = result.seasonNumber.map(String.init) ?? ""
        episodeNumber = result.episodeNumber.map(String.init) ?? ""
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isValid(for result: MediaSearchResult?) -> Bool {
        guard result != nil else {
            return false
        }

        return !trimmedTitle.isEmpty
    }

    func applying(to result: MediaSearchResult) -> MediaSearchResult {
        let normalizedYear = year.trimmingCharacters(in: .whitespacesAndNewlines)
        let releaseDate = normalizedYear.isEmpty ? result.releaseDate : normalizedYear

        return MediaSearchResult(
            trackId: result.trackId,
            mediaKind: result.mediaKind,
            trackName: trimmedTitle.isEmpty ? result.trackName : trimmedTitle,
            seriesName: normalizedOptional(seriesName) ?? result.seriesName,
            artistName: normalizedOptional(creator) ?? result.artistName,
            releaseDate: releaseDate,
            primaryGenreName: normalizedOptional(genre),
            shortDescription: normalizedOptional(synopsis),
            longDescription: normalizedOptional(synopsis),
            contentAdvisoryRating: result.contentAdvisoryRating,
            artworkURL: result.artworkURL,
            sortTitle: normalizedOptional(sortTitle),
            sortSeriesName: normalizedOptional(sortSeriesName),
            sourceURL: result.sourceURL,
            sourceName: result.sourceName,
            matchConfidence: result.matchConfidence,
            matchSummary: result.matchSummary,
            matchScore: result.matchScore,
            seasonNumber: normalizedInteger(seasonNumber) ?? result.seasonNumber,
            episodeNumber: normalizedInteger(episodeNumber) ?? result.episodeNumber
        )
    }

    mutating func reset(to result: MediaSearchResult) {
        self = MetadataDraft(result: result)
    }

    private func normalizedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedInteger(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let integer = Int(trimmed),
              integer > 0 else {
            return nil
        }

        return integer
    }
}
