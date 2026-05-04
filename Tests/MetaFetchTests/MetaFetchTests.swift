import Foundation
import XCTest
@testable import MetaFetch

final class MetaFetchTests: XCTestCase {
    func testAppIsRenamedMetaFetch() async throws {
        XCTAssertEqual(String(describing: MetaFetchApp.self), "MetaFetchApp")
    }

    func testStripsReleaseNoiseAndKeepsYear() async throws {
        let query = FilenameTitleParser.suggestedQuery(
            from: "The.Matrix.1999.1080p.BluRay.x264.mp4",
            mode: .movie
        )

        XCTAssertEqual(query, "The Matrix 1999")
    }

    func testRemovesBracketedJunkAndPreservesMeaningfulWords() async throws {
        let query = FilenameTitleParser.suggestedQuery(
            from: "[YTS] Mad.Max.Fury.Road.(2015).WEB-DL.H264.mp4",
            mode: .movie
        )

        XCTAssertEqual(query, "Mad Max Fury Road 2015")
    }

    func testMovieModeStopsAtEpisodeMarkers() async throws {
        let query = FilenameTitleParser.suggestedQuery(
            from: "Some.Show.S01E03.1080p.WEBRip.mp4",
            mode: .movie
        )

        XCTAssertEqual(query, "Some Show")
    }

    func testTVModePreservesEpisodeMarkers() async throws {
        let query = FilenameTitleParser.suggestedQuery(
            from: "Some.Show.S01E03.1080p.WEBRip.mp4",
            mode: .tvShow
        )

        XCTAssertEqual(query, "Some Show S01E03")
    }

    func testTVModeNormalizesAlternateEpisodeNotation() async throws {
        let query = FilenameTitleParser.suggestedQuery(
            from: "Severance.2x07.2160p.WEB-DL.mp4",
            mode: .tvShow
        )

        XCTAssertEqual(query, "Severance S02E07")
    }

    func testTVModeUsesFolderContextForGenericEpisodeFilenames() async throws {
        let url = URL(fileURLWithPath: "/Shows/Severance/Season 2/Episode 04.mp4")
        let query = FilenameTitleParser.suggestedQuery(fromFileURL: url, mode: .tvShow)

        XCTAssertEqual(query, "Severance S02E04")
    }

    func testTVModeUsesCombinedFolderSeasonName() async throws {
        let url = URL(fileURLWithPath: "/Shows/Severance Season 2/E04.mp4")
        let query = FilenameTitleParser.suggestedQuery(fromFileURL: url, mode: .tvShow)

        XCTAssertEqual(query, "Severance S02E04")
    }

    func testAutoSelectsOnlyClearExactMatch() async throws {
        let exact = makeResult(
            id: 1,
            title: "The Matrix",
            year: "1999",
            confidence: .exact,
            summary: "Exact title and year match",
            score: 185
        )
        let runnerUp = makeResult(
            id: 2,
            title: "The Matrix Reloaded",
            year: "2003",
            confidence: .strong,
            summary: "Strong title match",
            score: 120
        )

        let selection = SearchSelectionPolicy.suggestedAutoSelection(from: [exact, runnerUp])

        XCTAssertEqual(selection?.id, exact.id)
    }

    func testDoesNotAutoSelectWhenTopMatchIsNotExact() async throws {
        let strong = makeResult(
            id: 1,
            title: "Heat",
            year: "1995",
            confidence: .strong,
            summary: "Strong title match with matching year",
            score: 120
        )
        let possible = makeResult(
            id: 2,
            title: "Heat Wave",
            year: "1990",
            confidence: .possible,
            summary: "Possible movie page match",
            score: 60
        )

        let selection = SearchSelectionPolicy.suggestedAutoSelection(from: [strong, possible])

        XCTAssertNil(selection)
    }

    func testDoesNotAutoSelectWhenExactMatchIsTooCloseToRunnerUp() async throws {
        let top = makeResult(
            id: 1,
            title: "Crash",
            year: "2004",
            confidence: .exact,
            summary: "Exact title and year match",
            score: 145
        )
        let closeRunnerUp = makeResult(
            id: 2,
            title: "Crash",
            year: "1996",
            confidence: .strong,
            summary: "Exact title match",
            score: 122
        )

        let selection = SearchSelectionPolicy.suggestedAutoSelection(from: [top, closeRunnerUp])

        XCTAssertNil(selection)
    }

