import Foundation

@MainActor
final class MovieFileEntry: ObservableObject, Identifiable {
    let id = UUID()
    @Published var fileURL: URL
    let mediaMode: MediaLibraryMode
    var importIdentity: MediaFileIdentity?

    @Published var queryText: String {
        didSet {
            if queryText != oldValue {
                allowsSeriesOnlySave = false
            }
        }
    }
    @Published var searchResults: [MediaSearchResult] = []
    @Published var selectedResult: MediaSearchResult? {
        didSet {
            if selectedResult?.id != oldValue?.id {
                allowsSeriesOnlySave = false
                artworkOverrideURL = nil
                customArtworkURL = nil
                if let selectedResult {
                    metadataDraft = MetadataDraft(result: selectedResult)
                } else {
                    metadataDraft = MetadataDraft()
                }
            }
        }
    }
    @Published var artworkOverrideURL: URL?
    @Published var customArtworkURL: URL?
    @Published var posterSavingEnabled = true
    @Published var metadataDraft = MetadataDraft()
    @Published var currentMetadataSnapshot: MP4CurrentMetadataSnapshot?
    @Published var currentMetadataError: String?
    @Published var headroomInspection: MP4HeadroomInspection?
    @Published var providerDiagnostics = ""
    @Published var isInspectingHeadroom = false
    @Published var isSearching = false
    @Published var isSaving = false
    @Published var saveProgress: Double?
    @Published var allowsSeriesOnlySave = false
    @Published var errorMessage: String?
    @Published var statusMessage: String
    @Published var lastSavedAt: Date?
    @Published var lastSaveOutcome: MetadataWriteOutcome?
    var searchGeneration = 0

    init(
        fileURL: URL,
        mediaMode: MediaLibraryMode,
        importIdentity: MediaFileIdentity? = nil
    ) {
        self.fileURL = fileURL
        self.mediaMode = mediaMode
        self.importIdentity = importIdentity
        self.queryText = FilenameTitleParser.suggestedQuery(
            fromFileURL: fileURL,
            mode: mediaMode
        )
        self.statusMessage = "Ready to search"
    }

    var filename: String {
        fileURL.lastPathComponent
    }

    var canSave: Bool {
        metadataDraft.isValid(for: selectedResult) && !isSaving && !requiresSeriesOnlySaveConfirmation
    }

    var hasSelectedArtwork: Bool {
        selectedArtworkURL != nil
    }

    var willSaveArtwork: Bool {
        posterSavingEnabled && hasSelectedArtwork
    }

    var selectedArtworkURL: URL? {
        customArtworkURL ?? artworkOverrideURL ?? selectedResult?.artworkURL
    }

    var artworkChoiceSummary: String {
        if customArtworkURL != nil {
            return "Using your custom poster image."
        }

        if artworkOverrideURL != nil {
            return "Using the selected batch cover."
        }

        if selectedResult?.artworkURL != nil {
            return "Using this episode's artwork."
        }

        return "No artwork is available for this selection."
    }

    var saveActionLabel: String {
        if willSaveArtwork {
            return "Save Metadata + Poster"
        }

        if hasSelectedArtwork && !posterSavingEnabled {
            return "Fast Save Metadata"
        }

        return "Fast Save Metadata"
    }

    var saveModeSummary: String {
        if hasSelectedArtwork && !posterSavingEnabled {
            return "Poster artwork is available but disabled for this file. MetaFetch will prefer the fastest metadata-only path."
        }

        if willSaveArtwork {
            return "\(artworkChoiceSummary) Best presentation, slightly slower save."
        }

        return "No poster art is available, so MetaFetch will try a metadata-only header update first and fall back to a full rewrite only if needed."
    }

    var headroomSummary: String {
        guard willSaveArtwork else {
            return "Poster artwork is off for this file, so the metadata-only fast path is most likely."
        }

        guard let headroomInspection else {
            return "Run the headroom check before saving with poster artwork."
        }

        return headroomInspection.detail
    }

    var normalizedSaveProgress: Double? {
        guard let saveProgress else {
            return nil
        }

        return min(max(saveProgress, 0), 1)
    }

    var saveProgressLabel: String {
        guard let normalizedSaveProgress else {
            return ""
        }

        return "\(Int(normalizedSaveProgress * 100))%"
    }

    var episodeDetectionSummary: String? {
        guard mediaMode == .tvShow else {
            return nil
        }

        let parsedQuery = parsedCurrentQuery
        if let episodeCode = parsedQuery.episodeCode {
            return "Detected episode \(episodeCode)"
        }

        return "No episode code found. MetaFetch will search series-level matches until you add something like S01E03."
    }

    var requiresSeriesOnlySaveConfirmation: Bool {
        isSeriesOnlySelectionForEpisodeQuery && !allowsSeriesOnlySave
    }

    var isSeriesOnlySelectionForEpisodeQuery: Bool {
        guard mediaMode == .tvShow,
              parsedCurrentQuery.isEpisodeSpecific,
              selectedResult?.mediaKind == .tvSeries else {
            return false
        }

        return true
    }

    var parsedCurrentQuery: ParsedMediaQuery {
        FilenameTitleParser.parsedManualQuery(queryText, mode: mediaMode)
    }

    var batchReviewLabel: String {
        if isSaving {
            return "Saving"
        }

        if lastSavedAt != nil {
            return "Saved"
        }

        guard let selectedResult else {
            return searchResults.isEmpty ? "Needs Match" : "Needs Review"
        }

        if mediaMode == .tvShow, selectedResult.mediaKind == .tvSeries {
            return "Series Only"
        }

        switch selectedResult.matchConfidence {
        case .exact:
            return "Exact"
        case .strong:
            return "Review"
        case .possible:
            return "Needs Review"
        }
    }

    var sidebarStatus: String {
        if isSaving {
            if let normalizedSaveProgress {
                return "Saving \(Int(normalizedSaveProgress * 100))%"
            }

            return willSaveArtwork ? "Saving with artwork" : "Fast saving"
        }

        if lastSavedAt != nil {
            return "Saved"
        }

        if isSearching {
            return "Searching"
        }

        if selectedResult != nil {
            if requiresSeriesOnlySaveConfirmation {
                return "Series only • Confirm to save"
            }

            return batchReviewLabel
        }

        if !searchResults.isEmpty {
            return "\(searchResults.count) matches • Needs review"
        }

        return mediaMode.needsMatchCopy
    }
}
