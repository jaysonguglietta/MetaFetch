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