    @MainActor
    func testEpisodeSpecificTVSearchDoesNotAutoSelectSeriesFallback() async throws {
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

        XCTAssertNil(entry.selectedResult)
        XCTAssertEqual(entry.statusMessage, "No exact episode found. Showing the closest series matches instead.")
    }

    @MainActor
    func testSeriesOnlyEpisodeSelectionRequiresConfirmationBeforeSave() async throws {
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

        XCTAssertTrue(entry.requiresSeriesOnlySaveConfirmation)
        XCTAssertFalse(entry.canSave)

        entry.allowsSeriesOnlySave = true

        XCTAssertFalse(entry.requiresSeriesOnlySaveConfirmation)
        XCTAssertTrue(entry.canSave)

        entry.queryText = "Severance S02E05"

        XCTAssertTrue(entry.requiresSeriesOnlySaveConfirmation)
        XCTAssertFalse(entry.canSave)
    }

    func testImportValidatorRequiresWritableRegularMP4Files() async throws {
        let directory = try makeTemporaryDirectory(prefix: "MetaFetchTests")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let validMP4 = directory.appendingPathComponent("Movie.mp4")
        FileManager.default.createFile(atPath: validMP4.path, contents: Data([0x00]))

        let wrongExtension = directory.appendingPathComponent("Movie.mov")
        FileManager.default.createFile(atPath: wrongExtension.path, contents: Data([0x00]))

        let symlink = directory.appendingPathComponent("Linked.mp4")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: validMP4)

