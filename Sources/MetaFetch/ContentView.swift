import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var isSidebarVisible = true
    @State private var isHelpPresented = false
    @State private var isUpdatePresented = false
    @State private var isProviderSettingsPresented = false
    @State private var isAdvancedPreferencesPresented = false
    @State private var isStartOverConfirmationPresented = false

    var body: some View {
        ZStack {
            RetroBackdrop()

            HStack(spacing: 0) {
                if isSidebarVisible {
                    SidebarView(model: model)
                        .frame(width: 330)
                        .transition(.identity)

                    Rectangle()
                        .fill(RetroTheme.paper.opacity(0.08))
                        .frame(width: 1)
                }

                DetailView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $model.isFileImporterPresented,
            allowedContentTypes: [.mpeg4Movie, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.importFiles(from: urls)
            case .failure(let error):
                model.noticeMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $model.isFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.importFiles(from: urls)
            case .failure(let error):
                model.noticeMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $model.isWatchFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.startWatchingFolder(url)
                }
            case .failure(let error):
                model.noticeMessage = error.localizedDescription
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left") {
                    isSidebarVisible.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .accessibilityHint(isSidebarVisible ? "Hides the file list sidebar." : "Shows the file list sidebar.")

                Button("Help", systemImage: "questionmark.circle") {
                    isHelpPresented = true
                }
                .accessibilityHint("Opens MetaFetch workflow help.")

                Button("Updates", systemImage: "arrow.down.circle") {
                    presentUpdateCheck()
                }
                .disabled(model.updateState.isBusy)
                .help(updateControlHelp)
                .accessibilityHint(updateControlHelp)

                if let selectedMode = model.selectedMode, model.canChooseMode {
                    Menu(selectedMode.displayName) {
                        ForEach(MediaLibraryMode.allCases) { mode in
                            Button(mode.displayName) {
                                model.chooseMode(mode)
                            }
                        }

                        Divider()

                        Button("Choose On Launch") {
                            model.resetModeSelection()
                        }
                    }
                }

                if model.selectedMode != nil {
                    Button("Start Over", systemImage: "arrow.counterclockwise") {
                        if model.files.isEmpty {
                            model.resetModeSelection()
                        } else {
                            isStartOverConfirmationPresented = true
                        }
                    }
                }

                Button("Add MP4 Files", systemImage: "plus") {
                    model.isFileImporterPresented = true
                }
                .disabled(model.selectedMode == nil)
                .help(addFilesControlHelp)
                .accessibilityHint(addFilesControlHelp)

                Button("Add Season Folder", systemImage: "folder.badge.plus") {
                    model.isFolderImporterPresented = true
                }
                .disabled(model.selectedMode == nil)
                .help(folderControlHelp)
                .accessibilityHint(folderControlHelp)

                Button(model.saveAllButtonTitle, systemImage: "square.and.arrow.down") {
                    Task {
                        await model.saveAllTaggedFiles()
                    }
                }
                .disabled(!model.canSaveAnyTaggedFiles || model.isBatchBusy)
                .help(saveAllControlHelp)
                .accessibilityHint(saveAllControlHelp)

                if model.lastSaveReport != nil {
                    Button("Report", systemImage: "checklist") {
                        model.presentedSaveReport = model.lastSaveReport
                    }
                    .help("Reopens the latest save report.")
                    .accessibilityHint("Reopens the latest save report.")
                }

                Menu {
                    Toggle("Create Safety Backups", isOn: $model.createSafetyBackups)

                    Divider()

                    Button("Metadata Providers") {
                        isProviderSettingsPresented = true
                    }

                    Button("Advanced Preferences") {
                        isAdvancedPreferencesPresented = true
                    }

                    Button(model.isWatchingFolder ? "Stop Watch Folder" : "Watch Folder") {
                        if model.isWatchingFolder {
                            model.stopWatchingFolder()
                        } else {
                            model.isWatchFolderImporterPresented = true
                        }
                    }
                    .disabled(model.selectedMode == nil && !model.isWatchingFolder)

                    Button("Clear Completed") {
                        model.clearCompletedFiles()
                    }
                    .disabled(model.batchSavedCount == 0)

                    Button("Add Season Folder") {
                        model.isFolderImporterPresented = true
                    }
                    .disabled(model.selectedMode == nil)
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $isHelpPresented) {
            HelpView(currentMode: model.selectedMode)
        }
        .sheet(isPresented: $isUpdatePresented) {
            UpdateView(model: model)
        }
        .sheet(isPresented: $isProviderSettingsPresented) {
            ProviderSettingsView(model: model)
        }
        .sheet(isPresented: $isAdvancedPreferencesPresented) {
            AdvancedPreferencesView(model: model)
        }
        .sheet(item: $model.presentedSaveReport) { report in
            SaveReportView(model: model, report: report)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMetaFetchHelp)) { _ in
            isHelpPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkForMetaFetchUpdates)) { _ in
            presentUpdateCheck()
        }
        .confirmationDialog(
            "Start over?",
            isPresented: $isStartOverConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Loaded Files And Choose Again", role: .destructive) {
                model.startOver()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes files from MetaFetch’s current queue. It does not delete or modify your MP4 files.")
        }
    }

    private func presentUpdateCheck() {
        isUpdatePresented = true

        Task {
            await model.checkForUpdates()
        }
    }

    private var updateControlHelp: String {
        model.updateState.isBusy
        ? "MetaFetch is already checking for updates."
        : "Checks GitHub Releases for a newer MetaFetch version."
    }

    private var addFilesControlHelp: String {
        model.selectedMode == nil
        ? "Choose Movie or TV Show before importing MP4 files."
        : "Opens a file picker for local MP4 files or folders."
    }

    private var folderControlHelp: String {
        model.selectedMode == nil
        ? "Choose Movie or TV Show before importing a folder."
        : "Imports writable MP4 files from a folder and its subfolders."
    }

    private var saveAllControlHelp: String {
        if model.isBatchBusy {
            return "Wait for the current TV batch operation to finish before saving."
        }

        if !model.canSaveAnyTaggedFiles {
            return "Select at least one metadata match before saving files."
        }

        return "Saves metadata for every file with a selected match."
    }
}

private struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                MetaFetchSidebarBrand()

                Text(model.selectedMode?.sidebarHeading ?? "Choose Your\nMetadata Deck")
                    .font(RetroTheme.heroFont(30))
                    .foregroundStyle(RetroTheme.paper)

                Text(model.selectedMode?.sidebarDescription ?? "Pick Movie or TV Show in the main deck, then drop in MP4 files and start tagging.")
                    .font(RetroTheme.bodyFont(14))
                    .foregroundStyle(RetroTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    SidebarStat(label: "Loaded", value: "\(model.files.count)", accent: RetroTheme.magenta)
                    SidebarStat(
                        label: model.selectedMode?.statsReadyLabel ?? "Ready",
                        value: "\(model.files.filter { $0.selectedResult != nil }.count)",
                        accent: RetroTheme.lime
                    )
                }

                Picker("Queue Filter", selection: $model.queueFilter) {
                    ForEach(FileQueueFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .tint(RetroTheme.cyan)
                .help("Filters the loaded file queue without removing files.")

                Text(model.queueFilterSummary)
                    .font(RetroTheme.bodyFont(12))
                    .foregroundStyle(RetroTheme.muted)
            }
            .padding(20)
            .retroPanel(accent: RetroTheme.magenta)

            if let noticeMessage = model.noticeMessage {
                Text(noticeMessage)
                    .font(RetroTheme.bodyFont(13))
                    .foregroundStyle(RetroTheme.gold)
                    .padding(.horizontal, 4)
            }

            if model.canUseTVBatchTools {
                TVBatchPanel(model: model)
            }

            List(selection: $model.selectedFileID) {
                ForEach(model.filteredFiles) { entry in
                    SidebarRow(entry: entry)
                        .tag(entry.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onDelete(perform: model.removeFilteredFiles)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.files.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    RetroPill(
                        text: model.selectedMode == nil ? "Choose A Mode" : "No Tapes Loaded",
                        accent: RetroTheme.gold
                    )

                    Text(
                        model.selectedMode == nil
                        ? "Pick Movie or TV Show in the main deck, then drop one or more MP4 files to start tagging."
                        : "Drop one or more MP4 files in the main deck to start matching \(model.selectedMode == .movie ? "movies" : "episodes")."
                    )
                        .font(RetroTheme.bodyFont(14))
                        .foregroundStyle(RetroTheme.muted)
                }
                .padding(18)
                .retroPanel(accent: RetroTheme.gold)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TVBatchPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TV Batch Deck".uppercased())
                        .font(RetroTheme.labelFont(11))
                        .tracking(2.2)
                        .foregroundStyle(RetroTheme.cyan)

                    Text("Same-show episodes are easiest when you scan the whole mini stack, review the badges, then fast-save the tagged ones.")
                        .font(RetroTheme.bodyFont(13))
                        .foregroundStyle(RetroTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                SidebarStat(label: "Matched", value: "\(model.batchMatchedCount)", accent: RetroTheme.lime)
                SidebarStat(label: "Review", value: "\(model.batchNeedsReviewCount)", accent: RetroTheme.gold)
                SidebarStat(label: "Saved", value: "\(model.batchSavedCount)", accent: RetroTheme.cyan)
            }

            VStack(spacing: 8) {
                Button("Search All Episodes") {
                    Task {
                        await model.searchAllFiles()
                    }
                }
                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.cyan))
                .disabled(model.files.isEmpty || model.isBatchBusy)
                .help(searchAllHelp)
                .accessibilityHint(searchAllHelp)

                Button(model.saveAllButtonTitle) {
                    Task {
                        await model.saveAllTaggedFiles()
                    }
                }
                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.lime))
                .disabled(!model.canSaveAnyTaggedFiles || model.isBatchBusy)
                .help(saveAllHelp)
                .accessibilityHint(saveAllHelp)
            }
        }
        .padding(16)
        .retroPanel(accent: RetroTheme.cyan)
    }

    private var searchAllHelp: String {
        if model.files.isEmpty {
            return "Drop TV episode MP4 files before searching the batch."
        }

        if model.isBatchBusy {
            return "Wait for the current TV batch operation to finish."
        }

        return "Searches metadata for every loaded TV episode."
    }

    private var saveAllHelp: String {
        if model.isBatchBusy {
            return "Wait for the current TV batch operation to finish before saving."
        }

        if !model.canSaveAnyTaggedFiles {
            return "Select metadata matches for one or more episodes before saving."
        }

        return "Saves metadata for every ready episode."
    }
}

private struct SidebarStat: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(RetroTheme.labelFont(11))
                .tracking(2)
                .foregroundStyle(accent)

            Text(value)
                .font(RetroTheme.heroFont(20))
                .foregroundStyle(RetroTheme.paper)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel(accent: accent)
    }
}

private struct SidebarRow: View {
    @ObservedObject var entry: MovieFileEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [RetroTheme.magenta, RetroTheme.gold],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 48)

                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(RetroTheme.ink)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    InfoBadge(
                        text: entry.mediaMode.badgeLabel,
                        accent: entry.mediaMode == .movie ? RetroTheme.magenta : RetroTheme.cyan,
                        foreground: RetroTheme.ink
                    )

                    InfoBadge(
                        text: entry.batchReviewLabel,
                        accent: batchAccent,
                        foreground: batchForeground
                    )
                }

                Text(entry.filename)
                    .font(RetroTheme.labelFont(17))
                    .foregroundStyle(RetroTheme.paper)
                    .lineLimit(2)

                Text(entry.sidebarStatus.uppercased())
                    .font(RetroTheme.labelFont(11))
                    .tracking(2.1)
                    .foregroundStyle(iconAccent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel(accent: iconAccent)
    }

    private var iconName: String {
        if entry.isSaving {
            return "arrow.trianglehead.2.clockwise"
        }

        if entry.lastSavedAt != nil {
            return "checkmark"
        }

        if entry.selectedResult != nil {
            return "star.fill"
        }

        return entry.mediaMode.iconName
    }

    private var iconAccent: Color {
        if entry.lastSavedAt != nil {
            return RetroTheme.lime
        }

        if entry.selectedResult != nil {
            return RetroTheme.cyan
        }

        if entry.isSearching {
            return RetroTheme.gold
        }

        return RetroTheme.magenta
    }

    private var batchAccent: Color {
        switch entry.batchReviewLabel {
        case "Exact", "Saved":
            return RetroTheme.lime
        case "Review", "Needs Review", "Series Only":
            return RetroTheme.gold
        case "Saving":
            return RetroTheme.cyan
        default:
            return RetroTheme.paper.opacity(0.22)
        }
    }

    private var batchForeground: Color {
        switch entry.batchReviewLabel {
        case "Exact", "Saved", "Review", "Needs Review", "Series Only", "Saving":
            return RetroTheme.ink
        default:
            return RetroTheme.paper
        }
    }
}

