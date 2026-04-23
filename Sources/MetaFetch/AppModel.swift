import AppKit
import Foundation
import SwiftUI

enum SearchSelectionPolicy {
    static func suggestedAutoSelection(from results: [MediaSearchResult]) -> MediaSearchResult? {
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
    @Published var selectedMode: MediaLibraryMode?
    @Published var updateState: AppUpdateState = .idle

    private let searchService: MediaSearchServing
    private let metadataWriter: MetadataWriting
    private let updateService: AppUpdateChecking

    init(
        searchService: MediaSearchServing = MetadataCatalogSearchService(),
        metadataWriter: MetadataWriting = MP4MetadataWriter(),
        updateService: AppUpdateChecking = GitHubReleaseUpdateService()
    ) {
        self.searchService = searchService
        self.metadataWriter = metadataWriter
        self.updateService = updateService
    }

    var selectedFile: MovieFileEntry? {
        if let selectedFileID {
            return files.first(where: { $0.id == selectedFileID })
        }

        return files.first
    }

    var canSaveAnyTaggedFiles: Bool {
        files.contains(where: \.canSave)
    }

    var canUseTVBatchTools: Bool {
        selectedMode == .tvShow && files.count > 1
    }

    var isBatchBusy: Bool {
        files.contains { $0.isSearching || $0.isSaving }
    }

    var batchMatchedCount: Int {
        files.filter { $0.selectedResult != nil }.count
    }

    var batchSavedCount: Int {
        files.filter { $0.lastSavedAt != nil }.count
    }

    var batchNeedsReviewCount: Int {
        files.filter { !$0.canSave && $0.lastSavedAt == nil }.count
    }

    var canChooseMode: Bool {
        files.isEmpty
    }

    var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    func chooseMode(_ mode: MediaLibraryMode) {
        guard canChooseMode else {
            noticeMessage = "Remove the current files before switching modes."
            return
        }

        selectedMode = mode
        noticeMessage = nil
    }

    func resetModeSelection() {
        guard canChooseMode else {
            return
        }

        selectedMode = nil
        noticeMessage = nil
    }

    func startOver() {
        files.removeAll()
        selectedFileID = nil
        selectedMode = nil
        noticeMessage = nil
    }

    func importFiles(from urls: [URL]) {
        guard let selectedMode else {
            noticeMessage = MediaLibraryMode.movie.importNotice
            return
        }

        let validURLs = urls
            .compactMap(MediaFileImportValidator.validatedImportURL)

        guard !validURLs.isEmpty else {
            noticeMessage = "Only local, writable `.mp4` files are accepted right now."
            return
        }

        var knownPaths = Set(files.map { $0.fileURL.standardizedFileURL.path })
        let newEntries = validURLs.compactMap { url -> MovieFileEntry? in
            guard knownPaths.insert(url.path).inserted else {
                return nil
            }

            return MovieFileEntry(fileURL: url, mediaMode: selectedMode)
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
        let parsedQuery = FilenameTitleParser.parsedManualQuery(query, mode: file.mediaMode)

        guard !parsedQuery.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            file.errorMessage = file.mediaMode.emptyQueryError
            file.statusMessage = "Waiting for a title"
            return
        }

        file.isSearching = true
        file.errorMessage = nil
        file.statusMessage = searchStatusMessage(for: file.mediaMode, query: query)

        do {
            let results = try await searchService.search(matching: query, mode: file.mediaMode)
            let previousSelectionID = file.selectedResult?.id
            let preservedSelection: MediaSearchResult?
            file.searchResults = results
            file.isSearching = false

            if let previousSelectionID,
               let refreshedSelection = results.first(where: { $0.id == previousSelectionID }) {
                file.selectedResult = refreshedSelection
                preservedSelection = refreshedSelection
            } else {
                file.selectedResult = suggestedAutoSelection(
                    from: results,
                    mode: file.mediaMode,
                    parsedQuery: parsedQuery
                )
                preservedSelection = nil
            }

            if results.isEmpty {
                file.statusMessage = "No matches found yet"
                file.errorMessage = file.mediaMode.noResultsError
            } else if file.mediaMode == .tvShow,
                        parsedQuery.isEpisodeSpecific,
                        !results.contains(where: { $0.mediaKind == .tvEpisode }) {
                file.statusMessage = "No exact episode found. Showing the closest series matches instead."
            } else if preservedSelection != nil {
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
        } catch {
            file.isSearching = false
            file.statusMessage = "Search failed"
            file.errorMessage = error.localizedDescription
        }
    }

    func save(file: MovieFileEntry) async {
        guard let selectedResult = file.selectedResult else {
            file.errorMessage = file.mediaMode.saveSelectionError
            return
        }

        if file.requiresSeriesOnlySaveConfirmation {
            file.errorMessage = "This is a series-level TV match for an episode query. Confirm the series-only save before writing metadata."
            file.statusMessage = "Series-only save needs confirmation"
            return
        }

        let includeArtwork = file.willSaveArtwork
        let fileID = file.id
        file.isSaving = true
        file.saveProgress = nil
        file.errorMessage = nil
        file.statusMessage = includeArtwork
            ? "Preparing artwork and metadata"
            : "Preparing metadata-only fast path"

        do {
            if includeArtwork && selectedResult.artworkURL != nil {
                _ = try await ArtworkPipeline.shared.preparedArtwork(for: selectedResult.artworkURL)
            }

            file.statusMessage = includeArtwork
                ? "Starting MP4 rewrite with artwork and metadata"
                : "Starting metadata-only fast save"
            file.saveProgress = 0

            try await metadataWriter.writeMetadata(
                to: file.fileURL,
                using: selectedResult,
                includeArtwork: includeArtwork,
                progressHandler: { [weak self] progress in
                    await self?.applySaveProgress(progress, toFileWithID: fileID)
                }
            )
            file.saveProgress = 1
            file.lastSavedAt = Date()
            file.isSaving = false
            file.saveProgress = nil
            file.statusMessage = "Saved metadata at \(file.lastSavedAt?.formatted(date: .omitted, time: .shortened) ?? "just now")"
            advanceSelection(afterSaving: file)
        } catch {
            file.isSaving = false
            file.saveProgress = nil
            file.statusMessage = "Save failed"
            file.errorMessage = error.localizedDescription
        }
    }

    func saveAllTaggedFiles() async {
        await saveAllTaggedFiles(metadataOnly: false)
    }

    func saveAllTaggedFiles(metadataOnly: Bool) async {
        if metadataOnly {
            setArtworkSavingForAll(false)
        }

        for entry in files where entry.canSave {
            await save(file: entry)
        }
    }

    func searchAllFiles() async {
        for entry in files {
            await search(file: entry)
        }
    }

    func setArtworkSavingForAll(_ includeArtwork: Bool) {
        for entry in files {
            entry.includeArtworkWhenSaving = includeArtwork
        }

        noticeMessage = includeArtwork
            ? "Poster artwork will be included for all loaded files when available."
            : "Poster artwork is off for all loaded files, so batch saves will use the fastest metadata path."
    }

    func checkForUpdates() async {
        guard !updateState.isBusy else {
            return
        }

        updateState = .checking

        do {
            switch try await updateService.checkForUpdate(currentVersion: currentAppVersion) {
            case .upToDate(let version):
                updateState = .upToDate(version: version)
            case .available(let update):
                updateState = .available(update)
            }
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func downloadAvailableUpdate() async {
        guard case .available(let update) = updateState,
              !updateState.isBusy else {
            return
        }

        updateState = .downloading(update)

        do {
            let fileURL = try await updateService.download(update: update)
            updateState = .downloaded(update, fileURL: fileURL)
            openDownloadedUpdate(at: fileURL)
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func openReleasePage(for update: AppUpdate) {
        NSWorkspace.shared.open(update.releaseURL)
    }

    func openDownloadedUpdate(at fileURL: URL) {
        NSWorkspace.shared.open(fileURL)
    }

    private func suggestedAutoSelection(
        from results: [MediaSearchResult],
        mode: MediaLibraryMode,
        parsedQuery: ParsedMediaQuery
    ) -> MediaSearchResult? {
        guard let suggestedResult = SearchSelectionPolicy.suggestedAutoSelection(from: results) else {
            return nil
        }

        guard !(mode == .tvShow &&
                parsedQuery.isEpisodeSpecific &&
                suggestedResult.mediaKind == .tvSeries) else {
            return nil
        }

        return suggestedResult
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

    private func applySaveProgress(_ progress: MetadataWriteProgress, toFileWithID fileID: UUID) {
        guard let file = files.first(where: { $0.id == fileID }),
              file.isSaving else {
            return
        }

        file.saveProgress = progress.fractionCompleted
        file.statusMessage = progress.message
    }

    private func searchStatusMessage(for mode: MediaLibraryMode, query: String) -> String {
        switch mode {
        case .movie:
            return "Searching movie matches for “\(query)”"
        case .tvShow:
            return "Searching TV matches for “\(query)”"
        }
    }
}

enum MediaFileImportValidator {
    static func validatedImportURL(_ url: URL) -> URL? {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.isFileURL,
              standardizedURL.pathExtension.caseInsensitiveCompare("mp4") == .orderedSame,
              let resourceValues = try? standardizedURL.resourceValues(forKeys: [
                .isReadableKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isWritableKey,
              ]),
              resourceValues.isRegularFile == true,
              resourceValues.isReadable == true,
              resourceValues.isWritable == true,
              resourceValues.isSymbolicLink != true else {
            return nil
        }

        return standardizedURL
    }
}
