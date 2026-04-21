import Foundation

struct ParsedMediaQuery: Equatable, Sendable {
    let mode: MediaLibraryMode
    let title: String
    let year: String?
    let seasonNumber: Int?
    let episodeNumber: Int?

    var episodeCode: String? {
        guard let seasonNumber, let episodeNumber else {
            return nil
        }

        return String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }

    var isEpisodeSpecific: Bool {
        seasonNumber != nil && episodeNumber != nil
    }

    var suggestedSearchText: String {
        switch mode {
        case .movie:
            return [title.nilIfBlank]
                .compactMap { $0 }
                .joined(separator: " ")
        case .tvShow:
            return [title.nilIfBlank, year?.nilIfBlank, episodeCode]
                .compactMap { $0?.nilIfBlank }
                .joined(separator: " ")
        }
    }
}

enum FilenameTitleParser {
    private static let junkTokens: Set<String> = [
        "10bit", "2160p", "4k", "480p", "720p", "1080p",
        "aac", "ac3", "atmos", "bdrip", "bluray", "blu", "ray",
        "brrip", "ddp", "ddp5", "director", "directors", "dubbed",
        "dv", "dvdrip", "extended", "hdr", "hevc", "h264", "h265",
        "limited", "proper", "rarbg", "remastered", "repack",
        "subs", "uncut", "webrip", "web", "webdl", "web-dl",
        "x264", "x265", "yify"
    ]

    static func suggestedQuery(from filename: String, mode: MediaLibraryMode) -> String {
        parsedQuery(fromFilename: filename, mode: mode).suggestedSearchText
    }

    static func suggestedQuery(fromFileURL fileURL: URL, mode: MediaLibraryMode) -> String {
        parsedQuery(fromFileURL: fileURL, mode: mode).suggestedSearchText
    }

    static func parsedQuery(fromFilename filename: String, mode: MediaLibraryMode) -> ParsedMediaQuery {
        parse(source: filename, mode: mode, removesFileExtension: true)
    }

    static func parsedQuery(fromFileURL fileURL: URL, mode: MediaLibraryMode) -> ParsedMediaQuery {
        let fileQuery = parsedQuery(fromFilename: fileURL.lastPathComponent, mode: mode)
        guard mode == .tvShow else {
            return fileQuery
        }

        let folderContext = tvFolderContext(for: fileURL.deletingLastPathComponent())
        let title = isGenericEpisodeTitle(fileQuery.title)
            ? (folderContext.title ?? fileQuery.title)
            : fileQuery.title

        return ParsedMediaQuery(
            mode: mode,
            title: title,
            year: fileQuery.year,
            seasonNumber: fileQuery.seasonNumber ?? folderContext.seasonNumber,
            episodeNumber: fileQuery.episodeNumber
        )
    }

    static func parsedManualQuery(_ query: String, mode: MediaLibraryMode) -> ParsedMediaQuery {
        parse(source: query, mode: mode, removesFileExtension: false)
    }

    private static func parse(
        source: String,
        mode: MediaLibraryMode,
        removesFileExtension: Bool
    ) -> ParsedMediaQuery {
        let basename: String
        if removesFileExtension {
            basename = URL(fileURLWithPath: source)
                .deletingPathExtension()
                .lastPathComponent
        } else {
            basename = source
        }

        let preservedYears = basename.replacingOccurrences(
            of: #"[\(\[\{]((19|20)\d{2})[\)\]\}]"#,
            with: " $1 ",
            options: .regularExpression
        )

        let strippedGroups = preservedYears.replacingOccurrences(
            of: #"\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\}"#,
            with: " ",
            options: .regularExpression
        )

        let normalizedSeparators = strippedGroups
            .replacingOccurrences(of: #"[._]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s-\s"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedSeparators.isEmpty else {
            return ParsedMediaQuery(
                mode: mode,
                title: basename,
                year: nil,
                seasonNumber: nil,
                episodeNumber: nil
            )
        }

        let rawTokens = normalizedSeparators.split(whereSeparator: \.isWhitespace).map(String.init)
        var keptTokens: [String] = []
        var detectedYear: String?
        var detectedSeason = parseSeasonNumber(from: normalizedSeparators)
        var detectedEpisode = parseEpisodePhrase(from: normalizedSeparators)
        var encounteredEpisodeToken = false

        for token in rawTokens {
            let cleaned = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !cleaned.isEmpty else {
                continue
            }

            let lowercaseToken = cleaned.lowercased()

            if let episodeMarker = parseEpisodeMarker(from: lowercaseToken) {
                detectedSeason = detectedSeason ?? episodeMarker.season
                detectedEpisode = detectedEpisode ?? episodeMarker.episode
                encounteredEpisodeToken = true

                if mode == .movie {
                    break
                }

                continue
            }

            if mode == .tvShow,
               ["episode", "ep"].contains(lowercaseToken) {
                encounteredEpisodeToken = true
                continue
            }

            if isYear(lowercaseToken) {
                detectedYear = detectedYear ?? cleaned
                continue
            }

            if isNoise(lowercaseToken) {
                continue
            }

            if encounteredEpisodeToken {
                continue
            }

            keptTokens.append(cleaned)
        }

        if let detectedYear, mode == .movie || detectedSeason == nil {
            keptTokens.append(detectedYear)
        }

        let query = keptTokens.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fallbackTitle = query.isEmpty ? normalizedSeparators : query

        return ParsedMediaQuery(
            mode: mode,
            title: fallbackTitle,
            year: detectedYear,
            seasonNumber: detectedSeason,
            episodeNumber: detectedEpisode
        )
    }