private struct DetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.selectedMode == nil {
            ModeSelectionView(model: model)
        } else if model.canUseTVBatchTools {
            TVBatchWorkspaceView(model: model)
        } else if let selectedFile = model.selectedFile {
            FileWorkspaceView(model: model, entry: selectedFile)
        } else {
            EmptyStateView(model: model)
        }
    }
}

private struct ModeSelectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 34)

                VStack(spacing: 14) {
                    VStack(spacing: 12) {
                        MetaFetchLogoLockup(
                            markSize: 82,
                            wordmarkSize: 42,
                            subtitle: "movie + tv metadata tagging"
                        )
                        RetroPill(text: "Choose Your Deck", accent: RetroTheme.magenta)
                    }

                    Text("What Are We Tagging Today?")
                        .font(RetroTheme.heroFont(42))
                        .foregroundStyle(RetroTheme.paper)
                        .multilineTextAlignment(.center)

                    Text("Pick the library type first so MetaFetch can search with the right brain: films on one side, TV episodes on the other.")
                        .font(RetroTheme.bodyFont(19))
                        .foregroundStyle(RetroTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 760)
                }

                HStack(alignment: .top, spacing: 20) {
                    ForEach(MediaLibraryMode.allCases) { mode in
                        ModeChoiceCard(mode: mode) {
                            model.chooseMode(mode)
                        }
                    }
                }
                .frame(maxWidth: 920)

                if let noticeMessage = model.noticeMessage {
                    Text(noticeMessage)
                        .font(RetroTheme.bodyFont(15))
                        .foregroundStyle(RetroTheme.gold)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .retroPanel(accent: RetroTheme.gold)
                        .frame(maxWidth: 760)
                }

                Spacer(minLength: 26)
            }
            .padding(26)
        }
    }
}

private struct ModeChoiceCard: View {
    let mode: MediaLibraryMode
    let choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(RetroTheme.ink)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [RetroTheme.magenta, RetroTheme.gold],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName.uppercased())
                        .font(RetroTheme.labelFont(14))
                        .tracking(2.2)
                        .foregroundStyle(RetroTheme.gold)

                    Text(mode.modePickerSummary)
                        .font(RetroTheme.heroFont(24))
                        .foregroundStyle(RetroTheme.paper)
                }
            }

            Text(mode.modePickerDetail)
                .font(RetroTheme.bodyFont(15))
                .foregroundStyle(RetroTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                FeatureCard(
                    title: "Search Style",
                    copy: mode == .movie
                        ? "Best for title + year lookups like The Matrix 1999."
                        : "Best for show + episode lookups like Severance S02E04.",
                    accent: RetroTheme.cyan
                )

                FeatureCard(
                    title: "Saved Tags",
                    copy: mode == .movie
                        ? "Writes film metadata, synopsis, artwork, and more into the MP4."
                        : "Writes episode title, series name, season/episode context, artwork, and more into the MP4.",
                    accent: RetroTheme.magenta
                )
            }

            Button("Choose \(mode.displayName)", action: choose)
                .buttonStyle(RetroPrimaryButtonStyle(accent: mode == .movie ? RetroTheme.gold : RetroTheme.cyan))
                .accessibilityHint("Starts the \(mode.displayName) tagging workflow.")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel(accent: mode == .movie ? RetroTheme.gold : RetroTheme.cyan)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.displayName) tagging workflow")
        .accessibilityHint(mode.modePickerDetail)
    }
}

private struct EmptyStateView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let mode = model.selectedMode ?? .movie

        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 30)

                VStack(spacing: 14) {
                    VStack(spacing: 12) {
                        MetaFetchLogoLockup(
                            markSize: 82,
                            wordmarkSize: 42,
                            subtitle: "metadata search + tagging"
                        )
                        RetroPill(text: "1990s Tape Lab", accent: RetroTheme.magenta)
                    }

                    Text(mode.emptyStateTitle)
                        .font(RetroTheme.heroFont(42))
                        .foregroundStyle(RetroTheme.paper)
                        .multilineTextAlignment(.center)

                    Text(mode.emptyStateCopy)
                        .font(RetroTheme.bodyFont(19))
                        .foregroundStyle(RetroTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 720)
                }

                DropZoneCard(
                    mode: mode,
                    compact: false,
                    openPanel: { model.isFileImporterPresented = true },
                    receiveFiles: { model.importFiles(from: $0) }
                )
                .frame(maxWidth: 860)

                Button("Start Over / Choose Movie or TV Show") {
                    model.resetModeSelection()
                }
                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.cyan))

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 18, alignment: .top)
                    ],
                    alignment: .center,
                    spacing: 18
                ) {
                    FeatureCard(
                        title: "Drag + Drop",
                        copy: "Finder-ready intake so the filename can kick off the match hunt immediately.",
                        accent: RetroTheme.cyan
                    )

                    FeatureCard(
                        title: "Pick The Cut",
                        copy: mode == .movie
                            ? "Browse likely film pages and lock the one that best matches the movie in hand."
                            : "Browse series or episode cards and lock the one that best matches the file in hand.",
                        accent: RetroTheme.magenta
                    )

                    FeatureCard(
                        title: "Write It Back",
                        copy: mode == .movie
                            ? "Save title, synopsis, year, artwork, and more directly into the MP4 container."
                            : "Save series, episode title, season/episode context, artwork, and more directly into the MP4 container.",
                        accent: RetroTheme.gold
                    )
                }
                .frame(maxWidth: 920)

                Spacer(minLength: 26)
            }
            .padding(26)
        }
    }
}

private struct FeatureCard: View {
    let title: String
    let copy: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(RetroTheme.labelFont(14))
                .tracking(2.4)
                .foregroundStyle(accent)

            Text(copy)
                .font(RetroTheme.bodyFont(15))
                .foregroundStyle(RetroTheme.paper.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel(accent: accent)
    }
}

private struct TVBatchWorkspaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                episodeTable
                    .frame(width: 390)

                searchTable
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    searchTable
                    episodeTable
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var episodeTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            tableTitle(
                eyebrow: "Episode List",
                title: "\(model.filteredFiles.count) Shown",
                accent: RetroTheme.magenta
            )

            Picker("Queue Filter", selection: $model.queueFilter) {
                ForEach(FileQueueFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .tint(RetroTheme.cyan)

            HStack(spacing: 0) {
                tableHeader("EP", width: 52, alignment: .center)
                tableHeader("TITLE", alignment: .leading)
                tableHeader("STATUS", width: 86, alignment: .center)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(RetroTheme.paper.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.filteredFiles.enumerated()), id: \.element.id) { index, entry in
                        BatchEpisodeRow(
                            index: index + 1,
                            entry: entry,
                            isSelected: model.selectedFileID == entry.id,
                            isStriped: index.isMultiple(of: 2),
                            select: { model.selectedFileID = entry.id }
                        )
                    }
                }
            }
            .frame(minHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack(spacing: 10) {
                Button("Add Episodes") {
                    model.isFileImporterPresented = true
                }
                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))

                Button(model.saveAllButtonTitle) {
                    Task {
                        await model.saveAllTaggedFiles()
                    }
                }
                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.lime))
                .disabled(!model.canSaveAnyTaggedFiles || model.isBatchBusy)
            }

            Text("Drop more episodes here too. Selecting a show result applies it to every loaded file while preserving each file's episode code.")
                .font(RetroTheme.bodyFont(13))
                .foregroundStyle(RetroTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .retroPanel(accent: RetroTheme.magenta)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in
                let droppedFiles = await providers.loadDroppedFileURLs()
                model.importFiles(from: droppedFiles)
            }

            return !providers.isEmpty
        }
    }

    private var searchTable: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                MetaFetchLogoLockup(
                    markSize: 42,
                    wordmarkSize: 28,
                    subtitle: "tv batch search"
                )

                Spacer()

                SidebarStat(label: "Matched", value: "\(model.batchMatchedCount)", accent: RetroTheme.lime)
                    .frame(width: 116)
                SidebarStat(label: "Review", value: "\(model.batchNeedsReviewCount)", accent: RetroTheme.gold)
                    .frame(width: 116)
                SidebarStat(label: "Saved", value: "\(model.batchSavedCount)", accent: RetroTheme.cyan)
                    .frame(width: 116)
            }

            VStack(alignment: .leading, spacing: 14) {
                tableTitle(
                    eyebrow: "Search",
                    title: "Series Lookup",
                    accent: RetroTheme.gold
                )

                HStack(alignment: .center, spacing: 12) {
                    batchSearchField

                    Button {
                        Task {
                            await model.searchBatchShow()
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                    .disabled(model.batchQueryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBatchSearching)
                }

                HStack(spacing: 0) {
                    ForEach(TVBatchTab.allCases) { tab in
                        batchTab(tab)
                    }
                }
                .padding(4)
                .background(RetroTheme.paper.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                batchStatus

                tabbedBatchContent
            }
            .padding(16)
            .retroPanel(accent: RetroTheme.gold)

            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Circle()
                        .strokeBorder(RetroTheme.paper.opacity(0.32), lineWidth: 2)
                        .frame(width: 14, height: 14)
                    Text("selected")
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(RetroTheme.cyan)
                        .frame(width: 14, height: 14)
                    Text("all")
                }

                Text("Series chooses the show, Seasons checks episode mapping, Data picks per-file metadata, Cover chooses artwork.")
                    .font(RetroTheme.bodyFont(13))
                    .foregroundStyle(RetroTheme.muted)

                Spacer()
            }
            .font(RetroTheme.bodyFont(13))
            .foregroundStyle(RetroTheme.paper)
        }
        .padding(16)
        .retroPanel(accent: RetroTheme.cyan)
    }

    @ViewBuilder
    private var tabbedBatchContent: some View {
        switch model.selectedBatchTab {
        case .series:
            seriesResultsContent
        case .seasons:
            BatchSeasonsPane(model: model)
        case .data:
            BatchDataPane(model: model, entry: model.selectedFile)
        case .cover:
            BatchCoverPane(model: model, entry: model.selectedFile)
        }
    }

    private var seriesResultsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.batchSearchResults.isEmpty && !model.isBatchSearching {
                VStack(alignment: .leading, spacing: 12) {
                    RetroPill(text: "Drop, Search, Apply", accent: RetroTheme.gold)

                    Text("Search for the show title once. Click a result row to apply that show to all loaded episodes, then browse Seasons, Data, and Cover before saving.")
                        .font(RetroTheme.bodyFont(16))
                        .foregroundStyle(RetroTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
                .retroPanel(accent: RetroTheme.paper.opacity(0.18))
            } else {
                HStack(spacing: 0) {
                    tableHeader("COVER", width: 136, alignment: .center)
                    tableHeader("TITLE", alignment: .leading)
                    tableHeader("YEAR", width: 90, alignment: .center)
                    tableHeader("ACTION", width: 128, alignment: .center)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(RetroTheme.paper.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.batchSearchResults.enumerated()), id: \.element.id) { index, result in
                            BatchSearchResultRow(
                                result: result,
                                isSelected: model.selectedBatchResult?.id == result.id,
                                isStriped: index.isMultiple(of: 2),
                                apply: {
                                    Task {
                                        await model.applyBatchResultToAllFiles(result)
                                    }
                                }
                            )
                        }
                    }
                }
                .frame(minHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var batchSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(RetroTheme.gold)

            TextField("Show title", text: $model.batchQueryText)
                .textFieldStyle(.plain)
                .font(RetroTheme.bodyFont(17))
                .foregroundStyle(RetroTheme.paper)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.24))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(RetroTheme.paper.opacity(0.12), lineWidth: 1)
        )
    }

    private var batchStatus: some View {
        Group {
            if model.isBatchSearching {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(RetroTheme.cyan)

                    Text("Searching show matches...")
                        .font(RetroTheme.bodyFont(15))
                        .foregroundStyle(RetroTheme.paper)
                }
            } else if let batchErrorMessage = model.batchErrorMessage {
                Text(batchErrorMessage)
                    .font(RetroTheme.bodyFont(15))
                    .foregroundStyle(RetroTheme.gold)
            } else {
                Text(model.batchStatusMessage)
                    .font(RetroTheme.bodyFont(15))
                    .foregroundStyle(RetroTheme.paper)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel(accent: model.batchErrorMessage == nil ? RetroTheme.paper.opacity(0.18) : RetroTheme.gold)
    }

    private func tableTitle(eyebrow: String, title: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow.uppercased())
                .font(RetroTheme.labelFont(12))
                .tracking(2.4)
                .foregroundStyle(accent)

            Text(title)
                .font(RetroTheme.heroFont(24))
                .foregroundStyle(RetroTheme.paper)
        }
    }

    @ViewBuilder
    private func tableHeader(
        _ text: String,
        width: CGFloat? = nil,
        alignment: Alignment = .leading
    ) -> some View {
        if let width {
            Text(text)
                .font(RetroTheme.labelFont(11))
                .tracking(2.1)
                .foregroundStyle(RetroTheme.paper.opacity(0.72))
                .frame(width: width, alignment: alignment)
        } else {
            Text(text)
                .font(RetroTheme.labelFont(11))
                .tracking(2.1)
                .foregroundStyle(RetroTheme.paper.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func batchTab(_ tab: TVBatchTab) -> some View {
        let isSelected = model.selectedBatchTab == tab

        return Button {
            model.selectBatchTab(tab)
        } label: {
            Text(tab.title)
                .font(RetroTheme.bodyFont(13))
                .foregroundStyle(isSelected ? RetroTheme.ink : RetroTheme.paper.opacity(0.78))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? RetroTheme.paper : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.title) batch tab")
        .accessibilityHint("Shows the \(tab.title.lowercased()) tools for the TV batch.")
    }
}

private struct BatchSeasonsPane: View {
    @ObservedObject var model: AppModel

    private struct SeasonGroup: Hashable {
        let showTitle: String
        let season: Int
        let entries: [MovieFileEntry]

        func hash(into hasher: inout Hasher) {
            hasher.combine(showTitle)
            hasher.combine(season)
        }

        static func == (lhs: SeasonGroup, rhs: SeasonGroup) -> Bool {
            lhs.showTitle == rhs.showTitle && lhs.season == rhs.season
        }
    }

    private var seasonGroups: [SeasonGroup] {
        let grouped = Dictionary(grouping: model.files) { entry in
            let showTitle = (entry.selectedResult?.seriesName ?? entry.parsedCurrentQuery.title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedShow = showTitle.isEmpty ? "Unknown Show" : showTitle
            let season = entry.selectedResult?.seasonNumber ?? entry.parsedCurrentQuery.seasonNumber ?? 0
            return "\(normalizedShow.lowercased())|\(season)"
        }

        return grouped
            .map { _, entries in
                let firstEntry = entries.first
                let showTitle = (firstEntry?.selectedResult?.seriesName ?? firstEntry?.parsedCurrentQuery.title ?? "Unknown Show")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let season = firstEntry?.selectedResult?.seasonNumber ?? firstEntry?.parsedCurrentQuery.seasonNumber ?? 0
                return SeasonGroup(
                    showTitle: showTitle.isEmpty ? "Unknown Show" : showTitle,
                    season: season,
                    entries: entries.sorted { lhs, rhs in
                        (lhs.selectedResult?.episodeNumber ?? lhs.parsedCurrentQuery.episodeNumber ?? 0) <
                            (rhs.selectedResult?.episodeNumber ?? rhs.parsedCurrentQuery.episodeNumber ?? 0)
                    }
                )
            }
            .sorted { left, right in
                if left.showTitle.localizedStandardCompare(right.showTitle) != .orderedSame {
                    return left.showTitle.localizedStandardCompare(right.showTitle) == .orderedAscending
                }

                if left.season == 0 {
                    return false
                }

                if right.season == 0 {
                    return true
                }

                return left.season < right.season
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Browse the loaded episodes by detected season. Pick a row to focus it, or search an individual episode again if its data looks off.")
                .font(RetroTheme.bodyFont(15))
                .foregroundStyle(RetroTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(seasonGroups, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            RetroPill(
                                text: group.season == 0 ? "\(group.showTitle) • Unknown Season" : "\(group.showTitle) • Season \(group.season)",
                                accent: RetroTheme.cyan
                            )

                            ForEach(group.entries) { entry in
                                BatchSeasonEpisodeRow(
                                    model: model,
                                    entry: entry,
                                    isSelected: model.selectedFileID == entry.id
                                )
                            }
                        }
                        .padding(14)
                        .retroPanel(accent: RetroTheme.paper.opacity(0.16))
                    }
                }
            }
            .frame(minHeight: 420)
        }
    }
}

private struct BatchSeasonEpisodeRow: View {
    @ObservedObject var model: AppModel
    @ObservedObject var entry: MovieFileEntry
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                model.selectedFileID = entry.id
                model.selectBatchTab(.data)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.selectedResult?.seasonEpisodeLabel ?? entry.parsedCurrentQuery.episodeCode ?? "No episode code")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? RetroTheme.ink : RetroTheme.cyan)

                    Text(entry.selectedResult?.trackName ?? entry.filename)
                        .font(RetroTheme.labelFont(15))
                        .foregroundStyle(isSelected ? RetroTheme.ink : RetroTheme.paper)
                        .lineLimit(2)

                    Text(entry.sidebarStatus)
                        .font(RetroTheme.bodyFont(12))
                        .foregroundStyle(isSelected ? RetroTheme.ink.opacity(0.72) : RetroTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button("Search") {
                Task {
                    await model.search(file: entry)
                }
            }
            .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
            .disabled(entry.isSearching || entry.isSaving)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? RetroTheme.cyan : RetroTheme.panelRaised.opacity(0.88))
        )
    }
}

