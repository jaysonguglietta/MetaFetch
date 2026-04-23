import Foundation
import Testing
@testable import MetaFetch

@Test func appIsRenamedMetaFetch() async throws {
    #expect(String(describing: MetaFetchApp.self) == "MetaFetchApp")
}

@Test func stripsReleaseNoiseAndKeepsYear() async throws {
    let query = FilenameTitleParser.suggestedQuery(
        from: "The.Matrix.1999.1080p.BluRay.x264.mp4",
        mode: .movie
    )

    #expect(query == "The Matrix 1999")
}

@Test func removesBracketedJunkAndPreservesMeaningfulWords() async throws {
    let query = FilenameTitleParser.suggestedQuery(
        from: "[YTS] Mad.Max.Fury.Road.(2015).WEB-DL.H264.mp4",
        mode: .movie
    )

    #expect(query == "Mad Max Fury Road 2015")
}

@Test func movieModeStopsAtEpisodeMarkers() async throws {
    let query = FilenameTitleParser.suggestedQuery(
        from: "Some.Show.S01E03.1080p.WEBRip.mp4",
        mode: .movie
    )

    #expect(query == "Some Show")
}

@Test func tvModePreservesEpisodeMarkers() async throws {
    let query = FilenameTitleParser.suggestedQuery(
        from: "Some.Show.S01E03.1080p.WEBRip.mp4",
        mode: .tvShow
    )

    #expect(query == "Some Show S01E03")
}

@Test func tvModeNormalizesAlternateEpisodeNotation() async throws {
    let query = FilenameTitleParser.suggestedQuery(
        from: "Severance.2x07.2160p.WEB-DL.mp4",
        mode: .tvShow
    )

    #expect(query == "Severance S02E07")
}

@Test func tvModeUsesFolderContextForGenericEpisodeFilenames() async throws {
    let url = URL(fileURLWithPath: "/Shows/Severance/Season 2/Episode 04.mp4")
    let query = FilenameTitleParser.suggestedQuery(fromFileURL: url, mode: .tvShow)

    #expect(query == "Severance S02E04")
}

@Test func tvModeUsesCombinedFolderSeasonName() async throws {
    let url = URL(fileURLWithPath: "/Shows/Severance Season 2/E04.mp4")
    let query = FilenameTitleParser.suggestedQuery(fromFileURL: url, mode: .tvShow)

    #expect(query == "Severance S02E04")
}

@Test func autoSelectsOnlyClearExactMatch() async throws {
    let exact = makeResult(
        id: 1,
        title: "The Matrix",
        year: "1999",
        confidence: MatchConfidence.exact,
        summary: "Exact title and year match",
        score: 185
    )
    let runnerUp = makeResult(
        id: 2,
        title: "The Matrix Reloaded",
        year: "2003",
        confidence: MatchConfidence.strong,
        summary: "Strong title match",
        score: 120
    )

    let selection = SearchSelectionPolicy.suggestedAutoSelection(from: [exact, runnerUp])

    #expect(selection?.id == exact.id)
}

@Test func doesNotAutoSelectWhenTopMatchIsNotExact() async throws {
    let strong = makeResult(
        id: 1,
        title: "Heat",
        year: "1995",
        confidence: MatchConfidence.strong,
        summary: "Strong title match with matching year",
        score: 120
    )
    let possible = makeResult(
        id: 2,
        title: "Heat Wave",
        year: "1990",
        confidence: MatchConfidence.possible,
        summary: "Possible movie page match",
        score: 60
    )

    let selection = SearchSelectionPolicy.suggestedAutoSelection(from: [strong, possible])

    #expect(selection == nil)
}

