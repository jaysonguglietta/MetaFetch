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

enum TVBatchTab: String, CaseIterable, Identifiable {
    case series
    case seasons
    case data
    case cover

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .series:
            return "Series"
        case .seasons:
            return "Seasons"
        case .data:
            return "Data"
        case .cover:
            return "Cover"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static let safetyBackupsPreferenceKey = "MetaFetchCreateSafetyBackups"
    private static let posterSavingDefaultKey = "MetaFetchPosterSavingDefault"
    private static let autoApplyClearTVBatchMatchesKey = "MetaFetchAutoApplyClearTVBatchMatches"
    private static let renameAfterSaveKey = "MetaFetchRenameAfterSave"
    private static let movieRenameTemplateKey = "MetaFetchMovieRenameTemplate"
    private static let tvRenameTemplateKey = "MetaFetchTVRenameTemplate"
    private static let watchFolderPollingInterval: TimeInterval = 12

    @Published private(set) var files: [MovieFileEntry] = []
    @Published var selectedFileID: UUID?
    @Published var isFileImporterPresented = false
    @Published var isFolderImporterPresented = false
    @Published var isWatchFolderImporterPresented = false
    @Published var noticeMessage: String?
    @Published var selectedMode: MediaLibraryMode?
    @Published var queueFilter: FileQueueFilter = .all
    @Published var updateState: AppUpdateState = .idle
    @Published var batchQueryText = ""
    @Published var batchSearchResults: [MediaSearchResult] = []
    @Published var selectedBatchResult: MediaSearchResult?
    @Published var selectedBatchTab: TVBatchTab = .series
    @Published var isBatchSearching = false
    @Published var isBatchSaving = false
    @Published var batchStatusMessage = "Search for the show once, then apply it to every loaded episode."
    @Published var batchErrorMessage: String?
    @Published var lastSaveReport: SaveReport?
    @Published var presentedSaveReport: SaveReport?
    @Published var tmdbAPIKey: String {
        didSet {
            MetadataProviderPreferences.tmdbAPIKey = tmdbAPIKey
        }
    }
    @Published var omdbAPIKey: String {
        didSet {
            MetadataProviderPreferences.omdbAPIKey = omdbAPIKey
        }
    }
    @Published var preferredProviderSource: MetadataProviderSource {
        didSet {
            MetadataProviderPreferences.preferredProviderSource = preferredProviderSource
        }
    }
    @Published var createSafetyBackups: Bool {
        didSet {
            UserDefaults.standard.set(createSafetyBackups, forKey: Self.safetyBackupsPreferenceKey)
        }
    }
    @Published var posterSavingDefault: Bool {
        didSet {
            UserDefaults.standard.set(posterSavingDefault, forKey: Self.posterSavingDefaultKey)
            for file in files {
                file.posterSavingEnabled = posterSavingDefault
            }
        }
    }
    @Published var autoApplyClearTVBatchMatches: Bool {
        didSet {
            UserDefaults.standard.set(autoApplyClearTVBatchMatches, forKey: Self.autoApplyClearTVBatchMatchesKey)
        }
    }
    @Published var renameAfterSave: Bool {
        didSet {
            UserDefaults.standard.set(renameAfterSave, forKey: Self.renameAfterSaveKey)
        }
    }
    @Published var movieRenameTemplate: String {
        didSet {
            UserDefaults.standard.set(movieRenameTemplate, forKey: Self.movieRenameTemplateKey)
        }
    }
    @Published var tvRenameTemplate: String {
        didSet {
            UserDefaults.standard.set(tvRenameTemplate, forKey: Self.tvRenameTemplateKey)
        }
    }
    @Published var watchedFolderURL: URL?
    @Published var isWatchingFolder = false
    @Published private(set) var providerHealthRecords: [ProviderHealthRecord] = ProviderHealthHistory.records()
    @Published private(set) var taggingHistoryRecords: [TaggingHistoryRecord] = TaggingHistoryStore.records()

    private let searchService: MediaSearchServing
    private let metadataWriter: MetadataWriting
    private let updateService: AppUpdateChecking
    private let headroomInspector: MP4HeadroomInspecting
    private let currentMetadataReader = MP4CurrentMetadataReader()
    private var watchFolderTimer: Timer?

