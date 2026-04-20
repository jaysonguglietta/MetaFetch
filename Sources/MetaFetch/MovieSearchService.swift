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

struct MovieSearchResult: Hashable, Identifiable, Sendable {
    let trackId: Int
    let trackName: String
    let artistName: String?
    let releaseDate: String?
    let primaryGenreName: String?
    let shortDescription: String?
    let longDescription: String?
    let contentAdvisoryRating: String?
    let artworkUrl100: URL?
    let sourceName: String
    let matchConfidence: MatchConfidence
    let matchSummary: String
    let matchScore: Int

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

    var artworkURL: URL? {
        guard let artworkUrl100 else {
            return nil
        }

        let upgraded = artworkUrl100.absoluteString.replacingOccurrences(
            of: "100x100bb",
            with: "600x600bb"
        )

        return URL(string: upgraded) ?? artworkUrl100
    }

    var subtitleLine: String {
        [releaseYear, primaryGenreName, artistName]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " • ")
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
}

protocol MovieSearchServing: Sendable {
    func searchMovies(matching query: String) async throws -> [MovieSearchResult]
}

struct WikimediaMovieSearchService: MovieSearchServing {
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

    func searchMovies(matching query: String) async throws -> [MovieSearchResult] {
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
            URLQueryItem(name: "exchars", value: "600"),
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
        request.setValue(
            "MetaFetch/1.0 (macOS app for tagging MP4 movie files)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)

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
    ) -> MovieSearchResult {
        let extract = detail.extract?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortDescription = detail.pageprops?.shortDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedYear = extractYear(from: shortDescription) ?? extractYear(from: extract)
        let parsedGenre = extractGenre(from: shortDescription ?? extract)
        let parsedDirector = extractDirector(from: extract)
        let releaseDate = parsedYear.map { "\($0)-01-01T00:00:00Z" }
        let imageURL = detail.pageprops?.pageImage.flatMap { imageURLs[normalizedImageName($0)] }

        let provisionalResult = MovieSearchResult(
            trackId: detail.pageid ?? detail.title.hashValue,
            trackName: detail.title,
            artistName: parsedDirector,
            releaseDate: releaseDate,
            primaryGenreName: parsedGenre,
            shortDescription: shortDescription,
            longDescription: extract,
            contentAdvisoryRating: nil,
            artworkUrl100: imageURL,
            sourceName: "Wikipedia",
            matchConfidence: .possible,
            matchSummary: "Possible movie page match",
            matchScore: 0
        )

        let evaluation = evaluateMatch(
            provisionalResult,
            normalizedQuery: normalizedQuery,
            expectedYear: expectedYear
        )

        return MovieSearchResult(
            trackId: provisionalResult.trackId,
            trackName: provisionalResult.trackName,
            artistName: provisionalResult.artistName,
            releaseDate: provisionalResult.releaseDate,
            primaryGenreName: provisionalResult.primaryGenreName,
            shortDescription: provisionalResult.shortDescription,
            longDescription: provisionalResult.longDescription,
            contentAdvisoryRating: provisionalResult.contentAdvisoryRating,
            artworkUrl100: provisionalResult.artworkUrl100,
            sourceName: provisionalResult.sourceName,
            matchConfidence: evaluation.confidence,
            matchSummary: evaluation.summary,
            matchScore: evaluation.score
        )
    }

    private func evaluateMatch(
        _ result: MovieSearchResult,
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

    private func normalizedTitle(from text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(19|20)\d{2}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedImageName(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

private extension Array where Element: Hashable {
    func orderedUnique() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
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
}
