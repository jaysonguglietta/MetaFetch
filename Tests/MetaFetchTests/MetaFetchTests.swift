import Testing
@testable import MetaFetch

@Test func appIsRenamedMetaFetch() async throws {
    #expect(String(describing: MetaFetchApp.self) == "MetaFetchApp")
}

@Test func stripsReleaseNoiseAndKeepsYear() async throws {
    let query = FilenameTitleParser.suggestedQuery(
        from: "The.Matrix.1999.1080p.BluRay.x264.mp4"
    )

    #expect(query == "The Matrix 1999")
}

@Test func removesBracketedJunkAndPreservesMeaningfulWords() async throws {
    let query = FilenameTitleParser.suggestedQuery(
        from: "[YTS] Mad.Max.Fury.Road.(2015).WEB-DL.H264.mp4"
    )

    #expect(query == "Mad Max Fury Road 2015")
}

@Test func stopsAtEpisodeMarkers() async throws {
    let query = FilenameTitleParser.suggestedQuery(
        from: "Some.Show.S01E03.1080p.WEBRip.mp4"
    )

    #expect(query == "Some Show")
}

@Test func autoSelectsOnlyClearExactMatch() async throws {
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

    #expect(selection?.id == exact.id)
}

@Test func doesNotAutoSelectWhenTopMatchIsNotExact() async throws {
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

    #expect(selection == nil)
}

@Test func doesNotAutoSelectWhenExactMatchIsTooCloseToRunnerUp() async throws {
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

    #expect(selection == nil)
}

private func makeResult(
    id: Int,
    title: String,
    year: String,
    confidence: MatchConfidence,
    summary: String,
    score: Int
) -> MovieSearchResult {
    MovieSearchResult(
        trackId: id,
        trackName: title,
        artistName: "Test Director",
        releaseDate: "\(year)-01-01T00:00:00Z",
        primaryGenreName: "Science fiction film",
        shortDescription: "Test film",
        longDescription: "Test film directed by Test Director.",
        contentAdvisoryRating: nil,
        artworkUrl100: nil,
        sourceName: "Wikipedia",
        matchConfidence: confidence,
        matchSummary: summary,
        matchScore: score
    )
}
