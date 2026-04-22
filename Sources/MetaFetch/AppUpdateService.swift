import Foundation

struct AppUpdate: Identifiable {
    struct Asset {
        let name: String
        let downloadURL: URL
        let size: Int
        let contentType: String?
    }

    let id: String
    let version: String
    let tagName: String
    let name: String
    let releaseNotes: String
    let releaseURL: URL
    let publishedAt: Date?
    let asset: Asset?
}

enum AppUpdateCheckResult {
    case upToDate(version: String)
    case available(AppUpdate)
}

enum AppUpdateState {
    case idle
    case checking
    case upToDate(version: String)
    case available(AppUpdate)
    case downloading(AppUpdate)
    case downloaded(AppUpdate, fileURL: URL)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading:
            return true
        case .idle, .upToDate, .available, .downloaded, .failed:
            return false
        }
    }
}

protocol AppUpdateChecking: Sendable {
    func checkForUpdate(currentVersion: String) async throws -> AppUpdateCheckResult
    func download(update: AppUpdate) async throws -> URL
}

struct GitHubReleaseUpdateService: AppUpdateChecking {
    enum UpdateError: LocalizedError {
        case invalidReleaseURL
        case invalidDownloadURL
        case serverResponse(Int)
        case responseTooLarge
        case noInstallableAsset
        case assetTooLarge(Int)
        case downloadsFolderUnavailable
        case moveFailed

        var errorDescription: String? {
            switch self {
            case .invalidReleaseURL:
                return "MetaFetch could not build the GitHub release URL."
            case .invalidDownloadURL:
                return "The GitHub release asset URL was not trusted."
            case .serverResponse(let statusCode):
                return "GitHub returned HTTP \(statusCode) while checking for updates."
            case .responseTooLarge:
                return "The GitHub update response was larger than expected."
            case .noInstallableAsset:
                return "The latest GitHub release does not include a .dmg, .zip, or .pkg asset to install."
            case .assetTooLarge(let size):
                return "The update download is larger than MetaFetch allows right now (\(size) bytes)."
            case .downloadsFolderUnavailable:
                return "MetaFetch could not find your Downloads folder."
            case .moveFailed:
                return "MetaFetch downloaded the update but could not move it to Downloads."
            }
        }
    }

    private let owner = "jaysonguglietta"
    private let repository = "MetaFetch"
    private let maximumReleaseResponseBytes = 1_000_000
    private let maximumDownloadBytes = 350_000_000

    func checkForUpdate(currentVersion: String) async throws -> AppUpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest") else {
            throw UpdateError.invalidReleaseURL
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("MetaFetch", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)

        guard data.count <= maximumReleaseResponseBytes else {
            throw UpdateError.responseTooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: data)
        let latestVersion = Self.normalizedVersion(release.tagName)

        guard Self.isRemoteVersion(latestVersion, newerThan: currentVersion) else {
            return .upToDate(version: latestVersion)
        }

        let update = AppUpdate(
            id: release.tagName,
            version: latestVersion,
            tagName: release.tagName,
            name: release.name?.nilIfBlank ?? release.tagName,
            releaseNotes: release.body?.nilIfBlank ?? "No release notes were provided.",
            releaseURL: release.htmlURL,
            publishedAt: release.publishedAt,
            asset: preferredAsset(from: release.assets)
        )

        return .available(update)
    }

    func download(update: AppUpdate) async throws -> URL {
        guard let asset = update.asset else {
            throw UpdateError.noInstallableAsset
        }

        guard asset.downloadURL.scheme == "https",
              let host = asset.downloadURL.host?.lowercased(),
              host == "github.com" || host.hasSuffix(".github.com") else {
            throw UpdateError.invalidDownloadURL
        }

        guard asset.size <= maximumDownloadBytes else {
            throw UpdateError.assetTooLarge(asset.size)
        }

        var request = URLRequest(url: asset.downloadURL, timeoutInterval: 120)
        request.setValue("MetaFetch", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        try validate(response: response)

        let downloadsURL = try downloadsFolder()
        let destinationURL = uniqueDestinationURL(
            directory: downloadsURL,
            fileName: "MetaFetch-\(update.version)-\(asset.name)"
        )

        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            throw UpdateError.moveFailed
        }

        return destinationURL
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.serverResponse(httpResponse.statusCode)
        }
    }

    private func preferredAsset(from assets: [GitHubRelease.Asset]) -> AppUpdate.Asset? {
        let installableAssets = assets.compactMap { asset -> AppUpdate.Asset? in
            guard let downloadURL = asset.browserDownloadURL,
                  let fileExtension = asset.name.split(separator: ".").last?.lowercased(),
                  ["dmg", "zip", "pkg"].contains(String(fileExtension)) else {
                return nil
            }

            return AppUpdate.Asset(
                name: asset.name,
                downloadURL: downloadURL,
                size: asset.size,
                contentType: asset.contentType
            )
        }

        let priority = ["dmg", "zip", "pkg"]
        return installableAssets.sorted { lhs, rhs in
            let lhsPriority = priority.firstIndex(of: lhs.name.pathExtensionLowercased) ?? priority.count
            let rhsPriority = priority.firstIndex(of: rhs.name.pathExtensionLowercased) ?? priority.count
            return lhsPriority < rhsPriority
        }
        .first
    }

    private func downloadsFolder() throws -> URL {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw UpdateError.downloadsFolderUnavailable
        }

        return downloadsURL
    }

    private func uniqueDestinationURL(directory: URL, fileName: String) -> URL {
        let baseURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let pathExtension = baseURL.pathExtension
        let baseName = baseURL.deletingPathExtension().lastPathComponent

        for index in 1...100 {
            let candidate = directory
                .appendingPathComponent("\(baseName) (\(index))")
                .appendingPathExtension(pathExtension)

            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory
            .appendingPathComponent("\(baseName)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    private static func normalizedVersion(_ version: String) -> String {
        version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
            .trimmingPrefix("V")
    }

    private static func isRemoteVersion(_ remoteVersion: String, newerThan currentVersion: String) -> Bool {
        let normalizedCurrentVersion = normalizedVersion(currentVersion)

        if let remote = SemanticVersion(remoteVersion),
           let current = SemanticVersion(normalizedCurrentVersion) {
            return remote > current
        }

        return remoteVersion.caseInsensitiveCompare(normalizedCurrentVersion) != .orderedSame
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL?
        let size: Int
        let contentType: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
            case contentType = "content_type"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

private struct SemanticVersion: Comparable {
    let components: [Int]

    init?(_ rawValue: String) {
        let parsedComponents = rawValue
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { component -> Int? in
                let numericPrefix = component.prefix { $0.isNumber }
                return Int(numericPrefix)
            }

        guard parsedComponents.allSatisfy({ $0 != nil }) else {
            return nil
        }

        components = parsedComponents.compactMap { $0 }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)

        for index in 0..<maxCount {
            let lhsComponent = index < lhs.components.count ? lhs.components[index] : 0
            let rhsComponent = index < rhs.components.count ? rhs.components[index] : 0

            if lhsComponent != rhsComponent {
                return lhsComponent < rhsComponent
            }
        }

        return false
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    var pathExtensionLowercased: String {
        URL(fileURLWithPath: self).pathExtension.lowercased()
    }

    func trimmingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }

        return String(dropFirst(prefix.count))
    }
}