    private static func tvFolderContext(for directoryURL: URL) -> (title: String?, seasonNumber: Int?) {
        let parent = directoryURL.lastPathComponent
        let grandparent = directoryURL.deletingLastPathComponent().lastPathComponent
        let parentSeason = parseSeasonNumber(from: parent)
        let grandparentSeason = parseSeasonNumber(from: grandparent)
        let parentTitle = cleanedFolderTitle(parent)
        let grandparentTitle = cleanedFolderTitle(grandparent)

        if isGenericSeasonFolder(parent), let grandparentTitle {
            return (grandparentTitle, parentSeason ?? grandparentSeason)
        }

        return (parentTitle ?? grandparentTitle, parentSeason ?? grandparentSeason)
    }

    private static func parseEpisodeMarker(from token: String) -> (season: Int?, episode: Int)? {
        let patterns = [
            #"^s(\d{1,2})e(\d{1,2})$"#,
            #"^(\d{1,2})x(\d{1,2})$"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(token.startIndex..<token.endIndex, in: token)
            guard let match = regex.firstMatch(in: token, options: [], range: range),
                  match.numberOfRanges == 3,
                  let seasonRange = Range(match.range(at: 1), in: token),
                  let episodeRange = Range(match.range(at: 2), in: token),
                  let season = Int(token[seasonRange]),
                  let episode = Int(token[episodeRange]) else {
                continue
            }

            return (season, episode)
        }

        if let episode = token.firstCaptureInt(for: #"^e(\d{1,3})$"#) {
            return (nil, episode)
        }

        return nil
    }

    private static func parseEpisodePhrase(from text: String) -> Int? {
        text.firstCaptureInt(for: #"\b(?:episode|ep)\s*(\d{1,3})\b"#)
    }

    private static func parseSeasonNumber(from text: String) -> Int? {
        let patterns = [
            #"\bs(?:eason)?\s*(\d{1,2})\b"#,
            #"\bseason\s+(\d{1,2})\b"#,
        ]

        for pattern in patterns {
            if let season = text.firstCaptureInt(for: pattern) {
                return season
            }
        }

        return nil
    }

    private static func cleanedFolderTitle(_ title: String) -> String? {
        let cleaned = title
            .replacingOccurrences(of: #"[._]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\bseason\s*\d{1,2}\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bs\d{1,2}\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty, !isGenericSeasonFolder(cleaned) else {
            return nil
        }

        return cleaned
    }

    private static func isGenericSeasonFolder(_ title: String) -> Bool {
        title.lowercased().range(
            of: #"^(season\s*\d{1,2}|s\d{1,2})$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isGenericEpisodeTitle(_ title: String) -> Bool {
        let normalized = title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return true
        }

        return normalized.range(
            of: #"^(episode|ep|episode \d{1,3}|ep \d{1,3}|e?\d{1,3}|s\d{1,2}e\d{1,3})$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isYear(_ token: String) -> Bool {
        guard token.range(of: #"^(19|20)\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }

        return true
    }

    private static func isNoise(_ token: String) -> Bool {
        if junkTokens.contains(token) {
            return true
        }

        if token.range(of: #"^\d{3,4}p$"#, options: .regularExpression) != nil {
            return true
        }

        if token.range(of: #"^(x|h)\d{3}$"#, options: .regularExpression) != nil {
            return true
        }

        if token.range(of: #"^\d{1,2}bit$"#, options: .regularExpression) != nil {
            return true
        }

        if token.range(of: #"^ddp\d(?:\d)?$"#, options: .regularExpression) != nil {
            return true
        }

        if token.range(of: #"^\d\.\d$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func firstCaptureInt(for pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: self) else {
            return nil
        }

        return Int(self[captureRange])
    }
}
