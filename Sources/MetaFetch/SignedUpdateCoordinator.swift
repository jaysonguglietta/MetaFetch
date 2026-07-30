import Foundation
import Sparkle

@MainActor
final class SignedUpdateCoordinator {
    static let shared = SignedUpdateCoordinator()

    private var controller: SPUStandardUpdaterController?

    private init() {}

    var isConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            return false
        }
        return true
    }

    var configurationSummary: String {
        isConfigured
            ? "Sparkle 2 is configured for EdDSA-signed appcasts and pre-extraction verification."
            : "Sparkle is linked but inactive until SPARKLE_FEED_URL and SPARKLE_PUBLIC_KEY are supplied to the release build. GitHub checksum and code-signature verification remains active."
    }

    @discardableResult
    func checkForUpdates() -> Bool {
        guard isConfigured else { return false }
        if controller == nil {
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
        controller?.checkForUpdates(nil)
        return true
    }
}