@Test func doesNotAutoSelectWhenExactMatchIsTooCloseToRunnerUp() async throws {
    let top = makeResult(
        id: 1,
        title: "Crash",
        year: "2004",
        confidence: MatchConfidence.exact,
        summary: "Exact title and year match",
        score: 145
    )
    let closeRunnerUp = makeResult(
        id: 2,
        title: "Crash",
        year: "1996",
        confidence: MatchConfidence.strong,
        summary: "Exact title match",
        score: 122
    )

    let selection = SearchSelectionPolicy.suggestedAutoSelection(from: [top, closeRunnerUp])

    #expect(selection == nil)
}

@Test
@MainActor
func episodeSpecificTVSearchDoesNotAutoSelectSeriesFallback() async throws {
    let seriesOnlyResult = makeResult(
        id: 101,
        title: "Severance",
        year: "2022",
        mediaKind: .tvSeries,
        confidence: .exact,
        summary: "Exact show match, but S02E04 was not found",
        score: 150
    )
    let model = AppModel(searchService: StubSearchService(results: [seriesOnlyResult]))
    let entry = MovieFileEntry(
        fileURL: URL(fileURLWithPath: "/Shows/Severance/Severance.S02E04.mp4"),
        mediaMode: .tvShow
    )
    entry.queryText = "Severance S02E04"

    await model.search(file: entry)

    #expect(entry.selectedResult == nil)
    #expect(entry.statusMessage == "No exact episode found. Showing the closest series matches instead.")
}

@Test
@MainActor
func seriesOnlyEpisodeSelectionRequiresConfirmationBeforeSave() async throws {
    let seriesOnlyResult = makeResult(
        id: 101,
        title: "Severance",
        year: "2022",
        mediaKind: .tvSeries,
        confidence: .exact,
        summary: "Exact show match, but S02E04 was not found",
        score: 150
    )
    let entry = MovieFileEntry(
        fileURL: URL(fileURLWithPath: "/Shows/Severance/Severance.S02E04.mp4"),
        mediaMode: .tvShow
    )
    entry.queryText = "Severance S02E04"
    entry.selectedResult = seriesOnlyResult

    #expect(entry.requiresSeriesOnlySaveConfirmation)
    #expect(!entry.canSave)

    entry.allowsSeriesOnlySave = true

    #expect(!entry.requiresSeriesOnlySaveConfirmation)
    #expect(entry.canSave)

    entry.queryText = "Severance S02E05"

    #expect(entry.requiresSeriesOnlySaveConfirmation)
    #expect(!entry.canSave)
}

@Test func importValidatorRequiresWritableRegularMP4Files() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MetaFetchTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let validMP4 = directory.appendingPathComponent("Movie.mp4")
    FileManager.default.createFile(atPath: validMP4.path, contents: Data([0x00]))

    let wrongExtension = directory.appendingPathComponent("Movie.mov")
    FileManager.default.createFile(atPath: wrongExtension.path, contents: Data([0x00]))

    let symlink = directory.appendingPathComponent("Linked.mp4")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: validMP4)

    #expect(MediaFileImportValidator.validatedImportURL(validMP4) != nil)
    #expect(MediaFileImportValidator.validatedImportURL(wrongExtension) == nil)
    #expect(MediaFileImportValidator.validatedImportURL(symlink) == nil)
    #expect(MediaFileImportValidator.validatedImportURL(URL(string: "https://example.com/movie.mp4")!) == nil)
}