private struct BatchDataPane: View {
    @ObservedObject var model: AppModel
    let entry: MovieFileEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let entry {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        RetroPill(text: entry.parsedCurrentQuery.episodeCode ?? "Episode", accent: RetroTheme.gold)

                        Text(entry.filename)
                            .font(RetroTheme.heroFont(24))
                            .foregroundStyle(RetroTheme.paper)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(entry.statusMessage)
                            .font(RetroTheme.bodyFont(14))
                            .foregroundStyle(RetroTheme.muted)
                    }

                    Spacer()

                    Button("Search Episode") {
                        Task {
                            await model.search(file: entry)
                        }
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                    .disabled(entry.isSearching || entry.isSaving)
                }

                if let selectedResult = entry.selectedResult {
                    VStack(alignment: .leading, spacing: 9) {
                        MetadataLine(label: "Selected", value: selectedResult.trackName)
                        MetadataLine(label: "Series", value: selectedResult.seriesName ?? selectedResult.trackName)
                        MetadataLine(label: "Episode Code", value: selectedResult.seasonEpisodeLabel ?? entry.parsedCurrentQuery.episodeCode ?? "Not provided")
                        MetadataLine(label: "Genre", value: selectedResult.primaryGenreName ?? "Not provided")
                        MetadataLine(label: "Year", value: selectedResult.releaseYear ?? "Not provided")
                        MetadataLine(label: selectedResult.creatorLabel, value: selectedResult.creatorValue ?? "Not provided")
                        MetadataLine(label: "Artwork", value: entry.artworkChoiceSummary)
                    }
                    .padding(16)
                    .retroPanel(accent: RetroTheme.paper.opacity(0.16))

                    MetadataEditorCard(entry: entry)

                    DownloadedDetailsPanel(result: selectedResult)
                }

                Text("Choose a different returned match for this episode if needed.")
                    .font(RetroTheme.bodyFont(14))
                    .foregroundStyle(RetroTheme.muted)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(entry.searchResults.enumerated()), id: \.element.id) { index, result in
                            BatchEpisodeMatchChoiceRow(
                                result: result,
                                isSelected: entry.selectedResult?.id == result.id,
                                isStriped: index.isMultiple(of: 2),
                                select: {
                                    entry.selectedResult = result
                                    model.batchStatusMessage = "Selected \(result.trackName) for \(entry.filename)."
                                }
                            )
                        }
                    }
                }
                .frame(minHeight: 260)
            } else {
                Text("Select an episode from the list to inspect its metadata.")
                    .font(RetroTheme.bodyFont(16))
                    .foregroundStyle(RetroTheme.muted)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
                    .retroPanel(accent: RetroTheme.paper.opacity(0.18))
            }
        }
    }
}

private struct BatchEpisodeMatchChoiceRow: View {
    let result: MediaSearchResult
    let isSelected: Bool
    let isStriped: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 14) {
                ArtworkView(
                    url: result.artworkURL,
                    width: 64,
                    height: 92,
                    accent: isSelected ? RetroTheme.lime : RetroTheme.paper.opacity(0.22)
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(result.trackName)
                        .font(RetroTheme.heroFont(20))
                        .foregroundStyle(isSelected ? RetroTheme.ink : RetroTheme.paper)
                        .lineLimit(2)

                    Text(result.subtitleLine.isEmpty ? result.matchSummary : result.subtitleLine.uppercased())
                        .font(RetroTheme.labelFont(11))
                        .tracking(1.6)
                        .foregroundStyle(isSelected ? RetroTheme.ink.opacity(0.72) : RetroTheme.gold)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        MatchConfidenceBadge(confidence: result.matchConfidence)
                        InfoBadge(text: result.sourceName, accent: RetroTheme.paper.opacity(0.18), foreground: isSelected ? RetroTheme.ink : RetroTheme.paper)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(isSelected ? "Selected" : "Use")
                    .font(RetroTheme.labelFont(11))
                    .tracking(1.7)
                    .foregroundStyle(RetroTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? RetroTheme.lime : RetroTheme.gold)
                    )
            }
            .padding(12)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(result.trackName), \(result.matchSummary)")
        .accessibilityHint(isSelected ? "This episode match is selected." : "Selects this episode match for the current file.")
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(RetroTheme.cyan)
        }

        return AnyShapeStyle((isStriped ? RetroTheme.panelRaised : RetroTheme.panel).opacity(0.9))
    }
}

private struct BatchCoverPane: View {
    @ObservedObject var model: AppModel
    let entry: MovieFileEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose whether the batch writes each episode's own artwork or uses the selected series cover across all tagged episodes.")
                .font(RetroTheme.bodyFont(15))
                .foregroundStyle(RetroTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    coverChoiceCards
                }

                VStack(alignment: .leading, spacing: 16) {
                    coverChoiceCards
                }
            }

            if let entry {
                VStack(alignment: .leading, spacing: 12) {
                    RetroPill(text: "Selected Episode Cover", accent: RetroTheme.cyan)

                    HStack(alignment: .top, spacing: 16) {
                        ArtworkView(url: entry.selectedArtworkURL, width: 150, height: 220, accent: RetroTheme.lime)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(entry.selectedResult?.trackName ?? entry.filename)
                                .font(RetroTheme.heroFont(24))
                                .foregroundStyle(RetroTheme.paper)

                            Text(entry.artworkChoiceSummary)
                                .font(RetroTheme.bodyFont(14))
                                .foregroundStyle(RetroTheme.muted)

                            HStack(spacing: 10) {
                                Button("Use Episode Art") {
                                    model.useEpisodeArtwork(for: entry)
                                }
                                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))

                                Button("Use Series Cover") {
                                    model.useSeriesArtwork(for: entry)
                                }
                                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.lime))
                                .disabled(model.selectedBatchResult?.artworkURL == nil)
                            }
                        }
                    }
                }
                .padding(16)
                .retroPanel(accent: RetroTheme.paper.opacity(0.16))
            }
        }
        .frame(minHeight: 420, alignment: .topLeading)
    }

    private var coverChoiceCards: some View {
        Group {
            CoverChoiceCard(
                title: "Episode Covers",
                subtitle: "Use the poster TVMaze returned for each episode.",
                artworkURL: entry?.selectedResult?.artworkURL,
                actionTitle: "Use Episode Covers",
                accent: RetroTheme.gold,
                isDisabled: false,
                action: {
                    model.useEpisodeArtworkForBatch()
                }
            )

            CoverChoiceCard(
                title: "Series Cover",
                subtitle: "Use the selected series poster for every tagged episode.",
                artworkURL: model.selectedBatchResult?.artworkURL,
                actionTitle: "Use Series Cover",
                accent: RetroTheme.lime,
                isDisabled: model.selectedBatchResult?.artworkURL == nil,
                action: {
                    model.useSeriesArtworkForBatch()
                }
            )
        }
    }
}

