import AppKit
import SwiftUI

struct ArtworkView: View {
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
