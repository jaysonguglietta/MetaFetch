import AppKit
import SwiftUI

private final class MetaFetchAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }
}

@main
struct MetaFetchApp: App {
    @NSApplicationDelegateAdaptor(MetaFetchAppDelegate.self) private var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        PersistedLayoutSanitizer.sanitizeIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 720)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    NotificationCenter.default.post(name: .checkForMetaFetchUpdates, object: nil)
                }
            }

            CommandGroup(replacing: .help) {
                Button("MetaFetch Help") {
                    NotificationCenter.default.post(name: .showMetaFetchHelp, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }
    }
}

private enum PersistedLayoutSanitizer {
    static func sanitizeIfNeeded() {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return
        }

        let defaults = UserDefaults.standard
        guard let domain = defaults.persistentDomain(forName: bundleID) else {
            return
        }

        let splitViewKeys = domain.keys.filter { $0.hasPrefix("NSSplitView Subview Frames") }
        guard !splitViewKeys.isEmpty else {
            return
        }

        var removedInvalidSplitFrames = false

        for key in splitViewKeys {
            guard let frames = domain[key] as? [String],
                  let firstFrame = frames.first,
                  let sidebarWidth = widthComponent(from: firstFrame),
                  sidebarWidth <= 1 else {
                continue
            }

            defaults.removeObject(forKey: key)
            removedInvalidSplitFrames = true
        }

        guard removedInvalidSplitFrames else {
            return
        }

        let windowFrameKeys = domain.keys.filter { $0.hasPrefix("NSWindow Frame ") }
        for key in windowFrameKeys {
            defaults.removeObject(forKey: key)
        }
    }

    private static func widthComponent(from splitFrame: String) -> Double? {
        let components = splitFrame
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard components.count >= 3 else {
            return nil
        }

        return Double(components[2])
    }
}
