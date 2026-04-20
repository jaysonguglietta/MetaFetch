import SwiftUI

struct MetaFetchLogoMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.07, green: 0.11, blue: 0.22), Color(red: 0.10, green: 0.16, blue: 0.30)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(RetroTheme.paper.opacity(0.18), lineWidth: size * 0.025)

            RoundedRectangle(cornerRadius: size * 0.11, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(width: size * 0.28, height: size * 0.30)
                .offset(x: size * 0.22, y: size * 0.06)

            folderOutline
                .frame(width: size * 0.72, height: size * 0.54)
                .offset(y: size * 0.06)

            ZStack {
                Circle()
                    .fill(RetroTheme.cyan)
                    .frame(width: size * 0.42, height: size * 0.42)

                Circle()
                    .strokeBorder(RetroTheme.paper, lineWidth: size * 0.07)
                    .frame(width: size * 0.42, height: size * 0.42)

                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: size * 0.07, height: size * 0.07)
                    .offset(x: -size * 0.08, y: -size * 0.08)

                RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                    .fill(RetroTheme.paper)
                    .frame(width: size * 0.24, height: size * 0.07)
                    .rotationEffect(.degrees(-42))
                    .offset(x: -size * 0.19, y: size * 0.18)
            }
            .offset(y: size * 0.03)

            Circle()
                .fill(RetroTheme.peach)
                .frame(width: size * 0.10, height: size * 0.10)
                .overlay(
                    Circle()
                        .strokeBorder(RetroTheme.paper.opacity(0.4), lineWidth: size * 0.015)
                )
                .offset(x: size * 0.26, y: -size * 0.24)
        }
        .frame(width: size, height: size)
        .shadow(color: RetroTheme.cyan.opacity(0.18), radius: size * 0.18, x: 0, y: size * 0.12)
    }

    private var folderOutline: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                .strokeBorder(RetroTheme.paper, lineWidth: size * 0.05)
                .frame(width: size * 0.72, height: size * 0.40)
                .offset(y: size * 0.09)

            RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.94), Color.white.opacity(0.76)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.20, height: size * 0.09)
                .offset(x: size * 0.06, y: size * 0.02)

            Rectangle()
                .fill(Color.white.opacity(0.95))
                .frame(width: size * 0.60, height: size * 0.05)
                .offset(x: size * 0.02, y: size * 0.20)
        }
    }
}

struct MetaFetchWordmark: View {
    let size: CGFloat
    var subtitle: String? = "metadata search + tagging"

    var body: some View {
        VStack(alignment: .leading, spacing: max(4, size * 0.09)) {
            VStack(alignment: .leading, spacing: max(3, size * 0.06)) {
                Text("MetaFetch")
                    .font(.custom("Futura-CondensedExtraBold", size: size))
                    .tracking(size * 0.015)
                    .lineLimit(1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [RetroTheme.paper, Color.white, RetroTheme.cyan.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: RetroTheme.cyan.opacity(0.22), radius: size * 0.12, x: 0, y: size * 0.08)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [RetroTheme.cyan, RetroTheme.gold],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size * 0.92, height: max(3, size * 0.065))
            }

            if let subtitle {
                Text(subtitle.uppercased())
                    .font(.custom("AvenirNextCondensed-DemiBold", size: size * 0.32))
                    .tracking(size * 0.09)
                    .foregroundStyle(RetroTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetaFetchLogoLockup: View {
    var markSize: CGFloat = 68
    var wordmarkSize: CGFloat = 30
    var subtitle: String? = "metadata search + tagging"

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            MetaFetchLogoMark(size: markSize)
            MetaFetchWordmark(size: wordmarkSize, subtitle: subtitle)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetaFetchSidebarBrand: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetaFetchLogoLockup(
                markSize: 44,
                wordmarkSize: 24,
                subtitle: nil
            )

            RetroPill(text: "Metadata Deck", accent: RetroTheme.cyan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