        XCTAssertNotNil(MediaFileImportValidator.validatedImportURL(validMP4))
        XCTAssertNil(MediaFileImportValidator.validatedImportURL(wrongExtension))
        XCTAssertNil(MediaFileImportValidator.validatedImportURL(symlink))
        XCTAssertNil(MediaFileImportValidator.validatedImportURL(URL(string: "https://example.com/movie.mp4")!))
    }

    @MainActor
    func testSaveStopsIfImportedFileIsSwappedBeforeWriting() async throws {
        let directory = try makeTemporaryDirectory(prefix: "MetaFetchRaceTests")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let importedFile = directory.appendingPathComponent("The.Audacity.S01E03.mp4")
        let replacementTarget = directory.appendingPathComponent("Replacement.mp4")
        FileManager.default.createFile(atPath: importedFile.path, contents: Data([0x00]))
        FileManager.default.createFile(atPath: replacementTarget.path, contents: Data([0x00]))

        let metadataWriter = RecordingMetadataWriter()
        let result = makeEpisodeResult(
            id: 203,
            title: "Valley of Heart's Delight",
            episodeNumber: 3
        )
        let model = AppModel(
            searchService: StubSearchService(results: [result]),
            metadataWriter: metadataWriter
        )
        model.chooseMode(.tvShow)
        model.importFiles(from: [importedFile])

        let entry = try XCTUnwrap(model.files.first)
        entry.selectedResult = result

        try FileManager.default.removeItem(at: importedFile)
        try FileManager.default.createSymbolicLink(at: importedFile, withDestinationURL: replacementTarget)

        let saved = await model.save(file: entry)

        XCTAssertFalse(saved)
        XCTAssertTrue(metadataWriter.calls.isEmpty)
        XCTAssertEqual(entry.statusMessage, "Save stopped before writing")
    }

    func testNativeAtomWriterWritesMetadataIntoExistingHeadroom() async throws {
        let directory = try makeTemporaryDirectory(prefix: "MetaFetchAtomTests")
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

        let result = makeEpisodeResult(
            id: 303,
            title: "Episode Three",
            episodeNumber: 3
        )

        try await MP4AtomMetadataWriter().writeMetadata(
            to: fileURL,
            using: result,
            artworkData: nil
        )

        let taggedData = try Data(contentsOf: fileURL)
        XCTAssertEqual(taggedData.count, originalSize)
        XCTAssertNotNil(taggedData.range(of: Data([0xA9, 0x6E, 0x61, 0x6D])))
        XCTAssertNotNil(taggedData.range(of: Data("Episode Three".utf8)))
        XCTAssertNotNil(taggedData.range(of: Data("tvsh".utf8)))
        XCTAssertNotNil(taggedData.range(of: Data("The Audacity".utf8)))
        XCTAssertNotNil(taggedData.range(of: Data("tvsn".utf8)))
        XCTAssertNotNil(taggedData.range(of: Data("tves".utf8)))
        XCTAssertNotNil(taggedData.range(of: Data("trkn".utf8)))
        XCTAssertNotNil(taggedData.range(of: Data("sosn".utf8)))
        XCTAssertNotNil(taggedData.range(of: Data("soal".utf8)))
        XCTAssertNotNil(taggedData.range(of: Data("sonm".utf8)))
        XCTAssertTrue(try MP4AtomMetadataWriter().metadataWasPersisted(at: fileURL, result: result))
    }

    func testNativeAtomWriterRejectsOversizedMovieAtomBeforeAllocating() async throws {
        let directory = try makeTemporaryDirectory(prefix: "MetaFetchOversizedAtomTests")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("Hostile.S01E03.mp4")
        try writeOversizedMovieAtomFile(at: fileURL)

        do {
            try await MP4AtomMetadataWriter().writeMetadata(
                to: fileURL,
                using: makeEpisodeResult(id: 303, title: "Episode Three", episodeNumber: 3),
                artworkData: nil
            )
            XCTFail("Expected oversized movie atom to be rejected.")
        } catch MP4AtomMetadataWriter.AtomWriterError.movieAtomTooLarge {
            return
        } catch {
            XCTFail("Expected movieAtomTooLarge, got \(error).")
        }
    }

    @MainActor
    func testApplyingBatchShowKeepsEachDetectedEpisodeCode() async throws {
        let directory = try makeTemporaryDirectory(prefix: "MetaFetchBatchTests")
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

        XCTAssertEqual(model.files.map(\.queryText), [
            "The Audacity S01E03",
            "The Audacity S01E04",
        ])
    }

    @MainActor
    func testSaveAllTaggedFilesWritesEveryReadyEpisode() async throws {
        let directory = try makeTemporaryDirectory(prefix: "MetaFetchBatchSaveTests")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let firstEpisode = directory.appendingPathComponent("The.Audacity.S01E02.mp4")
        let secondEpisode = directory.appendingPathComponent("The.Audacity.S01E03.mp4")
        FileManager.default.createFile(atPath: firstEpisode.path, contents: Data([0x00]))
        FileManager.default.createFile(atPath: secondEpisode.path, contents: Data([0x00]))

        let metadataWriter = RecordingMetadataWriter()
        let defaultEpisodeResult = makeEpisodeResult(
            id: 202,
            title: "Shine Brightly",
            episodeNumber: 2
        )
        let model = AppModel(
            searchService: StubSearchService(results: [defaultEpisodeResult]),
            metadataWriter: metadataWriter
        )
        model.chooseMode(.tvShow)
        model.importFiles(from: [firstEpisode, secondEpisode])
        await model.search(file: model.files[0])
        await model.search(file: model.files[1])

        model.files[0].selectedResult = makeEpisodeResult(
            id: 202,
            title: "Shine Brightly",
            episodeNumber: 2
        )
        model.files[1].selectedResult = makeEpisodeResult(
            id: 203,
            title: "Valley of Heart's Delight",
            episodeNumber: 3
        )

        XCTAssertEqual(model.saveReadyCount, 2)
        XCTAssertEqual(model.saveAllButtonTitle, "Save 2 + Posters")

        await model.saveAllTaggedFiles()

        XCTAssertEqual(metadataWriter.savedPaths, [
            firstEpisode.standardizedFileURL.path,
            secondEpisode.standardizedFileURL.path,
        ])
        XCTAssertTrue(model.files.allSatisfy { $0.lastSavedAt != nil })
        XCTAssertEqual(model.batchStatusMessage, "Verified metadata and available poster artwork on 2 episodes.")
    }

    @MainActor
    func testBatchSeriesCoverChoiceIsWrittenToReadyEpisodes() async throws {
        let directory = try makeTemporaryDirectory(prefix: "MetaFetchBatchCoverTests")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let episodeFile = directory.appendingPathComponent("The.Audacity.S01E03.mp4")
        FileManager.default.createFile(atPath: episodeFile.path, contents: Data([0x00]))

        let seriesArtworkURL = URL(string: "https://static.tvmaze.com/uploads/images/original_untouched/series.jpg")!
        let metadataWriter = RecordingMetadataWriter()
        let model = AppModel(
            searchService: StubSearchService(results: [
                makeEpisodeResult(id: 203, title: "Valley of Heart's Delight", episodeNumber: 3),
            ]),
            metadataWriter: metadataWriter
        )
        model.chooseMode(.tvShow)
        model.importFiles(from: [episodeFile])
        await model.search(file: model.files[0])
        model.selectedBatchResult = makeResult(
            id: 303,
            title: "The Audacity",
            year: "2026",
            mediaKind: .tvSeries,
            confidence: .exact,
            summary: "Exact show match",
            score: 200
        ).replacingArtworkURL(seriesArtworkURL)

        model.useSeriesArtworkForBatch()
        await model.saveAllTaggedFiles()

        XCTAssertEqual(model.files[0].artworkOverrideURL, seriesArtworkURL)
        XCTAssertEqual(metadataWriter.savedArtworkURLs, [seriesArtworkURL])
        XCTAssertEqual(metadataWriter.calls.map(\.includeArtwork), [true])
    }
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

