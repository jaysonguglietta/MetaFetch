import Foundation

enum AppBuildInfo {
    static let fallbackVersion = "2.02"

    static var version: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? fallbackVersion
    }

    static var shortUserAgent: String {
        "MetaFetch/\(version)"
    }

    static var descriptiveUserAgent: String {
        "\(shortUserAgent) (macOS app for tagging MP4 movie files and TV episodes)"
    }
}
