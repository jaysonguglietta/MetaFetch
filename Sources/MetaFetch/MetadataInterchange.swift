import Foundation

struct MetadataInterchangeDocument: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var schema: Int = schemaVersion
    var mediaKind: String
    var title: String
    var seriesName: String?
    var creator: String?
    var genre: String?
    var releaseDate: String?
    var synopsis: String?
    var sortTitle: String?
    var sortSeriesName: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var contentRating: String?
    var communityRating: Double?
    var externalIDs: MediaExternalIDs

    init(
        schema: Int = MetadataInterchangeDocument.schemaVersion,
        mediaKind: String,
        title: String,
        seriesName: String? = nil,
        creator: String? = nil,
        genre: String? = nil,
        releaseDate: String? = nil,
        synopsis: String? = nil,
        sortTitle: String? = nil,
        sortSeriesName: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        contentRating: String? = nil,
        communityRating: Double? = nil,
        externalIDs: MediaExternalIDs = MediaExternalIDs()
    ) {
        self.schema = schema
        self.mediaKind = mediaKind
        self.title = title
        self.seriesName = seriesName
        self.creator = creator
        self.genre = genre
        self.releaseDate = releaseDate
        self.synopsis = synopsis
        self.sortTitle = sortTitle
        self.sortSeriesName = sortSeriesName
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.contentRating = contentRating
        self.communityRating = communityRating
        self.externalIDs = externalIDs
    }

    init(draft: MetadataDraft, result: MediaSearchResult) {
        let applied = draft.applying(to: result)
        mediaKind = applied.mediaKind.rawValue
        title = applied.trackName
        seriesName = applied.seriesName
        creator = applied.creatorValue
        genre = applied.primaryGenreName
        releaseDate = applied.releaseDate
        synopsis = applied.persistableSynopsis
        sortTitle = applied.sortTitle
        sortSeriesName = applied.sortSeriesName
        seasonNumber = applied.seasonNumber
        episodeNumber = applied.episodeNumber
        contentRating = applied.contentAdvisoryRating
        communityRating = applied.communityRating
        externalIDs = applied.externalIDs
    }

    func applying(to draft: inout MetadataDraft) {
        draft.title = title
        draft.seriesName = seriesName ?? ""
        draft.creator = creator ?? ""
        draft.genre = genre ?? ""
        draft.year = releaseDate ?? ""
        draft.synopsis = synopsis ?? ""
        draft.sortTitle = sortTitle ?? title
        draft.sortSeriesName = sortSeriesName ?? seriesName ?? ""
        draft.seasonNumber = seasonNumber.map(String.init) ?? ""
        draft.episodeNumber = episodeNumber.map(String.init) ?? ""
        draft.contentRating = contentRating ?? ""
        draft.communityRating = communityRating.map { String(format: "%.1f", $0) } ?? ""
        draft.imdbID = externalIDs.imdb ?? ""
        draft.tmdbID = externalIDs.tmdb.map(String.init) ?? ""
        draft.tvmazeID = externalIDs.tvmaze.map(String.init) ?? ""
    }
}

enum MetadataInterchange {
    enum InterchangeError: LocalizedError {
        case fileTooLarge
        case unsupportedFormat
        case malformedNFO
        case missingTitle

        var errorDescription: String? {
            switch self {
            case .fileTooLarge: "The metadata file exceeds the 1 MB safety limit."
            case .unsupportedFormat: "Choose a MetaFetch JSON or Kodi-compatible NFO file."
            case .malformedNFO: "The NFO file could not be parsed safely."
            case .missingTitle: "The metadata file does not contain a title."
            }
        }
    }

    private static let maximumBytes = 1_000_000