private func makeEpisodeResult(
    id: Int,
    title: String,
    episodeNumber: Int
) -> MediaSearchResult {
    MediaSearchResult(
        trackId: id,
        mediaKind: .tvEpisode,
        trackName: title,
        seriesName: "The Audacity",
        artistName: "AMC+",
        releaseDate: "2026-01-01T00:00:00Z",
        primaryGenreName: "Drama",
        shortDescription: "Test episode",
        longDescription: "Test episode.",
        contentAdvisoryRating: nil,
        artworkURL: nil,
        sourceURL: nil,
        sourceName: "TVMaze",
        matchConfidence: .exact,
        matchSummary: "Exact episode match",
        matchScore: 200,
        seasonNumber: 1,
        episodeNumber: episodeNumber
    )
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
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

private func writeOversizedMovieAtomFile(at fileURL: URL) throws {
    let movieAtomSize = UInt32(129 * 1024 * 1024)
    var mp4 = Data()
    let fileTypeAtom = makeTestAtom("ftyp", payload: Data("isom0000".utf8))
    mp4.append(fileTypeAtom)
    mp4.append(makeTestUInt32Data(movieAtomSize))
    mp4.append(Data("moov".utf8))
    try mp4.write(to: fileURL)

    let handle = try FileHandle(forWritingTo: fileURL)
    defer {
        try? handle.close()
    }
    try handle.truncate(atOffset: UInt64(fileTypeAtom.count) + UInt64(movieAtomSize))
}

private struct StubSearchService: MediaSearchServing {
    let results: [MediaSearchResult]

    func search(matching query: String, mode: MediaLibraryMode) async throws -> [MediaSearchResult] {
        results
    }
}

private final class RecordingMetadataWriter: MetadataWriting, @unchecked Sendable {
    private(set) var calls: [(fileURL: URL, result: MediaSearchResult, includeArtwork: Bool)] = []

    var savedPaths: [String] {
        calls.map { $0.fileURL.standardizedFileURL.path }
    }

    var savedArtworkURLs: [URL?] {
        calls.map(\.result.artworkURL)
    }

    func writeMetadata(
        to fileURL: URL,
        using result: MediaSearchResult,
        includeArtwork: Bool,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)?
    ) async throws {
        await progressHandler?(MetadataWriteProgress(
            fractionCompleted: 1,
            message: "Verified test save"
        ))
        calls.append((fileURL.standardizedFileURL, result, includeArtwork))
    }
}