private struct CoverChoiceCard: View {
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let actionTitle: String
    let accent: Color
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ArtworkView(url: artworkURL, width: 150, height: 220, accent: accent)

            Text(title)
                .font(RetroTheme.heroFont(22))
                .foregroundStyle(RetroTheme.paper)

            Text(subtitle)
                .font(RetroTheme.bodyFont(14))
                .foregroundStyle(RetroTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button(actionTitle, action: action)
                .buttonStyle(RetroPrimaryButtonStyle(accent: accent))
                .disabled(isDisabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel(accent: accent)
    }
}

private struct BatchEpisodeRow: View {
    let index: Int
    @ObservedObject var entry: MovieFileEntry
    let isSelected: Bool
    let isStriped: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 0) {
                Text("\(index)")
                    .font(RetroTheme.heroFont(18))
                    .foregroundStyle(isSelected ? RetroTheme.ink : RetroTheme.paper)
                    .frame(width: 52, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.selectedResult?.trackName ?? "No Title")
                        .font(RetroTheme.labelFont(16))
                        .foregroundStyle(isSelected ? RetroTheme.ink : RetroTheme.paper)
                        .lineLimit(2)

                    Text(entry.filename)
                        .font(RetroTheme.bodyFont(12))
                        .foregroundStyle(isSelected ? RetroTheme.ink.opacity(0.78) : RetroTheme.muted)
                        .lineLimit(1)

                    Text(entry.parsedCurrentQuery.episodeCode ?? "No episode code")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? RetroTheme.ink.opacity(0.72) : RetroTheme.cyan)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 5) {
                    Circle()
                        .fill(statusAccent)
                        .frame(width: 13, height: 13)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? RetroTheme.ink.opacity(0.22) : RetroTheme.paper.opacity(0.18), lineWidth: 1)
                        )

                    Text(statusShortLabel)
                        .font(RetroTheme.labelFont(9))
                        .tracking(1.2)
                        .foregroundStyle(isSelected ? RetroTheme.ink.opacity(0.78) : statusAccent)
                }
                .frame(width: 86, alignment: .center)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.filename), \(entry.batchReviewLabel)")
        .accessibilityHint("Selects this episode in the batch workspace.")
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(RetroTheme.cyan)
        }
        return AnyShapeStyle((isStriped ? RetroTheme.panelRaised : RetroTheme.panel).opacity(0.88))
    }

    private var statusAccent: Color {
        if entry.lastSavedAt != nil {
            return RetroTheme.lime
        }

        if entry.isSearching || entry.isSaving {
            return RetroTheme.gold
        }

        if entry.selectedResult?.matchConfidence == .exact {
            return RetroTheme.lime
        }

        if entry.selectedResult != nil || !entry.searchResults.isEmpty {
            return RetroTheme.gold
        }

        return RetroTheme.paper.opacity(0.24)
    }

    private var statusShortLabel: String {
        switch entry.batchReviewLabel {
        case "Needs Match":
            return "EMPTY"
        case "Needs Review":
            return "CHECK"
        case "Series Only":
            return "SERIES"
        default:
            return entry.batchReviewLabel.uppercased()
        }
    }
}

private struct BatchSearchResultRow: View {
    let result: MediaSearchResult
    let isSelected: Bool
    let isStriped: Bool
    let apply: () -> Void

