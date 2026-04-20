import SwiftUI

struct MetaFetchLogoMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.07, green: 0.09, blue: 0.18), Color(red: 0.15, green: 0.10, blue: 0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(RetroTheme.paper.opacity(0.18), lineWidth: size * 0.025)

            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .inset(by: size * 0.12)
                .strokeBorder(RetroTheme.cyan.opacity(0.92), lineWidth: size * 0.06)

            HStack(spacing: size * 0.08) {
                VStack(alignment: .leading, spacing: size * 0.08) {
                    Capsule(style: .continuous)
                        .fill(RetroTheme.cyan)
                        .frame(width: size * 0.16, height: size * 0.07)

                    Capsule(style: .continuous)
                        .fill(RetroTheme.magenta)
                        .frame(width: size * 0.22, height: size * 0.07)

                    Capsule(style: .continuous)
                        .fill(RetroTheme.gold)
                        .frame(width: size * 0.12, height: size * 0.07)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                        .fill(RetroTheme.gold)
                        .frame(width: size * 0.16, height: size * 0.40)

                    Image(systemName: "arrow.down.right")
                        .font(.system(size: size * 0.22, weight: .black))
                        .foregroundStyle(RetroTheme.ink)
                }
            }
            .offset(y: size * 0.02)
        }
        .frame(width: size, height: size)
        .shadow(color: RetroTheme.cyan.opacity(0.18), radius: size * 0.18, x: 0, y: size * 0.12)
    }
}

struct MetaFetchLogoLockup: View {
    var body: some View {
        HStack(spacing: 14) {
            MetaFetchLogoMark(size: 68)

            VStack(alignment: .leading, spacing: 4) {
                Text("MetaFetch")
                    .font(.custom("AvenirNextCondensed-Heavy", size: 32))
                    .foregroundStyle(RetroTheme.paper)

                Text("movie metadata fetch + stamp")
                    .font(.custom("Helvetica Neue", size: 14))
                    .foregroundStyle(RetroTheme.muted)
            }
        }
    }
}
