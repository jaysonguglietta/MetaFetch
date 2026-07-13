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
        synopsis = result.persistableSynopsis ?? ""
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

        let trimmedReleaseDate = year.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSeason = seasonNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEpisode = episodeNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedTitle.isEmpty &&
            (trimmedReleaseDate.isEmpty || normalizedReleaseDate(from: year) != nil) &&
            (trimmedSeason.isEmpty || normalizedInteger(seasonNumber) != nil) &&
            (trimmedEpisode.isEmpty || normalizedInteger(episodeNumber) != nil)
    }

    func applying(to result: MediaSearchResult) -> MediaSearchResult {
        let releaseDate = normalizedReleaseDate(from: year)

        return MediaSearchResult(
            trackId: result.trackId,
            mediaKind: result.mediaKind,
            trackName: trimmedTitle.isEmpty ? result.trackName : trimmedTitle,
            seriesName: normalizedOptional(seriesName),
            artistName: normalizedOptional(creator),
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
            seasonNumber: normalizedInteger(seasonNumber),
            episodeNumber: normalizedInteger(episodeNumber)
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

    private func normalizedReleaseDate(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
            return "\(trimmed)-01-01T00:00:00Z"
        }

        if trimmed.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return "\(trimmed)T00:00:00Z"
        }

        if ISO8601DateFormatter().date(from: trimmed) != nil {
            return trimmed
        }

        return nil
    }
}
