import Foundation
import SwiftUI

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
            file.searchResults = results
            file.selectedResult = results.first
            file.isSearching = false

            if results.isEmpty {
                file.statusMessage = "No matches found yet"
                file.errorMessage = "No movie matches came back. Try removing the year or shortening the title."
            } else {
                file.statusMessage = "Found \(results.count) possible match\(results.count == 1 ? "" : "es")"

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

        file.isSaving = true
        file.errorMessage = nil
        file.statusMessage = "Writing metadata back to \(file.filename)"

        do {
            try await metadataWriter.writeMetadata(to: file.fileURL, using: selectedResult)
            file.lastSavedAt = Date()
            file.isSaving = false
            file.statusMessage = "Saved metadata at \(file.lastSavedAt?.formatted(date: .omitted, time: .shortened) ?? "just now")"
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
}
