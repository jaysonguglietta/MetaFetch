import Foundation

enum MatchConfidence: String, Hashable, Sendable {
    case exact
    case strong
    case possible

    var label: String {
        switch self {
        case .exact:
            return "Exact Match"
        case .strong:
            return "Strong Match"
        case .possible:
            return "Possible Match"
        }
    }
}

struct MediaSearchResult: Hashable, Identifiable, Sendable {
    let trackId: Int
    let mediaKind: MediaSearchKind
    let trackName: String
    let seriesName: String?
    let artistName: String?
    let releaseDate: String?
    let primaryGenreName: String?
    let shortDescription: String?
    let longDescription: String?
    let contentAdvisoryRating: String?
    let artworkURL: URL?
    let sortTitle: String?
    let sortSeriesName: String?
    let sourceURL: URL?
    let sourceName: String
    let matchConfidence: MatchConfidence
    let matchSummary: String
    let matchScore: Int
    let seasonNumber: Int?
    let episodeNumber: Int?

    init(
        trackId: Int,
        mediaKind: MediaSearchKind,
        trackName: String,
        seriesName: String?,
        artistName: String?,
        releaseDate: String?,
        primaryGenreName: String?,
        shortDescription: String?,
        longDescription: String?,
        contentAdvisoryRating: String?,
        artworkURL: URL?,
        sortTitle: String? = nil,
        sortSeriesName: String? = nil,
        sourceURL: URL?,
        sourceName: String,
        matchConfidence: MatchConfidence,
        matchSummary: String,
        matchScore: Int,
        seasonNumber: Int?,
        episodeNumber: Int?
    ) {
        self.trackId = trackId
        self.mediaKind = mediaKind
        self.trackName = trackName
        self.seriesName = seriesName
        self.artistName = artistName
        self.releaseDate = releaseDate
        self.primaryGenreName = primaryGenreName
        self.shortDescription = shortDescription
        self.longDescription = longDescription
        self.contentAdvisoryRating = contentAdvisoryRating
        self.artworkURL = artworkURL
        self.sortTitle = sortTitle
        self.sortSeriesName = sortSeriesName
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.matchConfidence = matchConfidence
        self.matchSummary = matchSummary
        self.matchScore = matchScore
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }

    var id: Int {
        trackId
    }

    var releaseYear: String? {
        guard let releaseDate else {
            return nil
        }

        return String(releaseDate.prefix(4))
    }

    var synopsis: String {
        let preferred = [longDescription, shortDescription]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        return preferred ?? "No synopsis was returned for this title."
    }

    var subtitleLine: String {
        switch mediaKind {
        case .movie:
            return [releaseYear, primaryGenreName, artistName]
                .compactMap { $0?.trimmedNilIfBlank }
                .joined(separator: " • ")
        case .tvEpisode:
            return [seriesName, seasonEpisodeLabel, releaseYear]
                .compactMap { $0?.trimmedNilIfBlank }
                .joined(separator: " • ")
        case .tvSeries:
            return [releaseYear, primaryGenreName, artistName]
                .compactMap { $0?.trimmedNilIfBlank }
                .joined(separator: " • ")
        }
    }

    var seasonEpisodeLabel: String? {
        guard let seasonNumber, let episodeNumber else {
            return nil
        }

        return String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }

    var synopsisPreview: String {
        let text = synopsis
        guard text.count > 180 else {
            return text
        }

        return String(text.prefix(177)) + "..."
    }

    var hasArtwork: Bool {
        artworkURL != nil
    }

    var creatorValue: String? {
        artistName.trimmedNilIfBlank
    }

    var creatorLabel: String {
        switch mediaKind {
        case .movie:
            return "Director"
        case .tvEpisode, .tvSeries:
            return "Network"
        }
    }

    func replacingArtworkURL(_ artworkURL: URL?) -> MediaSearchResult {
        MediaSearchResult(
            trackId: trackId,
            mediaKind: mediaKind,
            trackName: trackName,
            seriesName: seriesName,
            artistName: artistName,
            releaseDate: releaseDate,
            primaryGenreName: primaryGenreName,
            shortDescription: shortDescription,
            longDescription: longDescription,
            contentAdvisoryRating: contentAdvisoryRating,
            artworkURL: artworkURL,
            sortTitle: sortTitle,
            sortSeriesName: sortSeriesName,
            sourceURL: sourceURL,
            sourceName: sourceName,
            matchConfidence: matchConfidence,
            matchSummary: matchSummary,
            matchScore: matchScore,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        )
    }
}

protocol MediaSearchServing: Sendable {
    func search(matching query: String, mode: MediaLibraryMode) async throws -> [MediaSearchResult]
}

struct MetadataCatalogSearchService: MediaSearchServing {
    private let movieService = WikimediaMovieSearchService()
    private let alternateMovieService = AlternateMovieProviderSearchService()
    private let tvService = TVMazeSearchService()

    func search(matching query: String, mode: MediaLibraryMode) async throws -> [MediaSearchResult] {
        switch mode {
        case .movie:
            async let primaryResults = searchPrimaryMovies(matching: query)
            async let alternateResults = alternateMovieService.searchMovies(matching: query)

            return await prioritizedMovieResults(primaryResults + alternateResults)
        case .tvShow:
            return try await tvService.searchTV(matching: query)
        }
    }