    static func jsonData(for document: MetadataInterchangeDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func nfoData(for document: MetadataInterchangeDocument) -> Data {
        let root = document.mediaKind == MediaSearchKind.movie.rawValue ? "movie" : "episodedetails"
        var fields: [(String, String?)] = [
            ("title", document.title),
            ("showtitle", document.seriesName),
            ("sorttitle", document.sortTitle),
            ("studio", document.creator),
            ("genre", document.genre),
            ("premiered", document.releaseDate.map { String($0.prefix(10)) }),
            ("plot", document.synopsis),
            ("mpaa", document.contentRating),
            ("rating", document.communityRating.map { String($0) }),
            ("season", document.seasonNumber.map(String.init)),
            ("episode", document.episodeNumber.map(String.init)),
            ("imdbid", document.externalIDs.imdb),
            ("tmdbid", document.externalIDs.tmdb.map(String.init)),
            ("tvmazeid", document.externalIDs.tvmaze.map(String.init)),
        ]
        fields.removeAll { $0.1?.isEmpty != false }
        let body = fields.map { "  <\($0.0)>\(xmlEscaped($0.1 ?? ""))</\($0.0)>" }.joined(separator: "\n")
        return Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<\(root)>\n\(body)\n</\(root)>\n".utf8)
    }

    static func load(from url: URL) throws -> MetadataInterchangeDocument {
        guard url.isFileURL, ["json", "nfo", "xml"].contains(url.pathExtension.lowercased()) else {
            throw InterchangeError.unsupportedFormat
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw InterchangeError.unsupportedFormat
        }
        guard (values.fileSize ?? 0) <= maximumBytes else { throw InterchangeError.fileTooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw InterchangeError.fileTooLarge }

        switch url.pathExtension.lowercased() {
        case "json":
            return try JSONDecoder().decode(MetadataInterchangeDocument.self, from: data)
        case "nfo", "xml":
            return try parseNFO(data)
        default:
            throw InterchangeError.unsupportedFormat
        }
    }

    private static func parseNFO(_ data: Data) throws -> MetadataInterchangeDocument {
        let delegate = SafeNFOParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw InterchangeError.malformedNFO }
        guard let title = delegate.values["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { throw InterchangeError.missingTitle }
        return MetadataInterchangeDocument(
            schema: MetadataInterchangeDocument.schemaVersion,
            mediaKind: delegate.root == "movie" ? MediaSearchKind.movie.rawValue : MediaSearchKind.tvEpisode.rawValue,
            title: title,
            seriesName: delegate.values["showtitle"],
            creator: delegate.values["studio"],
            genre: delegate.values["genre"],
            releaseDate: delegate.values["premiered"],
            synopsis: delegate.values["plot"],
            sortTitle: delegate.values["sorttitle"],
            sortSeriesName: nil,
            seasonNumber: delegate.values["season"].flatMap(Int.init),
            episodeNumber: delegate.values["episode"].flatMap(Int.init),
            contentRating: delegate.values["mpaa"],
            communityRating: delegate.values["rating"].flatMap(Double.init),
            externalIDs: MediaExternalIDs(
                imdb: delegate.values["imdbid"],
                tmdb: delegate.values["tmdbid"].flatMap(Int.init),
                tvmaze: delegate.values["tvmazeid"].flatMap(Int.init)
            )
        )
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private final class SafeNFOParserDelegate: NSObject, XMLParserDelegate {
    private let allowedFields: Set<String> = [
        "title", "showtitle", "sorttitle", "studio", "genre", "premiered", "plot",
        "mpaa", "rating", "season", "episode", "imdbid", "tmdbid", "tvmazeid",
    ]
    var root: String?
    var values: [String: String] = [:]
    private var currentField: String?
    private var buffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if root == nil { root = elementName.lowercased() }
        let field = elementName.lowercased()
        currentField = allowedFields.contains(field) ? field : nil
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentField != nil, buffer.count < 100_000 else { return }
        buffer += String(string.prefix(100_000 - buffer.count))
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let field = elementName.lowercased()
        if currentField == field {
            values[field] = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        currentField = nil
        buffer = ""
    }

    func parser(
        _ parser: XMLParser,
        resolveExternalEntityName name: String,
        systemID: String?
    ) -> Data? {
        nil
    }
}
