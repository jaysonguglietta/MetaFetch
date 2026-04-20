import SwiftUI

enum RetroTheme {
    static let night = Color(red: 0.05, green: 0.07, blue: 0.16)
    static let panel = Color(red: 0.10, green: 0.12, blue: 0.24)
    static let panelRaised = Color(red: 0.16, green: 0.12, blue: 0.30)
    static let cyan = Color(red: 0.22, green: 0.94, blue: 0.97)
    static let magenta = Color(red: 0.98, green: 0.28, blue: 0.71)
    static let lime = Color(red: 0.84, green: 0.97, blue: 0.27)
    static let gold = Color(red: 1.00, green: 0.77, blue: 0.26)
    static let peach = Color(red: 1.00, green: 0.54, blue: 0.41)
    static let paper = Color(red: 0.98, green: 0.94, blue: 0.86)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.12)
    static let muted = Color(red: 0.66, green: 0.71, blue: 0.83)

    static func heroFont(_ size: CGFloat) -> Font {
        .custom("AmericanTypewriter-Bold", size: size)
    }

    static func labelFont(_ size: CGFloat) -> Font {
        .custom("AvenirNextCondensed-DemiBold", size: size)
    }

    static func bodyFont(_ size: CGFloat) -> Font {
        .custom("Helvetica Neue", size: size)
    }
}

struct RetroBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    RetroTheme.night,
                    Color(red: 0.14, green: 0.07, blue: 0.24),
                    Color(red: 0.07, green: 0.17, blue: 0.26),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    RetroTheme.magenta.opacity(0.26),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    RetroTheme.cyan.opacity(0.20),
                    .clear,
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 380
            )

            GeometryReader { geometry in
                Canvas { context, size in
                    var grid = Path()

                    stride(from: CGFloat.zero, through: size.width, by: 44).forEach { x in
                        grid.move(to: CGPoint(x: x, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: size.height))
                    }

                    stride(from: CGFloat.zero, through: size.height, by: 44).forEach { y in
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                    }

                    context.stroke(
                        grid,
                        with: .color(RetroTheme.paper.opacity(0.05)),
                        lineWidth: 0.7
                    )

                    var scanlines = Path()
                    stride(from: CGFloat.zero, through: size.height, by: 6).forEach { y in
                        scanlines.move(to: CGPoint(x: 0, y: y))
                        scanlines.addLine(to: CGPoint(x: size.width, y: y))
                    }

                    context.stroke(
                        scanlines,
                        with: .color(.black.opacity(0.10)),
                        lineWidth: 1
                    )

                    let tapeDeck = CGRect(
                        x: size.width * 0.68,
                        y: 44,
                        width: min(size.width * 0.24, 320),
                        height: 160
                    )
                    context.fill(
                        Path(roundedRect: tapeDeck, cornerRadius: 28),
                        with: .linearGradient(
                            Gradient(colors: [RetroTheme.magenta.opacity(0.35), RetroTheme.gold.opacity(0.28)]),
                            startPoint: CGPoint(x: tapeDeck.minX, y: tapeDeck.minY),
                            endPoint: CGPoint(x: tapeDeck.maxX, y: tapeDeck.maxY)
                        )
                    )

                    let sticker = CGRect(
                        x: 34,
                        y: size.height - 150,
                        width: min(size.width * 0.28, 340),
                        height: 110
                    )
                    context.fill(
                        Path(roundedRect: sticker, cornerRadius: 30),
                        with: .linearGradient(
                            Gradient(colors: [RetroTheme.cyan.opacity(0.24), RetroTheme.lime.opacity(0.18)]),
                            startPoint: CGPoint(x: sticker.minX, y: sticker.minY),
                            endPoint: CGPoint(x: sticker.maxX, y: sticker.maxY)
                        )
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .ignoresSafeArea()
    }
}

struct RetroPanelModifier: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [RetroTheme.panel, RetroTheme.panelRaised],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accent.opacity(0.95), RetroTheme.paper.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )

                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .inset(by: 7)
                        .strokeBorder(RetroTheme.paper.opacity(0.08), lineWidth: 1)
                }
            )
            .shadow(color: accent.opacity(0.18), radius: 18, x: 0, y: 12)
            .shadow(color: .black.opacity(0.30), radius: 24, x: 0, y: 20)
    }
}

extension View {
    func retroPanel(accent: Color = RetroTheme.cyan) -> some View {
        modifier(RetroPanelModifier(accent: accent))
    }
}

struct RetroPill: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text.uppercased())
            .font(RetroTheme.labelFont(13))
            .tracking(2.4)
            .foregroundStyle(RetroTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent, RetroTheme.gold],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
    }
}

struct RetroSectionTitle: View {
    let eyebrow: String
    let title: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased())
                .font(RetroTheme.labelFont(12))
                .tracking(2.8)
                .foregroundStyle(accent)

            Text(title)
                .font(RetroTheme.heroFont(26))
                .foregroundStyle(RetroTheme.paper)
        }
    }
}

struct RetroPrimaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RetroTheme.labelFont(16))
            .tracking(1.2)
            .foregroundStyle(RetroTheme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent, RetroTheme.gold],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(RetroTheme.paper.opacity(0.45), lineWidth: 1.2)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .shadow(color: accent.opacity(0.18), radius: 8, x: 0, y: 6)
    }
}