    private func searchPrimaryMovies(matching query: String) async -> [MediaSearchResult] {
        (try? await movieService.searchMovies(matching: query)) ?? []
    }

    private func prioritizedMovieResults(_ results: [MediaSearchResult]) -> [MediaSearchResult] {
        let preferredSource = MetadataProviderPreferences.preferredProviderSource
        return results.sorted { lhs, rhs in
            let lhsScore = lhs.matchScore + preferredSource.priorityBonus(for: lhs.sourceName)
            let rhsScore = rhs.matchScore + preferredSource.priorityBonus(for: rhs.sourceName)
            if lhsScore == rhsScore {
                return lhs.trackName.localizedStandardCompare(rhs.trackName) == .orderedAscending
            }

            return lhsScore > rhsScore
        }
    }
}

private struct AlternateMovieProviderSearchService {
    private let tmdbService = TMDbMovieSearchService()
    private let omdbService = OMDbMovieSearchService()

    func searchMovies(matching query: String) async -> [MediaSearchResult] {
        async let tmdbResults = tmdbService.searchMovies(
            matching: query,
            apiKey: MetadataProviderPreferences.tmdbAPIKey
        )
        async let omdbResults = omdbService.searchMovies(
            matching: query,
            apiKey: MetadataProviderPreferences.omdbAPIKey
        )

        return await (tmdbResults + omdbResults)
            .sorted { lhs, rhs in lhs.matchScore > rhs.matchScore }
    }
}

private struct TMDbMovieSearchService {
    private struct SearchResponse: Decodable {
        let results: [Movie]
    }