    var body: some View {
        Button(action: apply) {
            HStack(spacing: 0) {
                ArtworkView(
                    url: result.artworkURL,
                    width: 96,
                    height: 132,
                    accent: isSelected ? RetroTheme.lime : RetroTheme.paper.opacity(0.20)
                )
                .padding(.vertical, 12)
                .frame(width: 136, alignment: .center)

                VStack(alignment: .leading, spacing: 8) {
                    Text(result.trackName)
                        .font(RetroTheme.heroFont(24))
                        .foregroundStyle(isSelected ? RetroTheme.ink : RetroTheme.paper)
                        .lineLimit(2)

                    if !result.subtitleLine.isEmpty {
                        Text(result.subtitleLine.uppercased())
                            .font(RetroTheme.labelFont(11))
                            .tracking(1.8)
                            .foregroundStyle(isSelected ? RetroTheme.ink.opacity(0.72) : RetroTheme.gold)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        MatchConfidenceBadge(confidence: result.matchConfidence)
                        InfoBadge(text: result.sourceName, accent: RetroTheme.paper.opacity(0.18), foreground: isSelected ? RetroTheme.ink : RetroTheme.paper)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(result.releaseYear ?? "-")
                    .font(RetroTheme.heroFont(20))
                    .foregroundStyle(isSelected ? RetroTheme.ink : RetroTheme.paper)
                    .frame(width: 90, alignment: .center)

                Text(isSelected ? "Applied" : "Apply All")
                    .font(RetroTheme.labelFont(11))
                    .tracking(1.7)
                    .foregroundStyle(RetroTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? RetroTheme.lime : RetroTheme.gold)
                    )
                    .frame(width: 128, alignment: .center)
            }
            .padding(.horizontal, 10)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(result.trackName), \(result.releaseYear ?? "unknown year"), \(result.matchSummary)")
        .accessibilityHint("Applies this series match to every loaded episode.")
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [RetroTheme.lime.opacity(0.95), RetroTheme.cyan.opacity(0.78)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }

        return AnyShapeStyle((isStriped ? RetroTheme.panelRaised : RetroTheme.panel).opacity(0.9))
    }
}

private struct FileWorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var entry: MovieFileEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        fileHeaderText
                            .frame(maxWidth: .infinity, alignment: .leading)

                        StatusBadge(entry: entry)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        fileHeaderText
                        StatusBadge(entry: entry)
                    }
                }
                .padding(22)
                .retroPanel(accent: RetroTheme.cyan)

                DropZoneCard(
                    mode: entry.mediaMode,
                    compact: true,
                    openPanel: { model.isFileImporterPresented = true },
                    receiveFiles: { model.importFiles(from: $0) }
                )

                VStack(alignment: .leading, spacing: 16) {
                    RetroSectionTitle(
                        eyebrow: "Title Search",
                        title: "Tune The Query",
                        accent: RetroTheme.magenta
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 14) {
                            searchField
                            searchButton
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            searchField
                            searchButton
                        }
                    }

                    Text(entry.mediaMode.searchHelperCopy)
                        .font(RetroTheme.bodyFont(15))
                        .foregroundStyle(RetroTheme.muted)

                    if let episodeDetectionSummary = entry.episodeDetectionSummary {
                        HStack(spacing: 10) {
                            Image(systemName: episodeDetectionSummary.hasPrefix("Detected") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(episodeDetectionSummary.hasPrefix("Detected") ? RetroTheme.lime : RetroTheme.gold)

                            Text(episodeDetectionSummary)
                                .font(RetroTheme.bodyFont(14))
                                .foregroundStyle(RetroTheme.paper)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .retroPanel(accent: episodeDetectionSummary.hasPrefix("Detected") ? RetroTheme.lime : RetroTheme.gold)
                    }

                    SearchStatusView(entry: entry)
                }
                .padding(22)
                .retroPanel(accent: RetroTheme.paper.opacity(0.18))

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 22) {
                        resultRack
                            .frame(minWidth: 380, maxWidth: .infinity, alignment: .leading)

                        previewPanel
                            .frame(width: 340)
                    }

                    VStack(alignment: .leading, spacing: 22) {
                        previewPanel
                            .frame(maxWidth: .infinity)

                        resultRack
                    }
                }
            }
            .padding(24)
        }
    }

    private var fileHeaderText: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetaFetchLogoLockup(
                markSize: 38,
                wordmarkSize: 24,
                subtitle: nil
            )

            RetroPill(text: entry.mediaMode.displayName, accent: RetroTheme.cyan)

            Text(entry.filename)
                .font(RetroTheme.heroFont(34))
                .foregroundStyle(RetroTheme.paper)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.fileURL.path)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(RetroTheme.muted)
                .textSelection(.enabled)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RetroTheme.gold)

            TextField(entry.mediaMode.searchPlaceholder, text: $entry.queryText)
                .textFieldStyle(.plain)
                .font(RetroTheme.bodyFont(17))
                .foregroundStyle(RetroTheme.paper)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(RetroTheme.paper.opacity(0.12), lineWidth: 1)
        )
    }

    private var searchButton: some View {
        Button("Search Again") {
            Task {
                await model.search(file: entry)
            }
        }
        .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.magenta))
        .disabled(entry.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entry.isSearching)
    }

    private var resultRack: some View {
        VStack(alignment: .leading, spacing: 14) {
            RetroSectionTitle(
                eyebrow: "Result Rack",
                title: "Best Matches",
                accent: RetroTheme.gold
            )

            if entry.searchResults.isEmpty && !entry.isSearching {
                VStack(alignment: .leading, spacing: 12) {
                    RetroPill(text: "No Cards Yet", accent: RetroTheme.gold)

                    Text(entry.mediaMode.emptyRackCopy)
                        .font(RetroTheme.bodyFont(15))
                        .foregroundStyle(RetroTheme.muted)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                .retroPanel(accent: RetroTheme.paper.opacity(0.18))
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(entry.searchResults) { result in
                        SearchResultCard(
                            result: result,
                            isSelected: entry.selectedResult?.id == result.id,
                            select: { entry.selectedResult = result }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewPanel: some View {
        SelectionPreviewCard(
            entry: entry,
            safetyBackupsEnabled: model.createSafetyBackups,
            inspectHeadroomAction: {
                Task {
                    await model.inspectHeadroom(for: entry)
                }
            },
            saveAction: {
                Task {
                    await model.save(file: entry)
                }
            }
        )
    }
}

private struct StatusBadge: View {
    @ObservedObject var entry: MovieFileEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Deck Status".uppercased())
                .font(RetroTheme.labelFont(11))
                .tracking(2.3)
                .foregroundStyle(accent)

            Text(message)
                .font(RetroTheme.heroFont(19))
                .foregroundStyle(RetroTheme.paper)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .retroPanel(accent: accent)
    }

    private var message: String {
        if entry.isSaving {
            return "Recording"
        }

        if entry.lastSavedAt != nil {
            return "Stamped"
        }

        if entry.isSearching {
            return "Scanning"
        }

        if entry.selectedResult != nil {
            return "Matched"
        }

        return "Waiting"
    }

    private var accent: Color {
        if entry.lastSavedAt != nil {
            return RetroTheme.lime
        }

        if entry.isSaving {
            return RetroTheme.gold
        }

        if entry.selectedResult != nil {
            return RetroTheme.cyan
        }

        return RetroTheme.magenta
    }
}

private struct SearchStatusView: View {
    @ObservedObject var entry: MovieFileEntry

    var body: some View {
        if entry.isSearching {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(RetroTheme.cyan)

                Text(entry.mediaMode.searchingMatchesLabel)
                    .font(RetroTheme.bodyFont(15))
                    .foregroundStyle(RetroTheme.paper)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .retroPanel(accent: RetroTheme.cyan)
        } else if let errorMessage = entry.errorMessage {
            Text(errorMessage)
                .font(RetroTheme.bodyFont(15))
                .foregroundStyle(RetroTheme.gold)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .retroPanel(accent: RetroTheme.gold)
        } else {
            Text(entry.statusMessage)
                .font(RetroTheme.bodyFont(15))
                .foregroundStyle(RetroTheme.paper)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .retroPanel(accent: RetroTheme.paper.opacity(0.18))
        }
    }
}

private struct DropZoneCard: View {
    let mode: MediaLibraryMode
    var compact: Bool
    let openPanel: () -> Void
    let receiveFiles: ([URL]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            RetroPill(text: compact ? "Drop More Files" : mode.dragTitle, accent: RetroTheme.gold)

            Text(compact ? "Load another tape into the deck." : mode.dragBody)
                .font(compact ? RetroTheme.heroFont(22) : RetroTheme.heroFont(30))
                .foregroundStyle(RetroTheme.paper)

            Text(compact ? "Finder drops work here too." : "Finder drops work here, and the filename gets cleaned up into a likely search title before the first match pass.")
                .font(RetroTheme.bodyFont(compact ? 14 : 17))
                .foregroundStyle(RetroTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button("Choose Files", action: openPanel)
                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
        }
        .padding(compact ? 20 : 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel(accent: RetroTheme.gold)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [RetroTheme.paper.opacity(0.22), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 1.5, dash: [10, 8])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in
                let droppedFiles = await providers.loadDroppedFileURLs()
                receiveFiles(droppedFiles)
            }

            return !providers.isEmpty
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(compact ? "Drop more MP4 files" : mode.dragTitle)
        .accessibilityHint("Drop local MP4 files here or use Choose Files.")
    }
}

private struct SearchResultCard: View {
    let result: MediaSearchResult
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: select) {
                cardContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(result.trackName), \(result.mediaKind.label), \(result.matchSummary)")
            .accessibilityHint(isSelected ? "This match is selected." : "Selects this metadata match.")

            if let sourceURL = result.sourceURL {
                Link(destination: sourceURL) {
                    Label("Open Source", systemImage: "safari")
                        .font(RetroTheme.labelFont(11))
                        .tracking(1.8)
                        .foregroundStyle(RetroTheme.cyan)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open source details for \(result.trackName)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel(accent: isSelected ? RetroTheme.lime : RetroTheme.paper.opacity(0.14))
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 16) {
            ArtworkView(url: result.artworkURL, width: 82, height: 122, accent: isSelected ? RetroTheme.lime : RetroTheme.paper.opacity(0.24))

            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        titleBlock

                        Spacer(minLength: 12)

                        if isSelected {
                            RetroPill(text: "Selected", accent: RetroTheme.lime)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        titleBlock

                        if isSelected {
                            RetroPill(text: "Selected", accent: RetroTheme.lime)
                        }
                    }
                }

                HStack(spacing: 8) {
                    InfoBadge(
                        text: result.mediaKind.label,
                        accent: RetroTheme.cyan,
                        foreground: RetroTheme.ink
                    )
                    MatchConfidenceBadge(confidence: result.matchConfidence)
                    InfoBadge(text: result.sourceName, accent: RetroTheme.paper.opacity(0.18), foreground: RetroTheme.paper)
                }

                Text(result.matchSummary)
                    .font(RetroTheme.labelFont(12))
                    .tracking(1.1)
                    .foregroundStyle(result.matchConfidence.accent)

                Text(result.synopsisPreview)
                    .font(RetroTheme.bodyFont(15))
                    .foregroundStyle(RetroTheme.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.trackName)
                .font(RetroTheme.heroFont(22))
                .foregroundStyle(RetroTheme.paper)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !result.subtitleLine.isEmpty {
                Text(result.subtitleLine.uppercased())
                    .font(RetroTheme.labelFont(12))
                    .tracking(2)
                    .foregroundStyle(RetroTheme.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct MetadataEditorCard: View {
    @ObservedObject var entry: MovieFileEntry
    @State private var isArtworkImporterPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                RetroPill(text: "Manual Edit", accent: RetroTheme.magenta)

                Spacer()

                if let selectedResult = entry.selectedResult {
                    Button("Reset") {
                        entry.metadataDraft.reset(to: selectedResult)
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.paper.opacity(0.18)))
                    .disabled(entry.isSaving)
                    .help("Restores the metadata fields from the selected source result.")
                }
            }

            Text("Adjust the tags that will be written before saving. Edits apply only to this file.")
                .font(RetroTheme.bodyFont(13))
                .foregroundStyle(RetroTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                editorField("Title", text: $entry.metadataDraft.title, required: true)

                if entry.mediaMode == .tvShow {
                    editorField("Series", text: $entry.metadataDraft.seriesName)

                    HStack(spacing: 10) {
                        editorField("Season", text: $entry.metadataDraft.seasonNumber)
                        editorField("Episode", text: $entry.metadataDraft.episodeNumber)
                    }
                }

                HStack(spacing: 10) {
                    editorField(entry.selectedResult?.creatorLabel ?? "Creator", text: $entry.metadataDraft.creator)
                    editorField("Genre", text: $entry.metadataDraft.genre)
                }

                editorField("Release Date", text: $entry.metadataDraft.year)

                editorField("Sort Title", text: $entry.metadataDraft.sortTitle)

                if entry.mediaMode == .tvShow {
                    editorField("Sort Series", text: $entry.metadataDraft.sortSeriesName)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description".uppercased())
                        .font(RetroTheme.labelFont(10))
                        .tracking(1.8)
                        .foregroundStyle(RetroTheme.paper.opacity(0.68))

                    TextEditor(text: $entry.metadataDraft.synopsis)
                        .font(RetroTheme.bodyFont(13))
                        .foregroundStyle(RetroTheme.paper)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 92)
                        .padding(8)
                        .background(Color.black.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(RetroTheme.paper.opacity(0.12), lineWidth: 1)
                        )
                        .disabled(entry.isSaving)
                        .accessibilityLabel("Description")
                }
            }

            if !entry.metadataDraft.isValid(for: entry.selectedResult) {
                Text("A title is required. Release date may be blank, `YYYY`, `YYYY-MM-DD`, or a full ISO date.")
                    .font(RetroTheme.bodyFont(12))
                    .foregroundStyle(RetroTheme.gold)
            }

            Divider()
                .overlay(RetroTheme.paper.opacity(0.14))

            VStack(alignment: .leading, spacing: 10) {
                Text("Poster Override".uppercased())
                    .font(RetroTheme.labelFont(10))
                    .tracking(1.8)
                    .foregroundStyle(RetroTheme.paper.opacity(0.68))

                Text(entry.customArtworkURL?.lastPathComponent ?? "Using source artwork unless you choose a custom image.")
                    .font(RetroTheme.bodyFont(12))
                    .foregroundStyle(RetroTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Choose Poster") {
                        isArtworkImporterPresented = true
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                    .disabled(entry.isSaving)

                    if entry.customArtworkURL != nil {
                        Button("Clear Poster") {
                            entry.customArtworkURL = nil
                        }
                        .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.paper.opacity(0.18)))
                        .disabled(entry.isSaving)
                    }
                }
            }
        }
        .padding(14)
        .retroPanel(accent: RetroTheme.magenta)
        .fileImporter(
            isPresented: $isArtworkImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                entry.customArtworkURL = urls.first?.standardizedFileURL
                entry.headroomInspection = nil
            case .failure(let error):
                entry.errorMessage = error.localizedDescription
            }
        }
    }

    private func editorField(
        _ label: String,
        text: Binding<String>,
        required: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((required ? "\(label) *" : label).uppercased())
                .font(RetroTheme.labelFont(10))
                .tracking(1.8)
                .foregroundStyle(RetroTheme.paper.opacity(0.68))

            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(RetroTheme.bodyFont(13))
                .foregroundStyle(RetroTheme.paper)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(RetroTheme.paper.opacity(0.12), lineWidth: 1)
                )
                .disabled(entry.isSaving)
                .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetadataDiffCard: View {
    @ObservedObject var entry: MovieFileEntry

    var body: some View {
        if let selectedResult = entry.selectedResult {
            let currentSnapshot = entry.currentMetadataSnapshot?.hasReadableValues == true
                ? entry.currentMetadataSnapshot
                : nil
            let rows = diffRows(for: selectedResult, currentSnapshot: currentSnapshot)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RetroPill(text: "Tag Preview Diff", accent: RetroTheme.cyan)
                    if currentSnapshot != nil {
                        InfoBadge(text: "Current MP4", accent: RetroTheme.gold, foreground: RetroTheme.ink)
                    } else if entry.currentMetadataError != nil {
                        InfoBadge(text: "Provider Baseline", accent: RetroTheme.paper.opacity(0.2), foreground: RetroTheme.paper)
                    }
                }

                Text(currentSnapshot != nil
                    ? "Current MP4 value on top, final value to save underneath. This catches accidental overwrites before writing."
                    : "Provider value on top, final value to save underneath. Current MP4 tags were not readable from this file.")
                    .font(RetroTheme.bodyFont(12))
                    .foregroundStyle(RetroTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(rows, id: \.label) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Text(row.label.uppercased())
                                .font(RetroTheme.labelFont(10))
                                .tracking(1.7)
                                .foregroundStyle(RetroTheme.cyan)
                                .frame(width: 88, alignment: .leading)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.before)
                                    .font(RetroTheme.bodyFont(12))
                                    .foregroundStyle(RetroTheme.muted)
                                    .lineLimit(2)

                                Text(row.after)
                                    .font(RetroTheme.bodyFont(13))
                                    .foregroundStyle(row.changed ? RetroTheme.gold : RetroTheme.paper)
                                    .lineLimit(2)
                            }

                            Spacer()

                            if row.changed {
                                InfoBadge(text: "Changed", accent: RetroTheme.gold, foreground: RetroTheme.ink)
                            }
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(14)
            .retroPanel(accent: RetroTheme.cyan)
        }
    }

    private func diffRows(
        for result: MediaSearchResult,
        currentSnapshot: MP4CurrentMetadataSnapshot?
    ) -> [DiffRow] {
        let draft = entry.metadataDraft
        return [
            DiffRow(label: "Title", before: baseline(currentSnapshot?.title, fallback: result.trackName), after: draft.title),
            DiffRow(label: "Sort", before: baseline(currentSnapshot?.sortTitle, fallback: result.sortTitle ?? result.trackName), after: draft.sortTitle),
            DiffRow(label: "Series", before: baseline(currentSnapshot?.seriesName, fallback: result.seriesName), after: displayValue(draft.seriesName)),
            DiffRow(label: "Sort Show", before: baseline(currentSnapshot?.sortSeriesName, fallback: result.sortSeriesName ?? result.seriesName), after: displayValue(draft.sortSeriesName)),
            DiffRow(label: "Episode", before: baselineEpisode(currentSnapshot, fallback: result.seasonEpisodeLabel), after: draftEpisodeCode),
            DiffRow(label: "Genre", before: baseline(currentSnapshot?.genre, fallback: result.primaryGenreName), after: displayValue(draft.genre)),
            DiffRow(label: "Release", before: baseline(currentSnapshot?.year, fallback: result.releaseDate ?? result.releaseYear), after: displayValue(draft.year)),
            DiffRow(label: result.creatorLabel, before: baseline(currentSnapshot?.creator, fallback: result.creatorValue), after: displayValue(draft.creator)),
        ]
    }

    private func baseline(_ currentValue: String?, fallback: String?) -> String {
        displayValue(currentValue ?? fallback ?? "")
    }

    private func baselineEpisode(_ currentSnapshot: MP4CurrentMetadataSnapshot?, fallback: String?) -> String {
        if let season = Int(currentSnapshot?.seasonNumber ?? ""),
           let episode = Int(currentSnapshot?.episodeNumber ?? "") {
            return String(format: "S%02dE%02d", season, episode)
        }

        return displayValue(fallback ?? "")
    }

    private func displayValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not provided" : trimmed
    }

    private var draftEpisodeCode: String {
        guard let season = Int(entry.metadataDraft.seasonNumber),
              let episode = Int(entry.metadataDraft.episodeNumber) else {
            return "Not provided"
        }

        return String(format: "S%02dE%02d", season, episode)
    }

    private struct DiffRow {
        let label: String
        let before: String
        let after: String

        var changed: Bool {
            normalized(before) != normalized(after)
        }

        private func normalized(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .lowercased()
        }
    }
}

