import Foundation

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

    static func suggestedQuery(from filename: String) -> String {
        let basename = URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent

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
            return basename
        }

        let rawTokens = normalizedSeparators.split(whereSeparator: \.isWhitespace).map(String.init)
        var keptTokens: [String] = []
        var detectedYear: String?

        for token in rawTokens {
            let cleaned = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !cleaned.isEmpty else {
                continue
            }

            let lowercaseToken = cleaned.lowercased()

            if lowercaseToken.range(of: #"^s\d{1,2}e\d{1,2}$"#, options: .regularExpression) != nil {
                break
            }

            if isYear(lowercaseToken) {
                detectedYear = detectedYear ?? cleaned
                continue
            }

            if isNoise(lowercaseToken) {
                continue
            }

            keptTokens.append(cleaned)
        }

        if let detectedYear {
            keptTokens.append(detectedYear)
        }

        let query = keptTokens.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return query.isEmpty ? normalizedSeparators : query
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