    init(
        searchService: MediaSearchServing = MetadataCatalogSearchService(),
        metadataWriter: MetadataWriting = MP4MetadataWriter(),
        updateService: AppUpdateChecking = GitHubReleaseUpdateService(),
        headroomInspector: MP4HeadroomInspecting = MP4HeadroomInspector()
    ) {
        self.searchService = searchService
        self.metadataWriter = metadataWriter
        self.updateService = updateService
        self.headroomInspector = headroomInspector
        self.createSafetyBackups = UserDefaults.standard.bool(forKey: Self.safetyBackupsPreferenceKey)
        self.tmdbAPIKey = MetadataProviderPreferences.tmdbAPIKey
        self.omdbAPIKey = MetadataProviderPreferences.omdbAPIKey
        self.preferredProviderSource = MetadataProviderPreferences.preferredProviderSource
        self.posterSavingDefault = UserDefaults.standard.object(forKey: Self.posterSavingDefaultKey) as? Bool ?? true
        self.autoApplyClearTVBatchMatches = UserDefaults.standard.bool(forKey: Self.autoApplyClearTVBatchMatchesKey)
        self.renameAfterSave = UserDefaults.standard.bool(forKey: Self.renameAfterSaveKey)
        self.movieRenameTemplate = UserDefaults.standard.string(forKey: Self.movieRenameTemplateKey)?.trimmedNilIfBlank ?? RenameTemplateDefaults.movie
        self.tvRenameTemplate = UserDefaults.standard.string(forKey: Self.tvRenameTemplateKey)?.trimmedNilIfBlank ?? RenameTemplateDefaults.tv
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

    var filteredFiles: [MovieFileEntry] {
        files.filter(matchesQueueFilter)
    }

    var queueFilterSummary: String {
        if queueFilter == .all {
            return "\(files.count) loaded"
        }

        return "\(filteredFiles.count) of \(files.count) shown"
    }

    var watchFolderSummary: String {
        guard let watchedFolderURL else {
            return "No watch folder selected."
        }

        return isWatchingFolder
            ? "Watching \(watchedFolderURL.lastPathComponent) every \(Int(Self.watchFolderPollingInterval)) seconds."
            : "Watch folder selected: \(watchedFolderURL.lastPathComponent)."
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1"
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

        let expandedImport = MediaImportURLExpander.expandedMediaFileURLs(from: urls)
        let validFiles = expandedImport.urls
            .compactMap(MediaFileImportValidator.validatedImport)
        let rejectedCount = expandedImport.rejectedCount + expandedImport.urls.count - validFiles.count

        guard !validFiles.isEmpty else {
            noticeMessage = expandedImport.scannedFolderCount > 0
                ? "No local, writable `.mp4` files were found in the selected folder."
                : "Only local, writable `.mp4` files are accepted right now."
            return
        }

        var knownPaths = Set(files.map { $0.fileURL.standardizedFileURL.path })
        var duplicateCount = 0
        let newEntries = validFiles.compactMap { validatedFile -> MovieFileEntry? in
            let url = validatedFile.url
            guard knownPaths.insert(url.path).inserted else {
                duplicateCount += 1
                return nil
            }

            let entry = MovieFileEntry(
                fileURL: url,
                mediaMode: selectedMode,
                importIdentity: validatedFile.identity
            )
            entry.posterSavingEnabled = posterSavingDefault
            return entry
        }

        guard !newEntries.isEmpty else {
            noticeMessage = importSummary(
                addedCount: 0,
                duplicateCount: duplicateCount,
                rejectedCount: rejectedCount,
                scannedFolderCount: expandedImport.scannedFolderCount
            ) ?? "Those MP4 files are already loaded."
            return
        }

        noticeMessage = importSummary(
            addedCount: newEntries.count,
            duplicateCount: duplicateCount,
            rejectedCount: rejectedCount,
            scannedFolderCount: expandedImport.scannedFolderCount
        )
        files.append(contentsOf: newEntries)
        refreshBatchQuerySuggestion()

        if selectedFileID == nil {
            selectedFileID = newEntries.first?.id
        }

        for entry in newEntries {
            Task {
                await search(file: entry)
            }
            Task {
                await loadCurrentMetadata(for: entry)
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

    func removeFilteredFiles(at offsets: IndexSet) {
        let visibleFiles = filteredFiles
        let removedIDs = offsets.compactMap { index in
            visibleFiles.indices.contains(index) ? visibleFiles[index].id : nil
        }

        files.removeAll { removedIDs.contains($0.id) }

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
        file.searchGeneration += 1
        let searchGeneration = file.searchGeneration

        guard !parsedQuery.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            file.isSearching = false
            file.errorMessage = file.mediaMode.emptyQueryError
            file.statusMessage = "Waiting for a title"
            return
        }

        file.isSearching = true
        file.errorMessage = nil
        file.statusMessage = searchStatusMessage(for: file.mediaMode, query: query)

        do {
            let searchResponse = try await searchResponse(matching: query, mode: file.mediaMode)
            let results = searchResponse.results
            guard file.searchGeneration == searchGeneration else {
                return
            }

            guard file.queryText.trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                file.isSearching = false
                file.statusMessage = "Search text changed"
                file.errorMessage = "Run search again to use the updated title."
                return
            }

            let previousSelectionID = file.selectedResult?.id
            let preservedSelection: MediaSearchResult?
            file.searchResults = results
            file.providerDiagnostics = providerDiagnosticSummary(for: searchResponse, mode: file.mediaMode)
            recordProviderDiagnostics(searchResponse.diagnostics)
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
            guard file.searchGeneration == searchGeneration else {
                return
            }

            file.isSearching = false
            file.statusMessage = "Search failed"
            file.errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func save(file: MovieFileEntry) async -> Bool {
        let reportEntry = await saveAndBuildReportEntry(file: file)
        let report = SaveReport(createdAt: Date(), entries: [reportEntry])
        lastSaveReport = report
        presentedSaveReport = report
        return reportEntry.didSucceed
    }

    func inspectHeadroom(for file: MovieFileEntry) async {
        guard let selectedResult = file.selectedResult else {
            file.errorMessage = file.mediaMode.saveSelectionError
            return
        }

        let resultForInspection = file.metadataDraft
            .applying(to: selectedResult)
            .replacingArtworkURL(file.selectedArtworkURL)

        file.isInspectingHeadroom = true
        file.headroomInspection = nil

        let inspection = await headroomInspector.inspect(
            fileURL: file.fileURL,
            result: resultForInspection,
            includeArtwork: file.willSaveArtwork
        )

        file.headroomInspection = inspection
        file.isInspectingHeadroom = false
        file.statusMessage = inspection.headline
    }

    func resetProviderHealthHistory() {
        ProviderHealthHistory.reset()
        providerHealthRecords = []
    }

    func resetTaggingHistory() {
        TaggingHistoryStore.reset()
        taggingHistoryRecords = []
    }

    private func loadCurrentMetadata(for file: MovieFileEntry) async {
        do {
            let snapshot = try await currentMetadataReader.read(from: file.fileURL)
            file.currentMetadataSnapshot = snapshot.hasReadableValues ? snapshot : nil
            file.currentMetadataError = nil
        } catch {
            file.currentMetadataSnapshot = nil
            file.currentMetadataError = error.localizedDescription
        }
    }

    private func saveAndBuildReportEntry(
        file: MovieFileEntry,
        includeArtworkOverride: Bool? = nil
    ) async -> SaveReportEntry {
        let startedAt = Date()

        guard let selectedResult = file.selectedResult else {
            file.errorMessage = file.mediaMode.saveSelectionError
            return SaveReportEntry(
                filename: file.filename,
                fileURL: file.fileURL,
                title: file.filename,
                outcome: nil,
                errorMessage: file.mediaMode.saveSelectionError,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        guard file.metadataDraft.isValid(for: selectedResult) else {
            let message = "Enter a title before saving metadata."
            file.errorMessage = message
            file.statusMessage = "Metadata editor needs a title"
            return SaveReportEntry(
                filename: file.filename,
                fileURL: file.fileURL,
                title: selectedResult.trackName,
                outcome: nil,
                errorMessage: message,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        if file.requiresSeriesOnlySaveConfirmation {
            let message = "This is a series-level TV match for an episode query. Confirm the series-only save before writing metadata."
            file.errorMessage = message
            file.statusMessage = "Series-only save needs confirmation"
            return SaveReportEntry(
                filename: file.filename,
                fileURL: file.fileURL,
                title: selectedResult.trackName,
                outcome: nil,
                errorMessage: message,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        do {
            try MediaFileImportValidator.validateStillSafeToWrite(
                file.fileURL,
                expectedIdentity: file.importIdentity
            )
        } catch {
            file.errorMessage = error.localizedDescription
            file.statusMessage = "Save stopped before writing"
            return SaveReportEntry(
                filename: file.filename,
                fileURL: file.fileURL,
                title: selectedResult.trackName,
                outcome: nil,
                errorMessage: error.localizedDescription,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        let includeArtwork = includeArtworkOverride ?? file.willSaveArtwork
        let resultForWriting = file.metadataDraft
            .applying(to: selectedResult)
            .replacingArtworkURL(file.selectedArtworkURL)
        let fileID = file.id
        file.isSaving = true
        file.saveProgress = nil
        file.errorMessage = nil
        file.lastSaveOutcome = nil
        file.statusMessage = includeArtwork
            ? "Preparing artwork and metadata"
            : "Preparing metadata-only fast path"

        do {
            if includeArtwork && resultForWriting.artworkURL != nil {
                _ = try await ArtworkPipeline.shared.preparedArtwork(for: resultForWriting.artworkURL)
            }

            file.statusMessage = includeArtwork
                ? "Starting MP4 rewrite with artwork and metadata"
                : "Starting metadata-only fast save"
            file.saveProgress = 0

            let outcome = try await metadataWriter.writeMetadata(
                to: file.fileURL,
                using: resultForWriting,
                includeArtwork: includeArtwork,
                options: MetadataWriteOptions(createSafetyBackup: createSafetyBackups),
                progressHandler: { [weak self] progress in
                    await self?.applySaveProgress(progress, toFileWithID: fileID)
                }
            )
            file.saveProgress = 1
            file.lastSavedAt = Date()
            file.lastSaveOutcome = outcome
            file.currentMetadataSnapshot = MP4CurrentMetadataSnapshot(
                result: resultForWriting,
                hasArtwork: includeArtwork
            )
            file.currentMetadataError = nil
            recordTaggingHistory(
                file: file,
                result: resultForWriting,
                outcome: outcome
            )
            let renameMessage = renameSavedFileIfNeeded(file: file, result: resultForWriting)
            file.importIdentity = MediaFileImportValidator.identity(for: file.fileURL)
            file.isSaving = false
            file.saveProgress = nil
            file.statusMessage = renameMessage ?? "Verified \(outcome.path.label.lowercased()) at \(file.lastSavedAt?.formatted(date: .omitted, time: .shortened) ?? "just now")"
            advanceSelection(afterSaving: file)
            return SaveReportEntry(
                filename: file.filename,
                fileURL: file.fileURL,
                title: resultForWriting.trackName,
                outcome: outcome,
                errorMessage: nil,
                duration: Date().timeIntervalSince(startedAt)
            )
        } catch {
            file.isSaving = false
            file.saveProgress = nil
            file.statusMessage = "Save failed"
            file.errorMessage = error.localizedDescription
            return SaveReportEntry(
                filename: file.filename,
                fileURL: file.fileURL,
                title: resultForWriting.trackName,
                outcome: nil,
                errorMessage: error.localizedDescription,
                duration: Date().timeIntervalSince(startedAt)
            )
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

        var reportEntries: [SaveReportEntry] = []

        for (index, entry) in taggedFiles.enumerated() {
            if canUseTVBatchTools {
                batchStatusMessage = "Saving \(index + 1) of \(taggedFiles.count): \(entry.filename)"
            }

            reportEntries.append(await saveAndBuildReportEntry(file: entry))
        }

        let report = SaveReport(createdAt: Date(), entries: reportEntries)
        lastSaveReport = report
        presentedSaveReport = report

        let verifiedSaveCount = report.successCount

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
            let searchResponse = try await searchResponse(matching: query, mode: .tvShow)
            let results = searchResponse.results
            batchSearchResults = results
            recordProviderDiagnostics(searchResponse.diagnostics)
            selectedBatchResult = SearchSelectionPolicy.suggestedAutoSelection(from: results)
            isBatchSearching = false

            if let selectedBatchResult {
                batchStatusMessage = "Auto-selected \(selectedBatchResult.trackName). Click a card to apply a different show."
                if autoApplyClearTVBatchMatches {
                    await applyBatchResultToAllFiles(selectedBatchResult)
                    return
                }
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
        selectedBatchTab = .seasons
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

    func selectBatchTab(_ tab: TVBatchTab) {
        selectedBatchTab = tab
        batchErrorMessage = nil
    }

    func useEpisodeArtworkForBatch() {
        for entry in files {
            entry.artworkOverrideURL = nil
        }

        selectedBatchTab = .cover
        batchErrorMessage = nil
        batchStatusMessage = "Using episode-specific artwork wherever TVMaze provides it."
    }

    func useSeriesArtworkForBatch() {
        guard let artworkURL = selectedBatchResult?.artworkURL else {
            batchErrorMessage = "Pick a series with cover art before applying one cover to the batch."
            batchStatusMessage = "No series cover is selected yet."
            selectedBatchTab = .cover
            return
        }

        for entry in files where entry.selectedResult != nil {
            entry.artworkOverrideURL = artworkURL
        }

        selectedBatchTab = .cover
        batchErrorMessage = nil
        batchStatusMessage = "Using the selected series cover for every tagged episode."
    }

    func useSeriesArtwork(for entry: MovieFileEntry) {
        guard let artworkURL = selectedBatchResult?.artworkURL else {
            batchErrorMessage = "Pick a series with cover art before applying a series cover."
            batchStatusMessage = "No series cover is selected yet."
            selectedBatchTab = .cover
            return
        }

        entry.artworkOverrideURL = artworkURL
        selectedBatchTab = .cover
        batchErrorMessage = nil
        batchStatusMessage = "Using the selected series cover for \(entry.filename)."
    }

    func useEpisodeArtwork(for entry: MovieFileEntry) {
        entry.artworkOverrideURL = nil
        selectedBatchTab = .cover
        batchErrorMessage = nil
        batchStatusMessage = "Using episode artwork for \(entry.filename)."
    }

    func searchAllFiles() async {
        for entry in files {
            await search(file: entry)
        }
    }

    func retryFailedSaves(from report: SaveReport, includeArtwork: Bool? = nil) async {
        let failedURLs = Set(report.entries.filter { !$0.didSucceed }.map { $0.fileURL.standardizedFileURL.path })
        let retryFiles = files.filter { failedURLs.contains($0.fileURL.standardizedFileURL.path) && $0.selectedResult != nil }

        guard !retryFiles.isEmpty else {
            noticeMessage = "No failed saves from that report are still loaded and retryable."
            return
        }

        isBatchSaving = true
        defer {
            isBatchSaving = false
        }

        var entries: [SaveReportEntry] = []
        for file in retryFiles {
            entries.append(await saveAndBuildReportEntry(file: file, includeArtworkOverride: includeArtwork))
        }

        let retryReport = SaveReport(createdAt: Date(), entries: entries)
        lastSaveReport = retryReport
        presentedSaveReport = retryReport
    }

    func clearCompletedFiles() {
        let savedIDs = Set(files.filter { $0.lastSavedAt != nil }.map(\.id))
        guard !savedIDs.isEmpty else {
            noticeMessage = "No saved files are ready to clear."
            return
        }

        files.removeAll { savedIDs.contains($0.id) }
        if let selectedFileID, savedIDs.contains(selectedFileID) {
            self.selectedFileID = files.first?.id
        }
        noticeMessage = "Cleared \(savedIDs.count) saved file\(savedIDs.count == 1 ? "" : "s") from the queue."
    }

    func startWatchingFolder(_ folderURL: URL) {
        guard selectedMode != nil else {
            noticeMessage = "Choose Movie or TV Show before starting a watch folder."
            return
        }

        watchedFolderURL = folderURL.standardizedFileURL
        isWatchingFolder = true
        scanWatchedFolder()

        watchFolderTimer?.invalidate()
        watchFolderTimer = Timer.scheduledTimer(withTimeInterval: Self.watchFolderPollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanWatchedFolder()
            }
        }
    }

    func stopWatchingFolder() {
        watchFolderTimer?.invalidate()
        watchFolderTimer = nil
        isWatchingFolder = false
        watchedFolderURL = nil
    }

    func scanWatchedFolder() {
        guard isWatchingFolder,
              let watchedFolderURL else {
            return
        }

        let expandedImport = MediaImportURLExpander.expandedMediaFileURLs(from: [watchedFolderURL])
        let knownPaths = Set(files.map { $0.fileURL.standardizedFileURL.path })
        let newURLs = expandedImport.urls
            .compactMap(MediaFileImportValidator.validatedImportURL)
            .filter { !knownPaths.contains($0.standardizedFileURL.path) }

        guard !newURLs.isEmpty else {
            return
        }

        importFiles(from: newURLs)
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
            revealDownloadedUpdate(at: fileURL)
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func openReleasePage(for update: AppUpdate) {
        NSWorkspace.shared.open(update.releaseURL)
    }

    func revealDownloadedUpdate(at fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
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

    private func matchesQueueFilter(_ file: MovieFileEntry) -> Bool {
        switch queueFilter {
        case .all:
            return true
        case .exact:
            return file.selectedResult?.matchConfidence == .exact
        case .needsReview:
            return file.lastSavedAt == nil && !file.canSave
        case .seriesOnly:
            return file.isSeriesOnlySelectionForEpisodeQuery
        case .saved:
            return file.lastSavedAt != nil
        case .failed:
            return file.errorMessage != nil || file.statusMessage.lowercased().contains("failed")
        case .hasPoster:
            return file.hasSelectedArtwork
        }
    }

    private func searchResponse(matching query: String, mode: MediaLibraryMode) async throws -> MetadataSearchResponse {
        if let diagnosticSearchService = searchService as? MetadataDiagnosticSearchServing {
            return try await diagnosticSearchService.searchWithDiagnostics(matching: query, mode: mode)
        }

        let results = try await searchService.search(matching: query, mode: mode)
        return MetadataSearchResponse(results: results)
    }

    private func providerDiagnosticSummary(for response: MetadataSearchResponse, mode: MediaLibraryMode) -> String {
        let results = response.results
        if !response.diagnostics.isEmpty {
            let prefix: String
            switch mode {
            case .movie:
                prefix = "Provider priority: \(preferredProviderSource.label)."
            case .tvShow:
                prefix = "TV provider diagnostics."
            }

            return ([prefix] + response.diagnostics.map(\.summary)).joined(separator: " • ")
        }

        switch mode {
        case .tvShow:
            return "TVMaze searched. \(results.count) result\(results.count == 1 ? "" : "s") returned."
        case .movie:
            let countsBySource = Dictionary(grouping: results, by: \.sourceName)
                .mapValues(\.count)
            var parts = ["Provider priority: \(preferredProviderSource.label)."]

            for sourceName in ["Wikipedia", "TMDb", "OMDb"] {
                if let count = countsBySource[sourceName], count > 0 {
                    parts.append("\(sourceName): \(count)")
                } else if sourceName == "TMDb", tmdbAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append("TMDb skipped: no key")
                } else if sourceName == "OMDb", omdbAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append("OMDb skipped: no key")
                } else {
                    parts.append("\(sourceName): no results")
                }
            }

            return parts.joined(separator: " • ")
        }
    }

    private func recordProviderDiagnostics(_ diagnostics: [MetadataProviderDiagnostic]) {
        ProviderHealthHistory.record(diagnostics)
        providerHealthRecords = ProviderHealthHistory.records()
    }

    private func recordTaggingHistory(
        file: MovieFileEntry,
        result: MediaSearchResult,
        outcome: MetadataWriteOutcome
    ) {
        TaggingHistoryStore.record(TaggingHistoryRecord(
            filename: file.filename,
            filePath: file.fileURL.path,
            title: result.trackName,
            mode: file.mediaMode.displayName,
            sourceName: result.sourceName,
            writePath: outcome.path.label,
            includedArtwork: outcome.includedArtwork
        ))
        taggingHistoryRecords = TaggingHistoryStore.records()
    }

    private func renameSavedFileIfNeeded(file: MovieFileEntry, result: MediaSearchResult) -> String? {
        guard renameAfterSave else {
            return nil
        }

        let template = result.mediaKind == .movie ? movieRenameTemplate : tvRenameTemplate
        let renderedName = renderedFilename(from: template, result: result)
        guard !renderedName.isEmpty else {
            file.errorMessage = "Rename template produced an empty filename."
            return "Saved, but rename template was empty."
        }

        let targetURL = uniqueURLForRename(
            directory: file.fileURL.deletingLastPathComponent(),
            filename: renderedName,
            extension: file.fileURL.pathExtension
        )

        guard targetURL.standardizedFileURL.path != file.fileURL.standardizedFileURL.path else {
            return nil
        }

        do {
            try FileManager.default.moveItem(at: file.fileURL, to: targetURL)
            file.fileURL = targetURL
            return "Saved and renamed to \(targetURL.lastPathComponent)"
        } catch {
            file.errorMessage = "Saved, but rename failed: \(error.localizedDescription)"
            return "Saved, but rename failed."
        }
    }

    private func renderedFilename(from template: String, result: MediaSearchResult) -> String {
        let seasonEpisode = result.seasonEpisodeLabel ?? ""
        let values = [
            "{title}": result.trackName,
            "{sort_title}": result.sortTitle ?? result.trackName,
            "{series}": result.seriesName ?? result.trackName,
            "{sort_series}": result.sortSeriesName ?? result.seriesName ?? result.trackName,
            "{year}": result.releaseYear ?? "",
            "{season}": result.seasonNumber.map { String(format: "%02d", $0) } ?? "",
            "{episode}": result.episodeNumber.map { String(format: "%02d", $0) } ?? "",
            "{season_episode}": seasonEpisode,
        ]

        let rendered = values.reduce(template) { partialResult, token in
            partialResult.replacingOccurrences(of: token.key, with: token.value)
        }

        return sanitizedFilename(rendered)
    }

    private func sanitizedFilename(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[/:]"#, with: " - ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
    }

    private func uniqueURLForRename(directory: URL, filename: String, extension pathExtension: String) -> URL {
        let baseURL = directory.appendingPathComponent(filename).appendingPathExtension(pathExtension)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        for index in 2...999 {
            let candidate = directory
                .appendingPathComponent("\(filename) \(index)")
                .appendingPathExtension(pathExtension)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory
            .appendingPathComponent("\(filename) \(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
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
        selectedBatchTab = .series
        isBatchSearching = false
        isBatchSaving = false
        batchStatusMessage = "Search for the show once, then apply it to every loaded episode."
        batchErrorMessage = nil
    }

    private func importSummary(
        addedCount: Int,
        duplicateCount: Int,
        rejectedCount: Int,
        scannedFolderCount: Int
    ) -> String? {
        var parts: [String] = []

        if addedCount > 0 {
            if scannedFolderCount > 0 {
                parts.append("Added \(addedCount) MP4 file\(addedCount == 1 ? "" : "s") from \(scannedFolderCount) folder\(scannedFolderCount == 1 ? "" : "s")")
            } else {
                parts.append("Added \(addedCount) MP4 file\(addedCount == 1 ? "" : "s")")
            }
        }

        if duplicateCount > 0 {
            parts.append("skipped \(duplicateCount) duplicate\(duplicateCount == 1 ? "" : "s")")
        }

        if rejectedCount > 0 {
            parts.append("skipped \(rejectedCount) unsupported file\(rejectedCount == 1 ? "" : "s")")
        }

        guard !parts.isEmpty,
              scannedFolderCount > 0 || duplicateCount > 0 || rejectedCount > 0 else {
            return nil
        }

        let message = parts.joined(separator: ", ")
        return message.prefix(1).uppercased() + message.dropFirst() + "."
    }
}

struct ValidatedMediaFile: Sendable {
    let url: URL
    let identity: MediaFileIdentity?
}

struct ExpandedImportURLs: Sendable {
    let urls: [URL]
    let rejectedCount: Int
    let scannedFolderCount: Int
}

enum MediaImportURLExpander {
    static func expandedMediaFileURLs(from urls: [URL]) -> ExpandedImportURLs {
        var expandedURLs: [URL] = []
        var rejectedCount = 0
        var scannedFolderCount = 0

        for url in urls {
            let standardizedURL = url.standardizedFileURL

            guard standardizedURL.isFileURL else {
                rejectedCount += 1
                continue
            }

            if isDirectory(standardizedURL) {
                scannedFolderCount += 1
                expandedURLs.append(contentsOf: mp4Files(in: standardizedURL))
            } else if standardizedURL.pathExtension.caseInsensitiveCompare("mp4") == .orderedSame {
                expandedURLs.append(standardizedURL)
            } else {
                rejectedCount += 1
            }
        }

        let uniqueSortedURLs = Array(Set(expandedURLs.map(\.standardizedFileURL)))
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        return ExpandedImportURLs(
            urls: uniqueSortedURLs,
            rejectedCount: rejectedCount,
            scannedFolderCount: scannedFolderCount
        )
    }

    private static func isDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isReadableKey,
            .isSymbolicLinkKey,
        ]) else {
            return false
        }

        return values.isDirectory == true &&
            values.isReadable == true &&
            values.isSymbolicLink != true
    }

    private static func mp4Files(in folderURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isReadableKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []

        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ]),
               values.isDirectory == true {
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard fileURL.pathExtension.caseInsensitiveCompare("mp4") == .orderedSame,
                  MediaFileImportValidator.validatedImport(fileURL) != nil else {
                continue
            }

            files.append(fileURL.standardizedFileURL)
        }

        return files
    }
}

struct MediaFileIdentity: Equatable, Sendable {
    let systemNumber: UInt64
    let fileNumber: UInt64
}

enum MediaFileImportValidator {
    enum ValidationError: LocalizedError {
        case unsafeFile
        case fileChanged

        var errorDescription: String? {
            switch self {
            case .unsafeFile:
                return "MetaFetch stopped before saving because the file is no longer a local, writable `.mp4` file."
            case .fileChanged:
                return "MetaFetch stopped before saving because this file changed after it was imported. Remove it and add it again before tagging."
            }
        }
    }

    static func validatedImportURL(_ url: URL) -> URL? {
        validatedImport(url)?.url
    }

    static func validatedImport(_ url: URL) -> ValidatedMediaFile? {
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

        return ValidatedMediaFile(
            url: standardizedURL,
            identity: identity(for: standardizedURL)
        )
    }

    static func validateStillSafeToWrite(
        _ url: URL,
        expectedIdentity: MediaFileIdentity?
    ) throws {
        guard let validatedFile = validatedImport(url) else {
            throw ValidationError.unsafeFile
        }

        if let expectedIdentity,
           let currentIdentity = validatedFile.identity,
           currentIdentity != expectedIdentity {
            throw ValidationError.fileChanged
        }
    }

    static func identity(for url: URL) -> MediaFileIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.standardizedFileURL.path),
              let systemNumber = unsignedIntegerAttribute(attributes[.systemNumber]),
              let fileNumber = unsignedIntegerAttribute(attributes[.systemFileNumber]) else {
            return nil
        }

        return MediaFileIdentity(
            systemNumber: systemNumber,
            fileNumber: fileNumber
        )
    }

    private static func unsignedIntegerAttribute(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            return number.uint64Value
        }

        if let value = value as? UInt64 {
            return value
        }

        if let value = value as? UInt {
            return UInt64(value)
        }

        if let value = value as? Int, value >= 0 {
            return UInt64(value)
        }

        return nil
    }
}

private extension String {
    var trimmedNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
