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

    var sidebarStatus: String {
        if isSaving {
            return "Saving metadata"
        }

        if lastSavedAt != nil {
            return "Saved"
        }

        if isSearching {
            return "Searching"
        }

        if selectedResult != nil {
            return "Match selected"
        }

        if !searchResults.isEmpty {
            return "\(searchResults.count) matches"
        }

        return "Needs a match"
    }
}