private struct HeadroomInspectionCard: View {
    @ObservedObject var entry: MovieFileEntry
    let safetyBackupsEnabled: Bool
    let inspectAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center) {
                RetroPill(text: "Save Path", accent: accent)
                Spacer()
                if entry.willSaveArtwork {
                    Button(entry.isInspectingHeadroom ? "Checking..." : "Check Poster Headroom") {
                        inspectAction()
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                    .disabled(entry.isSaving || entry.isInspectingHeadroom)
                }
            }

            if let outcome = entry.lastSaveOutcome {
                MetadataLine(label: "Last Save", value: outcome.path.label)
            }

            MetadataLine(label: "Safety Backups", value: safetyBackupsEnabled ? "On" : "Off")

            if entry.isInspectingHeadroom {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(RetroTheme.gold)

                    Text("Inspecting MP4 metadata headroom...")
                        .font(RetroTheme.bodyFont(13))
                        .foregroundStyle(RetroTheme.paper)
                }
            } else if let inspection = entry.headroomInspection {
                Text(inspection.headline)
                    .font(RetroTheme.labelFont(13))
                    .foregroundStyle(accent)

                Text(inspection.detail)
                    .font(RetroTheme.bodyFont(12))
                    .foregroundStyle(RetroTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let reservedBytes = inspection.reservedBytes,
                   let requiredBytes = inspection.requiredBytes {
                    MetadataLine(
                        label: "Reserved / Needed",
                        value: "\(Self.byteCount(reservedBytes)) / \(Self.byteCount(requiredBytes))"
                    )
                }
            } else {
                Text(entry.headroomSummary)
                    .font(RetroTheme.bodyFont(12))
                    .foregroundStyle(RetroTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .retroPanel(accent: accent)
    }

    private var accent: Color {
        guard let status = entry.headroomInspection?.status else {
            return entry.willSaveArtwork ? RetroTheme.gold : RetroTheme.lime
        }

        switch status {
        case .enough:
            return RetroTheme.lime
        case .needsRewrite:
            return RetroTheme.gold
        case .unavailable:
            return RetroTheme.magenta
        }
    }

    private static func byteCount(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}

private struct SelectionPreviewCard: View {
    @ObservedObject var entry: MovieFileEntry
    let safetyBackupsEnabled: Bool
    let inspectHeadroomAction: () -> Void
    let saveAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RetroSectionTitle(
                eyebrow: "Preview Deck",
                title: "Selected Match",
                accent: RetroTheme.lime
            )

            if let match = entry.selectedResult {
                ArtworkView(url: entry.selectedArtworkURL, width: 300, height: 440, accent: RetroTheme.lime)

                VStack(alignment: .leading, spacing: 8) {
                    Text(match.trackName)
                        .font(RetroTheme.heroFont(26))
                        .foregroundStyle(RetroTheme.paper)

                    if !match.subtitleLine.isEmpty {
                        Text(match.subtitleLine.uppercased())
                            .font(RetroTheme.labelFont(12))
                            .tracking(2.2)
                            .foregroundStyle(RetroTheme.gold)
                    }

                    DownloadedDetailsPanel(result: match, lineLimit: 14)
                }

                HStack(spacing: 8) {
                    InfoBadge(
                        text: match.mediaKind.label,
                        accent: RetroTheme.cyan,
                        foreground: RetroTheme.ink
                    )
                    MatchConfidenceBadge(confidence: match.matchConfidence)
                    InfoBadge(text: match.sourceName, accent: RetroTheme.paper.opacity(0.18), foreground: RetroTheme.paper)
                }

                Text(match.matchSummary)
                    .font(RetroTheme.bodyFont(14))
                    .foregroundStyle(match.matchConfidence.accent)

                if !entry.providerDiagnostics.isEmpty {
                    Text(entry.providerDiagnostics)
                        .font(RetroTheme.bodyFont(12))
                        .foregroundStyle(RetroTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .retroPanel(accent: RetroTheme.paper.opacity(0.16))
                }

                if let sourceURL = match.sourceURL {
                    Link(destination: sourceURL) {
                        Label("Open Source Details", systemImage: "safari")
                            .font(RetroTheme.labelFont(12))
                            .tracking(1.8)
                            .foregroundStyle(RetroTheme.cyan)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .overlay(RetroTheme.paper.opacity(0.16))

                VStack(alignment: .leading, spacing: 9) {
                    MetadataLine(label: "Match", value: match.matchSummary)
                    MetadataLine(label: "Source", value: match.sourceName)
                    MetadataLine(label: match.mediaKind == .tvEpisode ? "Episode" : "Title", value: match.trackName)
                    if let seriesName = match.seriesName {
                        MetadataLine(label: "Series", value: seriesName)
                    }
                    if let seasonEpisodeLabel = match.seasonEpisodeLabel {
                        MetadataLine(label: "Episode Code", value: seasonEpisodeLabel)
                    }
                    MetadataLine(label: "Genre", value: match.primaryGenreName ?? "Not provided")
                    MetadataLine(label: "Year", value: match.releaseYear ?? "Not provided")
                    MetadataLine(label: match.creatorLabel, value: match.creatorValue ?? "Not provided")
                    MetadataLine(label: "Artwork", value: entry.artworkChoiceSummary)
                }

                MetadataEditorCard(entry: entry)

                MetadataDiffCard(entry: entry)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.hasSelectedArtwork ? "Poster Artwork Included" : "No Poster Artwork Available")
                        .font(RetroTheme.labelFont(13))
                        .foregroundStyle(RetroTheme.paper)

                    Text(entry.saveModeSummary)
                        .font(RetroTheme.bodyFont(12))
                        .foregroundStyle(RetroTheme.muted)
                }

                Toggle("Save poster artwork for this file", isOn: $entry.posterSavingEnabled)
                    .font(RetroTheme.bodyFont(13))
                    .foregroundStyle(RetroTheme.paper)
                    .disabled(!entry.hasSelectedArtwork || entry.isSaving)
                    .help(entry.hasSelectedArtwork ? "Controls whether poster artwork is written during this save." : "No poster artwork is available for this file.")

                HeadroomInspectionCard(
                    entry: entry,
                    safetyBackupsEnabled: safetyBackupsEnabled,
                    inspectAction: inspectHeadroomAction
                )

                if entry.isSeriesOnlySelectionForEpisodeQuery {
                    VStack(alignment: .leading, spacing: 10) {
                        RetroPill(text: "Series Only", accent: RetroTheme.gold)

                        Text("This match is for the series, not the requested episode. Saving it will write show-level metadata into this MP4.")
                            .font(RetroTheme.bodyFont(13))
                            .foregroundStyle(RetroTheme.paper)

                        if entry.requiresSeriesOnlySaveConfirmation {
                            Button("Allow Series-Only Save") {
                                entry.allowsSeriesOnlySave = true
                                entry.errorMessage = nil
                                entry.statusMessage = "Series-only save confirmed"
                            }
                            .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                        } else {
                            Text("Series-only save confirmed for this selection.")
                                .font(RetroTheme.labelFont(12))
                                .tracking(1.8)
                                .foregroundStyle(RetroTheme.lime)
                        }
                    }
                    .padding(14)
                    .retroPanel(accent: RetroTheme.gold)
                }

                Button(action: saveAction) {
                    if entry.isSaving {
                        Label("Saving Metadata...", systemImage: "arrow.trianglehead.2.clockwise")
                    } else {
                        Label(entry.saveActionLabel, systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.lime))
                .disabled(!entry.canSave)
                .accessibilityHint("Writes the selected metadata to \(entry.filename).")

                if entry.isSaving {
                    VStack(alignment: .leading, spacing: 10) {
                        if let saveProgress = entry.normalizedSaveProgress {
                            ProgressView(value: saveProgress)
                                .progressViewStyle(.linear)
                                .tint(RetroTheme.lime)
                                .accessibilityLabel("Save progress")
                                .accessibilityValue(entry.saveProgressLabel)

                            HStack {
                                Text(entry.statusMessage)
                                    .font(RetroTheme.bodyFont(13))
                                    .foregroundStyle(RetroTheme.paper)

                                Spacer()

                                Text(entry.saveProgressLabel)
                                    .font(RetroTheme.labelFont(12))
                                    .foregroundStyle(RetroTheme.lime)
                            }
                        } else {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(RetroTheme.lime)

                                Text(entry.statusMessage)
                                    .font(RetroTheme.bodyFont(13))
                                    .foregroundStyle(RetroTheme.paper)
                            }
                        }
                    }
                }

                if let lastSavedAt = entry.lastSavedAt {
                    Text("Stamped at \(lastSavedAt.formatted(date: .omitted, time: .shortened))")
                        .font(RetroTheme.labelFont(12))
                        .tracking(2.1)
                        .foregroundStyle(RetroTheme.lime)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    RetroPill(text: "Review Needed", accent: RetroTheme.magenta)

                    Text(entry.mediaMode.selectionPrompt)
                        .font(RetroTheme.bodyFont(15))
                        .foregroundStyle(RetroTheme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 380, alignment: .topLeading)
            }
        }
        .padding(20)
        .retroPanel(accent: RetroTheme.lime)
    }
}

private struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    let currentMode: MediaLibraryMode?

    var body: some View {
        ZStack {
            RetroBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            MetaFetchLogoLockup(
                                markSize: 44,
                                wordmarkSize: 28,
                                subtitle: "help deck"
                            )

                            Text("MetaFetch Help")
                                .font(RetroTheme.heroFont(38))
                                .foregroundStyle(RetroTheme.paper)

                            Text("Current deck: \(currentMode?.displayName ?? "Choose Movie or TV Show")")
                                .font(RetroTheme.bodyFont(16))
                                .foregroundStyle(RetroTheme.muted)
                        }

                        Spacer()

                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                    }

                    HelpSection(
                        title: "Basic Flow",
                        accent: RetroTheme.cyan,
                        rows: [
                            "Choose Movie or TV Show before importing.",
                            "Drop one or more MP4 files, use Add MP4 Files, or import a season folder.",
                            "Review the suggested search query and search again if needed.",
                            "Pick the best result card, edit fields if needed, then save metadata back to the MP4.",
                        ]
                    )

                    HelpSection(
                        title: "Best Search Results",
                        accent: RetroTheme.lime,
                        rows: [
                            "Movie filenames work best when they include a clean title and year, like The.Matrix.1999.mp4.",
                            "TV filenames work best with season and episode codes, like Severance.S02E04.mp4 or Severance.2x04.mp4.",
                            "If a filename is messy, edit the search box directly and search again.",
                            "Use Options > Metadata Providers to add optional TMDb or OMDb keys for broader movie coverage.",
                            "Use Open Source when two matches look similar and you want to confirm the source page.",
                        ]
                    )

                    HelpSection(
                        title: "TV Episode Tips",
                        accent: RetroTheme.magenta,
                        rows: [
                            "Filenames like Show.Name.S01E03.mp4 and Show.Name.2x07.mp4 are detected automatically.",
                            "If the filename is generic, folder names help. For example: Severance/Season 2/Episode 04.mp4.",
                            "For a few episodes from the same show, drop them together and use the batch workspace to search the show once.",
                            "For larger seasons, use Add Season Folder to recursively queue writable MP4 files.",
                            "Clicking a show card applies that show to every file while preserving each detected episode code.",
                            "A Series Only badge means MetaFetch found the show, but not a specific episode yet.",
                            "Add or edit an episode code like S02E04 in the search field for exact episode tags.",
                        ]
                    )

                    HelpSection(
                        title: "Keyboard Shortcuts",
                        accent: RetroTheme.cyan,
                        rows: [
                            "Command-Shift-? opens this help deck from the macOS Help menu.",
                            "Command-Option-S shows or hides the sidebar.",
                            "Use Add MP4 Files when dragging files from Finder is not convenient.",
                            "Use Start Over to clear the current queue without deleting or changing your MP4 files.",
                        ]
                    )

                    HelpSection(
                        title: "Saving Speed",
                        accent: RetroTheme.gold,
                        rows: [
                            "MetaFetch first writes Apple/iTunes-style MP4 metadata atoms directly into the movie header when possible.",
                            "Use Manual Edit to adjust title, sort title, series, sort series, genre, release date, season, episode, creator, description, and custom poster before saving.",
                            "Use Check Poster Headroom before artwork saves to estimate whether a fast header update is likely.",
                            "Batch saves keep poster artwork on when the selected source provides it.",
                            "Saving with poster artwork may rebuild the MP4 container, but video/audio are not re-encoded.",
                            "The save report shows the actual write path, duration, poster state, failures, and backup files, then exports CSV or JSON or retries failed rows.",
                            "Use Advanced Preferences for poster defaults, safety backups, provider priority, watch folders, and rename-after-save templates.",
                        ]
                    )

                    HelpSection(
                        title: "Metadata Providers",
                        accent: RetroTheme.magenta,
                        rows: [
                            "Wikipedia/Wikimedia powers default movie search and TVMaze powers TV search without any setup.",
                            "TMDb and OMDb are optional movie providers. Add your own keys in Options > Metadata Providers when you want extra movie matches.",
                            "Provider keys are stored locally in Keychain and are not bundled into releases or shared with GitHub.",
                            "Advanced Preferences can boost Wikipedia, TMDb, or OMDb in movie result ranking without hiding other sources.",
                            "If a provider key is blank, MetaFetch simply skips that provider and keeps searching with the remaining sources.",
                        ]
                    )

                    HelpSection(
                        title: "Advanced Workflow",
                        accent: RetroTheme.gold,
                        rows: [
                            "Use queue filters to focus exact matches, needs-review rows, series-only rows, saved files, failures, or files with posters.",
                            "Use Tag Preview Diff to compare current MP4 tags with the final edited tags when existing tags are readable.",
                            "Provider diagnostics show searched, skipped, failed, and no-key provider states after movie searches.",
                            "Enable rename-after-save templates to produce clean filenames after verified saves.",
                            "Use Watch Folder to poll a folder and queue newly added writable MP4 files automatically.",
                        ]
                    )

                    HelpSection(
                        title: "Updates",
                        accent: RetroTheme.cyan,
                        rows: [
                            "Use Updates in the toolbar or Check for Updates from the app menu to look for newer GitHub releases.",
                            "MetaFetch compares the installed app version with the latest GitHub release tag.",
                            "When a release has a DMG, ZIP, or PKG asset, MetaFetch can download it to Downloads and reveal it in Finder.",
                            "Installer replacement still stays visible and user-confirmed, and MetaFetch no longer opens downloaded installers automatically.",
                        ]
                    )

                    HelpSection(
                        title: "Troubleshooting",
                        accent: RetroTheme.magenta,
                        rows: [
                            "No matches usually means the query is too noisy. Try a shorter title or add the release year.",
                            "Series Only in TV mode means MetaFetch found the show but still needs a specific episode code.",
                            "If an exact TV episode code is missing, MetaFetch also tries the trailing episode title and explains when TVMaze lists it under a different show or season.",
                            "For multi-episode tagging, search the show once in the batch workspace, click the right show card, review the badges, then Save All Tagged + Posters.",
                            "If saving is slow, check poster headroom or turn off poster artwork so MetaFetch can try the metadata-only fast path.",
                            "If MetaFetch says a file changed after import, remove that row and add the MP4 again before saving.",
                            "If a folder imports nothing, confirm it contains local writable MP4 files and is not a symlink.",
                            "If the layout feels cramped, hide the sidebar or widen the app window before reviewing poster cards.",
                        ]
                    )

                    HelpSection(
                        title: "Review Badges",
                        accent: RetroTheme.lime,
                        rows: [
                            "Exact means MetaFetch is confident enough to auto-select.",
                            "Review means the result is plausible but deserves a quick look.",
                            "Series Only means a TV show result was found without an exact episode.",
                            "Open Source lets you inspect the Wikipedia or TVMaze page behind a result.",
                        ]
                    )

                    HelpSection(
                        title: "Good Next Upgrades",
                        accent: RetroTheme.gold,
                        rows: [
                            "Add rename preset management for reusable library naming styles.",
                            "Expand current-tag reading to additional niche third-party MP4/iTunes atoms.",
                            "Add a signed Sparkle updater for fully automatic app replacement.",
                        ]
                    )
                }
                .padding(28)
                .frame(maxWidth: 880, alignment: .leading)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 720, minHeight: 640)
    }
}

