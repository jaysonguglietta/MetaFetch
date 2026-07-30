import Foundation

@MainActor
final class SecurityScopedAccessManager {
    static let shared = SecurityScopedAccessManager()
    private static let watchFolderBookmarkKey = "MetaFetchWatchFolderBookmark"
    private var activeURLs: [URL] = []
    private var activeWatchFolderURL: URL?

    private init() {}

    func retainAccess(to url: URL) {
        let standardized = url.standardizedFileURL
        guard !activeURLs.contains(standardized) else { return }
        if standardized.startAccessingSecurityScopedResource() {
            activeURLs.append(standardized)
        }
    }

    func storeWatchFolder(_ url: URL) throws {
        releaseWatchFolderAccess()
        retainAccess(to: url)
        activeWatchFolderURL = url.standardizedFileURL
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: Self.watchFolderBookmarkKey)
    }

    func restoreWatchFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.watchFolderBookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        retainAccess(to: url)
        activeWatchFolderURL = url.standardizedFileURL
        if isStale { try? storeWatchFolder(url) }
        return url.standardizedFileURL
    }

    func clearWatchFolder() {
        UserDefaults.standard.removeObject(forKey: Self.watchFolderBookmarkKey)
        releaseWatchFolderAccess()
    }

    private func releaseWatchFolderAccess() {
        guard let activeWatchFolderURL else { return }
        activeWatchFolderURL.stopAccessingSecurityScopedResource()
        activeURLs.removeAll { $0 == activeWatchFolderURL }
        self.activeWatchFolderURL = nil
    }

    deinit {
        for url in activeURLs { url.stopAccessingSecurityScopedResource() }
    }
}
