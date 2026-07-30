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
    var contentRating: String = ""
    var communityRating: String = ""
    var imdbID: String = ""
    var tmdbID: String = ""
    var tvmazeID: String = ""

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
        contentRating = result.contentAdvisoryRating ?? ""
        communityRating = result.communityRating.map { String(format: "%.1f", $0) } ?? ""
        imdbID = result.externalIDs.imdb ?? ""
        tmdbID = result.externalIDs.tmdb.map(String.init) ?? ""
        tvmazeID = result.externalIDs.tvmaze.map(String.init) ?? ""
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isValid(for result: MediaSearchResult?) -> Bool {
        validationError(for: result) == nil
    }

    func validationError(for result: MediaSearchResult?) -> String? {
        guard result != nil else {
            return "Select a metadata match before saving."
        }
        guard !trimmedTitle.isEmpty else {
            return "Enter a title before saving metadata."
        }

        let trimmedReleaseDate = year.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSeason = seasonNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEpisode = episodeNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReleaseDate.isEmpty && normalizedReleaseDate(from: year) == nil {
            return "Use YYYY, YYYY-MM-DD, or a full ISO date for Release Date."
        }
        if !trimmedSeason.isEmpty && normalizedInteger(seasonNumber) == nil {
            return "Season must be a positive whole number."
        }
        if !trimmedEpisode.isEmpty && normalizedInteger(episodeNumber) == nil {
            return "Episode must be a positive whole number."
        }
        let trimmedCommunityRating = communityRating.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCommunityRating.isEmpty,
           (Double(trimmedCommunityRating) == nil || !(0...10).contains(Double(trimmedCommunityRating) ?? -1)) {
            return "Community rating must be a number from 0 to 10."
        }
        let trimmedIMDbID = imdbID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedIMDbID.isEmpty,
           trimmedIMDbID.range(of: #"^tt\d{5,12}$"#, options: .regularExpression) == nil {
            return "IMDb ID must look like tt1234567."
        }
        for (label, value) in [("TMDb", tmdbID), ("TVMaze", tvmazeID)] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && normalizedInteger(value) == nil {
                return "\(label) ID must be a positive whole number."
            }
        }
        return nil
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
            contentAdvisoryRating: normalizedOptional(contentRating),
            artworkURL: result.artworkURL,
            sortTitle: normalizedOptional(sortTitle),
            sortSeriesName: normalizedOptional(sortSeriesName),
            sourceURL: result.sourceURL,
            sourceName: result.sourceName,
            matchConfidence: result.matchConfidence,
            matchSummary: result.matchSummary,
            matchScore: result.matchScore,
            seasonNumber: normalizedInteger(seasonNumber),
            episodeNumber: normalizedInteger(episodeNumber),
            communityRating: Double(communityRating.trimmingCharacters(in: .whitespacesAndNewlines)),
            externalIDs: MediaExternalIDs(
                imdb: normalizedOptional(imdbID),
                tmdb: normalizedInteger(tmdbID),
                tvmaze: normalizedInteger(tvmazeID)
            )
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
