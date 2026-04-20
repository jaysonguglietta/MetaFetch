import AppKit
import SwiftUI

@main
struct MetaFetchApp: App {
    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 720)
        }
    }
}