@Test func nativeAtomWriterWritesMetadataIntoExistingHeadroom() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MetaFetchAtomTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let fileURL = directory.appendingPathComponent("The.Audacity.S01E03.mp4")
    var mp4 = Data()
    mp4.append(makeTestAtom("ftyp", payload: Data("isom0000".utf8)))
    mp4.append(makeTestAtom("moov", payload: Data()))
    mp4.append(makeTestAtom("free", payload: Data(count: 4096)))
    mp4.append(makeTestAtom("mdat", payload: Data()))
    try mp4.write(to: fileURL)
    let originalSize = try Data(contentsOf: fileURL).count

    let result = MediaSearchResult(
        trackId: 303,
        mediaKind: .tvEpisode,
        trackName: "Episode Three",
        seriesName: "The Audacity",
        artistName: "Test Network",
        releaseDate: "2026-04-20T00:00:00Z",
        primaryGenreName: "Drama",
        shortDescription: "A test episode.",
        longDescription: "A test episode for MP4 atom writing.",
        contentAdvisoryRating: "TV-14",
        artworkURL: nil,
        sourceURL: nil,
        sourceName: "TVMaze",
        matchConfidence: .exact,
        matchSummary: "Exact episode match",
        matchScore: 200,
        seasonNumber: 1,
        episodeNumber: 3
    )

    try await MP4AtomMetadataWriter().writeMetadata(
        to: fileURL,
        using: result,
        artworkData: nil
    )

    let taggedData = try Data(contentsOf: fileURL)
    #expect(taggedData.count == originalSize)
    #expect(taggedData.range(of: Data([0xA9, 0x6E, 0x61, 0x6D])) != nil)
    #expect(taggedData.range(of: Data("Episode Three".utf8)) != nil)
    #expect(taggedData.range(of: Data("tvsh".utf8)) != nil)
    #expect(taggedData.range(of: Data("The Audacity".utf8)) != nil)
    #expect(taggedData.range(of: Data("tvsn".utf8)) != nil)
    #expect(taggedData.range(of: Data("tves".utf8)) != nil)
    #expect(try MP4AtomMetadataWriter().metadataWasPersisted(at: fileURL, result: result))
}

@Test
@MainActor
func applyingBatchShowKeepsEachDetectedEpisodeCode() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MetaFetchBatchTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let firstEpisode = directory.appendingPathComponent("Wrong.Show.S01E03.mp4")
    let secondEpisode = directory.appendingPathComponent("Wrong.Show.S01E04.mp4")
    FileManager.default.createFile(atPath: firstEpisode.path, contents: Data([0x00]))
    FileManager.default.createFile(atPath: secondEpisode.path, contents: Data([0x00]))

    let showResult = makeResult(
        id: 303,
        title: "The Audacity",
        year: "2026",
        mediaKind: .tvSeries,
        confidence: .exact,
        summary: "Exact show match",
        score: 200
    )
    let model = AppModel(searchService: StubSearchService(results: [showResult]))
    model.chooseMode(.tvShow)
    model.importFiles(from: [firstEpisode, secondEpisode])

    await model.applyBatchResultToAllFiles(showResult)

    #expect(model.files.map(\.queryText) == [
        "The Audacity S01E03",
        "The Audacity S01E04",
    ])
}

private func makeResult(
    id: Int,
    title: String,
    year: String,
    mediaKind: MediaSearchKind = .movie,
    confidence: MatchConfidence,
    summary: String,
    score: Int
) -> MediaSearchResult {
    MediaSearchResult(
        trackId: id,
        mediaKind: mediaKind,
        trackName: title,
        seriesName: nil,
        artistName: "Test Director",
        releaseDate: "\(year)-01-01T00:00:00Z",
        primaryGenreName: "Science fiction film",
        shortDescription: "Test film",
        longDescription: "Test film directed by Test Director.",
        contentAdvisoryRating: nil,
        artworkURL: nil,
        sourceURL: nil,
        sourceName: "Wikipedia",
        matchConfidence: confidence,
        matchSummary: summary,
        matchScore: score,
        seasonNumber: nil,
        episodeNumber: nil
    )
}

private func makeTestAtom(_ type: String, payload: Data) -> Data {
    var data = Data()
    data.append(makeTestUInt32Data(UInt32(payload.count + 8)))
    data.append(Data(type.utf8))
    data.append(payload)
    return data
}

private func makeTestUInt32Data(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

private struct StubSearchService: MediaSearchServing {
    let results: [MediaSearchResult]

    func search(matching query: String, mode: MediaLibraryMode) async throws -> [MediaSearchResult] {
        results
    }
}
