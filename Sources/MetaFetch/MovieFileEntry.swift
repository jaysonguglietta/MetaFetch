import Foundation

@MainActor
final class MovieFileEntry: ObservableObject, Identifiable {
    let id = UUID()
    let fileURL: URL

    @Published var queryText: String
    @Published var searchResults: [MovieSearchResult] = []
    @Published var selectedResult: MovieSearchResult?
    @Published var isSearching = false
    @Published var isSaving = false
    @Published var includeArtworkWhenSaving = true
    @Published var errorMessage: String?
    @Published var statusMessage = "Ready to search"
    @Published var lastSavedAt: Date?

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.queryText = FilenameTitleParser.suggestedQuery(from: fileURL.lastPathComponent)
    }

    var filename: String {
        fileURL.lastPathComponent
    }

    var canSave: Bool {
        selectedResult != nil && !isSaving
    }

    var hasSelectedArtwork: Bool {
        selectedResult?.hasArtwork == true
    }

    var willSaveArtwork: Bool {
        includeArtworkWhenSaving && hasSelectedArtwork
    }

    var saveActionLabel: String {
        if willSaveArtwork {
            return "Save Metadata + Poster"
        }

        return "Fast Save Metadata"
    }

    var saveModeSummary: String {
        if willSaveArtwork {
            return "Includes poster artwork. Best presentation, slightly slower save."
        }

        if hasSelectedArtwork {
            return "Poster art is off for a quicker save."
        }

        return "No poster art is available for this match, so this is already the fastest mode."
    }

    var sidebarStatus: String {
        if isSaving {
            return willSaveArtwork ? "Saving with artwork" : "Fast saving"
        }

        if lastSavedAt != nil {
            return "Saved"
        }

        if isSearching {
            return "Searching"
        }

        if selectedResult != nil {
            return selectedResult?.matchConfidence.label ?? "Match selected"
        }

        if !searchResults.isEmpty {
            return "\(searchResults.count) matches"
        }

        return "Needs a match"
    }
}
