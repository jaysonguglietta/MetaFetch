import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var isSidebarVisible = true
    @State private var isHelpPresented = false
    @State private var isUpdatePresented = false
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
            allowedContentTypes: [.mpeg4Movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.importFiles(from: urls)
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

                Button("Help", systemImage: "questionmark.circle") {
                    isHelpPresented = true
                }

                Button("Updates", systemImage: "arrow.down.circle") {
                    presentUpdateCheck()
                }
                .disabled(model.updateState.isBusy)

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

                Button("Save All Tagged", systemImage: "square.and.arrow.down") {
                    Task {
                        await model.saveAllTaggedFiles()
                    }
                }
                .disabled(!model.canSaveAnyTaggedFiles)
            }
        }
        .sheet(isPresented: $isHelpPresented) {
            HelpView(currentMode: model.selectedMode)
        }
        .sheet(isPresented: $isUpdatePresented) {
            UpdateView(model: model)
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
                ForEach(model.files) { entry in
                    SidebarRow(entry: entry)
                        .tag(entry.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onDelete(perform: model.removeFiles)
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

                Button("Save All Tagged + Posters") {
                    Task {
                        await model.saveAllTaggedFiles()
                    }
                }
                .buttonStyle(RetroPrimaryButtonStyle(accent: RetroTheme.lime))
                .disabled(!model.canSaveAnyTaggedFiles || model.isBatchBusy)
            }
        }
        .padding(16)
        .retroPanel(accent: RetroTheme.cyan)
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
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel(accent: mode == .movie ? RetroTheme.gold : RetroTheme.cyan)
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
                title: "\(model.files.count) Loaded",
                accent: RetroTheme.magenta
            )

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
                    ForEach(Array(model.files.enumerated()), id: \.element.id) { index, entry in
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

                Button("Save All + Posters") {
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
                    batchTab("Favourites", isSelected: true)
                    batchTab("Series", isSelected: false)
                    batchTab("Seasons", isSelected: false)
                    batchTab("Data", isSelected: false)
                    batchTab("Cover", isSelected: false)
                }
                .padding(4)
                .background(RetroTheme.paper.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                batchStatus

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

                if model.batchSearchResults.isEmpty && !model.isBatchSearching {
                    VStack(alignment: .leading, spacing: 12) {
                        RetroPill(text: "Drop, Search, Apply", accent: RetroTheme.gold)

                        Text("Search for the show title once. Click a result row to apply that show to all loaded episodes, then review the episode list on the left.")
                            .font(RetroTheme.bodyFont(16))
                            .foregroundStyle(RetroTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
                    .retroPanel(accent: RetroTheme.paper.opacity(0.18))
                } else {
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

                Text("Clicking a result applies it to all loaded episodes.")
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

    private func batchTab(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(RetroTheme.bodyFont(13))
            .foregroundStyle(isSelected ? RetroTheme.ink : RetroTheme.paper.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? RetroTheme.paper : Color.clear)
            )
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

            if let sourceURL = result.sourceURL {
                Link(destination: sourceURL) {
                    Label("Open Source", systemImage: "safari")
                        .font(RetroTheme.labelFont(11))
                        .tracking(1.8)
                        .foregroundStyle(RetroTheme.cyan)
                }
                .buttonStyle(.plain)
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

private struct SelectionPreviewCard: View {
    @ObservedObject var entry: MovieFileEntry
    let saveAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RetroSectionTitle(
                eyebrow: "Preview Deck",
                title: "Selected Match",
                accent: RetroTheme.lime
            )

            if let match = entry.selectedResult {
                ArtworkView(url: match.artworkURL, width: 300, height: 440, accent: RetroTheme.lime)

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

                    Text(match.synopsis)
                        .font(RetroTheme.bodyFont(15))
                        .foregroundStyle(RetroTheme.muted)
                        .lineLimit(10)
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
                    MetadataLine(label: "Artwork", value: match.artworkURL == nil ? "None" : "Included")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(match.hasArtwork ? "Poster Artwork Included" : "No Poster Artwork Available")
                        .font(RetroTheme.labelFont(13))
                        .foregroundStyle(RetroTheme.paper)

                    Text(entry.saveModeSummary)
                        .font(RetroTheme.bodyFont(12))
                        .foregroundStyle(RetroTheme.muted)
                }

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

                if entry.isSaving {
                    VStack(alignment: .leading, spacing: 10) {
                        if let saveProgress = entry.normalizedSaveProgress {
                            ProgressView(value: saveProgress)
                                .progressViewStyle(.linear)
                                .tint(RetroTheme.lime)

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
                            "Drop one or more MP4 files or use Add MP4 Files.",
                            "Review the suggested search query and search again if needed.",
                            "Pick the best result card, then save metadata back to the MP4.",
                        ]
                    )

                    HelpSection(
                        title: "Best Search Results",
                        accent: RetroTheme.lime,
                        rows: [
                            "Movie filenames work best when they include a clean title and year, like The.Matrix.1999.mp4.",
                            "TV filenames work best with season and episode codes, like Severance.S02E04.mp4 or Severance.2x04.mp4.",
                            "If a filename is messy, edit the search box directly and search again.",
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
                            "Batch saves keep poster artwork on when the selected source provides it.",
                            "Saving with poster artwork may rebuild the MP4 container, but video/audio are not re-encoded.",
                            "The progress bar tracks the current save path and shows when MetaFetch falls back.",
                        ]
                    )

                    HelpSection(
                        title: "Updates",
                        accent: RetroTheme.cyan,
                        rows: [
                            "Use Updates in the toolbar or Check for Updates from the app menu to look for newer GitHub releases.",
                            "MetaFetch compares the installed app version with the latest GitHub release tag.",
                            "When a release has a DMG, ZIP, or PKG asset, MetaFetch can download it to Downloads and open it.",
                            "Installer replacement still stays visible and user-confirmed, which is safer than silently replacing a running app.",
                        ]
                    )

                    HelpSection(
                        title: "Troubleshooting",
                        accent: RetroTheme.magenta,
                        rows: [
                            "No matches usually means the query is too noisy. Try a shorter title or add the release year.",
                            "Series Only in TV mode means MetaFetch found the show but still needs a specific episode code.",
                            "For multi-episode tagging, search the show once in the batch workspace, click the right show card, review the badges, then Save All Tagged + Posters.",
                            "If saving is slow, turn off poster artwork so MetaFetch can try the metadata-only fast path.",
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
                            "An optional safety mode could create recovery backups for users who prefer protection over fastest saves.",
                            "A manual metadata editor would let you tweak title, synopsis, genre, and artwork before saving.",
                            "A batch save report could show which files used header-only saves versus container rebuilds.",
                            "A headroom inspector could explain why a file will or will not save quickly before you click Save.",
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
                        Button(update.asset == nil ? "Open Release Page" : "Download And Open") {
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
                        Button("Open Download") {
                            model.openDownloadedUpdate(at: fileURL)
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
                        : "MetaFetch can download \(update.asset?.name ?? "the installer") to your Downloads folder and open it."
                )

                releaseNotes(for: update)
            }
        case .downloading(let update):
            VStack(alignment: .leading, spacing: 16) {
                updateMessage(
                    eyebrow: "Downloading",
                    title: "Fetching Version \(update.version)",
                    message: "The update is downloading from GitHub. MetaFetch will open it when the download finishes."
                )

                ProgressView()
                    .progressViewStyle(.linear)
            }
        case .downloaded(let update, let fileURL):
            VStack(alignment: .leading, spacing: 14) {
                updateMessage(
                    eyebrow: "Downloaded",
                    title: "Version \(update.version) Is In Downloads",
                    message: "The installer was downloaded and opened. If macOS did not bring it forward, open it again from: \(fileURL.path)"
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