private struct UpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            RetroBackdrop()

            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        MetaFetchLogoLockup(
                            markSize: 44,
                            wordmarkSize: 28,
                            subtitle: "release radar"
                        )

                        Text("MetaFetch Updates")
                            .font(RetroTheme.heroFont(38))
                            .foregroundStyle(RetroTheme.paper)

                        Text("Installed version \(model.currentAppVersion)")
                            .font(RetroTheme.bodyFont(16))
                            .foregroundStyle(RetroTheme.muted)
                    }

                    Spacer()

                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                }

                updateBody
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .retroPanel(accent: accent)

                HStack {
                    Button("Check Again") {
                        Task {
                            await model.checkForUpdates()
                        }
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.cyan))
                    .disabled(model.updateState.isBusy)

                    Spacer()

                    if case .available(let update) = model.updateState {
                        Button(update.asset == nil ? "Open Release Page" : "Download And Reveal") {
                            if update.asset == nil {
                                model.openReleasePage(for: update)
                            } else {
                                Task {
                                    await model.downloadAvailableUpdate()
                                }
                            }
                        }
                        .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.lime))
                    }

                    if case .downloaded(_, let fileURL) = model.updateState {
                        Button("Reveal Download") {
                            model.revealDownloadedUpdate(at: fileURL)
                        }
                        .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.lime))
                    }
                }
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 680, minHeight: 520)
    }

    @ViewBuilder
    private var updateBody: some View {
        switch model.updateState {
        case .idle:
            updateMessage(
                eyebrow: "Ready",
                title: "Check GitHub Releases",
                message: "MetaFetch can check the latest GitHub release, compare versions, and download the installer asset when one is available."
            )
        case .checking:
            VStack(alignment: .leading, spacing: 16) {
                updateMessage(
                    eyebrow: "Checking",
                    title: "Looking For A Newer Release",
                    message: "MetaFetch is asking GitHub for the latest published release."
                )

                ProgressView()
                    .progressViewStyle(.linear)
            }
        case .upToDate(let version):
            updateMessage(
                eyebrow: "Current",
                title: "No Newer Release Found",
                message: "The latest GitHub release is \(version). Your installed version \(model.currentAppVersion) does not need an update."
            )
        case .available(let update):
            VStack(alignment: .leading, spacing: 14) {
                updateMessage(
                    eyebrow: "Available",
                    title: "Version \(update.version) Is Ready",
                    message: update.asset == nil
                        ? "GitHub has a newer release, but it does not include a .dmg, .zip, or .pkg asset. Open the release page to download it manually."
                        : "MetaFetch can download \(update.asset?.name ?? "the installer") to your Downloads folder and reveal it in Finder."
                )

                releaseNotes(for: update)
            }
        case .downloading(let update):
            VStack(alignment: .leading, spacing: 16) {
                updateMessage(
                    eyebrow: "Downloading",
                    title: "Fetching Version \(update.version)",
                    message: "The update is downloading from GitHub. MetaFetch will reveal it in Finder when the download finishes."
                )

                ProgressView()
                    .progressViewStyle(.linear)
            }
        case .downloaded(let update, let fileURL):
            VStack(alignment: .leading, spacing: 14) {
                updateMessage(
                    eyebrow: "Downloaded",
                    title: "Version \(update.version) Is In Downloads",
                    message: "The installer was downloaded and selected in Finder. Open it only after you trust the release: \(fileURL.path)"
                )

                releaseNotes(for: update)
            }
        case .failed(let message):
            updateMessage(
                eyebrow: "Update Check Failed",
                title: "Couldn’t Finish The Update Flow",
                message: message
            )
        }
    }

    private var accent: Color {
        switch model.updateState {
        case .available, .downloaded:
            return RetroTheme.lime
        case .failed:
            return RetroTheme.magenta
        case .checking, .downloading:
            return RetroTheme.cyan
        case .idle, .upToDate:
            return RetroTheme.gold
        }
    }

    private func updateMessage(eyebrow: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RetroSectionTitle(eyebrow: eyebrow, title: title, accent: accent)

            Text(message)
                .font(RetroTheme.bodyFont(16))
                .foregroundStyle(RetroTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func releaseNotes(for update: AppUpdate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(update.name.uppercased())
                .font(RetroTheme.labelFont(13))
                .tracking(2.2)
                .foregroundStyle(RetroTheme.gold)

            ScrollView {
                Text(update.releaseNotes)
                    .font(RetroTheme.bodyFont(14))
                    .foregroundStyle(RetroTheme.paper)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 150)

            Button("Open Release Page") {
                model.openReleasePage(for: update)
            }
            .buttonStyle(.link)
        }
    }
}

private struct ProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var showsKeys = false

    var body: some View {
        ZStack {
            RetroBackdrop()

            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        MetaFetchLogoLockup(
                            markSize: 44,
                            wordmarkSize: 28,
                            subtitle: "source mixer"
                        )

                        Text("Metadata Providers")
                            .font(RetroTheme.heroFont(38))
                            .foregroundStyle(RetroTheme.paper)

                        Text("Wikipedia and TVMaze always stay enabled. Add optional movie provider keys when you want broader poster and release coverage.")
                            .font(RetroTheme.bodyFont(16))
                            .foregroundStyle(RetroTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                }

                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        providerStatus(
                            title: "TMDb",
                            isEnabled: providerKeyIsSet(model.tmdbAPIKey)
                        )

                        providerStatus(
                            title: "OMDb",
                            isEnabled: providerKeyIsSet(model.omdbAPIKey)
                        )

                        Spacer()

                        Toggle("Show Keys", isOn: $showsKeys)
                            .font(RetroTheme.bodyFont(13))
                            .foregroundStyle(RetroTheme.paper)
                    }

                    providerKeyField(
                        title: "TMDb API Key",
                        description: "Used for optional movie search results and TMDb poster URLs. Leave blank to skip TMDb.",
                        text: $model.tmdbAPIKey
                    )

                    providerKeyField(
                        title: "OMDb API Key",
                        description: "Used for optional IMDb-backed movie details such as director, rating, genre, plot, and poster.",
                        text: $model.omdbAPIKey
                    )
                }
                .padding(20)
                .retroPanel(accent: RetroTheme.cyan)

                HStack {
                    Button("Clear Provider Keys") {
                        model.tmdbAPIKey = ""
                        model.omdbAPIKey = ""
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.paper.opacity(0.18)))
                    .disabled(model.tmdbAPIKey.isEmpty && model.omdbAPIKey.isEmpty)

                    Spacer()

                    Button("Save Settings") {
                        dismiss()
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.lime))
                }
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 700, minHeight: 560)
    }

    private func providerStatus(title: String, isEnabled: Bool) -> some View {
        InfoBadge(
            text: "\(title) \(isEnabled ? "On" : "Off")",
            accent: isEnabled ? RetroTheme.lime : RetroTheme.paper.opacity(0.18),
            foreground: isEnabled ? RetroTheme.ink : RetroTheme.paper
        )
    }

    private func providerKeyIsSet(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func providerKeyField(
        title: String,
        description: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(RetroTheme.labelFont(11))
                .tracking(2.2)
                .foregroundStyle(RetroTheme.cyan)

            Text(description)
                .font(RetroTheme.bodyFont(13))
                .foregroundStyle(RetroTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            keyInput(title: title, text: text)
                .textFieldStyle(.plain)
                .font(RetroTheme.bodyFont(14))
                .foregroundStyle(RetroTheme.paper)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color.black.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(RetroTheme.paper.opacity(0.12), lineWidth: 1)
                )
                .accessibilityLabel(title)
        }
    }

    @ViewBuilder
    private func keyInput(title: String, text: Binding<String>) -> some View {
        if showsKeys {
            TextField(title, text: text)
        } else {
            SecureField(title, text: text)
        }
    }
}

