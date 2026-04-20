import Foundation
import SwiftUI

enum SearchSelectionPolicy {
    static func suggestedAutoSelection(from results: [MovieSearchResult]) -> MovieSearchResult? {
        guard let topResult = results.first else {
            return nil
        }

        guard topResult.matchConfidence == .exact else {
            return nil
        }

        guard let runnerUp = results.dropFirst().first else {
            return topResult
        }

        guard topResult.matchScore - runnerUp.matchScore >= 30 else {
            return nil
        }

        return topResult
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var files: [MovieFileEntry] = []
    @Published var selectedFileID: UUID?
    @Published var isFileImporterPresented = false
    @Published var noticeMessage: String?

    private let searchService: MovieSearchServing
    private let metadataWriter: MetadataWriting

    init(
        searchService: MovieSearchServing = WikimediaMovieSearchService(),
        metadataWriter: MetadataWriting = MP4MetadataWriter()
    ) {
        self.searchService = searchService
        self.metadataWriter = metadataWriter
    }

    var selectedFile: MovieFileEntry? {
        if let selectedFileID {
            return files.first(where: { $0.id == selectedFileID })
        }

        return files.first
    }

    var canSaveAnyTaggedFiles: Bool {
        files.contains(where: { $0.selectedResult != nil && !$0.isSaving })
    }

    func importFiles(from urls: [URL]) {
        let validURLs = urls
            .map(\.standardizedFileURL)
            .filter { $0.pathExtension.caseInsensitiveCompare("mp4") == .orderedSame }

        guard !validURLs.isEmpty else {
            noticeMessage = "Only `.mp4` files are accepted right now."
            return
        }

        let existingPaths = Set(files.map { $0.fileURL.standardizedFileURL.path })
        let newEntries = validURLs.compactMap { url -> MovieFileEntry? in
            guard !existingPaths.contains(url.path) else {
                return nil
            }

            return MovieFileEntry(fileURL: url)
        }

        guard !newEntries.isEmpty else {
            noticeMessage = "Those MP4 files are already loaded."
            return
        }

        noticeMessage = nil
        files.append(contentsOf: newEntries)

        if selectedFileID == nil {
            selectedFileID = newEntries.first?.id
        }

        for entry in newEntries {
            Task {
                await search(file: entry)
            }
        }
    }

    func removeFiles(at offsets: IndexSet) {
        let removedIDs = offsets.map { files[$0].id }

        for index in offsets.sorted(by: >) {
            files.remove(at: index)
        }

        if let selectedFileID, removedIDs.contains(selectedFileID) {
            self.selectedFileID = files.first?.id
        }
    }

    func search(file: MovieFileEntry) async {
        let query = file.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            file.errorMessage = "Enter a movie title to search."
            file.statusMessage = "Waiting for a title"
            return
        }

        file.isSearching = true
        file.errorMessage = nil
        file.statusMessage = "Searching movie matches for “\(query)”"

        do {
            let results = try await searchService.searchMovies(matching: query)
            let previousSelectionID = file.selectedResult?.id
            let preservedSelection: MovieSearchResult?
            file.searchResults = results
            file.isSearching = false

            if let previousSelectionID,
               let refreshedSelection = results.first(where: { $0.id == previousSelectionID }) {
                file.selectedResult = refreshedSelection
                preservedSelection = refreshedSelection
            } else {
                file.selectedResult = SearchSelectionPolicy.suggestedAutoSelection(from: results)
                preservedSelection = nil
            }

            if results.isEmpty {
                file.statusMessage = "No matches found yet"
                file.errorMessage = "No movie matches came back. Try removing the year or shortening the title."
            } else {
                if preservedSelection != nil {
                    file.statusMessage = "Kept your selected match while refreshing \(results.count) result\(results.count == 1 ? "" : "s")"
                } else if let selectedResult = file.selectedResult,
                          selectedResult.matchConfidence == .exact {
                    file.statusMessage = "Auto-selected a high-confidence match from \(results.count) result\(results.count == 1 ? "" : "s")"
                } else {
                    file.statusMessage = "Found \(results.count) possible match\(results.count == 1 ? "" : "es"). Pick the best one."
                }

                let artworkURLs = results
                    .prefix(6)
                    .compactMap(\.artworkURL)

                await ArtworkPipeline.shared.prefetch(urls: Array(artworkURLs))
            }
        } catch {
            file.isSearching = false
            file.statusMessage = "Search failed"
            file.errorMessage = error.localizedDescription
        }
    }

    func save(file: MovieFileEntry) async {
        guard let selectedResult = file.selectedResult else {
            file.errorMessage = "Choose a movie match before saving."
            return
        }

        let includeArtwork = file.willSaveArtwork
        file.isSaving = true
        file.errorMessage = nil
        file.statusMessage = includeArtwork
            ? "Preparing poster artwork and metadata"
            : "Preparing fast metadata save"

        do {
            if includeArtwork && selectedResult.artworkURL != nil {
                _ = try await ArtworkPipeline.shared.preparedArtwork(for: selectedResult.artworkURL)
            }

            file.statusMessage = includeArtwork
                ? "Rewriting MP4 with metadata and poster artwork"
                : "Rewriting MP4 with metadata only"

            try await metadataWriter.writeMetadata(
                to: file.fileURL,
                using: selectedResult,
                includeArtwork: includeArtwork
            )
            file.lastSavedAt = Date()
            file.isSaving = false
            file.statusMessage = "Saved metadata at \(file.lastSavedAt?.formatted(date: .omitted, time: .shortened) ?? "just now")"
            advanceSelection(afterSaving: file)
        } catch {
            file.isSaving = false
            file.statusMessage = "Save failed"
            file.errorMessage = error.localizedDescription
        }
    }

    func saveAllTaggedFiles() async {
        for entry in files where entry.selectedResult != nil && !entry.isSaving {
            await save(file: entry)
        }
    }

    private func advanceSelection(afterSaving savedFile: MovieFileEntry) {
        guard let currentIndex = files.firstIndex(where: { $0.id == savedFile.id }) else {
            return
        }

        let trailingFiles = files.suffix(from: files.index(after: currentIndex))
        let leadingFiles = files.prefix(upTo: currentIndex)

        if let nextFile = trailingFiles.first(where: { $0.lastSavedAt == nil }) ??
            leadingFiles.first(where: { $0.lastSavedAt == nil }) {
            selectedFileID = nextFile.id
        }
    }
}
