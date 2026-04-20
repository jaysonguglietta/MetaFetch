import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var isSidebarVisible = true

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

                Button("Add MP4 Files", systemImage: "plus") {
                    model.isFileImporterPresented = true
                }

                Button("Save All Tagged", systemImage: "square.and.arrow.down") {
                    Task {
                        await model.saveAllTaggedFiles()
                    }
                }
                .disabled(!model.canSaveAnyTaggedFiles)
            }
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                MetaFetchSidebarBrand()

                Text("Video Store\nMetadata Deck")
                    .font(RetroTheme.heroFont(30))
                    .foregroundStyle(RetroTheme.paper)

                Text("Drag in tapes, tune the title, pick the right movie card, and stamp the file with fresh metadata.")
                    .font(RetroTheme.bodyFont(14))
                    .foregroundStyle(RetroTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    SidebarStat(label: "Loaded", value: "\(model.files.count)", accent: RetroTheme.magenta)
                    SidebarStat(label: "Ready", value: "\(model.files.filter { $0.selectedResult != nil }.count)", accent: RetroTheme.lime)
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
                    RetroPill(text: "No Tapes Loaded", accent: RetroTheme.gold)

                    Text("Drop one or more MP4 files in the main deck to start matching movies.")
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

        return "film"
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
}

private struct DetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let selectedFile = model.selectedFile {
            FileWorkspaceView(model: model, entry: selectedFile)
        } else {
            EmptyStateView(model: model)
        }
    }
}

private struct EmptyStateView: View {
    @ObservedObject var model: AppModel

    var body: some View {
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

                    Text("Stamp Your MP4s Like It’s 1999")
                        .font(RetroTheme.heroFont(42))
                        .foregroundStyle(RetroTheme.paper)
                        .multilineTextAlignment(.center)

                    Text("Drag in movie files, search the title, browse bright matching cards, and write the chosen metadata back into the file with a VHS-era glow.")
                        .font(RetroTheme.bodyFont(19))
                        .foregroundStyle(RetroTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 720)
                }

                DropZoneCard(
                    compact: false,
                    openPanel: { model.isFileImporterPresented = true },
                    receiveFiles: { model.importFiles(from: $0) }
                )
                .frame(maxWidth: 860)

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
                        copy: "Browse likely film pages and lock the one that best matches the movie in hand.",
                        accent: RetroTheme.magenta
                    )

                    FeatureCard(
                        title: "Write It Back",
                        copy: "Save title, synopsis, year, artwork, and more directly into the MP4 container.",
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

                    Text("We clean up the filename first, but you can dial in the title manually before pulling fresh matches.")
                        .font(RetroTheme.bodyFont(15))
                        .foregroundStyle(RetroTheme.muted)

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

            RetroPill(text: "Now Loading", accent: RetroTheme.cyan)

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

            TextField("Movie title", text: $entry.queryText)
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

                    Text("Search results will land here after the title lookup finishes.")
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

                Text("Searching movie matches...")
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
    var compact: Bool
    let openPanel: () -> Void
    let receiveFiles: ([URL]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            RetroPill(text: compact ? "Drop More Files" : "Drag MP4 Movies Here", accent: RetroTheme.gold)

            Text(compact ? "Load another tape into the deck." : "Feed the metadata machine with a fresh batch of movie files.")
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
    let result: MovieSearchResult
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
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
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .retroPanel(accent: isSelected ? RetroTheme.lime : RetroTheme.paper.opacity(0.14))
        }
        .buttonStyle(.plain)
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
                    MatchConfidenceBadge(confidence: match.matchConfidence)
                    InfoBadge(text: match.sourceName, accent: RetroTheme.paper.opacity(0.18), foreground: RetroTheme.paper)
                }

                Text(match.matchSummary)
                    .font(RetroTheme.bodyFont(14))
                    .foregroundStyle(match.matchConfidence.accent)

                Divider()
                    .overlay(RetroTheme.paper.opacity(0.16))

                VStack(alignment: .leading, spacing: 9) {
                    MetadataLine(label: "Match", value: match.matchSummary)
                    MetadataLine(label: "Source", value: match.sourceName)
                    MetadataLine(label: "Title", value: match.trackName)
                    MetadataLine(label: "Genre", value: match.primaryGenreName ?? "Not provided")
                    MetadataLine(label: "Year", value: match.releaseYear ?? "Not provided")
                    MetadataLine(label: "Creator", value: match.artistName ?? "Not provided")
                    MetadataLine(label: "Artwork", value: match.artworkURL == nil ? "None" : "Included")
                }

                if match.hasArtwork {
                    Toggle(isOn: $entry.includeArtworkWhenSaving) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include Poster Artwork")
                                .font(RetroTheme.labelFont(13))
                                .foregroundStyle(RetroTheme.paper)

                            Text(entry.saveModeSummary)
                                .font(RetroTheme.bodyFont(12))
                                .foregroundStyle(RetroTheme.muted)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(RetroTheme.lime)
                } else {
                    Text(entry.saveModeSummary)
                        .font(RetroTheme.bodyFont(12))
                        .foregroundStyle(RetroTheme.muted)
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
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(RetroTheme.lime)

                        Text(entry.statusMessage)
                            .font(RetroTheme.bodyFont(13))
                            .foregroundStyle(RetroTheme.paper)
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

                    Text("Choose one of the movie cards on the left to preview the metadata that will get written into the MP4.")
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

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                placeholder
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.85), lineWidth: 2)
        )
        .shadow(color: accent.opacity(0.20), radius: 14, x: 0, y: 12)
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