private struct AdvancedPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var isWatchFolderImporterPresented = false
    @State private var historyExportError: String?

    var body: some View {
        ZStack {
            RetroBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            MetaFetchLogoLockup(
                                markSize: 44,
                                wordmarkSize: 28,
                                subtitle: "power deck"
                            )

                            Text("Advanced Preferences")
                                .font(RetroTheme.heroFont(38))
                                .foregroundStyle(RetroTheme.paper)

                            Text("Keep the main workflow simple, but tune speed, artwork, provider priority, batch automation, watch folders, and file naming here.")
                                .font(RetroTheme.bodyFont(16))
                                .foregroundStyle(RetroTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                    }

                    preferenceSection(title: "Save Defaults", accent: RetroTheme.lime) {
                        Toggle("Save poster artwork by default", isOn: $model.posterSavingDefault)
                        Toggle("Create safety backups before writing", isOn: $model.createSafetyBackups)

                        Text("Poster saving can still be changed per file. Safety backups trade speed for a recoverable sidecar copy.")
                            .font(RetroTheme.bodyFont(12))
                            .foregroundStyle(RetroTheme.muted)
                    }

                    preferenceSection(title: "Provider Priority", accent: RetroTheme.cyan) {
                        Picker("Preferred movie provider", selection: $model.preferredProviderSource) {
                            ForEach(MetadataProviderSource.allCases) { source in
                                Text(source.label).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Provider priority gives matching results from your preferred source a scoring boost without hiding other sources.")
                            .font(RetroTheme.bodyFont(12))
                            .foregroundStyle(RetroTheme.muted)

                        Divider()
                            .overlay(RetroTheme.paper.opacity(0.14))

                        Text("Provider Health".uppercased())
                            .font(RetroTheme.labelFont(10))
                            .tracking(1.8)
                            .foregroundStyle(RetroTheme.cyan)

                        if model.providerHealthRecords.isEmpty {
                            Text("No provider health history yet. Search once to record searched, skipped, and failed provider states locally.")
                                .font(RetroTheme.bodyFont(12))
                                .foregroundStyle(RetroTheme.muted)
                        } else {
                            ForEach(model.providerHealthRecords) { record in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.providerName)
                                        .font(RetroTheme.labelFont(12))
                                        .foregroundStyle(record.failedCount > 0 ? RetroTheme.gold : RetroTheme.paper)

                                    Text(record.summary)
                                        .font(RetroTheme.bodyFont(12))
                                        .foregroundStyle(RetroTheme.muted)

                                    if !record.lastDetail.isEmpty {
                                        Text(record.lastDetail)
                                            .font(RetroTheme.bodyFont(11))
                                            .foregroundStyle(RetroTheme.paper.opacity(0.72))
                                            .lineLimit(2)
                                    }
                                }
                                .padding(10)
                                .background(Color.black.opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            Button("Reset Provider Health") {
                                model.resetProviderHealthHistory()
                            }
                            .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.paper.opacity(0.18)))
                        }
                    }

                    preferenceSection(title: "TV Batch Rules", accent: RetroTheme.magenta) {
                        Toggle("Auto-apply a clear exact show match", isOn: $model.autoApplyClearTVBatchMatches)

                        Text("When enabled, a clear exact show result immediately drives all loaded episode searches while preserving each episode code.")
                            .font(RetroTheme.bodyFont(12))
                            .foregroundStyle(RetroTheme.muted)
                    }

                    preferenceSection(title: "Rename After Tagging", accent: RetroTheme.gold) {
                        Toggle("Rename files after successful save", isOn: $model.renameAfterSave)

                        TextField("Movie template", text: $model.movieRenameTemplate)
                            .textFieldStyle(.roundedBorder)
                        TextField("TV template", text: $model.tvRenameTemplate)
                            .textFieldStyle(.roundedBorder)

                        Text("Tokens: {title}, {sort_title}, {series}, {sort_series}, {year}, {season}, {episode}, {season_episode}. Existing files get a safe numeric suffix.")
                            .font(RetroTheme.bodyFont(12))
                            .foregroundStyle(RetroTheme.muted)
                    }

                    preferenceSection(title: "Tagging History", accent: RetroTheme.magenta) {
                        if model.taggingHistoryRecords.isEmpty {
                            Text("No saved-file history yet. Verified saves are kept locally so you can remember what was tagged recently.")
                                .font(RetroTheme.bodyFont(12))
                                .foregroundStyle(RetroTheme.muted)
                        } else {
                            ForEach(model.taggingHistoryRecords.prefix(8)) { record in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title)
                                        .font(RetroTheme.labelFont(12))
                                        .foregroundStyle(RetroTheme.paper)

                                    Text(record.filename)
                                        .font(RetroTheme.bodyFont(12))
                                        .foregroundStyle(RetroTheme.gold)
                                        .lineLimit(1)

                                    Text(record.summary)
                                        .font(RetroTheme.bodyFont(11))
                                        .foregroundStyle(RetroTheme.muted)
                                }
                                .padding(10)
                                .background(Color.black.opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            Button("Clear History") {
                                model.resetTaggingHistory()
                            }
                            .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.paper.opacity(0.18)))

                            Button("Export History CSV") {
                                exportHistoryCSV()
                            }
                            .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.cyan))

                            if let historyExportError {
                                Text(historyExportError)
                                    .font(RetroTheme.bodyFont(12))
                                    .foregroundStyle(RetroTheme.gold)
                            }
                        }
                    }

                    preferenceSection(title: "Watch Folder", accent: RetroTheme.cyan) {
                        Text(model.watchFolderSummary)
                            .font(RetroTheme.bodyFont(13))
                            .foregroundStyle(RetroTheme.paper)

                        HStack(spacing: 10) {
                            Button(model.isWatchingFolder ? "Stop Watching" : "Choose Watch Folder") {
                                if model.isWatchingFolder {
                                    model.stopWatchingFolder()
                                } else {
                                    isWatchFolderImporterPresented = true
                                }
                            }
                            .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.cyan))
                            .disabled(model.selectedMode == nil && !model.isWatchingFolder)

                            if model.isWatchingFolder {
                                Button("Scan Now") {
                                    model.scanWatchedFolder()
                                }
                                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                            }
                        }
                    }
                }
                .padding(28)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 720)
        .fileImporter(
            isPresented: $isWatchFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.startWatchingFolder(url)
                }
            case .failure(let error):
                model.noticeMessage = error.localizedDescription
            }
        }
    }

    private func preferenceSection<Content: View>(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RetroSectionTitle(eyebrow: "Advanced", title: title, accent: accent)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .font(RetroTheme.bodyFont(14))
            .foregroundStyle(RetroTheme.paper)
        }
        .padding(18)
        .retroPanel(accent: accent)
    }

    private func exportHistoryCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MetaFetch Tagging History.csv"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            try TaggingHistoryStore.csvData(from: model.taggingHistoryRecords)
                .write(to: url, options: [.atomic])
            historyExportError = nil
        } catch {
            historyExportError = error.localizedDescription
        }
    }
}

private struct SaveReportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let report: SaveReport
    @State private var exportError: String?

    var body: some View {
        ZStack {
            RetroBackdrop()

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        MetaFetchLogoLockup(
                            markSize: 44,
                            wordmarkSize: 28,
                            subtitle: "save report"
                        )

                        Text("Save Report")
                            .font(RetroTheme.heroFont(38))
                            .foregroundStyle(RetroTheme.paper)

                        Text(report.summary)
                            .font(RetroTheme.bodyFont(16))
                            .foregroundStyle(RetroTheme.muted)
                    }

                    Spacer()

                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                }

                HStack(spacing: 10) {
                    SidebarStat(label: "Verified", value: "\(report.successCount)", accent: RetroTheme.lime)
                    SidebarStat(label: "Failed", value: "\(report.failureCount)", accent: report.failureCount == 0 ? RetroTheme.cyan : RetroTheme.gold)
                    SidebarStat(label: "Files", value: "\(report.entries.count)", accent: RetroTheme.magenta)
                }

                HStack(spacing: 10) {
                    Button("Retry Failed") {
                        Task {
                            await model.retryFailedSaves(from: report)
                        }
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.magenta))
                    .disabled(report.failureCount == 0 || model.isBatchBusy)

                    Button("Retry Without Posters") {
                        Task {
                            await model.retryFailedSaves(from: report, includeArtwork: false)
                        }
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                    .disabled(report.failureCount == 0 || model.isBatchBusy)

                    Button("Export CSV") {
                        export(data: report.csvData(), suggestedName: "MetaFetch Save Report.csv")
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.cyan))

                    Button("Export JSON") {
                        do {
                            try export(data: report.jsonData(), suggestedName: "MetaFetch Save Report.json")
                        } catch {
                            exportError = error.localizedDescription
                        }
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))

                    if let exportError {
                        Text(exportError)
                            .font(RetroTheme.bodyFont(12))
                            .foregroundStyle(RetroTheme.gold)
                    }

                    Spacer()
                }

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(report.entries) { entry in
                            SaveReportRow(entry: entry)
                        }
                    }
                }
                .frame(minHeight: 360)
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 620)
    }

    private func export(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            try data.write(to: url, options: [.atomic])
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct SaveReportRow: View {
    let entry: SaveReportEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: entry.didSucceed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(entry.didSucceed ? RetroTheme.lime : RetroTheme.gold)

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.filename)
                        .font(RetroTheme.heroFont(22))
                        .foregroundStyle(RetroTheme.paper)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(entry.title)
                        .font(RetroTheme.bodyFont(14))
                        .foregroundStyle(RetroTheme.muted)
                }

                Spacer()

                RetroPill(text: entry.statusLabel, accent: entry.didSucceed ? RetroTheme.lime : RetroTheme.gold)
            }

            VStack(alignment: .leading, spacing: 7) {
                MetadataLine(label: "Save Path", value: entry.pathLabel)
                MetadataLine(label: "Duration", value: entry.durationLabel)

                if let outcome = entry.outcome {
                    MetadataLine(label: "Detail", value: outcome.path.detail)
                    MetadataLine(label: "Poster", value: outcome.includedArtwork ? "Included" : "Not included")

                    if let backupURL = outcome.backupURL {
                        MetadataLine(label: "Backup", value: backupURL.lastPathComponent)
                    }
                }

                if let errorMessage = entry.errorMessage {
                    MetadataLine(label: "Error", value: errorMessage)
                }
            }

            HStack(spacing: 10) {
                Button("Reveal File") {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.fileURL])
                }
                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.cyan))

                if let backupURL = entry.outcome?.backupURL {
                    Button("Reveal Backup") {
                        NSWorkspace.shared.activateFileViewerSelecting([backupURL])
                    }
                    .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.gold))
                }
            }
        }
        .padding(16)
        .retroPanel(accent: entry.didSucceed ? RetroTheme.lime : RetroTheme.gold)
    }
}

private struct HelpSection: View {
    let title: String
    let accent: Color
    let rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RetroSectionTitle(
                eyebrow: "Guide",
                title: title,
                accent: accent
            )

            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                            .padding(.top, 7)

                        Text(row)
                            .font(RetroTheme.bodyFont(15))
                            .foregroundStyle(RetroTheme.paper)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .retroPanel(accent: accent)
    }
}

private struct MatchConfidenceBadge: View {
    let confidence: MatchConfidence

    var body: some View {
        InfoBadge(text: confidence.label, accent: confidence.accent, foreground: RetroTheme.ink)
    }
}

private struct InfoBadge: View {
    let text: String
    let accent: Color
    let foreground: Color

    var body: some View {
        Text(text.uppercased())
            .font(RetroTheme.labelFont(10))
            .tracking(1.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(accent)
            )
    }
}

private struct DownloadedDetailsPanel: View {
    let result: MediaSearchResult
    var lineLimit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RetroPill(text: "Downloaded Details", accent: RetroTheme.cyan)

            Text(result.synopsis)
                .font(RetroTheme.bodyFont(15))
                .foregroundStyle(RetroTheme.muted)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                InfoBadge(text: result.sourceName, accent: RetroTheme.paper.opacity(0.18), foreground: RetroTheme.paper)

                if let sourceURL = result.sourceURL {
                    Link(destination: sourceURL) {
                        Label("Open Source", systemImage: "safari")
                            .font(RetroTheme.labelFont(11))
                            .tracking(1.7)
                            .foregroundStyle(RetroTheme.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel(accent: RetroTheme.cyan)
    }
}

private struct MetadataLine: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(RetroTheme.labelFont(11))
                .tracking(2.3)
                .foregroundStyle(RetroTheme.cyan)

            Text(value)
                .font(RetroTheme.bodyFont(15))
                .foregroundStyle(RetroTheme.paper)
        }
    }
}

private struct ArtworkView: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let accent: Color
    @State private var artworkData: Data?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let artworkData,
               let nsImage = NSImage(data: artworkData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
                    .opacity(isLoading ? 0.72 : 1)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.85), lineWidth: 2)
        )
        .shadow(color: accent.opacity(0.20), radius: 14, x: 0, y: 12)
        .accessibilityHidden(true)
        .task(id: url) {
            await loadArtwork()
        }
    }

    @MainActor
    private func loadArtwork() async {
        artworkData = nil
        guard let url else {
            isLoading = false
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            artworkData = try await ArtworkPipeline.shared.preparedArtwork(for: url)
        } catch {
            artworkData = nil
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [RetroTheme.panelRaised, RetroTheme.panel],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: width / 4.4, weight: .bold))
                    .foregroundStyle(accent)

                Text("NO COVER")
                    .font(RetroTheme.labelFont(13))
                    .tracking(2.2)
                    .foregroundStyle(RetroTheme.paper.opacity(0.8))
            }
        }
    }
}

private extension MatchConfidence {
    var accent: Color {
        switch self {
        case .exact:
            return RetroTheme.lime
        case .strong:
            return RetroTheme.gold
        case .possible:
            return RetroTheme.paper.opacity(0.28)
        }
    }
}

@MainActor
private extension Array where Element == NSItemProvider {
    func loadDroppedFileURLs() async -> [URL] {
        var urls: [URL] = []
        for provider in self {
            if let url = await provider.loadDroppedFileURL() {
                urls.append(url)
            }
        }

        return urls
    }
}

@MainActor
private extension NSItemProvider {
    func loadDroppedFileURL() async -> URL? {
        await withCheckedContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? NSData,
                   let url = URL(dataRepresentation: data as Data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }

                if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
