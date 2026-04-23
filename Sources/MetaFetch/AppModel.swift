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
    @Published var batchQueryText = ""
    @Published var batchSearchResults: [MediaSearchResult] = []
    @Published var selectedBatchResult: MediaSearchResult?
    @Published var isBatchSearching = false
    @Published var isBatchSaving = false
    @Published var batchStatusMessage = "Search for the show once, then apply it to every loaded episode."
    @Published var batchErrorMessage: String?

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
        saveReadyCount > 0
    }

    var canUseTVBatchTools: Bool {
        selectedMode == .tvShow && files.count > 1
    }

    var isBatchBusy: Bool {
        isBatchSearching || isBatchSaving || files.contains { $0.isSearching || $0.isSaving }
    }

    var saveReadyCount: Int {
        files.filter(\.canSave).count
    }

    var saveAllButtonTitle: String {
        guard saveReadyCount > 0 else {
            return selectedMode == .tvShow ? "Save All + Posters" : "Save All Tagged"
        }

        if selectedMode == .tvShow {
            return "Save \(saveReadyCount) + Posters"
        }

        return "Save \(saveReadyCount) Tagged"
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
        resetBatchSearch()
        noticeMessage = nil
    }

    func resetModeSelection() {
        guard canChooseMode else {
            return
        }

        selectedMode = nil
        noticeMessage = nil
        resetBatchSearch()
    }

    func startOver() {
        files.removeAll()
        selectedFileID = nil
        selectedMode = nil
        noticeMessage = nil
        resetBatchSearch()
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
        refreshBatchQuerySuggestion()

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

        if files.isEmpty {
            resetBatchSearch()
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

    @discardableResult
    func save(file: MovieFileEntry) async -> Bool {
        guard let selectedResult = file.selectedResult else {
            file.errorMessage = file.mediaMode.saveSelectionError
            return false
        }

        if file.requiresSeriesOnlySaveConfirmation {
            file.errorMessage = "This is a series-level TV match for an episode query. Confirm the series-only save before writing metadata."
            file.statusMessage = "Series-only save needs confirmation"
            return false
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
            file.statusMessage = "Verified MP4 tags at \(file.lastSavedAt?.formatted(date: .omitted, time: .shortened) ?? "just now")"
            advanceSelection(afterSaving: file)
            return true
        } catch {
            file.isSaving = false
            file.saveProgress = nil
            file.statusMessage = "Save failed"
            file.errorMessage = error.localizedDescription
            return false
        }
    }

    func saveAllTaggedFiles() async {
        guard !isBatchSaving else {
            return
        }

        let taggedFiles = files.filter(\.canSave)

        guard !taggedFiles.isEmpty else {
            noticeMessage = "No tagged files are ready to save yet."
            if canUseTVBatchTools {
                batchErrorMessage = "No tagged episodes are ready to save yet."
                batchStatusMessage = "Pick or apply matches before saving the batch."
            }
            return
        }

        isBatchSaving = true
        defer {
            isBatchSaving = false
        }

        if canUseTVBatchTools {
            batchErrorMessage = nil
            batchStatusMessage = "Saving and verifying \(taggedFiles.count) tagged episode\(taggedFiles.count == 1 ? "" : "s")"
        }

        var verifiedSaveCount = 0

        for (index, entry) in taggedFiles.enumerated() {
            if canUseTVBatchTools {
                batchStatusMessage = "Saving \(index + 1) of \(taggedFiles.count): \(entry.filename)"
            }

            if await save(file: entry) {
                verifiedSaveCount += 1
            }
        }

        guard canUseTVBatchTools else {
            return
        }

        let failedCount = taggedFiles.count - verifiedSaveCount
        if failedCount == 0 {
            batchErrorMessage = nil
            batchStatusMessage = "Verified metadata and available poster artwork on \(verifiedSaveCount) episode\(verifiedSaveCount == 1 ? "" : "s")."
        } else {
            batchErrorMessage = "\(failedCount) episode\(failedCount == 1 ? "" : "s") did not verify. Check the yellow rows for details."
            batchStatusMessage = "Verified \(verifiedSaveCount) of \(taggedFiles.count) tagged episode\(taggedFiles.count == 1 ? "" : "s")."
        }
    }

    func searchBatchShow() async {
        let query = batchQueryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            batchErrorMessage = "Enter a show title first."
            batchStatusMessage = "Waiting for a show title"
            return
        }

        isBatchSearching = true
        batchErrorMessage = nil
        batchStatusMessage = "Searching show matches for “\(query)”"

        do {
            let results = try await searchService.search(matching: query, mode: .tvShow)
            batchSearchResults = results
            selectedBatchResult = SearchSelectionPolicy.suggestedAutoSelection(from: results)
            isBatchSearching = false

            if let selectedBatchResult {
                batchStatusMessage = "Auto-selected \(selectedBatchResult.trackName). Click a card to apply a different show."
            } else if results.isEmpty {
                batchStatusMessage = "No show matches found"
                batchErrorMessage = "Try a shorter show title."
            } else {
                batchStatusMessage = "Pick the show card that should drive this episode batch."
            }

            let artworkURLs = results
                .prefix(6)
                .compactMap(\.artworkURL)

            await ArtworkPipeline.shared.prefetch(urls: Array(artworkURLs))
        } catch {
            isBatchSearching = false
            batchStatusMessage = "Batch search failed"
            batchErrorMessage = error.localizedDescription
        }
    }

    func applyBatchResultToAllFiles(_ result: MediaSearchResult) async {
        guard selectedMode == .tvShow else {
            return
        }

        let showTitle = (result.seriesName ?? result.trackName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !showTitle.isEmpty else {
            batchErrorMessage = "That result does not have a usable show title."
            return
        }

        selectedBatchResult = result
        batchErrorMessage = nil
        batchStatusMessage = "Applying \(showTitle) to \(files.count) episode\(files.count == 1 ? "" : "s")"

        for entry in files where entry.mediaMode == .tvShow {
            let parsedQuery = entry.parsedCurrentQuery
            entry.queryText = [showTitle, parsedQuery.episodeCode]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            await search(file: entry)
        }

        batchStatusMessage = "Applied \(showTitle). Review any yellow badges, then fast-save the tagged files."
    }

    func searchAllFiles() async {
        for entry in files {
            await search(file: entry)
        }
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

    private func refreshBatchQuerySuggestion() {
        guard selectedMode == .tvShow,
              batchQueryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let titles = files
            .map { $0.parsedCurrentQuery.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let title = titles.first else {
            return
        }

        batchQueryText = title
    }

    private func resetBatchSearch() {
        batchQueryText = ""
        batchSearchResults = []
        selectedBatchResult = nil
        isBatchSearching = false
        isBatchSaving = false
        batchStatusMessage = "Search for the show once, then apply it to every loaded episode."
        batchErrorMessage = nil
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