    private struct Movie: Decodable {
        let id: Int
        let title: String
        let releaseDate: String?
        let overview: String?
        let posterPath: String?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case releaseDate = "release_date"
            case overview
            case posterPath = "poster_path"
        }
    }

    func searchMovies(matching query: String, apiKey: String) async -> [MediaSearchResult] {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !sanitizedQuery.isEmpty else {
            return []
        }

        var components = URLComponents(string: "https://api.themoviedb.org/3/search/movie")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: sanitizedQuery),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "page", value: "1"),
        ]

        guard let url = components?.url else {
            return []
        }

        do {
            let response: SearchResponse = try await performRequest(url, decoding: SearchResponse.self)
            let expectedYear = extractYear(from: sanitizedQuery)
            let normalizedQuery = normalizedTitle(from: sanitizedQuery)

            return response.results
                .prefix(10)
                .map {
                    buildResult(
                        from: $0,
                        normalizedQuery: normalizedQuery,
                        expectedYear: expectedYear
                    )
                }
        } catch {
            return []
        }
    }

    private func buildResult(
        from movie: Movie,
        normalizedQuery: String,
        expectedYear: String?
    ) -> MediaSearchResult {
        let releaseDate = movie.releaseDate.map { "\($0)T00:00:00Z" }
        let posterURL = movie.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
        let sourceURL = URL(string: "https://www.themoviedb.org/movie/\(movie.id)")

        let provisionalResult = MediaSearchResult(
            trackId: 1_000_000_000 + movie.id,
            mediaKind: .movie,
            trackName: movie.title,
            seriesName: nil,
            artistName: nil,
            releaseDate: releaseDate,
            primaryGenreName: nil,
            shortDescription: movie.overview,
            longDescription: movie.overview,
            contentAdvisoryRating: nil,
            artworkURL: posterURL,
            sourceURL: sourceURL,
            sourceName: "TMDb",
            matchConfidence: .possible,
            matchSummary: "TMDb movie result",
            matchScore: 0,
            seasonNumber: nil,
            episodeNumber: nil
        )

        let evaluation = evaluateProviderMatch(
            provisionalResult,
            normalizedQuery: normalizedQuery,
            expectedYear: expectedYear,
            sourceBonus: 28
        )

        return provisionalResult.withMatchEvaluation(evaluation)
    }

    private func performRequest<Response: Decodable>(_ url: URL, decoding type: Response.Type) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = BoundedJSONRequest.timeoutInterval
        request.setValue("MetaFetch/1.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await BoundedJSONRequest.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct OMDbMovieSearchService {
    private struct SearchResponse: Decodable {
        let Search: [SearchHit]?
        let Response: String
    }

    private struct SearchHit: Decodable {
        let Title: String
        let Year: String
        let imdbID: String
        let Poster: String
    }

    private struct DetailResponse: Decodable {
        let Title: String?
        let Year: String?
        let Rated: String?
        let Genre: String?
        let Director: String?
        let Plot: String?
        let Poster: String?
        let imdbID: String?
        let Response: String
    }

    func searchMovies(matching query: String, apiKey: String) async -> [MediaSearchResult] {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !sanitizedQuery.isEmpty else {
            return []
        }

        var components = URLComponents(string: "https://www.omdbapi.com/")
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "s", value: sanitizedQuery),
            URLQueryItem(name: "type", value: "movie"),
            URLQueryItem(name: "r", value: "json"),
        ]

        guard let url = components?.url else {
            return []
        }

        do {
            let response: SearchResponse = try await performRequest(url, decoding: SearchResponse.self)
            guard response.Response.lowercased() == "true" else {
                return []
            }

            let details = await fetchDetails(
                for: Array((response.Search ?? []).prefix(8)),
                apiKey: apiKey
            )
            let expectedYear = extractYear(from: sanitizedQuery)
            let normalizedQuery = normalizedTitle(from: sanitizedQuery)

            return details.map {
                buildResult(
                    from: $0,
                    normalizedQuery: normalizedQuery,
                    expectedYear: expectedYear
                )
            }
        } catch {
            return []
        }
    }

    private func fetchDetails(for hits: [SearchHit], apiKey: String) async -> [DetailResponse] {
        await withTaskGroup(of: DetailResponse?.self) { group in
            for hit in hits {
                group.addTask {
                    var components = URLComponents(string: "https://www.omdbapi.com/")
                    components?.queryItems = [
                        URLQueryItem(name: "apikey", value: apiKey),
                        URLQueryItem(name: "i", value: hit.imdbID),
                        URLQueryItem(name: "plot", value: "full"),
                        URLQueryItem(name: "r", value: "json"),
                    ]

                    guard let url = components?.url else {
                        return nil
                    }

                    return try? await performRequest(url, decoding: DetailResponse.self)
                }
            }

            var details: [DetailResponse] = []
            for await detail in group {
                if let detail, detail.Response.lowercased() == "true" {
                    details.append(detail)
                }
            }

            return details
        }
    }

    private func buildResult(
        from detail: DetailResponse,
        normalizedQuery: String,
        expectedYear: String?
    ) -> MediaSearchResult {
        let title = detail.Title?.trimmedNilIfBlank ?? "Untitled OMDb Result"
        let releaseDate = detail.Year?.firstMatch(for: #"\b(19|20)\d{2}\b"#).map { "\($0)-01-01T00:00:00Z" }
        let artworkURL = detail.Poster.flatMap { $0 == "N/A" ? nil : URL(string: $0) }
        let imdbID = detail.imdbID ?? ""
        let sourceURL = imdbID.isEmpty ? nil : URL(string: "https://www.imdb.com/title/\(imdbID)/")

        let provisionalResult = MediaSearchResult(
            trackId: 2_000_000_000 + numericIMDbID(imdbID),
            mediaKind: .movie,
            trackName: title,
            seriesName: nil,
            artistName: detail.Director?.nilIfNA,
            releaseDate: releaseDate,
            primaryGenreName: detail.Genre?.nilIfNA,
            shortDescription: detail.Plot?.nilIfNA,
            longDescription: detail.Plot?.nilIfNA,
            contentAdvisoryRating: detail.Rated?.nilIfNA,
            artworkURL: artworkURL,
            sourceURL: sourceURL,
            sourceName: "OMDb",
            matchConfidence: .possible,
            matchSummary: "OMDb movie result",
            matchScore: 0,
            seasonNumber: nil,
            episodeNumber: nil
        )

        let evaluation = evaluateProviderMatch(
            provisionalResult,
            normalizedQuery: normalizedQuery,
            expectedYear: expectedYear,
            sourceBonus: 24
        )

        return provisionalResult.withMatchEvaluation(evaluation)
    }

    private func numericIMDbID(_ imdbID: String) -> Int {
        let digits = imdbID.filter(\.isNumber)
        return Int(digits.suffix(8)) ?? abs(imdbID.hashValue % 100_000_000)
    }

    private func performRequest<Response: Decodable>(_ url: URL, decoding type: Response.Type) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = BoundedJSONRequest.timeoutInterval
        request.setValue("MetaFetch/1.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await BoundedJSONRequest.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct WikimediaMovieSearchService {
    private struct SearchResponse: Decodable {
        struct Query: Decodable {
            let search: [SearchHit]
        }

        let query: Query
    }

    private struct SearchHit: Decodable {
        let pageid: Int
        let title: String
        let snippet: String?
    }

    private struct PageDetailsResponse: Decodable {
        struct Query: Decodable {
            let pages: [String: PageDetail]
        }

        let query: Query
    }

    private struct PageDetail: Decodable {
        struct PageProps: Decodable {
            let pageImage: String?
            let shortDescription: String?

            enum CodingKeys: String, CodingKey {
                case pageImage = "page_image"
                case shortDescription = "wikibase-shortdesc"
            }
        }

        let pageid: Int?
        let title: String
        let extract: String?
        let pageprops: PageProps?
    }

    private struct ImageInfoResponse: Decodable {
        struct Query: Decodable {
            let pages: [String: ImagePage]
        }

        let query: Query
    }

    private struct ImagePage: Decodable {
        struct ImageInfo: Decodable {
            let url: URL?
        }

        let title: String
        let imageinfo: [ImageInfo]?
    }

    enum SearchError: LocalizedError {
        case invalidURL
        case invalidResponse
        case requestFailed(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The movie search URL could not be created."
            case .invalidResponse:
                return "The movie search service returned an unexpected response."
            case .requestFailed(let statusCode):
                return "The movie search failed with HTTP \(statusCode)."
            }
        }
    }

    func searchMovies(matching query: String) async throws -> [MediaSearchResult] {
        let sanitizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedQuery.isEmpty else {
            return []
        }

        let directCandidateTitles = directTitleCandidates(for: sanitizedQuery)
        let searchHits = (try? await fetchCombinedSearchHits(for: sanitizedQuery)) ?? []

        let candidateTitles = (directCandidateTitles + searchHits.map(\.title))
            .orderedUnique()

        guard !candidateTitles.isEmpty else {
            return []
        }

        let pageDetails = try await fetchPageDetails(for: Array(candidateTitles.prefix(18)))
        let likelyMovieDetails = pageDetails.values.filter(isLikelyMoviePage)
        let effectiveDetails = likelyMovieDetails.isEmpty ? Array(pageDetails.values) : likelyMovieDetails

        let imageNames = effectiveDetails
            .compactMap { $0.pageprops?.pageImage }
            .orderedUnique()
        let imageURLs = try await fetchImageURLs(for: imageNames)

        let expectedYear = extractYear(from: sanitizedQuery)
        let normalizedQuery = normalizedTitle(from: sanitizedQuery)

        return effectiveDetails
            .map { detail in
                buildResult(
                    from: detail,
                    imageURLs: imageURLs,
                    normalizedQuery: normalizedQuery,
                    expectedYear: expectedYear
                )
            }
            .sorted { lhs, rhs in lhs.matchScore > rhs.matchScore }
    }

    private func fetchCombinedSearchHits(for query: String) async throws -> [SearchHit] {
        let year = extractYear(from: query)
        let titleOnlyQuery = query.replacingOccurrences(
            of: #"\b(19|20)\d{2}\b"#,
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

        var searchQueries: [String] = []
        if let year {
            searchQueries.append("\(titleOnlyQuery) \(year) film")
        }

        searchQueries.append("\(titleOnlyQuery) film")
        searchQueries.append(titleOnlyQuery)

        var combined: [SearchHit] = []
        for searchQuery in searchQueries.orderedUnique() where !searchQuery.isEmpty {
            combined.append(contentsOf: try await fetchSearchHits(for: searchQuery))
        }

        return combined
    }

    private func fetchSearchHits(for query: String) async throws -> [SearchHit] {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: "12"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "origin", value: "*"),
        ]

        guard let url = components?.url else {
            throw SearchError.invalidURL
        }

        let response: SearchResponse = try await performRequest(url, decoding: SearchResponse.self)
        return response.query.search
    }

    private func fetchPageDetails(for titles: [String]) async throws -> [String: PageDetail] {
        guard !titles.isEmpty else {
            return [:]
        }

        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "titles", value: titles.joined(separator: "|")),
            URLQueryItem(name: "prop", value: "extracts|pageprops"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exchars", value: "1200"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "origin", value: "*"),
        ]

        guard let url = components?.url else {
            throw SearchError.invalidURL
        }

        let response: PageDetailsResponse = try await performRequest(url, decoding: PageDetailsResponse.self)
        let details = response.query.pages.values
            .filter { ($0.pageid ?? -1) > 0 }

        return Dictionary(uniqueKeysWithValues: details.map { ($0.title, $0) })
    }

    private func fetchImageURLs(for imageNames: [String]) async throws -> [String: URL] {
        guard !imageNames.isEmpty else {
            return [:]
        }

        let fileTitles = imageNames.map { "File:\($0)" }

        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "titles", value: fileTitles.joined(separator: "|")),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url"),
            URLQueryItem(name: "iilimit", value: "1"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "origin", value: "*"),
        ]

        guard let url = components?.url else {
            throw SearchError.invalidURL
        }

        let response: ImageInfoResponse = try await performRequest(url, decoding: ImageInfoResponse.self)

        var urlsByImageName: [String: URL] = [:]
        for page in response.query.pages.values {
            guard let firstURL = page.imageinfo?.first?.url else {
                continue
            }

            let filename = page.title.replacingOccurrences(of: "File:", with: "")
            urlsByImageName[normalizedImageName(filename)] = firstURL
        }

        return urlsByImageName
    }

    private func performRequest<Response: Decodable>(_ url: URL, decoding type: Response.Type) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = BoundedJSONRequest.timeoutInterval
        request.setValue(
            "MetaFetch/1.1 (macOS app for tagging MP4 movie files and TV episodes)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await BoundedJSONRequest.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SearchError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(Response.self, from: data)
    }

    private func buildResult(
        from detail: PageDetail,
        imageURLs: [String: URL],
        normalizedQuery: String,
        expectedYear: String?
    ) -> MediaSearchResult {
        let extract = detail.extract?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortDescription = detail.pageprops?.shortDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedYear = extractYear(from: shortDescription) ?? extractYear(from: extract)
        let parsedGenre = extractGenre(from: shortDescription ?? extract)
        let parsedDirector = extractDirector(from: extract)
        let releaseDate = parsedYear.map { "\($0)-01-01T00:00:00Z" }
        let imageURL = detail.pageprops?.pageImage.flatMap { imageURLs[normalizedImageName($0)] }
        let sourceURL = wikipediaURL(forPageID: detail.pageid, title: detail.title)

        let provisionalResult = MediaSearchResult(
            trackId: detail.pageid ?? detail.title.hashValue,
            mediaKind: .movie,
            trackName: detail.title,
            seriesName: nil,
            artistName: parsedDirector,
            releaseDate: releaseDate,
            primaryGenreName: parsedGenre,
            shortDescription: shortDescription,
            longDescription: extract,
            contentAdvisoryRating: nil,
            artworkURL: imageURL,
            sourceURL: sourceURL,
            sourceName: "Wikipedia",
            matchConfidence: .possible,
            matchSummary: "Possible movie page match",
            matchScore: 0,
            seasonNumber: nil,
            episodeNumber: nil
        )

        let evaluation = evaluateMatch(
            provisionalResult,
            normalizedQuery: normalizedQuery,
            expectedYear: expectedYear
        )

        return MediaSearchResult(
            trackId: provisionalResult.trackId,
            mediaKind: provisionalResult.mediaKind,
            trackName: provisionalResult.trackName,
            seriesName: provisionalResult.seriesName,
            artistName: provisionalResult.artistName,
            releaseDate: provisionalResult.releaseDate,
            primaryGenreName: provisionalResult.primaryGenreName,
            shortDescription: provisionalResult.shortDescription,
            longDescription: provisionalResult.longDescription,
            contentAdvisoryRating: provisionalResult.contentAdvisoryRating,
            artworkURL: provisionalResult.artworkURL,
            sourceURL: provisionalResult.sourceURL,
            sourceName: provisionalResult.sourceName,
            matchConfidence: evaluation.confidence,
            matchSummary: evaluation.summary,
            matchScore: evaluation.score,
            seasonNumber: nil,
            episodeNumber: nil
        )
    }

    private func evaluateMatch(
        _ result: MediaSearchResult,
        normalizedQuery: String,
        expectedYear: String?
    ) -> (score: Int, confidence: MatchConfidence, summary: String) {
        let normalizedResultTitle = normalizedTitle(from: result.trackName)
        var score = 0

        let exactTitle = normalizedResultTitle == normalizedQuery
        let partialTitle = !exactTitle && normalizedResultTitle.contains(normalizedQuery)

        if exactTitle {
            score += 120
        } else if partialTitle {
            score += 60
        }

        let combinedText = [
            result.trackName,
            result.shortDescription,
            result.longDescription,
            result.primaryGenreName,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        let filmSignals = combinedText.contains(" film")
            || combinedText.contains(" directed by ")
            || combinedText.contains(" starring ")
            || combinedText.contains(" stars ")

        if filmSignals {
            score += 40
        }

        let isLikelyNonMovie = combinedText.contains("franchise")
            || combinedText.contains("soundtrack")
            || combinedText.contains("novel")
            || combinedText.contains("video game")

        if isLikelyNonMovie {
            score -= 30
        }

        let yearMatches: Bool
        if let expectedYear,
           result.releaseYear == expectedYear || combinedText.contains(expectedYear) {
            score += 25
            yearMatches = true
        } else {
            yearMatches = false
        }

        if let genre = result.primaryGenreName?.lowercased(), genre.contains("film") {
            score += 10
        }

        let confidence: MatchConfidence
        if exactTitle && yearMatches {
            confidence = .exact
        } else if exactTitle && score >= 140 {
            confidence = .exact
        } else if score >= 95 {
            confidence = .strong
        } else {
            confidence = .possible
        }

        let summary: String
        if exactTitle && yearMatches {
            summary = "Exact title and year match"
        } else if exactTitle {
            summary = "Exact title match"
        } else if partialTitle && yearMatches {
            summary = "Strong title match with matching year"
        } else if partialTitle {
            summary = "Strong title match"
        } else if yearMatches {
            summary = "Film page with matching year"
        } else if filmSignals {
            summary = "Likely film page from search"
        } else {
            summary = "Possible movie page match"
        }

        return (score, confidence, summary)
    }

    private func directTitleCandidates(for query: String) -> [String] {
        let titleOnlyQuery = query.replacingOccurrences(
            of: #"\b(19|20)\d{2}\b"#,
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let year = extractYear(from: query)
        var candidates = [
            titleOnlyQuery,
            query,
            "\(titleOnlyQuery) (film)",
            "\(titleOnlyQuery) film",
        ]

        if let year, !titleOnlyQuery.isEmpty {
            candidates.append("\(titleOnlyQuery) (\(year) film)")
            candidates.append("\(titleOnlyQuery) (\(year) movie)")
        }

        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .orderedUnique()
    }

    private func extractYear(from text: String?) -> String? {
        guard let text else {
            return nil
        }

        return text.firstMatch(for: #"\b(19|20)\d{2}\b"#)
    }

    private func extractGenre(from text: String?) -> String? {
        guard let text else {
            return nil
        }

        let patterns = [
            #"\b(?:19|20)\d{2}\s+([A-Za-z][A-Za-z\s-]{0,60}?)\s+film\b"#,
            #"\bis an? ([A-Za-z][A-Za-z\s-]{0,60}?)\s+film\b"#,
        ]

        for pattern in patterns {
            if let match = text.firstCapture(for: pattern) {
                return match.cleanedMediaPhrase()
            }
        }

        return nil
    }

    private func extractDirector(from text: String?) -> String? {
        guard let text else {
            return nil
        }

        let patterns = [
            #"\bwritten and directed by ([^.;,]+)"#,
            #"\bdirected by ([^.;,]+)"#,
            #"\bfilm by ([^.;,]+)"#,
        ]

        for pattern in patterns {
            if let match = text.firstCapture(for: pattern) {
                return match.cleanedNamePhrase()
            }
        }

        return nil
    }

    private func isLikelyMoviePage(_ detail: PageDetail) -> Bool {
        let combinedText = [
            detail.title,
            detail.extract,
            detail.pageprops?.shortDescription,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return combinedText.contains(" film")
            || combinedText.contains(" directed by ")
            || combinedText.contains(" stars ")
            || combinedText.contains(" starring ")
    }

    private func wikipediaURL(forPageID pageID: Int?, title: String) -> URL? {
        if let pageID {
            return URL(string: "https://en.wikipedia.org/?curid=\(pageID)")
        }

        let encodedTitle = title
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)

        guard let encodedTitle else {
            return nil
        }

        return URL(string: "https://en.wikipedia.org/wiki/\(encodedTitle)")
    }
}

private struct TVMazeSearchService {
    private struct ShowSearchHit: Decodable {
        let score: Double
        let show: TVMazeShow
    }

    private struct TVMazeShow: Decodable {
        let id: Int
        let url: URL?
        let name: String
        let premiered: String?
        let summary: String?
        let genres: [String]
        let image: TVMazeImage?
        let network: TVMazeNetwork?
        let webChannel: TVMazeNetwork?
    }

    private struct TVMazeEpisode: Decodable {
        let id: Int
        let url: URL?
        let name: String
        let season: Int?
        let number: Int?
        let airdate: String?
        let summary: String?
        let image: TVMazeImage?
    }

    private struct TVMazeImage: Decodable {
        let medium: URL?
        let original: URL?
    }

    private struct TVMazeNetwork: Decodable {
        let name: String
    }

    enum SearchError: LocalizedError {
        case invalidURL
        case invalidResponse
        case requestFailed(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The TV show search URL could not be created."
            case .invalidResponse:
                return "The TV search service returned an unexpected response."
            case .requestFailed(let statusCode):
                return "The TV search failed with HTTP \(statusCode)."
            }
        }
    }

    func searchTV(matching query: String) async throws -> [MediaSearchResult] {
        let parsedQuery = FilenameTitleParser.parsedManualQuery(query, mode: .tvShow)
        let normalizedTitle = normalizedTitle(from: parsedQuery.title)

        guard !normalizedTitle.isEmpty else {
            return []
        }

        let hits = try await fetchShowMatches(for: parsedQuery.title)
        guard !hits.isEmpty else {
            return []
        }

        if parsedQuery.isEpisodeSpecific,
           let seasonNumber = parsedQuery.seasonNumber,
           let episodeNumber = parsedQuery.episodeNumber {
            let episodeMatches = try await fetchEpisodeMatches(
                from: Array(hits.prefix(6)),
                parsedQuery: parsedQuery,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber
            )

            if !episodeMatches.isEmpty {
                return episodeMatches.sorted { lhs, rhs in
                    if lhs.matchScore == rhs.matchScore {
                        return lhs.trackName < rhs.trackName
                    }

                    return lhs.matchScore > rhs.matchScore
                }
            }
        }

        return hits
            .prefix(10)
            .map { buildShowResult(from: $0, parsedQuery: parsedQuery) }
            .sorted { lhs, rhs in lhs.matchScore > rhs.matchScore }
    }

    private func fetchShowMatches(for title: String) async throws -> [ShowSearchHit] {
        var components = URLComponents(string: "https://api.tvmaze.com/search/shows")
        components?.queryItems = [
            URLQueryItem(name: "q", value: title),
        ]

        guard let url = components?.url else {
            throw SearchError.invalidURL
        }

        return try await performRequest(url, decoding: [ShowSearchHit].self)
    }

    private func fetchEpisodeMatches(
        from hits: [ShowSearchHit],
        parsedQuery: ParsedMediaQuery,
        seasonNumber: Int,
        episodeNumber: Int
    ) async throws -> [MediaSearchResult] {
        await withTaskGroup(of: MediaSearchResult?.self) { group in
            for hit in hits {
                group.addTask {
                    do {
                        guard let episode = try await fetchEpisode(
                            forShowID: hit.show.id,
                            seasonNumber: seasonNumber,
                            episodeNumber: episodeNumber
                        ) else {
                            return nil
                        }

                        return buildEpisodeResult(
                            episode: episode,
                            show: hit.show,
                            showScore: hit.score,
                            parsedQuery: parsedQuery
                        )
                    } catch {
                        return nil
                    }
                }
            }

            var matches: [MediaSearchResult] = []
            for await result in group {
                if let result {
                    matches.append(result)
                }
            }

            return matches
        }
    }

    private func fetchEpisode(
        forShowID showID: Int,
        seasonNumber: Int,
        episodeNumber: Int
    ) async throws -> TVMazeEpisode? {
        guard var components = URLComponents(string: "https://api.tvmaze.com/shows/\(showID)/episodebynumber") else {
            throw SearchError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "season", value: String(seasonNumber)),
            URLQueryItem(name: "number", value: String(episodeNumber)),
        ]

        guard let url = components.url else {
            throw SearchError.invalidURL
        }

        return try await performOptionalRequest(url, decoding: TVMazeEpisode.self)
    }

    private func performRequest<Response: Decodable>(_ url: URL, decoding type: Response.Type) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = BoundedJSONRequest.timeoutInterval
        request.setValue(
            "MetaFetch/1.1 (macOS app for tagging MP4 movie files and TV episodes)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await BoundedJSONRequest.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SearchError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func performOptionalRequest<Response: Decodable>(
        _ url: URL,
        decoding type: Response.Type
    ) async throws -> Response? {
        var request = URLRequest(url: url)
        request.timeoutInterval = BoundedJSONRequest.timeoutInterval
        request.setValue(
            "MetaFetch/1.1 (macOS app for tagging MP4 movie files and TV episodes)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await BoundedJSONRequest.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SearchError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func buildEpisodeResult(
        episode: TVMazeEpisode,
        show: TVMazeShow,
        showScore: Double,
        parsedQuery: ParsedMediaQuery
    ) -> MediaSearchResult {
        let normalizedShowName = normalizedTitle(from: show.name)
        let normalizedQuery = normalizedTitle(from: parsedQuery.title)
        let exactTitle = normalizedShowName == normalizedQuery
        let partialTitle = !exactTitle && normalizedShowName.contains(normalizedQuery)
        let yearMatches = parsedQuery.year == nil || show.premiered?.hasPrefix(parsedQuery.year ?? "") == true

        var score = Int(showScore * 30)
        if exactTitle {
            score += 120
        } else if partialTitle {
            score += 70
        }

        score += 80

        if yearMatches, parsedQuery.year != nil {
            score += 20
        }

        let confidence: MatchConfidence
        if exactTitle && yearMatches {
            confidence = .exact
        } else if exactTitle || partialTitle {
            confidence = .strong
        } else {
            confidence = .possible
        }

        let episodeCode = episodeCode(season: episode.season, episode: episode.number)
        let summary: String
        if exactTitle && yearMatches {
            summary = "Exact show + \(episodeCode ?? "episode") match"
        } else if exactTitle {
            summary = "Exact show match for \(episodeCode ?? "episode")"
        } else if partialTitle {
            summary = "Strong show match for \(episodeCode ?? "episode")"
        } else {
            summary = "Episode found on a likely matching series"
        }

        return MediaSearchResult(
            trackId: episode.id,
            mediaKind: .tvEpisode,
            trackName: episode.name.trimmedNilIfBlank ?? "\(show.name) \(episodeCode ?? "")".trimmedNilIfBlank ?? show.name,
            seriesName: show.name,
            artistName: show.network?.name ?? show.webChannel?.name,
            releaseDate: isoDate(from: episode.airdate),
            primaryGenreName: show.genres.joined(separator: ", ").trimmedNilIfBlank,
            shortDescription: episode.summary?.htmlStripped(),
            longDescription: (episode.summary?.htmlStripped()).trimmedNilIfBlank ?? show.summary?.htmlStripped(),
            contentAdvisoryRating: nil,
            artworkURL: episode.image?.original ?? episode.image?.medium ?? show.image?.original ?? show.image?.medium,
            sourceURL: episode.url ?? show.url,
            sourceName: "TVMaze",
            matchConfidence: confidence,
            matchSummary: summary,
            matchScore: score,
            seasonNumber: episode.season,
            episodeNumber: episode.number
        )
    }

    private func buildShowResult(from hit: ShowSearchHit, parsedQuery: ParsedMediaQuery) -> MediaSearchResult {
        let show = hit.show
        let normalizedShowName = normalizedTitle(from: show.name)
        let normalizedQuery = normalizedTitle(from: parsedQuery.title)
        let exactTitle = normalizedShowName == normalizedQuery
        let partialTitle = !exactTitle && normalizedShowName.contains(normalizedQuery)
        let yearMatches = parsedQuery.year == nil || show.premiered?.hasPrefix(parsedQuery.year ?? "") == true

        var score = Int(hit.score * 30)
        if exactTitle {
            score += 120
        } else if partialTitle {
            score += 60
        }

        if yearMatches, parsedQuery.year != nil {
            score += 20
        }

        let confidence: MatchConfidence
        if exactTitle && yearMatches {
            confidence = .exact
        } else if exactTitle || partialTitle {
            confidence = .strong
        } else {
            confidence = .possible
        }

        let summary: String
        if parsedQuery.isEpisodeSpecific, let episodeCode = parsedQuery.episodeCode {
            if exactTitle {
                summary = "Exact show match, but \(episodeCode) was not found"
            } else if partialTitle {
                summary = "Strong show match, but \(episodeCode) was not found"
            } else {
                summary = "Series match only. Try refining the show title or episode code."
            }
        } else if exactTitle && yearMatches {
            summary = "Exact show and year match"
        } else if exactTitle {
            summary = "Exact show match"
        } else if partialTitle {
            summary = "Strong show match"
        } else {
            summary = "Possible series match"
        }

        return MediaSearchResult(
            trackId: show.id,
            mediaKind: .tvSeries,
            trackName: show.name,
            seriesName: nil,
            artistName: show.network?.name ?? show.webChannel?.name,
            releaseDate: isoDate(from: show.premiered),
            primaryGenreName: show.genres.joined(separator: ", ").trimmedNilIfBlank,
            shortDescription: show.summary?.htmlStripped(),
            longDescription: show.summary?.htmlStripped(),
            contentAdvisoryRating: nil,
            artworkURL: show.image?.original ?? show.image?.medium,
            sourceURL: show.url,
            sourceName: "TVMaze",
            matchConfidence: confidence,
            matchSummary: summary,
            matchScore: score,
            seasonNumber: nil,
            episodeNumber: nil
        )
    }

    private func episodeCode(season: Int?, episode: Int?) -> String? {
        guard let season, let episode else {
            return nil
        }

        return String(format: "S%02dE%02d", season, episode)
    }

    private func isoDate(from shortDate: String?) -> String? {
        guard let shortDate = shortDate.trimmedNilIfBlank else {
            return nil
        }

        return "\(shortDate)T00:00:00Z"
    }
}

private extension Array where Element: Hashable {
    func orderedUnique() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

private extension MediaSearchResult {
    func withMatchEvaluation(
        _ evaluation: (score: Int, confidence: MatchConfidence, summary: String)
    ) -> MediaSearchResult {
        MediaSearchResult(
            trackId: trackId,
            mediaKind: mediaKind,
            trackName: trackName,
            seriesName: seriesName,
            artistName: artistName,
            releaseDate: releaseDate,
            primaryGenreName: primaryGenreName,
            shortDescription: shortDescription,
            longDescription: longDescription,
            contentAdvisoryRating: contentAdvisoryRating,
            artworkURL: artworkURL,
            sortTitle: sortTitle,
            sortSeriesName: sortSeriesName,
            sourceURL: sourceURL,
            sourceName: sourceName,
            matchConfidence: evaluation.confidence,
            matchSummary: evaluation.summary,
            matchScore: evaluation.score,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        )
    }
}

private extension Optional where Wrapped == String {
    var trimmedNilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}

private extension String {
    var trimmedNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfNA: String? {
        guard let trimmed = trimmedNilIfBlank,
              trimmed.uppercased() != "N/A" else {
            return nil
        }

        return trimmed
    }

    func firstMatch(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range),
              let matchRange = Range(match.range, in: self) else {
            return nil
        }

        return String(self[matchRange])
    }

    func firstCapture(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: self) else {
            return nil
        }

        return String(self[captureRange])
    }

    func cleanedMediaPhrase() -> String {
        replacingOccurrences(of: #"^\s*(american|british|english|french|german|italian|japanese|south korean|indian)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    func cleanedNamePhrase() -> String {
        let cleaned = replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.lowercased().hasPrefix("the ") {
            return "The " + cleaned.dropFirst(4)
        }

        return cleaned
    }

    func htmlStripped() -> String {
        replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func normalizedTitle(from text: String) -> String {
    text
        .lowercased()
        .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\b(19|20)\d{2}\b"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func extractYear(from text: String?) -> String? {
    text?.firstMatch(for: #"\b(19|20)\d{2}\b"#)
}

private func normalizedImageName(_ text: String) -> String {
    text
        .lowercased()
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func evaluateProviderMatch(
    _ result: MediaSearchResult,
    normalizedQuery: String,
    expectedYear: String?,
    sourceBonus: Int
) -> (score: Int, confidence: MatchConfidence, summary: String) {
    let normalizedResultTitle = normalizedTitle(from: result.trackName)
    let hasSearchTitle = !normalizedQuery.isEmpty
    var score = sourceBonus

    let exactTitle = hasSearchTitle && normalizedResultTitle == normalizedQuery
    let partialTitle = hasSearchTitle && !exactTitle && (
        normalizedResultTitle.contains(normalizedQuery)
        || normalizedQuery.contains(normalizedResultTitle)
    )

    if exactTitle {
        score += 120
    } else if partialTitle {
        score += 60
    }

    let combinedText = [
        result.trackName,
        result.shortDescription,
        result.longDescription,
        result.primaryGenreName,
        result.artistName,
    ]
    .compactMap { $0?.lowercased() }
    .joined(separator: " ")

    let yearMatches: Bool
    if let expectedYear,
       result.releaseYear == expectedYear || combinedText.contains(expectedYear) {
        score += 25
        yearMatches = true
    } else {
        yearMatches = false
    }

    if result.artworkURL != nil {
        score += 8
    }

    if result.longDescription.trimmedNilIfBlank != nil || result.shortDescription.trimmedNilIfBlank != nil {
        score += 10
    }

    if result.artistName.trimmedNilIfBlank != nil {
        score += 6
    }

    if result.primaryGenreName.trimmedNilIfBlank != nil {
        score += 6
    }

    let confidence: MatchConfidence
    if exactTitle && yearMatches {
        confidence = .exact
    } else if exactTitle && score >= 140 {
        confidence = .exact
    } else if score >= 95 {
        confidence = .strong
    } else {
        confidence = .possible
    }

    let summary: String
    if exactTitle && yearMatches {
        summary = "Exact \(result.sourceName) title and year match"
    } else if exactTitle {
        summary = "Exact \(result.sourceName) title match"
    } else if partialTitle && yearMatches {
        summary = "Strong \(result.sourceName) title match with matching year"
    } else if partialTitle {
        summary = "Strong \(result.sourceName) title match"
    } else if yearMatches {
        summary = "\(result.sourceName) result with matching year"
    } else {
        summary = "Possible \(result.sourceName) movie result"
    }

    return (score, confidence, summary)
}

private enum BoundedJSONRequest {
    static let timeoutInterval: TimeInterval = 15
    private static let maximumResponseBytes = 4 * 1024 * 1024

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if response.expectedContentLength > maximumResponseBytes {
            throw URLError(.dataLengthExceedsMaximum)
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumResponseBytes))
        }

        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumResponseBytes {
                throw URLError(.dataLengthExceedsMaximum)
            }
        }

        return (data, response)
    }
}
